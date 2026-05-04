extends Area2D

var _speed: float = 60.0
var _direction: Vector2 = Vector2.DOWN
var _rotation_speed: float = 0.0
var _size: int = 24

func _ready() -> void:
	_size = randi_range(20, 50)
	$CollisionShape2D.shape.radius = _size * 0.5
	_speed = randf_range(30.0, 100.0)
	_rotation_speed = randf_range(-3.0, 3.0)
	var angle: float = randf_range(0.0, TAU)
	_direction = Vector2.from_angle(angle)
	add_to_group("asteroids")
	SpriteFactory.apply_asteroid_texture($Sprite2D, _size)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	rotation += _rotation_speed * delta
	var screen := get_viewport_rect().size
	var margin: float = 80.0
	if global_position.x < -margin or global_position.x > screen.x + margin or global_position.y < -margin or global_position.y > screen.y + margin:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(99)
		var hit = preload("res://scenes/effects/hit_effect.tscn").instantiate()
		get_tree().current_scene.add_child(hit)
		hit.global_position = global_position
		var exp = preload("res://scenes/effects/explosion.tscn").instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position
		queue_free()
