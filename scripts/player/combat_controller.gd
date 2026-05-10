extends Node
## 战斗控制器
##
## 负责：普攻、技能（散射/激光）、追踪导弹、自动拾取。
## 消费来自 ActionRouter 的动作请求，并统一校验冷却。

@onready var _player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _action_router: Node = _player.get_node("ActionRouter") if _player.has_node("ActionRouter") else null

var _shoot_timer: float = 0.0
var _missile_timer: float = 0.0

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _missile_scene = preload("res://scenes/entities/homing_missile.tscn")
var _laser_scene = preload("res://scenes/entities/laser_bolt.tscn")

var _missile_pods: Array[Node2D] = []
var _missile_pod_built: int = 0
var _pickup_radius: float = 280.0
var _pickup_frame_skip: int = 0


func update(delta: float) -> void:
	_shoot_timer -= delta
	_spawn_homing_missiles(delta)
	_try_pickup_nearby()

	if _shoot_timer <= 0.0:
		_shoot()

	_consume_actions()


func reset_shoot_timer() -> void:
	_shoot_timer = GameState.get_shoot_cooldown()


## ── 子弹生成辅助（消除多人同步代码重复） ──────────────

func _spawn_bullet(pos: Vector2, angle: float, damage: int, is_player: bool, level: int, speed: float) -> void:
	var bullet := Pool.acquire("bullet", _bullet_scene)
	get_tree().current_scene.add_child(bullet)
	bullet.setup(pos, angle, damage, is_player, level, speed)

	## 联机时不区分 Host/Client，均上报到 Main 的子弹同步队列。
	## - Host: 广播给 Client，实现同屏可见
	## - Client: 上报给 Host，保证权威命中结算
	if NetworkManager.is_online():
		var _m = get_tree().current_scene
		if _m and _m.has_method("register_bullet_spawn"):
			_m.register_bullet_spawn(pos, angle, damage, is_player, level, speed)


## ── 普攻 ────────────────────────────────────────────

func _shoot() -> void:
	_shoot_timer = GameState.get_shoot_cooldown()
	SFX.play_shoot()

	var base_angle: float = _player.rotation - PI * 0.5
	var bullet_count: int = GameState.get_bullet_count()
	var level: int = GameState.shoot_level
	var damage: int = GameState.get_bullet_damage()
	var engine_offset: Vector2 = Vector2.from_angle(base_angle) * 24
	var perp: Vector2 = Vector2(-sin(base_angle), cos(base_angle))

	if level >= 12:
		var spread_angles: Array[float] = [-0.3, -0.15, 0.0, 0.15, 0.3]
		for i in range(bullet_count):
			var a: float = base_angle + spread_angles[i % spread_angles.size()] * (0.5 + (level - 12) * 0.1)
			var spread_offset: float = (i - bullet_count / 2.0) * 18.0
			var offset: Vector2 = perp * spread_offset
			_spawn_bullet(_player.global_position + engine_offset + offset, a, damage, true, level, 660.0)
	elif level >= 8:
		var max_spread: float = 16.0 + level
		var positions: Array[float] = []
		for i in range(bullet_count):
			positions.append(-max_spread + i * (max_spread * 2.0 / max(bullet_count - 1, 1)))
		for i in bullet_count:
			var a: float = base_angle + positions[i] * 0.008
			var offset: Vector2 = perp * positions[i]
			_spawn_bullet(_player.global_position + engine_offset + offset, a, damage, true, level, 660.0)
	elif level >= 4:
		var max_spread: float = 12.0 + level * 3.0
		var positions: Array[float] = []
		for i in range(bullet_count):
			positions.append(-max_spread + i * (max_spread * 2.0 / max(bullet_count - 1, 1)))
		for i in bullet_count:
			var offset: Vector2 = perp * positions[i]
			_spawn_bullet(_player.global_position + engine_offset + offset, base_angle, damage, true, level, 660.0)
	else:
		var max_spread: float = 10.0 + level * 2.0
		var positions: Array[float] = []
		for i in range(bullet_count):
			positions.append(-max_spread + i * (max_spread * 2.0 / max(bullet_count - 1, 1)))
		for i in bullet_count:
			var offset: Vector2 = perp * positions[i]
			_spawn_bullet(_player.global_position + engine_offset + offset, base_angle, damage, true, level, 660.0)

	_show_muzzle_flash()


## ── 技能 ────────────────────────────────────────────

func fire_ring_shotgun() -> void:
	var count: int = 16
	var base_angle: float
	if _player.get_node("MotionController") and _player.get_node("MotionController").get("mobile_mode"):
		base_angle = _player.rotation - PI * 0.5
	else:
		var mouse_pos := _player.get_global_mouse_position()
		base_angle = _player.global_position.angle_to_point(mouse_pos)
	var perp: Vector2 = Vector2(-sin(base_angle), cos(base_angle))
	var engine_offset: Vector2 = Vector2.from_angle(base_angle) * 24
	var damage: int = GameState.get_bullet_damage() + 2
	for i in range(count):
		var a: float = base_angle + i * TAU / count
		var offset: Vector2 = perp * 8.0 + Vector2(cos(a), sin(a)) * 4.0
		_spawn_bullet(_player.global_position + engine_offset + offset, a, damage, true, 5, 500.0)


func fire_laser() -> void:
	var count: int = 3
	for i in range(count):
		var angle: float = _player.rotation - PI * 0.5 + (i - 1) * 0.15
		var pos: Vector2 = _player.global_position + Vector2.from_angle(angle) * 28
		var bolt := _laser_scene.instantiate()
		get_tree().current_scene.add_child(bolt)
		bolt.setup(pos, angle, GameState.get_laser_damage())
	SFX.play_shoot()


func _show_muzzle_flash() -> void:
	var muzzle_flash := _player.get_node("MuzzleFlash") as Sprite2D if _player.has_node("MuzzleFlash") else null
	if not muzzle_flash:
		return
	muzzle_flash.visible = true
	var tween := create_tween()
	tween.tween_property(muzzle_flash, "modulate:a", 0.0, 0.06)
	tween.tween_callback(func(): muzzle_flash.visible = false)


func _consume_actions() -> void:
	if not _action_router:
		return
	var actions: Array[String] = _action_router.consume_actions()
	for action in actions:
		match action:
			"skill":
				if GameState.use_skill():
					fire_ring_shotgun()
			"laser":
				if GameState.use_laser():
					fire_laser()


## ── 追踪导弹 ────────────────────────────────────────

func _get_missile_tier() -> int:
	var level: int = GameState.shoot_level
	return mini(level / 5, 5)

func _get_missile_damage() -> int:
	var tier: int = _get_missile_tier()
	var dmg: int = (GameState.get_bullet_damage() + 2) * int(pow(1.5, tier - 1))
	return dmg

func _get_missile_interval() -> float:
	var tier: int = _get_missile_tier()
	return 1.5 / tier

func _build_missile_pods() -> void:
	var tier: int = _get_missile_tier()
	if tier <= _missile_pod_built:
		return
	while _missile_pods.size() > 0:
		var p: Node2D = _missile_pods.pop_back()
		p.queue_free()
	_missile_pod_built = tier
	for i in range(tier):
		var pod := Sprite2D.new()
		pod.texture = _make_pod_texture(Color(0.9, 0.3, 0.15))
		pod.scale = Vector2(0.5, 0.5)
		pod.z_index = 2
		_player.add_child(pod)
		_missile_pods.append(pod)

func _make_pod_texture(col: Color) -> ImageTexture:
	var size: int = 10
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = size / 2
	var cy: int = size / 2
	for y in range(size):
		for x in range(size):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var d: float = sqrt(dx * dx + dy * dy)
			if d < cx - 1:
				img.set_pixel(x, y, col)
				if d > cx - 3:
					img.set_pixel(x, y, col.lightened(0.3))
	var tex := ImageTexture.create_from_image(img)
	return tex

func _update_missile_pods() -> void:
	var tier: int = _get_missile_tier()
	if tier != _missile_pod_built:
		_build_missile_pods()
	var rear: Vector2 = Vector2.RIGHT.rotated(_player.rotation + PI) * 48
	var perp: Vector2 = Vector2.UP.rotated(_player.rotation)
	var spacing: float = 18.0
	var start: float = -(tier - 1) * spacing * 0.5
	for i in range(tier):
		if i < _missile_pods.size():
			_missile_pods[i].global_position = _player.global_position + rear + perp * (start + i * spacing)
			_missile_pods[i].rotation = _player.rotation + PI

func _spawn_homing_missiles(delta: float) -> void:
	var tier: int = _get_missile_tier()
	if tier <= 0:
		return
	_update_missile_pods()
	_missile_timer += delta
	if _missile_timer < _get_missile_interval():
		return
	_missile_timer = 0.0
	for i in range(tier):
		if i < _missile_pods.size():
			var pos: Vector2 = _missile_pods[i].global_position
			var angle: float = _player.rotation + PI + (i - (tier - 1) * 0.5) * 0.15
			var missile := _missile_scene.instantiate()
			get_tree().current_scene.add_child(missile)
			missile.setup(pos, angle, _get_missile_damage())


## ── 自动拾取 ────────────────────────────────────────

func update_pickup_radius() -> void:
	_pickup_radius = 420.0
	var pickup_area: Area2D = _player.get_node("PickupArea") as Area2D if _player.has_node("PickupArea") else null
	if pickup_area and pickup_area.get_child_count() > 0:
		pickup_area.get_child(0).shape.radius = _pickup_radius

func _try_pickup_nearby() -> void:
	_pickup_frame_skip += 1
	if _pickup_frame_skip % 4 != 0:
		return
	var powerups := get_tree().get_nodes_in_group("powerups")
	for pu in powerups:
		if pu.is_inside_tree() and _player.global_position.distance_to(pu.global_position) < _pickup_radius:
			if pu.has_method("start_magnet"):
				pu.start_magnet(_player)
