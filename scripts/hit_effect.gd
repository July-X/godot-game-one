extends Node2D

const HIT_SECONDS := 0.10
const CORE_SECONDS := 0.30
const GOLD := Color("#ffcb70")
const ICE := Color("#b9dcf2")
const ARMOR := Color("#76d7f3")
const HULL := Color("#ffd9c7")
const HIT_FRAMES := 6
const HIT_CELL := Vector2(31, 31)
const HIT_PATH := "res://assets/sprites/explosion/ordinary_hit.png"
static var _hit_strip: Texture2D = load(HIT_PATH) if ResourceLoader.exists(HIT_PATH) else null
var _age := 0.0
var _duration := HIT_SECONDS
var _core_pickup := false
var _shield_hit := false
var _ordinary_enemy := false
var _tint := ICE

func _ready() -> void:
	# 静止特效没有需要插值的路径，出生点也没有上一帧。
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	reset()

func start_core_pickup() -> void:
	start(true)

func start_shield_hit() -> void:
	start(false, true)

func start_boss_shield_hit() -> void:
	start(false, true)
	_tint = ARMOR

func start_boss_hull_hit() -> void:
	start()
	_tint = HULL

func start_ordinary_hit() -> void:
	start()
	_ordinary_enemy = true

func start(core_pickup := false, shield_hit := false) -> void:
	_core_pickup = core_pickup
	_shield_hit = shield_hit
	_ordinary_enemy = false
	_tint = GOLD if shield_hit else ICE
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
		var tone := Color(GOLD, 1.0 - t)
		for i in 8:
			var axis := Vector2.from_angle(TAU * i / 8.0)
			var tangent := axis.orthogonal() * lerpf(3.5, 1.0, t)
			draw_line((axis * radius - tangent).round(), (axis * radius + tangent).round(), tone, 2.0)
	elif _shield_hit:
		var tone := Color(_tint, 1.0 - t)
		for side: int in [-1, 1]:
			var x := roundf(side * lerpf(3.0, 9.0, t))
			draw_line(Vector2(x - 2, 3), Vector2(x + 2, -3), tone, 2)
	elif _ordinary_enemy and _hit_strip:
		var frame := mini(floori(t * HIT_FRAMES), HIT_FRAMES - 1)
		var source := Rect2(Vector2(frame * HIT_CELL.x, 0), HIT_CELL)
		# 图集的 (15,15) 是弹体上报的接触点。
		draw_texture_rect_region(_hit_strip, Rect2(Vector2(-15, -15), HIT_CELL), source, Color(1, 1, 1, 1.0 - t))
	else:
		var tone := Color(_tint, 1.0 - t)
		if t < 0.35:
			draw_rect(Rect2(-2, -2, 4, 4), tone)
		for i in 5:
			var ray := Vector2.from_angle(0.35 + i * TAU / 5.0)
			var tip := ray * lerpf(3.0, 11.0, t)
			draw_line((tip - ray * 3.0).round(), tip.round(), tone, 2.0)
