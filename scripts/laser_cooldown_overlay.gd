extends ColorRect
## 像素风圆形激光冷却覆盖层
## 顺时针填充紫色圆环，就绪时显示完整亮紫色圆

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(c.x, c.y) - 6.0
	if r <= 0:
		return

	## 像素风：用 12 边形代替完美圆形
	var segments: int = 12
	var step_angle: float = TAU / segments

	if _progress >= 1.0:
		## 就绪状态：亮紫色圆
		var pts: PackedVector2Array = [c]
		for i in range(segments + 1):
			var a: float = -PI * 0.5 + step_angle * i
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_polygon(pts, [Color(0.25, 0.12, 0.85, 0.5)])
		draw_arc(c, r - 1, -PI * 0.5, -PI * 0.5 + TAU, segments, Color(0.5, 0.3, 1.0, 0.85), 2.0)
		return

	## 冷却中：暗色多边形背景
	var bg_pts: PackedVector2Array = [c]
	for i in range(segments + 1):
		var a: float = -PI * 0.5 + step_angle * i
		bg_pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polygon(bg_pts, [Color(0.06, 0.04, 0.2, 0.5)])
	draw_arc(c, r - 1, -PI * 0.5, -PI * 0.5 + TAU, segments, Color(0.2, 0.15, 0.4, 0.5), 2.0)

	if _progress <= 0.01:
		return

	## 填充扇形（像素风格，用多边形分段填充）
	var pie_angle: float = -PI * 0.5 + TAU * _progress
	var fill_seg: int = max(2, int(segments * _progress))
	var fill_pts: PackedVector2Array = [c]
	for i in range(fill_seg + 1):
		var a: float = -PI * 0.5 + step_angle * i
		fill_pts.append(c + Vector2(cos(a), sin(a)) * r)
	var intensity: float = 0.3 + _progress * 0.6
	draw_polygon(fill_pts, [Color(0.35 * _progress, 0.15 * _progress, 0.9 * _progress, intensity)])
