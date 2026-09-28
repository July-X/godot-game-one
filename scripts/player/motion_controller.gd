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


## ── 闪避（Dash）────────────────────────────────────────
##
## 为什么需要它：本作原本只有"鼠标惯性走位"，速度上限就是 move_speed（260），
## 而敌弹速度 430~950。**玩家跑不过子弹**，遇到必须闪的弹型就只能挨打——
## 这是"明明看着有空间却还是被打死"的根本原因。
##
## 闪避不是"加速"，而是**短时间位移 + 无敌帧**：
## 只加速不给无敌帧，玩家冲进弹幕里照样死；只给无敌帧不给位移，
## 则变成原地免疫。两者必须同时给。
##
## 1.1 秒冷却是关键：CD 太短等于常驻无敌，太长则救不了场。
## 0.22 秒无敌 / 1.1 秒 CD ≈ 20% 的时间可以免疫，配合 950px/s 的位移
## 足以从弹幕缝隙里穿出去。
const DASH_SPEED: float = 950.0
const DASH_DURATION: float = 0.16
const DASH_COOLDOWN: float = 1.1
## 无敌帧比位移略长一点，手感更宽容（冲刺末尾擦到弹也不死）
const DASH_IFRAMES: float = 0.22

var _dash_left: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector2 = Vector2.UP
## 本次闪避是否刚结束（用于给一点收尾减速，避免松手瞬间急停）
var _dash_recover: float = 0.0


func can_dash() -> bool:
	return _dash_left <= 0.0 and _dash_cd <= 0.0


func get_dash_cooldown_ratio() -> float:
	if _dash_cd <= 0.0:
		return 0.0
	return clampf(_dash_cd / DASH_COOLDOWN, 0.0, 1.0)


## 触发闪避。dir 为零时用当前朝向。
## 返回 true 表示这次闪避真的触发了（用于播音效/特效）。
func try_dash(dir: Vector2 = Vector2.ZERO) -> bool:
	if not can_dash():
		return false
	_dash_dir = dir.normalized() if dir.length() > 0.01 else _dash_dir_from_velocity()
	if _dash_dir.length() < 0.01:
		_dash_dir = Vector2.UP
	_dash_left = DASH_DURATION
	_dash_cd = DASH_COOLDOWN
	_dash_recover = 0.0
	## 闪避期间清掉鼠标惯性，否则冲刺结束后会被旧速度拽回原处
	if not mobile_mode:
		mouse_vel = Vector2.ZERO
	return true


func _dash_dir_from_velocity() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.UP
	if _player.velocity.length() > 5.0:
		return _player.velocity.normalized()
	## 完全静止时按飞机当前朝向（rotation 指向机头）
	return Vector2.from_angle(_player.rotation - PI * 0.5)


func is_dashing() -> bool:
	return _dash_left > 0.0


func _tick_dash(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd = maxf(_dash_cd - delta, 0.0)
	if _dash_left <= 0.0:
		if _dash_recover > 0.0:
			_dash_recover = maxf(_dash_recover - delta, 0.0)
		return
	_dash_left = maxf(_dash_left - delta, 0.0)
	if _dash_left <= 0.0:
		## 冲刺结束的收尾减速：保留一小段惯性，手感才不会"急停"
		_dash_recover = 0.18


func update(delta: float, speed_multiplier: float, screen_size: Vector2) -> void:
	_tick_dash(delta)
	if not mobile_mode:
		mouse_vel = mouse_vel.lerp(Vector2.ZERO, 1.5 * delta)

	if _dash_left > 0.0:
		_player.velocity = _dash_dir * DASH_SPEED
		_player.rotation = _dash_dir.angle() + PI * 0.5
	elif mobile_mode:
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
