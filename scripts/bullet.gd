extends Area2D

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 600.0
var _damage: int = 1
var _is_player_bullet: bool = true
var _lifetime: float = 3.0

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	connect("area_entered", _on_area_entered)
	## 生成子弹精灵
	_sprite.texture = SpriteFactory.create_bullet_sprite(true)

func setup(pos: Vector2, angle: float, damage: int, is_player: bool) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle + PI * 0.5
	_damage = damage
	_is_player_bullet = is_player
	if _sprite:
		_sprite.texture = SpriteFactory.create_bullet_sprite(is_player)
		var scale_val: float = 1.0 + min(damage * 0.2, 1.5)
		_sprite.scale = Vector2(scale_val, scale_val)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_lifetime -= delta
	if _lifetime <= 0:
		queue_free()
	var screen := get_viewport_rect().size
	if global_position.x < -50 or global_position.x > screen.x + 50 or global_position.y < -50 or global_position.y > screen.y + 50:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if _is_player_bullet:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(_damage)
			_spawn_hit()
			queue_free()
	else:
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(_damage)
			_spawn_hit()
			queue_free()

func _on_area_entered(area: Area2D) -> void:
	if _is_player_bullet:
		if area.is_in_group("enemy_hitbox") and area.get_parent().has_method("take_damage"):
			area.get_parent().take_damage(_damage)
			_spawn_hit()
			queue_free()

func _spawn_hit() -> void:
	var hit = preload("res://scenes/effects/hit_effect.tscn").instantiate()
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
