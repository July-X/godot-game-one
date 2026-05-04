extends Area2D

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 600.0
var _damage: int = 1
var _is_player_bullet: bool = true
var _lifetime: float = 3.0

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	connect("area_entered", _on_area_entered)

func setup(pos: Vector2, angle: float, damage: int, is_player: bool) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle + PI * 0.5
	_damage = damage
	_is_player_bullet = is_player

	if is_player:
		## 玩家子弹 — 蓝色能量弹
		$Sprite2D.modulate = Color(0.3, 0.7, 1.0, 1.0)
		$Sprite2D.scale = Vector2(0.8, 0.8) + Vector2.ONE * min(damage * 0.15, 1.0)
	else:
		## 敌人子弹 — 红色
		$Sprite2D.modulate = Color(1.0, 0.3, 0.2, 0.9)
		$Sprite2D.scale = Vector2(0.6, 0.6)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_lifetime -= delta
	if _lifetime <= 0:
		queue_free()

	## 出屏删除
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
