extends Node2D
## 土星环式护盾效果
## draw_polyline 绘制椭圆环，半径固定（按最大飞机尺寸），层数控制光晕数量

var _base_radius: float = 48.0
var _layer_count: int = 0
var _ring_angle: float = 0.0
var _opacity: float = 1.0

## 椭圆比例（x 轴拉伸，y 轴压缩 = 透视效果）
const ELLIPSE_X: float = 1.6
const ELLIPSE_Y: float = 0.5

func setup(layers: int, opacity: float = 1.0) -> void:
	_layer_count = layers
	_opacity = opacity

func _process(delta: float) -> void:
	_ring_angle += delta * 0.3  # 缓慢自转
	queue_redraw()

func _draw() -> void:
	if _layer_count <= 0:
		return

	var segments: int = 28
	var rings: Array[Dictionary] = []

	## 根据层数生成环数：层 1→1环，层 5→3环，层 10→5环，层 30→7环
	var ring_count: int = mini(2 + _layer_count / 5, 7)

	for r in range(ring_count):
		var t: float = float(r) / float(max(ring_count - 1, 1))
		var radius_offset: float = 6.0 + t * 28.0  # 环从内到外扩散
		var alpha: float = (0.3 + 0.5 * (1.0 - t)) * _opacity
		var thick: float = 2.0 + (1.0 - t) * 4.0  # 内环粗外环细
		var hue_shift: float = t * 0.15
		rings.append({
			"radius": _base_radius + radius_offset,
			"color": Color(0.2 + hue_shift, 0.5 - hue_shift * 0.3, 1.0, alpha),
			"thick": thick,
		})

	for ring in rings:
		var r: float = ring.radius
		var pts: PackedVector2Array = []
		for i in range(segments + 1):
			var a: float = TAU * i / segments + _ring_angle
			var x: float = cos(a) * r * ELLIPSE_X
			var y: float = sin(a) * r * ELLIPSE_Y
			pts.append(Vector2(x, y))
		## 更亮的尾迹效果：双层叠加，主色 2px + 辉光 5px
		var glow := Color(ring.color.r, ring.color.g, ring.color.b, ring.color.a * 0.4)
		draw_polyline(pts, glow, ring.thick + 4.0)
		draw_polyline(pts, ring.color, ring.thick)
