extends Node2D
## 渐变光环环（内浅外深）
## 用多层 draw_arc 实现径向渐变效果

var _radius: float = 80.0
var _color: Color = Color(1.0, 0.7, 0.15, 0.5)
var _thickness: float = 20.0

func setup(r: float, col: Color, thick: float = 20.0) -> void:
	_radius = r
	_color = col
	_thickness = thick
	queue_redraw()

func set_color(col: Color) -> void:
	_color = col
	queue_redraw()

func _draw() -> void:
	var segments: int = 32
	var r: float = _radius
	var base: Color = _color
	var thick: float = _thickness

	# 最外层辉光 — 暗、宽、透明
	draw_arc(Vector2.ZERO, r, 0, TAU, segments,
		Color(base.r * 0.7, base.g * 0.7, base.b * 0.7, base.a * 0.15), thick + 10.0)

	# 外圈 — 较暗
	draw_arc(Vector2.ZERO, r, 0, TAU, segments,
		Color(base.r * 0.85, base.g * 0.85, base.b * 0.85, base.a * 0.6), thick * 0.85)

	# 中圈 — 主色
	draw_arc(Vector2.ZERO, r, 0, TAU, segments,
		Color(base.r, base.g, base.b, base.a * 0.85), thick * 0.55)

	# 内圈 — 最亮、最细
	draw_arc(Vector2.ZERO, r, 0, TAU, segments,
		Color(base.r * 1.2, base.g * 1.2, base.b * 1.2, base.a * 0.95), thick * 0.25)
