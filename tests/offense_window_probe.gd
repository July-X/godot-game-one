extends Node

const TRIAL := preload("res://scenes/offense_window_trial.tscn")
const Trial := preload("res://scripts/battle/trials/offense_window_trial.gd")
const LEGACY_PATH := "res://scenes/offense_window_trial_v1.tscn"
const MobileControls := preload("res://scenes/ui/mobile_controls.tscn")
const TITLE := "res://scenes/ui/title_screen.tscn"
const SHOT := "res://scenes/entities/bullet.tscn"
const ENEMY := "res://scenes/entities/enemy.tscn"
var trial: Trial
var _births: Array = []
var _lanes: Dictionary = {}
var _deaths: Dictionary = {}
var _charges: Dictionary = {}
var _interruptions: Array[Dictionary] = []
var _source_ok := true
var _cue_ok := true
var _path := PackedVector2Array()
var _stick_origin := Vector2.ZERO
var _delay := 0
var _offset := 0
var _first_wave_only := false
var _last_hp := 0
var _hp_lost := 0
var _pass := 0
var _fail := 0

func _ready() -> void:
	process_priority = 100
	_run.call_deferred()

func _process(_delta: float) -> void:
	if is_instance_valid(trial):
		trial._hitstop_left = 0.0
		Engine.time_scale = 1.0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if "--wide" in args else 1280, 720)
	if "--entry" in args:
		await _check_title_flow()
		_finish()
		return
	var card := args[0] if not args.is_empty() else "pierce"
	var route := args[1] if args.size() > 1 else "rush"
	_first_wave_only = "--first-wave" in args
	for arg in args:
		if arg.begins_with("--delay="):
			_delay = arg.trim_prefix("--delay=").to_int()
		elif arg.begins_with("--offset="):
			_offset = arg.trim_prefix("--offset=").to_int()
	seed(1121)
	trial = TRIAL.instantiate()
	trial.use_legacy = "--legacy" in args
	if "--touch-flight" in args:
		trial.add_child(MobileControls.instantiate())
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	trial.child_entered_tree.connect(_observe_spawn)
	trial.charge_interrupted.connect(_observe_interruption)
	GameState.health_changed.connect(_observe_health)
	_last_hp = GameState.get_current_health(1)
	await get_tree().process_frame
	_check("opens_only_two_cards", UpgradeDraft.get_draft(1).cards == Trial.OFFER)
	_check("selection_before_flight", trial.trial_tick == -1 and get_tree().get_nodes_in_group("player_bullets").is_empty())
	var key := InputEventKey.new()
	key.keycode = KEY_1 if card == "pierce" else KEY_2
	key.pressed = true
	get_viewport().push_input(key, true)
	trial._player.set_process_unhandled_input(false)
	if "--touch-flight" in args:
		_stick_origin = Vector2(160, trial.field.y - 165)
		var press := InputEventScreenTouch.new()
		press.pressed = true
		press.position = _stick_origin
		get_viewport().push_input(press, true)
	_check("one_selected_card", GameState.get_card_stacks(1) == {card: 1})
	var end := 330 if _first_wave_only else Trial.END_TICK
	var deadline := Engine.get_physics_frames() + end + 30
	while not trial._finished and trial.trial_tick < end and Engine.get_physics_frames() < deadline:
		await get_tree().physics_frame
		if not trial._finished and trial.trial_tick < end:
			_steer(route)
			_path.append(trial._player.position.snapped(Vector2.ONE * .01))
			if trial._charged_fire_at > 0 and not _charges.has(trial._charged_fire_at):
				_charges[trial._charged_fire_at] = trial.trial_tick
			if trial.trial_tick in [125, 189]:
				await _capture(args)
	_check("reaches_end", trial.trial_tick == end and trial._finished == not _first_wave_only)
	_check("fixed_schedules", _births.size() == Trial.ORDERS.size() * (1 if _first_wave_only else Trial.COLUMN_X.size()))
	_check("no_ordinary_progression", GameState.level == 1 and not UpgradeDraft.has_draft(1)
		and not is_instance_valid(trial._boss) and not is_instance_valid(trial._elite))
	_check("all_real_fans_match_live_emitters", _fans_match_deaths())
	_check("real_bullet_spawns_have_a_live_source", _source_ok)
	_check("interruptions_match_death_in_pending_charge", _cue_ok and _interruptions_match_deaths())
	_check("all_break_cues_expire", trial._breaks.is_empty())
	if not _first_wave_only and trial.use_legacy:
		var first: Array = _lanes.get(Trial.FIRE_TICKS[0], [[], []])
		var expected_left := 0 if card == "pierce" and route == "rush" else 3
		_check("first_fan_changes_when_rear_is_destroyed", first[0].size() == expected_left and first[1].size() == 3)
	if route == "center":
		_check("center_flythrough_is_safe", _path.size() > 180 and _hp_lost == 0 and _path[0].y - _path[180].y > 90
			and not _deaths.has(Trial.LEFT_EMITTER))
	print("[WINDOW_DATA] ", JSON.stringify({"card": card, "route": route, "view": str(trial.field), "delay": _delay, "offset": _offset,
		"version": "legacy" if trial.use_legacy else "revised", "fire_ticks": trial._fire_beats(0),
		"charge_starts": _charges, "interruptions": _interruptions,
		"path": var_to_bytes(_path).hex_encode().sha256_text(), "samples": _path.size(), "births": _births, "fans": _lanes, "deaths": _deaths,
		"hp_lost": _hp_lost, "end": trial.trial_tick}))
	_finish()

func _steer(route: String) -> void:
	var tick := trial.trial_tick
	var beat := tick % Trial.WAVE_TICKS
	var wave := tick / Trial.WAVE_TICKS
	var target := trial.field * Vector2(.5, .78)
	if (route == "rush" and beat < 192) or (route == "late" and beat > 104 and beat < 281):
		target.x = trial.field.x * Trial.COLUMN_X[wave]
		if wave == 0:
			target.x += _offset
		var advance := 100 if _stick_origin != Vector2.ZERO else 117
		var climb := beat - advance - (_delay if wave == 0 else 0) if route == "rush" else beat - 196
		target.y -= clampf(climb * 1.4, 0, 130)
	elif route == "center":
		target.y -= minf(beat * .7, 126)
	var player = trial._player
	var desired: Vector2 = ((target - player.position) * 7).limit_length(player.move_speed)
	if _stick_origin != Vector2.ZERO:
		var drag := InputEventScreenDrag.new()
		drag.position = _stick_origin + desired / player.move_speed * trial.get_node("MobileControls").joystick_radius
		get_viewport().push_input(drag, true)
		return
	var event := InputEventMouseMotion.new()
	event.relative = (desired - player._motion.mouse_vel) / (player.mouse_sensitivity * player.move_speed)
	player._unhandled_input(event)

func _observe_spawn(node: Node) -> void:
	var tick := trial.trial_tick
	if node.scene_file_path == SHOT:
		_record_fan.call_deferred(node.get_instance_id(), tick)
	elif node.scene_file_path == ENEMY:
		var slot := _births.size() % Trial.ORDERS.size()
		var wave := _births.size() / Trial.ORDERS.size()
		_births.append([tick, node.enemy_type, node.position.x, node.position.y])
		node.enemy_died.connect(func(): _deaths[wave * Trial.ORDERS.size() + slot] = trial.trial_tick,
			CONNECT_ONE_SHOT)

func _record_fan(id: int, tick: int) -> void:
	var shot = instance_from_id(id)
	if not is_instance_valid(shot) or not shot.is_in_group("enemy_bullets"):
		return
	if not _lanes.has(tick):
		_lanes[tick] = [[], []]
	var lane := int(shot.position.x > trial.field.x * .5)
	var slot := Trial.LEFT_EMITTER if lane == 0 else Trial.RIGHT_EMITTER
	var actor = trial.squad[slot]
	_source_ok = (_source_ok and is_instance_valid(actor) and actor.health > 0
		and absf(shot.position.distance_to(actor.position) - 20.0) < .1 and shot._speed == 430.0)
	var source := (tick - 1) / Trial.WAVE_TICKS * Trial.ORDERS.size() + slot
	_lanes[tick][lane].append([shot.position.x, shot.position.y, shot._direction.x, shot._direction.y, shot._speed, source])

func _fans_match_deaths() -> bool:
	for tick: int in _lanes:
		var wave := (tick - 1) / Trial.WAVE_TICKS
		if (tick - 1) % Trial.WAVE_TICKS + 1 not in trial._fire_beats(wave):
			return false
	for wave in (1 if _first_wave_only else Trial.COLUMN_X.size()):
		for beat: int in trial._fire_beats(wave):
			var tick := wave * Trial.WAVE_TICKS + beat
			var pair: Array = _lanes.get(tick, [[], []])
			for lane in 2:
				var index := Trial.LEFT_EMITTER if lane == 0 else Trial.RIGHT_EMITTER
				var death: int = _deaths.get(wave * Trial.ORDERS.size() + index, Trial.END_TICK)
				var count: int = pair[lane].size()
				if count != (3 if death >= tick else 0):
					return false
	return true

func _observe_interruption(slot: int, fire_tick: int, at: Vector2) -> void:
	var ship = trial.squad[slot]
	_cue_ok = _cue_ok and is_instance_valid(ship) and ship.global_position.is_equal_approx(at) and trial._break_voice.playing
	_interruptions.append({"slot": slot, "tick": trial.trial_tick, "fire_tick": fire_tick, "x": at.x, "y": at.y})

func _interruptions_match_deaths() -> bool:
	if trial.use_legacy:
		return _interruptions.is_empty()
	var expected := 0
	for wave in (1 if _first_wave_only else Trial.COLUMN_X.size()):
		var starts_at := wave * Trial.WAVE_TICKS
		var fires := trial._fire_beats(wave)
		for slot in [Trial.LEFT_EMITTER, Trial.RIGHT_EMITTER]:
			var death: int = _deaths.get(wave * Trial.ORDERS.size() + slot, -1)
			for i in fires.size():
				var fire: int = starts_at + fires[i]
				if death < starts_at + trial._charge_start(fires, i) or death >= fire:
					continue
				expected += 1
				if not _interruptions.any(func(event): return event.slot == slot and event.fire_tick == fire and event.tick == death):
					return false
	return _interruptions.size() == expected

func _observe_health(hp: int, _maximum: int) -> void:
	_hp_lost += maxi(_last_hp - hp, 0)
	_last_hp = hp

func _capture(args: PackedStringArray) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for arg in args:
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			var path := arg.trim_prefix("--capture=").path_join("frame-%d.png" % trial.trial_tick)
			_check("saved_frame", get_viewport().get_texture().get_image().save_png(path) == OK)

func _check_title_flow() -> void:
	get_tree().node_added.connect(func(node: Node):
		if node.scene_file_path in [TRIAL.resource_path, LEGACY_PATH] and not (OS.has_feature("android") or OS.has_feature("ios")):
			node._spawn_mobile_controls())
	get_tree().current_scene = null
	get_tree().change_scene_to_file(TITLE)
	await get_tree().scene_changed
	var title := get_tree().current_scene
	await get_tree().process_frame
	await _tap(title.get_node("Menu/BtnTrials"))
	await _tap(title.get_node("TrialHub/BtnOffenseWindow"))
	trial = get_tree().current_scene as Trial
	_check("title_opens_independent_trial", is_instance_valid(trial) and UpgradeDraft.get_draft(1).cards == Trial.OFFER)
	if not is_instance_valid(trial):
		return
	await get_tree().process_frame
	_check("revised_is_default", not trial.use_legacy and not trial._comparison.button_pressed)
	for legacy in [true, false]:
		var preset := "legacy" if legacy else "revised"
		await _tap(trial._comparison)
		_check("can_select_%s_before_cards" % preset,
			trial.use_legacy == legacy and trial._comparison.button_pressed == legacy)
		var stand := Vector2(160, trial.field.y - 162)
		_touch(stand, true, 0)
		var drag := InputEventScreenDrag.new()
		drag.position = get_viewport().get_final_transform() * (stand - Vector2(84, 0))
		Input.parse_input_event(drag)
		Input.flush_buffered_events()
		await _tap(trial._hud._draft_card_buttons[1], 1)
		_check("%s_two_fingers_choose_power_and_keep_steering" % preset,
			GameState.get_card_stacks(1) == {"power": 1} and trial._player._motion.touch_move.x < -.7
			and not trial._comparison.visible)
		_touch(stand, false, 0)
		var previous := trial.get_instance_id()
		await _tap(trial._retry_button)
		trial = get_tree().current_scene as Trial
		_check("%s_retry_resets_time_and_choice" % preset, is_instance_valid(trial) and trial.get_instance_id() != previous
			and trial.trial_tick == -1 and GameState.get_card_stacks(1).is_empty() and UpgradeDraft.has_draft(1)
			and trial.use_legacy == legacy and trial._comparison.button_pressed == legacy
			and trial._breaks.is_empty() and not trial._break_voice.playing)
		if not is_instance_valid(trial):
			return
	await _tap(trial.get_node("TrialUI/Options/Buttons/Back"))
	_check("return_to_title_clears_trial_draft", get_tree().current_scene.scene_file_path == TITLE and not UpgradeDraft.has_draft(1))

func _tap(button: Button, index := 0) -> void:
	for pressed in [true, false]:
		_touch(button.get_global_rect().get_center(), pressed, index)
		await get_tree().process_frame
	await get_tree().process_frame

func _touch(pos: Vector2, pressed: bool, index: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = get_viewport().get_final_transform() * pos
	touch.pressed = pressed
	Input.parse_input_event(touch)
	Input.flush_buffered_events()

func _check(name: String, ok: bool) -> void:
	_pass += int(ok)
	_fail += int(not ok)
	print("[WINDOW] ", name, " pass=", ok)

func _finish() -> void:
	if is_instance_valid(trial):
		get_tree().current_scene = null
		trial.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("[WINDOW] SUMMARY pass=%d failed=%d" % [_pass, _fail])
	get_tree().quit(int(_fail > 0))
