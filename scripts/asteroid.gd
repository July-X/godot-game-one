extends Area2D

const MAX_HEALTH: int = 100
const PLAYER_COLLISION_DAMAGE: int = 5

var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

var entity_id: int = 0
var _is_network_ghost: bool = false
var _speed: float = 60.0
var _direction: Vector2 = Vector2.DOWN
var _rotation_speed: float = 0.0
var _size: int = 24
var _health: int = MAX_HEALTH

func get_entity_id() -> int:
	return entity_id

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
	if NetworkManager.is_online() and _is_network_ghost:
		return
	global_position += _direction * _speed * delta
	rotation += _rotation_speed * delta
	var screen := get_viewport_rect().size
	var margin: float = 80.0
	if global_position.x < -margin or global_position.x > screen.x + margin or global_position.y < -margin or global_position.y > screen.y + margin:
		if NetworkManager.is_online() and multiplayer.is_server():
			var scene := get_tree().current_scene
			if scene and scene.has_method("_on_network_asteroid_destroyed"):
				scene._on_network_asteroid_destroyed(entity_id)
		queue_free()

func take_damage(amount: float) -> void:
	_health -= amount
	_health = max(_health, 0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "modulate", Color(2.0, 1.8, 1.0, 1.0), 0.04)
	tween.tween_callback(func():
		var recover := create_tween()
		recover.tween_property($Sprite2D, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	)

func _destroy(killer_peer_id: int = -1) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		var scene := get_tree().current_scene
		if scene and scene.has_method("_on_network_asteroid_destroyed"):
			scene._on_network_asteroid_destroyed(entity_id)
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_explosion()
	GameState.add_score(50, killer_peer_id)
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if NetworkManager.is_online() and _is_network_ghost:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		GameState.death_message = "撞上小行星 遭受重创"
		body.take_damage(PLAYER_COLLISION_DAMAGE)
		_destroy()

func _on_area_entered(area: Area2D) -> void:
	if NetworkManager.is_online() and _is_network_ghost:
		return
	if area.is_in_group("player_bullets") and area.has_method("setup"):
		take_damage(area._damage)
		if _health <= 0:
			var killer_peer_id := -1
			if area.has_method("get"):
				var maybe_owner: Variant = area.get("owner_peer_id")
				if typeof(maybe_owner) == TYPE_INT and int(maybe_owner) > 0:
					killer_peer_id = int(maybe_owner)
			_destroy(killer_peer_id)
		var hit = Pool.acquire("hit_effect", _hit_effect_scene)
		get_tree().current_scene.add_child(hit)
		hit.global_position = global_position
		hit.start()
		area.queue_free()
