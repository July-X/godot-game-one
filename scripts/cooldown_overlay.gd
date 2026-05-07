extends ColorRect
## 通用冷却覆盖层 — 支持三角形（tri）和圆形（circle）两种像素风格

enum Style { TRIANGLE, CIRCLE }

@export var overlay_style: Style = Style.TRIANGLE

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func set_style(s: Style) -> void:
	overlay_style = s
	queue_redraw()

func _draw() -> void:
	match overlay_style:
		Style.TRIANGLE:
			_draw_triangle()
		Style.CIRCLE:
			_draw_circle()

## ── 三角形（技能：环形散射） ──
func _draw_triangle() -> void:
	var w: float = size.x
	var h: float = size.y
	var m: float = 6.0
	var top := Vector2(w * 0.5, m)
	var br := Vector2(w - m, h - m)
	var bl := Vector2(m, h - m)
	var tri := PackedVector2Array([top, br, bl])

	if _progress >= 1.0:
		draw_polygon(tri, [Color(0.15, 0.72, 0.28, 0.55)])
		draw_polyline(tri, Color(0.3, 1.0, 0.5, 0.9), 2.0)
		return

	draw_polygon(tri, [Color(0.05, 0.08, 0.15, 0.5)])
	draw_polyline(tri, Color(0.3, 0.35, 0.5, 0.6), 2.0)
	if _progress <= 0.01:
		return

	var bottom_y: float = h - m
	var top_y: float = m
	var fill_y: float = bottom_y - (bottom_y - top_y) * _progress
	var steps: int = max(1, int(_progress * 14))
	var fill_pts: PackedVector2Array = [Vector2(w * 0.5, fill_y)]
	for s in range(1, steps + 1):
		var t: float = float(s) / float(steps)
		fill_pts.append(Vector2(lerp(w * 0.5, w - m, t), fill_y + (bottom_y - fill_y) * t))
	for s in range(steps, 0, -1):
		var t: float = float(s) / float(steps)
		fill_pts.append(Vector2(lerp(w * 0.5, m, t), fill_y + (bottom_y - fill_y) * t))
	draw_polygon(fill_pts, [Color(0.1, 0.6, 0.22, 0.4)])
	var edge_pts: PackedVector2Array = [Vector2(w * 0.5, fill_y)]
	for s in range(1, steps + 1):
		var t: float = float(s) / float(steps)
		edge_pts.append(Vector2(lerp(w * 0.5, w - m, t), fill_y + (bottom_y - fill_y) * t))
	edge_pts.append(Vector2(w * 0.5, fill_y))
	draw_polyline(edge_pts, Color(0.2, 0.85, 0.4, 0.6), 2.0)

## ── 圆形（激光/未来技能） ──
func _draw_circle() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) - 6.0
	if r <= 0:
		return
	var segments: int = 12
	var step_angle: float = TAU / segments

	if _progress >= 1.0:
		var pts: PackedVector2Array = [c]
		for i in range(segments + 1):
			var a: float = -PI * 0.5 + step_angle * i
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_polygon(pts, [Color(0.25, 0.12, 0.85, 0.5)])
		draw_arc(c, r - 1, -PI * 0.5, -PI * 0.5 + TAU, segments, Color(0.5, 0.3, 1.0, 0.85), 2.0)
		return

	var bg_pts: PackedVector2Array = [c]
	for i in range(segments + 1):
		var a: float = -PI * 0.5 + step_angle * i
		bg_pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polygon(bg_pts, [Color(0.06, 0.04, 0.2, 0.5)])
	draw_arc(c, r - 1, -PI * 0.5, -PI * 0.5 + TAU, segments, Color(0.2, 0.15, 0.4, 0.5), 2.0)
	if _progress <= 0.01:
		return

	var fill_seg: int = max(2, int(segments * _progress))
	var fill_pts: PackedVector2Array = [c]
	for i in range(fill_seg + 1):
		var a: float = -PI * 0.5 + step_angle * i
		fill_pts.append(c + Vector2(cos(a), sin(a)) * r)
	var intensity: float = 0.3 + _progress * 0.6
	draw_polygon(fill_pts, [Color(0.35 * _progress, 0.15 * _progress, 0.9 * _progress, intensity)])
