extends Node2D

var _radius: float = 0.0
var _alpha: float = 1.0

func setup(r: float, a: float) -> void:
	_radius = r
	_alpha = a
	queue_redraw()

func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_arc(Vector2.ZERO, _radius, 0, TAU, 32, Color(0.2, 0.55, 1.0, 0.45 * _alpha), 4.0)
