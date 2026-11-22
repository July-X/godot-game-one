extends "res://tests/opening_trial_probe.gd"

const CloseScene := preload("res://scenes/elite_close_trial.tscn")
const Close := preload("res://scripts/elite_close_trial.gd")

var close_trial: Close
var break_tick := -1
var elite_shots: Array = []
var elite_contacts: Array = []
var frames: Array = []
var bonus: Array = []
var flight: Array = []
var _replay: Array = []
var _aim := Vector2.ZERO
var _late_contact := false

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if "--wide" in args else 1280, 720)
	var route := args[0] if not args.is_empty() else "press"
	for arg in args:
		if arg.begins_with("--flight="):
			var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--flight=")))
			if not recorded is Array or recorded.size() != Close.LAST_TICK - Close.START_TICK:
				push_error("Expected one joystick sample per trial frame")
				get_tree().quit(1)
				return
			_replay = recorded
	seed(Close.ELITE_SEED)
	close_trial = CloseScene.instantiate()
	trial = close_trial
	stick = Mobile.instantiate()
	trial.add_child(stick)
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	if "--retry" in args:
		await _check_retry()
		_verdict()
		return
	origin = Vector2(156, trial.field.y - 171)
	trial.child_entered_tree.connect(_observe_node)
	trial.volley_interrupted.connect(_record_interruption)
	close_trial.bonus_hit.connect(func(shot_id, extra): bonus.append([trial.trial_tick, shot_id, extra]))
	GameState.health_changed.connect(_record_health)
	GameState.shield_changed.connect(_record_shield)
	_touch(origin, true)
	var deadline := Engine.get_physics_frames() + 1200
	while not trial.finished and Engine.get_physics_frames() < deadline:
		await get_tree().physics_frame
		if trial.finished or not is_instance_valid(trial._player):
			break
		_steer(route)
		_sample_charge()
		_sample_frame()
	_check("fixed_card_and_elite", GameState.get_card_stacks(1) == {Close.TRIAL_CARD: 1} and elite_spawn_count == 1)
	_check("complete_18_seconds", trial.finished and trial.trial_tick == Close.LAST_TICK)
	_check("real_fans_follow_warnings", _check_fans() and _check_interruptions())
	print("[CLOSE_DATA] ", JSON.stringify({
		"view": str(trial.field), "route": route, "seed": Close.ELITE_SEED, "mode": "B" if close_trial.variant_b else "A",
		"births": births, "fans": fans, "interruptions": interruptions,
		"elite_shots": elite_shots, "break": break_tick, "contacts": elite_contacts,
		"frames": frames, "flight": flight, "enemy_contacts": enemy_contacts, "losses": health_loss,
		"defeat": close_trial.defeat_tick, "remaining_hp": close_trial.remaining_hp, "bonus": bonus,
	}))
	if "--hold-result" in args:
		for i in 60:
			await get_tree().process_frame
	get_tree().current_scene = null
	trial.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_verdict()

func _verdict() -> void:
	print("[CLOSE] SUMMARY failed=", _fail)
	get_tree().quit(int(_fail > 0))

func _check_retry() -> void:
	var variant := close_trial.variant_b
	var old := close_trial.get_instance_id()
	get_tree().node_added.connect(func(node):
		if node is Close:
			node._spawn_mobile_controls())
	await get_tree().process_frame
	await _tap_button(trial.get_node("TrialUI/Options/Buttons/Retry"))
	close_trial = get_tree().current_scene as Close
	_check("retry_keeps_mode_and_resets_clock", is_instance_valid(close_trial)
		and close_trial.get_instance_id() != old and close_trial.variant_b == variant
		and close_trial.trial_tick < Close.START_TICK + 12 and GameState.get_card_stacks(1) == {Close.TRIAL_CARD: 1}
		and close_trial._player._motion.mobile_mode)
	if not is_instance_valid(close_trial):
		return
	await _tap_button(close_trial.get_node("TrialUI/Options/Buttons/Back"))
	_check("returns_to_title", get_tree().current_scene.scene_file_path == Title)

func _steer(route: String) -> void:
	var desired: Vector2
	if not _replay.is_empty():
		var sample: Array = _replay[flight.size()]
		desired = Vector2(float(sample[0]), float(sample[1]))
	else:
		desired = _planned_stick(route)
	flight.append([desired.x, desired.y])
	var drag := InputEventScreenDrag.new()
	drag.position = origin + desired / trial._player.move_speed * stick.joystick_radius
	get_viewport().push_input(drag, true)

func _planned_stick(route: String) -> Vector2:
	var age := trial.trial_tick - Close.START_TICK
	var width := trial.field.x
	var axis := 1.0 - Opening.CLUSTER_X + Opening.FINALE_SHIFT
	var target := trial.field * Vector2(axis, .78)
	var at: Vector2 = trial._player.position
	var since_break := trial.trial_tick - break_tick if break_tick >= 0 else -1
	var leave := (route == "early" and since_break >= 0) or (route == "press" and age >= 410) \
		or (route == "late" and (_late_contact or since_break >= 236))
	if age < 36:
		target.x = width * .46
	elif route == "dodge" or leave:
		var sweep := age if route == "dodge" else maxi(0, age - 410)
		target.x = width * .12 + pingpong(width * .48 + sweep * 3.6, width * .76)
		target.y = trial.field.y * .82
	elif route == "early":
		target.y -= clampf((age - 158) * 3.75, 0, 310.0)
	elif age < 286:
		target.y -= clampf((age - 193) * 1.8, 0, 298.0)
	elif age < 333:
		target.x += 92.0
		target.y = at.y
	elif route == "late" and since_break >= 0 and since_break < 100:
		target.x = width * .62
		target.y = at.y
	else:
		if _aim == Vector2.ZERO or route == "late":
			_aim = trial._elite.position if is_instance_valid(trial._elite) else Vector2(width * .5, 120)
		var floor_y := 256.0
		if route == "late":
			floor_y = 368.0 if since_break < 0 else _aim.y + 150.0
		target = at.lerp(_aim, clampf((at.y - floor_y) / maxf(1.0, at.y - _aim.y), 0.0, 1.0))
	var desired := ((target - at) * 7).limit_length(trial._player.move_speed)
	return _avoid_visible_bullets(desired) if leave or route in ["dodge", "late"] else desired

func _observe_node(node: Node) -> void:
	super._observe_node(node)
	if node is Elite:
		node.shield_broken_window_started.connect(func(): break_tick = trial.trial_tick, CONNECT_ONE_SHOT)

func _observe_bullet(id: int, tick: int) -> void:
	super._observe_bullet(id, tick)
	var shot = instance_from_id(id)
	if is_instance_valid(shot) and shot.is_in_group("enemy_bullets") and shot._speed in [380.0, 520.0, 620.0]:
		elite_shots.append([tick, shot.position.x, shot.position.y, shot._direction.x, shot._direction.y, shot._speed])

func _record_hit(shot, target: Node2D, serial: int, born: int) -> void:
	super._record_hit(shot, target, serial, born)
	if target is Elite and shot._pierced.has(target):
		var gap := trial._player.global_position.distance_to(target.global_position)
		var exposed: float = Elite.PHASE_B_EXPOSE_DURATION - target._phase_b_timer if target._phase_b_timer > 0.0 else -1.0
		elite_contacts.append([trial.trial_tick, serial, born, target.get_network_shield(),
			target.get_network_health(), gap, exposed, shot.get_instance_id()])
		if gap <= Close.CLOSE_RANGE and exposed >= Close.CLOSES_AT:
			_late_contact = true

func _sample_frame() -> void:
	var player_pos: Vector2 = trial._player.global_position
	var elite_pos := Vector2.ZERO
	var health := 0.0
	var shield := 0.0
	if is_instance_valid(trial._elite):
		elite_pos = trial._elite.global_position
		health = trial._elite.get_network_health()
		shield = trial._elite.get_network_shield()
	frames.append([trial.trial_tick, player_pos.x, player_pos.y, elite_pos.x, elite_pos.y, health, shield])
