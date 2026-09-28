extends Area2D
const Palette = preload("res://scripts/palette.gd")
## 子弹 — 支持对象池复用

var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 600.0
var _damage: float = 1.0
var _is_player_bullet: bool = true
var _lifetime: float = 4.0
var _has_bounced: bool = false
var _level: int = 1
## 构筑：贯穿剩余次数。0 = 普通子弹（一击即消），>0 = 还能再打穿 N 个目标。
## 记录已命中的目标是为了避免同一颗子弹在同一帧对同一个敌人反复结算伤害。
var _pierce_left: int = 0
var _pierced: Array = []
var _splash_radius: float = 0.0
var _homing_strength: float = 0.0
var _pooled: bool = false
var _is_network_ghost: bool = false
var owner_peer_id: int = -1

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	## 子弹速度可达数百 px/s，物理 60Hz 时单个物理帧位移接近 10px。
	## 开物理插值后引擎会在两个物理帧之间补位置，对高速抛射物而言
	## 命中判定与渲染位置会错开半帧（视觉上像"打偏"），因此显式关闭。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not is_connected("body_entered", _on_body_entered):
		body_entered.connect(_on_body_entered)
	if not is_connected("area_entered", _on_area_entered):
		area_entered.connect(_on_area_entered)

## 从对象池取出后调用此方法替代第二次 _ready
func reset() -> void:
	_direction = Vector2.ZERO
	_speed = 600.0
	_damage = 1.0
	_has_bounced = false
	_level = 1
	_lifetime = 4.0
	_is_network_ghost = false
	owner_peer_id = -1
	_pierce_left = 0
	_pierced.clear()
	_splash_radius = 0.0
	_homing_strength = 0.0
	remove_from_group("player_bullets")
	remove_from_group("enemy_bullets")
	_sprite.modulate = Palette.PLAYER_BULLET if _is_player_bullet else Color(1, 1, 1, 1)


## 从持有者的构筑读取行为开关。每颗子弹生成时取一次，之后不再查——
## 子弹可能存活好几秒，构筑在这期间不会变，查了也没用。
func apply_owner_cards(pid: int) -> void:
	if not _is_player_bullet:
		return
	_pierce_left = GameState.get_bullet_pierce(pid)
	_splash_radius = GameState.get_splash_radius(pid) if GameState.get_bullet_splash(pid) else 0.0
	_homing_strength = 1.8 if GameState.get_bullet_homing(pid) else 0.0
	_speed += GameState.get_bullet_speed_bonus(pid)


## 命中一个敌人。返回 true 表示子弹应该被消耗掉。
##
## 贯穿不依赖 Area2D 的 monitoring 开关：area_entered 只在"进入"时触发一次，
## 子弹停在敌人身上不会重复上报，靠 _pierced 去重就够了。
## 额外去重 monitoring 反而有风险（关了忘开 / 开了忘关）。
func _resolve_hit(target: Node) -> bool:
	if _pierced.has(target):
		return false
	_pierced.append(target)
	if _splash_radius > 0.0:
		_splash_damage(get_tree().get_nodes_in_group("enemies"))
	if _pierce_left > 0:
		_pierce_left -= 1
		return false
	return true


## 溅射：对半径内的其他敌人造成一半伤害。直接伤害已在调用方结算过。
func _splash_damage(enemies: Array) -> void:
	var origin: Vector2 = global_position
	for e: Node in enemies:
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		if e is Node2D and (e as Node2D).global_position.distance_to(origin) <= _splash_radius:
			e.take_damage(_damage * 0.5, owner_peer_id)
			var fx := Pool.acquire("hit_effect", _hit_effect_scene)
			get_tree().current_scene.add_child(fx)
			fx.global_position = (e as Node2D).global_position
			fx.start()

func setup(pos: Vector2, angle: float, damage: float, is_player: bool, level: int = 1, speed: float = 600.0, owner_id: int = -1) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle + PI * 0.5
	_damage = damage
	_is_player_bullet = is_player
	_has_bounced = false
	_level = level
	_speed = speed
	owner_peer_id = owner_id
	remove_from_group("player_bullets")
	remove_from_group("enemy_bullets")
	if is_player:
		add_to_group("player_bullets")
	else:
		add_to_group("enemy_bullets")
	_apply_bullet_appearance()

func set_network_ghost(v: bool) -> void:
	_is_network_ghost = v

func _exit_tree() -> void:
	remove_from_group("player_bullets")
	remove_from_group("enemy_bullets")

func _apply_bullet_appearance() -> void:
	if _is_player_bullet:
		_sprite.texture = SpriteFactory.create_bullet_sprite(true, _level)
		var scale_val: float = (0.6 + min(_damage * 0.08, 0.6)) * 0.55
		_sprite.scale = Vector2(scale_val, scale_val)
		_sprite.modulate = Palette.PLAYER_BULLET
	else:
		_sprite.texture = SpriteFactory.create_bullet_sprite(false, 1)
		## 敌弹视觉尺寸比玩家弹略大：弹幕游戏里"看起来更大"会被读成
		## "更难躲"，能提前给玩家心理准备。判定框不变，不影响实际难度。
		_sprite.scale = Vector2(0.78, 0.78)


## 「追踪回路」卡的转向：朝最近敌人缓慢修正方向。
## 强度刻意做得很低（1.8 rad/s）——卡面写的是"轻微追踪"，
## 追踪太强就变成自动瞄准，玩家不需要走位了，构筑反而破坏手感。
func _steer_to_nearest_enemy(delta: float) -> void:
	var best: Node2D = null
	var best_d: float = 420.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if _pierced.has(e):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	if best == null:
		return
	var want: Vector2 = global_position.direction_to(best.global_position)
	_direction = _direction.lerp(want, clampf(_homing_strength * delta, 0.0, 1.0)).normalized()
	rotation = _direction.angle() + PI * 0.5

func _physics_process(delta: float) -> void:
	if _homing_strength > 0.0:
		_steer_to_nearest_enemy(delta)
	global_position += _direction * _speed * delta
	_lifetime -= delta

	## 屏幕外裁剪：超出屏幕一定距离后回收
	var screen := get_viewport_rect().size
	var margin: float = 60.0

	if _is_player_bullet:
		if not _has_bounced:
			var b_margin: float = 10.0
			var bounced: bool = false
			if global_position.x < b_margin:
				global_position.x = b_margin; _direction.x = abs(_direction.x); bounced = true
			elif global_position.x > screen.x - b_margin:
				global_position.x = screen.x - b_margin; _direction.x = -abs(_direction.x); bounced = true
			if global_position.y < b_margin:
				global_position.y = b_margin; _direction.y = abs(_direction.y); bounced = true
			elif global_position.y > screen.y - b_margin:
				global_position.y = screen.y - b_margin; _direction.y = -abs(_direction.y); bounced = true
			if bounced:
				_has_bounced = true; _speed *= 1.3
				_direction = _direction.normalized()
				rotation = _direction.angle() + PI * 0.5
				_sprite.modulate = Color(1.0, 0.5, 0.2, 1.0)

	if global_position.x < -margin or global_position.x > screen.x + margin \
		or global_position.y < -margin or global_position.y > screen.y + margin:
		_recycle()
		return

	if _lifetime <= 0:
		_recycle()

func _recycle() -> void:
	Pool.release(self)

func _on_body_entered(body: Node2D) -> void:
	if not GameState.game_running:
		return
	if NetworkManager.is_online() and _is_network_ghost:
		return
	if _is_player_bullet:
		## 多人：Client 子弹击中本地幽灵敌人 → 报告 Host
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			if NetworkManager.is_online() and not multiplayer.is_server():
				if body.has_method("get_entity_id"):
					var attacker_peer := owner_peer_id
					if attacker_peer <= 0:
						attacker_peer = multiplayer.get_unique_id()
					GameState._rpc_report_enemy_hit.rpc_id(1, body.get_entity_id(), maxi(1, int(round(_damage))), attacker_peer)
				_spawn_hit()
				_recycle()
			else:
				body.take_damage(_damage, owner_peer_id)
				_spawn_hit()
				if _resolve_hit(body):
					_recycle()
	else:
		if body.is_in_group("player") and body.has_method("take_damage"):
			## 多人：Client 端玩家中弹 → 报告 Host
			if NetworkManager.is_online() and not multiplayer.is_server():
				var pid: int = body.peer_id
				GameState._rpc_report_player_hit.rpc_id(1, maxi(1, int(round(_damage))), pid)
				_spawn_hit()
				_recycle()
			else:
				var source: String = "弹幕子弹"
				if _damage >= 0.45:
					source = "狙击子弹"
				elif _damage >= 0.25:
					source = "散弹子弹"
				GameState.death_message = "被 " + source + " 击落"
				body.take_damage(_damage)
				_spawn_hit()
				_recycle()

func _on_area_entered(area: Area2D) -> void:
	if not GameState.game_running:
		return
	if NetworkManager.is_online() and _is_network_ghost:
		return
	if _is_player_bullet:
		if area.is_in_group("enemy_hitbox") and area.get_parent().has_method("take_damage"):
			if NetworkManager.is_online() and not multiplayer.is_server():
				var enemy = area.get_parent()
				if enemy.has_method("get_entity_id"):
					var attacker_peer := owner_peer_id
					if attacker_peer <= 0:
						attacker_peer = multiplayer.get_unique_id()
					GameState._rpc_report_enemy_hit.rpc_id(1, enemy.get_entity_id(), maxi(1, int(round(_damage))), attacker_peer)
				_spawn_hit()
				_recycle()
			else:
				var enemy := area.get_parent()
				enemy.take_damage(_damage, owner_peer_id)
				_spawn_hit()
				if _resolve_hit(enemy):
					_recycle()

func _spawn_hit() -> void:
	## 日常命中的反馈：极轻的震屏 + 命中音。
	## 这里最容易犯的错是给太重——自动射击每秒钟能命中十几次，
	## 一旦每次都震，连击时画面会持续抖，弹幕反而看不清。
	## 所以强度压到 0.06，并把"手感"主要交给命中音的连击升调。
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("emit_hit_feedback"):
		scene.emit_hit_feedback(scene.SHAKE_HIT, 0.0, true)
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
	hit.start()
