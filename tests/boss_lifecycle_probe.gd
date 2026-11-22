extends "res://tests/lan_probe.gd"
## 同一场景可检查单人碰撞、真实 ENet 双端和死亡回调内的换场边界。
const BURST = preload("res://scripts/shield_shatter_burst.gd")
const POWERUP = preload("res://scenes/entities/powerup.tscn")
const TARGET := Vector2(608, 270)
const ITEMS := ["core", "heal", "speed", "power", "core", "heal"]
const BossModel = preload("res://scripts/boss.gd")
const LaserModel = preload("res://scripts/boss_ultimate_laser_visual.gd")

var bursts: Array[int] = []
var burst_origin := Vector2.ZERO
var release_cues := 0
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
	_boss.shield_released.connect(func(): release_cues += 1)
	if _role in ["bomb", "game-over", "scene-exit"]:
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

func _observe(node: Node) -> void:
	if node.get_script() == BURST:
		bursts.append(node.get_instance_id())
		burst_origin = _boss.global_position
	elif recording and node.scene_file_path == POWERUP.resource_path:
		drops.append(node.get_instance_id())
		birth_positions.append(node.global_position)

func _shield_cycle() -> bool:
	var charge_snapshot := {}
	if _role == "client":
		_main._player.global_position = Vector2(916, 530)
	if _role != "client":
		# 等入场动画结束后跨过正式激光阈值。
		await _wait_seconds(1.65)
		_boss.global_position = TARGET
		_boss.take_damage(ceilf(_boss.get_network_max_health() * 0.26))
		_boss.set_physics_process(true)
	if not _require("shield_raised", await _wait_until(_has_boss_shield, 5)):
		return false
	var shield_hp: float = _boss.get_network_health()
	_check("hud_shield_charge", await _wait_until(_hud_says.bind("有盾 · 不掉血 · 激光蓄力"), 1.5), "")
	if _role == "client":
		await _restore_laser_stage("charge", LaserModel.VisualMode.CHARGE, 0.20)
	if _role != "client":
		charge_snapshot = _main._boss_snapshot(_boss)
		_shoot_at_boss()
		var contact := await _wait_until(func(): return shot_hit, 1.0)
		_check("shield_blocks_physical_main_shot", contact and _has_boss_shield() and _boss.get_network_health() == shield_hp,
			"contact=%s HP=%s -> %s" % [contact, shield_hp, _boss.get_network_health()])
		if not _require("laser_fired", await _wait_until(func(): return _boss._ultimate_laser_firing, 4)):
			return false
		_main._player.global_position = Vector2(750, 530)
	_check("hud_shield_sweep", await _wait_until(_hud_says.bind("有盾 · 不掉血 · 激光推进"), 4.0), "")
	if _role == "client":
		if not await _check_mid_beam_snapshot():
			return false
	if NetworkManager.is_online():
		await _capture_boss_and_cards()
	await _wait_seconds(0.22)
	_check("sweep_nose_points_along_beam_after_pilot_moves", _faces_laser_beam(), str(_boss.global_rotation))
	_check("hud_shield_hold", await _wait_until(_hud_says.bind("有盾 · 不掉血 · 激光持续"), 4.0), "")
	var hold: LaserModel = _main._boss_laser_visual
	_check("hold_has_full_beam", is_instance_valid(hold) and hold._mode == LaserModel.VisualMode.BEAM
		and hold._age >= BossModel.BOSS_ULTIMATE_LASER_TRAVEL, "")
	if _role == "client":
		await _restore_laser_stage("hold", LaserModel.VisualMode.BEAM, BossModel.BOSS_ULTIMATE_LASER_TRAVEL + 0.18)
	_check("hold_nose_points_along_beam", _faces_laser_beam(), str(_boss.global_rotation))
	if _role == "client":
		# 按原有接收入口注入一次滞后的瞄准角。
		var locked_heading: float = _boss._network_target_rotation
		_boss.apply_network_rotation(_boss.global_rotation + PI * 0.5)
		_check("late_rotation_cannot_steer_firing_boss", _faces_laser_beam()
			and is_equal_approx(_boss._network_target_rotation, locked_heading), str(_boss.global_rotation))
	_check("health_remains_shielded", _has_boss_shield() and _boss.get_network_health() == shield_hp, str(shield_hp))
	if not _require("shield_ended", await _wait_until(func(): return is_instance_valid(_boss) and not _has_boss_shield(), 13)):
		return false
	_boss.set_physics_process(false)
	var cooling: LaserModel = _main._boss_laser_visual
	_check("open_replaces_danger_with_cooling", is_instance_valid(cooling) and cooling._mode == LaserModel.VisualMode.COOLING, "")
	_check("hud_release_cue", await _wait_until(_hud_says.bind("护盾解除 · 可攻击"), 0.25), "")
	if _role == "host":
		var eid: int = _boss.entity_id
		var current: int = _boss.get_attack_window_stamp()
		_main._rpc_sync_boss_window.rpc(eid, current, burst_origin, Vector2.ZERO, 0.0, shield_hp)
		_main._rpc_sync_boss_window.rpc(eid, charge_snapshot.stamp, charge_snapshot.from, charge_snapshot.to, 0.0, shield_hp)
		_main._rpc_spawn_boss.rpc(eid, _boss.get_network_level(), _boss.get_sprite_variant_id(), charge_snapshot)
		_main._rpc_sync_boss_window.rpc(eid + 1, current + 1, burst_origin, Vector2.ZERO, 0.0, shield_hp)
		_report_release_origin.rpc(burst_origin)
	if _role == "client":
		_check("duplicates_and_old_snapshot_delivered", await _wait_until(func(): return authority_release_at != Vector2.INF, 0.25), "")
		_check("old_packets_keep_same_unshielded_boss", is_same(_boss, _main._boss) and not _has_boss_shield(), "")
		_check("old_packets_do_not_relight_laser", not is_instance_valid(_main._boss_laser_visual)
			or (is_same(cooling, _main._boss_laser_visual) and cooling._mode == LaserModel.VisualMode.COOLING), "")
	_check("one_visible_burst_and_cue", bursts.size() == 1 and release_cues == 1, str(bursts))
	if bursts.size() == 1:
		var fx = instance_from_id(bursts[0])
		var expected := authority_release_at if _role == "client" else burst_origin
		_check("burst_at_authority_release", is_instance_valid(fx) and fx.global_position.distance_to(expected) < 0.1, str(expected))
		if is_instance_valid(fx):
			_check("short_mothership_fragments", fx._mothership_release and fx.z_index == -1 and is_equal_approx(fx._duration, 0.32), "")
			if _role == "solo" and DisplayServer.get_name() != "headless":
				await _read_pixels(fx)
	await _wait_seconds(0.65)
	_check("cooling_expires", not is_instance_valid(cooling) and not is_instance_valid(_main._boss_laser_visual), "")
	_check("one_burst_released", bursts.size() == 1 and not is_instance_id_valid(bursts[0]), str(bursts))
	_check("hud_attack_window_open", _hud_says("可攻击") and not _main._hud._boss_status_hatch.visible, "")
	if _role != "client":
		_shoot_at_boss()
		_check("open_takes_physical_main_shot", await _wait_until(func(): return shot_hit and _boss.get_network_health() < shield_hp, 1.0),
			"contact=%s HP=%s -> %s" % [shot_hit, shield_hp, _boss.get_network_health()])
		# 等受击缩放收尾，隔离下一次击毁的反馈。
		if not _require("nonfatal_hit_settled", await _wait_until(func(): return _boss._hit_recoil_tween == null, 1.0)):
			return false
	if _role == "client":
		_check("open_hit_health_is_synced", await _wait_until(func(): return _boss.get_network_health() < shield_hp, 2.0),
			"HP=%s -> %s" % [shield_hp, _boss.get_network_health()])
		_ack.rpc_id(1, 6)
	elif _role == "host":
		_check("join_observed_open_hit", await _wait_until(func(): return client_stage == 6, 2.0), "")
		client_stage = 0
	return true

func _has_boss_shield() -> bool:
	return is_instance_valid(_boss) and _boss.get_attack_window() >= BossModel.AttackWindow.CHARGING

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
	_check("active_snapshot_roundtrip", await _resnapshot(), "")
	_check("active_snapshot_keeps_node_and_beam", is_same(_boss, _main._boss) and is_same(beam, _main._boss_laser_visual)
		and beam._age >= original_age and _has_boss_shield(), "")
	# 模拟渲染副本缺失，实体和主客连接继续运行。
	_main._clear_boss_laser_visual()
	_check("missing_beam_snapshot_roundtrip", await _resnapshot(), "")
	var restored: Node2D = _main._boss_laser_visual
	_check("resnapshot_restores_beam_at_live_age", is_instance_valid(restored) and not is_same(restored, beam)
		and restored._age >= original_age - 0.10 and restored._beam_start.distance_to(TARGET) < 40.0 and release_cues == 0,
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

func _shoot_at_boss() -> void:
	shot_hit = false
	_main._player.global_position = _boss.global_position + Vector2(0, 185)
	_main._player.rotation = 0
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
		# 两次真实磁吸请求：P2 可以收速射，房主专属核心须留在场内。
		instance_from_id(drops[0]).start_magnet(_main._player)
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
	_boss.boss_died.connect(_observe_death)
	match _role:
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
