extends Node

const Enemy := preload("res://scripts/battle/enemies/enemy.gd")
const Waves := preload("res://scripts/battle/wave_director.gd")
const NORMAL := "res://scenes/main.tscn"
const CHOICES := [
	[0, 1, Waves.PHASE_SETUP, 1, 1],
	[1, 1, Waves.PHASE_SETUP, 3, 3],
	[2, 1, Waves.PHASE_SETUP, 6, 6],
	[1, 6, Waves.PHASE_CREST, 2, 3],
	[2, 11, Waves.PHASE_SURGE, 3, 6],
	[2, 11, Waves.PHASE_SURGE, 6, 6],
]

var _main: Node
var _role: String
var _folder: String
var _case: String
var _port: int
var _passed := 0
var _failed := 0
var _solo := false
var _host := false
var _graphical := false
var _capture_enabled := false
var _stabilize_render := false
var _last_draw_usec := 0
var _observed_ship := 0
var _warning_draw_usec := 0
var _frames := {}
var _next_capture := ""
var _shooter: Node2D
var _origin := Vector2.ZERO
var _last_frame_usec := 0
var _frame_gaps := PackedFloat64Array()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60
	_run.call_deferred()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _stabilize_render and now - _last_draw_usec >= 66000:
		# macOS can stop swapping a test window even while its SceneTree is running.
		# Ask the renderer for a real viewport frame when the desktop stalls.
		RenderingServer.force_draw(false)
	if _last_frame_usec > 0:
		_frame_gaps.append((now - _last_frame_usec) / 1000.0)
		_last_frame_usec = now

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_role = args[0]
	_folder = args[1]
	_case = args[2]
	_port = int(args[3])
	_solo = _role == "solo"
	_host = _role != "guest"
	_graphical = DisplayServer.get_name() != "headless"
	_capture_enabled = _graphical and not args.has("no-capture")
	_stabilize_render = _graphical and args.has("stabilize-render")
	if not (_solo and args.has("no-capture")):
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if args.has("wide") else 960, 720)
	if _graphical:
		RenderingServer.frame_post_draw.connect(_record_frame)
	seed(20261128)
	if not await _open_battle():
		_check("normal_entry", false)
		_finish()
		return
	_check("normal_entry", true)
	_main = get_tree().current_scene
	_main._asteroid_timer = 1000
	_main._wave_director._cooldown = 1000
	var ready := await _until(func():
		return is_instance_valid(_main._player) and (_solo or _main._player_entry_ready), 9.0)
	_check("ready", ready)
	if not ready:
		_finish()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var field: Vector2 = NetworkManager.battle_size(_main)
	_origin = field * Vector2(.4, .4)
	_shooter = _main._players.get(1, _main._player)
	_shooter.set_physics_process(false)
	_shooter.collision_layer = 0
	_shooter.position = _origin + Vector2(200, 0)
	_shooter.reset_physics_interpolation()
	if not _solo:
		var guest: Node2D = _main._players[NetworkManager.recovery.guest_slot]
		guest.set_physics_process(false)
		guest.collision_layer = 0
		guest.position = _origin + Vector2(-150, 250)
		guest.reset_physics_interpolation()
	await _barrier("ready")
	if _case == "cancellation":
		await _cancellations()
	else:
		var choices := CHOICES.slice(0, 1) if _case == "delayed" else CHOICES
		for index in choices.size():
			await _observe(index, choices[index])
	_finish()

func _open_battle() -> bool:
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	var title := get_tree().current_scene
	if _solo:
		title.get_node("Menu/BtnSingle").pressed.emit()
	else:
		title.get_node("Menu/BtnMultiplayer").pressed.emit()
		await get_tree().scene_changed
		var lobby := get_tree().current_scene
		if _host:
			lobby._btn_be_host.pressed.emit()
			NetworkDiscovery.stop_all()
			_touch("listening")
			if not await _until(func(): return not lobby._btn_start.disabled, 12.0):
				return false
			lobby._btn_start.pressed.emit()
		else:
			if not await _until(func(): return _marked("host", "listening"), 10.0):
				return false
			lobby._btn_be_client.pressed.emit()
			HarmonyBridge.report_discovered_host("复跑房间", "127.0.0.1", _port)
			lobby._host_buttons["127.0.0.1:%d" % _port].pressed.emit()
	return await _until(func():
		return (get_tree().current_scene != null and get_tree().current_scene.scene_file_path == NORMAL), 14.0)

func _stage(label: String, kind: int, level: int, phase: int, at: Vector2) -> Enemy:
	var ship: Enemy
	if _host:
		GameState.level = level
		_main._wave_director._phase_index = phase
		_main._wave_director._phase_left = 1000
		_shooter.position = at + Vector2(200, 0)
		_shooter.reset_physics_interpolation()
		ship = _main._spawn_enemy_at(kind, at)
		ship.move_speed = 0.0
		ship.drop_chance = 0.0
		ship._shoot_timer = 8.0
		_write(label + "-eid", str(ship.entity_id))
	if not _solo:
		if not _host:
			if not await _until(func(): return _marked("host", label + "-eid"), 9.0):
				return null
			var eid := int(FileAccess.get_file_as_string(_file("host", label + "-eid")))
			if not await _until(func(): return is_instance_valid(_main._entities.get(eid)), 6.0):
				return null
			ship = _main._entities[eid]
		await _barrier(label + "-spawn")
	_check(label + "_managed_enemy", is_instance_valid(ship) and ship.ordinary_attack and ship._is_network_ghost != _host)
	return ship

func _observe(index: int, row: Array) -> void:
	var label := "type%d-level%d-case%d" % [row[0], row[1], index]
	var at := Vector2(46, _origin.y) if index == 5 else _origin
	var ship := await _stage(label, row[0], row[1], row[2], at)
	if not is_instance_valid(ship):
		_check(label + "_spawn", false)
		return
	if _host:
		ship._shoot_timer = 0.10
	_observed_ship = ship.get_instance_id()
	_warning_draw_usec = 0
	_frame_gaps.clear()
	_last_frame_usec = Time.get_ticks_usec()
	var prep := await _until(func():
		return (ship.attack_phase == Enemy.AttackPhase.PREPARE and
			(not _graphical or _warning_draw_usec > 0)), 3.0)
	var warning_at := _warning_draw_usec if _graphical else Time.get_ticks_usec()
	_check(label + "_warning", prep and _bullets().is_empty())
	if not prep:
		_last_frame_usec = 0
		return
	var heading := ship.attack_heading
	var directions := ship.attack_angles.duplicate()
	var origins: Array[Vector2] = []
	for i in directions.size():
		origins.append(ship.attack_muzzle(i))
	_check(label + "_budget_and_pattern", directions.size() == row[4] and ship.attack_first_count == row[3])
	if row[0] == 2:
		var safe := true
		for angle: float in directions:
			safe = safe and absf(wrapf(angle - heading, -PI, PI)) >= deg_to_rad(39.9)
		_check(label + "_common_safe_gap", safe)
	await _capture(label + "-prepare")
	var driving := _host and index in [0, 4]
	var health_before := GameState.get_current_health(1)
	if driving:
		# Actual player movement via its normal motion controller, without automatic fire.
		_shooter.trial_draft_movement_only = true
		_shooter.clear_lan_input()
		_shooter._motion.mobile_mode = true
		_shooter._motion.handle_mobile_move(Vector2.DOWN if index == 0 else Vector2.RIGHT)
		_shooter.set_physics_process(true)
		if index == 4:
			_shooter.collision_layer = 1
	var first := await _until(func(): return not _bullets().is_empty(), 2.5)
	var first_at := Time.get_ticks_usec()
	if _host and index == 0:
		_shooter._motion.handle_mobile_move(Vector2.ZERO)
		_shooter.set_physics_process(false)
		var moved: Vector2 = _shooter.position - (at + Vector2(200, 0))
		_check(label + "_perpendicular_motion", absf(moved.x) < 1.0 and moved.y > 45.0)
		var degree := rad_to_deg(heading)
		_check(label + "_rightward_aim_remains_locked", absf(degree) < 0.05 and absf(ship.attack_heading - heading) < .001)
	_check(label + "_first_batch_after_warning", first and _bullets().size() == row[3] and
		ship.attack_phase != Enemy.AttackPhase.PREPARE and
		((_solo and not _graphical) or first_at - warning_at >= 450000))
	await _capture(label + "-release")
	var all_arrived := await _until(func(): return _bullets().size() == row[4], 1.2)
	var all_at := Time.get_ticks_usec()
	var checked := {}
	var authority := true
	for bullet in _bullets():
		authority = authority and (bullet._is_network_ghost != _host)
		for i in directions.size():
			var direction := Vector2.from_angle(directions[i])
			if bullet._direction.is_equal_approx(direction) and absf(direction.cross(bullet.global_position - origins[i])) <= 1.0:
				checked[i] = true
	_check(label + "_matched_ballistics", all_arrived and checked.size() == directions.size() and authority)
	var recovered := await _until(func(): return ship.attack_phase == Enemy.AttackPhase.RECOVER, 1.0)
	_check(label + "_recover", recovered)
	if row[3] != row[4]:
		await _capture(label + "-second-release")
	await get_tree().create_timer(.16).timeout
	if _host and index == 4:
		_shooter._motion.handle_mobile_move(Vector2.ZERO)
		_shooter.set_physics_process(false)
		var moved: Vector2 = _shooter.position - (at + Vector2(200, 0))
		_check(label + "_pilot_uses_open_sector", moved.x > 100.0 and absf(moved.y) < 0.5
			and GameState.get_current_health(1) == health_before)
		print("[ENEMY] SAFE_ROUTE ", JSON.stringify({"role": _role, "movement": [moved.x, moved.y],
			"health_before": health_before, "health_after": GameState.get_current_health(1)}))
		_shooter.collision_layer = 0
	await _capture(label + "-recover")
	_last_frame_usec = 0
	_frame_gaps.sort()
	var p95 := _frame_gaps[int((_frame_gaps.size() - 1) * 0.95)] if not _frame_gaps.is_empty() else 0.0
	print("[ENEMY] ATTACK ", JSON.stringify({"case": label, "role": _role, "level": row[1],
		"draw_to_first_ms": (first_at - warning_at) / 1000.0, "gap_ms": (all_at - first_at) / 1000.0, "frame_gap_p95_ms": p95,
		"directions": Array(directions),
		"origins": origins.map(func(value): return [value.x, value.y]), "first": row[3], "total": checked.size()}))
	await _retire(label, ship)

func _cancellations() -> void:
	var label := "no-draw"
	var ship := await _stage(label, 0, 1, Waves.PHASE_SETUP, _origin)
	if not is_instance_valid(ship):
		_check("no_draw_enemy", false)
		return
	if not _host:
		ship._ordinary_visual.hide()
	await _barrier(label + "-armed")
	if _host:
		ship._shoot_timer = 0.05
	var started := await _until(func(): return ship.attack_phase == Enemy.AttackPhase.PREPARE, 2.0)
	var prep_usec := Time.get_ticks_usec()
	var stamp := ship.attack_stamp
	var old_state := ship.ordinary_attack_snapshot()
	if not _host:
		# Stale, future, and other-round acknowledgements travel through the real RPC.
		var round_id := GameState.get_sync_round()
		_main._rpc_enemy_warning_seen.rpc_id(1, round_id, ship.entity_id, stamp - 1)
		_main._rpc_enemy_warning_seen.rpc_id(1, round_id, ship.entity_id, stamp + 1)
		_main._rpc_enemy_warning_seen.rpc_id(1, round_id + 1, ship.entity_id, stamp)
	var skipped := await _until(func(): return ship.attack_phase == Enemy.AttackPhase.RECOVER, 2.0)
	var elapsed := (Time.get_ticks_usec() - prep_usec) / 1000.0
	_check("unseen_warning_times_out_without_fire", started and skipped and not ship.attack_release
		and _bullets().is_empty() and elapsed >= 800 and elapsed <= 1200)
	print("[ENEMY] TIMEOUT ", JSON.stringify({"role": _role, "elapsed_ms": elapsed}))
	if _host:
		_main._rpc_enemy_attack.rpc(GameState.get_sync_round(), ship.entity_id, old_state)
	else:
		ship._ordinary_visual.show()
	await _barrier(label + "-replay")
	await get_tree().create_timer(.15).timeout
	_check("retired_prepare_cannot_reopen", ship.attack_phase != Enemy.AttackPhase.PREPARE)
	await _retire(label, ship)

	for reason in ["death", "retarget"]:
		ship = await _stage(reason, 0, 1, Waves.PHASE_SETUP, _origin)
		if not is_instance_valid(ship):
			_check(reason + "_enemy", false)
			return
		if _host:
			ship._shoot_timer = 0.05
		var prepared := await _until(func(): return ship.attack_phase == Enemy.AttackPhase.PREPARE, 2.0)
		await _barrier(reason + "-visible")
		var instance := ship.get_instance_id()
		if _host and reason == "death":
			ship.take_damage(ship.health)
		elif _host:
			ship.set_target(null)
		var closed := await _until(func():
			var remaining := instance_from_id(instance) as Enemy
			return not is_instance_valid(remaining) or remaining.attack_phase == Enemy.AttackPhase.RECOVER, 2.0)
		await get_tree().create_timer(.50).timeout
		_check(reason + "_cancels_pending_shot", prepared and closed and _bullets().is_empty())
		await _retire(reason, ship if is_instance_valid(ship) else null)

	label = "reconnect"
	ship = await _stage(label, 1, 6, Waves.PHASE_CREST, _origin)
	if not is_instance_valid(ship):
		_check("reconnect_enemy", false)
		return
	if _host:
		ship._shoot_timer = 0.05
	var fired := await _until(func(): return ship.attack_phase == Enemy.AttackPhase.FOLLOW_THROUGH and not _bullets().is_empty(), 2.0)
	old_state = ship.ordinary_attack_snapshot()
	await _barrier(label + "-first")
	if not _host:
		NetworkManager.drop_lan_transport()
	var paused := await _until(func(): return get_tree().paused, 4.0)
	var cleared := paused and ship.attack_phase == Enemy.AttackPhase.FLIGHT and _bullets().is_empty()
	var resumed := await _until(func(): return not get_tree().paused and NetworkManager.is_online(), 16.0)
	_check("recovery_clears_warning_and_old_bullets", fired and cleared and resumed and _bullets().is_empty())
	print("[ENEMY] RECOVERY ", JSON.stringify({"role": _role, "first_batch_observed": fired,
		"held": paused, "cleared": cleared, "resumed": resumed, "remaining": _bullets().size()}))
	await _barrier(label + "-resumed")
	if _host and resumed:
		ship._shoot_timer = 5.0
		_main._rpc_enemy_attack.rpc(GameState.get_sync_round(), ship.entity_id, old_state)
		_main._rpc_enemy_attack.rpc(GameState.get_sync_round() - 1, ship.entity_id, old_state)
	await get_tree().create_timer(.20).timeout
	_check("recovery_rejects_stale_attack_state", ship.attack_phase == Enemy.AttackPhase.FLIGHT and _bullets().is_empty())
	await _barrier(label + "-old-state")
	if _host and resumed:
		ship._shoot_timer = 0.08
	var new_cue := await _until(func(): return ship.attack_phase == Enemy.AttackPhase.PREPARE, 2.0)
	_check("recovery_starts_with_fresh_warning", new_cue and _bullets().is_empty())
	await _retire(label, ship)

func _retire(label: String, ship: Enemy) -> void:
	await _barrier(label + "-checked")
	if _host and is_instance_valid(ship):
		ship.die()
	for shot in _bullets():
		Pool.release(shot)
	await get_tree().create_timer(.20).timeout

func _bullets() -> Array[Node]:
	return get_tree().get_nodes_in_group("enemy_bullets").filter(func(shot): return not shot.is_queued_for_deletion())

func _capture(label: String) -> void:
	if not _capture_enabled:
		return
	_next_capture = label
	if not await _until(func(): return _next_capture.is_empty(), .45):
		_check("rendered_" + label, false)
		_next_capture = ""

func _record_frame() -> void:
	_last_draw_usec = Time.get_ticks_usec()
	if _observed_ship > 0 and _warning_draw_usec == 0:
		var enemy := instance_from_id(_observed_ship) as Enemy
		if is_instance_valid(enemy) and enemy.attack_phase == Enemy.AttackPhase.PREPARE \
				and enemy.attack_stamp == enemy._ordinary_visual.drawn_warning_stamp:
			_warning_draw_usec = _last_draw_usec
	if not _next_capture.is_empty():
		_frames[_next_capture] = get_viewport().get_texture().get_image()
		_next_capture = ""

func _barrier(label: String) -> void:
	if _solo:
		return
	_touch(label)
	_check("barrier_" + label, await _until(func(): return _marked("guest" if _host else "host", label), 8.0))

func _file(role: String, label: String) -> String:
	return _folder.path_join("%s-%s.mark" % [role, label])

func _marked(role: String, label: String) -> bool:
	return FileAccess.file_exists(_file(role, label))

func _write(label: String, value: String) -> void:
	var file := FileAccess.open(_file(_role, label), FileAccess.WRITE)
	if file:
		file.store_string(value)

func _touch(label: String) -> void:
	_write(label, "ok")

func _until(predicate: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_usec() + int(seconds * 1000000)
	while Time.get_ticks_usec() < until:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false

func _check(label: String, ok: bool) -> void:
	print("[ENEMY] ", _role, " ", label, " pass=", ok)
	_passed += int(ok)
	_failed += int(not ok)

func _finish() -> void:
	for label: String in _frames:
		var image: Image = _frames[label]
		_check("capture_" + label, image.save_png(_folder.path_join(_role + "-" + label + ".png")) == OK)
	print("[ENEMY] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))
