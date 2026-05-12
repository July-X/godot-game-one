extends Node2D

enum VisualMode { CHARGE, BEAM }

var _mode: int = VisualMode.CHARGE
var _age: float = 0.0
var _duration: float = 1.0
var _travel_time: float = 0.8
var _beam_start: Vector2 = Vector2.ZERO
var _beam_end: Vector2 = Vector2.ZERO
var _beam_width: float = 96.0

func setup_charge(pos: Vector2, duration: float) -> void:
	_mode = VisualMode.CHARGE
	global_position = pos
	_duration = maxf(duration, 0.1)
	_age = 0.0
	z_index = 85

func setup_beam(from: Vector2, to: Vector2, travel_time: float, width: float, hold_duration: float = 0.0) -> void:
	_mode = VisualMode.BEAM
	global_position = Vector2.ZERO
	_beam_start = from
	_beam_end = to
	_travel_time = maxf(travel_time, 0.05)
	_duration = _travel_time + maxf(hold_duration, 0.0) + 0.35
	_beam_width = maxf(width, 12.0)
	_age = 0.0
	z_index = 86

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= _duration:
		queue_free()

func _draw() -> void:
	if _mode == VisualMode.CHARGE:
		_draw_charge()
	else:
		_draw_beam()

func _draw_charge() -> void:
	var t := clampf(_age / _duration, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_age * 24.0)
	var radius := lerpf(24.0, 86.0, t)
	var alpha := lerpf(0.28, 0.92, t)
	draw_circle(Vector2.ZERO, radius * (1.0 + pulse * 0.08), Color(1.0, 0.12, 0.05, alpha * 0.22))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(1.0, 0.24, 0.12, alpha), 5.0)
	draw_arc(Vector2.ZERO, radius * 0.62, -_age * 5.0, TAU - _age * 5.0, 96, Color(1.0, 0.82, 0.34, alpha), 3.0)
	draw_circle(Vector2.ZERO, 10.0 + pulse * 5.0, Color(1.0, 0.92, 0.55, alpha))

func _draw_beam() -> void:
	var travel_ratio := clampf(_age / _travel_time, 0.0, 1.0)
	var fade := 1.0
	if _age > _travel_time:
		fade = 1.0 - clampf((_age - _travel_time) / maxf(_duration - _travel_time, 0.01), 0.0, 1.0)
	## 推进阶段：rect 向前伸长；持续阶段：满长度
	var beam_len := _beam_start.distance_to(_beam_end)
	var current_len := beam_len * travel_ratio if _age < _travel_time else beam_len
	var dir := (_beam_end - _beam_start).normalized()
	if dir.length_squared() <= 0.001:
		dir = Vector2.DOWN
	var perp := Vector2(-dir.y, dir.x)
	var rect_end := _beam_start + dir * current_len
	## 用多个窄矩形拼成渐变宽束（深红中心→浅红边缘）
	var slices: int = 12
	for i in range(slices):
		var t := (float(i) + 0.5) / float(slices)  ## -0.5~0.5 归一化到横向偏移比例
		var offset := (t - 0.5) * _beam_width
		var edge_ratio: float = abs(t - 0.5) * 2.0  ## 0=中心, 1=边缘
		var r: float = 1.0
		var g: float = lerpf(0.04, 0.35, edge_ratio)
		var b: float = lerpf(0.02, 0.25, edge_ratio)
		var col := Color(r, g, b, 0.7 * fade)
		var slice_w: float = _beam_width / float(slices) * 1.2
		if slice_w < 1.0:
			continue
		var slice_hw := slice_w * 0.5
		var p1 := _beam_start + perp * (offset - slice_hw)
		var p2 := _beam_start + perp * (offset + slice_hw)
		var p3 := rect_end + perp * (offset + slice_hw)
		var p4 := rect_end + perp * (offset - slice_hw)
		draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), col)
	## 中心高亮光柱
	var core_w: float = _beam_width * 0.08
	var core_col := Color(1.0, 0.96, 0.68, 0.7 * fade)
	var cp1 := _beam_start + perp * (-core_w)
	var cp2 := _beam_start + perp * core_w
	var cp3 := rect_end + perp * core_w
	var cp4 := rect_end + perp * (-core_w)
	draw_colored_polygon(PackedVector2Array([cp1, cp2, cp3, cp4]), core_col)
