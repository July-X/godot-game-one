extends CharacterBody2D

signal died

@export var move_speed: float = 300.0
@export var acceleration: float = 1500.0
@export var friction: float = 800.0

var _shoot_timer: float = 0.0
var _invincible_timer: float = 0.0
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _muzzle_flash: Sprite2D = $MuzzleFlash

func _ready() -> void:
	_muzzle_flash.visible = false

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return

	## WASD 移动（带加减速）
	var input := Vector2.ZERO
	input.x = Input.get_axis("move_left", "move_right")
	input.y = Input.get_axis("move_up", "move_down")

	if input.length() > 0:
		input = input.normalized()
		velocity = velocity.lerp(input * move_speed, acceleration * delta / move_speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	## 限制在屏幕内
	var screen_size := get_viewport_rect().size
	global_position.x = clamp(global_position.x, 16, screen_size.x - 16)
	global_position.y = clamp(global_position.y, 16, screen_size.y - 16)

	## 朝向鼠标
	var mouse_pos := get_global_mouse_position()
	var angle := global_position.angle_to_point(mouse_pos)
	rotation = angle + PI * 0.5

	## 射击
	_shoot_timer -= delta
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0:
		_shoot()

	## 无敌闪烁
	if _invincible_timer > 0:
		_invincible_timer -= delta
		_sprite.modulate.a = 0.3 + abs(sin(_invincible_timer * 20)) * 0.7
	else:
		_sprite.modulate.a = 1.0

func _shoot() -> void:
	_shoot_timer = GameState.get_shoot_cooldown()
	SFX.play_shoot()

	var mouse_pos := get_global_mouse_position()
	var base_angle := global_position.angle_to_point(mouse_pos)
	var bullet_count := GameState.get_bullet_count()
	var spread := deg_to_rad(GameState.get_bullet_spread_angle())

	var start_angle: float = base_angle - spread * 0.5
	var step: float = spread / max(bullet_count - 1, 1)

	for i in bullet_count:
		var angle: float = start_angle + step * i
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(angle) * 20, angle, GameState.get_bullet_damage(), true)

	## 枪口闪烁
	if _muzzle_flash:
		_muzzle_flash.visible = true
		var tween := create_tween()
		tween.tween_property(_muzzle_flash, "modulate:a", 0.0, 0.08)
		tween.tween_callback(func(): _muzzle_flash.visible = false)

func take_damage(amount: int = 1) -> void:
	if _invincible_timer > 0:
		return
	GameState.take_damage(amount)
	_invincible_timer = 1.0
	_spawn_hit_effect()
	if GameState.current_health <= 0:
		_spawn_explosion()
		died.emit()
		queue_free()

func _spawn_hit_effect() -> void:
	var hit = preload("res://scenes/effects/hit_effect.tscn").instantiate()
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position

func _spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_explosion()
