extends Node
## 屏幕震动（trauma 模型，Autoload 级别的单例入口由 main.gd 转发）
##
## 为什么不直接把 offset 写死在各个事件里：
## 多处震动同时触发时（例如 Boss 破盾 + 击杀 + 受击），
## 简单赋值会互相覆盖而不是叠加，震感反而变弱。
## trauma 模型把它们变成"累加的强度"，再统一衰减，天然支持叠加。
##
## 震幅 = trauma² × MAX_OFFSET：平方是为了让小事件（0.2）几乎无感、
## 大事件（1.0）才猛烈，符合"平时安静、关键时刻炸一下"的节奏。
## 用随机而非正弦：弹幕游戏的震屏目的是掩盖打击瞬间，正弦的规律摆动会
## 暴露节拍、让玩家觉得画面在"晃"而不是"被击中"。

## 强度累加器，0~1
var _trauma: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _camera: Camera2D = null
var _offset_limit := Vector2.INF
var _soft_hit_left := 0.0
var _soft_hit_cooldown := 0.0

const MAX_OFFSET: float = 12.0
const DECAY_PER_SECOND: float = 1.6
## 小于这个值就不摇了，避免连续小事件把画面搞得一直在抖
const REST_THRESHOLD: float = 0.02
const SOFT_HIT_OFFSET := 1.2
const SOFT_HIT_SECONDS := 0.12
const SOFT_HIT_INTERVAL := 0.22


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return
	_soft_hit_left = maxf(0.0, _soft_hit_left - delta)
	_soft_hit_cooldown = maxf(0.0, _soft_hit_cooldown - delta)
	var offset := Vector2.ZERO
	if _trauma > 0.0:
		_trauma = maxf(_trauma - DECAY_PER_SECOND * delta, 0.0)
		var amount := _trauma * _trauma * MAX_OFFSET
		offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
		if _trauma <= REST_THRESHOLD:
			_trauma = 0.0
			offset = Vector2.ZERO
	elif _soft_hit_left > 0.0:
		# 单方向轻推再回中；不累加 trauma，不覆盖同步的强震屏。
		offset.y = SOFT_HIT_OFFSET * sin(PI * _soft_hit_left / SOFT_HIT_SECONDS)
	if offset != Vector2.ZERO or _shake_offset != Vector2.ZERO:
		_shake_offset = offset
		_camera.offset = offset.clamp(-_offset_limit, _offset_limit)

## 密集命中不会延长动画，留出静止帧；已有显著震屏时不启动。
func add_soft_hit_bump() -> void:
	if _soft_hit_cooldown > 0.0 or _trauma > 0.0:
		return
	_soft_hit_left = SOFT_HIT_SECONDS
	_soft_hit_cooldown = SOFT_HIT_INTERVAL


## 累加震动强度，自动夹在 0~1。
## intensity 语义：0.1 轻微、0.3 明显、0.6 强烈、1.0 极限
func add_trauma(intensity: float) -> void:
	_trauma = clampf(_trauma + intensity, 0.0, 1.0)

## 联机只在取景余量内移动相机，仍按原时序采样震动。
func set_offset_limit(limit: Vector2) -> void:
	_offset_limit = limit

func reset() -> void:
	_trauma = 0.0
	_soft_hit_left = 0.0
	_soft_hit_cooldown = 0.0
	_shake_offset = Vector2.ZERO
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO
