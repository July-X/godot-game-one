extends "res://tests/first_boss_aftermath_probe.gd"
## -- solo|host|client 7777 pass|hit|blocked|busy|withdraw|recover [baseline] [record]

var _case := ""
var _pilot: Node2D
var _ship: Node2D
var _flight_id := 0
var _launches := 0
var _fixed_y := 0.0
var _max_x := -INF
var _flight_start := 0.0
var _finish_time := 0.0
var _kill_count := 0
var _exit_count := 0
var _last_hp := 12
var _supply_count := 0
var _normal_births: Array[Dictionary] = []
var _approach_voices := {}
var _completed := false


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	_case = args[2] if args.size() > 2 else "pass"
	_baseline = args.has("baseline")
	_sample = "quiet"
	seed(SEED)
	if not await _require("ordinary_title_and_lobby_entry", await _open_battle()):
		return
	_main = get_tree().current_scene
	if _role != "solo" and not await _require("both_slots_in_real_enet_battle", await _wait_until(func():
			return _cond_both_players() and _main._player_entry_ready and NetworkManager.recovery.is_reserved(), 9)):
		return
	_main.child_entered_tree.connect(_observe_child)
	var field := NetworkManager.battle_size(_main)
	var slot := NetworkManager.local_player_id()
	_pilot = _main._player if _role == "solo" else _main._players[slot]
	_pilot.position = Vector2(field.x * (0.55 if _role == "client" else 0.40), field.y * 0.60)
	_pilot.reset_physics_interpolation()
	_pilot.set_physics_process(false)
	_pilot.set_process_unhandled_input(false)
	_pilot._motion.mobile_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if _role == "solo" and args.has("record"):
		_main._spawn_mobile_controls()
		_main._hud._layout_battle_hud()
	if _role != "client":
		_main._asteroid_timer = 99.0
		_main._wave_director._cooldown = 99.0
	await _barrier("ready")
	if _role != "client":
		await _kill_boss(Vector2(field.x * 0.5, BOSS_Y))
		# Same checkpoint for all choices. The normal director schedules its next row itself.
		_main._wave_director._cooldown = 3.35
		_main._asteroid_timer = 4.0
		if _case == "blocked":
			UpgradeDraft.open_draft(slot)
		elif _case == "busy":
			_main._wave_director.reset(_main._wave_director.PHASE_CREST)
			_main._wave_director._budget = _main._wave_director.BUDGET_CAP
	if not await _require("first_boss_really_retired", await _wait_until(func():
			return _death_ms >= 0 and not is_instance_valid(_main._boss), 6)):
		return
	if _baseline or _case in ["blocked", "busy"]:
		_check("normal_wave_has_priority", await _until_active(func():
			return not _normal_births.is_empty(), 5.0), str(_normal_births))
		_check("no_transport_during_ineligible_gap", _launches == 0, "")
		await _finish()
		return
	if not await _require("transport_spawns_once_after_aftermath", await _wait_until(func():
			return is_instance_valid(_ship), 13)):
		return
	var kills_before := GameState.total_kills
	var score_before := GameState.score
	var flight := _ship
	_check("one_cargo_hull_and_fixed_upper_lane", _launches == 1 and _last_hp == 12
		and is_equal_approx(_fixed_y, field.y * 0.26), "id=%d y=%.2f hp=%d at=%.3f" % [_flight_id, _fixed_y, _last_hp, _flight_start])
	if _role != "client":
		_check("launch_after_authority_releases_aftermath", _flight_start >= 1.95 and _flight_start <= 2.2, str(_flight_start))
	var shooter := (_role == "solo" or (_role == "client") == args.has("guest-shoots")) and _case != "pass"
	var start: Vector2 = _pilot.global_position
	_pilot.set_physics_process(true)
	_pilot._combat._shoot_timer = 180.0
	_pilot._motion.handle_mobile_move(Vector2.LEFT)
	var moved := await _until_active(func(): return start.x - _pilot.global_position.x >= 70.0, 0.9)
	_pilot._motion.handle_mobile_move(Vector2.ZERO)
	_check("real_lateral_move_keeps_central_lane_clear", moved and _pilot.global_position.y > _fixed_y + 120,
		"px=%.1f y=%.1f" % [start.x - _pilot.global_position.x, _pilot.global_position.y])
	if not await _require("transport_traverses_under_own_motion", await _until_active(func():
			return is_instance_valid(_ship) and _ship.global_position.x >= 166.0, 2.0)):
		return
	if _case == "withdraw":
		_main._on_elite_spawn_requested()
		var withdrew := await _wait_until(func(): return _completed and is_instance_valid(_main._elite), 3)
		_check("elite_takes_priority_and_transport_exits_once", withdrew and _exit_count == 1
			and _kill_count == 0 and _supply_count == 0 and _launches == 1, "")
		await _finish()
		return
	if _case == "recover":
		if shooter:
			_fire_one(flight, true)
		if not await _require("real_first_cannon_volley_reduces_hull_without_killing", await _until_active(func():
				return is_instance_valid(_ship) and _ship.health < 12 and _ship.health > 0, 1.15)):
			return
		await _rewire(flight)
	if shooter:
		while is_instance_valid(flight) and not flight.is_queued_for_deletion() and _active_seconds - _flight_start < 3.8:
			_fire_one(flight)
			var next_volley := _active_seconds + 0.38
			await _wait_until(func(): return _active_seconds >= next_volley or not is_instance_valid(_ship), 3)
	var ended := await _wait_until(func(): return _completed and not _normal_births.is_empty(), 18)
	_check("transport_resolves_and_normal_wave_advances", ended, "result=%.3f first_normal=%s" % [_finish_time, _normal_births.front() if not _normal_births.is_empty() else {}])
	if _case == "pass":
		_check("natural_exit_passes_opposite_edge_without_reward", _max_x >= field.x and _supply_count == 0
			and (_role == "client" or (_exit_count == 1 and _kill_count == 0)), "max_x=%.1f exit=%d kill=%d supplies=%d" % [_max_x, _exit_count, _kill_count, _supply_count])
	else:
		var supplied := await _wait_until(func(): return _supply_count == 1, 2.0)
		_check("real_intercept_awards_one_existing_supply", supplied and (_role == "client" or (_kill_count == 1 and _exit_count == 0 and _last_hp <= 0)),
			"last_hp=%d exit=%d kill=%d supplies=%d" % [_last_hp, _exit_count, _kill_count, _supply_count])
	_check("kills_score_hull_and_next_wave_stay_independent", GameState.total_kills == kills_before and GameState.score == score_before
		and GameState.get_current_health(slot) >= GameState.START_HEALTH and not _normal_births.is_empty(),
		"kills=%d→%d score=%d→%d hp=%d" % [kills_before, GameState.total_kills, score_before, GameState.score, GameState.get_current_health(slot)])
	var recording := args.has("record")
	var stop := 7.82 if recording else _active_seconds + 0.45
	await _wait_until(func(): return _active_seconds >= stop, 20 if recording else 8)
	_check("no_extra_ship_or_announcement", _launches == 1 and _approach_voices.size() == 1
		and _supply_count <= 1, "launches=%d cues=%d supply=%d" % [_launches, _approach_voices.size(), _supply_count])
	if _case == "recover":
		await _retry_transport()
	await _barrier("done")
	await _finish()


func _open_battle() -> bool:
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	var title := get_tree().current_scene
	if _role == "solo":
		title.get_node("Menu/BtnSingle").pressed.emit()
	else:
		title.get_node("Menu/BtnMultiplayer").pressed.emit()
		await get_tree().scene_changed
		var lobby := get_tree().current_scene
		if _role == "host":
			lobby._btn_be_host.pressed.emit()
			NetworkDiscovery.stop_all()
			if not await _wait_until(func(): return not lobby._btn_start.disabled, 14):
				return false
			lobby._btn_start.pressed.emit()
		else:
			lobby._btn_be_client.pressed.emit()
			HarmonyBridge.report_discovered_host("复跑房间", "127.0.0.1", _port)
			var key := "127.0.0.1:%d" % _port
			if not await _wait_until(func(): return lobby._host_buttons.has(key), 6):
				return false
			lobby._host_buttons[key].pressed.emit()
	return await _wait_until(func():
		var scene := get_tree().current_scene
		return is_instance_valid(scene) and scene.scene_file_path == MAIN_SCENE, 15)


func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_ship) and not _ship.is_queued_for_deletion():
		_max_x = maxf(_max_x, _ship.position.x)
		if _last_hp != _ship.health:
			_log("hull %d→%d x=%.1f t=%.3f" % [_last_hp, _ship.health, _ship.position.x, _active_seconds])
			_last_hp = _ship.health
	if _launches > 0 and not _completed:
		for voice: AudioStreamPlayer in SFX.get_children():
			if voice.playing and voice.stream == SFX.get("_stream_transport_approach"):
				var playback := voice.get_stream_playback()
				if playback:
					_approach_voices[playback.get_instance_id()] = true


func _observe_child(node: Node) -> void:
	if _death_ms < 0:
		return
	if node is Enemy:
		if not _baseline and bool(node.get("is_transport")):
			_ship = node
			_flight_id = node.entity_id
			_launches += 1
			_flight_start = _active_seconds
			_fixed_y = node.position.y
			node.tree_exiting.connect(_transport_finished, CONNECT_ONE_SHOT)
			if _role != "client":
				node.enemy_died.connect(func():
					_kill_count += 1
					_last_hp = node.health
					_log("fatal hull=%d x=%.1f t=%.3f" % [_last_hp, node.position.x, _active_seconds])
					node.die()
					node.retire_transport())
				node.transport_exited.connect(func():
					_exit_count += 1
					node.die())
		else:
			var birth := {"frame": Engine.get_physics_frames() - _death_frame, "active": _active_seconds,
				"type": node.enemy_type, "pos": node.position, "id": node.entity_id}
			_normal_births.append(birth)
			_log("normal_birth %s" % str(birth))
	elif _launches > 0 and node.scene_file_path == "res://scenes/entities/powerup.tscn" and node.get_powerup_type() == "heal":
		_supply_count += 1


func _transport_finished() -> void:
	_finish_time = _active_seconds
	_completed = true


func _fire_one(flight: Node2D, single := false) -> void:
	var origin: Vector2 = flight.global_position
	var aim := origin
	for step in 4:
		var flight_time := _pilot.global_position.distance_to(aim) / GameState.MAIN_CANNON_SPEED
		aim = origin + Vector2.RIGHT * float(flight.move_speed) * flight_time
	var angle := _pilot.global_position.angle_to_point(aim)
	_pilot.rotation = angle + PI * 0.5
	if single:
		_pilot._combat._spawn_bullet(_pilot.global_position + Vector2.from_angle(angle) * 24.0, angle,
			GameState.get_bullet_damage(_pilot.peer_id), true, 1, GameState.MAIN_CANNON_SPEED)
	else:
		_pilot._combat._shoot()
	_log("cannon slot=%d aim=%s hull_at=%s" % [_pilot.peer_id, aim, origin])


func _rewire(flight: Node2D) -> void:
	var recovery: Node = NetworkManager.recovery
	var previous: int = recovery.guest_wire
	var round_id := GameState.get_sync_round()
	await _barrier("hold_transport")
	if _role == "client":
		recovery.set_background(true)
	var held := await _wait_until(func(): return get_tree().paused, 4)
	var held_at: Vector2 = flight.position
	var held_hp: int = flight.health
	await _wait_seconds(0.25)
	_check("hold_preserves_current_hull_and_position", held and flight.position == held_at and flight.health == held_hp, str(held_at))
	if _role == "client":
		NetworkManager.drop_lan_transport()
		recovery.set_background(false)
	var restored := await _wait_until(func():
		return (not get_tree().paused and NetworkManager.is_online()
			and recovery.guest_wire > 1 and recovery.guest_wire != previous), 13)
	_check("same_round_and_entity_after_new_wire", restored and GameState.get_sync_round() == round_id
		and _main._entities.get(_flight_id) == flight and flight.health == held_hp
		and _launches == 1 and _approach_voices.size() == 1, "wire=%d→%d id=%d hp=%d" % [previous, recovery.guest_wire, _flight_id, held_hp])
	await _barrier("transport_restored")


func _retry_transport() -> void:
	await _barrier("retry")
	var old_round := GameState.get_sync_round()
	if _role == "host":
		_main._restart()
	var reset := await _wait_until(func():
		var scene := get_tree().current_scene
		return (is_instance_valid(scene) and scene.scene_file_path == MAIN_SCENE and scene != _main
			and GameState.get_sync_round() > old_round), 8)
	var fresh := get_tree().current_scene
	_check("retry_requires_another_first_boss", reset and fresh._transport_offer == 0
		and not is_instance_valid(fresh._transport), "")
	await _barrier("retry_done")
