extends Node2D

var _duration: float = 0.3
var _intensity: float = 8.0
var _timer: float = 0.0
var _camera: Camera2D = null

func _ready() -> void:
	_camera = get_viewport().get_camera_2d()
	_timer = _duration

func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
	_timer -= delta
	if _timer <= 0:
		queue_free()
		return
	var progress: float = _timer / _duration
	var shake_amount: float = _intensity * progress
	_camera.offset = Vector2(
		randf_range(-shake_amount, shake_amount),
		randf_range(-shake_amount, shake_amount)
	)
