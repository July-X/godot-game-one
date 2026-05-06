extends ColorRect

var _progress: float = 0.0
var _ready: bool = false

func set_ready_progress(value: float) -> void:
	_ready = value >= 1.0
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) - 4.0
	if r <= 0:
		return

	if _ready:
		draw_circle(c, r, Color(0.15, 0.75, 0.3, 0.35))
		draw_arc(c, r, 0, TAU, 32, Color(0.3, 1.0, 0.45, 0.6), 2.0)
		return

	var steps: int = max(12, int(r * 0.6))
	var bg_color := Color(0.05, 0.08, 0.14, 0.45)
	var bg_pts: PackedVector2Array = [c]
	for i in range(steps + 1):
		var a: float = -PI * 0.5 + TAU * i / steps
		bg_pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polygon(bg_pts, [bg_color])

	if _progress <= 0.01:
		return

	var green_end: float = -PI * 0.5 + TAU * _progress
	var green_steps: int = max(4, int(r * _progress * 0.5))
	var green_pts: PackedVector2Array = [c]
	for i in range(green_steps + 1):
		var a: float = -PI * 0.5 + (green_end + PI * 0.5) * i / green_steps
		green_pts.append(c + Vector2(cos(a), sin(a)) * r)
	var g: float = 0.15 + _progress * 0.6
	var fill_color := Color(0.05 * _progress, g, 0.15 * _progress, 0.25 + _progress * 0.25)
	draw_polygon(green_pts, [fill_color])
