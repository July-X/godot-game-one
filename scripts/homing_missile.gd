extends Area2D

enum MissileState { SEARCH, HOMING, DYING }

var _speed: float = 400.0
var _damage: float = 3.0
var _lifetime: float = 5.0
var _target: Node2D = null
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _trail_points: PackedVector2Array = PackedVector2Array()
var owner_peer_id: int = -1

## 寻敌阶段最大飞行距离
var _search_distance: float = 300.0
var _search_traveled: float = 0.0
var _state: int = MissileState.SEARCH
var _dying_timer: float = 0.15

func _ready() -> void:
	add_to_group("player_bullets")
	connect("body_entered", _on_body_entered)
	connect("area_entered", _on_area_entered)

func setup(pos: Vector2, angle: float, damage: float, owner_id: int = -1) -> void:
	global_position = pos
	rotation = angle + PI * 0.5
	_damage = damage
	owner_peer_id = owner_id
	_state = MissileState.SEARCH
	_search_traveled = 0.0

var _trail_frame_skip: int = 0

func _physics_process(delta: float) -> void:
	_lifetime -= delta
	_trail_points.append(global_position)

	match _state:
		MissileState.SEARCH:
			_search_traveled += _speed * delta
			_find_target()
			if is_instance_valid(_target):
				_state = MissileState.HOMING
			elif _search_traveled >= _search_distance or _lifetime <= 0:
				_state = MissileState.DYING
				_dying_timer = 0.15
			else:
				var forward: Vector2 = Vector2.RIGHT.rotated(rotation - PI * 0.5)
				global_position += forward * _speed * delta

		MissileState.HOMING:
			if is_instance_valid(_target):
				var dir: Vector2 = global_position.direction_to(_target.global_position)
				rotation = lerp_angle(rotation, dir.angle() + PI * 0.5, 3.0 * delta)
				global_position += dir * _speed * delta
			else:
				_state = MissileState.DYING
				_dying_timer = 0.15

		MissileState.DYING:
			_dying_timer -= delta
			scale = scale.lerp(Vector2.ZERO, 6.0 * delta)
			modulate.a = max(modulate.a - delta * 4.0, 0.0)
			if _dying_timer <= 0.0:
				queue_free()
				return
			var dying_dir: Vector2 = Vector2.RIGHT.rotated(rotation - PI * 0.5)
			global_position += dying_dir * _speed * delta * 0.5

	if _state != MissileState.DYING:
		var screen := get_viewport_rect().size
		if global_position.x < -30 or global_position.x > screen.x + 30 or global_position.y < -30 or global_position.y > screen.y + 30:
			queue_free()
			return

	_trail_frame_skip += 1
	if _trail_frame_skip % 2 == 0:
		queue_redraw()

func _draw() -> void:
	if _trail_points.size() > 1:
		var pts: PackedVector2Array = []
		var limit: int = max(_trail_points.size() - 15, 0)
		for i in range(limit, _trail_points.size()):
			pts.append(to_local(_trail_points[i]))
		if pts.size() > 1:
			draw_polyline(pts, Color(1.0, 0.5, 0.1, 0.7), 3.0)
			draw_polyline(pts, Color(1.0, 0.8, 0.3, 0.4), 6.0)

func _find_target() -> void:
	if is_instance_valid(_target):
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	var best_priority: Node2D = null
	var best_priority_dist: float = INF
	var best: Node2D = null
	var best_dist: float = INF
	for e in enemies:
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var node := e as Node2D
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

func _on_body_entered(body: Node2D) -> void:
	if not GameState.game_running or _state == MissileState.DYING:
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		_apply_or_report_enemy_damage(body, _damage)
		_spawn_hit()
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if not GameState.game_running or _state == MissileState.DYING:
		return
	if area.is_in_group("enemy_hitbox") and area.get_parent().has_method("take_damage"):
		_apply_or_report_enemy_damage(area.get_parent(), _damage)
		_spawn_hit()
		queue_free()

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
