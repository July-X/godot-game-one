extends Area2D

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 600.0
var _damage: int = 1
var _is_player_bullet: bool = true
var _lifetime: float = 4.0
var _has_bounced: bool = false
var _level: int = 1

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	connect("area_entered", _on_area_entered)

func setup(pos: Vector2, angle: float, damage: int, is_player: bool, level: int = 1) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle + PI * 0.5
	_damage = damage
	_is_player_bullet = is_player
	_has_bounced = false
	_level = level
	if is_player:
		add_to_group("player_bullets")
	if not is_player:
		_speed = 780.0
	_apply_bullet_appearance()

func _exit_tree() -> void:
	if _is_player_bullet:
		remove_from_group("player_bullets")

func _apply_bullet_appearance() -> void:
	if _is_player_bullet:
		_sprite.texture = SpriteFactory.create_bullet_sprite(true, _level)
		var scale_val: float = 1.0 + min(_damage * 0.15, 1.5)
		_sprite.scale = Vector2(scale_val, scale_val)
	else:
		_sprite.texture = SpriteFactory.create_bullet_sprite(false, 1)
		_sprite.scale = Vector2(1.0, 1.0)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_lifetime -= delta

	## 屏幕边缘反弹一次
	if not _has_bounced:
		var screen := get_viewport_rect().size
		var margin: float = 10.0
		var bounced: bool = false
		if global_position.x < margin:
			global_position.x = margin
			_direction.x = abs(_direction.x)
			bounced = true
		elif global_position.x > screen.x - margin:
			global_position.x = screen.x - margin
			_direction.x = -abs(_direction.x)
			bounced = true
		if global_position.y < margin:
			global_position.y = margin
			_direction.y = abs(_direction.y)
			bounced = true
		elif global_position.y > screen.y - margin:
			global_position.y = screen.y - margin
			_direction.y = -abs(_direction.y)
			bounced = true
		if bounced:
			_has_bounced = true
			_speed *= 1.3
			_direction = _direction.normalized()
			rotation = _direction.angle() + PI * 0.5
			if _is_player_bullet:
				_sprite.modulate = Color(1.0, 0.5, 0.2, 1.0)
			else:
				_sprite.modulate = Color(1.0, 1.0, 0.3, 1.0)
	else:
		var screen2 := get_viewport_rect().size
		if global_position.x < -20 or global_position.x > screen2.x + 20 or global_position.y < -20 or global_position.y > screen2.y + 20:
			queue_free()

	if _lifetime <= 0:
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
