extends Node2D

var _duration: float = 0.3
var _intensity: float = 8.0
var _timer: float = 0.0
var _camera: Camera2D = null

func _ready() -> void:
	_camera = get_viewport().get_camera_2d()
	_timer = _duration

func _physics_process(delta: float) -> void:
	## 用物理帧而不是渲染帧：开启 physics_interpolation 后，引擎会把 Camera2D
	## 切到物理处理模式（控制台会打印 "Camera2D overridden to physics process
	## mode"）。震动值若在渲染帧写、相机在物理帧读，两者节奏不一致会出现台阶感。
	## 交给物理帧后，相机再由插值补到渲染帧，震动在高刷新率下反而更顺。
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
