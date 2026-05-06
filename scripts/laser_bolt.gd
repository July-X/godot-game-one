extends Area2D

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 1200.0
var _damage: float = 5.0
var _lifetime: float = 0.6
var _chain_max: int = 4
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var LightningLine = preload("res://scripts/lightning_line.gd")
var _line_points: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	add_to_group("player_bullets")
	connect("body_entered", _on_body_entered)

func setup(pos: Vector2, angle: float, damage: float) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle
	_damage = damage

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_lifetime -= delta
	_line_points.append(global_position)

	if _lifetime <= 0:
		queue_free()

	var screen := get_viewport_rect().size
	if global_position.x < -80 or global_position.x > screen.x + 80 or global_position.y < -80 or global_position.y > screen.y + 80:
		queue_free()

	queue_redraw()

func _draw() -> void:
	if _line_points.size() > 1:
		var pts: PackedVector2Array = []
		for p in _line_points:
			pts.append(to_local(p))
		draw_polyline(pts, Color(0.5, 0.2, 1.0, 0.5), 6.0)
		draw_polyline(pts, Color(0.8, 0.5, 1.0, 0.35), 10.0)
	var tail := Vector2.RIGHT.rotated(-rotation) * 32
	draw_line(tail, Vector2.ZERO, Color(0.3, 0.3, 1.0, 0.95), 3.0)
	draw_line(tail, Vector2.ZERO, Color(0.6, 0.9, 1.0, 0.7), 7.0)
	draw_line(tail, Vector2.ZERO, Color(0.3, 0.8, 1.0, 0.35), 12.0)

func _on_body_entered(body: Node2D) -> void:
	if not GameState.game_running:
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(_damage)
		_spawn_hit()
		_chain_lightning(body)
		queue_free()

func _chain_lightning(hit_body: Node2D) -> void:
	var chained: Array = [hit_body]
	var from: Node2D = hit_body
	var remaining: int = _chain_max - 1
	for i in range(remaining):
		var next := _find_nearest_enemy(from, chained)
		if next == null:
			break
		var chain_dmg: float = _damage * 0.5 * pow(0.7, i)
		next.take_damage(chain_dmg)
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
	var hit = _hit_effect_scene.instantiate()
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
