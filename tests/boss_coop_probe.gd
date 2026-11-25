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
	await _evade_and_cover()
	await _hold_inside()
	await _downed_fallback()
	await _recovery_and_death()
	await _barrier("complete")
	await _wait_seconds(0.24)
	get_tree().quit(_summarize())


func _process(_delta: float) -> void:
	pass


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
	if _role == "host":
		boss.global_position = AT
		boss._pulse_used_this_shield = false # 隔离下一盾轮首招，常规节奏另由实弹矩阵覆盖。
		# 此夹具要固定谁倒地/重连；全招式的自然轮换另由 boss-aggro 验证。
		boss._aggro = BossModel.AggroLedger.new()
		boss._aggro.record_damage(expected, (boss.get_network_max_health() + boss.get_max_shield_hp()) * .10)
		boss._next_attack = 0
		boss._shoot_timer = 0.0
		boss._tick_attack_schedule(0.0)
	var seen := await _wait_until(func(): return _phase() == LOCK and _main._hud._boss_status_phase.text.contains("锁定 P1" if expected == 1 else "锁定 P2"), 0.7)
	var cue: Dictionary = boss.coop_pulse_snapshot()
	var origin: Vector2 = cue.from
	var end: Vector2 = cue.to
	var target := P1_AT if expected == 1 else P2_AT
	var wing := P2_AT if expected == 1 else P1_AT
	_check(label + "_same_target_warning_and_clear_side", seen and cue.slot == expected and boss.coop_pulse_contains(target)
		and not boss.coop_pulse_contains(wing) and boss.get_attack_window() == BossModel.AttackWindow.OPEN
		and not boss.has_duo_window() and not cue.has("duo")
		and Vector2(end - origin).normalized().dot(AT.direction_to(target)) > 0.998,
		"slot=%d stamp=%d from=%s to=%s hud=%s" % [cue.slot, cue.stamp, origin, end, _main._hud._boss_status_phase.text])
	if expected == 1 and label == "p1":
		var direction := origin.direction_to(end)
		var across := direction.orthogonal()
		var radius := BossModel.COOP_PULSE_RADIUS
		_check("lane_and_rounded_cap_share_damage_boundary",
			boss.coop_pulse_contains(target + across * (radius - 0.5))
			and not boss.coop_pulse_contains(target + across * (radius + 0.5))
			and boss.coop_pulse_contains(end + direction * (radius - 0.5))
			and not boss.coop_pulse_contains(end + direction * (radius + 0.5)), "")
	await _capture(label + "-warning")
	return cue


func _evade_and_cover() -> void:
	var cue := await _lock_on("p1", 1)
	var before := GameState.get_current_health(1)
	var shield: float = _main._boss.get_shield_hp()
	if _role == "host":
		_steer = Vector2(cue.from).direction_to(cue.to).orthogonal()
	else:
		_cover = true
	var fired := await _wait_until(func(): return _phase() == FIRE, 1.3)
	await _capture("p1-fire")
	var active: Dictionary = _main._boss.coop_pulse_snapshot()
	_check("p1_fire_keeps_locked_geometry", fired and active.slot == cue.slot and active.from == cue.from and active.to == cue.to, str(active))
	var stopped := await _wait_until(func(): return _phase() == OPEN, 0.6)
	_steer = Vector2.ZERO
	_cover = false
	if _role == "client":
		await _wait_until(func(): return _main._boss.get_shield_hp() < shield, 0.5)
	var p1_at: Vector2 = _main._players[1].global_position
	var closest := Geometry2D.get_closest_point_to_segment(p1_at, cue.from, cue.to)
	_check("p1_evades_with_movement_p2_lands_real_shots", stopped and p1_at.distance_to(P1_AT) >= 76.0
		and closest.distance_to(p1_at) > BossModel.COOP_PULSE_RADIUS
		and GameState.get_current_health(1) == before and _main._boss.get_shield_hp() < shield,
		"shield %.1f→%.1f hp=%d" % [shield, _main._boss.get_shield_hp(), GameState.get_current_health(1)])
	await _barrier("p1_done")


func _hold_inside() -> void:
	var cue := await _lock_on("p2", _guest)
	var before := GameState.get_current_health(_guest)
	var side_hp := GameState.get_current_health(1)
	var fired := await _wait_until(func(): return _phase() == FIRE, 1.3)
	await _capture("p2-fire")
	var active: Dictionary = _main._boss.coop_pulse_snapshot()
	_check("p2_fire_keeps_locked_geometry", fired and active.from == cue.from and active.to == cue.to and active.slot == _guest, str(active))
	_check("ordinary_pulse_has_no_flank_window", fired and not active.has("flank"), str(active))
	await _wait_until(func(): return _phase() == OPEN, 0.6)
	var hurt := await _wait_until(func(): return GameState.get_current_health(_guest) < before, 0.6)
	_check("stationary_p2_takes_one_pulse_p1_safe", hurt and GameState.get_current_health(_guest) == before - int(BossModel.COOP_PULSE_DAMAGE)
		and GameState.get_current_health(1) == side_hp, str([before, GameState.get_current_health(_guest), side_hp, GameState.get_current_health(1)]))
	await _barrier("p2_done")


func _downed_fallback() -> void:
	var cue := await _lock_on("down", 1)
	if _role == "host":
		_main._players[1].force_kill()
	var down := await _wait_until(func(): return GameState.rescue_peer_id == 1 and _phase() == OPEN, 0.55)
	_check("downed_cancels_unfired_pulse", down and _main._boss.coop_pulse_snapshot().stamp == cue.stamp + 1, "")
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


func _recovery_and_death() -> void:
	var cue := await _lock_on("rewire", _guest)
	var raw: int = NetworkManager.recovery.guest_wire
	var max_hp: float = _main._boss.get_network_max_health()
	var maximum_shield: float = _main._boss.get_max_shield_hp()
	var old_id: int = _main._players[_guest].get_instance_id()
	await _barrier("ready_to_pause")
	if _role == "client":
		NetworkManager.recovery.set_background(true)
		await _wait_seconds(0.15)
		_main._boss.queue_free()
		_main._entities.erase(_boss_id)
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var restored := await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != raw
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13)
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
		var fatal_tick := Engine.get_physics_frames()
		_cannon(1)
		var died := await _wait_until(func(): return not is_instance_valid(_main._boss), 0.3)
		_check("live_pulse_stops_on_actual_fatal_collision", fired and broken and was_live and died
			and Engine.get_physics_frames() - fatal_tick <= 4, "ticks=%d" % (Engine.get_physics_frames() - fatal_tick))
		_main._rpc_spawn_boss.rpc(_boss_id, 5, 1, old_snapshot)
		_main._rpc_sync_boss_pulse.rpc(_boss_id, old_snapshot.pulse)
	var cleared := await _wait_until(func(): return not is_instance_valid(_main._boss) and _drops == 6 and _reward_count() == rewards + 1, 3)
	var hp := GameState.get_current_health(_guest)
	await _wait_seconds(0.30)
	_check("death_cleans_lane_rejects_replay_and_rewards_once", cleared and not is_instance_valid(_main._boss)
		and _drops == 6 and _reward_count() == rewards + 1 and GameState.get_current_health(_guest) == hp,
		"drops=%d own_reward_delta=%d" % [_drops, _reward_count() - rewards])


func _cannon(damage: int) -> void:
	_main._players[1]._combat._spawn_bullet(_main._boss.global_position + Vector2(0, 43), -PI * 0.5, damage, true, 1, 900.0)

func _reward_count() -> int:
	var s := GameState._state(NetworkManager.local_player_id())
	return roundi(float(s.laser_cd_bonus) + int(s.extra_bullet_count) + float(s.extra_damage_bonus) * 0.5 + float(s.move_speed_bonus) * 10.0)

func _phase() -> int:
	return int(_main._boss.coop_pulse_snapshot().phase) if is_instance_valid(_main._boss) else OPEN

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
