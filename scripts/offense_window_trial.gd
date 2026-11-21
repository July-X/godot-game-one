extends "res://scripts/main.gd"
## 两张卡共用这条时间线。每股扇弹只由仍然存活的发射者放出。
const Enemy := preload("res://scripts/enemy.gd")
const TrialPalette := preload("res://scripts/palette.gd")
const SafeArea := preload("res://scripts/battle_safe_area.gd")
const OFFER := ["pierce", "power"]
const COLUMN_X := [.30, .24, .34, .27, .32]
const WAVE_TICKS := 540
const END_TICK := 45 * 60
const ARRIVAL_TICKS := 100
const FIRE_TICKS := [166, 244]
const CHARGE_TICKS := 48
const RETREAT_TICK := 300
const LEFT_EMITTER := 2
const RIGHT_EMITTER := 4
const ORDERS := [
	{"at": 12, "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .43)},
	{"at": 34, "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .34)},
	{"at": 56, "kind": 1, "from": Vector2(.30, -.05), "to": Vector2(.30, .25)},
	{"at": 72, "kind": 0, "from": Vector2(.59, -.05), "to": Vector2(.715, .33)},
	{"at": 84, "kind": 1, "from": Vector2(.85, -.05), "to": Vector2(.75, .27)},
]

@onready var _options: VBoxContainer = $TrialUI/Options
@onready var _summary: Label = $TrialUI/Options/Summary
@onready var _retry_button: Button = $TrialUI/Options/Buttons/Retry
var trial_tick := -1
var field := Vector2.ZERO
var squad: Array[CharacterBody2D] = []
var _charge_progress := 0.0
var _finished := false

func _ready() -> void:
	super._ready()
	UpgradeDraft.clear_drafts()
	_asteroid_timer = INF
	GameState.kills_for_next_level = ORDERS.size() * COLUMN_X.size() + 1
	field = get_viewport_rect().size
	squad.resize(ORDERS.size())
	_player.position = field * Vector2(.5, .78)
	_player.reset_physics_interpolation()
	_player.trial_draft_movement_only = true
	_player.set_process_unhandled_input(false)
	_retry_button.pressed.connect(_restart, CONNECT_DEFERRED)
	$TrialUI/Options/Buttons/Back.pressed.connect(_return_to_title, CONNECT_DEFERRED)
	if not _player._motion.mobile_mode:
		_retry_button.text = "重试 · R"
	_options.minimum_size_changed.connect(_layout_options)
	get_viewport().size_changed.connect(_layout_options)
	get_window().focus_entered.connect(_layout_options)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout_options()
	_hud._level_label.hide()
	_hud.set_wave_phase("进攻窗口 · 45 秒", Color.LIGHT_CYAN)
	UpgradeDraft.card_chosen.connect(_on_trial_choice)
	UpgradeDraft.offer_cards(1, OFFER)

func _exit_tree() -> void:
	UpgradeDraft.clear_drafts()
	super._exit_tree()

func _on_trial_choice(pid: int, _card: String, _index: int) -> void:
	if pid != 1 or trial_tick >= 0:
		return
	trial_tick = 0
	_player.trial_draft_movement_only = false
	_player.set_process_unhandled_input(true)
	_retry_button.show()
	_layout_options()
	if not _player._motion.mobile_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and trial_tick >= 0:
		_restart.call_deferred()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _tick_wave_director(_delta: float) -> void:
	pass

func _on_elite_spawn_requested() -> void:
	# 试飞的击杀只影响本局分数。
	pass

func _physics_process(_delta: float) -> void:
	if trial_tick < 0 or _finished:
		return
	trial_tick += 1
	var wave := (trial_tick - 1) / WAVE_TICKS
	var beat := (trial_tick - 1) % WAVE_TICKS + 1
	var axis: float = COLUMN_X[wave]
	for i in ORDERS.size():
		_move_formation_ship(i, beat, axis)
	if beat in FIRE_TICKS:
		_fire_fan(LEFT_EMITTER, axis)
		_fire_fan(RIGHT_EMITTER, axis)
	var charge := 0.0
	for fire: int in FIRE_TICKS:
		if beat >= fire - CHARGE_TICKS and beat < fire:
			charge = float(beat - fire + CHARGE_TICKS + 1) / CHARGE_TICKS
	if charge > 0.0 or _charge_progress > 0.0:
		_charge_progress = charge
		queue_redraw()
	if trial_tick % 60 == 0:
		_hud.set_wave_phase("进攻窗口 · %d 秒" % ((END_TICK - trial_tick) / 60), Color.LIGHT_CYAN)
	if trial_tick == END_TICK:
		_finish("45 秒试飞完成")

func _move_formation_ship(index: int, beat: int, axis: float) -> void:
	var order: Dictionary = ORDERS[index]
	if beat == order.at:
		var entry: Vector2 = order.from
		if index <= LEFT_EMITTER:
			entry.x = axis
		var ship := _spawn_enemy_at(order.kind, field * entry)
		ship.set_physics_process(false)
		ship.rotation = PI
		ship.drop_chance = 0.0
		ship.enemy_died.connect(ship.remove_from_group.bind("enemies"), CONNECT_ONE_SHOT)
		squad[index] = ship
	var ship = squad[index]
	if not is_instance_valid(ship):
		return
	var travel := clampf(float(beat - int(order.at)) / ARRIVAL_TICKS, 0.0, 1.0)
	var from: Vector2 = order.from
	var to: Vector2 = order.to
	if index <= LEFT_EMITTER:
		from.x = axis
		to.x = axis
		if index < LEFT_EMITTER:
			to.x += (.052 if index == 0 else -.052) * smoothstep(FIRE_TICKS[0] + 12.0, FIRE_TICKS[0] + 54.0, beat)
	ship.position = field * from.lerp(to, travel)
	var retreat := clampf(float(beat - RETREAT_TICK) / 52.0, 0.0, 1.0)
	ship.position.y = lerpf(ship.position.y, -40.0, retreat)
	ship.get_node("HealthBar").value = ship.health
	if retreat >= 1.0:
		ship.queue_free()

func _fire_fan(index: int, axis: float) -> void:
	var ship = squad[index]
	if not is_instance_valid(ship) or ship.health <= 0:
		return
	var exits := [.10, axis, .43] if index == LEFT_EMITTER else [.60, .75, .90]
	for end_x: float in exits:
		var direction: Vector2 = ship.global_position.direction_to(field * Vector2(end_x, 1.0))
		ship._spawn_enemy_bullet(ship.global_position + direction * 20, direction.angle(),
			0.3, Enemy.SPEED_SLOW, TrialPalette.ENEMY_BULLET_SLOW)

func _draw() -> void:
	if _charge_progress <= 0.0:
		return
	for index in [LEFT_EMITTER, RIGHT_EMITTER]:
		var ship = squad[index]
		if is_instance_valid(ship) and ship.health > 0:
			draw_arc(ship.position, 29, -PI * 0.5, -PI * 0.5 + TAU * _charge_progress,
				24, TrialPalette.WARN_LINE, 2.0, true)

func _on_player_died() -> void:
	_finish("试飞结束 · 飞机被击落")

func _finish(message: String) -> void:
	if _finished:
		return
	_finished = true
	_charge_progress = 0.0
	queue_redraw()
	GameState.stop_game()
	_clear_runtime_entities_on_game_over()
	_summary.text = message
	_summary.show()
	_retry_button.show()
	_layout_options()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _layout_options() -> void:
	var safe := SafeArea.for_viewport(get_viewport()).grow(-SafeArea.MENU_MARGIN)
	_options.size = _options.get_combined_minimum_size()
	var y := safe.get_center().y + 100.0 if _finished else safe.end.y - _options.size.y
	_options.position = Vector2(safe.get_center().x - _options.size.x * 0.5,
		minf(y, safe.end.y - _options.size.y)).round()

func _return_to_title() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
