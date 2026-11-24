extends "res://tests/boss_coop_probe.gd"

const Trial := preload("res://scripts/rift_route_trial.gd")
const Route := preload("res://scenes/rift_route_trial.tscn")
const TRACK := BossModel.PulsePhase.TRACK

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var mode := args[2] if args.size() > 2 else "solo"
	var solo := _role == "solo"
	var wide_host := mode.ends_with("-host") or mode == "rift-outer-burn"
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
		"rift-outer-burn", "rift-outer-burn-mirror", "rift-outer-burn-solo":
			await _check_outer_burn(solo, mode.ends_with("-mirror"))
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

func _check_outer_burn(solo: bool, mirror: bool) -> void:
	var boss: BossModel = _main._boss
	var pilot: Node2D = _main._player
	if _role != "client":
		boss.set_physics_process(false)
		GameState.set_shield_layers(pilot.peer_id, 0)
		pilot._invincible_timer = 0.0
		for player in _main._players.values():
			GameState.set_shield_layers(player.peer_id, 0)
			player._invincible_timer = 0.0
		_start_burn_sample(boss)
	var first := solo or (_role == "host") != mirror
	var host_side := -1.0 if mirror else 1.0
	var own_side := -host_side if _role == "client" else host_side
	var id := int(pilot.peer_id)
	var initial := GameState.get_current_health(id)
	await _burn_sample("outside_59", 30, own_side * 59, -host_side * 59, initial, solo)
	await _burn_sample("both_at_39", 8, own_side * 39, -host_side * 39, initial - 1, solo)
	if _role != "client":
		# Leave a fraction in the old beam and remove player hit immunity to observe even an early tick.
		boss._finish_ultimate_laser()
		_start_burn_sample(boss)
		pilot._invincible_timer = 0.0
		for player in _main._players.values():
			player._invincible_timer = 0.0
	await _burn_sample("new_beam_no_remainder", 5, own_side * (39 if first else 59),
		-host_side * (39 if mirror else 59), initial - 1, solo)
	await _burn_sample("stagger_first_only", 3, own_side * 39, -host_side * 39,
		initial - (2 if first else 1), solo)
	await _burn_sample("stagger_second_catches_up", 5, own_side * 39, -host_side * 39, initial - 2, solo)

func _start_burn_sample(boss: BossModel) -> void:
	boss.global_position = AT
	boss._start_ultimate_laser()
	boss._laser_locked_direction = Vector2.DOWN
	boss._ultimate_laser_end = AT + Vector2(0, 1200)
	boss._fire_ultimate_laser()
	boss._ultimate_laser_fire_timer = BossModel.BOSS_ULTIMATE_LASER_HOLD_SECONDS - 0.1

func _burn_sample(label: String, frames: int, own_offset: float, guest_offset: float, expected: int, solo: bool) -> void:
	var pilot: Node2D = _main._player
	pilot.global_position = Vector2(640 + own_offset, 455)
	if not solo:
		await _barrier(label + "_placed")
	if _role != "client":
		if not solo:
			var at := Vector2(640 + guest_offset, 455)
			var peer: Node2D = _main._players[_guest]
			_check(label + "_host_received_guest_position", await _wait_until(func():
				return peer.global_position.distance_to(at) < .05, 2.0), str(peer.global_position))
		# Step the real laser tick at exactly 60 Hz, independent of transport or wall-clock delay.
		for frame in frames:
			_main._boss._tick_ultimate_laser(1.0 / 60.0)
	if not solo:
		await _barrier(label + "_sampled")
		await _wait_seconds(.23)
	var hp := GameState.get_current_health(pilot.peer_id)
	_check(label, hp == expected, "slot=%d frames=%d hp=%d expected=%d at=%s" %
		[pilot.peer_id, frames, hp, expected, pilot.global_position])
