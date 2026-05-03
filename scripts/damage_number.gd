extends Node3D

@onready var label: Label3D = $Label3D

var _velocity: Vector3 = Vector3.ZERO
var _life: float = 0.0
const LIFETIME: float = 0.8
const RISE_SPEED: float = 1.5
const FADE_START: float = 0.4

func _ready() -> void:
	## 随机左右偏移，避免重叠
	_velocity = Vector3(randf_range(-0.3, 0.3), RISE_SPEED, 0)
	label.modulate.a = 1.0

func _process(delta: float) -> void:
	_life += delta
	global_position += _velocity * delta
	_velocity.y = maxf(_velocity.y - delta * 2.0, 0.0)

	## 渐隐
	if _life > FADE_START:
		var alpha: float = 1.0 - (_life - FADE_START) / (LIFETIME - FADE_START)
		label.modulate.a = maxf(alpha, 0.0)

	if _life >= LIFETIME:
		queue_free()

func setup(amount: int, is_player: bool = false, custom_color: Color = Color.TRANSPARENT) -> void:
	label.text = str(amount)
	if custom_color != Color.TRANSPARENT:
		label.modulate = custom_color
	elif is_player:
		label.modulate = Color(1.0, 0.3, 0.2, 1.0)
	else:
		label.modulate = Color(1.0, 0.85, 0.3, 1.0)
