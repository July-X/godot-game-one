extends Node2D

var _age: float = 0.0
var _duration: float = 0.48
var _fragments: Array[Dictionary] = []
var _flecks := PackedVector2Array()
var _spread := 1.0
var _mothership_release := false

func setup_mothership_release() -> void:
	_mothership_release = true
	_duration = 0.32
	_spread = 0.22
	setup(72.0, Color(0.45, 0.66, 0.80, 0.6), 24)

func setup(radius: float, color: Color, count: int = 18, compact := false) -> void:
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
	if compact:
		_duration = 0.23
		_spread = 0.14
		# 六个余烬沿用原爆点的随机取样，与盾片同画在一个节点里。
		for i in 6:
			_flecks.append(Vector2(randf_range(-30, 30), randf_range(-30, 30)))
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
		var base_radius: float = float(frag.radius) + float(frag.speed) * t * _spread
		var p1: Vector2 = dir * base_radius
		var p2: Vector2 = dir * (base_radius + float(frag.length) * (1.0 + t) * sqrt(_spread))
		var c: Color = frag.color
		c.a *= alpha
		draw_line(p1, p2, c, (1.0 if _mothership_release else 3.0) * alpha + 1.0)
	if _mothership_release:
		return
	var ring_color := Color(1.0, 0.72, 0.18, 0.35 * alpha)
	draw_arc(Vector2.ZERO, 78.0 + 70.0 * t * _spread, 0.0, TAU, 40, ring_color, 8.0 * alpha * _spread + 1.0)
	for fleck in _flecks:
		draw_rect(Rect2((fleck * (1.0 + t)).round(), Vector2(3, 2)), Color(1.0, 0.82, 0.45, alpha))
