extends "res://tests/lan_probe.gd"
## 同一场景可检查单人碰撞、真实 ENet 双端和死亡回调内的换场边界。
const BURST = preload("res://scripts/shield_shatter_burst.gd")
const POWERUP = preload("res://scenes/entities/powerup.tscn")
const TARGET := Vector2(608, 270)
const ITEMS := ["core", "heal", "speed", "power", "core", "heal"]

var bursts: Array[int] = []
var burst_origin := Vector2.ZERO
var drops: Array[int] = []
var birth_positions: Array[Vector2] = []
var recording := false
var collected: Array[String] = []
var deaths := 0
var health_at_death := 0.0
var shot_hit := false
var client_stage := 0
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
	if _role != "client":
		_main._spawn_boss(5)
	if not _require("boss_in_tree", await _wait_until(func(): return is_instance_valid(_main._boss), 5)):
		return
	_boss = _main._boss
	_boss.set_physics_process(false)
	if _role in ["bomb", "game-over", "scene-exit"]:
		await _alternate_death()
	elif await _shield_cycle():
		await _shoot_and_collect()
	_check("no_orphan_shards", _orphan_shards() == 0, str(_orphan_shards()))
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
	if _role != "client":
		# 等入场动画结束后跨过正式激光阈值，专项只缩短持续束的等待。
		await _wait_seconds(1.65)
		_boss.global_position = TARGET
		_boss.take_damage(ceilf(_boss.get_network_max_health() * 0.26))
		_boss.set_physics_process(true)
	if not _require("shield_raised", await _wait_until(func(): return is_instance_valid(_boss._boss_shield_circle), 5)):
		return false
	if _role != "client":
		if not _require("laser_fired", await _wait_until(func(): return _boss._ultimate_laser_firing, 4)):
			return false
		_boss._ultimate_laser_fire_timer = 0
	if not _require("shield_ended", await _wait_until(func(): return _boss._boss_shield_circle == null, 5)):
		return false
	_boss.set_physics_process(false)
	if _role == "host":
		_main._rpc_destroy_boss_shield.rpc()
	elif _role == "solo":
		_main._rpc_destroy_boss_shield()
	_check("one_visible_burst", bursts.size() == 1, str(bursts))
	if bursts.size() == 1:
		var fx = instance_from_id(bursts[0])
		_check("burst_at_boss", fx.global_position.distance_to(burst_origin) < 0.1, "%s / %s" % [fx.global_position, burst_origin])
		_check("original_fragments", fx._fragments.size() == 24 and is_equal_approx(fx._duration, 0.48), "")
		if _role == "solo" and DisplayServer.get_name() != "headless":
			await _read_pixels(fx)
	await _wait_seconds(0.65)
	_check("one_burst_released", bursts.size() == 1 and not is_instance_id_valid(bursts[0]), str(bursts))
	return true

func _shoot_and_collect() -> void:
	recording = true
	if _role != "client":
		_boss.global_position = TARGET
		_boss._health = 1
		_boss.boss_died.connect(_observe_death)
		_main._player.global_position = TARGET + Vector2(0, 185)
		_main._player.rotation = 0
		_main._player._combat._shoot()
		for shot in get_tree().get_nodes_in_group("player_bullets"):
			shot.body_entered.connect(func(body):
				if is_same(body, _boss):
					shot_hit = true)
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
			_check("live_shards_before_exit", bursts.size() == 1, str(bursts.size()))
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

func _reward_count(id: int) -> int:
	return roundi(GameState.get_laser_cd_bonus(id) + GameState.get_extra_bullet_count(id) +
			GameState.get_extra_damage_bonus(id) / 2.0 + GameState.get_move_speed_bonus(id) / 0.1)

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
	var ring_at := Vector2(78.0 + 70.0 * fx._age / fx._duration, 0)
	bullet.setup(fx.to_global(ring_at), 0, 1, false, 1, 0)
	bullet.reset_physics_interpolation()
	var center := Vector2i(fx.get_global_transform_with_canvas() * ring_at)
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
			if absf(shard.r - base.r) > 0.08:
				lit += 1
				if absf(hazard.r - base.r) > 0.18 and hazard == frames[3].get_pixel(x, y):
					foreground += 1
	_check("rendered_ring_and_foreground_bullet", lit > 10 and foreground > 0, "shard_pixels=%d overlap=%d" % [lit, foreground])
	fx.show()
	bullet.queue_free()
	get_tree().paused = false
