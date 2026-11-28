extends RefCounted
## 首战使用闭环、露芯和聚拢断弧区分盾相。范围沿用母舰原盾环。

const RING_RADIUS := 72.0
const LOCK_SETTLE_SECONDS := 0.18

static func draw_shield_ring(canvas: CanvasItem) -> void:
	canvas.draw_circle(Vector2.ZERO, RING_RADIUS, Color("#355672a0"), false, 4.0, true)
	canvas.draw_circle(Vector2.ZERO, RING_RADIUS, Color("#9dd2e3be"), false, 1.6, true)

static func draw_exposed_core(canvas: CanvasItem) -> void:
	# 低亮机芯是本体上的固定形状，着色与真实命中闪光相互独立。
	var socket := PackedVector2Array([
		Vector2(0, -21), Vector2(10, -9), Vector2(8, 10),
		Vector2(0, 16), Vector2(-8, 10), Vector2(-10, -9),
	])
	canvas.draw_colored_polygon(socket, Color("#30252b"))
	var core := PackedVector2Array([
		Vector2(0, -16), Vector2(6, -8), Vector2(5, 7),
		Vector2(0, 12), Vector2(-5, 7), Vector2(-6, -8),
	])
	canvas.draw_colored_polygon(core, Color("#ab6746"))
	canvas.draw_rect(Rect2(-2, -8, 4, 12), Color("#ecb481"))
	for side in [-1.0, 1.0]:
		var edge := Vector2(side * 13.0, 2.0)
		canvas.draw_line(edge - Vector2(0, 6), edge + Vector2(0, 6), Color("#ce886085"), 2.0)

static func draw_recharge(canvas: CanvasItem, age: float) -> void:
	# 这是循环收束动作。只有权威回盾才闭合圆环。
	for side in 4:
		var travel := fposmod(age / 0.52 + float(side % 2) * 0.48, 1.0)
		var radius := RING_RADIUS + lerpf(19.0, 3.0, travel)
		var angle := side * TAU * 0.25 + PI * 0.25
		var tone := Color("#a2d2e4")
		tone.a = 0.25 + sin(travel * PI) * 0.47
		canvas.draw_arc(Vector2.ZERO, radius, angle - 0.24, angle + 0.24, 8, tone, 2.4, true)
		var direction := Vector2.from_angle(angle)
		var spark := (direction * (radius + 7.0)).round()
		canvas.draw_rect(Rect2(spark - Vector2(1.5, 1.5), Vector2(3, 3)), tone)

static func draw_local_lock(canvas: Node2D, at: Vector2, age: float) -> void:
	var progress := clampf(age / LOCK_SETTLE_SECONDS, 0.0, 1.0)
	var gap := Vector2(30.0, 24.0) + Vector2(9.0, 8.0) * pow(1.0 - progress, 2)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var edge := at + gap * Vector2(x, y)
			var corner := PackedVector2Array([
				canvas.to_local(edge - Vector2(x * 8.0, 0.0)),
				canvas.to_local(edge),
				canvas.to_local(edge - Vector2(0.0, y * 7.0)),
			])
			canvas.draw_polyline(corner, Color("#292020d9"), 4.4, true)
			canvas.draw_polyline(corner, Color("#ffe6acc4"), 2.2, true)
