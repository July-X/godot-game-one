extends Node2D

var _age: float = 0.0
var _duration: float = 0.48
var _fragments: Array[Dictionary] = []

func setup(radius: float, color: Color, count: int = 18) -> void:
	_fragments.clear()
	for i in range(count):
		var a: float = TAU * float(i) / float(count) + randf_range(-0.12, 0.12)
		_fragments.append({
			"angle": a,
			"speed": randf_range(90.0, 210.0),
			"radius": radius + randf_range(-8.0, 8.0),
			"length": randf_range(12.0, 28.0),
			"color": color.lightened(randf_range(0.0, 0.35)),
		})
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(_age / _duration, 0.0, 1.0)
	var alpha: float = 1.0 - t
	for frag in _fragments:
		var dir := Vector2.from_angle(float(frag.angle))
		var base_radius: float = float(frag.radius) + float(frag.speed) * t
		var p1: Vector2 = dir * base_radius
		var p2: Vector2 = dir * (base_radius + float(frag.length) * (1.0 + t))
		var c: Color = frag.color
		c.a *= alpha
		draw_line(p1, p2, c, 3.0 * alpha + 1.0)
	var ring_color := Color(1.0, 0.72, 0.18, 0.35 * alpha)
	draw_arc(Vector2.ZERO, 78.0 + 70.0 * t, 0.0, TAU, 40, ring_color, 8.0 * alpha + 1.0)
