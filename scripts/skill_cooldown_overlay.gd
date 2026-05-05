extends ColorRect

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) * 0.85

	var top: Vector2 = c + Vector2(0, -r)
	var bottom_right: Vector2 = c + Vector2(r * 0.866, r * 0.5)
	var bottom_left: Vector2 = c + Vector2(-r * 0.866, r * 0.5)

	var full_points: PackedVector2Array = [top, bottom_right, bottom_left]
	var full_color := Color(0.15, 0.3, 0.5, 0.3)
	draw_polygon(full_points, [full_color])

	if _progress <= 0.0:
		return

	var mid_right: Vector2 = c + Vector2(r * 0.866 * _progress, r * 0.5 * _progress)
	var mid_left: Vector2 = c + Vector2(-r * 0.866 * _progress, r * 0.5 * _progress)

	var g: float = 0.25 + _progress * 0.5
	var fill_color := Color(0.15 * _progress, g, 0.25 * _progress, 0.35 + _progress * 0.3)
	draw_polygon([top, mid_right, mid_left], [fill_color])
