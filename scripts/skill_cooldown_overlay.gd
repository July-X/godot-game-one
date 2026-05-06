extends ColorRect

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) - 2.0
	if r <= 0:
		return

	if _progress >= 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.7, 0.3, 0.55))
		draw_arc(c, r - 1, 0, TAU, 32, Color(0.3, 1.0, 0.5, 0.8), 3.0)
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.12, 0.55))

	if _progress <= 0.01:
		return

	var pie: float = -PI * 0.5 + TAU * _progress
	var psteps: int = max(4, int(r * max(_progress, 0.05) * 0.5))
	var pts: PackedVector2Array = [c]
	for i in range(psteps + 1):
		var a: float = -PI * 0.5 + (pie + PI * 0.5) * i / psteps
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var g: float = 0.15 + _progress * 0.65
	draw_polygon(pts, [Color(0.08 * _progress, g, 0.18 * _progress, 0.4 + _progress * 0.3)])
