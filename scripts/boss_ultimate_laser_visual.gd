extends Node2D

const Boss = preload("res://scripts/boss.gd")
const BEAM_SHADER := preload("res://scripts/boss_laser_beam.gdshader")
const EMBER := Color("#f16c36")
const AMBER := Color("#ffb86b")
const PIXEL := Vector2.ONE * 2.0
const COOL_SECONDS := 0.22
enum VisualMode { CHARGE, BEAM, COOLING }

var authority_boss: Boss
var _mode := VisualMode.CHARGE
var _age := 0.0
var _duration := 0.0
var _travel_time := 0.0
var _beam_start := Vector2.ZERO
var _beam_end := Vector2.ZERO
var _beam_width := 0.0

func _ready() -> void:
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	z_index = -2

func setup_charge(pos: Vector2, duration: float, age := 0.0) -> void:
	_mode = VisualMode.CHARGE
	global_position = pos
	_duration = duration
	_age = age

func setup_beam(from: Vector2, to: Vector2, travel_time: float, width: float, hold_duration: float, age := 0.0) -> void:
	_mode = VisualMode.BEAM
	global_position = from
	global_rotation = from.angle_to_point(to)
	_beam_start = from
	_beam_end = to
	_travel_time = travel_time
	_duration = travel_time + hold_duration
	_beam_width = width
	_age = age
	var beam := ShaderMaterial.new()
	beam.shader = BEAM_SHADER
	beam.set_shader_parameter("outer_radius", width * 0.5)
	beam.set_shader_parameter("core_radius", width * 0.5 * Boss.ULTIMATE_LASER_INNER_RATIO)
	material = beam

func advance_to_age(age: float) -> void:
	_age = maxf(age, _age)

func finish_beam() -> bool:
	if _mode != VisualMode.BEAM:
		return false
	# 抢在下一次重绘前关掉缓存中的光束矩形。
	(material as ShaderMaterial).set_shader_parameter("beam_open", false)
	_mode = VisualMode.COOLING
	_age = 0.0
	_duration = COOL_SECONDS
	queue_redraw()
	return true

func _process(delta: float) -> void:
	if _mode != VisualMode.COOLING and is_instance_valid(authority_boss):
		_age = authority_boss.get_laser_visual_age()
	else:
		_age += delta
	if _mode != VisualMode.BEAM and _age >= _duration:
		queue_free()
	queue_redraw()

func _draw() -> void:
	match _mode:
		VisualMode.CHARGE: _draw_charge()
		VisualMode.BEAM: _draw_beam()
		VisualMode.COOLING:
			material = null
			_draw_cooling()

func _draw_charge() -> void:
	var level := clampf(_age / _duration, 0.0, 1.0)
	var time := floorf(_age * 30.0) / 30.0
	for i in 28:
		var amount := fposmod(time * (1.25 + (i % 5) * 0.17) + i * 0.618, 1.0)
		var axis := Vector2.from_angle(i * 2.4 + amount * 0.32)
		var radius := lerpf(14.0, lerpf(53.0, 75.0, level) + (i % 3) * 7.0, 1.0 - amount)
		var alpha := sin(amount * PI) * lerpf(0.72, 1.0, level)
		for step in 3:
			var center := (axis * (radius + step * 4.0)).snapped(PIXEL)
			var tone := AMBER if step == 0 else EMBER
			draw_rect(Rect2(center - PIXEL, PIXEL * 2.0), Color(tone, alpha / (1.0 + step)))
	# 从舰体后方出光，让外沿随收能逐渐变暖。
	var halo := 28.0 + level * 14.0
	draw_circle(Vector2.ZERO, halo + 8.0, Color(EMBER, 0.05 + level * 0.10))
	draw_circle(Vector2.ZERO, halo, Color(EMBER, 0.10 + level * 0.16))
	# 晚段的短亮点加快，外缘维持同样的低亮度。
	var beat := fposmod(time * time * 1.6, 1.0)
	for i in 12:
		var arc := i * TAU / 12.0 + time * 0.9
		var radius := lerpf(56.0, 31.0, beat)
		var point := (Vector2.from_angle(arc) * radius).snapped(PIXEL)
		draw_rect(Rect2(point, PIXEL), Color(AMBER, level * (1.0 - beat) * 0.72))

func _draw_beam() -> void:
	var path_length := _beam_start.distance_to(_beam_end) * clampf(_age / _travel_time, 0.0, 1.0)
	if path_length * path_length <= 0.001 or _age >= _duration:
		return
	var beam := material as ShaderMaterial
	var radius := _beam_width * 0.5
	beam.set_shader_parameter("path_length", path_length)
	beam.set_shader_parameter("age", _age)
	draw_rect(Rect2(-radius, -radius, path_length + 2.0 * radius, _beam_width), Color.WHITE)

func _draw_cooling() -> void:
	var heat := 1.0 - clampf(_age / _duration, 0.0, 1.0)
	for i in 11:
		var radius := 31.0 + (i % 4) * 5.0 + 14.0 * (1.0 - heat)
		var center := (Vector2.from_angle(i * 2.4) * radius).snapped(PIXEL)
		draw_rect(Rect2(center, PIXEL * (2.0 if i % 3 == 0 else 1.0)), Color(EMBER, 0.62 * heat))
