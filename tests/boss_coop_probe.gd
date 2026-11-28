extends "res://tests/lan_probe.gd"
## 双进程保留实际位移、命中、倒地、重连与奖励。重排每段起始站位及攻击次序以隔离用例。
const BossModel := preload("res://scripts/battle/enemies/boss/boss.gd")
const AT := Vector2(640, 190)
const P1_AT := Vector2(430, 595)
const P2_AT := Vector2(850, 595)
const LOCK := BossModel.PulsePhase.LOCK
const FIRE := BossModel.PulsePhase.FIRE
const OPEN := BossModel.PulsePhase.OPEN
var _boss_id := 0
var _guest := 0
var _peer_steps := {}
var _steer := Vector2.ZERO
var _cover := false
var _shoot_left := 0.0
var _drops := 0
var _evidence := ""
var _cue_playbacks := {"lock": {}, "recharge": {}, "break": {}}


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	_evidence = args[3] if args.size() > 3 else ""
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var ready := err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)
	if not _require("real_enet", ready):
		return
	_enter_main_scene()
	if not _require("pilots_and_lan_recovery", await _wait_until(func(): return _cond_both_players() and NetworkManager.recovery.is_reserved(), 7)):
		return
	_guest = NetworkManager.recovery.guest_slot
	_main._asteroid_timer = 120
	_main._wave_director._cooldown = 120
	_main._player.set_physics_process(false)
	_main._player.set_process_unhandled_input(false)
	_main._player._motion.mobile_mode = true
	_main._spawn_mobile_controls()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main._hud._update_platform_hints()
	var canvas := get_viewport().get_visible_rect()
	_main._hud._layout_in_safe_area(Rect2(canvas.position + Vector2(42, 19), canvas.size - Vector2(67, 41)))
	seed(14813)
	await _barrier("ready")
	if _role == "host":
		_main._spawn_boss(5)
		_main._boss._stop_entry_motion()
		_main._boss.global_position = AT
		_main._boss._shoot_timer = 90.0
	if not _require("boss_entered", await _wait_until(func(): return is_instance_valid(_main._boss), 3)):
		return
	_boss_id = _main._boss.entity_id
	await _evade_and_cover("p1", 1)
	await _evade_and_cover("p2-cover", _guest)
	await _hold_inside()
	await _no_safe_path()
	await _downed_fallback()
	await _shield_window()
	await _recovery_and_death()
	await _barrier("complete")
	await _wait_seconds(0.24)
	get_tree().quit(_summarize())


func _process(_delta: float) -> void:
	for voice: AudioStreamPlayer in SFX.get_children():
		if not voice.playing:
			continue
		var kind := ""
		if voice.stream == SFX._stream_boss_pulse_lock:
			kind = "lock"
		elif voice.stream == SFX._stream_boss_shield_recharge:
			kind = "recharge"
		elif voice.stream == SFX._stream_shield_break:
			kind = "break"
		if not kind.is_empty():
			var playing := voice.get_stream_playback()
			if playing:
				_cue_playbacks[kind][playing.get_instance_id()] = true

func _cue_count(kind: String) -> int:
	return _cue_playbacks[kind].size()


func _physics_process(delta: float) -> void:
	if get_tree().paused or not is_instance_valid(_main) or not is_instance_valid(_main._player):
		return
	var pilot := _main._player as Node2D
	if not _steer.is_zero_approx():
		pilot._motion.handle_mobile_move(_steer)
		pilot._motion.update(delta, 1.0, NetworkManager.battle_size(pilot))
	if _cover and is_instance_valid(_main._boss):
		_shoot_left -= delta
		if _shoot_left <= 0.0:
			pilot.rotation = pilot.global_position.angle_to_point(_main._boss.global_position) + PI * 0.5
			pilot._combat._shoot()
			_shoot_left += GameState.get_shoot_cooldown(pilot.peer_id)


func _arrange(label: String, host_at := P1_AT, guest_at := P2_AT) -> void:
	var pilot := _main._player as Node2D
	pilot._motion.stop_for_downed()
	pilot.global_position = host_at if _role == "host" else guest_at
	pilot._invincible_timer = 0
	pilot._rescue_protected_until = 0
	_steer = Vector2.ZERO
	_cover = false
	_shoot_left = 0.0
	if _role == "host":
		_main._boss._shoot_timer = 90.0
		GameState.set_shield_layers(1, 0)
		GameState.set_shield_layers(_guest, 0)
	await _barrier(label + "_placed")
	if _role == "host":
		var aligned := await _wait_until(func(): return _main._players[_guest].global_position.distance_to(guest_at) < 1.0, 2)
		_check(label + "_host_received_guest_position", aligned, str(_main._players[_guest].global_position))
	await _barrier(label + "_ready")


func _lock_on(label: String, expected: int) -> Dictionary:
	await _arrange(label)
	var boss: BossModel = _main._boss
	var sounds := _cue_count("lock")
	if _role == "host":
		boss.global_position = AT
		boss._pulse_used_this_shield = false # 隔离下一盾轮首招，常规节奏另由实弹矩阵覆盖。
		# 此夹具要固定谁倒地/重连；全招式的自然轮换另由 boss-aggro 验证。
		boss._aggro = BossModel.AggroLedger.new()
		boss._aggro.record_damage(expected, (boss.get_network_max_health() + boss.get_max_shield_hp()) * .10)
		boss._next_attack = 0
		boss._shoot_timer = 0.0
		boss._tick_attack_schedule(0.0)
	var seen := await _wait_until(func(): return _phase() == LOCK, 0.7)
	await get_tree().process_frame
	var cue: Dictionary = boss.coop_pulse_snapshot()
	var origin: Vector2 = cue.from
	var end: Vector2 = cue.to
	var target := P1_AT if expected == 1 else P2_AT
	var wing := P2_AT if expected == 1 else P1_AT
	_check(label + "_same_target_warning_and_clear_side", seen and cue.slot == expected and boss.coop_pulse_contains(target)
		and not boss.coop_pulse_contains(wing) and boss.get_attack_window() == BossModel.AttackWindow.OPEN
		and not boss.has_duo_window() and not cue.has("duo")
		and Vector2(end - origin).normalized().dot(AT.direction_to(target)) > 0.998,
		"slot=%d stamp=%d from=%s to=%s" % [cue.slot, cue.stamp, origin, end])
	var marked := expected == NetworkManager.local_player_id()
	_check(label + "_local_warning_uses_own_pilot_without_caption", boss.first_boss_lock_visible()
		and is_instance_valid(boss.first_boss_local_lock_pilot()) == marked and _threat_text().is_empty() and _boss_rows_clear(),
		"target=%d local=%d cue=%s" % [expected, NetworkManager.local_player_id(), marked])
	if marked:
		await _wait_until(func(): return _cue_count("lock") > sounds, 0.18)
	_check(label + "_lock_sound_only_on_target_once", _cue_count("lock") == sounds + int(marked),
		"sounds=%d→%d target=%s" % [sounds, _cue_count("lock"), marked])
	if expected == 1 and label == "p1":
		var direction := origin.direction_to(end)
		var across := direction.orthogonal()
		var radius := BossModel.COOP_PULSE_RADIUS
		_check("lane_and_rounded_cap_share_damage_boundary",
			boss.coop_pulse_contains(target + across * (radius - 0.5))
			and not boss.coop_pulse_contains(target + across * (radius + 0.5))
			and boss.coop_pulse_contains(end + direction * (radius - 0.5))
			and not boss.coop_pulse_contains(end + direction * (radius + 0.5)), "")
	if label == "p1" or label == "p2-cover":
		await _capture(label + "-warning")
	elif label in ["down", "break", "rewire"]:
		await _barrier(label + "_both_saw_lock")
	return cue


func _evade_and_cover(label: String, target: int) -> void:
	var cue := await _lock_on(label, target)
	var before := GameState.get_current_health(target)
	var shield: float = _main._boss.get_shield_hp()
	var started := Time.get_ticks_msec()
	if NetworkManager.local_player_id() == target:
		_steer = Vector2(cue.from).direction_to(cue.to).orthogonal()
	else:
		_cover = true
	var fired := await _wait_until(func(): return _phase() == FIRE, 1.3)
	var active: Dictionary = _main._boss.coop_pulse_snapshot()
	_check(label + "_fire_keeps_locked_geometry", fired and active.slot == cue.slot
		and active.from == cue.from and active.to == cue.to, str(active))
	_check(label + "_fire_clears_lock_marker", not _main._boss.first_boss_lock_visible() and _threat_text().is_empty(), "")
	var stopped := await _wait_until(func(): return _phase() == OPEN, 0.6)
	_steer = Vector2.ZERO
	_cover = false
	# 同一批已飞出的侧翼主炮可能在脉冲结束后才到舰体。两端都等实弹结算。
	var hit := await _wait_until(func(): return _main._boss.get_shield_hp() < shield, 0.6)
	var at: Vector2 = _main._players[target].global_position
	var closest := Geometry2D.get_closest_point_to_segment(at, cue.from, cue.to)
	var shift := at.distance_to(P1_AT if target == 1 else P2_AT)
	_check(label + "_marked_evades_and_wing_lands_real_shots", stopped and hit and shift >= 76.0
		and closest.distance_to(at) > BossModel.COOP_PULSE_RADIUS
		and GameState.get_current_health(target) == before,
		"shield %.1f→%.1f hp=%d shift=%.1f observed_ms=%d" % [shield, _main._boss.get_shield_hp(),
			GameState.get_current_health(target), shift, Time.get_ticks_msec() - started])
	await _barrier(label + "_done")


func _hold_inside() -> void:
	var cue := await _lock_on("p2", _guest)
	var before := GameState.get_current_health(_guest)
	var side_hp := GameState.get_current_health(1)
	var fired := await _wait_until(func(): return _phase() == FIRE, 1.3)
	var active: Dictionary = _main._boss.coop_pulse_snapshot()
	_check("p2_fire_keeps_locked_geometry", fired and active.from == cue.from and active.to == cue.to and active.slot == _guest, str(active))
	_check("ordinary_pulse_has_no_flank_window", fired and not active.has("flank"), str(active))
	await _wait_until(func(): return _phase() == OPEN, 0.6)
	var hurt := await _wait_until(func(): return GameState.get_current_health(_guest) < before, 0.6)
	_check("stationary_p2_takes_one_pulse_p1_safe", hurt and GameState.get_current_health(_guest) == before - int(BossModel.COOP_PULSE_DAMAGE)
		and GameState.get_current_health(1) == side_hp, str([before, GameState.get_current_health(_guest), side_hp, GameState.get_current_health(1)]))
	await _barrier("p2_done")

func _no_safe_path() -> void:
	await _arrange("overlap", P1_AT, P1_AT)
	if _role == "host":
		_main._boss.global_position = AT
		_check("overlapping_pilots_cannot_start_pulse", not _main._boss._try_coop_pulse(), "")
	await _barrier("overlap_attempted")
	_check("no_marker_without_real_lock", _phase() == OPEN and not _main._boss.first_boss_lock_visible(), "")
	await _barrier("overlap_checked")


func _downed_fallback() -> void:
	var cue := await _lock_on("down", 1)
	if _role == "host":
		_main._players[1].force_kill()
	var down := await _wait_until(func(): return GameState.rescue_peer_id == 1 and _phase() == OPEN, 0.55)
	_check("downed_cancels_unfired_pulse", down and _main._boss.coop_pulse_snapshot().stamp == cue.stamp + 1, "")
	_check("downed_clears_lock_marker", not _main._boss.first_boss_lock_visible(), "")
	if _role == "host":
		var boss: BossModel = _main._boss
		boss._shoot_timer = 0.0
		boss._next_attack = 2
		boss._tick_attack_schedule(0.0)
		_check("one_pilot_gets_aimed_fallback_instead_of_new_laser", boss.get_attack_window() == BossModel.AttackWindow.OPEN
			and get_tree().get_nodes_in_group("enemy_bullets").size() > 0, "")
	await _barrier("down_checked")
	if _role == "client":
		_main._player.global_position = GameState.rescue_position + Vector2(30, 24)
	var rescued := await _wait_until(func(): return GameState.rescue_peer_id == 0 and GameState.rescues_left == 2, 2.0)
	_check("real_rescue_after_cancelled_lane", rescued, str(GameState.rescues_left))
	await _barrier("rescue_done")
	# Main._player 曾切到存活队友，按本机槽位继续准备。
	_main._player = _main._players[NetworkManager.local_player_id()]
	_main._player.set_physics_process(false)

func _shield_window() -> void:
	var cue := await _lock_on("break", 1)
	var break_sounds := _cue_count("break")
	var recharge_sounds := _cue_count("recharge")
	if _role == "host":
		_cannon(ceili(_main._boss.get_shield_hp()))
	var broken := await _wait_until(func(): return not _main._boss.has_impact_shield() and _phase() == OPEN, 0.65)
	if _role == "host":
		_main._boss._shoot_timer = 90.0
	_check("actual_cannon_break_cancels_unfired_pulse", broken and _main._boss.coop_pulse_snapshot().stamp == cue.stamp + 1
		and not _main._boss.first_boss_lock_visible(), str(_main._boss.coop_pulse_snapshot()))
	await _capture("shield-break")
	await _wait_seconds(1.05)
	_check("exposed_keeps_empty_shield_and_no_caption", _main._boss.is_shield_exposed()
		and _main._hud._boss_shield_fill.size.x == 0.0 and _main._hud._boss_status_phase.text.is_empty()
		and _cue_count("break") == break_sounds + 1 and _boss_rows_clear(), _main._hud._boss_status_phase.text)
	await _capture("exposed")
	var exposed_stamp: int = _main._boss.get_shield_stamp()
	var restored := await _rewire("exposed")
	if _role == "host":
		_main._rpc_sync_boss_pulse.rpc(_boss_id, cue)
	await _barrier("exposed_old_lock_sent")
	_check("reconnect_exposed_ignores_old_lock_and_does_not_replay_break", restored and _phase() == OPEN
		and _main._boss.get_shield_stamp() == exposed_stamp and _main._hud._boss_shield_release_left == 0.0
		and _main._hud._boss_status_phase.text.is_empty() and _cue_count("break") == break_sounds + 1
		and not _main._boss.first_boss_lock_visible(), "")
	var recharge := await _wait_until(func(): return _main._boss.is_shield_recharging(), 4.5)
	await get_tree().process_frame
	_check("recharge_keeps_bar_empty_and_has_no_caption", recharge and _main._hud._boss_status_phase.text.is_empty()
		and _main._hud._boss_shield_fill.size.x == 0.0 and _boss_rows_clear(), _main._hud._boss_status_phase.text)
	await _capture("recharge")
	await _wait_until(func(): return _cue_count("recharge") > recharge_sounds, 0.20)
	var recharge_stamp: int = _main._boss.get_shield_stamp()
	var recovered_recharge := await _rewire("recharge")
	_check("reconnect_recharge_rebuilds_phase_without_replaying_sound", recovered_recharge
		and _main._boss.get_shield_stamp() == recharge_stamp and _main._boss.is_shield_recharging()
		and not _main._boss.has_impact_shield() and _cue_count("recharge") == recharge_sounds + 1, "")
	_check("raised_shield_replaces_recharge", await _wait_until(func():
		return _main._boss.has_impact_shield() and _main._hud._boss_status_phase.text.begins_with("护盾 "), 1.5),
		_main._hud._boss_status_phase.text)
	await _barrier("shield_ready")

func _rewire(label: String) -> bool:
	var raw: int = NetworkManager.recovery.guest_wire
	await _barrier(label + "_ready_to_pause")
	if _role == "client":
		NetworkManager.recovery.set_background(true)
	var frozen := await _wait_until(func(): return get_tree().paused, 1.0)
	var cue_running := false
	for voice: AudioStreamPlayer in SFX.get_children():
		cue_running = cue_running or (voice.playing and voice.stream in [
			SFX._stream_shield_break, SFX._stream_boss_shield_recharge, SFX._stream_boss_pulse_lock])
	_check(label + "_hold_hides_warning_and_stops_cue_tails", frozen and not _main._boss.first_boss_lock_visible()
		and not cue_running, "")
	if _role == "client":
		# 让原连接先送达后台消息，房主也能在真正断链前看到冻结。
		await _wait_seconds(0.18)
		_main._boss.queue_free()
		_main._entities.erase(_boss_id)
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	return await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != raw
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13)

func _recovery_and_death() -> void:
	var cue := await _lock_on("rewire", _guest)
	var raw: int = NetworkManager.recovery.guest_wire
	var max_hp: float = _main._boss.get_network_max_health()
	var maximum_shield: float = _main._boss.get_max_shield_hp()
	var old_id: int = _main._players[_guest].get_instance_id()
	var lock_sounds := _cue_count("lock")
	var restored := await _rewire("locked")
	_check("new_wire_keeps_locked_pulse_and_fixed_budget", restored and _main._players[_guest].get_instance_id() == old_id
		and _phase() == LOCK and _main._boss.coop_pulse_snapshot() == cue and _main._boss.get_network_max_health() == max_hp
		and _main._boss.get_max_shield_hp() == maximum_shield and GameState.rescues_left == 2,
		"old=%d new=%d" % [raw, NetworkManager.recovery.guest_wire])
	if not restored:
		return
	var stale := cue.duplicate()
	stale.stamp -= 1
	stale.phase = FIRE
	stale.to += Vector2(120, 0)
	if _role == "host":
		_main._rpc_sync_boss_pulse.rpc(_boss_id, stale)
		_main._rpc_sync_boss_pulse.rpc(_boss_id, cue)
	await _barrier("replayed_lock")
	_check("duplicate_and_older_pulse_do_not_change_restored_lock", _phase() == LOCK
		and _main._boss.coop_pulse_snapshot() == cue, "")
	_check("restore_current_lock_without_replaying_local_sound", _main._boss.first_boss_lock_visible()
		and is_instance_valid(_main._boss.first_boss_local_lock_pilot()) == (_role == "client")
		and _cue_count("lock") == lock_sounds, "")
	get_tree().node_added.connect(func(node: Node):
		if node.scene_file_path == "res://scenes/entities/powerup.tscn":
			_drops += 1)
	var rewards := _reward_count()
	if _role == "host":
		var fired := await _wait_until(func(): return _phase() == FIRE, 1.3)
		var boss: BossModel = _main._boss
		var old_snapshot: Dictionary = _main._boss_snapshot(boss)
		_cannon(ceili(boss.get_shield_hp()))
		var broken := await _wait_until(func(): return not boss.has_impact_shield(), 0.15)
		var was_live := _phase() == FIRE
		boss._health = 1.0
		var hit_tick := [-1]
		var death_tick := [-1]
		var immediate_cleanup := [false]
		boss.boss_died.connect(func():
			death_tick[0] = Engine.get_physics_frames()
			immediate_cleanup[0] = (_main._boss == null and not boss.first_boss_lock_visible()
				and not _main._hud._boss_status_root.visible))
		var round := _cannon(1)
		if is_instance_valid(round):
			round.body_entered.connect(func(body: Node):
				if body == boss:
					hit_tick[0] = Engine.get_physics_frames())
		var died := await _wait_until(func(): return not is_instance_valid(_main._boss), 0.3)
		_check("live_pulse_stops_on_actual_fatal_collision", fired and broken and was_live and died
			and hit_tick[0] >= 0 and death_tick[0] == hit_tick[0] and immediate_cleanup[0],
			"hit_tick=%d death_tick=%d cleaned=%s" % [hit_tick[0], death_tick[0], immediate_cleanup[0]])
		_main._rpc_spawn_boss.rpc(_boss_id, 5, 1, old_snapshot)
		_main._rpc_sync_boss_pulse.rpc(_boss_id, old_snapshot.pulse)
	var cleared := await _wait_until(func(): return not is_instance_valid(_main._boss) and _drops == 6 and _reward_count() == rewards + 1, 3)
	var hp := GameState.get_current_health(_guest)
	await _wait_seconds(0.30)
	_check("death_cleans_lane_rejects_replay_and_rewards_once", cleared and not is_instance_valid(_main._boss)
		and _drops == 6 and _reward_count() == rewards + 1 and GameState.get_current_health(_guest) == hp,
		"drops=%d own_reward_delta=%d" % [_drops, _reward_count() - rewards])
	_check("death_hides_all_boss_status", not _main._hud._boss_status_root.visible and _threat_text().is_empty(), "")


func _cannon(damage: int) -> Area2D:
	var previous := get_tree().get_nodes_in_group("player_bullets")
	_main._players[1]._combat._spawn_bullet(_main._boss.global_position + Vector2(0, 43), -PI * 0.5, damage, true, 1, 900.0)
	for round in get_tree().get_nodes_in_group("player_bullets"):
		if not previous.has(round):
			return round
	return null

func _reward_count() -> int:
	var s := GameState._state(NetworkManager.local_player_id())
	return roundi(float(s.laser_cd_bonus) + int(s.extra_bullet_count) + float(s.extra_damage_bonus) * 0.5 + float(s.move_speed_bonus) * 10.0)

func _phase() -> int:
	return int(_main._boss.coop_pulse_snapshot().phase) if is_instance_valid(_main._boss) else OPEN

func _threat_text() -> String:
	var label := _main._hud.get("_boss_attack_label") as Label
	return label.text if is_instance_valid(label) and label.is_visible_in_tree() else ""

func _boss_rows_clear() -> bool:
	var hud = _main._hud
	var panel: Rect2 = hud._boss_status_root.get_global_rect()
	if not hud._safe_rect.encloses(panel) or panel.intersects(hud._local_pilot.get_global_rect()) \
			or panel.intersects(hud._wingman.get_global_rect()) or panel.intersects(hud._skill_bar.get_global_rect()) \
			or (hud._draft_panel.visible and panel.intersects(hud._draft_panel.get_global_rect())):
		return false
	for score: Label in hud._score_rows:
		if score.visible and panel.intersects(score.get_global_rect()):
			return false
	var threat := hud.get("_boss_attack_label") as Label
	if is_instance_valid(threat) and threat.is_visible_in_tree():
		var caption := threat.get_global_rect()
		var hull: Rect2 = hud._boss_status_label.get_global_rect()
		var shield: Rect2 = hud._boss_status_phase.get_global_rect()
		var clear := not caption.intersects(hull) and not caption.intersects(shield) and caption.size.x >= threat.get_minimum_size().x
		if not clear:
			print("[BOSS HUD] hull=%s threat=%s minimum=%s shield=%s" % [hull, caption, threat.get_minimum_size(), shield])
		return clear
	return true

func _capture(name: String) -> void:
	if _evidence.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var output := _evidence.path_join("%s-%s.png" % [name, _role])
	_check(name + "_screenshot", get_viewport().get_texture().get_image().save_png(output) == OK, output)

func _require(label: String, ok: bool) -> bool:
	_check(label, ok, "")
	if not ok:
		get_tree().quit(_summarize())
	return ok

func _barrier(label: String) -> void:
	if _role == "host":
		_host_at.rpc(label)
	else:
		_guest_at.rpc_id(1, label)
	if not await _wait_until(func(): return _peer_steps.has(label), 5.0):
		_check("peer_" + label, false, "timeout")

@rpc("authority", "reliable", "call_remote")
func _host_at(label: String) -> void:
	_peer_steps[label] = true

@rpc("any_peer", "reliable", "call_remote")
func _guest_at(label: String) -> void:
	if not multiplayer.is_server():
		return
	_peer_steps[label] = true
