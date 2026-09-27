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
var _boss_ultimate_laser_visual_script = preload("res://scripts/boss_ultimate_laser_visual.gd")
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
var _last_boss_hud_phase: String = ""
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
var _entity_target_positions: Dictionary = {}
## { peer_id : 远端玩家节点的目标坐标 }，客户端插值用
var _player_target_positions: Dictionary = {}
var _despawned_entity_ids: Dictionary = {}
var _entity_sync_timer: float = 0.0
var _health_sync_timer: float = 0.0
var _player_report_timer: float = 0.0
var _last_entity_resync_request_msec: int = 0
var _boss_reward_claimed_peers: Dictionary = {}
const ENTITY_SYNC_INTERVAL: float = 0.022
const ENTITY_SYNC_STRIDE: int = 3
const ENTITY_SHIELD_SYNC_STRIDE: int = 3
const ENTITY_ROTATION_SYNC_STRIDE: int = 2
const ENTITY_RESYNC_REQUEST_INTERVAL_MSEC: int = 750
## 星空平铺贴图边长（像素）。必须与 star 落点避开边缘的规则配套：
## 贴图内不放跨界星星，滚动时按该边长取模循环即可无缝衔接。
## 取 512 而非更小：256 的贴图在 1280 宽的屏幕上会横排重复 5 次，
## 肉眼能直接看出网格状重复（实测截图确认）；512 只重复 2.5 次。
const STAR_FIELD_TILE: int = 512
## 玩家极速兜底值（motion_controller.move_speed 默认 260）。
## 正常情况走 player.get_max_move_speed()，这里只作为玩家节点尚未就绪时的回退。
const PLAYER_MOVE_SPEED_FALLBACK: float = 260.0
## 敌人移动速度上限 = 玩家极速的 80%。
## 弹幕可读性是弹幕射击的第一支柱：玩家唯一的规避手段是走位，
## 敌人一旦快过玩家，玩家就既追不上也躲不开，画面必然糊成一片。
## 原公式 12 级就让 type2 达到 277 px/s（玩家 260）、30 级 1716 px/s。
const ENEMY_SPEED_MAX_RATIO: float = 0.8
const ENEMY_SPEED_MIN: float = 40.0
## 敌速随等级的成长斜率（原为 level*6，太陡）
const ENEMY_SPEED_PER_LEVEL: float = 3.0
const ENEMY_SPEED_PER_TYPE: float = 8.0
## 敌速只吃一点点精英乘区：速度是可读性，血量才是成长感
const ENEMY_SPEED_ELITE_STEP: float = 0.01
const ENEMY_SPEED_ELITE_MAX: float = 1.3
## 精英乘区封顶（原为 1 + 场次*0.05 无上限，20 级已 3.85、40 级 11.7）
const POST_ELITE_MULT_STEP: float = 0.02
const POST_ELITE_MULT_MAX: float = 2.2
## 玩家位置同步：[peer_id, x, y, rotation]，与实体同步同频（约 45Hz）
const PLAYER_SYNC_STRIDE: int = 4
## 待发送的子弹生成数据（Host → Client 或 Client → Host）
var _pending_bullet_spawns: Array = []
var _pending_laser_spawns: Array = []
var _alive_players: Dictionary = {}
var _client_bg_frame_skip: int = 0
var _fallback_in_progress: bool = false
var _last_elite_shield_break_banner_msec: int = -1000000

const MODE_SWITCH_PROMPT_HOLD_SECONDS: float = 5.0
const DEATH_MARQUEE_HOLD_SECONDS: float = 0.5
const DEATH_MARQUEE_FADE_SECONDS: float = 3.0

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
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)
	GameState.elite_spawn_requested.connect(_on_elite_spawn_requested)
	GameState.boss_spawn_requested.connect(_on_boss_spawn_requested)
	GameState.game_over.connect(_on_game_over_triggered)
	_debug_log_variant_assets()
	var online := NetworkManager.is_online()
	print("[Main] online=", online)
	if online and not multiplayer.is_server():
		_apply_client_perf_profile()

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
				push_warning("[Main] 同步后未找到本地玩家节点，向 Host 请求补生成（peer_id=%d）" % my_id)
				_request_spawn_self.rpc_id(1, my_id)
				for _retry in 60:
					node = get_node_or_null(str(my_id))
					if node:
						break
					await get_tree().process_frame
				if node == null:
					push_error("[Main] 仍未找到本地玩家节点（peer_id=%d），本机将无法输入/开火" % my_id)
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

## 生成一张可无缝平铺的星空贴图。
## count 是这块贴图里的星星数量，size_min/size_max 是单颗像素直径，
## bright_min/bright_max 是亮度范围，colored=true 时给近景星加色相变化。
static func _build_star_tile(count: int, size_min: int, size_max: int,
		bright_min: float, bright_max: float, colored: bool) -> ImageTexture:
	var img := Image.create(STAR_FIELD_TILE, STAR_FIELD_TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(count):
		var size: int = randi_range(size_min, size_max)
		var b: float = randf_range(bright_min, bright_max)
		var tint := Color(b, b * 0.88, b * randf_range(0.85, 1.25), 1.0)
		if colored:
			match randi() % 5:
				0: tint = Color(b, b * 0.9, b, 1.0)
				1: tint = Color(b, b * 0.7, b * 0.6, 1.0)
				2: tint = Color(b * 0.5, b * 0.8, b, 1.0)
				3: tint = Color(b * 0.85, b * 0.7, b * 0.7, 1.0)
				_: tint = Color(b * 0.7, b * 0.8, b, 1.0)
		## 贴图边缘的星星会平铺时在接缝处重复，因此避开边缘一格
		var ox: int = randi_range(1, STAR_FIELD_TILE - size - 1)
		var oy: int = randi_range(1, STAR_FIELD_TILE - size - 1)
		var half: float = float(size) / 2.0
		var centre: float = float(size) * 0.5
		for y in range(size):
			for x in range(size):
				var dx: float = float(x) - centre
				var dy: float = float(y) - centre
				var d: float = sqrt(dx * dx + dy * dy)
				if d >= half:
					continue
				## 近景大星带柔和衰减，远景小星保持硬边像素感
				var a: float = 1.0 if size <= 3 else 1.0 - (d / half) * (d / half)
				img.set_pixel(ox + x, oy + y, Color(tint.r, tint.g, tint.b, a))
	return ImageTexture.create_from_image(img)

func _create_parallax_background() -> void:
	if _bg_color:
		_bg_color.color = Color(0.06, 0.06, 0.12, 1.0)
		_bg_color.z_index = -100

	## 星空从「每颗星一个 Sprite2D」改为「每层一张平铺贴图」。
	## 旧实现是 180+90+35 = 305 个节点、305 张各自独立的 2~12px 贴图，
	## 每帧全部移动，既无法合批也吃满 draw call；实测在本机（AMD 5300M）
	## 只有 1 个敌人 12 颗子弹时也只有 106 fps，够不到 120。
	## 新实现每层 1 个节点 + 1 张 512×512 可平铺贴图，draw call 从 305 降到 3。
	##
	## 星星数量按**旧实现的实际密度**反推，而不是随手取值：
	## 旧实现 305 颗铺在 1500×920 的活动区域 = 每 4525 px² 一颗。
	## 512×512 贴图下对应 far=34 / mid=17 / near=7。
	## （第一版按 256 贴图取 120/60/22，密度是原来的 14 倍，弹幕可读性
	##   被背景吃掉——对弹幕射击来说这是比"看出贴图重复"严重得多的问题。）
	var star_tiles: Array = [
		_build_star_tile(34, 2, 2, 0.3, 0.7, false),
		_build_star_tile(17, 3, 5, 0.5, 0.9, false),
		_build_star_tile(7, 6, 12, 0.7, 1.0, true),
	]
	var layer_defs: Array = [
		{speed = 12.0, z = -10},
		{speed = 24.0, z = -9},
		{speed = 40.0, z = -8},
	]
	for i in range(layer_defs.size()):
		var def: Dictionary = layer_defs[i]
		var sprite := Sprite2D.new()
		sprite.texture = star_tiles[i]
		## 平铺需要纹理重复；region 覆盖「一屏 + 一个贴图边长」，
		## 滚动时露出的下一圈正好补上移出的部分
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, STAR_FIELD_TILE * 4, STAR_FIELD_TILE * 3)
		sprite.centered = false
		sprite.position = Vector2.ZERO
		sprite.z_index = int(def.z)
		add_child(sprite)
		_bg_layers.append({nodes = [sprite], speed = float(def.speed)})


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
	GameState.ensure_player_state(_player.peer_id)
	_alive_players[_player.peer_id] = true
	_player.died.connect(_on_player_died)


func _get_networked_player_spawn_position(p_peer_id: int) -> Vector2:
	var screen := get_viewport_rect().size
	if p_peer_id == 1:
		return Vector2(screen.x * 0.32, screen.y * 0.7)
	return Vector2(screen.x * 0.68, screen.y * 0.7)


func _spawn_networked_player(p_peer_id: int, announce: bool) -> void:
	if not multiplayer.is_server():
		return
	if _players.has(p_peer_id):
		return
	var player := _player_scene.instantiate()
	player.name = str(p_peer_id)
	player.position = _get_networked_player_spawn_position(p_peer_id)
	add_child(player)
	GameState.ensure_player_state(p_peer_id)
	_alive_players[p_peer_id] = true
	player.died.connect(_on_networked_player_died.bind(p_peer_id))
	_players[p_peer_id] = player
	## 兼容 _player 引用（指向本机玩家）
	var my_id := multiplayer.get_unique_id()
	if p_peer_id == my_id:
		_player = player
	if player.has_method("on_level_up"):
		player.on_level_up()
	if announce:
		_rpc_spawn_networked_player.rpc(p_peer_id, player.position.x, player.position.y)


## 多人模式：新 peer 连接时（只在服务器端触发）
func _on_multiplayer_player_connected(p_peer_id: int) -> void:
	if multiplayer.is_server():
		_spawn_networked_player(p_peer_id, true)
		## Host 自己的玩家节点是在 main._ready() 里 announce 的，那时新 peer 还没连上，
		## 广播进了虚空。新加入端只能靠主动请求补齐，而请求可能在 Host 建好
		## _players 之前就到达（Host 刚进战斗场景就有人 join），此时拿到空名单，
		## 客户端会永久缺一个远端幽灵节点（画面上少一个人、也少一份同步）。
		## 所以这里在 peer 连上的瞬间主动补发一次完整名单。
		_send_player_snapshot_to(p_peer_id)


## Host → 指定 peer：补发当前全部玩家节点（生成 + 坐标）
func _send_player_snapshot_to(peer_id: int) -> void:
	if peer_id <= 0:
		return
	for pid: int in _players:
		var player_node: Node2D = _players[pid]
		if is_instance_valid(player_node):
			_rpc_spawn_networked_player.rpc_id(peer_id, pid, player_node.position.x, player_node.position.y)


## 多人模式：peer 断线时清理其玩家节点
func _on_multiplayer_player_disconnected(p_peer_id: int) -> void:
	if _players.has(p_peer_id):
		var node: Node2D = _players[p_peer_id]
		if is_instance_valid(node):
			node.queue_free()
		_players.erase(p_peer_id)
	_alive_players.erase(p_peer_id)
	_player_target_positions.erase(p_peer_id)
	if multiplayer.is_server() and not _alive_players.is_empty():
		_fallback_to_single_player("队友已退出，切换为单人模式")
	elif _alive_players.is_empty() and multiplayer.is_server():
		_fallback_to_single_player("联机已断开，切换为单人模式")
	else:
		_refresh_primary_player_target()


## 多人模式：服务器断开（Client 端触发）
func _on_multiplayer_server_disconnected() -> void:
	_fallback_to_single_player("房主已退出，切换为单人模式")


## 多人模式：某玩家死亡回调
func _on_networked_player_died(p_peer_id: int) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_despawn_player.rpc(p_peer_id)
	_rpc_despawn_player(p_peer_id)
	_players.erase(p_peer_id)
	_alive_players.erase(p_peer_id)
	## 合作模式：仅当全员死亡（或全部离场）才结束。
	if _alive_players.is_empty():
		_finish_multiplayer_game_over(GameState.score, GameState.level)
	else:
		_refresh_primary_player_target()

func _fallback_to_single_player(message: String = "") -> void:
	if _fallback_in_progress:
		return
	_fallback_in_progress = true
	var reload_delay := 0.0
	if not message.is_empty():
		reload_delay = MODE_SWITCH_PROMPT_HOLD_SECONDS
		_show_death_marquee_text(message, MODE_SWITCH_PROMPT_HOLD_SECONDS)
	_clear_network_runtime_state()
	NetworkManager.disconnect_network()
	call_deferred("_reload_as_single_player_clean", reload_delay)

func _clear_network_runtime_state() -> void:
	_pending_bullet_spawns.clear()
	_pending_laser_spawns.clear()
	_entity_target_positions.clear()
	_player_target_positions.clear()
	_despawned_entity_ids.clear()
	_boss_reward_claimed_peers.clear()
	_entities.clear()
	_players.clear()
	_alive_players.clear()
	_clear_runtime_entities_on_game_over()
	if Pool and Pool.has_method("reset_all"):
		Pool.reset_all()

func _reload_as_single_player_clean(delay_seconds: float = 0.0) -> void:
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")

@rpc("authority", "reliable", "call_remote")
func _rpc_despawn_player(p_peer_id: int) -> void:
	if not _players.has(p_peer_id):
		return
	var was_local_player := NetworkManager.is_online() \
		and multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer != null \
		and p_peer_id == multiplayer.get_unique_id()
	var node: Node = _players[p_peer_id]
	if is_instance_valid(node):
		node.queue_free()
	_players.erase(p_peer_id)
	_alive_players.erase(p_peer_id)
	_player_target_positions.erase(p_peer_id)
	if _player != null and is_instance_valid(_player) and _player.name == str(p_peer_id):
		_player = null
	if was_local_player and not _alive_players.is_empty():
		_show_death_marquee_text("你已坠毁，等待队友继续战斗")

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
	_update_boss_hud()

	## 多人：Host 定期同步实体位置 + flush 子弹
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_entity_sync_timer -= delta
			if _entity_sync_timer <= 0.0:
				_entity_sync_timer = ENTITY_SYNC_INTERVAL
				_batch_sync_entity_positions()
				_batch_sync_players()
			_health_sync_timer -= delta
			if _health_sync_timer <= 0.0:
				_health_sync_timer = 0.1
				_batch_sync_entity_health()
		elif _player != null and is_instance_valid(_player):
			## 客户端只上报自己的坐标，由 Host 转发给其他端
			_player_report_timer -= delta
			if _player_report_timer <= 0.0:
				_player_report_timer = ENTITY_SYNC_INTERVAL
				_rpc_report_player_state.rpc_id(1, _player.peer_id,
					_player.global_position.x, _player.global_position.y, _player.rotation)
		## 客户端玩家的幽灵节点在 Host 侧也要插值
		_apply_player_interpolation(delta)
		_flush_bullet_spawns()
		_flush_laser_spawns()

	if NetworkManager.is_online() and not multiplayer.is_server():
		_client_bg_frame_skip += 1
		if _client_bg_frame_skip % 2 == 0:
			_scroll_background(delta * 2.0)
		_apply_entity_interpolation(delta)
		_apply_player_interpolation(delta)
		return
	_scroll_background(delta)

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
			## 平铺贴图：整层只有一个节点，按贴图边长取模滚动即可无缝循环，
			## 不再需要逐颗星越界后随机重置坐标。
			node.position.y += delta * spd
			if node.position.y > STAR_FIELD_TILE:
				node.position.y -= STAR_FIELD_TILE
			node.position.x += delta * spd * 0.15
			if node.position.x > STAR_FIELD_TILE:
				node.position.x -= STAR_FIELD_TILE

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

func _apply_client_perf_profile() -> void:
	## 加入端降低背景渲染负担，优先保障同屏战斗帧率。
	## 星空现在每层只有一个节点，不能再按节点删一半，改为把贴图调暗
	## （视觉上就是星星变少/变暗），nebula / planet 仍按节点减半。
	for layer in _bg_layers:
		var nodes: Array = layer.nodes
		for n in nodes:
			var node: Node2D = n as Node2D
			if node != null and is_instance_valid(node):
				node.modulate = Color(0.72, 0.72, 0.8, 1.0)
	for i in range(_nebulas.size() - 1, -1, -1):
		if i % 2 == 0:
			continue
		var neb: Node = _nebulas[i]
		if is_instance_valid(neb):
			neb.queue_free()
		_nebulas.remove_at(i)
	for i in range(_planets.size() - 1, -1, -1):
		if i % 2 == 0:
			continue
		var pl: Node = _planets[i]
		if is_instance_valid(pl):
			pl.queue_free()
		_planets.remove_at(i)

func _apply_entity_interpolation(delta: float) -> void:
	var alpha: float = clampf(delta * 18.0, 0.0, 1.0)
	for eid in _entity_target_positions.keys():
		if not _entities.has(eid):
			continue
		var node: Node2D = _entities[eid] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var target: Vector2 = _entity_target_positions[eid]
		node.global_position = node.global_position.lerp(target, alpha)


## 远端玩家插值：45Hz 同步包 + 60fps 渲染，直接 snap 会有轻微顿挫
## Host 和 Client 都要跑：Host 侧插值的是客户端玩家的幽灵节点
func _apply_player_interpolation(delta: float) -> void:
	var alpha: float = clampf(delta * 18.0, 0.0, 1.0)
	for pid: int in _player_target_positions.keys():
		if not _players.has(pid) or not is_instance_valid(_players[pid]):
			continue
		## 本机节点只由输入驱动，任何情况下都不接受远端坐标
		if NetworkManager.is_online() and pid == multiplayer.get_unique_id():
			continue
		var pnode: Node2D = _players[pid] as Node2D
		if pnode == null:
			continue
		pnode.global_position = pnode.global_position.lerp(_player_target_positions[pid], alpha)


## 敌速上限：优先取本机玩家的真实极速，玩家节点没就绪时用兜底常量。
## 做成访问口而不是常量，是为了让"玩家改速度"和"敌速上限"不会各改各的。
func _enemy_speed_cap() -> float:
	if _player != null and is_instance_valid(_player) and _player.has_method("get_max_move_speed"):
		var spd: float = float(_player.get_max_move_speed())
		if spd > 0.0:
			return spd * ENEMY_SPEED_MAX_RATIO
	return PLAYER_MOVE_SPEED_FALLBACK * ENEMY_SPEED_MAX_RATIO


## 敌人移动速度。设计意图见 docs/Design_Decisions.md「敌速与精英乘区拆开」：
## 速度是可读性属性，不吃满精英乘区，且硬性夹在玩家极速的 80% 以内。
## 做成 static 是为了让 tests/curve_probe.gd 能脱离场景直接回归这条曲线。
static func compute_enemy_speed(level: int, enemy_type: int,
		elite_count: int, speed_cap: float) -> float:
	var base: float = 40.0 + float(level) * ENEMY_SPEED_PER_LEVEL \
		+ float(enemy_type) * ENEMY_SPEED_PER_TYPE
	var speed_mult: float = minf(1.0 + float(elite_count) * ENEMY_SPEED_ELITE_STEP,
		ENEMY_SPEED_ELITE_MAX)
	return clampf(base * speed_mult, ENEMY_SPEED_MIN, speed_cap)


## 精英乘区：只该影响血量与开火频率，且必须有上限。
## 原公式 1 + 场次*0.05 无上限，精英每 20 击杀出一次、累计击杀随等级平方增长，
## 于是这个乘区是指数的：20 级 3.85、40 级 11.7。
static func compute_post_elite_multiplier(elite_count: int) -> float:
	return minf(1.0 + float(elite_count) * POST_ELITE_MULT_STEP, POST_ELITE_MULT_MAX)

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
	enemy.move_speed = compute_enemy_speed(GameState.level, enemy_type,
		GameState.elite_encounter_count, _enemy_speed_cap())
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
	_entity_target_positions.erase(entity_id)
	if _entities.has(entity_id):
		_entities.erase(entity_id)
	if multiplayer.is_server():
		_rpc_despawn_entity.rpc(entity_id)
		GameState._rpc_play_sfx.rpc("enemy_death")

## Client → Host（经 GameState 转发）：敌人受击
func _on_network_enemy_hit(entity_id: int, damage: int, attacker_peer_id: int = -1) -> void:
	if _entities.has(entity_id):
		var enemy = _entities[entity_id]
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.take_damage(damage, attacker_peer_id)

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
	var assigned_peer_id: int = int(powerup.get_meta("assigned_peer_id", 0))
	_rpc_spawn_powerup.rpc(eid, powerup_type, powerup.global_position.x, powerup.global_position.y, assigned_peer_id)

## Host：掉落物被拾取后广播销毁
func _on_network_powerup_collected(entity_id: int, collector_peer_id: int = 1) -> void:
	if not multiplayer.is_server():
		return
	var powerup_type := ""
	var feedback_pos := Vector2.ZERO
	if _entities.has(entity_id):
		var node = _entities[entity_id]
		if is_instance_valid(node) and node.has_method("get_powerup_type"):
			powerup_type = node.get_powerup_type()
			if node is Node2D:
				feedback_pos = (node as Node2D).global_position
			GameState.collect_powerup(powerup_type, collector_peer_id)
			_send_powerup_feedback(collector_peer_id, powerup_type, feedback_pos)
	if _despawned_entity_ids.has(entity_id):
		return
	_despawned_entity_ids[entity_id] = true
	_entity_target_positions.erase(entity_id)
	if _entities.has(entity_id):
		var node2 = _entities[entity_id]
		if is_instance_valid(node2):
			node2.queue_free()
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
	_entity_target_positions.erase(entity_id)
	if _entities.has(entity_id):
		var node: Node = _entities[entity_id]
		if is_instance_valid(node):
			node.queue_free()
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
	if _elite.has_signal("shield_broken_window_started"):
		_elite.shield_broken_window_started.connect(_on_elite_shield_broken_window_started)
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		_elite.entity_id = eid
		_entities[eid] = _elite
		_rpc_spawn_elite.rpc(eid, elite_mult)
		_rpc_show_elite_warning.rpc()
	add_child(_elite)
	var tween := create_tween()
	tween.tween_property(_elite, "position", Vector2(640, 120), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_elite_shield_broken_window_started() -> void:
	var eid := -1
	if _elite != null and is_instance_valid(_elite):
		eid = int(_elite.entity_id)
	_show_elite_shield_break_banner()
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_show_elite_shield_break_banner.rpc()
		if eid > 0:
			_rpc_elite_shield_destroyed.rpc(eid)

func _show_elite_shield_break_banner() -> void:
	var now := int(Time.get_ticks_msec())
	if now - _last_elite_shield_break_banner_msec < 600:
		return
	_last_elite_shield_break_banner_msec = now
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("护盾破裂，集火窗口", 0.8, Color(1.0, 0.9, 0.35, 1.0))

func _on_elite_died() -> void:
	if _elite != null:
		var eid: int = _elite.entity_id
		if _entities.has(eid):
			_entities.erase(eid)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_rpc_despawn_entity.rpc(eid)
	_elite = null
	GameState.post_elite_multiplier = compute_post_elite_multiplier(GameState.elite_encounter_count)
	if _pending_boss_level > 0 and GameState.game_running:
		call_deferred("_consume_pending_boss_spawn")

func _show_elite_warning() -> void:
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("裂隙猎手接近", 3.0, Color(1.0, 0.38, 0.15, 1.0))
		return
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
	if _has_active_boss():
		return
	if not GameState.game_running:
		return
	if _is_elite_blocking_boss_spawn():
		## 精英仍在场时，缓存本次 Boss 触发，待精英死亡后立即补发
		_pending_boss_level = maxi(_pending_boss_level, level)
		return
	_pending_boss_level = 0
	_show_boss_warning()
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if not GameState.game_running:
			return
		if _is_elite_blocking_boss_spawn():
			_pending_boss_level = maxi(_pending_boss_level, level)
			return
		call_deferred("_spawn_boss", level)
	)

func _is_elite_blocking_boss_spawn() -> bool:
	if _elite == null:
		return false
	if not is_instance_valid(_elite):
		_elite = null
		return false
	if _elite.is_queued_for_deletion():
		_elite = null
		return false
	return true

func _has_active_boss() -> bool:
	if _boss == null:
		return false
	if not is_instance_valid(_boss):
		_boss = null
		return false
	if _boss.is_queued_for_deletion():
		_boss = null
		return false
	return true

func _consume_pending_boss_spawn() -> void:
	if _pending_boss_level <= 0 or not GameState.game_running:
		return
	if _is_elite_blocking_boss_spawn():
		call_deferred("_consume_pending_boss_spawn")
		return
	var pending_level: int = _pending_boss_level
	_pending_boss_level = 0
	_on_boss_spawn_requested(pending_level)

func _spawn_boss(level: int) -> void:
	if _has_active_boss():
		return
	if _is_elite_blocking_boss_spawn():
		_pending_boss_level = maxi(_pending_boss_level, level)
		return
	_enter_boss_fight_mode()
	_boss_reward_claimed_peers.clear()
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
	if _boss.has_signal("phase_changed"):
		_boss.phase_changed.connect(_on_boss_phase_changed)
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
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_rpc_despawn_entity.rpc(eid)
	_boss = null
	_exit_boss_fight_mode()
	if _hud and _hud.has_method("hide_boss_status"):
		_hud.hide_boss_status()
	if NetworkManager.is_online() and multiplayer.is_server():
		_grant_random_boss_rewards_to_alive_players()
	elif not NetworkManager.is_online():
		_grant_random_boss_reward_to_peer(-1)

func _on_boss_phase_changed(phase_name: String) -> void:
	_last_boss_hud_phase = phase_name
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner(phase_name, 0.8, Color(1.0, 0.55, 0.85, 1.0))
	if NetworkManager.is_online() and multiplayer.is_server() and _boss != null:
		var vid: int = 1
		if _boss.has_method("get_sprite_variant_id"):
			vid = _boss.get_sprite_variant_id()
		_rpc_sync_boss_phase.rpc(phase_name, vid)

func _update_boss_hud() -> void:
	if _hud == null or not _hud.has_method("show_boss_status"):
		return
	if _boss != null and is_instance_valid(_boss) and _boss.has_method("get_network_health"):
		var phase_name := "压制校准"
		if _boss.has_method("get_phase_name"):
			phase_name = _boss.get_phase_name()
		_hud.show_boss_status(_boss.get_network_health(), _boss.get_network_max_health(), phase_name)
		if phase_name != _last_boss_hud_phase:
			_last_boss_hud_phase = phase_name
			if _hud.has_method("show_center_banner") and phase_name != "压制校准":
				_hud.show_center_banner(phase_name, 0.8, Color(1.0, 0.55, 0.85, 1.0))
	elif _hud.has_method("hide_boss_status"):
		_last_boss_hud_phase = ""
		_hud.hide_boss_status()

func _enter_boss_fight_mode() -> void:
	_boss_fight_active = true
	_clear_non_boss_entities()
	if _bg_color:
		_bg_color.color = Color(0.14, 0.03, 0.03, 1.0)
	if BGM and BGM.has_method("play_boss_bgm"):
		BGM.play_boss_bgm()
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_set_boss_bg.rpc(true)

func _exit_boss_fight_mode() -> void:
	_boss_fight_active = false
	if _bg_color:
		_bg_color.color = Color(0.06, 0.06, 0.12, 1.0)
	if BGM and BGM.has_method("play_bgm"):
		BGM.play_bgm()
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_set_boss_bg.rpc(false)

func _clear_non_boss_entities() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == _boss:
			continue
		if n and is_instance_valid(n):
			if NetworkManager.is_online() and multiplayer.is_server() and n.has_method("get_entity_id"):
				var despawn_eid: int = int(n.get_entity_id())
				if despawn_eid > 0:
					_despawned_entity_ids[despawn_eid] = true
					if _entities.has(despawn_eid):
						_entities.erase(despawn_eid)
					_rpc_despawn_entity.rpc(despawn_eid)
			n.queue_free()
	for a in get_tree().get_nodes_in_group("asteroids"):
		if a and is_instance_valid(a):
			if NetworkManager.is_online() and multiplayer.is_server() and a.has_method("get_entity_id"):
				var despawn_aid: int = int(a.get_entity_id())
				if despawn_aid > 0:
					_despawned_entity_ids[despawn_aid] = true
					if _entities.has(despawn_aid):
						_entities.erase(despawn_aid)
					_rpc_despawn_entity.rpc(despawn_aid)
			a.queue_free()
	for b in get_tree().get_nodes_in_group("player_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for p in get_tree().get_nodes_in_group("powerups"):
		if p and is_instance_valid(p):
			if NetworkManager.is_online() and multiplayer.is_server() and p.has_method("get"):
				var despawn_pid: int = int(p.get("entity_id"))
				if despawn_pid > 0:
					_despawned_entity_ids[despawn_pid] = true
					_entity_target_positions.erase(despawn_pid)
					if _entities.has(despawn_pid):
						_entities.erase(despawn_pid)
					_rpc_despawn_entity.rpc(despawn_pid)
			p.queue_free()

func _show_boss_warning() -> void:
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("裂隙母舰展开", 2.3, Color(1.0, 0.2, 0.25, 1.0))
		return
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

func _grant_random_boss_rewards_to_alive_players() -> void:
	var peer_ids := GameState.get_alive_player_ids()
	if peer_ids.is_empty():
		peer_ids = [1]
	for peer_id in peer_ids:
		_grant_random_boss_reward_to_peer(peer_id)

func _grant_random_boss_reward_to_peer(peer_id: int) -> void:
	var pool := _boss_reward_pool()
	if pool.is_empty():
		return
	_apply_boss_reward_for_peer(pool.pick_random(), peer_id)

func _apply_boss_reward_for_peer(reward_type: String, peer_id: int) -> void:
	if not _is_valid_boss_reward(reward_type):
		return
	var resolved_peer := peer_id if peer_id > 0 else 1
	if NetworkManager.is_online():
		if _boss_reward_claimed_peers.has(resolved_peer):
			return
		_boss_reward_claimed_peers[resolved_peer] = true
	GameState.apply_reward(reward_type, resolved_peer)
	if NetworkManager.is_online() and multiplayer.is_server() and GameState.has_method("force_sync_to_peer"):
		GameState.force_sync_to_peer(resolved_peer)
	_send_boss_reward_feedback(resolved_peer, reward_type)
	if _player and is_instance_valid(_player) and _player.has_method("_update_appearance"):
		_player._update_appearance()

func _is_valid_boss_reward(reward_type: String) -> bool:
	return reward_type in _boss_reward_pool()

func _boss_reward_pool() -> Array[String]:
	return ["laser_cd", "bullet_count", "damage", "speed"]

func _on_player_died() -> void:
	if NetworkManager.is_online():
		var peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null else 1
		_on_networked_player_died(peer_id)
		return
	if _player and is_instance_valid(_player):
		_alive_players.erase(_player.peer_id)
	GameState.stop_game()
	_pending_boss_level = 0
	_clear_runtime_entities_on_game_over()
	_show_death_marquee()
	if _hud and is_instance_valid(_hud) and _hud.has_method("_on_game_over"):
		_hud._on_game_over(GameState.score, GameState.level)

func _on_game_over_triggered(final_score: int, final_level: int) -> void:
	if NetworkManager.is_online() and not _alive_players.is_empty():
		return
	if NetworkManager.is_online():
		_finish_multiplayer_game_over(final_score, final_level)
		return
	_on_player_died()

func _finish_multiplayer_game_over(final_score: int, final_level: int) -> void:
	if not NetworkManager.is_online():
		_on_player_died()
		return
	GameState.stop_game()
	_pending_boss_level = 0
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_force_game_over.rpc(final_score, final_level)
	_clear_runtime_entities_on_game_over()
	_show_death_marquee()
	if _hud and is_instance_valid(_hud) and _hud.has_method("_on_game_over"):
		_hud._on_game_over(final_score, final_level)

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


func _show_death_marquee_text(msg: String, hold_seconds: float = DEATH_MARQUEE_HOLD_SECONDS) -> void:
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
	tween.tween_interval(hold_seconds)
	tween.tween_property(banner, "modulate:a", 0.0, DEATH_MARQUEE_FADE_SECONDS)
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
	_send_player_snapshot_to(requester)

## Client -> Host：请求确保本机玩家节点存在（修复偶发漏生成）
@rpc("any_peer", "reliable", "call_remote")
func _request_spawn_self(expected_peer_id: int = -1) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if expected_peer_id > 0 and expected_peer_id != sender:
		return
	_spawn_networked_player(sender, true)


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
	GameState.ensure_player_state(p_peer_id)
	player.died.connect(_on_networked_player_died.bind(p_peer_id))
	_players[p_peer_id] = player
	_alive_players[p_peer_id] = true
	if p_peer_id == multiplayer.get_unique_id():
		_player = player
	if player.has_method("on_level_up"):
		player.on_level_up()
	_refresh_primary_player_target()

func _refresh_primary_player_target() -> void:
	var new_target: Node2D = null
	if _players.is_empty():
		return
	var preferred_id := multiplayer.get_unique_id() if NetworkManager.is_online() else 1
	if _alive_players.has(preferred_id):
		if _players.has(preferred_id) and is_instance_valid(_players[preferred_id]):
			new_target = _players[preferred_id]
	if new_target == null and NetworkManager.is_online() and _alive_players.has(1):
		if _players.has(1) and is_instance_valid(_players[1]):
			new_target = _players[1]
	if new_target == null:
		for pid in _alive_players.keys():
			if _players.has(pid) and is_instance_valid(_players[pid]):
				new_target = _players[pid]
				break
	if new_target == null:
		return
	_player = new_target
	_retarget_hostile_entities(_player)

func _retarget_hostile_entities(target_player: Node2D) -> void:
	if target_player == null or not is_instance_valid(target_player):
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_method("set_target"):
			e.set_target(target_player)
	if _elite != null and is_instance_valid(_elite) and _elite.has_method("set_target"):
		_elite.set_target(target_player)
	if _boss != null and is_instance_valid(_boss) and _boss.has_method("set_target"):
		_boss.set_target(target_player)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_entity_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	if requester <= 0:
		return
	for eid in _entities.keys():
		var entity_id := int(eid)
		if _despawned_entity_ids.has(entity_id):
			continue
		var node: Node = _entities[eid]
		if is_instance_valid(node):
			_send_entity_spawn_to_peer(requester, entity_id, node)

func _request_entity_snapshot_from_host() -> void:
	if not NetworkManager.is_online() or multiplayer.is_server():
		return
	var now := int(Time.get_ticks_msec())
	if now - _last_entity_resync_request_msec < ENTITY_RESYNC_REQUEST_INTERVAL_MSEC:
		return
	_last_entity_resync_request_msec = now
	_rpc_request_entity_snapshot.rpc_id(1)

func _send_entity_spawn_to_peer(peer_id: int, eid: int, node: Node) -> void:
	if peer_id <= 0 or not is_instance_valid(node):
		return
	if node == _boss or node.is_in_group("boss"):
		var level := GameState.level
		var variant_id := _current_boss_variant_id
		if node.has_method("get_network_level"):
			level = int(node.get_network_level())
		if node.has_method("get_sprite_variant_id"):
			variant_id = int(node.get_sprite_variant_id())
		_rpc_spawn_boss.rpc_id(peer_id, eid, level, variant_id)
		return
	if node == _elite or (node.is_in_group("enemies") and node.has_method("get_network_shield")):
		_rpc_spawn_elite.rpc_id(peer_id, eid, GameState.post_elite_multiplier)
		return
	if node.is_in_group("powerups") and node.has_method("get_powerup_type"):
		var powerup_node := node as Node2D
		if powerup_node:
			var assigned_peer_id: int = int(node.get_meta("assigned_peer_id", 0))
			_rpc_spawn_powerup.rpc_id(peer_id, eid, node.get_powerup_type(), powerup_node.global_position.x, powerup_node.global_position.y, assigned_peer_id)
		return
	if node.is_in_group("asteroids"):
		var asteroid_node := node as Node2D
		if asteroid_node:
			_rpc_spawn_asteroid.rpc_id(peer_id, eid, asteroid_node.global_position.x, asteroid_node.global_position.y)
		return
	if node.is_in_group("enemies"):
		var enemy_node := node as Node2D
		if enemy_node:
			_rpc_spawn_enemy.rpc_id(
				peer_id,
				eid,
				int(node.get("enemy_type")),
				enemy_node.global_position.x,
				enemy_node.global_position.y,
				int(node.get("health")),
				float(node.get("move_speed")),
				float(node.get("shoot_cooldown")),
				float(node.get("drop_chance")),
				1.0
			)

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
	if _elite.has_signal("shield_broken_window_started"):
		_elite.shield_broken_window_started.connect(_on_elite_shield_broken_window_started)
	add_child(_elite)

## Host → Client：强制销毁精英护盾光晕（护盾同步包可能丢包或迟到）
@rpc("authority", "reliable", "call_remote")
func _rpc_elite_shield_destroyed(eid: int) -> void:
	var node: Node = null
	if _entities.has(eid) and is_instance_valid(_entities[eid]):
		node = _entities[eid]
	elif _elite and is_instance_valid(_elite) and int(_elite.entity_id) == eid:
		node = _elite
	if node and node.has_method("force_network_shield_destroyed"):
		node.force_network_shield_destroyed()

## Host → Client：同步 Boss 阶段变换
@rpc("authority", "reliable", "call_remote")
func _rpc_sync_boss_phase(phase_name: String, variant_id: int) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if _boss.has_method("set_sprite_variant"):
		_boss.set_sprite_variant(variant_id)
	if _boss.has_method("_apply_visual_state"):
		_boss._apply_visual_state()
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner(phase_name, 0.8, Color(1.0, 0.55, 0.85, 1.0))

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
	_boss.boss_died.connect(_on_boss_died)
	if _boss.has_signal("phase_changed"):
		_boss.phase_changed.connect(_on_boss_phase_changed)
	add_child(_boss)

## Host → Client：生成掉落物幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_powerup(eid: int, powerup_type: String, pos_x: float, pos_y: float, assigned_peer_id: int = 0) -> void:
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
	if assigned_peer_id > 0:
		pu.set_meta("assigned_peer_id", assigned_peer_id)
	_entities[eid] = pu
	add_child(pu)

func on_local_powerup_feedback(powerup_type: String, world_pos: Vector2) -> void:
	if _hud and _hud.has_method("show_pickup_toast"):
		_hud.show_pickup_toast(powerup_type, world_pos)
	if powerup_type == "core" and _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("冷却加速", 0.6, Color(1.0, 0.78, 0.24, 1.0))

func on_local_boss_reward_feedback(_reward_type: String) -> void:
	if _hud == null:
		return
	if _hud.has_method("show_boss_bonus_attribute_feedback"):
		_hud.show_boss_bonus_attribute_feedback()

func _send_powerup_feedback(peer_id: int, powerup_type: String, world_pos: Vector2) -> void:
	var target_peer := peer_id if peer_id > 0 else 1
	if target_peer == multiplayer.get_unique_id():
		on_local_powerup_feedback(powerup_type, world_pos)
	else:
		_rpc_show_powerup_feedback.rpc_id(target_peer, powerup_type, world_pos.x, world_pos.y)

func _send_boss_reward_feedback(peer_id: int, reward_type: String) -> void:
	var target_peer := peer_id if peer_id > 0 else 1
	if target_peer == multiplayer.get_unique_id():
		on_local_boss_reward_feedback(reward_type)
	else:
		_rpc_show_boss_reward_feedback.rpc_id(target_peer, reward_type)

@rpc("authority", "reliable", "call_remote")
func _rpc_show_powerup_feedback(powerup_type: String, pos_x: float, pos_y: float) -> void:
	on_local_powerup_feedback(powerup_type, Vector2(pos_x, pos_y))

@rpc("authority", "reliable", "call_remote")
func _rpc_show_boss_reward_feedback(reward_type: String) -> void:
	on_local_boss_reward_feedback(reward_type)

@rpc("authority", "reliable", "call_remote")
func _rpc_show_elite_warning() -> void:
	_show_elite_warning()

@rpc("authority", "reliable", "call_remote")
func _rpc_show_elite_shield_break_banner() -> void:
	_show_elite_shield_break_banner()

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
	_entity_target_positions.erase(eid)
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
		if n.name == str(eid) or (n.has_method("get_entity_id") and int(n.get_entity_id()) == eid):
			n.queue_free()

## Host → Client：实体位置批量同步
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_positions(data: PackedFloat32Array) -> void:
	var i := 0
	while i + ENTITY_SYNC_STRIDE - 1 < data.size():
		var eid := int(data[i])
		var x := data[i + 1]
		var y := data[i + 2]
		i += ENTITY_SYNC_STRIDE
		if not _entities.has(eid) or not is_instance_valid(_entities[eid]):
			if not _despawned_entity_ids.has(eid):
				_request_entity_snapshot_from_host()
			continue
		var node: Node2D = _entities[eid] as Node2D
		if node == null:
			continue
		var target_pos := Vector2(x, y)
		if node.get_meta("net_sync_inited", false) == false:
			node.global_position = target_pos
			node.set_meta("net_sync_inited", true)
		_entity_target_positions[eid] = target_pos

## Host → Client：同步实体血量（低频 10Hz）
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_health(data: PackedFloat32Array) -> void:
	var i := 0
	while i + 2 < data.size():
		var eid := int(data[i])
		var hp := data[i + 1]
		var max_hp := data[i + 2]
		i += 3
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			var node: Node = _entities[eid]
			if node.has_method("apply_network_health"):
				node.apply_network_health(hp, max_hp)

## Host → Client：只同步带护盾实体的护盾值，避免所有实体同步包膨胀。
@rpc("authority", "reliable", "call_remote")
func _rpc_sync_entity_shields(data: PackedFloat32Array) -> void:
	var i := 0
	while i + ENTITY_SHIELD_SYNC_STRIDE - 1 < data.size():
		var eid := int(data[i])
		var shield := data[i + 1]
		var max_shield := data[i + 2]
		i += ENTITY_SHIELD_SYNC_STRIDE
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			var node: Node = _entities[eid]
			if shield >= 0.0 and node.has_method("apply_network_shield"):
				node.apply_network_shield(shield, max_shield)

## Host → Client：同步少数需要朝向的实体；主位置包仍保持 5 字段，避免所有实体承担 rotation 成本。
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_rotations(data: PackedFloat32Array) -> void:
	var i := 0
	while i + ENTITY_ROTATION_SYNC_STRIDE - 1 < data.size():
		var eid := int(data[i])
		var rot := data[i + 1]
		i += ENTITY_ROTATION_SYNC_STRIDE
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			var node: Node = _entities[eid]
			if node.has_method("apply_network_rotation"):
				node.apply_network_rotation(rot)

## Host：打包所有实体位置
## Host：每 100ms 单独发送一次血量数据
func _batch_sync_entity_health() -> void:
	if _entities.is_empty():
		return
	var health_data := PackedFloat32Array()
	for eid: int in _entities:
		var node = _entities[eid]
		if is_instance_valid(node) and node.has_method("get_network_health"):
			health_data.append(eid as float)
			health_data.append(float(node.get_network_health()))
			if node.has_method("get_network_max_health"):
				health_data.append(float(node.get_network_max_health()))
	if health_data.size() > 0:
		_rpc_sync_entity_health.rpc(health_data)

func _batch_sync_entity_positions() -> void:
	if _entities.is_empty():
		return
	var data := PackedFloat32Array()
	var shield_data := PackedFloat32Array()
	var rotation_data := PackedFloat32Array()
	for eid: int in _entities:
		var node = _entities[eid]
		if is_instance_valid(node):
			data.append(eid as float)
			data.append(node.global_position.x)
			data.append(node.global_position.y)
			if node.has_method("get_network_shield") and node.has_method("get_network_max_shield"):
				shield_data.append(eid as float)
				shield_data.append(float(node.get_network_shield()))
				shield_data.append(float(node.get_network_max_shield()))
			if node.has_method("get_network_rotation") and node.has_method("apply_network_rotation"):
				rotation_data.append(eid as float)
				rotation_data.append(float(node.get_network_rotation()))
	if data.size() > 0:
		_rpc_sync_entity_positions.rpc(data)
	if shield_data.size() > 0:
		_rpc_sync_entity_shields.rpc(shield_data)
	if rotation_data.size() > 0:
		_rpc_sync_entity_rotations.rpc(rotation_data)


## 玩家位置同步 ────────────────────────────────────────────────
##
## 为什么不用 MultiplayerSynchronizer：引擎的场景复制（SceneCache）依赖
## 「同步器节点路径能被解析到」，而本项目是**每端各自 change_scene 进
## main.tscn**，客户端挂载战斗场景晚于 Host 开始广播，于是引擎会
##   Node not found: "Main/1/MultiplayerSynchronizer" (relative to "/root")
##   Failed to get path from RPC: Main / Invalid packet received
## 并丢弃后续同步包 —— 表现为客户端间歇性丢失远端玩家节点与位置同步。
## 玩家位置改走和敌人/子弹同一条手工管线，行为可预期、可插值、易回归。

## Host：批量广播全部玩家节点坐标（含各端幽灵），与实体同步同频
func _batch_sync_players() -> void:
	var data := PackedFloat32Array()
	for pid: int in _players:
		var node = _players[pid]
		if not is_instance_valid(node):
			continue
		data.append(pid as float)
		data.append(node.global_position.x)
		data.append(node.global_position.y)
		data.append(float(node.rotation))
	if data.size() > 0:
		_rpc_sync_player_states.rpc(data)


## Host → Client：应用远端玩家坐标
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_player_states(data: PackedFloat32Array) -> void:
	var i := 0
	while i + PLAYER_SYNC_STRIDE - 1 < data.size():
		var pid := int(data[i])
		var pos := Vector2(data[i + 1], data[i + 2])
		var rot := data[i + 3]
		i += PLAYER_SYNC_STRIDE
		if NetworkManager.is_online() and pid == multiplayer.get_unique_id():
			continue
		_apply_remote_player_state(pid, pos, rot)


## Client → Host：上报本机坐标，驱动 Host 上的幽灵节点
@rpc("any_peer", "unreliable", "call_remote")
func _rpc_report_player_state(p_peer_id: int, pos_x: float, pos_y: float, rot: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 0 and p_peer_id != sender:
		return
	_apply_remote_player_state(p_peer_id, Vector2(pos_x, pos_y), rot)


## 把远端坐标写入目标点 + 朝向；首次直接吸附，之后由 _apply_entity_interpolation 平滑
func _apply_remote_player_state(p_peer_id: int, pos: Vector2, rot: float) -> void:
	if not _players.has(p_peer_id) or not is_instance_valid(_players[p_peer_id]):
		return
	var node: Node2D = _players[p_peer_id] as Node2D
	if node == null:
		return
	if node.get_meta("player_sync_inited", false) == false:
		node.global_position = pos
		node.set_meta("player_sync_inited", true)
	_player_target_positions[p_peer_id] = pos
	node.rotation = rot

## 子弹同步 ──────────────────────────────────────────────────

## 注册一颗子弹生成（由 enemy/boss/player 调用）
func register_bullet_spawn(pos: Vector2, angle: float, damage: float, is_player: bool, level: int, speed: float, color: Color = Color(1,1,1,1), owner_peer_id: int = -1) -> void:
	if not NetworkManager.is_online():
		return
	_pending_bullet_spawns.append([pos.x, pos.y, angle, damage, is_player, level, speed, color.r, color.g, color.b, owner_peer_id])

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
func register_laser_spawn(pos: Vector2, angle: float, damage: float, owner_peer_id: int = -1) -> void:
	if not NetworkManager.is_online():
		return
	_pending_laser_spawns.append([pos.x, pos.y, angle, damage, owner_peer_id])


func broadcast_boss_shield_create(pos: Vector2) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_create_boss_shield.rpc(pos.x, pos.y)

func broadcast_boss_shield_destroy() -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_destroy_boss_shield.rpc()

@rpc("authority", "reliable", "call_remote")
func _rpc_create_boss_shield(pos_x: float, pos_y: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if _boss.has_method("_create_shield_circle"):
		_boss._create_shield_circle()

@rpc("authority", "reliable", "call_remote")
func _rpc_destroy_boss_shield() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if _boss.has_method("_spawn_shield_shatter_burst"):
		_boss._spawn_shield_shatter_burst()
	if _boss.has_method("_destroy_shield_circle"):
		_boss._destroy_shield_circle()

func broadcast_boss_ultimate_laser_charge(pos: Vector2, duration: float) -> void:
	_show_boss_ultimate_laser_charge(pos, duration)
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_show_boss_ultimate_laser_charge.rpc(pos.x, pos.y, duration)

func broadcast_boss_ultimate_laser_fire(from: Vector2, to: Vector2, travel_time: float, width: float, hold_duration: float = 0.0) -> void:
	_show_boss_ultimate_laser_fire(from, to, travel_time, width, hold_duration)
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_show_boss_ultimate_laser_fire.rpc(from.x, from.y, to.x, to.y, travel_time, width, hold_duration)

func _show_boss_ultimate_laser_charge(pos: Vector2, duration: float) -> void:
	var visual := Node2D.new()
	visual.set_script(_boss_ultimate_laser_visual_script)
	add_child(visual)
	if visual.has_method("setup_charge"):
		visual.setup_charge(pos, duration)
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("究极激光炮充能", 0.9, Color(1.0, 0.28, 0.12, 1.0))

func _show_boss_ultimate_laser_fire(from: Vector2, to: Vector2, travel_time: float, width: float, hold_duration: float = 0.0) -> void:
	var visual := Node2D.new()
	visual.set_script(_boss_ultimate_laser_visual_script)
	add_child(visual)
	if visual.has_method("setup_beam"):
		visual.setup_beam(from, to, travel_time, width, hold_duration)

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
@rpc("any_peer", "unreliable_ordered", "call_remote")
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
			entry[6],                      # speed
			int(entry[10]) if entry.size() > 10 else -1
		)
		if entry.size() > 7:
			bullet.modulate = Color(entry[7], entry[8], entry[9], 1.0)
		if not multiplayer.is_server() and bullet.has_method("set_network_ghost"):
			bullet.set_network_ghost(true)

## 激光同步：
@rpc("authority", "reliable", "call_remote")
func _rpc_set_boss_bg(active: bool) -> void:
	if _bg_color:
		_bg_color.color = Color(0.14, 0.03, 0.03, 1.0) if active else Color(0.06, 0.06, 0.12, 1.0)

@rpc("authority", "reliable", "call_remote")
func _rpc_show_boss_ultimate_laser_charge(pos_x: float, pos_y: float, duration: float) -> void:
	_show_boss_ultimate_laser_charge(Vector2(pos_x, pos_y), duration)

@rpc("authority", "reliable", "call_remote")
func _rpc_show_boss_ultimate_laser_fire(from_x: float, from_y: float, to_x: float, to_y: float, travel_time: float, width: float, hold_duration: float = 0.0) -> void:
	_show_boss_ultimate_laser_fire(Vector2(from_x, from_y), Vector2(to_x, to_y), travel_time, width, hold_duration)

## - Client -> Host：上报激光发射请求（Host 生成权威激光并回广播）
## - Host -> Client：广播激光视觉（客户端仅视觉不结算伤害）
@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_spawn_lasers(data: Array) -> void:
	if not NetworkManager.is_online():
		return
	if multiplayer.is_server():
		for entry in data:
			var bolt = _laser_scene.instantiate()
			add_child(bolt)
			var owner_peer := int(entry[4]) if entry.size() > 4 else -1
			bolt.setup(Vector2(entry[0], entry[1]), entry[2], entry[3], owner_peer)
		_rpc_spawn_lasers.rpc(data)
		return
	for entry in data:
		var bolt = _laser_scene.instantiate()
		add_child(bolt)
		var owner_peer := int(entry[4]) if entry.size() > 4 else -1
		bolt.setup(Vector2(entry[0], entry[1]), entry[2], entry[3], owner_peer)
		if bolt.has_method("set_network_ghost"):
			bolt.set_network_ghost(true)
