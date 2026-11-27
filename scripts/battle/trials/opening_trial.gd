extends "res://scripts/battle/main.gd"
## 开场试飞的时钟与编队。飞机、选卡、碰撞和精英继续走主场景路径。
signal volley_interrupted(role: String, at: Vector2, release_tick: int)

const Enemy := preload("res://scripts/battle/enemies/enemy.gd")
const SafeArea := preload("res://scripts/ui/battle_safe_area.gd")
const TrialPalette := preload("res://scripts/visuals/palette.gd")
const OFFER := ["pierce", "splash", "power"]
const DRAFT_TICK := 20 * 60
const FINALE_TICK := 55 * 60
const ELITE_TICK := FINALE_TICK + 155
const END_TICK := 90 * 60
const PRACTICE := {78: .28, 452: .76, 828: .28, 4360: .25, 4860: .76}
const BUILD_STARTS := [1290, 1932, 2604]
const BUILD_SHIFTS := [0.0, .025, -.025]
const FINALE_SHIFT := .045
const COLUMN_X := .28
const CLUSTER_X := .55
const WING_X := .79
const ARMOR_HP := 7
const ARRIVAL_TICKS := 108
const CHARGE_TICKS := 108
const BREAK_TICKS := 13
const FAN_EXIT_OFFSETS := [-.055, 0.0, .055]

@onready var _cues: Node2D = $ChargeCues
@onready var _options: VBoxContainer = $TrialUI/Options
@onready var _result: Label = $TrialUI/Options/Result
var trial_tick := 0
var field := Vector2.ZERO
var finished := false
var interruptions := 0
var _selected := false
var _fighters: Dictionary = {}
var _breaks: Array[Dictionary] = []
var _next_build := 0

func _ready() -> void:
	super._ready()
	UpgradeDraft.clear_drafts()
	UpgradeDraft.card_chosen.connect(_on_choice)
	_asteroid_timer = INF
	# 本场只在固定时间领一张卡；重开普通局时由 reset_game 恢复升级口径。
	GameState.kills_for_next_level = 100
	field = NetworkManager.battle_size(self)
	if is_instance_valid(_player) and not NetworkManager.is_online():
		_player.position = field * Vector2(.5, .78)
		_player.reset_physics_interpolation()
	_cues.draw.connect(_draw_cues)
	var retry: Button = $TrialUI/Options/Buttons/Retry
	retry.pressed.connect(_restart, CONNECT_DEFERRED)
	$TrialUI/Options/Buttons/Back.pressed.connect(_return_to_title, CONNECT_DEFERRED)
	if is_instance_valid(_player) and not _player._motion.mobile_mode:
		retry.text = "重试 · R"
	_hud._level_label.hide()
	_options.minimum_size_changed.connect(_layout_options)
	get_viewport().size_changed.connect(_layout_options)
	get_window().focus_entered.connect(_layout_options)
	_layout_options()
	_update_countdown()

func _exit_tree() -> void:
	UpgradeDraft.clear_drafts()
	if _hitstop_left > 0.0:
		Engine.time_scale = _hitstop_target
	super._exit_tree()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_restart.call_deferred()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _tick_wave_director(_delta: float) -> void:
	pass

func _on_elite_spawn_requested() -> void:
	pass

func _on_boss_spawn_requested(_level: int) -> void:
	pass

func _physics_process(_delta: float) -> void:
	if finished or (trial_tick == DRAFT_TICK and not _selected):
		return
	trial_tick += 1
	if trial_tick == DRAFT_TICK:
		UpgradeDraft.offer_cards(1, OFFER)
	if PRACTICE.has(trial_tick):
		var x: float = PRACTICE[trial_tick]
		_add_fighter("practice-%d" % trial_tick, 1, Vector2(x, .36), 174)
	if _next_build < BUILD_STARTS.size() and trial_tick == BUILD_STARTS[_next_build]:
		_add_build(BUILD_SHIFTS[_next_build])
		_next_build += 1
	if trial_tick == FINALE_TICK:
		_add_build(FINALE_SHIFT, true)
	elif trial_tick == ELITE_TICK:
		_spawn_elite()
	if not _fighters.is_empty() or not _breaks.is_empty():
		_move_fighters()
		while not _breaks.is_empty() and trial_tick >= int(_breaks[0].until):
			_breaks.pop_front()
		_cues.queue_redraw()
	if trial_tick % 60 == 0:
		_update_countdown()
	if trial_tick == END_TICK:
		_finish("完成")

func _on_choice(pid: int, _card: String, _index: int) -> void:
	if pid == 1:
		_selected = true

func _add_build(shift: float, mirrored := false) -> void:
	var column := (1.0 - COLUMN_X if mirrored else COLUMN_X) + shift
	var cluster := (1.0 - CLUSTER_X if mirrored else CLUSTER_X) + shift
	var wing := (1.0 - WING_X if mirrored else WING_X) + shift
	var side := -1.0 if mirrored else 1.0
	_add_fighter("column-front", 0, Vector2(column, .54), 0, 0, -15.0 * side)
	_add_fighter("column-middle", 0, Vector2(column, .405), 0, 0, 19.0 * side)
	_add_fighter("column-rear", 1, Vector2(column, .27), 201)
	_add_fighter("cluster-front", 0, Vector2(cluster, .42))
	_add_fighter("cluster-neighbor", 0, Vector2(cluster, .39), 0, 0, -47.0 * side)
	_add_fighter("cluster-rear", 1, Vector2(cluster, .39), 202, 0, 47.0 * side)
	_add_fighter("wing", 1, Vector2(wing, .38), 193, ARMOR_HP)

func _add_fighter(role: String, kind: int, station: Vector2, fire := 0, health := 0, side := 0.0) -> void:
	# 聚团间距按画布单位收拢，两种画幅都使用实际 78 单位的溅射规则。
	var origin := field * Vector2(station.x, -.07) + Vector2(side * 2.3, 0.0)
	var target := field * station + Vector2(side, 0.0)
	var ship := _spawn_enemy_at(kind, origin, health, false)
	ship.name = "%d-%s" % [trial_tick, role]
	ship.set_physics_process(false)
	ship.rotation = PI
	_fighters[role] = {
		"ship": ship, "spawn": trial_tick, "origin": origin, "target": target,
		"fire": trial_tick + fire if fire > 0 else -1,
	}
	ship.enemy_died.connect(ship.remove_from_group.bind("enemies"), CONNECT_ONE_SHOT)
	if fire > 0:
		ship.enemy_died.connect(_on_emitter_died.bind(role), CONNECT_ONE_SHOT)

func _move_fighters() -> void:
	for role: String in _fighters.keys():
		var order: Dictionary = _fighters[role]
		var ship = order.ship
		if not is_instance_valid(ship):
			_fighters.erase(role)
			continue
		var age := trial_tick - int(order.spawn)
		var retreat := clampf((age - 305.0) / 64.0, 0.0, 1.0)
		if retreat >= 1.0:
			_fighters.erase(role)
			_retire_trial_fighter(ship)
			continue
		var travel := smoothstep(0.0, float(ARRIVAL_TICKS), age)
		ship.position = order.origin.lerp(order.target, travel)
		ship.position.y = lerpf(ship.position.y, -50.0, retreat)
		ship.get_node("HealthBar").value = ship.health
		if trial_tick == int(order.fire) and ship.health > 0:
			_fire_fan(ship)

func _retire_trial_fighter(ship: Node2D) -> void:
	ship.queue_free()

func _fan_direction(at: Vector2, offset: float) -> Vector2:
	return at.direction_to(Vector2(at.x + field.x * offset, field.y))

func _fire_fan(ship: CharacterBody2D, reliable := false) -> void:
	var at := ship.global_position
	for offset: float in FAN_EXIT_OFFSETS:
		var direction := _fan_direction(at, offset)
		ship._spawn_enemy_bullet(at + direction * 20.0, direction.angle(), .3,
			Enemy.SPEED_SLOW, TrialPalette.ENEMY_BULLET_SLOW, reliable)
	SFX.play_enemy_volley()

func _on_emitter_died(role: String) -> void:
	var order: Dictionary = _fighters.get(role, {})
	if finished or order.is_empty() or not _is_charging(order):
		return
	var at: Vector2 = order.ship.global_position
	interruptions += 1
	_breaks.append({"at": _cues.to_local(at), "until": trial_tick + BREAK_TICKS})
	_cues.queue_redraw()
	volley_interrupted.emit(role, at, int(order.fire))

func _is_charging(order: Dictionary) -> bool:
	var remaining := int(order.fire) - trial_tick
	return remaining > 0 and remaining <= CHARGE_TICKS

func _draw_cues() -> void:
	for order: Dictionary in _fighters.values():
		var ship = order.ship
		if not is_instance_valid(ship) or ship.health <= 0 or not _is_charging(order):
			continue
		var progress := 1.0 - float(int(order.fire) - trial_tick) / CHARGE_TICKS
		var center := _cues.to_local(ship.global_position)
		var ink := Color("#ffbd75") if progress < .66 else Color("#ff875c")
		_cues.draw_arc(center, lerpf(38, 30, progress), -PI * .5, -PI * .5 + TAU * lerpf(.25, 1, progress),
			30, ink, 2.5, true)
		_draw_fan_heading(center, ship.global_position, progress)
	for burst in _breaks:
		var life := 1.0 - float(int(burst.until) - trial_tick) / BREAK_TICKS
		for i in 4:
			var angle := i * PI * .5 + life * .22
			_cues.draw_arc(burst.at, lerpf(30, 47, life), angle + .12, angle + lerpf(1.19, .57, life),
				8, Color(1.0, .82, .58, .9 * (1.0 - life)), 2.3, true)

func _draw_fan_heading(center: Vector2, at: Vector2, progress: float) -> void:
	if progress > .66:
		for offset: float in FAN_EXIT_OFFSETS:
			var direction := _fan_direction(at, offset)
			_cues.draw_line(center + direction * 32, center + direction * 60, Color(1.0, .51, .33, .48), 1.5, true)

func _update_countdown() -> void:
	_hud.set_wave_phase("开场试飞 · %d 秒" % ((END_TICK - trial_tick) / 60), Color.LIGHT_CYAN)

func _on_player_died() -> void:
	_finish("被击落")

func _finish(outcome: String) -> void:
	if finished:
		return
	finished = true
	_fighters.clear()
	_breaks.clear()
	_cues.queue_redraw()
	UpgradeDraft.clear_drafts()
	GameState.stop_game()
	_clear_runtime_entities_on_game_over()
	_result.text = "%s · 截断 %d 次" % [outcome, interruptions]
	_result.show()
	_layout_options()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _layout_options() -> void:
	var safe := SafeArea.for_viewport(get_viewport()).grow(-SafeArea.MENU_MARGIN)
	_options.size = _options.get_combined_minimum_size()
	var y := safe.get_center().y + 100.0 if finished else safe.end.y - _options.size.y
	_options.position = Vector2(safe.get_center().x - _options.size.x * .5,
		minf(y, safe.end.y - _options.size.y)).round()

func _return_to_title() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
