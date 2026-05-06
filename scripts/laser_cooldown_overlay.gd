extends ColorRect

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) - 4.0
	if r <= 0:
		return

	if _progress >= 1.0:
		draw_circle(c, r, Color(0.3, 0.15, 0.9, 0.55))
		draw_arc(c, r - 1, 0, TAU, 32, Color(0.5, 0.3, 1.0, 0.85), 3.0)
		return

	var steps: int = max(12, int(r * 0.8))
	var bg_pts: PackedVector2Array = [c]
	for i in range(steps + 1):
		var a: float = -PI * 0.5 + TAU * i / steps
		bg_pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polygon(bg_pts, [Color(0.08, 0.06, 0.25, 0.55)])

	if _progress <= 0.01:
		return

	var pie: float = -PI * 0.5 + TAU * _progress
	var psteps: int = max(4, int(r * max(_progress, 0.05) * 0.5))
	var pts: PackedVector2Array = [c]
	for i in range(psteps + 1):
		var a: float = -PI * 0.5 + (pie + PI * 0.5) * i / psteps
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var intensity: float = 0.4 + _progress * 0.5
	draw_polygon(pts, [Color(0.35 * _progress, 0.15 * _progress, 0.9 * _progress, intensity)])
