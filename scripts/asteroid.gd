extends Area2D

var _speed: float = 60.0
var _direction: Vector2 = Vector2.DOWN
var _rotation_speed: float = 0.0

func _ready() -> void:
	var size: int = randi_range(16, 40)
	$CollisionShape2D.shape.radius = size * 0.5
	_speed = randf_range(40.0, 90.0)
	_rotation_speed = randf_range(-2.0, 2.0)
	_direction = Vector2.DOWN.rotated(randf_range(-0.3, 0.3))
	SpriteFactory.apply_asteroid_texture($Sprite2D, size)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	rotation += _rotation_speed * delta
	var screen := get_viewport_rect().size
	if global_position.y > screen.y + 60 or global_position.y < -60 or global_position.x < -60 or global_position.x > screen.x + 60:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(99)
		var hit = preload("res://scenes/effects/hit_effect.tscn").instantiate()
		get_tree().current_scene.add_child(hit)
		hit.global_position = global_position
		queue_free()
