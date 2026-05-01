extends Area3D

@export var speed: float = 18.0
@export var lifetime: float = 1.2
@export var damage: int = 1

var _direction = Vector3(0, 0, -1)
var _hit_effect_scene = preload("res://scenes/entities/hit_effect.tscn")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func configure(direction: Vector3) -> void:
	_direction = direction.normalized()
	look_at(global_position + _direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_spawn_hit_effect()
	queue_free()

func _spawn_hit_effect() -> void:
	var effect = _hit_effect_scene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position
