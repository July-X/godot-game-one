extends CharacterBody2D

signal enemy_died

@export var health: int = 2
@export var move_speed: float = 60.0
@export var score_value: int = 10
@export var shoot_cooldown: float = 2.0

var _shoot_timer: float = 0.0
var _target: Node2D = null
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")

func _ready() -> void:
	add_to_group("enemies")
	## 随机初始移动方向
	var angle := randf() * TAU
	velocity = Vector2.from_angle(angle) * move_speed
	_shoot_timer = randf_range(0.5, shoot_cooldown)

func set_target(target: Node2D) -> void:
	_target = target

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return

	## 移动
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		velocity = velocity.lerp(to_target * move_speed, 2.0 * delta)
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.5 * delta)

	move_and_slide()

	## 屏幕边界反弹
	var screen := get_viewport_rect().size
	if global_position.x < 20 or global_position.x > screen.x - 20:
		velocity.x *= -1
		global_position.x = clamp(global_position.x, 20, screen.x - 20)
	if global_position.y < 20 or global_position.y > screen.y - 20:
		velocity.y *= -1
		global_position.y = clamp(global_position.y, 20, screen.y - 20)

	## 朝向玩家
	if _target and is_instance_valid(_target):
		rotation = global_position.angle_to_point(_target.global_position) + PI * 0.5

	## 射击
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _target and is_instance_valid(_target):
		_shoot()
		_shoot_timer = shoot_cooldown + randf_range(-0.5, 0.5)

func _shoot() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var angle := global_position.angle_to_point(_target.global_position)
	var bullet := _bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.setup(global_position + Vector2.from_angle(angle) * 20, angle, 1, false)

func take_damage(amount: int = 1) -> void:
	health -= amount
	## 受击闪烁
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.1)

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
	## 20% 概率掉落道具
	if randf() < 0.2:
		var pu = _powerup_scene.instantiate()
		get_tree().current_scene.add_child(pu)
		pu.global_position = global_position
		var types := ["spread", "speed", "power", "heal", "bomb"]
		pu.setup(types[randi() % types.size()])
