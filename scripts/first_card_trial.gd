extends "res://scripts/main.gd"
## 单人首卡试飞。出生和扇弹只读游戏时钟，与选卡、击杀数及随机导演无关。
const Enemy := preload("res://scripts/enemy.gd")
const TrialPalette := preload("res://scripts/palette.gd")
const SafeArea := preload("res://scripts/battle_safe_area.gd")
const FIRST_OFFER := ["pierce", "splash", "graze_focus"]
# 出生和停靠点按视口比例排列。右队先分开进入，再收拢到溅射半径内。
const ORDERS := [
	{"at": 12, "lane": "column", "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .43)},
	{"at": 34, "lane": "column", "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .34)},
	{"at": 56, "lane": "column", "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .25)},
	{"at": 72, "lane": "cluster", "kind": 0, "from": Vector2(.59, -.05), "to": Vector2(.71, .30)},
	{"at": 84, "lane": "cluster", "kind": 1, "from": Vector2(.74, -.05), "to": Vector2(.74, .25)},
	{"at": 96, "lane": "cluster", "kind": 0, "from": Vector2(.89, -.05), "to": Vector2(.77, .30)},
]
const ARRIVAL_TICKS := 100
const RETREAT_TICK := 278
const VOLLEYS := [338, 368, 398]
const END_TICK := 550
const FAN_EXITS := [.59, .73, .87]
const ACTION_HINTS := {
	"pierce": {"text": "去左侧对齐纵队", "start": 1, "end": 180},
	"splash": {"text": "去右侧等敌机靠拢", "start": 1, "end": 180},
	"graze_focus": {"text": "等扇弹，沿弹幕外缘飞", "start": RETREAT_TICK - 90, "end": VOLLEYS[0] + 24},
}

enum TrialVariant { COMMAND_LINE, A, B }

@export var from_draft := false
@export var playtest_variant := TrialVariant.COMMAND_LINE
@onready var _action_hint: Label = $Backdrop/ActionHint
var trial_tick := -1
var next_order := 0
var squad: Array[CharacterBody2D] = []
var field: Vector2
var asteroid_resume := 0.0
var _trial_card := ""
var _show_action_hint := false
var _hint: Dictionary = {}
var _log_enabled := false
var _recording := false
var _first_result_tick := -1
var _hp_last := 0
var _hp_lost := 0
var _graze_before := 0

func _ready() -> void:
	super._ready()
	UpgradeDraft.clear_drafts()
	var args := OS.get_cmdline_user_args()
	var from_menu := playtest_variant != TrialVariant.COMMAND_LINE
	from_draft = from_draft or from_menu or "--from-draft" in args
	_show_action_hint = playtest_variant == TrialVariant.B if from_menu else "--trial-hint" in args
	_log_enabled = from_menu or "--trial-log" in args
	if _show_action_hint:
		get_viewport().size_changed.connect(_layout_action_hint)
		get_window().focus_entered.connect(_layout_action_hint)
	$TrialUI/Options.hide()
	$TrialUI/Options/Power.pressed.connect(_choose_power.bind("tap"))
	$TrialUI/Options/Retry.pressed.connect(func():
		if is_inside_tree():
			_restart(), CONNECT_DEFERRED)
	$TrialUI/Options/Back.pressed.connect(func():
		if is_inside_tree():
			get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn"), CONNECT_DEFERRED)
	$TrialUI/Options.minimum_size_changed.connect(_layout_trial_options)
	get_viewport().size_changed.connect(_layout_trial_options)
	get_window().focus_entered.connect(_layout_trial_options)
	UpgradeDraft.card_chosen.connect(_start_trial)
	if from_draft:
		_player.position = get_viewport_rect().size * Vector2(.50, .78)
		GameState.level_up()

func _exit_tree() -> void:
	_finish_observation("exit")
	super._exit_tree()
	UpgradeDraft.clear_drafts()

func _on_level_up(new_level: int) -> void:
	if new_level != 2 or trial_tick >= 0:
		super._on_level_up(new_level)
		return
	asteroid_resume = _asteroid_timer
	_asteroid_timer = INF
	# 旧弹和残敌退出本次换波，保留分数、掉落和玩家当前位置。
	for group in ["enemies", "asteroids", "enemy_bullets", "player_bullets"]:
		for unit in get_tree().get_nodes_in_group(group):
			unit.queue_free()
	_player.trial_draft_movement_only = true
	_player.set_process_unhandled_input(false)
	_player.on_level_up()
	$TrialUI/Options.show()
	_layout_trial_options()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.set_draft_prompt("首卡试飞 · 选定后进场 · 超时取第一张")
	UpgradeDraft.offer_cards(1, FIRST_OFFER)

func _choose_power(source: String) -> void:
	if GameState.level == 2 and trial_tick < 0 and UpgradeDraft.has_draft(1):
		UpgradeDraft.offer_cards(1, ["power"])
		UpgradeDraft.choose_card(1, 0, source)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_4, KEY_KP_4]:
		_choose_power("key")
	else:
		super._input(event)

func _start_trial(pid: int, card: String, _index: int) -> void:
	if trial_tick >= 0:
		return
	trial_tick = 0
	_trial_card = card
	field = get_viewport_rect().size
	if _show_action_hint:
		_hint = ACTION_HINTS.get(card, {})
	if _log_enabled:
		_recording = true
		_hp_last = GameState.get_current_health(pid)
		_graze_before = GameState._graze_stacks
		GameState.health_changed.connect(_observe_health)
		if card in ["pierce", "splash"]:
			child_entered_tree.connect(_observe_projectile)
		elif card == "graze_focus":
			_player._graze_area.area_entered.connect(_observe_graze)
		_log_trial("choice", {"source": UpgradeDraft.get_draft(pid).source, "hp": _hp_last})
	$TrialUI/Options.hide()
	_player.trial_draft_movement_only = false
	_player.set_process_unhandled_input(true)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.set_wave_phase("首卡试飞 · 中路可通行", Color.LIGHT_CYAN)

func _tick_wave_director(delta: float) -> void:
	if GameState.level < 2 or (trial_tick >= END_TICK and not from_draft):
		super._tick_wave_director(delta)

func _physics_process(_delta: float) -> void:
	if trial_tick < 0 or trial_tick >= END_TICK:
		return
	if not GameState.game_running:
		_finish_observation("defeat")
		return
	trial_tick += 1
	_tick_action_hint()
	while next_order < ORDERS.size() and ORDERS[next_order].at == trial_tick:
		var order: Dictionary = ORDERS[next_order]
		var ship = _spawn_enemy_at(order.kind, field * order.from)
		ship.set_physics_process(false)
		ship.rotation = PI
		ship.drop_chance = 0.0
		# 同一物理帧的后续炮弹和溅射不能再次给这架已击毁的靶机计分。
		ship.enemy_died.connect(ship.remove_from_group.bind("enemies"), CONNECT_ONE_SHOT)
		squad.append(ship)
		next_order += 1
	for i in squad.size():
		var ship = squad[i]
		if not is_instance_valid(ship):
			continue
		var order: Dictionary = ORDERS[i]
		var travel := clampf(float(trial_tick - int(order.at)) / ARRIVAL_TICKS, 0.0, 1.0)
		var retreat := clampf(float(trial_tick - RETREAT_TICK) / 50.0, 0.0, 1.0)
		ship.position = field * (order.from as Vector2).lerp(order.to, travel)
		ship.position.y = lerpf(ship.position.y, -40.0, retreat)
		ship.get_node("HealthBar").value = ship.health
		if retreat >= 1.0:
			ship.queue_free()
	if trial_tick == RETREAT_TICK:
		_hud.set_wave_phase("右侧扇弹 · 中路可通行", Color.LIGHT_CYAN)
		queue_redraw()
	if trial_tick in VOLLEYS:
		for end_x: float in FAN_EXITS:
			var bullet = Pool.acquire("bullet", _bullet_scene)
			add_child(bullet)
			var start := _fan_origin()
			var direction := start.direction_to(field * Vector2(end_x, 1.0))
			bullet.setup(start, direction.angle(), 0.3, false, 1, Enemy.SPEED_SLOW)
			bullet.modulate = TrialPalette.ENEMY_BULLET_SLOW
		if trial_tick == VOLLEYS[0]:
			queue_redraw()
	if trial_tick == END_TICK:
		_finish_observation("complete")
		if not from_draft:
			_asteroid_timer = asteroid_resume
			_hud.set_draft_prompt("")
			_last_wave_phase_text = ""
			_refresh_wave_phase_hud()
			return
		_player.set_physics_process(false)
		_player.set_process_unhandled_input(false)
		var stick := get_node_or_null("MobileControls")
		if stick != null:
			stick.disable_for_results()
		_hud.set_wave_phase("试飞结束", Color.LIGHT_CYAN)
		$TrialUI/Options/Power.hide()
		$TrialUI/Options/Retry.show()
		$TrialUI/Options.show()
		_layout_trial_options()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _layout_trial_options() -> void:
	var options: Control = $TrialUI/Options
	if not options.visible:
		return
	var safe := SafeArea.for_viewport(get_viewport()).grow(-SafeArea.MENU_MARGIN)
	options.set_anchors_preset(Control.PRESET_TOP_LEFT)
	options.size = options.get_combined_minimum_size()
	options.position = Vector2(safe.get_center().x - options.size.x * 0.5,
		minf(safe.position.y + safe.size.y / 3.0, safe.end.y - options.size.y)).round()

func _layout_action_hint() -> void:
	if not _action_hint.visible:
		return
	var safe := SafeArea.for_viewport(get_viewport())
	_action_hint.size = _action_hint.get_minimum_size()
	_action_hint.position = Vector2(safe.get_center().x - _action_hint.size.x * 0.5, safe.position.y + 14).round()

func _tick_action_hint() -> void:
	if _hint.is_empty():
		return
	if trial_tick == _hint.start:
		_action_hint.text = _hint.text
		_action_hint.show()
		_layout_action_hint()
		_log_trial("hint_start")
	elif trial_tick == _hint.end:
		_hide_action_hint("window")

func _hide_action_hint(reason: String) -> void:
	if is_instance_valid(_action_hint) and _action_hint.visible:
		_action_hint.hide()
		_log_trial("hint_end", {"reason": reason})

func _observe_health(hp: int, _maximum: int) -> void:
	_hp_lost += maxi(_hp_last - hp, 0)
	_hp_last = hp

func _observe_projectile(node: Node) -> void:
	if node.scene_file_path == _bullet_scene.resource_path:
		node.card_effect.connect(_observe_projectile_result)

func _observe_projectile_result(card: String, target: Node2D) -> void:
	if card == _trial_card and squad.has(target):
		_record_first_result()

func _observe_graze(_area: Area2D) -> void:
	if GameState._graze_stacks > _graze_before:
		_record_first_result()

func _record_first_result() -> void:
	if not _recording or _first_result_tick >= 0:
		return
	_first_result_tick = trial_tick
	_log_trial("first_result", {"hp_lost": _hp_lost})

func _finish_observation(reason: String) -> void:
	_hide_action_hint(reason)
	if not _recording:
		return
	_log_trial("slice_end", {"reason": reason, "result_tick": _first_result_tick, "hp_lost": _hp_lost, "hp": _hp_last})
	_recording = false
	GameState.health_changed.disconnect(_observe_health)
	if child_entered_tree.is_connected(_observe_projectile):
		child_entered_tree.disconnect(_observe_projectile)

func _log_trial(event: String, details := {}) -> void:
	if not _recording:
		return
	var entry := {"event": event, "card": _trial_card, "variant": "B" if _show_action_hint else "A",
		"tick": trial_tick, "seconds": float(trial_tick) / Engine.physics_ticks_per_second}
	entry.merge(details)
	print("[TRIAL_EVENT] ", JSON.stringify(entry))

func _fan_origin() -> Vector2:
	return Vector2(field.x * .75, 0)

func _draw() -> void:
	if trial_tick >= RETREAT_TICK and trial_tick < VOLLEYS[0]:
		var color := Color(TrialPalette.WARN_LINE, .46)
		for end_x: float in FAN_EXITS:
			draw_line(_fan_origin(), field * Vector2(end_x, 1.0), color, 2.0)
