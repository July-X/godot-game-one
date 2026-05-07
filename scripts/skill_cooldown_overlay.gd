extends ColorRect
## 像素风三角技能冷却覆盖层
## 从底部向上填充绿色三角，冷却中显示半透明暗色三角

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var m: float = 6.0

	var top := Vector2(w * 0.5, m)
	var br := Vector2(w - m, h - m)
	var bl := Vector2(m, h - m)
	var tri := PackedVector2Array([top, br, bl])

	if _progress >= 1.0:
		## 就绪状态：亮绿色三角 + 像素风格边框（2px）
		var border := PackedVector2Array([top + Vector2(0, 2), br + Vector2(-2, -2), bl + Vector2(2, -2)])
		draw_polygon(tri, [Color(0.15, 0.72, 0.28, 0.55)])
		draw_polyline(tri, Color(0.3, 1.0, 0.5, 0.9), 2.0)
		return

	## 冷却中：半透明暗色三角背景
	draw_polygon(tri, [Color(0.05, 0.08, 0.15, 0.5)])
	draw_polyline(tri, Color(0.3, 0.35, 0.5, 0.6), 2.0)

	if _progress <= 0.01:
		return

	var bottom_y: float = h - m
	var top_y: float = m
	var fill_y: float = bottom_y - (bottom_y - top_y) * _progress

	## 像素风格：用阶梯式填充代替平滑斜线
	var steps: int = max(1, int(_progress * 14))
	var fill_pts: PackedVector2Array = [Vector2(w * 0.5, fill_y)]
	for s in range(1, steps + 1):
		var t: float = float(s) / float(steps)
		var sx: float = lerp(w * 0.5, w - m, t)
		var sy: float = fill_y + (bottom_y - fill_y) * t
		fill_pts.append(Vector2(sx, sy))
	for s in range(steps, 0, -1):
		var t: float = float(s) / float(steps)
		var sx: float = lerp(w * 0.5, m, t)
		var sy: float = fill_y + (bottom_y - fill_y) * t
		fill_pts.append(Vector2(sx, sy))

	draw_polygon(fill_pts, [Color(0.1, 0.6, 0.22, 0.4)])
	## 填充区域边框
	var edge_pts: PackedVector2Array = [Vector2(w * 0.5, fill_y)]
	for s in range(1, steps + 1):
		var t: float = float(s) / float(steps)
		edge_pts.append(Vector2(lerp(w * 0.5, w - m, t), fill_y + (bottom_y - fill_y) * t))
	edge_pts.append(Vector2(w * 0.5, fill_y))
	draw_polyline(edge_pts, Color(0.2, 0.85, 0.4, 0.6), 2.0)
