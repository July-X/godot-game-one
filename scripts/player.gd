extends CharacterBody2D

signal died

@export var move_speed: float = 280.0
@export var acceleration: float = 1200.0
@export var friction: float = 600.0
@export var pickup_radius: float = 80.0

var _shoot_timer: float = 0.0
var _invincible_timer: float = 0.0
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _muzzle_flash: Sprite2D = $MuzzleFlash
@onready var _pickup_area: Area2D = $PickupArea

func _ready() -> void:
	_muzzle_flash.visible = false
	if _pickup_area:
		_pickup_area.body_entered.connect(_on_pickup_body_entered)
		## 拾取范围可视化（调试用，可关闭）
		if _pickup_area.get_child_count() > 0:
			_pickup_area.get_child(0).shape.radius = pickup_radius

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return

	var mouse_pos := get_global_mouse_position()
	var to_mouse: Vector2 = global_position.direction_to(mouse_pos)
	var mouse_dist: float = global_position.distance_to(mouse_pos)

	## 鼠标方向移动 — 距离越远速度越快
	if mouse_dist > 30.0:
		var speed_ratio: float = clamp(mouse_dist / 200.0, 0.1, 1.0)
		var target_vel: Vector2 = to_mouse * move_speed * speed_ratio
		velocity = velocity.lerp(target_vel, acceleration * delta / move_speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	## 限制在屏幕内
	var screen_size := get_viewport_rect().size
	global_position.x = clamp(global_position.x, 20, screen_size.x - 20)
	global_position.y = clamp(global_position.y, 20, screen_size.y - 20)

	## 朝向鼠标
	var angle: float = global_position.angle_to_point(mouse_pos)
	rotation = angle + PI * 0.5

	## 自动射击
	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_shoot()

	## 自动拾取道具
	_try_pickup_nearby()

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
	var base_angle: float = global_position.angle_to_point(mouse_pos)
	var bullet_count: int = GameState.get_bullet_count()
	var spread: float = deg_to_rad(GameState.get_bullet_spread_angle())

	var start_angle: float = base_angle - spread * 0.5
	var step: float = spread / max(bullet_count - 1, 1)

	for i in bullet_count:
		var bullet_angle: float = start_angle + step * i
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(bullet_angle) * 20, bullet_angle, GameState.get_bullet_damage(), true)

	## 枪口闪烁
	if _muzzle_flash:
		_muzzle_flash.visible = true
		var tween := create_tween()
		tween.tween_property(_muzzle_flash, "modulate:a", 0.0, 0.08)
		tween.tween_callback(func(): _muzzle_flash.visible = false)

func _try_pickup_nearby() -> void:
	## 自动拾取范围内的道具
	var powerups := get_tree().get_nodes_in_group("powerups")
	for pu in powerups:
		if pu.is_inside_tree() and global_position.distance_to(pu.global_position) < pickup_radius:
			if pu.has_method("collect"):
				pu.collect()

func _on_pickup_body_entered(body: Node2D) -> void:
	if body.is_in_group("powerups") and body.has_method("collect"):
		body.collect()

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
