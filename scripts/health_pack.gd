extends Area3D

signal picked_up

@export var heal_amount: int = 2
@export var rotation_speed: float = 90.0  # 度/秒
@export var float_amplitude: float = 0.3
@export var float_speed: float = 2.0

var _time: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_y = global_position.y

func _process(delta: float) -> void:
	# Y 轴旋转
	rotate_y(deg_to_rad(rotation_speed * delta))
	
	# 浮动动画
	_time += delta
	var new_y = _base_y + sin(_time * float_speed) * float_amplitude
	global_position.y = new_y

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("heal"):
		body.heal(heal_amount)
		picked_up.emit()
		SFX.play_pickup()
		queue_free()
