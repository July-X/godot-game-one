extends Node2D

const HIT_SECONDS := 0.10
const CORE_SECONDS := 0.30
const GOLD := Color("#ffcb70")
const ICE := Color("#b9dcf2")
var _age := 0.0
var _duration := HIT_SECONDS
var _core_pickup := false
var _shield_hit := false

func _ready() -> void:
	reset()

func start_core_pickup() -> void:
	start(true)

func start_shield_hit() -> void:
	start()
	_shield_hit = true

func start(core_pickup := false) -> void:
	_core_pickup = core_pickup
	_shield_hit = false
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
	else:
		var ice := Color(ICE, 1.0 - t)
		if t < 0.35:
			draw_rect(Rect2(-2, -2, 4, 4), ice)
		for i in 5:
			var ray := Vector2.from_angle(0.35 + i * TAU / 5.0)
			var tip := ray * lerpf(3.0, 11.0, t)
			draw_line((tip - ray * 3.0).round(), tip.round(), ice, 2.0)
