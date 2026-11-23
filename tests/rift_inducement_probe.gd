extends "res://tests/boss_coop_probe.gd"

const Trial := preload("res://scripts/rift_route_trial.gd")
const Route := preload("res://scenes/rift_route_trial.tscn")
const TRACK := BossModel.PulsePhase.TRACK

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var mode := args[2] if args.size() > 2 else "solo"
	var solo := mode == "solo"
	var wide_host := mode.ends_with("-host")
	_evidence = args[3] if args.size() > 3 else ""
	var viewport_size := Vector2i(1600, 720) if (_role == "host") == wide_host else Vector2i(960, 720)
	if not solo:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = viewport_size
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if not _require("real_enet", err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)):
			return
	seed(90220)
	var trial := Route.instantiate() as Trial
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	_main = trial
	if not solo:
		if not _require("stable_slots_in_shared_battle", await _wait_until(func():
			return _cond_both_players() and NetworkManager.recovery.is_reserved(), 5)
			and NetworkManager.battle_size(trial) == Vector2(1280, 720)):
			return
		_guest = NetworkManager.recovery.guest_slot
	trial._player.set_physics_process(false)
	trial._player.set_process_unhandled_input(false)
	trial._player._motion.mobile_mode = true
	if not solo:
		await _barrier("pilots_ready")
	if _role != "client":
		trial.trial_tick = Trial.BOSS_LEG - 1
		await get_tree().physics_frame
		await get_tree().physics_frame
		trial._boss._stop_entry_motion()
		trial._boss.global_position = AT
		trial._boss._shoot_timer = 90.0
	if not _require("route_enters_boss", await _wait_until(func(): return is_instance_valid(trial._boss), 4)):
		return
	match mode:
		"solo":
			await _induce("solo", 1, true)
		"rift-outer-burn":
			await _check_outer_burn()
		_:
			# Both candidates must win on actual projectile damage, including twice in a row.
			var first := _guest if wide_host else 1
			await _induce("first", first, false)
			await _recharge()
			await _induce("repeat", first, false)
			await _recharge()
			await _induce("switch", 1 if wide_host else _guest, false)
			await _recharge()
			await _cancel_before_fire()
	if not solo:
		await _barrier("done")
		await _wait_seconds(.22)
	get_tree().quit(_summarize())

func _induce(label: String, target: int, solo: bool) -> void:
	var boss: BossModel = _main._boss
	var pilot: Node2D = _main._player
	var mine: bool = pilot.peer_id == target
	var start := P1_AT if target == 1 else P2_AT
	var away := Vector2.LEFT if target == 1 else Vector2.RIGHT
	var partner := P2_AT if target == 1 else P1_AT
	if _role != "client":
		boss.global_position = AT
		# Keep the arranged collider in place until the staging shot has landed.
		boss.set_physics_process(false)
	if solo:
		pilot.global_position = start
		GameState.set_shield_layers(1, 0)
	else:
		await _arrange(label)
	var shield_at_start := boss.get_shield_hp()
	var pressure_damage := int(boss.get_max_shield_hp() * .74)
	if mine:
		# An amplified fixture shot supplies measurable pressure on the real authority.
		var axis := start.direction_to(AT)
		pilot._combat._spawn_bullet(AT - axis * 62, axis.angle(), pressure_damage, true, 1, 700.0)
	if _role != "client":
		var hit := await _wait_until(func(): return boss.get_shield_hp() < shield_at_start, 1.8)
		_check(label + "_real_pressure_from_expected_slot", hit and (solo or boss._aggro.damage_score(target,
			boss.get_network_max_health() + boss.get_max_shield_hp()) > .6),
			"shield %.1f→%.1f ledger=%s" % [shield_at_start, boss.get_shield_hp(), boss._aggro._recent_damage])
		boss.global_position = AT
		boss._next_attack = 0
		boss._shoot_timer = 0.0
		boss._tick_attack_schedule(0.0)
		boss.set_physics_process(true)
	var tracked := await _wait_until(func(): return _phase() == TRACK, 2.5)
	var cue := boss.coop_pulse_snapshot()
	var name := "P1" if target == 1 else "P2"
	_check(label + "_marker_before_any_beam", tracked and cue.get("marked", false)
		and cue.slot == target and cue.from == Vector2.ZERO and boss.coop_pulse_label() == "瞄准 " + name, str(cue))
	var before_hp := GameState.get_current_health(target)
	var wing_hp := GameState.get_current_health(1 if target != 1 else _guest)
	var before_cover := shield_at_start - pressure_damage
	if mine:
		_steer = away
	else:
		_cover = true
	if label in ["first", "solo"]:
		await _capture(label + "-tracking")
	var locked := await _wait_until(func(): return _phase() == LOCK, .60)
	var lock := boss.coop_pulse_snapshot()
	var axis := Vector2(lock.from).direction_to(lock.to)
	var original_axis := AT.direction_to(start)
	var turned_away := -away.x * rad_to_deg(original_axis.angle_to(axis))
	_check(label + "_lock_follows_early_reposition_with_safe_side", locked and lock.slot == target and lock.get("marked", false)
		and turned_away > 2.5 and (solo or not boss.coop_pulse_contains(partner)),
		"target=%s angle_change=%.2f° from=%s to=%s" % [name, turned_away, lock.from, lock.to])
	if label in ["first", "solo"]:
		await _capture(label + "-locked")
	if mine:
		# Once locked, continue moving away along the closest open axis.
		_steer = axis.orthogonal() * signf(axis.orthogonal().dot(away))
	var fired := await _wait_until(func(): return _phase() == FIRE, .86)
	var active := boss.coop_pulse_snapshot()
	_check(label + "_fired_geometry_is_identical_to_lock", fired and active.from == lock.from and active.to == lock.to
		and active.slot == lock.slot and not active.marked and boss.get_attack_window() == BossModel.AttackWindow.OPEN, str(active))
	if label in ["first", "solo"]:
		await _capture(label + "-fire")
	if solo:
		_cover = true
	await _wait_until(func(): return _phase() == OPEN, .6)
	_steer = Vector2.ZERO
	var countered := await _wait_until(func(): return boss.get_shield_hp() < before_cover, .8)
	_cover = false
	if not solo:
		await _wait_seconds(.14)
	_check(label + "_unhurt_with_real_counterfire", countered and GameState.get_current_health(target) == before_hp
		and (solo or GameState.get_current_health(1 if target != 1 else _guest) == wing_hp),
		"shield %.1f→%.1f target_hp=%d" % [before_cover, boss.get_shield_hp(), GameState.get_current_health(target)])
	if not solo:
		await _barrier(label + "_finished")

func _recharge() -> void:
	var boss: BossModel = _main._boss
	if _role == "host":
		boss._shoot_timer = 90.0
		boss.take_damage(boss.get_shield_hp())
	var open := await _wait_until(func(): return not boss.has_impact_shield(), 1.0)
	var closed := await _wait_until(func(): return boss.has_impact_shield(), 6.0)
	_check("next_real_shield_round", open and closed, str(boss.get_shield_stamp()))
	await _barrier("recharged_%d" % boss.get_shield_stamp())

func _cancel_before_fire() -> void:
	await _arrange("cancel")
	var boss: BossModel = _main._boss
	if _role == "host":
		boss.global_position = AT
		boss._shoot_timer = 0.0
		boss._tick_attack_schedule(0.0)
	var tracked := await _wait_until(func(): return _phase() == TRACK, .6)
	var cue := boss.coop_pulse_snapshot()
	var old_wire: int = NetworkManager.recovery.guest_wire
	await _barrier("cancel_marked")
	if _role == "client":
		NetworkManager.recovery.set_background(true)
		await _wait_seconds(.06)
		_main._entities.erase(boss.entity_id)
		boss.queue_free()
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var resumed := await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != old_wire
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13)
	var restored: BossModel = _main._boss
	_check("new_enet_connection_restores_same_target_marker", resumed and is_instance_valid(restored)
		and restored.coop_pulse_snapshot() == cue, "old=%d new=%d" % [old_wire, NetworkManager.recovery.guest_wire])
	await _barrier("cancel_resumed")
	if _role == "host":
		boss.take_damage(boss.get_shield_hp(), 1)
	var cancelled := await _wait_until(func(): return _phase() == OPEN and is_instance_valid(restored) and not restored.has_impact_shield(), .5)
	_check("shield_break_removes_target_marker_without_firing", tracked and cancelled and not restored.coop_pulse_snapshot().marked, "")

func _check_outer_burn() -> void:
	var boss: BossModel = _main._boss
	var pilot: Node2D = _main._player
	var side := 1.0 if _role == "host" else -1.0
	pilot.global_position = Vector2(640 + side * 59, 455)
	pilot._invincible_timer = 0.0
	if _role == "host":
		GameState.set_shield_layers(1, 0)
		GameState.set_shield_layers(_guest, 0)
	await _barrier("burn_outside")
	if _role == "host":
		if not await _wait_until(func(): return _main._players[_guest].global_position.distance_to(Vector2(581, 455)) < .5, 2.0):
			_check("host_received_outside_position", false, str(_main._players[_guest].global_position))
		boss.global_position = AT
		boss._start_ultimate_laser()
		# Fixed vertical beam gives both pilots the same distance from its axis.
		boss._laser_locked_direction = Vector2.DOWN
		boss._ultimate_laser_end = AT + Vector2(0, 1200)
		boss._fire_ultimate_laser()
		boss._ultimate_laser_fire_timer = BossModel.BOSS_ULTIMATE_LASER_HOLD_SECONDS - 0.1
	var id := int(pilot.peer_id)
	var initial := GameState.get_current_health(id)
	var live := await _wait_until(func(): return boss.get_attack_window() >= BossModel.AttackWindow.SWEEP, 1.0)
	await _wait_seconds(.6)
	_check("farther_than_outer_edge_is_safe", live and GameState.get_current_health(id) == initial, "hp=%d at=%s" % [initial, pilot.global_position])
	if _role == "host":
		boss.set_physics_process(false)
	await _barrier("burn_move_inside")
	pilot.global_position = Vector2(640 + side * 39, 455)
	await _barrier("burn_inside")
	if _role == "host":
		var peer: Node2D = _main._players[_guest]
		if not await _wait_until(func(): return peer.global_position.distance_to(Vector2(601, 455)) < .05, 2.0):
			_check("host_received_inside_position", false, str(peer.global_position))
		boss.set_physics_process(true)
	await _barrier("burn_measuring")
	await _wait_seconds(1.5)
	var hp := GameState.get_current_health(id)
	_check("this_pilot_takes_outer_burn_with_both_inside", hp < initial and hp > 0, "slot=%d hp=%d→%d at=%s" % [id, initial, hp, pilot.global_position])
