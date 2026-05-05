extends Area2D

const MAX_HEALTH: int = 100

var _speed: float = 60.0
var _direction: Vector2 = Vector2.DOWN
var _rotation_speed: float = 0.0
var _size: int = 24
var _health: int = MAX_HEALTH

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
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	rotation += _rotation_speed * delta
	var screen := get_viewport_rect().size
	var margin: float = 80.0
	if global_position.x < -margin or global_position.x > screen.x + margin or global_position.y < -margin or global_position.y > screen.y + margin:
		queue_free()

func take_damage(amount: float) -> void:
	_health -= amount
	var tween := create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "modulate", Color(2.0, 1.8, 1.0, 1.0), 0.04)
	tween.tween_callback(func():
		var recover := create_tween()
		recover.tween_property($Sprite2D, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	)
	if _health <= 0:
		_destroy()

func _destroy() -> void:
	var exp = preload("res://scenes/effects/explosion.tscn").instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_explosion()
	GameState.add_score(50)
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		GameState.death_message = "撞上小行星 遭受重创"
		body.take_damage(max(1.0, ceil(GameState.max_health * 0.5)))
		_destroy()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_bullets") and area.has_method("setup"):
		take_damage(area._damage)
		var hit = preload("res://scenes/effects/hit_effect.tscn").instantiate()
		get_tree().current_scene.add_child(hit)
		hit.global_position = global_position
		area.queue_free()
