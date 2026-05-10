## Main — 主游戏场景控制器
## 多人模式：Host 通过显式 RPC 广播玩家/敌人生成与同步，避免依赖自动场景复制。
## 服务器（Host peer_id=1）控制所有敌人生成和 GameState 广播；
## 客户端（Client peer_id=2）只渲染和响应输入。
##
## 单机兼容：NetworkManager.is_online() 为 false 时走原有单人逻辑。
extends Node2D

var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _laser_scene = preload("res://scenes/entities/laser_bolt.tscn")
var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _elite_scene = preload("res://scenes/entities/elite.tscn")
var _boss_scene = preload("res://scenes/entities/boss.tscn")
var _asteroid_scene = preload("res://scenes/entities/asteroid.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")
var _mobile_controls_scene = preload("res://scenes/ui/mobile_controls.tscn")

var _player: Node2D = null
var _hud: Node = null
var _elite: Node2D = null
var _boss: Node2D = null
var _boss_variant_cycle: Array[int] = []
var _boss_variant_last: int = 0
var _current_boss_variant_id: int = 0
var _boss_fight_active: bool = false
var _pending_boss_level: int = 0
var _enemy_spawn_timer: float = 0.0
var _difficulty_timer: float = 0.0
var _asteroid_timer: float = 0.0
var _bg_layers: Array[Dictionary] = []
var _nebulas: Array[Node2D] = []
var _planets: Array[Node2D] = []

## 多人模式：存储所有已生成的玩家节点（peer_id → Node）
var _players: Dictionary = {}

## 多人模式：实体追踪（entity_id → Node）
var _next_entity_id: int = 1000
var _entities: Dictionary = {}
var _despawned_entity_ids: Dictionary = {}
var _entity_sync_timer: float = 0.0
const ENTITY_SYNC_INTERVAL: float = 0.05
## 待发送的子弹生成数据（Host → Client 或 Client → Host）
var _pending_bullet_spawns: Array = []
var _pending_laser_spawns: Array = []

@onready var _bg_color: ColorRect = $BgColor

func _ready() -> void:
	set_process(true)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_parallax_background()
	_spawn_mobile_controls()
	_spawn_hud()
	_start_bgm()
	Pool.setup("bullet", _bullet_scene, 40)
	Pool.setup("hit_effect", _hit_effect_scene, 20)
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)
	GameState.elite_spawn_requested.connect(_on_elite_spawn_requested)
	GameState.boss_spawn_requested.connect(_on_boss_spawn_requested)
	GameState.game_over.connect(_on_game_over_triggered)
	_debug_log_variant_assets()
	var online := NetworkManager.is_online()
	print("[Main] online=", online, " server=", multiplayer.is_server(), " peer_id=", multiplayer.get_unique_id())

	## 多人：Host 负责权威生成，Client 通过 RPC 复位玩家列表
	if online and multiplayer.is_server():
		## 注册子弹批量刷出处理（每帧 flush）
		set_process(true)

	## 多人模式：订阅连接/断线信号，服务器端负责生成所有玩家
	if online:
		NetworkManager.player_connected.connect(_on_multiplayer_player_connected)
		NetworkManager.player_disconnected.connect(_on_multiplayer_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_multiplayer_server_disconnected)
		## 服务器端：为自己和已连接的所有 peer 生成玩家
		if multiplayer.is_server():
			_spawn_networked_player(1, true)  # Host 自己
			for pid in NetworkManager.connected_peers:
				_spawn_networked_player(pid, true)
		## 客户端：向服务器请求一次完整玩家同步，避免错过早期生成 RPC
		else:
			await get_tree().process_frame
			_request_player_sync.rpc_id(1)
			var my_id := multiplayer.get_unique_id()
			var node: Node = null
			for _attempt in 60:
				node = get_node_or_null(str(my_id))
				if node:
					break
				await get_tree().process_frame
			if node == null:
				push_warning("[Main] 未能在同步后找到本地玩家节点（peer_id=%d）" % my_id)
	else:
		## 单机模式：原有逻辑
		_spawn_player()

func _debug_log_variant_assets() -> void:
	var boss_count := 0
	for i in range(1, 100):
		var p := "res://assets/sprites/enemies/boss/boss_%02d.png" % i
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			break
		boss_count += 1

	var player_count := 0
	for i in range(1, 100):
		var p := "res://assets/sprites/player/variants/lv%02d.png" % i
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			break
		player_count += 1

	print("[variants] boss=", boss_count, " player=", player_count)

func _create_parallax_background() -> void:
	if _bg_color:
		_bg_color.color = Color(0.06, 0.06, 0.12, 1.0)
		_bg_color.z_index = -100

	var far_layer := {nodes = [], speed = 12.0}
	for i in range(180):
		var star := Sprite2D.new()
		var b: float = randf_range(0.3, 0.7)
		var blue_tint: float = randf_range(0.8, 1.3)
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(b, b * 0.85, b * blue_tint, randf_range(0.3, 0.8)))
		star.texture = ImageTexture.create_from_image(img)
		star.position = Vector2(randf_range(0, 1500), randf_range(-100, 820))
		star.z_index = -10
		add_child(star)
		far_layer.nodes.append(star)
	_bg_layers.append(far_layer)

	var mid_layer := {nodes = [], speed = 24.0}
	for i in range(90):
		var star := Sprite2D.new()
		var b: float = randf_range(0.5, 0.9)
		var blue_tint: float = randf_range(0.85, 1.2)
		var size: int = randi_range(3, 5)
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in range(size):
			for x in range(size):
				var d: float = sqrt(float(x - size * 0.5) * float(x - size * 0.5) + float(y - size * 0.5) * float(y - size * 0.5))
				if d < float(size) / 2.0:
					img.set_pixel(x, y, Color(b, b * 0.9, b * blue_tint, 1.0))
		star.texture = ImageTexture.create_from_image(img)
		star.position = Vector2(randf_range(0, 1500), randf_range(-100, 820))
		star.z_index = -9
		add_child(star)
		mid_layer.nodes.append(star)
	_bg_layers.append(mid_layer)

	var near_layer := {nodes = [], speed = 40.0}
	for i in range(35):
		var star := Sprite2D.new()
		var b: float = randf_range(0.7, 1.0)
		var size: int = randi_range(6, 12)
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var col: Color
		match randi() % 5:
			0: col = Color(b, b * 0.9, b, 1.0)
			1: col = Color(b, b * 0.7, b * 0.6, 1.0)
			2: col = Color(b * 0.5, b * 0.8, b, 1.0)
			3: col = Color(b, b * 0.85, b * 0.7, 1.0)
			_: col = Color(b * 0.7, b * 0.8, b, 1.0)
		var cx2: int = size / 2
		for y in range(size):
			for x in range(size):
				var d: float = sqrt(float(x - cx2) * float(x - cx2) + float(y - cx2) * float(y - cx2))
				if d < float(size) / 2.0:
					var t: float = d / (float(size) / 2.0)
					img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0 - t * t))
		star.texture = ImageTexture.create_from_image(img)
		star.position = Vector2(randf_range(0, 1500), randf_range(-100, 820))
		star.z_index = -8
		add_child(star)
		near_layer.nodes.append(star)
	_bg_layers.append(near_layer)

	for i in range(8):
		var nebula := Sprite2D.new()
		var w: int = randi_range(200, 400)
		var h: int = randi_range(120, 280)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var cx: float = w / 2.0
		var cy: float = h / 2.0
		var nc_r: float = randf_range(0.06, 0.25)
		var nc_g: float = randf_range(0.03, 0.15)
		var nc_b: float = randf_range(0.3, 0.7)
		var nc_a: float = randf_range(0.08, 0.18)
		var blob_count: int = randi_range(3, 6)
		for j in range(blob_count):
			var bx: float = randf_range(w * 0.1, w * 0.9)
			var by: float = randf_range(h * 0.1, h * 0.9)
			var rx: float = randf_range(w * 0.1, w * 0.35)
			var ry: float = randf_range(h * 0.1, h * 0.35)
			var rot: float = randf_range(0.0, PI)
			var intensity: float = randf_range(0.5, 1.0)
			for y in range(h):
				for x in range(w):
					var ldx: float = float(x) - bx
					var ldy: float = float(y) - by
					var cos_r: float = cos(-rot)
					var sin_r: float = sin(-rot)
					var local_x: float = ldx * cos_r - ldy * sin_r
					var local_y: float = ldx * sin_r + ldy * cos_r
					var d: float = sqrt(local_x * local_x / (rx * rx) + local_y * local_y / (ry * ry))
					if d < 1.0:
						var a: float = nc_a * (1.0 - d * d) * intensity
						var existing := img.get_pixel(x, y)
						var new_r: float = min(existing.r + nc_r * a, nc_r)
						var new_g: float = min(existing.g + nc_g * a, nc_g)
						var new_b: float = min(existing.b + nc_b * a, nc_b)
						var new_a: float = min(existing.a + a, nc_a)
						img.set_pixel(x, y, Color(new_r, new_g, new_b, new_a))
		nebula.texture = ImageTexture.create_from_image(img)
		nebula.position = Vector2(randf_range(-200, 1500), randf_range(-200, 900))
		nebula.z_index = -6 + randi() % 3
		add_child(nebula)
		_nebulas.append(nebula)

	for i in range(3):
		var planet := Sprite2D.new()
		var p_size: int = randi_range(50, 90)
		var img := Image.create(p_size, p_size, false, Image.FORMAT_RGBA8)
		var pc_r: float = randf_range(0.15, 0.4)
		var pc_g: float = randf_range(0.08, 0.25)
		var pc_b: float = randf_range(0.35, 0.65)
		for y in range(p_size):
			for x in range(p_size):
				var dx: float = float(x - p_size * 0.5)
				var dy: float = float(y - p_size * 0.5)
				var d: float = sqrt(dx * dx + dy * dy)
				var mr: float = float(p_size) / 2.0
				if d < mr:
					var t: float = d / mr
					var rr: float = pc_r * (1.0 - t * 0.4)
					var gg: float = pc_g * (1.0 - t * 0.4)
					var bb: float = pc_b * (1.0 - t * 0.4)
					var a: float = 1.0 if t < 0.8 else (1.0 - t) * 5.0
					img.set_pixel(x, y, Color(rr, gg, bb, a))
		if randf() < 0.5:
			var ring_r: float = float(p_size) / 2.0 * 1.4
			for y in range(p_size):
				for x in range(p_size):
					var d2: float = sqrt(float(x - p_size * 0.5) * float(x - p_size * 0.5) + float(y - p_size * 0.5) * float(y - p_size * 0.5))
					if d2 > ring_r - 2.0 and d2 < ring_r + 2.0:
						var ring_a: float = 0.4 * (1.0 - abs(d2 - ring_r) / 2.0)
						img.set_pixel(x, y, Color(pc_r * 1.2, pc_g * 1.2, pc_b * 1.2, ring_a))
		planet.texture = ImageTexture.create_from_image(img)
		planet.position = Vector2(randf_range(100, 1180), randf_range(100, 620))
		planet.z_index = -4
		add_child(planet)
		_planets.append(planet)

func _start_bgm() -> void:
	BGM.play_bgm()

func _spawn_player() -> void:
	_player = _player_scene.instantiate()
	_player.position = Vector2(640, 500)
	add_child(_player)
	_player.died.connect(_on_player_died)


func _get_networked_player_spawn_position(p_peer_id: int) -> Vector2:
	var slot := p_peer_id - 1
	if slot < 0:
		slot = 0
	var offset := float(slot % 2) * 180.0
	var row := float(slot / 2) * 90.0
	return Vector2(540.0 + offset, 500.0 - row)


func _spawn_networked_player(p_peer_id: int, announce: bool) -> void:
	if not multiplayer.is_server():
		return
	if _players.has(p_peer_id):
		return
	var player := _player_scene.instantiate()
	player.name = str(p_peer_id)
	player.position = _get_networked_player_spawn_position(p_peer_id)
	add_child(player)
	player.died.connect(_on_networked_player_died.bind(p_peer_id))
	_players[p_peer_id] = player
	## 兼容 _player 引用（指向本机玩家）
	var my_id := multiplayer.get_unique_id()
	if p_peer_id == my_id:
		_player = player
	if announce:
		_rpc_spawn_networked_player.rpc(p_peer_id, player.position.x, player.position.y)


## 多人模式：新 peer 连接时（只在服务器端触发）
func _on_multiplayer_player_connected(p_peer_id: int) -> void:
	if multiplayer.is_server():
		_spawn_networked_player(p_peer_id, true)


## 多人模式：peer 断线时清理其玩家节点
func _on_multiplayer_player_disconnected(p_peer_id: int) -> void:
	if _players.has(p_peer_id):
		var node: Node2D = _players[p_peer_id]
		if is_instance_valid(node):
			node.queue_free()
		_players.erase(p_peer_id)
	## 若所有玩家都断开，服务器自己也退出
	if _players.is_empty() and multiplayer.is_server():
		_on_player_died()


## 多人模式：服务器断开（Client 端触发）
func _on_multiplayer_server_disconnected() -> void:
	_show_death_marquee_text("服务器断开连接")
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


## 多人模式：某玩家死亡回调
func _on_networked_player_died(p_peer_id: int) -> void:
	_players.erase(p_peer_id)
	## 合作模式：仅当全员死亡（或全部离场）才结束。
	if _players.is_empty():
		_on_player_died()

func _spawn_hud() -> void:
	_hud = _hud_scene.instantiate()
	add_child(_hud)

func _spawn_mobile_controls() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		if get_node_or_null("MobileControls") != null:
			return
		var mc = _mobile_controls_scene.instantiate()
		mc.name = "MobileControls"
		add_child(mc)

func _process(delta: float) -> void:
	if not GameState.game_running:
		return

	## 多人：Host 定期同步实体位置 + flush 子弹
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_entity_sync_timer -= delta
			if _entity_sync_timer <= 0.0:
				_entity_sync_timer = ENTITY_SYNC_INTERVAL
				_batch_sync_entity_positions()
		_flush_bullet_spawns()
		_flush_laser_spawns()

	_scroll_background(delta)

	## 关键：联机时仅 Host 运行刷怪与敌方战斗逻辑。
	## Client 只渲染已同步实体，避免本地生成“假怪”导致命中无效/不同步。
	if NetworkManager.is_online() and not multiplayer.is_server():
		return

	if _elite != null and is_instance_valid(_elite):
		return
	if _boss != null and is_instance_valid(_boss):
		return

	_asteroid_timer -= delta
	if _asteroid_timer <= 0:
		_spawn_asteroid()
		_asteroid_timer = randf_range(2.0, 5.0)

	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0:
		_spawn_enemy()
		_enemy_spawn_timer = max(1.2 - GameState.level * 0.06, 0.2)

	_difficulty_timer += delta
	if _difficulty_timer > 8.0:
		_difficulty_timer = 0.0
		_spawn_enemy()

func _scroll_background(delta: float) -> void:
	for layer in _bg_layers:
		var spd: float = layer.speed
		for node in layer.nodes:
			node.position.y += delta * spd
			if node.position.y > 800:
				node.position.y = -60
				node.position.x = randf_range(0, 1280)

	for neb in _nebulas:
		neb.position.y += delta * 2.5
		neb.position.x += delta * 0.8
		if neb.position.y > 900:
			neb.position.y = -200
			neb.position.x = randf_range(-200, 1500)

	for pl in _planets:
		pl.position.y += delta * 1.2
		pl.position.x += delta * 0.3
		if pl.position.y > 760:
			pl.position.y = -100
			pl.position.x = randf_range(100, 1180)

func _spawn_enemy() -> void:
	var enemy = _enemy_scene.instantiate()
	var side := randi() % 4
	var pos := Vector2.ZERO
	var screen := get_viewport_rect().size
	match side:
		0: pos = Vector2(randf_range(0, screen.x), -30)
		1: pos = Vector2(randf_range(0, screen.x), screen.y + 30)
		2: pos = Vector2(-30, randf_range(0, screen.y))
		3: pos = Vector2(screen.x + 30, randf_range(0, screen.y))
	enemy.position = pos
	var enemy_type: int = randi() % 3
	enemy.enemy_type = enemy_type
	var mult: float = GameState.post_elite_multiplier
	enemy.health = int((1 + GameState.level / 2 + enemy_type) * mult)
	enemy.move_speed = (40.0 + GameState.level * 6.0 + enemy_type * 10.0) * mult
	enemy.shoot_cooldown = max((2.0 - GameState.level * 0.12) / mult, 0.4)
	enemy.drop_chance = 0.20 + enemy_type * 0.12
	if _player and is_instance_valid(_player):
		enemy.set_target(_player)
	enemy.enemy_died.connect(_on_enemy_died)
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		enemy.entity_id = eid
		_entities[eid] = enemy
		enemy.enemy_died.connect(_on_network_enemy_died.bind(eid))
		_rpc_spawn_enemy.rpc(eid, enemy_type, pos.x, pos.y, enemy.health, enemy.move_speed, enemy.shoot_cooldown, enemy.drop_chance, mult)
	add_child(enemy)

func _on_enemy_died() -> void:
	pass

func _on_network_enemy_died(entity_id: int) -> void:
	_despawned_entity_ids[entity_id] = true
	if _entities.has(entity_id):
		_entities.erase(entity_id)
	if multiplayer.is_server():
		_rpc_despawn_entity.rpc(entity_id)

## Client → Host（经 GameState 转发）：敌人受击
func _on_network_enemy_hit(entity_id: int, damage: int) -> void:
	if _entities.has(entity_id):
		var enemy = _entities[entity_id]
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.take_damage(damage)

## Client → Host（经 GameState 转发）：玩家受击
func _on_network_player_hit(damage: int, target_peer_id: int) -> void:
	var player_node = _players.get(target_peer_id)
	if player_node and is_instance_valid(player_node) and player_node.has_method("take_damage"):
		player_node.take_damage(damage)

## Client → Host：请求拾取掉落物
func request_network_powerup_collect(entity_id: int) -> void:
	if not NetworkManager.is_online():
		return
	_rpc_request_powerup_collect.rpc_id(1, entity_id)

## Client → Host：请求开始磁吸某个掉落物
func request_network_powerup_magnet(entity_id: int) -> void:
	if not NetworkManager.is_online():
		return
	_rpc_request_powerup_magnet.rpc_id(1, entity_id)

## Host：注册掉落物实体并广播给客户端
func register_powerup_entity(powerup: Node2D, powerup_type: String) -> void:
	if not NetworkManager.is_online() or not multiplayer.is_server():
		return
	if powerup == null or not is_instance_valid(powerup):
		return
	if powerup.get("entity_id") != 0:
		return
	var eid := _next_entity_id
	_next_entity_id += 1
	powerup.entity_id = eid
	_entities[eid] = powerup
	_rpc_spawn_powerup.rpc(eid, powerup_type, powerup.global_position.x, powerup.global_position.y)

## Host：掉落物被拾取后广播销毁
func _on_network_powerup_collected(entity_id: int, collector_peer_id: int = 1) -> void:
	if not multiplayer.is_server():
		return
	_despawned_entity_ids[entity_id] = true
	if _entities.has(entity_id):
		var node = _entities[entity_id]
		if is_instance_valid(node) and node.has_method("get_powerup_type"):
			GameState.collect_powerup(node.get_powerup_type())
		if is_instance_valid(node):
			node.queue_free()
		_entities.erase(entity_id)
	_rpc_despawn_entity.rpc(entity_id)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_powerup_collect(entity_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _despawned_entity_ids.has(entity_id):
		return
	var collector_peer_id := multiplayer.get_remote_sender_id()
	if collector_peer_id <= 0:
		collector_peer_id = 1
	_on_network_powerup_collected(entity_id, collector_peer_id)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_powerup_magnet(entity_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _despawned_entity_ids.has(entity_id):
		return
	if not _entities.has(entity_id):
		return
	var node: Node = _entities[entity_id]
	if not is_instance_valid(node) or not node.has_method("start_magnet"):
		return
	var requester_peer := multiplayer.get_remote_sender_id()
	var player_node: Node2D = _players.get(requester_peer)
	if player_node and is_instance_valid(player_node):
		node.start_magnet(player_node)
		return
	if _player and is_instance_valid(_player):
		node.start_magnet(_player)

func _spawn_asteroid() -> void:
	var asteroid = _asteroid_scene.instantiate()
	var side := randi() % 4
	var screen := get_viewport_rect().size
	match side:
		0: asteroid.position = Vector2(randf_range(60, screen.x - 60), -40)
		1: asteroid.position = Vector2(randf_range(60, screen.x - 60), screen.y + 40)
		2: asteroid.position = Vector2(-40, randf_range(60, screen.y - 60))
		3: asteroid.position = Vector2(screen.x + 40, randf_range(60, screen.y - 60))
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		asteroid.name = str(eid)
		asteroid.entity_id = eid
		_entities[eid] = asteroid
		_rpc_spawn_asteroid.rpc(eid, asteroid.position.x, asteroid.position.y)
	add_child(asteroid)

func _on_network_asteroid_destroyed(entity_id: int) -> void:
	if not multiplayer.is_server():
		return
	_despawned_entity_ids[entity_id] = true
	if _entities.has(entity_id):
		_entities.erase(entity_id)
	_rpc_despawn_entity.rpc(entity_id)

func _on_elite_spawn_requested() -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	if _elite != null and is_instance_valid(_elite):
		return
	call_deferred("_spawn_elite")

func _spawn_elite() -> void:
	_show_elite_warning()
	GameState.elite_encounter_count += 1
	_elite = _elite_scene.instantiate()
	_elite.position = Vector2(640, -60)
	var elite_mult: float = 1.0 + (GameState.elite_encounter_count - 1) * 0.1
	_elite.set_difficulty(elite_mult)
	if _player and is_instance_valid(_player):
		_elite.set_target(_player)
	_elite.elite_died.connect(_on_elite_died)
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		_elite.entity_id = eid
		_entities[eid] = _elite
		_rpc_spawn_elite.rpc(eid, elite_mult)
	add_child(_elite)
	var tween := create_tween()
	tween.tween_property(_elite, "position", Vector2(640, 120), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_elite_died() -> void:
	if _elite != null:
		var eid: int = _elite.entity_id
		if _entities.has(eid):
			_entities.erase(eid)
		if multiplayer.is_server():
			_rpc_despawn_entity.rpc(eid)
	_elite = null
	GameState.post_elite_multiplier = 1.0 + GameState.elite_encounter_count * 0.05
	if _pending_boss_level > 0 and GameState.game_running:
		var pending_level: int = _pending_boss_level
		_pending_boss_level = 0
		call_deferred("_on_boss_spawn_requested", pending_level)

func _show_elite_warning() -> void:
	var warning := Label.new()
	warning.text = "警告: 精英怪 来袭"
	warning.add_theme_font_size_override("font_size", 36)
	warning.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, 1.0))
	warning.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	warning.add_theme_constant_override("shadow_outline_size", 2)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning.position = Vector2(0, 300)
	warning.size = Vector2(1280, 60)
	warning.z_index = 100
	add_child(warning)
	var tween := create_tween()
	tween.tween_property(warning, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.2)
	tween.tween_property(warning, "modulate:a", 0.0, 0.5)
	tween.tween_callback(warning.queue_free)

## ── Boss 系统 ──────────────────────────────────────────────

func _on_boss_spawn_requested(level: int) -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	if _boss != null and is_instance_valid(_boss):
		return
	if not GameState.game_running:
		return
	if _elite != null and is_instance_valid(_elite):
		## 精英仍在场时，缓存本次 Boss 触发，待精英死亡后立即补发
		_pending_boss_level = maxi(_pending_boss_level, level)
		return
	_pending_boss_level = 0
	_show_boss_warning()
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if not GameState.game_running:
			return
		call_deferred("_spawn_boss", level)
	)

func _spawn_boss(level: int) -> void:
	_enter_boss_fight_mode()
	_boss = _boss_scene.instantiate()
	_boss.position = Vector2(640, -80)
	var variant_id := _pick_boss_variant_id()
	_current_boss_variant_id = variant_id
	if _boss.has_method("set_sprite_variant"):
		_boss.set_sprite_variant(variant_id)
	_boss.setup(level)
	if _player and is_instance_valid(_player):
		_boss.set_target(_player)
	_boss.boss_died.connect(_on_boss_died)
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		_boss.entity_id = eid
		_entities[eid] = _boss
		_rpc_spawn_boss.rpc(eid, level, variant_id)
	add_child(_boss)
	var tween := create_tween()
	tween.tween_property(_boss, "position", Vector2(640, 160), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _pick_boss_variant_id() -> int:
	var variant_count := 0
	for i in range(1, 100):
		var p := "res://assets/sprites/enemies/boss/boss_%02d.png" % i
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			break
		variant_count += 1
	if variant_count <= 0:
		return 0

	if _boss_variant_cycle.is_empty():
		for id in range(1, variant_count + 1):
			_boss_variant_cycle.append(id)
		_boss_variant_cycle.shuffle()

	if _boss_variant_cycle.size() >= 2 and _boss_variant_cycle[0] == _boss_variant_last:
		var tmp: int = _boss_variant_cycle[0]
		_boss_variant_cycle[0] = _boss_variant_cycle[1]
		_boss_variant_cycle[1] = tmp

	var picked: int = _boss_variant_cycle.pop_front()
	_boss_variant_last = picked
	return picked

func _on_boss_died() -> void:
	if _boss != null:
		var eid: int = _boss.entity_id
		if _entities.has(eid):
			_entities.erase(eid)
		if multiplayer.is_server():
			_rpc_despawn_entity.rpc(eid)
	_boss = null
	GameState.force_set_boss_active(false)
	_exit_boss_fight_mode()
	_show_reward_panel()

func _enter_boss_fight_mode() -> void:
	_boss_fight_active = true
	_clear_non_boss_entities()
	if _bg_color:
		_bg_color.color = Color(0.14, 0.03, 0.03, 1.0)
	if BGM and BGM.has_method("play_boss_bgm"):
		BGM.play_boss_bgm()

func _exit_boss_fight_mode() -> void:
	_boss_fight_active = false
	if _bg_color:
		_bg_color.color = Color(0.06, 0.06, 0.12, 1.0)
	if BGM and BGM.has_method("play_bgm"):
		BGM.play_bgm()

func _clear_non_boss_entities() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == _boss:
			continue
		if n and is_instance_valid(n):
			n.queue_free()
	for a in get_tree().get_nodes_in_group("asteroids"):
		if a and is_instance_valid(a):
			a.queue_free()
	for b in get_tree().get_nodes_in_group("player_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for p in get_tree().get_nodes_in_group("powerups"):
		if p and is_instance_valid(p):
			p.queue_free()

func _show_boss_warning() -> void:
	var screen := get_viewport_rect().size
	var banner_h: float = maxf(96.0, screen.y * 0.16)
	var banner_y := screen.y * 0.28

	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)

	var overlay := ColorRect.new()
	overlay.color = Color(0.08, 0.0, 0.0, 0.0)
	overlay.position = Vector2(0, banner_y)
	overlay.size = Vector2(screen.x, banner_h)
	cl.add_child(overlay)

	var warning := Label.new()
	warning.text = "BOSS 来袭！"
	warning.add_theme_color_override("font_color", Color(1.0, 0.15, 0.25, 1))
	warning.add_theme_font_size_override("font_size", 52)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning.position = Vector2(0, banner_y)
	warning.size = Vector2(screen.x, banner_h)
	warning.modulate = Color(1, 1, 1, 0)
	cl.add_child(warning)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.72, 0.2)
	tween.parallel().tween_property(warning, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.0)
	tween.tween_property(overlay, "color:a", 0.0, 0.3)
	tween.parallel().tween_property(warning, "modulate:a", 0.0, 0.3)
	tween.tween_callback(cl.queue_free)

var _reward_panel_scene = preload("res://scripts/reward_panel.gd")

func _show_reward_panel() -> void:
	var panel := _reward_panel_scene.new()
	panel.z_index = 200
	panel.setup()
	panel.reward_chosen.connect(_on_reward_chosen)
	add_child(panel)

func _on_reward_chosen(reward_type: String) -> void:
	if _player and is_instance_valid(_player) and _player.has_method("_update_appearance"):
		_player._update_appearance()

func _on_player_died() -> void:
	GameState.stop_game()
	_pending_boss_level = 0
	_clear_runtime_entities_on_game_over()
	_show_death_marquee()

func _on_game_over_triggered(final_score: int, final_level: int) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_force_game_over.rpc(final_score, final_level)
	_on_player_died()

@rpc("authority", "reliable", "call_remote")
func _rpc_force_game_over(final_score: int, final_level: int) -> void:
	GameState.game_running = false
	_clear_runtime_entities_on_game_over()
	if _hud and is_instance_valid(_hud) and _hud.has_method("_on_game_over"):
		_hud._on_game_over(final_score, final_level)

func _clear_runtime_entities_on_game_over() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("asteroids"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("powerups"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("player_bullets"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy_bullets"):
		if n and is_instance_valid(n):
			n.queue_free()

func _show_death_marquee() -> void:
	var msg: String = GameState.death_message
	if msg.is_empty():
		msg = "被击落"
	_show_death_marquee_text(msg)


func _show_death_marquee_text(msg: String) -> void:
	var banner := Label.new()
	var screen := get_viewport_rect().size
	banner.text = "☠  " + msg + "  ☠"
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	banner.add_theme_constant_override("shadow_outline_size", 2)
	banner.horizontal_alignment = 1
	banner.position = Vector2(0, 20)
	banner.size = Vector2(screen.x, 36)
	banner.z_index = 200
	add_child(banner)

	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_property(banner, "modulate:a", 0.0, 3.0)
	tween.tween_callback(banner.queue_free)

func _restart_on_touch() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		_restart()

func _on_level_up(_new_level: int) -> void:
	if _player and _player.has_method("on_level_up"):
		_player.on_level_up()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not GameState.game_running:
		if OS.has_feature("android") or OS.has_feature("ios"):
			_restart()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and not GameState.game_running:
		_restart()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _restart() -> void:
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_rpc_restart_game.rpc()
		return
	get_tree().reload_current_scene()

@rpc("authority", "reliable", "call_local")
func _rpc_restart_game() -> void:
	get_tree().reload_current_scene()

## ── 多人模式 RPC ──────────────────────────────────────────────

## Client → Host：请求一次完整玩家同步
@rpc("any_peer", "reliable", "call_remote")
func _request_player_sync() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	for peer_id: int in _players:
		var player_node: Node2D = _players[peer_id]
		if is_instance_valid(player_node):
			_rpc_spawn_networked_player.rpc_id(requester, peer_id, player_node.position.x, player_node.position.y)


## Host → Client：生成玩家节点
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_networked_player(p_peer_id: int, pos_x: float, pos_y: float) -> void:
	if not NetworkManager.is_online():
		return
	if _players.has(p_peer_id):
		return
	var player := _player_scene.instantiate()
	player.name = str(p_peer_id)
	player.position = Vector2(pos_x, pos_y)
	add_child(player)
	player.died.connect(_on_networked_player_died.bind(p_peer_id))
	_players[p_peer_id] = player
	if p_peer_id == multiplayer.get_unique_id():
		_player = player


## Host → Client：生成敌人幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_enemy(eid: int, etype: int, pos_x: float, pos_y: float, hp: int, spd: float, cd: float, drop: float, mult: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	var enemy = _enemy_scene.instantiate()
	enemy.name = str(eid)
	enemy.entity_id = eid
	enemy._is_network_ghost = true
	enemy.enemy_type = etype
	enemy.position = Vector2(pos_x, pos_y)
	enemy.health = hp
	enemy.move_speed = spd
	enemy.shoot_cooldown = cd
	enemy.drop_chance = drop
	if _player and is_instance_valid(_player):
		enemy.set_target(_player)
	_entities[eid] = enemy
	add_child(enemy)

## Host → Client：生成精英幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_elite(eid: int, elite_mult: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	_elite = _elite_scene.instantiate()
	_elite.name = str(eid)
	_elite.entity_id = eid
	_elite._is_network_ghost = true
	_elite.position = Vector2(640, -60)
	_elite.set_difficulty(elite_mult)
	if _player and is_instance_valid(_player):
		_elite.set_target(_player)
	_entities[eid] = _elite
	add_child(_elite)

## Host → Client：生成 Boss 幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_boss(eid: int, level: int, variant_id: int) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	_boss = _boss_scene.instantiate()
	_boss.name = str(eid)
	_boss.entity_id = eid
	_boss._is_network_ghost = true
	_boss.position = Vector2(640, -80)
	if _boss.has_method("set_sprite_variant"):
		_boss.set_sprite_variant(variant_id)
	_boss.setup(level)
	if _player and is_instance_valid(_player):
		_boss.set_target(_player)
	_entities[eid] = _boss
	add_child(_boss)

## Host → Client：生成掉落物幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_powerup(eid: int, powerup_type: String, pos_x: float, pos_y: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	var pu = _powerup_scene.instantiate()
	pu.name = str(eid)
	pu.entity_id = eid
	pu._is_network_ghost = true
	pu.position = Vector2(pos_x, pos_y)
	pu.setup(powerup_type)
	_entities[eid] = pu
	add_child(pu)

@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_asteroid(eid: int, pos_x: float, pos_y: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	var asteroid = _asteroid_scene.instantiate()
	asteroid.name = str(eid)
	asteroid.entity_id = eid
	asteroid._is_network_ghost = true
	asteroid.position = Vector2(pos_x, pos_y)
	_entities[eid] = asteroid
	add_child(asteroid)

## Host → Client：销毁实体
@rpc("authority", "reliable", "call_remote")
func _rpc_despawn_entity(eid: int) -> void:
	_despawned_entity_ids[eid] = true
	if _entities.has(eid):
		var node = _entities[eid]
		if is_instance_valid(node):
			node.queue_free()
		_entities.erase(eid)
	## 兜底：若字典丢失或出现重复实例，按 name/entity_id 全量清理残留节点。
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if n.name == str(eid) or (n.has_method("get_entity_id") and int(n.get_entity_id()) == eid):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("powerups"):
		if not is_instance_valid(n):
			continue
		if n.name == str(eid):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(n):
			continue
		if n.name == str(eid):
			n.queue_free()

## Host → Client：实体位置批量同步（5Hz）
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_positions(data: PackedFloat64Array) -> void:
	var i := 0
	while i < data.size():
		var eid := int(data[i])
		var x := data[i + 1]
		var y := data[i + 2]
		i += 3
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			_entities[eid].global_position = Vector2(x, y)

## Host：打包所有实体位置
func _batch_sync_entity_positions() -> void:
	if _entities.is_empty():
		return
	var data := PackedFloat64Array()
	for eid: int in _entities:
		var node = _entities[eid]
		if is_instance_valid(node):
			data.append(eid as float)
			data.append(node.global_position.x)
			data.append(node.global_position.y)
	if data.size() > 0:
		_rpc_sync_entity_positions.rpc(data)

## 子弹同步 ──────────────────────────────────────────────────

## 注册一颗子弹生成（由 enemy/boss/player 调用）
func register_bullet_spawn(pos: Vector2, angle: float, damage: float, is_player: bool, level: int, speed: float, color: Color = Color(1,1,1,1)) -> void:
	if not NetworkManager.is_online():
		return
	_pending_bullet_spawns.append([pos.x, pos.y, angle, damage, is_player, level, speed, color.r, color.g, color.b])

## 每帧 flush 待发送子弹
func _flush_bullet_spawns() -> void:
	if _pending_bullet_spawns.is_empty():
		return
	var data := _pending_bullet_spawns.duplicate()
	_pending_bullet_spawns.clear()
	if multiplayer.is_server():
		_rpc_spawn_bullets.rpc(data)
	else:
		_rpc_spawn_bullets.rpc_id(1, data)

## 注册激光生成（Host 广播；Client 上报 Host）
func register_laser_spawn(pos: Vector2, angle: float, damage: float) -> void:
	if not NetworkManager.is_online():
		return
	_pending_laser_spawns.append([pos.x, pos.y, angle, damage])

## 每帧 flush 待发送激光
func _flush_laser_spawns() -> void:
	if _pending_laser_spawns.is_empty():
		return
	var data := _pending_laser_spawns.duplicate()
	_pending_laser_spawns.clear()
	if multiplayer.is_server():
		_rpc_spawn_lasers.rpc(data)
	else:
		_rpc_spawn_lasers.rpc_id(1, data)

## Host → Client（或 Client → Host）：刷出子弹视觉副本
@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_bullets(data: Array) -> void:
	if not NetworkManager.is_online():
		return
	## Client → Host：Host 接收后需要再广播一次，确保加入端能看到自己的子弹。
	if multiplayer.is_server():
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id > 1:
			_rpc_spawn_bullets.rpc(data)
	for entry in data:
		var bullet := Pool.acquire("bullet", _bullet_scene)
		if bullet == null:
			continue
		add_child(bullet)
		bullet.setup(
			Vector2(entry[0], entry[1]),  # pos
			entry[2],                      # angle
			entry[3] as int,               # damage
			bool(entry[4]),                # is_player
			entry[5],                      # level
			entry[6]                       # speed
		)
		if entry.size() > 7:
			bullet.modulate = Color(entry[7], entry[8], entry[9], 1.0)
		if not multiplayer.is_server() and bullet.has_method("set_network_ghost"):
			bullet.set_network_ghost(true)

## 激光同步：
## - Client -> Host：上报激光发射请求（Host 生成权威激光并回广播）
## - Host -> Client：广播激光视觉（客户端仅视觉不结算伤害）
@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_lasers(data: Array) -> void:
	if not NetworkManager.is_online():
		return
	if multiplayer.is_server():
		for entry in data:
			var bolt = _laser_scene.instantiate()
			add_child(bolt)
			bolt.setup(Vector2(entry[0], entry[1]), entry[2], entry[3])
		_rpc_spawn_lasers.rpc(data)
		return
	for entry in data:
		var bolt = _laser_scene.instantiate()
		add_child(bolt)
		bolt.setup(Vector2(entry[0], entry[1]), entry[2], entry[3])
		if bolt.has_method("set_network_ghost"):
			bolt.set_network_ghost(true)
