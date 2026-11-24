extends "res://tests/lan_probe.gd"
## 同一场景可检查单人碰撞、真实 ENet 双端和死亡回调内的换场边界。
const BURST = preload("res://scripts/shield_shatter_burst.gd")
const POWERUP = preload("res://scenes/entities/powerup.tscn")
const TARGET := Vector2(608, 270)
const ITEMS := ["core", "heal", "speed", "power", "core", "heal"]
const BossModel = preload("res://scripts/boss.gd")
const LaserModel = preload("res://scripts/boss_ultimate_laser_visual.gd")
const HitModel = preload("res://scripts/hit_effect.gd")

var bursts: Array[int] = []
var release_cues := 0
var first_break_frame := -1
var first_warning_frame := -1
var first_raised_frame := -1
var beam_overlapping_volleys := 0
var contacts := {}
var boss_playbacks := {}
var authority_release_at := Vector2.INF
var snapshot_roundtrips := 0
var drops: Array[int] = []
var birth_positions: Array[Vector2] = []
var recording := false
var collected: Array[String] = []
var deaths := 0
var health_at_death := 0.0
var shot_hit := false
var client_stage := -1
var origin := TARGET
var reward_before := {}
var p2 := 0
var p2_speed := 0
var fatal_frame := -1
var death_frame := -1
var explosions := 0
var stale_probe_done := -1

func _run() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1280, 720)
	if _role in ["host", "client"]:
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if not _require("connected", err == OK and await _wait_until(NetworkManager.is_online, 8.0)):
			return
	_enter_main_scene()
	if NetworkManager.is_online() and not _require("both_pilots", await _wait_until(_cond_both_players, 8.0)):
		return
	_main._player.set_physics_process(false)
	# 先观察出生，再让两端分别拾取。幽灵机的感应圈也能提前触发磁吸。
	for player in _main._players.values():
		player.get_node("PickupArea").monitoring = false
	if _role != "host":
		_main.position = Vector2(69, 37)
	get_tree().node_added.connect(_observe)
	GameState.powerup_collected.connect(func(kind): collected.append(kind))
	for id in GameState.get_alive_player_ids():
		reward_before[id] = _reward_count(id)
	if NetworkManager.is_online():
		p2 = NetworkManager.connected_peers[0] if _role == "host" else multiplayer.get_unique_id()
		p2_speed = GameState.get_shoot_speed_level(p2)
		_check("starts_in_cruise", await _wait_until(_presentation.bind(false), 3), "")
		var callsign: Label = _main._hud._local_pilot.get_node("Rows/Callsign")
		_check("local_pilot_slot", callsign.text == ("P1 ━ 本机" if _role == "host" else "P2 ═ 本机"), callsign.text)
		if _role == "client":
			_ack.rpc_id(1, 0)
		elif not _require("both_peers_in_cruise_before_boss", await _wait_until(func(): return client_stage >= 0, 5)):
			return
	if OS.get_cmdline_user_args().has("boss-kill"):
		await _beam_kill_matrix()
		if _role == "client":
			await _wait_seconds(0.25)
		get_tree().quit(_summarize())
		return
	if _role != "client":
		_main._spawn_boss(5)
	if not _require("boss_in_tree", await _wait_until(func(): return is_instance_valid(_main._boss), 5)):
		return
	if NetworkManager.is_online():
		_check("boss_background_and_music", await _wait_until(_presentation.bind(true), 3), "")
		if _role == "client":
			BGM.stop_bgm()
			_main._backdrop.set_boss_mode(false)
			_main._request_player_sync.rpc_id(1)
			_check("player_snapshot_restores_active_stage", await _wait_until(_presentation.bind(true), 3), "")
	_boss = _main._boss
	if _role != "client":
		_boss.set_physics_process(false)
	_boss.shield_released.connect(func():
		release_cues += 1
		if release_cues == 1:
			first_break_frame = Engine.get_physics_frames())
	if _role in ["bomb", "game-over", "scene-exit", "finishing-beam"]:
		await _alternate_death()
	elif await _shield_cycle():
		await _shoot_and_collect()
	_check("no_orphan_shards", _orphan_shards() == 0, str(_orphan_shards()))
	if NetworkManager.is_online() and _role in ["host", "client"]:
		await _retry_and_leave()
	get_tree().quit(_summarize())

func _require(label: String, value: bool) -> bool:
	_check(label, value, "")
	if not value:
		get_tree().quit(1)
	return value

func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_boss):
		return
	for node in Pool._active:
		if node is HitModel:
			contacts[node._tint] = true
	for voice: AudioStreamPlayer in SFX.get_children():
		if not voice.playing:
			continue
		var label := ""
		if voice.stream == SFX._stream_shield_break:
			label = "break"
		elif voice.stream == SFX._stream_shield_hit:
			label = "shield"
		elif SFX._hit_streams.has(voice.stream):
			label = "hull"
		if not label.is_empty():
			var playback := voice.get_stream_playback()
			if playback:
				if not boss_playbacks.has(label):
					boss_playbacks[label] = {}
				boss_playbacks[label][playback.get_instance_id()] = true

func _physics_process(_delta: float) -> void:
	if first_break_frame < 0 or first_raised_frame >= 0 or not is_instance_valid(_boss):
		return
	if first_warning_frame < 0 and _boss.is_shield_recharging():
		first_warning_frame = Engine.get_physics_frames()
	elif first_warning_frame >= 0 and _boss.has_impact_shield():
		first_raised_frame = Engine.get_physics_frames()

func _observe(node: Node) -> void:
	if node.get_script() == BURST:
		bursts.append(node.get_instance_id())
	elif recording and node.scene_file_path == POWERUP.resource_path:
		drops.append(node.get_instance_id())
		birth_positions.append(node.global_position)
	elif recording and node.scene_file_path == "res://scenes/effects/explosion.tscn":
		explosions += 1
	elif is_instance_valid(_boss) and _boss._ultimate_laser_firing and node.scene_file_path == "res://scenes/entities/bullet.tscn":
		_count_overlapping_volley.call_deferred(node)

func _count_overlapping_volley(node: Node) -> void:
	if is_instance_valid(node) and node.is_in_group("enemy_bullets"):
		beam_overlapping_volleys += 1

func _shield_cycle() -> bool:
	var hull_hp: float = _boss.get_network_health()
	var after_open_hit := hull_hp - 3.0 * BossModel.BOSS_EXPOSED_DAMAGE_MULTIPLIER
	var full_shield: float = _boss.get_max_shield_hp()
	_check("starts_with_a_full_shield_separate_from_hull", _has_boss_shield() and full_shield > 0.0
		and is_equal_approx(full_shield * 7.0, hull_hp), "HP=%.2f shield=%.2f" % [hull_hp, full_shield])
	var old_charge := {}
	if _role != "client":
		await _wait_seconds(1.6)
		_boss.global_position = TARGET
		_boss._rush_cooldown = 100.0
		_boss._dodge_cooldown = 100.0
		_boss.set_physics_process(true)
		_shoot_at_boss(1)
		_check("first_physical_shot_only_hurts_shield", await _wait_until(func():
			return shot_hit and is_equal_approx(_boss.get_shield_hp(), full_shield - 1.0), 1.0)
			and _boss.get_network_health() == hull_hp, "")
		_main._player.global_position = Vector2(640, 655)
	if not _require("laser_charges_at_full_hull", await _wait_until(func():
			return _boss.get_attack_window() == BossModel.AttackWindow.CHARGING, 7.0)):
		return false
	_check("hud_separate_partial_shield_and_full_hull", await _wait_until(func():
		return (_main._hud._boss_status_phase.text.ends_with("激光蓄力")
			and _main._hud._boss_shield_fill.size.x < 500.0
			and _main._hud._boss_status_fill.size.x == 500.0), 0.7), str(_boss.get_shield_hp()))
	if _role == "client":
		_main._player.global_position = Vector2(1100, 620)
		await _restore_laser_stage("charge", LaserModel.VisualMode.CHARGE, 0.20)
		_ack.rpc_id(1, 10)
	else:
		old_charge = _main._boss_snapshot(_boss)
		if _role == "host":
			_check("join_rebuilt_charge_before_break", await _wait_until(func(): return client_stage >= 10, 1.2), "")
		_shoot_at_boss(ceili(full_shield + hull_hp))
	if not _require("physical_break_cancels_unfired_charge", await _wait_until(func():
			return not _has_boss_shield() and _boss.get_attack_window() == BossModel.AttackWindow.OPEN, 2.1)):
		return false
	_check("breaker_does_not_spill_into_hull", _boss.get_network_health() == hull_hp and release_cues == 1
		and not is_instance_valid(_main._boss_laser_visual), "")
	_check("hud_break_keeps_hull_full", await _wait_until(func():
		return (_hud_says("破盾 · 可攻击") and _main._hud._boss_shield_fill.size.x == 0.0
			and _main._hud._boss_status_fill.size.x == 500.0), 0.25), "")
	if _role == "solo" and DisplayServer.get_name() != "headless":
		await _read_pixels(instance_from_id(bursts[0]))
	if _role != "client":
		_shoot_at_boss(3)
		_check("next_real_round_hurts_hull", await _wait_until(func():
			return shot_hit and _boss.get_network_health() < hull_hp, 1.2), "")
		_main._player.global_position = Vector2(640, 655)
	_check("damaged_hull_agrees_on_hud", await _wait_until(func():
		return (is_equal_approx(_boss.get_network_health(), after_open_hit)
			and _main._hud._boss_status_fill.size.x < 500.0), 1.5), str(_boss.get_network_health()))
	_check("warns_before_regenerating", await _wait_until(func():
		return _boss.is_shield_recharging() and _hud_says("即将回盾") and not _has_boss_shield(), 4.0), "")
	if not _require("returns_at_full_shield_without_healing", await _wait_until(func():
			return (_has_boss_shield() and is_equal_approx(_boss.get_shield_hp(), full_shield)
				and is_equal_approx(_boss.get_network_health(), after_open_hit)), 1.4)):
		return false
	if _role != "client":
		var sampled := await _wait_until(func(): return first_raised_frame >= 0, 0.2)
		var open_ticks := first_raised_frame - first_break_frame
		var warning_ticks := first_raised_frame - first_warning_frame
		_check("exposure_270_ticks_warns_last_48", sampled and absi(open_ticks - 270) <= 2
			and absi(warning_ticks - 48) <= 2, "open=%d warning=%d" % [open_ticks, warning_ticks])
	_check("first_shards_expired", bursts.size() == 1 and not is_instance_id_valid(bursts[0]), "")

	if not _require("second_laser_locks_before_fire", await _wait_until(func():
			return (_boss.get_attack_window() == BossModel.AttackWindow.CHARGING
				and not _boss._laser_locked_direction.is_zero_approx()), 6.0)):
		return false
	var locked_aim: Vector2 = _boss._laser_locked_direction
	if _role != "client":
		_main._player.global_position = Vector2(970, 660)
	if not _require("locked_aim_does_not_follow_moving_pilot", await _wait_until(func():
			return (_boss.get_attack_window() == BossModel.AttackWindow.SWEEP
				and is_instance_valid(_main._boss_laser_visual)
				and _main._boss_laser_visual._beam_start.direction_to(_main._boss_laser_visual._beam_end).dot(locked_aim) > 0.9999), 1.5)):
		return false
	if _role == "client":
		if not await _check_mid_beam_snapshot():
			return false
		_ack.rpc_id(1, 11)
	elif _role == "host":
		_check("join_restored_live_shielded_beam", await _wait_until(func(): return client_stage >= 11, 1.7), "")
	var in_flight: LaserModel = _main._boss_laser_visual
	var in_flight_snapshot := {}
	if _role != "client":
		in_flight_snapshot = _main._boss_snapshot(_boss)
		_shoot_at_boss(ceili(full_shield + hull_hp))
	if not _require("physical_break_while_beam_active", await _wait_until(func(): return not _has_boss_shield(), 1.5)):
		return false
	var in_flight_from := in_flight._beam_start
	var in_flight_to := in_flight._beam_end
	_check("open_while_beam_stays_same_node_and_geometry", is_same(in_flight, _main._boss_laser_visual)
		and _faces_laser_beam() and is_equal_approx(_boss.get_network_health(), after_open_hit), "")
	_check("combined_beam_and_shield_state_in_hud", await _wait_until(func():
		return (_main._hud._boss_status_phase.text.begins_with("破盾 · 可攻击 · 激光")
			and _main._hud._boss_shield_fill.size.x == 0.0), 0.22), "")
	if _role == "host":
		var eid: int = _boss.entity_id
		_main._rpc_sync_boss_shield.rpc(eid, _boss.get_shield_stamp(), 0.0, full_shield, _boss.global_position)
		_main._rpc_sync_boss_shield.rpc(eid, in_flight_snapshot.shield_stamp, full_shield, full_shield, _boss.global_position)
		_main._rpc_sync_boss_shield.rpc(eid + 1, _boss.get_shield_stamp() + 1, full_shield, full_shield, _boss.global_position)
		_main._rpc_spawn_boss.rpc(eid, _boss.get_network_level(), _boss.get_sprite_variant_id(), old_charge)
		_main._rpc_spawn_boss.rpc(eid, _boss.get_network_level(), _boss.get_sprite_variant_id(), in_flight_snapshot)
		_report_release_origin.rpc(_boss.global_position)
	if _role == "client":
		_check("duplicate_and_stale_packets_cannot_repair_shield_or_rewind_beam", await _wait_until(func():
			return authority_release_at != Vector2.INF, 0.4) and not _has_boss_shield()
			and is_same(_boss, _main._boss) and is_same(in_flight, _main._boss_laser_visual), "")
		var fx = instance_from_id(bursts.back())
		_check("break_burst_uses_authority_world_position", is_instance_valid(fx)
			and fx.global_position.distance_to(authority_release_at) < 0.1, str(authority_release_at))
		await _restore_laser_stage("open_hull_during_laser", LaserModel.VisualMode.BEAM, 0.2)
		var restored: LaserModel = _main._boss_laser_visual
		_check("open_snapshot_keeps_shield_empty_and_restores_same_geometry", not _has_boss_shield()
			and restored._beam_start.is_equal_approx(in_flight_from) and restored._beam_end.is_equal_approx(in_flight_to), "")
	var axis := in_flight_from.direction_to(in_flight_to)
	if _role != "client":
		var health: int = GameState.get_current_health()
		GameState.set_shield_layers(1, 0)
		_main._player._invincible_timer = 0.0
		_main._player.global_position = in_flight_from + axis * 110.0 + axis.orthogonal() * 37.0
		_check("beam_still_damages_after_shield_break", await _wait_until(func():
			return GameState.get_current_health() < health, 0.85), "")
		_main._player.global_position = in_flight_from + axis * 110.0 + axis.orthogonal() * 128.0
		var hp_after_contact: int = GameState.get_current_health()
		_main._player._invincible_timer = 0.0
		await _wait_seconds(0.18)
		_check("side_of_the_in_flight_beam_is_safe", GameState.get_current_health() == hp_after_contact, "")
	_check("exactly_one_cue_per_broken_cycle", release_cues == 2 and bursts.size() == 2, str(bursts))
	if NetworkManager.is_online():
		await _capture_boss_and_cards()
	if not _require("same_laser_continues_into_hold", await _wait_until(func():
			return _boss.get_attack_window() == BossModel.AttackWindow.HOLD, 4.0)):
		return false
	var hold: LaserModel = _main._boss_laser_visual
	_check("hold_nose_points_along_beam_after_pilot_moves", _faces_laser_beam()
		and hold._beam_start.is_equal_approx(in_flight_from) and hold._beam_end.is_equal_approx(in_flight_to), "")
	if _role == "client":
		await _restore_laser_stage("hold", LaserModel.VisualMode.BEAM, BossModel.BOSS_ULTIMATE_LASER_TRAVEL + 0.18)
		var locked_heading: float = _boss._network_target_rotation
		_boss.apply_network_rotation(_boss.global_rotation + PI * 0.5)
		_check("late_rotation_cannot_steer_firing_boss", _faces_laser_beam()
			and is_equal_approx(_boss._network_target_rotation, locked_heading), "")
	_check("shield_refills_during_the_same_live_beam", await _wait_until(func():
		return _has_boss_shield() and _boss.get_attack_window() == BossModel.AttackWindow.HOLD, 5.0), "")
	if not _require("laser_ends_independently_of_raised_shield", await _wait_until(func():
			return _boss.get_attack_window() == BossModel.AttackWindow.OPEN and _has_boss_shield(), 12.0)):
		return false
	if _role != "client":
		_check("no_new_volleys_while_laser_was_active", beam_overlapping_volleys == 0, str(beam_overlapping_volleys))
	_boss.set_physics_process(false)
	var cooling: LaserModel = _main._boss_laser_visual
	_check("open_replaces_danger_with_cooling", is_instance_valid(cooling) and cooling._mode == LaserModel.VisualMode.COOLING, "")
	await _wait_seconds(0.55)
	_check("cooling_expires_without_extra_shield_release", not is_instance_valid(cooling)
		and not is_instance_valid(_main._boss_laser_visual) and release_cues == 2 and not is_instance_id_valid(bursts[1]), "")
	_check("two_distinct_physical_contact_colors", contacts.has(HitModel.ARMOR) and contacts.has(HitModel.HULL), str(contacts.keys()))
	_check("separate_hit_timbres_and_exactly_two_break_playbacks", boss_playbacks.get("break", {}).size() == 2
		and not boss_playbacks.get("shield", {}).is_empty() and not boss_playbacks.get("hull", {}).is_empty(), str(boss_playbacks.keys()))
	if _role != "client":
		_shoot_at_boss(ceili(_boss.get_max_shield_hp()))
	if not _require("next_shield_can_break", await _wait_until(func(): return not _has_boss_shield(), 1.5)):
		return false
	if _role == "client":
		_ack.rpc_id(1, 6)
	elif _role == "host":
		_check("join_observed_third_cycle", await _wait_until(func(): return client_stage == 6, 2.0), "")
		client_stage = 0
	return true

func _has_boss_shield() -> bool:
	return is_instance_valid(_boss) and _boss.has_impact_shield()

func _faces_laser_beam() -> bool:
	var beam: LaserModel = _main._boss_laser_visual
	if not is_instance_valid(beam) or beam._mode != LaserModel.VisualMode.BEAM:
		return false
	var axis := beam._beam_start.direction_to(beam._beam_end)
	return axis.dot(Vector2.UP.rotated(_boss.global_rotation)) > 0.9999

func _restore_laser_stage(label: String, mode: LaserModel.VisualMode, min_age: float) -> void:
	var ready := await _wait_until(func():
		var visual: LaserModel = _main._boss_laser_visual
		return is_instance_valid(visual) and visual._mode == mode and visual._age >= min_age, 1.0)
	if not ready:
		_check("resnapshot_restores_" + label, false, "stage did not reach sampling age")
		return
	var before: LaserModel = _main._boss_laser_visual
	var before_age := before._age
	var origin := before.global_position
	_main._clear_boss_laser_visual()
	var synced := await _resnapshot()
	var restored: LaserModel = _main._boss_laser_visual
	_check("resnapshot_restores_" + label, synced and is_instance_valid(restored)
		and restored._mode == mode and restored._age >= before_age - 0.10
		and restored.global_position.is_equal_approx(origin), "")

func _check_mid_beam_snapshot() -> bool:
	if not _require("beam_in_flight_before_resync", await _wait_until(func():
		var current: Node2D = _main._boss_laser_visual
		return is_instance_valid(current) and current._age >= 0.4, 1.5)):
		return false
	var beam: Node2D = _main._boss_laser_visual
	var original_age: float = beam._age
	var original_origin: Vector2 = beam._beam_start
	_check("active_snapshot_roundtrip", await _resnapshot(), "")
	_check("active_snapshot_keeps_node_and_beam", is_same(_boss, _main._boss) and is_same(beam, _main._boss_laser_visual)
		and beam._age >= original_age and _has_boss_shield(), "")
	# 模拟渲染副本缺失，实体和主客连接继续运行。
	_main._clear_boss_laser_visual()
	_check("missing_beam_snapshot_roundtrip", await _resnapshot(), "")
	var restored: Node2D = _main._boss_laser_visual
	_check("resnapshot_restores_beam_at_live_age", is_instance_valid(restored) and not is_same(restored, beam)
		and restored._age >= original_age - 0.10 and restored._beam_start.is_equal_approx(original_origin) and release_cues == 1,
		"beam_age=%.3f → %.3f" % [original_age, restored._age if is_instance_valid(restored) else -1.0])
	return true

func _resnapshot() -> bool:
	var next_roundtrip := snapshot_roundtrips + 1
	_main._rpc_request_entity_snapshot.rpc_id(1)
	_confirm_snapshot.rpc_id(1)
	return await _wait_until(func(): return snapshot_roundtrips == next_roundtrip, 1.0)

@rpc("any_peer", "reliable", "call_remote")
func _confirm_snapshot() -> void:
	if not multiplayer.is_server():
		return
	_mark_snapshot.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable", "call_remote")
func _mark_snapshot() -> void:
	snapshot_roundtrips += 1

@rpc("authority", "reliable", "call_remote")
func _report_release_origin(at: Vector2) -> void:
	authority_release_at = at

func _shoot_at_boss(damage := 0) -> void:
	shot_hit = false
	_main._player.global_position = _boss.global_position + Vector2(0, 185)
	_main._player.rotation = 0
	if damage > 0:
		var start: Vector2 = _boss.global_position + Vector2(0.0, 115.0)
		_main._player._combat._spawn_bullet(start, -PI * 0.5, damage, true, 1, 780.0)
	else:
		_main._player._combat._shoot()
	for shot in get_tree().get_nodes_in_group("player_bullets"):
		shot.body_entered.connect(func(body):
			if is_same(body, _boss):
				shot_hit = true, CONNECT_ONE_SHOT)

func _shoot_and_collect() -> void:
	recording = true
	if _role != "client":
		_boss.global_position = TARGET
		_boss._health = 1
		_boss.boss_died.connect(_observe_death)
		_shoot_at_boss()
	if not _require("six_materialized", await _wait_until(func(): return drops.size() >= 6, 5)):
		return
	_check_drops()
	if _role == "client":
		# 前段的束外站位距速射掉落 602。先回到生产吸附范围，再发真实请求。
		_main._player.global_position = origin + Vector2(0, 160)
		await _wait_seconds(0.15)
		# 绕过本机过滤，仍须在房主拒绝 P2 请求 P1 专属核心。
		_main._rpc_request_powerup_magnet.rpc_id(1, GameState.get_sync_round(), instance_from_id(drops[0]).entity_id)
		instance_from_id(drops[2]).start_magnet(_main._player)
		_ack.rpc_id(1, 1)
	else:
		_check("one_physical_main_shot_kill", deaths == 1 and shot_hit, "deaths=%d contact=%s" % [deaths, shot_hit])
		if _role == "host" and not _require("client_checked_drops", await _wait_until(func(): return client_stage >= 1, 4)):
			return
		if _role == "host":
			var gained := await _wait_until(func(): return GameState.get_shoot_speed_level(p2) == p2_speed + 1, 4)
			_check("p2_received_speed", gained, str(GameState.get_shoot_speed_level(p2)))
			var core = instance_from_id(drops[0])
			_check("p2_cannot_magnet_host_core", is_instance_valid(core) and core._magnet_owner_peer_id == 0, "")
		# 加入端看完六件静止掉落后再让房主实际吸取。
		_main._player.global_position = origin
		_main._player._combat._shoot_timer = 8
		_main._player.set_physics_process(true)
	var gone := await _wait_until(func(): return drops.all(func(id): return not is_instance_id_valid(id)), 5)
	_check("all_six_collected_or_despawned", gone, "")
	if _role != "client":
		var expected := ITEMS.duplicate()
		if _role == "host":
			expected.erase("speed")
		expected.sort()
		collected.sort()
		_check("local_collections", collected == expected, str(collected))
	var peers: Array = [_main._player.peer_id] if _role == "client" else GameState.get_alive_player_ids()
	for id in peers:
		_check("one_reward_%s" % id, _reward_count(id) == reward_before.get(id, 0) + 1, str(_reward_count(id)))
	if _role == "client":
		_check("own_speed_synced", GameState.get_shoot_speed_level(p2) == p2_speed + 1, str(GameState.get_shoot_speed_level(p2)))
		_ack.rpc_id(1, 2)
		await _wait_seconds(0.25)
	elif _role == "host":
		_check("client_finished", await _wait_until(func(): return client_stage == 2, 4), "")

func _observe_death() -> void:
	deaths += 1
	health_at_death = _boss.get_network_health()
	origin = _boss.global_position
	_check("drops_pending_at_death_signal", drops.is_empty(), str(drops.size()))
	# 移走退场中的机体，检验回调确实已保留死亡落点。
	_boss.position += Vector2(30, 20)
	_boss.die()

func _check_drops() -> void:
	var types := []
	var owners := []
	var positioned := true
	var registered := true
	for i in drops.size():
		var item = instance_from_id(drops[i])
		types.append(item.get_powerup_type())
		owners.append(item.get_meta("assigned_peer_id", 0))
		var expected := origin + Vector2.from_angle(i * TAU / ITEMS.size()) * 92.0
		positioned = positioned and birth_positions[i].distance_to(expected) < 0.1
		if NetworkManager.is_online():
			registered = registered and _main._entities.get(item.entity_id) == item and item._is_network_ghost == (_role == "client")
	_check("types_and_order", types == ITEMS, str(types))
	# 原版按物品下标分配，两个核心的下标 0 和 4 在双人局都给房主。
	_check("core_owners", owners == [1, 0, 0, 0, 1, 0], str(owners))
	_check("six_death_world_positions", positioned, str(origin))
	if NetworkManager.is_online():
		_check("registered_on_this_peer", registered, "")

func _alternate_death() -> void:
	if _role != "finishing-beam":
		_boss.boss_died.connect(_observe_death)
	match _role:
		"finishing-beam":
			await _kill_in_beam_phase(BossModel.AttackWindow.SWEEP, 0)
		"bomb":
			_boss._drop_supply_fragments()
			var supplies := []
			for pickup in get_tree().get_nodes_in_group("powerups"):
				supplies.append(pickup.get_powerup_type())
				pickup.queue_free()
			_check("overload_supply_still_immediate", supplies == ["heal", "speed", "power", "heal"], str(supplies))
			await get_tree().process_frame
			_boss._start_ultimate_laser()
			_boss._tick_ultimate_laser(_boss.BOSS_ULTIMATE_LASER_CHARGE + 0.01)
			var active: LaserModel = _main._boss_laser_visual
			_check("active_beam_before_bomb", is_instance_valid(active) and active._mode == LaserModel.VisualMode.BEAM, "")
			_boss.boss_died.connect(func():
				_check("boss_death_removes_beam_immediately", not is_instance_valid(_main._boss_laser_visual)
					and (not is_instance_valid(active) or not active.visible), ""))
			var bomb = POWERUP.instantiate()
			_main.add_child(bomb)
			recording = true
			bomb.setup("bomb")
			bomb.collect()
			if _require("bomb_drops", await _wait_until(func(): return drops.size() >= 6, 3)):
				_check_drops()
				_check("bomb_killed_with_hp", health_at_death > 0 and collected.has("bomb"), str(health_at_death))
				_check("bomb_reward_once", deaths == 1 and _reward_count(1) == reward_before[1] + 1, "")
		"game-over", "scene-exit":
			recording = true
			_boss._start_ultimate_laser()
			_boss._tick_ultimate_laser(_boss.BOSS_ULTIMATE_LASER_CHARGE + 0.01)
			_boss._tick_ultimate_laser(_boss.BOSS_ULTIMATE_LASER_TRAVEL + _boss.BOSS_ULTIMATE_LASER_HOLD_SECONDS + 0.01)
			var cooling: LaserModel = _main._boss_laser_visual
			_boss.take_damage(_boss.get_shield_hp())
			_check("live_shards_before_exit", bursts.size() == 1, str(bursts.size()))
			_check("cooling_before_exit", is_instance_valid(cooling) and cooling._mode == LaserModel.VisualMode.COOLING, "")
			_boss.boss_died.connect(func():
				if _role == "game-over":
					_main._player.force_kill()
				else:
					get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn"))
			_boss.die()
			await _wait_seconds(0.15 if _role == "scene-exit" else 0.65)
			var ended := not GameState.game_running if _role == "game-over" else get_tree().current_scene.scene_file_path == "res://scenes/ui/title_screen.tscn"
			_check("battle_ended_or_changed", ended, "")
			_check("no_late_loot", drops.is_empty() and get_tree().get_nodes_in_group("powerups").is_empty(), str(drops.size()))
			_check("no_shards_after_exit", bursts.size() == 1 and not is_instance_id_valid(bursts[0]), "")
			_check("no_laser_after_exit", not is_instance_valid(cooling), "")

func _beam_kill_matrix() -> void:
	_main._wave_director._cooldown = INF
	_main._asteroid_timer = INF
	var stages := [BossModel.AttackWindow.CHARGING, BossModel.AttackWindow.SWEEP, BossModel.AttackWindow.HOLD]
	for i in stages.size():
		if _role != "client":
			_main._spawn_boss(5)
		if not await _kill_in_beam_phase(stages[i], i):
			return

func _kill_in_beam_phase(stage: BossModel.AttackWindow, sample: int) -> bool:
	var label: String = BossModel.AttackWindow.keys()[stage].to_lower()
	var handshake := 10 + sample * 2
	var old_snapshot := {}
	var score_before := GameState.score
	var local_id: int = _main._player.peer_id
	var reward := _reward_count(local_id)
	var p1_health := GameState.get_current_health(1)
	_main._player.get_node("PickupArea").monitoring = false
	fatal_frame = -1
	death_frame = -1
	deaths = 0
	explosions = 0
	drops.clear()
	birth_positions.clear()
	recording = true
	var beam_contact := TARGET + Vector2(0, 100)
	if _role != "client":
		_boss = _main._boss
		_prepare_fatal_beam(stage)
		old_snapshot = _main._boss_snapshot(_boss)
		_boss.boss_died.connect(func():
			deaths += 1
			death_frame = Engine.get_physics_frames()
			_check(label + "_same_frame_signal_clears_beam_and_hud",
				_main._boss == null and _main._boss_laser_visual == null and not _main._hud._boss_status_root.visible
					and not _boss._ultimate_laser_charging and not _boss._ultimate_laser_firing and drops.is_empty(), "")
			_boss.die())
	var ready := await _wait_until(func():
		return (is_instance_valid(_main._boss) and _main._boss.get_attack_window() == stage
			and is_instance_valid(_main._boss_laser_visual) and is_instance_valid(_main._hud._boss_status_root)
			and _main._hud._boss_status_root.visible), 3.0)
	if not _require(label + "_phase_visible_before_impact", ready):
		return false
	var target: BossModel = _main._boss
	var eid := target.entity_id
	if _role == "client":
		_ack.rpc_id(1, handshake)
	else:
		if _role == "host" and not _require(label + "_guest_observes_phase",
				await _wait_until(func(): return client_stage >= handshake, 3.0)):
			return false
		if stage != BossModel.AttackWindow.CHARGING:
			_check(label + "_future_pilot_position_is_inside_live_beam",
				is_zero_approx(target._distance_to_beam_center(beam_contact)), str(beam_contact))
		target.set_physics_process(true)
		var round := Pool.acquire("bullet", preload("res://scenes/entities/bullet.tscn"))
		_main.add_child(round)
		round.setup(TARGET + Vector2(0, 105), -PI * 0.5, ceili(target.get_network_health()), true, 1, 780.0, 1)
		round.body_entered.connect(func(body):
			if body == target:
				fatal_frame = Engine.get_physics_frames()
				_main._player.global_position = beam_contact)
		var contacted := await _wait_until(func(): return fatal_frame >= 0, 0.8)
		await get_tree().physics_frame
		_check(label + "_fatal_projectile_settles_by_next_physics_tick",
			contacted and deaths == 1 and death_frame >= fatal_frame and death_frame <= fatal_frame + 1,
			"hit=%d death=%d" % [fatal_frame, death_frame])
		if _role == "host":
			_main._rpc_spawn_boss.rpc(eid, 5, 1, old_snapshot)
			_main._rpc_sync_boss_window.rpc(eid, old_snapshot.stamp, old_snapshot.from, old_snapshot.to, old_snapshot.age, old_snapshot.hp)
			_main._rpc_sync_boss_shield.rpc(eid, old_snapshot.shield_stamp, old_snapshot.shield, old_snapshot.max_shield, TARGET)
			_main._rpc_despawn_entity.rpc(eid, true)
			_mark_stale_probe.rpc(sample)
	var cleaned := await _wait_until(func():
		return not _main._has_active_boss() and _main._boss_laser_visual == null and not _main._hud._boss_status_root.visible, 1.0)
	_check(label + "_beam_hull_and_hud_clear", cleaned, "")
	await _wait_seconds(0.24)
	_check(label + "_no_followup_damage", GameState.is_player_alive(1) and GameState.get_current_health(1) == p1_health,
		"HP=%d → %d" % [p1_health, GameState.get_current_health(1)])
	var settled := await _wait_until(func(): return drops.size() >= 6 and GameState.score >= score_before + 1000, 1.0)
	_check(label + "_exactly_one_score_reward_drop_and_explosion", settled and drops.size() == 6
		and explosions == 1 and _reward_count(local_id) == reward + 1 and GameState.score == score_before + 1000,
		"drops=%d explosions=%d score=%d" % [drops.size(), explosions, GameState.score - score_before])
	# The reliable marker follows the deliberately late packets. Wait for receipt
	# so this checks rejection of delivered packets, not a fixed network delay.
	var stale_packets_seen := _role != "client" or await _wait_until(func(): return stale_probe_done == sample, 1.5)
	_check(label + "_old_packets_cannot_restore_retired_boss",
		stale_packets_seen and not is_instance_valid(target)
			and not _main._has_active_boss() and _main._boss_laser_visual == null
			and (not NetworkManager.is_online() or _main._despawned_entity_ids.has(eid)), "")
	if _role == "client":
		_ack.rpc_id(1, handshake + 1)
	elif _role == "host":
		if not _require(label + "_guest_checks_cleanup", await _wait_until(func(): return client_stage >= handshake + 1, 3.0)):
			return false
	recording = false
	return true

func _prepare_fatal_beam(stage: BossModel.AttackWindow) -> void:
	_boss.set_physics_process(false)
	_boss._stop_entry_motion()
	_boss.global_position = TARGET
	_main._player.global_position = TARGET + Vector2(0, 320)
	if stage == BossModel.AttackWindow.CHARGING:
		# 合法破盾会取消蓄力。这里故意注入无盾蓄力，检验死亡兜底。
		_boss.take_damage(_boss.get_shield_hp())
		_boss._start_ultimate_laser()
	else:
		_boss._start_ultimate_laser()
		_boss._tick_ultimate_laser(BossModel.BOSS_ULTIMATE_LASER_CHARGE + 0.01)
		_boss.take_damage(_boss.get_shield_hp())
	_main._player.global_position = Vector2(1070, 650)
	if stage != BossModel.AttackWindow.CHARGING:
		_boss._tick_ultimate_laser(0.8 if stage == BossModel.AttackWindow.SWEEP else 3.2)

@rpc("authority", "reliable", "call_remote")
func _mark_stale_probe(sample: int) -> void:
	stale_probe_done = sample

func _reward_count(id: int) -> int:
	return roundi(GameState.get_laser_cd_bonus(id) + GameState.get_extra_bullet_count(id) +
			GameState.get_extra_damage_bonus(id) / 2.0 + GameState.get_move_speed_bonus(id) / 0.1)

func _hud_says(text: String) -> bool:
	var label = _main._hud._boss_status_phase
	return is_instance_valid(label) and label.text == text

func _presentation(boss: bool) -> bool:
	var player: AudioStreamPlayer = BGM._bgm_player
	var backdrop = _main._backdrop
	return _main._boss_fight_active == boss and player.playing and player.max_polyphony == 1 and BGM.get_child_count() == 1 \
		and BGM._track_gain >= 0.999 and player.stream == (BGM._boss if boss else BGM._cruise) \
		and backdrop.get_node("Panorama").texture == (backdrop.RIFT if boss else backdrop.CRUISE)

func _retry_and_leave() -> void:
	_check("boss_defeat_returns_to_cruise_once", is_instance_valid(_main) and await _wait_until(_presentation.bind(false), 3), "")
	_check("no_laser_or_boss_hud_after_defeat", not is_instance_valid(_main._boss_laser_visual)
		and not _main._hud._boss_status_root.visible, "")
	var playback: AudioStreamPlayback = BGM._bgm_player.get_stream_playback()
	if _role == "client":
		_main._request_player_sync.rpc_id(1)
	await _wait_seconds(0.25)
	_check("duplicate_stage_does_not_restart_voice", playback == BGM._bgm_player.get_stream_playback(), "")
	if _role == "client":
		_ack.rpc_id(1, 3)
	elif await _wait_until(func(): return client_stage >= 3, 4):
		_main._finish_multiplayer_game_over(GameState.score, GameState.level)
	else:
		_check("p2_ready_for_game_over", false, "")
		return
	_check("game_over_stops_music", await _wait_until(func(): return not GameState.game_running and not BGM._bgm_player.playing, 5), "")
	if _role == "client":
		_ack.rpc_id(1, 4)
	elif await _wait_until(func(): return client_stage >= 4, 4):
		_main._restart()
	else:
		_check("p2_ready_for_retry", false, "")
		return
	if not _require("retry_loaded_new_battle", await _wait_until(func():
		var current := get_tree().current_scene
		return is_instance_valid(current) and not is_same(current, _main) and current.scene_file_path == MAIN_SCENE, 8)):
		return
	_main = get_tree().current_scene
	_check("retry_has_one_cruise_voice", await _wait_until(_presentation.bind(false), 3), "")
	if _role == "client":
		_ack.rpc_id(1, 5)
	elif await _wait_until(func(): return client_stage >= 5, 4):
		_leave_battle.rpc()
	var title_loaded := await _wait_until(func():
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == "res://scenes/ui/title_screen.tscn", 5)
	await _wait_seconds(0.6)
	_check("leaving_battle_cancels_music", title_loaded and not BGM._bgm_player.playing and BGM._target_stream == null, "")

@rpc("authority", "reliable", "call_local")
func _leave_battle() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")

func _capture_boss_and_cards() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4 or args[2] != "capture" or DisplayServer.get_name() == "headless":
		if _role == "host":
			await _wait_seconds(0.35)
		return
	var hud = _main._hud
	if _role == "client":
		_main._spawn_mobile_controls()
		hud._layout_battle_hud()
		hud._update_platform_hints()
	else:
		for pid in [1, p2]:
			UpgradeDraft.offer_cards(pid, ["pierce", "splash", "power"])
		GameState.force_sync_to_peer(p2)
	if not _require("capture_has_authoritative_draft",
			await _wait_until(UpgradeDraft.has_draft.bind(_main._player.peer_id), 1.0)):
		return
	await _wait_seconds(0.23)
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	_check("captured_lan_presentation", frame.save_png(args[3].path_join(_role + "-laser-and-draft.png")) == OK, "")
	if _role == "host":
		await _wait_seconds(0.80)
		UpgradeDraft.clear_drafts()
		GameState.force_sync_to_peer(p2)

func _orphan_shards() -> int:
	var count := 0
	for id in Node.get_orphan_node_ids():
		if instance_from_id(id).get_script() == BURST:
			count += 1
	return count

@rpc("any_peer", "reliable", "call_remote")
func _ack(stage: int) -> void:
	if not multiplayer.is_server():
		return
	client_stage = stage

func _read_pixels(fx) -> void:
	get_tree().paused = true
	var bullet = preload("res://scenes/entities/bullet.tscn").instantiate()
	_main.add_child(bullet)
	var frag: Dictionary = fx._fragments[0]
	var t: float = fx._age / fx._duration
	var radius: float = frag.radius + frag.speed * t * fx._spread
	var mid: Vector2 = Vector2.from_angle(frag.angle) * (radius + frag.length * (1.0 + t) * sqrt(fx._spread) * 0.5)
	bullet.setup(fx.to_global(mid), 0, 1, false, 1, 0)
	bullet.reset_physics_interpolation()
	var center := Vector2i(fx.get_global_transform_with_canvas() * mid)
	var region := Rect2i(center - Vector2i(8, 8), Vector2i(17, 17))
	var frames: Array[Image] = []
	var args := OS.get_cmdline_user_args()
	for mask in 4:
		fx.visible = (mask & 1) != 0
		bullet.visible = (mask & 2) != 0
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame := get_viewport().get_texture().get_image()
		if args.size() >= 3:
			_check("capture_%d" % mask, frame.save_png(args[2].path_join("shield-%d.png" % mask)) == OK, "")
		frames.append(frame.get_region(region))
	var lit := 0
	var foreground := 0
	for y in region.size.y:
		for x in region.size.x:
			var base := frames[0].get_pixel(x, y)
			var shard := frames[1].get_pixel(x, y)
			var hazard := frames[2].get_pixel(x, y)
			if shard.b - base.b > 0.08:
				lit += 1
				if absf(hazard.r - base.r) > 0.18 and hazard == frames[3].get_pixel(x, y):
					foreground += 1
	_check("rendered_shard_and_foreground_bullet", lit > 6 and foreground > 0, "shard_pixels=%d overlap=%d" % [lit, foreground])
	fx.show()
	bullet.queue_free()
	get_tree().paused = false
