extends Area2D

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 1200.0
var _damage: float = 5.0
var _lifetime: float = 0.6
var _chain_max: int = 4
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var LightningLine = preload("res://scripts/lightning_line.gd")
var _line_points: PackedVector2Array = PackedVector2Array()
var _has_bounced: bool = false
var _target: Node2D = null
var _is_network_ghost: bool = false
var owner_peer_id: int = -1
## 寻敌角度（两条射线宽度 × 2，即 0.15×2×2 = 0.6 弧度）
const HOMING_ANGLE: float = 0.6
const HOMING_SPEED: float = 4.0

func _ready() -> void:
	## 与 bullet.gd 同理：高速抛射物关物理插值，避免渲染位置与命中判定错开半帧
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("player_bullets")
	connect("body_entered", _on_body_entered)

func setup(pos: Vector2, angle: float, damage: float, owner_id: int = -1) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle
	_damage = damage
	_target = null
	_has_bounced = false
	owner_peer_id = owner_id

func set_network_ghost(v: bool) -> void:
	_is_network_ghost = v

var _trail_frame_skip: int = 0

func _physics_process(delta: float) -> void:
	## 自动寻敌：在锥形范围内找最近敌人
	_find_target_in_cone()

	if _target != null and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		var angle_diff: float = abs(_direction.angle_to(to_target))
		if angle_diff < HOMING_ANGLE:
			_direction = _direction.lerp(to_target, HOMING_SPEED * delta).normalized()
			rotation = _direction.angle()
			_speed = 900.0  # 寻敌时减速

	global_position += _direction * _speed * delta
	_lifetime -= delta
	_line_points.append(global_position)

	if _lifetime <= 0:
		queue_free()

	var screen := get_viewport_rect().size
	if not _has_bounced:
		var bounced: bool = false
		if global_position.x < 20:
			_direction.x = abs(_direction.x); bounced = true
		elif global_position.x > screen.x - 20:
			_direction.x = -abs(_direction.x); bounced = true
		if global_position.y < 20:
			_direction.y = abs(_direction.y); bounced = true
		elif global_position.y > screen.y - 20:
			_direction.y = -abs(_direction.y); bounced = true
		if bounced:
			_has_bounced = true
			_direction = _direction.normalized()
			rotation = _direction.angle()
			_speed = 1200.0
	# 反弹后或超出更远距离再回收
	var margin: float = 120.0 if _has_bounced else 80.0
	if global_position.x < -margin or global_position.x > screen.x + margin \
		or global_position.y < -margin or global_position.y > screen.y + margin:
		queue_free()

	_trail_frame_skip += 1
	if _trail_frame_skip % 2 == 0:
		queue_redraw()

func _find_target_in_cone() -> void:
	if _target != null and is_instance_valid(_target):
		return
	var best_priority: Node2D = null
	var best_priority_dist: float = INF
	var best: Node2D = null
	var best_dist: float = INF
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var node := e as Node2D
		var to_e: Vector2 = global_position.direction_to(node.global_position)
		var diff: float = abs(_direction.angle_to(to_e))
		if diff >= HOMING_ANGLE and not _is_priority_enemy(node):
			continue
		var d: float = global_position.distance_squared_to(node.global_position)
		if _is_priority_enemy(node):
			if d < best_priority_dist:
				best_priority_dist = d
				best_priority = node
		elif d < best_dist:
			best_dist = d
			best = node
	_target = best_priority if best_priority != null else best

func _is_priority_enemy(node: Node) -> bool:
	return node.is_in_group("boss") or node.has_method("get_network_shield")

func _draw() -> void:
	if _line_points.size() > 1:
		var pts: PackedVector2Array = []
		for p in _line_points:
			pts.append(to_local(p))
		draw_polyline(pts, Color(0.5, 0.2, 1.0, 0.5), 3.0)
		draw_polyline(pts, Color(0.8, 0.5, 1.0, 0.35), 5.0)
	var tail := Vector2.RIGHT.rotated(-rotation) * 32
	draw_line(tail, Vector2.ZERO, Color(0.3, 0.3, 1.0, 0.95), 3.0)
	draw_line(tail, Vector2.ZERO, Color(0.6, 0.9, 1.0, 0.7), 7.0)
	draw_line(tail, Vector2.ZERO, Color(0.3, 0.8, 1.0, 0.35), 12.0)

func _on_body_entered(body: Node2D) -> void:
	if not GameState.game_running:
		return
	if NetworkManager.is_online() and _is_network_ghost:
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		_apply_or_report_enemy_damage(body, _damage)
		_spawn_hit()
		_chain_lightning(body, _is_server_authority())
		queue_free()

func _chain_lightning(hit_body: Node2D, can_apply_local_damage: bool) -> void:
	var chained: Array = [hit_body]
	var from: Node2D = hit_body
	var remaining: int = _chain_max - 1
	for i in range(remaining):
		var next := _find_nearest_enemy(from, chained)
		if next == null:
			break
		var chain_dmg: float = _damage * 0.5 * pow(0.7, i)
		if can_apply_local_damage:
			next.take_damage(chain_dmg)
		else:
			_report_enemy_hit(next, chain_dmg)
		_draw_lightning_bolt(from.global_position, next.global_position)
		chained.append(next)
		from = next

func _find_nearest_enemy(origin: Node2D, exclude: Array) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 240.0
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e in exclude or not is_instance_valid(e):
			continue
		var d: float = origin.global_position.distance_squared_to(e.global_position)
		if d < best_dist * best_dist:
			best_dist = sqrt(d)
			best = e
	return best

func _draw_lightning_bolt(from: Vector2, to: Vector2) -> void:
	var line := LightningLine.new()
	get_tree().current_scene.add_child(line)
	line.setup(from, to)

func _spawn_hit() -> void:
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
	hit.start()

func _is_server_authority() -> bool:
	return (not NetworkManager.is_online()) or multiplayer.is_server()

func _normalized_damage(damage: float) -> int:
	return maxi(1, int(round(damage)))

func _report_enemy_hit(enemy: Node2D, damage: float) -> void:
	if not enemy.has_method("get_entity_id"):
		return
	var attacker_peer := owner_peer_id
	if attacker_peer <= 0 and multiplayer.has_multiplayer_peer():
		attacker_peer = multiplayer.get_unique_id()
	GameState._rpc_report_enemy_hit.rpc_id(1, enemy.get_entity_id(), _normalized_damage(damage), attacker_peer)

func _apply_or_report_enemy_damage(enemy: Node2D, damage: float) -> void:
	if _is_server_authority():
		enemy.take_damage(damage, owner_peer_id)
	else:
		_report_enemy_hit(enemy, damage)
