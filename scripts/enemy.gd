extends CharacterBody2D

signal enemy_died

@export var enemy_type: int = 0
@export var health: int = 2
@export var move_speed: float = 60.0
@export var shoot_cooldown: float = 2.0

var _shoot_timer: float = 0.0
var _target: Node2D = null
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")
var _move_angle: float = 0.0
var _wobble_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("enemies")
	if _sprite:
		_sprite.texture = SpriteFactory.create_enemy_sprite(enemy_type)
	_move_angle = randf() * TAU
	_wobble_timer = randf() * TAU
	_shoot_timer = randf_range(0.5, shoot_cooldown)

func set_target(target: Node2D) -> void:
	_target = target

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return

	_wobble_timer += delta * 2.0

	## 移动模式因类型而异
	match enemy_type:
		0: _move_chase(delta)
		1: _move_zigzag(delta)
		2: _move_orbit(delta)

	move_and_slide()

	## 屏幕边界反弹
	var screen := get_viewport_rect().size
	var margin: float = 20.0
	if global_position.x < margin or global_position.x > screen.x - margin:
		velocity.x *= -0.8
		global_position.x = clamp(global_position.x, margin, screen.x - margin)
	if global_position.y < margin or global_position.y > screen.y - margin:
		velocity.y *= -0.8
		global_position.y = clamp(global_position.y, margin, screen.y - margin)

	## 朝向玩家
	if _target and is_instance_valid(_target):
		var angle: float = global_position.angle_to_point(_target.global_position) + PI * 0.5
		rotation = angle

	## 射击
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _target and is_instance_valid(_target):
		_shoot()
		_shoot_timer = shoot_cooldown + randf_range(-0.3, 0.3)

func _move_chase(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		velocity = velocity.lerp(to_target * move_speed, 1.5 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 50.0 * delta)

func _move_zigzag(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		var perp: Vector2 = Vector2(-to_target.y, to_target.x)
		var wobble: float = sin(_wobble_timer) * 0.6
		var dir: Vector2 = (to_target + perp * wobble).normalized()
		velocity = velocity.lerp(dir * move_speed, 1.2 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 50.0 * delta)

func _move_orbit(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		var perp: Vector2 = Vector2(-to_target.y, to_target.x)
		var dist: float = global_position.distance_to(_target.global_position)
		var target_dist: float = 200.0
		var radial: float = (dist - target_dist) / target_dist
		var dir: Vector2 = (perp.normalized() * 0.7 + to_target.normalized() * -radial * 0.3).normalized()
		velocity = velocity.lerp(dir * move_speed, 1.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 50.0 * delta)

func _shoot() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var angle: float = global_position.angle_to_point(_target.global_position)
	match enemy_type:
		0: _shoot_single(angle)
		1: _shoot_spread(angle)
		2: _shoot_circle()

func _shoot_single(angle: float) -> void:
	var bullet := _bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.setup(global_position + Vector2.from_angle(angle) * 20, angle, 1, false)

func _shoot_spread(angle: float) -> void:
	for i in range(-1, 2):
		var a: float = angle + i * 0.2
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 20, a, 1, false)

func _shoot_circle() -> void:
	for i in range(6):
		var a: float = float(i) * TAU / 6.0
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 20, a, 1, false)

func take_damage(amount: int = 1) -> void:
	health -= amount
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.08)
	if health <= 0:
		die()

func die() -> void:
	GameState.add_kill()
	enemy_died.emit()
	_spawn_explosion()
	_try_spawn_powerup()
	queue_free()

func _spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_enemy_death()

func _try_spawn_powerup() -> void:
	if randf() < 0.15 + enemy_type * 0.05:
		var pu = _powerup_scene.instantiate()
		get_tree().current_scene.add_child(pu)
		pu.global_position = global_position
		var types := ["spread", "speed", "power", "heal", "bomb"]
		pu.setup(types[randi() % types.size()])
