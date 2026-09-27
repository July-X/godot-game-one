extends Area2D
## 子弹 — 支持对象池复用

var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 600.0
var _damage: float = 1.0
var _is_player_bullet: bool = true
var _lifetime: float = 4.0
var _has_bounced: bool = false
var _level: int = 1
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
	remove_from_group("player_bullets")
	remove_from_group("enemy_bullets")
	_sprite.modulate = Color(1, 1, 1, 1)

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
	else:
		_sprite.texture = SpriteFactory.create_bullet_sprite(false, 1)
		_sprite.scale = Vector2(0.67, 0.67)

func _physics_process(delta: float) -> void:
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
				area.get_parent().take_damage(_damage, owner_peer_id)
				_spawn_hit()
				_recycle()

func _spawn_hit() -> void:
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
	hit.start()
