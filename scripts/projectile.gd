extends Area3D

@export var speed: float = 20.0
@export var lifetime: float = 1.0
@export var damage: int = 1

var _direction: Vector3 = Vector3(0, 0, -1)
var _hit_effect_scene = preload("res://scenes/entities/hit_effect.tscn")
var _trail_mesh: MeshInstance3D
var _trail_timer: float = 0.0
var _expired: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_trail_mesh = $Trail
	_update_trail()
	await get_tree().create_timer(lifetime).timeout
	if not _expired:
		_expired = true
		queue_free()

func configure(direction: Vector3) -> void:
	_direction = direction.normalized()
	look_at(global_position + _direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_trail_timer += delta
	if _trail_timer >= 0.02:
		_trail_timer = 0.0
		_update_trail()

func _update_trail() -> void:
	if _trail_mesh == null:
		return
	var length: float = 0.4
	var mid: Vector3 = -_direction * length * 0.5
	_trail_mesh.position = mid
	_trail_mesh.transform.basis = Basis().scaled(Vector3(0.03, 0.03, length * 0.5))

func _on_body_entered(body: Node) -> void:
	if _expired:
		return
	_expired = true
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_spawn_hit_effect()
	SFX.play_hit()
	queue_free()

func _spawn_hit_effect() -> void:
	var effect = _hit_effect_scene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position
