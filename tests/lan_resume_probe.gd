extends "res://tests/lan_probe.gd"
## 两个真实 ENet 实例。只用外部标记协调断链前后的测试时机。

const HOME := Vector2(420, 430)
const WING := Vector2(960, 566)
const REVIVE_AT := Vector2(650, 570)
const Boss = preload("res://scripts/battle/enemies/boss/boss.gd")
const MARKED_SHOT_SPEED := 47.0
var _directory: String
var _scenario: String
var _slot := 0
var _round := 0
var _draft := 0
var _pickup := 0
var _peer_at_start := 0
var _boss_id := 0
var _calibrations := 0


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		get_tree().quit(2)
		return
	_scenario = args[2]
	_directory = args[3]
	if _role == "intruder":
		await _block_outsider()
		return
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var linked := err == OK and await _wait_until(func(): return NetworkManager.is_online() and NetworkManager.connected_peers.size() == 1, 8)
	_check("initial_real_enet", linked, error_string(err))
	if linked:
		GameState.cannon_calibrated.connect(func(): _calibrations += 1)
		_enter_main_scene()
		var ready := await _wait_until(func(): return _cond_both_players() and NetworkManager.recovery.is_reserved(), 6)
		_check("two_known_slots_and_ticket", ready, str(_main._players.keys()))
		if ready:
			_slot = NetworkManager.recovery.guest_slot
			_round = NetworkManager.recovery.round_id
			_peer_at_start = _wire_id()
			_main._asteroid_timer = 120
			_main._wave_director._cooldown = 120
			for pilot in _main._players.values():
				pilot._combat._shoot_timer = 120
			match _scenario:
				"resume-timeout": await _timeout_scenario()
				"resume-exit": await _explicit_exit()
				"resume-quiet": await _silent_process()
				_: await _battle_scenario()
	get_tree().quit(_summarize())


func _process(_delta: float) -> void:
	pass


func _battle_scenario() -> void:
	var staged := await _stage_battle()
	_check("state_ready_rescue_pickup_draft_and_boss", staged, str([GameState.rescues_left, GameState.get_bullet_power_level(_slot)]))
	if not staged:
		return
	await _barrier("staged")
	var actor := "host" if _scenario == "resume-host" else "client"
	await _cycle("short", actor, false)
	await _cycle("rewire", actor, true)
	if not get_tree().paused and NetworkManager.is_online():
		await _exercise_restored_input()
	await _barrier("complete")
	_check("downed_revived_and_rewired_without_replaying_calibration",
		GameState.get_main_cannon_speed() == 900.0 and _calibrations == 1, str(_calibrations))
	_check("rewire_preserves_single_credit_per_enemy", GameState.total_kills == 4
		and GameState.score == 40 and GameState.get_peer_score(_slot) == 40 and GameState.get_peer_score(1) == 0,
		"kills=%d scores=%s" % [GameState.total_kills, GameState.get_all_player_scores()])
	var original: int = _main.get_instance_id()
	if _role == "host":
		_main._restart()
	var restarted := await _wait_until(func():
		var active := get_tree().current_scene
		return (is_instance_valid(active) and active.get_instance_id() != original
			and GameState.get_sync_round() > _round and active._players.size() == 2), 6)
	_check("retry_clears_only_old_round_calibration_and_pending_casts",
		restarted and GameState.get_main_cannon_speed() == 660.0 and _calibrations == 1
		and not GameState.is_cast_pending("skill") and not GameState.is_cast_pending("laser"), str(_calibrations))
	await _barrier("after_retry")
	await _wait_seconds(0.3)


func _stage_battle() -> bool:
	_main._player.global_position = REVIVE_AT + (Vector2(22, 0) if _role == "client" else Vector2.ZERO)
	await _barrier("overlap")
	if _role == "host":
		var near := await _wait_until(func(): return _main._player_target_positions.get(_slot, Vector2.ZERO).distance_to(REVIVE_AT) < 40, 2)
		if not near:
			return false
		_main._players[1].force_kill()
		_check("growth_granted_while_one_pilot_downed", _main._players[1].is_downed, "")
		for i in 4:
			var enemy = _main._spawn_enemy_at(0, Vector2(340 + i * 44, 190), 1, false)
			enemy.die(_slot)
			enemy.die(1)
	if not await _wait_until(func(): return GameState.rescues_left == 2 and GameState.is_player_alive(1), 3):
		return false
	_main._player.global_position = HOME if _role == "host" else WING
	await _barrier("separated")
	if _role == "host":
		var placed := await _wait_until(func(): return _main._player_target_positions.get(_slot, Vector2.ZERO).distance_to(WING) < 1, 3)
		if not placed:
			return false
		GameState.take_damage(9, _slot)
		GameState._state(_slot).skill_cooldown = 19.0
		GameState._state(_slot).laser_cooldown = 15.0
		GameState.apply_card(_slot, "pierce")
		_pickup = _main._next_entity_id
		_main.spawn_boss_fragment("power", WING, _slot)
	if not await _wait_until(func(): return GameState.get_bullet_power_level(_slot) == 2, 3):
		return false
	if _role == "host":
		_main._on_boss_spawn_requested(5)
	var entered := await _wait_until(func(): return is_instance_valid(_main._boss) and _main._boss.global_position.distance_to(Vector2(640, 160)) < 2, 8)
	if not entered:
		return false
	_main._boss.set_physics_process(false)
	_boss_id = _main._boss.entity_id
	await _barrier("boss_parked")
	if _role == "host":
		var boss: Boss = _main._boss
		boss._start_ultimate_laser()
		boss._tick_ultimate_laser(Boss.BOSS_ULTIMATE_LASER_CHARGE + 0.02)
		boss._ultimate_laser_fire_timer = 8.0
		boss._publish_attack_window()
		_main._players[1]._combat._spawn_bullet(Vector2(790, 380), 0.0, 1, false, 1, MARKED_SHOT_SPEED)
		UpgradeDraft.offer_cards(_slot, ["power", "vitality", "shield"])
		GameState.force_sync_to_peer(-1)
	return await _wait_until(func():
		_draft = int(UpgradeDraft.get_draft(_slot).get("id", 0))
		return _draft > 0 and is_instance_valid(_main._boss_laser_visual) and _marked_shot() != null, 3)


func _cycle(label: String, actor: String, drop: bool) -> void:
	var recovery: Node = NetworkManager.recovery
	var my_id := NetworkManager.local_player_id()
	await _barrier(label + "_armed")
	if _role == actor:
		var pilot = _main._players[my_id]
		pilot._motion.touch_move = Vector2.RIGHT
		pilot._action_router.request_action("dash")
		_background(true)
	var paused := await _wait_until(func(): return get_tree().paused and recovery.deadline > 0, 5)
	_check(label + "_frozen_clean_input", paused and _main._players[my_id]._motion.touch_move.is_zero_approx()
		and _main._players[my_id]._action_router._queued_actions.is_empty() and is_instance_valid(_main._lan_message), "")
	if not paused:
		return
	var capture := OS.get_environment("RESUME_CAPTURE_PREFIX")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s-%s-%s.png" % [capture, _role, label])
	var frozen_at: Vector2 = _main._players[my_id].global_position
	var health := GameState.get_current_health(_slot)
	var cd := GameState.get_skill_cooldown(_slot)
	var laser_cd := GameState.get_laser_cooldown(_slot)
	var left := float(UpgradeDraft.get_draft(_slot).left)
	var main_id := _main.get_instance_id()
	var old_wire := _wire_id()
	var old_pilot_id: int = _main._players[_slot].get_instance_id()
	await _barrier(label + "_held")
	if drop:
		if _role == "client":
			# 让快照确实补齐缺失的机体副本和本地待确认选择。
			_main._boss.queue_free()
			_main._entities.erase(_boss_id)
			_main._clear_boss_laser_visual()
			var shot := _marked_shot()
			if shot:
				shot.queue_free()
			UpgradeDraft.get_draft(_slot).pending = true
		if _role == actor:
			NetworkManager.drop_lan_transport()
			_flag("socket_closed")
		else:
			await _wait_flag("socket_closed", 4)
	await _wait_seconds(0.55)
	var current_cd := GameState.get_skill_cooldown(_slot)
	var current_left := float(UpgradeDraft.get_draft(_slot).left)
	_check(label + "_no_progress_while_other_background", get_tree().paused and _main._players[my_id].global_position == frozen_at
		and is_equal_approx(current_cd, cd) and is_equal_approx(current_left, left),
		"paused=%s pos=%s→%s cooldown=%.4f→%.4f draft=%.4f→%.4f" % [get_tree().paused, frozen_at,
			_main._players[my_id].global_position, cd, current_cd, left, current_left])
	if drop and actor == "host" and OS.has_environment("RESUME_WIRE_WHILE_BACKGROUND"):
		# 模拟系统先恢复 UDP 可用性，应用随后才回前台。握手成功也不能解冻。
		if _role == "host":
			NetworkManager.retry_lan_transport()
		var authenticated := await _wait_until(func(): return _wire_id() > 1 and _wire_id() != old_wire, 8)
		_check("new_wire_auth_does_not_unfreeze_background_host", authenticated and get_tree().paused
			and is_equal_approx(GameState.get_skill_cooldown(_slot), cd), "wire=%d" % _wire_id())
	if drop and actor == "client" and _role == actor and OS.has_environment("RESUME_WITH_OUTSIDER"):
		await _wait_flag("outsider_done", 11)
	await _barrier(label + "_before_foreground")
	var started := Time.get_ticks_msec()
	if _role == actor:
		_background(false)
	var restored := await _wait_until(func(): return not get_tree().paused and recovery.deadline == 0 and NetworkManager.is_online(), 16)
	var new_wire := _wire_id()
	_check(label + "_qualified_transport_and_original_nodes", restored and _main.get_instance_id() == main_id
		and _main._players.size() == 2 and _main._players[_slot].get_instance_id() == old_pilot_id
		and new_wire > 1 and (new_wire != _peer_at_start if drop else new_wire == old_wire),
		"original=%d current=%d resume_ms=%d" % [_peer_at_start, new_wire, Time.get_ticks_msec() - started])
	if restored:
		var pilot = _main._players[_slot]
		_check(label + "_authority_full_state_before_play", recovery.round_id == _round and pilot.get_multiplayer_authority() == new_wire
			and _main._players[1].get_multiplayer_authority() == 1 and pilot.global_position.distance_to(WING) < 2
			and GameState.get_current_health(_slot) == health and absf(GameState.get_skill_cooldown(_slot) - cd) < 0.3
			and absf(GameState.get_laser_cooldown(_slot) - laser_cd) < 0.3
			and GameState.rescues_left == 2 and GameState.get_card_stacks(_slot).get("pierce", 0) == 1
			and GameState.get_bullet_power_level(_slot) == 2 and UpgradeDraft.has_draft(_slot)
			and int(UpgradeDraft.get_draft(_slot).id) == _draft and is_instance_valid(_main._boss)
			and _main._boss.entity_id == _boss_id and is_instance_valid(_main._boss_laser_visual)
			and _marked_shot() != null, "")
	await _barrier(label + "_complete")


func _exercise_restored_input() -> void:
	if _role == "host":
		_main._rpc_finish_powerup.rpc(_round, _pickup, "power", WING, _slot, "power", 1)
		_main._rpc_finish_powerup.rpc(_round - 1, _pickup + 80, "power", WING, _slot, "power", 1)
		var old := GameState._to_dict()
		old.round = _round - 1
		old.sequence = GameState.next_sync_sequence()
		old.player_states[str(_slot)].bullet_power_level = 49
		GameState._rpc_sync_game_state.rpc_id(_wire_id(), old)
		GameState.force_sync_to_peer(_wire_id())
	else:
		var shot = _main._players[_slot]
		shot._motion.mouse_vel = Vector2(160, 0)
		UpgradeDraft.choose_card(_slot, 1, "tap")
	var chosen := await _wait_until(func(): return UpgradeDraft.get_draft(_slot).get("chosen", false), 3)
	_check("restored_slot_can_choose_once_and_report_position", chosen and int(UpgradeDraft.get_draft(_slot).get("index", -1)) == 1
		and GameState.get_card_stacks(_slot).get("vitality", 0) == 1 and GameState.get_bullet_power_level(_slot) == 2
		and _main._hud._active_pickup_toasts.is_empty(), str(UpgradeDraft.get_draft(_slot)))
	var advanced := await _wait_until(func(): return _main._players[_slot].global_position.x > WING.x + 5.0, 2)
	_check("new_wire_controls_same_slot", advanced, str(_main._players[_slot].global_position))


func _timeout_scenario() -> void:
	await _barrier("timeout_armed")
	_background(true)
	await _barrier("both_background")
	var deadline: int = NetworkManager.recovery.deadline
	NetworkManager.drop_lan_transport()
	if _role == "client":
		_background(false)
		var timed := await _wait_until(func(): return _main._fallback_in_progress, 23)
		_check("no_reply_expires_real_grace", timed and not get_tree().paused and Time.get_ticks_msec() >= deadline,
			"elapsed_ms=%d" % (Time.get_ticks_msec() - deadline + 20_000))
		_flag("guest_timed_out")
	else:
		await _wait_flag("guest_timed_out", 24)
		_check("both_offline_held_until_foreground", get_tree().paused and not _main._fallback_in_progress, "")
		_background(false)
		_check("expired_host_falls_back_on_foreground", _main._fallback_in_progress and not get_tree().paused, "")
	await _barrier("timeout_complete")


func _explicit_exit() -> void:
	await _barrier("exit_armed")
	var actor := "host" if OS.get_environment("RESUME_EXIT_ACTOR") == "host" else "client"
	if _role == actor:
		NetworkManager.disconnect_network()
		await _wait_flag("exit_seen", 5)
	else:
		var started := Time.get_ticks_msec()
		var gone := await _wait_until(func(): return _main._fallback_in_progress, 3)
		_check("explicit_exit_skips_grace", gone and not get_tree().paused, "ms=%d" % (Time.get_ticks_msec() - started))
		_flag("exit_seen")


func _block_outsider() -> void:
	await _wait_flag("socket_closed", 16)
	await _wait_seconds(6.3)
	var auth := {"seen": false}
	var api := multiplayer as SceneMultiplayer
	# 模拟抵达鉴权层但拿不出原局凭证的加入方。
	api.auth_callback = func(_id: int, _data: PackedByteArray): pass
	api.peer_authenticating.connect(func(_peer: int): auth.seen = true)
	var err := NetworkManager.join_host("127.0.0.1", _port)
	var admitted := await _wait_until(func(): return NetworkManager.connected_peers.has(1), 2)
	_check("unrelated_connection_cannot_enter_battle", err == OK and auth.seen and not admitted, "authenticated_slot=%s auth_attempt=%s" % [admitted, auth.seen])
	NetworkManager.disconnect_network()
	_flag("outsider_done")
	get_tree().quit(_summarize())


func _silent_process() -> void:
	await _barrier("before_silence")
	await _wait_seconds(0.6)
	if _role == "host":
		var pid := FileAccess.open(_directory.path_join("host-pid"), FileAccess.WRITE)
		pid.store_string(str(OS.get_process_id()))
		pid.close()
	else:
		var held := await _wait_until(func(): return get_tree().paused, 8)
		_check("silent_host_detected_by_heartbeat", held, "lifecycle notice was not injected")
	var continued := await _wait_flag("host-continued", 11)
	var resumed := await _wait_until(func(): return not get_tree().paused and NetworkManager.recovery._epoch + NetworkManager.recovery._applied > 0, 8)
	_check("silent_host_resumes_on_same_enet", continued and resumed and _wire_id() == _peer_at_start,
		"old=%d now=%d" % [_peer_at_start, _wire_id()])
	await _barrier("silence_done")
	await _wait_seconds(0.25)


func _wire_id() -> int:
	return NetworkManager.recovery.guest_wire

func _marked_shot() -> Node2D:
	for shot: Node2D in get_tree().get_nodes_in_group("enemy_bullets"):
		if not shot.is_queued_for_deletion() and is_equal_approx(shot._speed, MARKED_SHOT_SPEED):
			return shot
	return null

func _background(value: bool) -> void:
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED if value else NOTIFICATION_APPLICATION_RESUMED)

func _flag(file: String) -> void:
	var marker := FileAccess.open(_directory.path_join(file), FileAccess.WRITE)
	if marker:
		marker.store_string("ready")

func _wait_flag(file: String, seconds: float) -> bool:
	return await _wait_until(func(): return FileAccess.file_exists(_directory.path_join(file)), seconds)

func _barrier(label: String) -> void:
	_flag(label + "-" + _role)
	var ready := await _wait_flag(label + "-" + ("client" if _role == "host" else "host"), 8)
	if not ready:
		_check("barrier_" + label, false, "other process did not reach this checkpoint")
