extends Control
## 升级卡的图标（程序化绘制，不依赖字体或 emoji）
##
## 为什么不用 emoji / 特殊字符：项目没有内置图标字体，缺字形会显示成方块；
## 而且 64×64 的像素风配彩色 emoji 会非常突兀。这里用 Godot 的 draw API
## 直接画几何图形，和游戏的程序化美术管线是同一套语言。
##
## 为什么必须有图标：弹幕战斗中玩家只有零点几秒扫一眼面板，
## 纯文字读不完。图标能在 0.2 秒内传达"穿透 / 爆炸 / 追踪 / 散开"，
## 文字只是补充说明而不是主要信息通道。

const ICON_SIZE: float = 40.0
const BULLET_COLOR: Color = Color(0.55, 0.9, 1.0)
const ACCENT_COLOR: Color = Color(1.0, 0.85, 0.45)

var _card_id: String = ""
var _tint: Color = Color.WHITE


func setup(card_id: String, tint: Color) -> void:
	_card_id = card_id
	_tint = tint
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	match _card_id:
		"pierce": _draw_pierce(c)
		"splash": _draw_splash(c)
		"homing": _draw_homing(c)
		"ricochet": _draw_ricochet(c)
		"graze_focus": _draw_graze(c)
		"power": _draw_power(c)
		"firerate": _draw_firerate(c)
		"spread": _draw_spread(c)
		"vitality": _draw_vitality(c)
		"shield": _draw_shield(c)
		_: _draw_power(c)


## 一颗子弹（所有图标的公共元素，统一的"这是射击"符号）
func _bullet(c: Vector2, dir: Vector2, scale_f: float = 1.0) -> void:
	var s: float = 3.0 * scale_f
	draw_rect(Rect2(c - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), BULLET_COLOR)
	## 朝向的小尖角，让"方向"一眼可读
	var tip: Vector2 = c + dir * s * 2.2
	draw_colored_polygon(PackedVector2Array([
		tip, c + dir * s * 0.6 + dir.orthogonal() * s, c + dir * s * 0.6 - dir.orthogonal() * s,
	]), BULLET_COLOR)


func _arrow(from: Vector2, to: Vector2, col: Color, width: float = 2.0) -> void:
	draw_line(from, to, col, width)
	var dir: Vector2 = (to - from).normalized()
	draw_colored_polygon(PackedVector2Array([
		to, to - dir * 7.0 + dir.orthogonal() * 3.5, to - dir * 7.0 - dir.orthogonal() * 3.5,
	]), col)


## 贯穿：子弹 + 穿过它的箭头
func _draw_pierce(c: Vector2) -> void:
	_arrow(c + Vector2(-15, 0), c + Vector2(15, 0), ACCENT_COLOR, 2.5)
	_bullet(c, Vector2.RIGHT, 1.2)


## 溅射：子弹 + 爆开的星芒
func _draw_splash(c: Vector2) -> void:
	for i in range(8):
		var a: float = float(i) * TAU / 8.0
		draw_line(c + Vector2.from_angle(a) * 6.0, c + Vector2.from_angle(a) * 16.0,
			ACCENT_COLOR, 2.0)
	_bullet(c, Vector2.UP, 0.9)


## 追踪：子弹 + 弯向目标的弧线
func _draw_homing(c: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in range(13):
		var t: float = float(i) / 12.0
		pts.append(c + Vector2(lerpf(-16.0, 6.0, t), -sin(t * PI * 0.9) * 12.0))
	draw_polyline(pts, ACCENT_COLOR, 2.0)
	_bullet(c + Vector2(8, 0), Vector2.RIGHT, 0.9)


## 回弹：Z 字折线
func _draw_ricochet(c: Vector2) -> void:
	draw_polyline(PackedVector2Array([
		c + Vector2(-16, 12), c + Vector2(-5, -10), c + Vector2(6, 12), c + Vector2(16, -8),
	]), ACCENT_COLOR, 2.0)
	_bullet(c + Vector2(16, -8), Vector2.RIGHT, 0.8)


## 擦弹：中心点 + 外环（"贴着飞"就是环）
func _draw_graze(c: Vector2) -> void:
	draw_arc(c, 15.0, 0.0, TAU, 24, ACCENT_COLOR, 2.0)
	draw_circle(c, 3.5, BULLET_COLOR)


## 威力：更粗的子弹 + 加重短线
func _draw_power(c: Vector2) -> void:
	_bullet(c, Vector2.UP, 1.8)
	draw_line(c + Vector2(-9, 10), c + Vector2(9, 10), ACCENT_COLOR, 2.0)


## 速射：三发紧邻的子弹（表示"密"）
func _draw_firerate(c: Vector2) -> void:
	for i in range(3):
		_bullet(c + Vector2(-8.0 + float(i) * 8.0, 0), Vector2.UP, 0.75)


## 扩散：三发扇形散开
func _draw_spread(c: Vector2) -> void:
	_bullet(c + Vector2(0, 12), Vector2.UP, 0.7)
	_bullet(c + Vector2(-9, 12), Vector2.UP.rotated(-0.5), 0.7)
	_bullet(c + Vector2(9, 12), Vector2.UP.rotated(0.5), 0.7)


## 装甲：盾形
func _draw_vitality(c: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -15), c + Vector2(12, -8), c + Vector2(12, 4),
		c + Vector2(0, 15), c + Vector2(-12, 4), c + Vector2(-12, -8),
	]), BULLET_COLOR)


## 护盾电容：盾形 + 闪电
func _draw_shield(c: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -15), c + Vector2(12, -8), c + Vector2(12, 4),
		c + Vector2(0, 15), c + Vector2(-12, 4), c + Vector2(-12, -8),
	]), Color(BULLET_COLOR, 0.45))
	draw_polyline(PackedVector2Array([
		c + Vector2(2, -9), c + Vector2(-4, 0), c + Vector2(2, 0), c + Vector2(-3, 9),
	]), ACCENT_COLOR, 2.5)
