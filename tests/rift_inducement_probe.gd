extends "res://tests/boss_coop_probe.gd"

const Trial := preload("res://scripts/battle/trials/rift_route_trial.gd")
const Route := preload("res://scenes/rift_route_trial.tscn")
const TRACK := BossModel.PulsePhase.TRACK
const Bullet := preload("res://scripts/battle/projectiles/bullet.gd")
const Mobile := preload("res://scenes/ui/mobile_controls.tscn")
const Palette := preload("res://scripts/visuals/palette.gd")
const DUO_P1_AT := Vector2(490, 355)
const DUO_P2_AT := Vector2(790, 355)
var _flank_impact := Vector2.INF
var _duo_receipts: Array[int] = []
var _duo_frames: Dictionary[String, Image] = {}

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var mode := args[2] if args.size() > 2 else "solo"
	var solo := _role == "solo"
	var wide_host := mode.ends_with("-host") or mode == "rift-outer-burn"
	var baseline := args.has("baseline")
	var duo := mode.begins_with("rift-duo-")
	GameState.rift_remix = duo
	_evidence = args[3] if args.size() > 3 and args[3] != "baseline" else ""
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
	if duo and not solo:
		trial.add_child(Mobile.instantiate())
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	_main = trial
	if not solo:
		if not _require("stable_slots_in_shared_battle", await _wait_until(func():
			return _cond_both_players() and NetworkManager.recovery.is_reserved(), 5)
			and NetworkManager.battle_size(trial) == Vector2(1280, 720)):
			return
		_guest = NetworkManager.recovery.guest_slot
		if duo and not _require("remix_entry_ready", await _wait_until(func(): return trial._player_entry_ready, 1.5)):
			return
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
		"rift-flank-solo", "rift-flank-host", "rift-flank-client", "rift-duo-solo":
			await _flank_matrix(solo, 1 if solo or not wide_host else _guest, baseline)
		"rift-duo-host", "rift-duo-client":
			await _duo_matrix(_guest if wide_host else 1)
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
	for name: String in _duo_frames:
		var output := _evidence.path_join("%s-%s.png" % [name, _role])
		_check(name + "_screenshot", _duo_frames[name].save_png(output) == OK, output)
	get_tree().quit(_summarize())

func _capture(name: String) -> void:
	if not name.begins_with("duo-"):
		await super._capture(name)
		return
	if _evidence.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	# Encode and write PNGs after verification so image I/O cannot consume the lock window.
	_duo_frames[name] = get_viewport().get_texture().get_image()

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
	var resumed := await _reconnect_guest("cancel_marked")
	var restored: BossModel = _main._boss
	_check("new_enet_connection_restores_same_target_marker", resumed and is_instance_valid(restored)
		and restored.coop_pulse_snapshot() == cue, str(cue))
	await _barrier("cancel_resumed")
	if _role == "host":
		boss.take_damage(boss.get_shield_hp(), 1)
	var cancelled := await _wait_until(func(): return _phase() == OPEN and is_instance_valid(restored) and not restored.has_impact_shield(), .5)
	var after := restored.coop_pulse_snapshot()
	_check("shield_break_removes_target_marker_without_firing", tracked and cancelled and not after.marked, "")
	_check("cancelled_pulse_never_opens_flank", after.get("flank", {}) == cue.get("flank", {}), str(after))

func _reconnect_guest(label: String) -> bool:
	var old_wire: int = NetworkManager.recovery.guest_wire
	await _barrier(label)
	if _role == "client":
		var boss: BossModel = _main._boss
		NetworkManager.recovery.set_background(true)
		await _wait_seconds(.06)
		_main._entities.erase(boss.entity_id)
		boss.queue_free()
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	return await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != old_wire
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13)

func _flank_matrix(solo: bool, target: int, baseline: bool) -> void:
	_main.child_entered_tree.connect(_watch_flank_projectile)
	var stand := await _flank_case("stand", solo, target, false, baseline)
	if stand.is_empty():
		return
	if not baseline:
		var boss: BossModel = _main._boss
		var hull := boss.get_network_health()
		if _role != "client":
			boss._shield_hp = 5.0
			_fire_flank_round(Vector2(stand.flank.side) * 24.0 + Vector2(0, 22), 4, true)
		var broken := await _wait_until(func(): return not boss.has_impact_shield(), .56)
		if _role == "client":
			boss.apply_network_coop_pulse(stand)
		_check("weak_round_breaks_shield_and_closes_without_hull_spill", broken and not _flank_active()
			and is_equal_approx(hull, boss.get_network_health()), "shield=%.1f hull=%.1f" %
			[boss.get_shield_hp(), boss.get_network_health()])
		if not solo:
			await _barrier("flank_break_checked")
	await _flank_recharge(solo)
	var second_target := target if solo else (1 if target != 1 else _guest)
	var live := await _flank_case("flank", solo, second_target, true, baseline)
	if live.is_empty() or baseline:
		return
	if not solo:
		await _check_flank_recovery(live)
	else:
		_check("solo_flank_expires", await _wait_until(func(): return not _flank_active(), 1.4), "")
	await _flank_recharge(solo)
	if not solo and not await _check_blocked_lane(target):
		return
	if await _start_flank_pulse("death", solo, target):
		var fired := await _wait_until(func(): return _phase() == FIRE and _flank_active(), 1.6)
		if not solo:
			await _barrier("flank_before_death")
		var victim: BossModel = _main._boss
		var eid := victim.entity_id
		var stale := _main._boss_snapshot(victim) as Dictionary
		if _role != "client":
			# Exercise cleanup while the shield window still exists.
			victim.die()
		var gone := await _wait_until(func(): return not is_instance_valid(_main._boss), 2.0)
		if _role == "client":
			_main._rpc_spawn_boss(eid, 5, 1, stale)
			_main._rpc_sync_boss_pulse(eid, stale.pulse)
		_check("death_retires_open_flank_and_rejects_stale_state", fired and gone and not _flank_active(), "")

func _check_blocked_lane(target: int) -> bool:
	if not await _start_flank_pulse("blocked", false, target):
		return false
	var boss: BossModel = _main._boss
	var closed: Dictionary = boss.coop_pulse_snapshot().flank
	await _barrier("block_lane_after_track")
	if _role == "host":
		var marked: Node2D = _main._players[target]
		var partner: Node2D = _main._players[1 if target != 1 else _guest]
		var previous := partner.global_position
		partner.global_position = AT.lerp(marked.global_position, .8)
		boss._tick_coop_pulse(BossModel.ROUTE_PULSE_AIM_SECONDS + .01)
		partner.global_position = previous
		boss._pulse_used_this_shield = false
	var cancelled := await _wait_until(func(): return _phase() == OPEN, .6)
	_check("unsafe_lane_cancels_without_opening_flank", cancelled and boss.coop_pulse_snapshot().flank == closed, "")
	await _barrier("blocked_lane_checked")
	return true

func _watch_flank_projectile(node: Node) -> void:
	if _role != "client" and node is Bullet:
		var observe := _record_flank_impact.bind(node)
		if not node.body_entered.is_connected(observe):
			node.body_entered.connect(observe)

func _record_flank_impact(body: Node2D, shot: Area2D) -> void:
	if body == _main._boss and shot._is_player_bullet:
		_flank_impact = shot.global_position

func _start_flank_pulse(label: String, solo: bool, target: int) -> bool:
	var boss: BossModel = _main._boss
	var pilot: Node2D = _main._player
	if solo:
		pilot._motion.stop_for_downed()
		pilot.global_position = P1_AT
		pilot._invincible_timer = 0.0
		GameState.set_shield_layers(1, 0)
	else:
		await _arrange(label)
	if _role != "client":
		boss._stop_entry_motion()
		boss.global_position = AT
		# Isolate the attack with the same two starting lines and target on each build.
		boss._aggro = BossModel.AggroLedger.new()
		boss._aggro.record_damage(target, boss.get_network_max_health() * .25)
		boss._next_attack = 0
		boss._shoot_timer = 0.0
		boss._tick_attack_schedule(0.0)
	return _require(label + "_track_has_no_flank", await _wait_until(func(): return _phase() == TRACK, .9)
		and boss.coop_pulse_snapshot().slot == target and not _flank_active())

func _flank_case(label: String, solo: bool, target: int, move: bool, baseline: bool) -> Dictionary:
	if not await _start_flank_pulse(label, solo, target):
		return {}
	var boss: BossModel = _main._boss
	var me := int(_main._player.peer_id)
	var hp := GameState.get_current_health(target)
	var shooter := target if solo or not move else (1 if target != 1 else _guest)
	var wing_hp := GameState.get_current_health(shooter)
	var shield := boss.get_shield_hp()
	var hull := boss.get_network_health()
	var away := Vector2.LEFT if target == 1 else Vector2.RIGHT
	if move and me == target:
		_steer = away
	var locked := await _wait_until(func(): return _phase() == LOCK, .80)
	var lock := boss.coop_pulse_snapshot()
	_check(label + "_lock_has_no_flank", locked and not _flank_active(), str(lock))
	_check(label + "_old_route_or_solo_has_no_duo_window", not boss.has_duo_window() and not lock.has("duo"), "")
	await _capture(label + "-locked")
	if move and me == target:
		# Once the line is fixed, cross it during the warning toward the exposed side.
		_steer = -away
	var fired := await _wait_until(func(): return _phase() == FIRE, 1.10)
	var pulse := boss.coop_pulse_snapshot()
	var flank: Dictionary = pulse.get("flank", {})
	_check(label + "_actual_fire_keeps_locked_geometry", fired and lock.from == pulse.from
		and lock.to == pulse.to and lock.slot == pulse.slot, str(pulse))
	if not _require(label + "_flank_opens_only_on_fire", fired and (baseline or (_flank_active()
		and float(flank.left) > 1.0 and float(flank.left) <= 1.20001))):
		return {}
	_steer = Vector2.ZERO
	var side := Vector2.LEFT if pulse.to.x >= pulse.from.x else Vector2.RIGHT
	var aim := side * 24.0 + Vector2(0, 22) if move else Vector2(0, 25)
	if not baseline:
		_check(label + "_weak_edge_opposite_locked_lane", flank.side == side, str(flank))
	if me == shooter:
		_fire_flank_round(aim, 4)
	await _capture(label + "-fire")
	var expected := 6.0 if move and not baseline else 4.0
	var hit := await _wait_until(func(): return boss.get_shield_hp() <= shield - expected + 0.005, .6)
	var trial := _main as Trial
	if not baseline:
		var spark := await _wait_until(func(): return not trial._flank_sparks.is_empty(), .16)
		_check(label + "_only_qualified_impact_has_flank_spark", spark == move, "")
		if spark:
			await _capture(label + "-hit")
	var health_settled := await _wait_until(func(): return GameState.get_current_health(target) == hp - (0 if move else 10), .45)
	_check(label + "_one_real_shot_and_pilot_hp", hit and health_settled
		and is_equal_approx(shield - boss.get_shield_hp(), expected) and is_equal_approx(hull, boss.get_network_health())
		and (not move or GameState.get_current_health(shooter) == wing_hp),
		"target=%d shooter=%d aim=%s contact=%s shield=%.1f→%.1f hull=%.1f hp=%d→%d" %
		[target, shooter, aim, _flank_impact, shield, boss.get_shield_hp(), hull, hp, GameState.get_current_health(target)])
	if not solo:
		await _barrier(label + "_shot_checked")
	return pulse

func _duo_matrix(favored: int) -> void:
	_main.child_entered_tree.connect(_watch_flank_projectile)
	_main._boss.route_duo_success.connect(func(stamp: int, _marked: int, _wing: int): _duo_receipts.append(stamp))
	var other := _guest if favored == 1 else 1
	await _duo_success_case("first", favored, favored)
	await _recharge()
	var lock := await _duo_success_case("exchanged", other, favored)
	if lock.is_empty():
		return
	var trial := _main as Trial
	var success_stamp := trial._last_duo_success_stamp
	var resumed := await _reconnect_guest("duo_live_reconnect")
	var boss: BossModel = _main._boss
	if _role == "client":
		boss.apply_network_coop_pulse(lock)
	_check("rewire_closes_duo_without_replaying_success", resumed and not boss.has_duo_window()
		and boss._duo_success_left == 0.0 and trial._last_duo_success_stamp == success_stamp, str(boss.coop_pulse_snapshot()))
	await _barrier("duo_recovered")
	await _recharge()
	var missed := await _begin_duo("missed", favored, favored)
	if missed.is_empty():
		return
	var me := NetworkManager.local_player_id()
	var shield := boss.get_shield_hp()
	if me == missed.duo.wing:
		_fire_flank_round(Vector2(0, 25), 4, false, true)
	_check("center_hit_cannot_claim_success", await _wait_until(func():
		return is_equal_approx(shield - boss.get_shield_hp(), 4.0), .40)
		and trial._last_duo_success_stamp == success_stamp, "slot=%d shield=%.1f→%.1f" % [missed.duo.wing, shield, boss.get_shield_hp()])
	await _barrier("duo_center_hit")
	shield = boss.get_shield_hp()
	if me == missed.duo.marked:
		_fire_flank_round(Vector2(missed.duo.side) * 24.0 + Vector2(0, 22), 4, false, true)
	_check("marked_pilot_cannot_claim_early_wing_hit", await _wait_until(func():
		return is_equal_approx(shield - boss.get_shield_hp(), 4.0), .40)
		and _phase() == LOCK and trial._last_duo_success_stamp == success_stamp,
		"slot=%d shield=%.1f→%.1f" % [missed.duo.marked, shield, boss.get_shield_hp()])
	await _barrier("duo_wrong_pilot_hit")
	var expired := await _wait_until(func(): return not boss.has_duo_window() and not boss.has_flank_window(), 2.1)
	_check("missed_window_expires_without_success", expired and trial._last_duo_success_stamp == success_stamp, "")
	# Re-center the moving boss for the late-shot comparison on both peers.
	if _role == "host":
		boss.set_physics_process(false)
		boss.global_position = AT
	_check("same_fixed_contact_for_late_shot", await _wait_until(func(): return boss.global_position.distance_to(AT) < 1.0, .6), "")
	await _barrier("duo_late_contact_ready")
	shield = boss.get_shield_hp()
	if NetworkManager.local_player_id() == missed.duo.wing:
		_fire_flank_round(Vector2(missed.duo.side) * 24.0 + Vector2(0, 22), 4, false, true)
	_check("late_shot_is_ordinary", await _wait_until(func(): return is_equal_approx(shield - boss.get_shield_hp(), 4.0), .65)
		and trial._last_duo_success_stamp == success_stamp, "shield=%.1f→%.1f" % [shield, boss.get_shield_hp()])
	await _barrier("duo_late_checked")
	if _role == "host":
		boss.set_physics_process(true)
	await _recharge()
	var breaking := await _begin_duo("breaking", other, favored)
	if breaking.is_empty():
		return
	var hull := boss.get_network_health()
	if _role == "host":
		boss._shield_hp = 5.0
	await _barrier("duo_break_ready")
	if NetworkManager.local_player_id() == breaking.duo.wing:
		_fire_flank_round(Vector2(breaking.duo.side) * 24.0 + Vector2(0, 22), 4, false, true)
	var broke := await _wait_until(func():
		return not boss.has_impact_shield() and trial._last_duo_success_stamp == int(breaking.duo.stamp), .55)
	_check("wing_break_cancels_pulse_and_never_spills_into_hull", broke and _phase() == OPEN
		and not boss.has_duo_window() and not boss.has_flank_window() and is_equal_approx(hull, boss.get_network_health()),
		"stamp=%d wing=%d shield=%.1f hull=%.1f" % [breaking.duo.stamp, breaking.duo.wing, boss.get_shield_hp(), boss.get_network_health()])
	success_stamp = trial._last_duo_success_stamp
	await _barrier("duo_break_checked")
	var restored := await _wait_until(boss.has_impact_shield, 6.0)
	_check("shield_returns_after_cooperation_break", restored, "")
	await _barrier("duo_break_recharged")
	if (await _begin_duo("downed", favored, favored)).is_empty():
		return
	if _role == "host":
		trial._players[_guest].force_kill()
	_check("downed_partner_closes_cooperation_and_cancels_unsafe_pulse", await _wait_until(func():
		return not boss.has_duo_window() and _phase() == OPEN, .7) and trial._last_duo_success_stamp == success_stamp, "")
	if _role == "host":
		_check("one_pilot_cannot_open_coop_pulse", not boss._try_coop_pulse(), "")
	var previous := trial.get_instance_id()
	var old_round := GameState.get_sync_round()
	await _barrier("duo_down_checked")
	if _role == "host":
		trial.get_node("TrialUI/Options/Buttons/Retry").pressed.emit()
	var retried := await _wait_until(func():
		var current := get_tree().current_scene as Trial
		return is_instance_valid(current) and current.get_instance_id() != previous and current._player_entry_ready, 5.0)
	_check("retry_resets_window_and_success", retried and get_tree().current_scene._last_duo_success_stamp == 0
		and GameState.get_sync_round() > old_round and get_tree().current_scene._boss == null,
		"old_round=%d current_round=%d" % [old_round, GameState.get_sync_round()])
	if retried:
		_main = get_tree().current_scene
		if _role == "host":
			_main.trial_tick = Trial.BOSS_LEG - 1
		var new_boss := await _wait_until(func(): return is_instance_valid(_main._boss), 2.0)
		if _role == "client":
			_main._on_route_packet(1, var_to_bytes([old_round, ["duo_success", success_stamp]]))
		_check("retry_ignores_old_round_success", new_boss and _main._last_duo_success_stamp == 0
			and not _main._boss.has_duo_window() and _main._boss._duo_success_left == 0.0, "")
	if _role == "host":
		_check("exactly_one_authority_receipt_per_hit_window", _duo_receipts.size() == 3
			and _duo_receipts[0] < _duo_receipts[1] and _duo_receipts[1] < _duo_receipts[2], str(_duo_receipts))

func _begin_duo(label: String, expected: int, favored: int) -> Dictionary:
	await _arrange("duo_" + label, DUO_P1_AT, DUO_P2_AT)
	var boss: BossModel = _main._boss
	if _role == "host":
		boss.global_position = AT
		boss._aggro = BossModel.AggroLedger.new()
		boss._aggro.record_damage(favored, boss.get_network_max_health() * .25)
		boss._shoot_timer = 90.0
		boss._try_coop_pulse()
		if label == "first" and not _evidence.is_empty():
			# A real hostile round in open space makes the visual comparison repeatable.
			boss._spawn_enemy_bullet(AT + Vector2(92, 32), PI * .5, 1.0, 125.0, Palette.ENEMY_BULLET_FAST)
	var tracking := await _wait_until(func(): return _phase() == TRACK, .7)
	_check(label + "_tracking_is_unchanged", tracking and not boss.has_duo_window(), "")
	if label == "first":
		await _capture("duo-first-tracking")
	var locked := await _wait_until(func(): return _phase() == LOCK and boss.has_duo_window(), .9)
	if not _require(label + "_duo_starts_only_on_lock", locked):
		return {}
	var lock := boss.coop_pulse_snapshot()
	var wing := _guest if expected == 1 else 1
	var side := Vector2.LEFT if lock.to.x >= lock.from.x else Vector2.RIGHT
	_check(label + "_marked_and_wing_use_stable_slots", lock.slot == expected and lock.duo.marked == expected
		and lock.duo.wing == wing and lock.duo.side == side and float(lock.duo.left) > 1.45
		and float(lock.duo.left) <= BossModel.ROUTE_DUO_SECONDS, str(lock))
	return lock

func _duo_success_case(label: String, expected: int, favored: int) -> Dictionary:
	var lock := await _begin_duo(label, expected, favored)
	if lock.is_empty():
		return {}
	var trial := _main as Trial
	var boss: BossModel = trial._boss
	var target_hp := GameState.get_current_health(expected)
	var target_start: Vector2 = trial._players[expected].global_position
	var me := NetworkManager.local_player_id()
	var previous := trial._last_duo_success_stamp
	var fired := {}
	_watch_duo_fire(expected, target_start, fired)
	var joystick := trial.get_node("MobileControls")
	if not joystick._ui_root.visible:
		var touch := InputEventScreenTouch.new()
		touch.position = Vector2(140, 568)
		touch.pressed = true
		get_viewport().push_input(touch, true)
	if me == expected:
		_steer = Vector2.LEFT if expected == 1 else Vector2.RIGHT
	var phase_label: Label = trial._hud._boss_status_phase
	var phase_seen := await _wait_until(func(): return phase_label.text.contains("打盾"), .18)
	var panel: Rect2 = trial._hud._boss_status_root.get_global_rect()
	_check(label + "_duo_hud_keeps_score_and_touch_controls_clear", phase_seen
		and Trial.SafeArea.for_viewport(get_viewport()).encloses(panel)
		and phase_label.get_minimum_size().x <= phase_label.size.x
		and not panel.intersects(trial._hud._score_label.get_global_rect())
		and joystick._ui_root.visible and not panel.intersects(joystick._base_node.get_global_rect())
		and trial._hud._skill_slots.all(func(slot: Dictionary): return not panel.intersects(slot.button.get_global_rect())), "")
	await _capture("duo-" + label + "-lock")
	var shield := boss.get_shield_hp()
	if me == lock.duo.wing:
		_fire_duo_primary(lock.duo.side)
	var hit := await _wait_until(func():
		return is_equal_approx(shield - boss.get_shield_hp(), 6.0) and trial._last_duo_success_stamp == int(lock.duo.stamp), .55)
	_check(label + "_wing_primary_from_pilot_scores_during_lock", hit and _phase() == LOCK and previous < int(lock.duo.stamp),
		"stamp=%d marked=%d wing=%d shield=%.1f→%.1f contact=%s" %
		[lock.duo.stamp, expected, lock.duo.wing, shield, boss.get_shield_hp(), _flank_impact])
	await _barrier(label + "_wing_hit")
	await _capture("duo-" + label + "-success")
	shield = boss.get_shield_hp()
	var notice_before := boss._duo_success_left
	if _role == "client":
		trial._on_route_packet(1, var_to_bytes([GameState.get_sync_round(), ["duo_success", int(lock.duo.stamp)]]))
		_check(label + "_repeat_receipt_cannot_replay_success", boss._duo_success_left == notice_before, "")
	if me == lock.duo.wing:
		_fire_flank_round(Vector2(lock.duo.side) * 24.0 + Vector2(0, 22), 4, false, true)
	_check(label + "_second_valid_hit_does_not_extend_success", await _wait_until(func():
		return is_equal_approx(shield - boss.get_shield_hp(), 6.0), .55) and boss._duo_success_left < notice_before
		and trial._last_duo_success_stamp == int(lock.duo.stamp), "shield=%.1f→%.1f" % [shield, boss.get_shield_hp()])
	var fired_seen := await _wait_until(func(): return not fired.is_empty(), .85)
	_steer = Vector2.ZERO
	_check(label + "_marked_pilot_moves_out_without_relocking", fired_seen and fired.from == lock.from and fired.to == lock.to
		and fired.moved >= 65.0 and GameState.get_current_health(expected) == target_hp,
		"slot=%d moved=%.1f hull=%d lane=%s→%s" % [expected, fired.get("moved", 0.0), GameState.get_current_health(expected), lock.from, lock.to])
	await _barrier(label + "_locked_lane_checked")
	joystick.cancel_move_touch()
	return lock

func _watch_duo_fire(marked: int, start: Vector2, observed: Dictionary) -> void:
	if await _wait_until(func(): return _phase() == FIRE, .85):
		var pulse: Dictionary = _main._boss.coop_pulse_snapshot()
		observed.merge({"from": pulse.from, "to": pulse.to,
			"moved": start.distance_to(_main._players[marked].global_position)})

func _fire_duo_primary(side: Vector2) -> void:
	var pilot: Node2D = _main._player
	var to_boss: Vector2 = _main._boss.global_position - pilot.global_position
	# Aim the two stock barrels at the edge. With a 36 px aim offset, one round
	# grazes the shield on the lit side and the other passes outside the circle.
	pilot.rotation = to_boss.angle() + PI * .5 + side.x * asin(36.0 / to_boss.length())
	pilot._combat._shoot()

func _fire_flank_round(offset: Vector2, damage: int, splash := false, reliable := false) -> void:
	var pilot: Node2D = _main._player
	var aim: Vector2 = _main._boss.global_position + offset
	var axis := pilot.global_position.direction_to(aim)
	_flank_impact = Vector2.INF
	pilot._combat._spawn_bullet(aim - axis * 58.0, axis.angle(), damage, true, 1, 760.0, reliable)
	if splash:
		# Give only the shield-breaking round the same splash radius as the card.
		var shot := get_tree().get_nodes_in_group("player_bullets").back() as Bullet
		shot._splash_radius = 78.0

func _flank_recharge(solo: bool) -> void:
	if not solo:
		await _recharge()
		return
	var boss: BossModel = _main._boss
	boss._shoot_timer = 90.0
	if boss.has_impact_shield():
		boss.take_damage(boss.get_shield_hp())
	_check("solo_next_shield_round", await _wait_until(boss.has_impact_shield, 5.4), "")

func _flank_active() -> bool:
	return is_instance_valid(_main._boss) and float(_main._boss.coop_pulse_snapshot().get("flank", {}).get("left", 0.0)) > 0.0

func _check_flank_recovery(old_pulse: Dictionary) -> void:
	var pre: Dictionary = _main._boss.coop_pulse_snapshot().flank
	var old_snapshot: Dictionary = _main._boss_snapshot(_main._boss)
	old_snapshot.pulse = old_pulse
	var shield: float = _main._boss.get_shield_hp()
	var resumed := await _reconnect_guest("flank_live_reconnect")
	var boss: BossModel = _main._boss
	var state: Dictionary = boss.coop_pulse_snapshot().get("flank", {})
	_check("reconnect_restores_current_edge_and_remaining_time", resumed and _flank_active()
		and state.stamp == pre.stamp and state.side == pre.side and float(state.left) <= float(pre.left)
		and float(state.left) < 1.18 and is_equal_approx(shield, boss.get_shield_hp()),
		"before=%s resumed=%s shield=%.1f" % [pre, state, boss.get_shield_hp()])
	_check("reconnect_does_not_replay_flank_hit", (_main as Trial)._flank_sparks.is_empty(), "")
	if _role == "client":
		for repeat in 2:
			_main._rpc_spawn_boss(boss.entity_id, 5, boss.get_sprite_variant_id(), old_snapshot)
		var after: Dictionary = boss.coop_pulse_snapshot().flank
		_check("duplicate_window_does_not_extend_or_redamage_shield", float(after.left) <= float(state.left)
			and after.stamp == state.stamp and is_equal_approx(shield, boss.get_shield_hp()), str(after))
	_check("flank_expires_before_next_pulse", await _wait_until(func(): return not _flank_active(), 1.5), "")
	var closed := await _reconnect_guest("flank_closed_reconnect")
	if _role == "client":
		_main._boss.apply_network_coop_pulse(old_pulse)
	_check("expired_flank_stays_closed_after_reconnect_and_replay", closed and not _flank_active(),
		str(_main._boss.coop_pulse_snapshot()))

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
