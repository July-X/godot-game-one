extends Node2D

const HIT_SECONDS := 0.10
const CORE_SECONDS := 0.30
const GOLD := Color("#ffcb70")
const ICE := Color("#b9dcf2")
const HIT_FRAMES := 6
const HIT_CELL := Vector2(31, 31)
const HIT_PATH := "res://assets/sprites/explosion/ordinary_hit.png"
static var _hit_strip: Texture2D = load(HIT_PATH) if ResourceLoader.exists(HIT_PATH) else null
var _age := 0.0
var _duration := HIT_SECONDS
var _core_pickup := false
var _shield_hit := false

func _ready() -> void:
	reset()

func start_core_pickup() -> void:
	start(true)

func start_shield_hit() -> void:
	start(false, true)

func start(core_pickup := false, shield_hit := false) -> void:
	_core_pickup = core_pickup
	_shield_hit = shield_hit
	# 静止火花创建后才赋予世界坐标，首帧不能从 (0,0) 开始插值。
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_INHERIT if core_pickup or shield_hit else PHYSICS_INTERPOLATION_MODE_OFF
	_duration = CORE_SECONDS if core_pickup else HIT_SECONDS
	_age = 0.0
	show()
	set_process(true)
	queue_redraw()

func reset() -> void:
	hide()
	set_process(false)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		reset()
		Pool.release(self)
	else:
		queue_redraw()

func _draw() -> void:
	var t := clampf(_age / _duration, 0.0, 1.0)
	if _core_pickup:
		var radius := lerpf(6.0, 31.0, 1.0 - (1.0 - t) * (1.0 - t))
		var gold := Color(GOLD, 1.0 - t)
		for i in 8:
			var axis := Vector2.from_angle(TAU * i / 8.0)
			var tangent := axis.orthogonal() * lerpf(3.5, 1.0, t)
			draw_line((axis * radius - tangent).round(), (axis * radius + tangent).round(), gold, 2.0)
	elif _shield_hit:
		var gold := Color(GOLD, 1.0 - t)
		for side: int in [-1, 1]:
			var x := roundf(side * lerpf(3.0, 9.0, t))
			draw_line(Vector2(x - 2, 3), Vector2(x + 2, -3), gold, 2)
	elif _hit_strip:
		var frame := mini(floori(t * HIT_FRAMES), HIT_FRAMES - 1)
		var source := Rect2(Vector2(frame * HIT_CELL.x, 0), HIT_CELL)
		# 图集的 (15,15) 是弹体上报的接触点。
		draw_texture_rect_region(_hit_strip, Rect2(Vector2(-15, -15), HIT_CELL), source, Color(1, 1, 1, 1.0 - t))
	else:
		var ice := Color(ICE, 1.0 - t)
		if t < 0.35:
			draw_rect(Rect2(-2, -2, 4, 4), ice)
		for i in 5:
			var ray := Vector2.from_angle(0.35 + i * TAU / 5.0)
			var tip := ray * lerpf(3.0, 11.0, t)
			draw_line((tip - ray * 3.0).round(), tip.round(), ice, 2.0)
