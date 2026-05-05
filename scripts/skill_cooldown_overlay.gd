extends ColorRect

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) - 2.0
	var start_angle: float = -PI * 0.5
	var end_angle: float = start_angle + TAU * _progress
	var steps: int = max(4, int(r * TAU * 0.3))
	var g: float = 0.25 + _progress * 0.5
	var color := Color(0.15 * _progress, g, 0.25 * _progress, 0.35 + _progress * 0.25)
	var points: PackedVector2Array = [c]
	for i in range(steps + 1):
		var a: float = start_angle + (end_angle - start_angle) * i / steps
		points.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polygon(points, [color])
