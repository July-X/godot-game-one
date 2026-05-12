extends Node
## 移动控制器
##
## 处理桌面端鼠标惯性移动和移动端摇杆移动，
## 包含屏幕边界限制。

@onready var _player: CharacterBody2D = get_parent() as CharacterBody2D

@export var move_speed: float = 260.0
@export var friction: float = 500.0
@export var mouse_sensitivity: float = 0.008

var mouse_vel: Vector2 = Vector2.ZERO
var mobile_vel: Vector2 = Vector2.ZERO
var touch_move: Vector2 = Vector2.ZERO
var mobile_mode: bool = false


func _ready() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		mobile_mode = true


func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if mobile_mode:
		return
	mouse_vel += event.relative * mouse_sensitivity * move_speed


func handle_mobile_move(vec: Vector2) -> void:
	touch_move = vec


func update(delta: float, speed_multiplier: float, screen_size: Vector2) -> void:
	if not mobile_mode:
		mouse_vel = mouse_vel.lerp(Vector2.ZERO, 1.5 * delta)

	if mobile_mode:
		_update_mobile(delta, speed_multiplier)
	else:
		_update_desktop(delta, speed_multiplier)

	_player.move_and_slide()
	_clamp_to_bounds(screen_size)


func _update_desktop(delta: float, speed_multiplier: float) -> void:
	_player.velocity = mouse_vel.limit_length(move_speed * speed_multiplier)
	if _player.velocity.length() > 10.0:
		_player.rotation = _player.velocity.angle() + PI * 0.5


func _update_mobile(delta: float, speed_multiplier: float) -> void:
	if touch_move.length() > 0.1:
		var target: Vector2 = touch_move * move_speed * speed_multiplier
		mobile_vel = mobile_vel.lerp(target, 10.0 * delta)
		_player.velocity = mobile_vel
		_player.rotation = _player.velocity.angle() + PI * 0.5
	else:
		mobile_vel = mobile_vel.lerp(Vector2.ZERO, 12.0 * delta)
		_player.velocity = mobile_vel


func _clamp_to_bounds(screen_size: Vector2) -> void:
	var margin: float = 24.0
	if _player.global_position.x < margin:
		_player.global_position.x = margin
		_player.velocity.x = abs(_player.velocity.x) * 0.5
	elif _player.global_position.x > screen_size.x - margin:
		_player.global_position.x = screen_size.x - margin
		_player.velocity.x = -abs(_player.velocity.x) * 0.5
	if _player.global_position.y < margin:
		_player.global_position.y = margin
		_player.velocity.y = abs(_player.velocity.y) * 0.5
	elif _player.global_position.y > screen_size.y - margin:
		_player.global_position.y = screen_size.y - margin
		_player.velocity.y = -abs(_player.velocity.y) * 0.5
