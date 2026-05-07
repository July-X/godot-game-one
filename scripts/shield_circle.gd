extends Node2D
## 圆形光环环绘制（替代 GradientTexture2D 矩形纹理方案）
## 用 draw_arc 绘制完美圆环，无矩形外框

var _radius: float = 80.0
var _color: Color = Color(1.0, 0.7, 0.15, 0.5)
var _thickness: float = 16.0

func setup(r: float, col: Color, thick: float = 16.0) -> void:
	_radius = r
	_color = col
	_thickness = thick
	queue_redraw()

func set_color(col: Color) -> void:
	_color = col
	queue_redraw()

func _draw() -> void:
	var segments: int = 32
	# 外圈半透明光晕
	draw_arc(Vector2.ZERO, _radius, 0, TAU, segments, Color(_color.r, _color.g, _color.b, _color.a * 0.25), _thickness + 6.0)
	# 主色环
	draw_arc(Vector2.ZERO, _radius, 0, TAU, segments, _color, _thickness)
