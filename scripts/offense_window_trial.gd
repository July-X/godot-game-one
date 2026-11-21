extends "res://scripts/main.gd"
## 两张卡共用这条时间线。每股扇弹只由仍然存活的发射者放出。
signal charge_interrupted(slot: int, fire_tick: int, world_position: Vector2)

const Enemy := preload("res://scripts/enemy.gd")
const TrialPalette := preload("res://scripts/palette.gd")
const SafeArea := preload("res://scripts/battle_safe_area.gd")
const OFFER := ["pierce", "power"]
const COLUMN_X := [.30, .24, .34, .27, .32]
const WAVE_TICKS := 540
const END_TICK := 45 * 60
const ARRIVAL_TICKS := 100
const FIRE_TICKS := [166, 244]
const REVISED_OPENING_FIRES := [188, 244]
const CHARGE_TICKS := 48
const REVISED_CHARGE_TICKS := 92
const BETWEEN_CHARGES := 16
const BREAK_TICKS := 12
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
@onready var _comparison: CheckButton = $TrialUI/Options/Buttons/Legacy
@onready var _cues: Node2D = $ChargeCues
@onready var _break_voice: AudioStreamPlayer2D = $ChargeBreak
@export var use_legacy := false
var trial_tick := -1
var field := Vector2.ZERO
var squad: Array[CharacterBody2D] = []
var _charge_progress := 0.0
var _charged_fire_at := -1
var _breaks: Array[Dictionary] = []
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
	_comparison.set_pressed_no_signal(use_legacy)
	_comparison.toggled.connect(func(enabled: bool): use_legacy = enabled)
	_cues.draw.connect(_draw_revised_cues)
	var sound := SFX._generate_tone(1150.0, .028, .17)
	sound.data += SFX._generate_tone(620.0, .068, .19).data
	_break_voice.stream = sound
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
	_comparison.hide()
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

func _restart() -> void:
	var scene_path := "res://scenes/offense_window_trial_v1.tscn" if use_legacy else "res://scenes/offense_window_trial.tscn"
	get_tree().change_scene_to_file(scene_path)

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
	var fires := _fire_beats(wave)
	for i in ORDERS.size():
		_move_formation_ship(i, beat, axis, fires[0])
	_update_charge(beat, fires)
	if beat in fires:
		_fire_fan(LEFT_EMITTER, axis)
		_fire_fan(RIGHT_EMITTER, axis)
	if not _breaks.is_empty():
		while not _breaks.is_empty() and trial_tick - int(_breaks[0].tick) >= BREAK_TICKS:
			_breaks.pop_front()
		_cues.queue_redraw()
	if trial_tick % 60 == 0:
		_hud.set_wave_phase("进攻窗口 · %d 秒" % ((END_TICK - trial_tick) / 60), Color.LIGHT_CYAN)
	if trial_tick == END_TICK:
		_finish("45 秒试飞完成")

func _fire_beats(wave: int) -> Array:
	return REVISED_OPENING_FIRES if wave == 0 and not use_legacy else FIRE_TICKS

func _charge_start(fires: Array, index: int) -> int:
	var fire: int = fires[index]
	var lead := CHARGE_TICKS if use_legacy else REVISED_CHARGE_TICKS
	return maxi(fire - lead, int(fires[index - 1]) + BETWEEN_CHARGES) if index > 0 else fire - lead

func _update_charge(beat: int, fires: Array) -> void:
	var charge := 0.0
	_charged_fire_at = -1
	for i in fires.size():
		var fire: int = fires[i]
		if beat >= fire:
			continue
		var start := _charge_start(fires, i)
		if beat >= start:
			charge = float(beat - start + 1) / (fire - start)
			_charged_fire_at = trial_tick - beat + fire
		break
	if charge > 0.0 or _charge_progress > 0.0:
		_charge_progress = charge
		if use_legacy:
			queue_redraw()
		else:
			_cues.queue_redraw()

func _move_formation_ship(index: int, beat: int, axis: float, first_fire: int) -> void:
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
		if not use_legacy and index in [LEFT_EMITTER, RIGHT_EMITTER]:
			ship.enemy_died.connect(_on_emitter_died.bind(ship, index), CONNECT_ONE_SHOT)
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
			var side := 1.0 if index == 0 else -1.0
			to.x += side * .052 * smoothstep(first_fire + 12.0, first_fire + 54.0, beat)
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
	if use_legacy:
		_draw_charge(self)

func _draw_charge(canvas: Node2D) -> void:
	if _charge_progress <= 0.0:
		return
	for index in [LEFT_EMITTER, RIGHT_EMITTER]:
		var ship = squad[index]
		if not is_instance_valid(ship) or ship.health <= 0:
			continue
		if use_legacy:
			canvas.draw_arc(ship.position, 29, -PI * 0.5, -PI * 0.5 + TAU * _charge_progress,
				24, TrialPalette.WARN_LINE, 2.0, true)
		else:
			var urgent := _charge_progress >= .62
			var radius := lerpf(37.0, 28.0, _charge_progress)
			var sweep := TAU * lerpf(.24, 1.0, _charge_progress)
			var ink := Color("#ff875c") if urgent else Color("#ffbd75")
			canvas.draw_arc(ship.position, radius, -PI * .5, -PI * .5 + sweep, 32, ink, 2.8 if urgent else 1.8, true)
			if urgent:
				canvas.draw_arc(ship.position, radius + 5, PI * .24, PI * .76, 10, ink, 1.2, true)

func _on_emitter_died(ship: CharacterBody2D, slot: int) -> void:
	if _charged_fire_at <= trial_tick or _finished or not GameState.game_running:
		return
	var at := ship.global_position
	_breaks.append({"at": _cues.to_local(at), "tick": trial_tick})
	_cues.queue_redraw()
	_break_voice.global_position = at
	_break_voice.play()
	charge_interrupted.emit(slot, _charged_fire_at, at)

func _draw_revised_cues() -> void:
	if use_legacy:
		return
	_draw_charge(_cues)
	for burst in _breaks:
		var life := float(trial_tick - int(burst.tick)) / BREAK_TICKS
		var radius := lerpf(28.0, 43.0, life)
		var ink := Color(1.0, .82, .58, .90 * (1.0 - life))
		for i in 4:
			var angle := i * PI * .5 + life * .22
			_cues.draw_arc(burst.at, radius, angle + .12, angle + lerpf(1.21, .60, life), 8, ink, 2.2, true)

func _on_player_died() -> void:
	_finish("试飞结束 · 飞机被击落")

func _finish(message: String) -> void:
	if _finished:
		return
	_finished = true
	_charge_progress = 0.0
	_charged_fire_at = -1
	_breaks.clear()
	_cues.queue_redraw()
	_break_voice.stop()
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
