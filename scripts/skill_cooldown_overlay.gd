extends ColorRect

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var m: float = 8.0

	var top := Vector2(w * 0.5, m)
	var br := Vector2(w - m, h - m)
	var bl := Vector2(m, h - m)
	var tri := PackedVector2Array([top, br, bl])

	if _progress >= 1.0:
		draw_polygon(tri, [Color(0.15, 0.72, 0.28, 0.6)])
		draw_polyline(tri, Color(0.3, 1.0, 0.5, 0.9), 3.0)
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0))
	draw_polygon(tri, [Color(0.05, 0.08, 0.15, 0.55)])
	draw_polyline(tri, Color(0.3, 0.35, 0.5, 0.6), 2.0)

	if _progress <= 0.01:
		return

	var bottom_y: float = h - m
	var top_y: float = m
	var fill_y: float = bottom_y - (bottom_y - top_y) * _progress
	var fill_top := Vector2(w * 0.5, fill_y)
	var fill_br := Vector2(lerp(m, w - m, _progress), bottom_y)
	var fill_bl := Vector2(lerp(w - m, m, _progress), bottom_y)
	draw_polygon(PackedVector2Array([fill_top, fill_br, fill_bl]), [Color(0.1, 0.65, 0.22, 0.45)])
	draw_polyline(PackedVector2Array([fill_top, fill_br, fill_bl]), Color(0.2, 0.9, 0.4, 0.7), 2.0)
