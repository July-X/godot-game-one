extends Area2D

var _speed: float = 400.0
var _damage: float = 3.0
var _lifetime: float = 5.0
var _target: Node2D = null
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _trail_points: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	add_to_group("player_bullets")
	connect("body_entered", _on_body_entered)
	connect("area_entered", _on_area_entered)

func setup(pos: Vector2, angle: float, damage: float) -> void:
	global_position = pos
	rotation = angle + PI * 0.5
	_damage = damage

func _physics_process(delta: float) -> void:
	_lifetime -= delta
	_trail_points.append(global_position)

	if _lifetime <= 0:
		queue_free()
		return

	_find_target()
	if is_instance_valid(_target):
		var dir: Vector2 = global_position.direction_to(_target.global_position)
		rotation = lerp_angle(rotation, dir.angle() + PI * 0.5, 3.0 * delta)
		global_position += dir * _speed * delta
	else:
		var forward: Vector2 = Vector2.RIGHT.rotated(rotation - PI * 0.5)
		global_position += forward * _speed * delta

	var screen := get_viewport_rect().size
	if global_position.x < -30 or global_position.x > screen.x + 30 or global_position.y < -30 or global_position.y > screen.y + 30:
		queue_free()

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
	var best: Node2D = null
	var best_dist: float = 99999.0
	for e in enemies:
		if e.enemy_type == 0 and is_instance_valid(e):
			var d: float = global_position.distance_squared_to(e.global_position)
			if d < best_dist:
				best_dist = d
				best = e
	_target = best

func _on_body_entered(body: Node2D) -> void:
	if not GameState.game_running:
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(_damage)
		_spawn_hit()
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if not GameState.game_running:
		return
	if area.is_in_group("enemy_hitbox") and area.get_parent().has_method("take_damage"):
		area.get_parent().take_damage(_damage)
		_spawn_hit()
		queue_free()

func _spawn_hit() -> void:
	var hit = _hit_effect_scene.instantiate()
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
