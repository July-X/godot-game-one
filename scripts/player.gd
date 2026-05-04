extends CharacterBody2D

signal died

@export var move_speed: float = 260.0
@export var acceleration: float = 1000.0
@export var friction: float = 500.0
@export var pickup_radius: float = 80.0
@export var mouse_sensitivity: float = 0.0008
@export var mouse_smoothing: float = 0.08

var _shoot_timer: float = 0.0
var _invincible_timer: float = 0.0
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _yaw_velocity: float = 0.0
var _pitch_velocity: float = 0.0
var _current_speed: float = 0.0
var _walk_cycle: float = 0.0
var _head_bob_timer: float = 0.0
var _is_moving: bool = false
var _pitch: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _muzzle_flash: Sprite2D = $MuzzleFlash
@onready var _pickup_area: Area2D = $PickupArea
@onready var _engine_glow: Sprite2D = $EngineGlow

func _ready() -> void:
	_muzzle_flash.visible = false
	_update_appearance()
	if _pickup_area:
		_pickup_area.body_entered.connect(_on_pickup_body_entered)
		if _pickup_area.get_child_count() > 0:
			_pickup_area.get_child(0).shape.radius = pickup_radius

func _update_appearance() -> void:
	## 根据升级等级改变外观
	var level: int = GameState.shoot_level
	if _sprite:
		_sprite.texture = SpriteFactory.create_player_sprite(level)
	if _engine_glow:
		var glow_intensity: float = 1.0 + level * 0.3
		_engine_glow.modulate = Color(1.0, 0.6, 0.2, 0.6 * glow_intensity)
		_engine_glow.scale = Vector2(1.0 + level * 0.15, 1.0 + level * 0.15)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and GameState.run_state == "running":
		var target_yaw: float = -event.relative.x * mouse_sensitivity
		var target_pitch: float = -event.relative.y * mouse_sensitivity
		_yaw_velocity = lerp(_yaw_velocity, target_yaw, mouse_smoothing)
		_pitch_velocity = lerp(_pitch_velocity, target_pitch, mouse_smoothing)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and GameState.run_state == "running":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return

	_shoot_timer -= delta
	_invincible_timer = max(_invincible_timer - delta, 0.0)

	## 鼠标视角（平滑插值）
	rotate(_yaw_velocity)
	_pitch = clamp(_pitch + _pitch_velocity, -PI * 0.4, PI * 0.4)
	_yaw_velocity *= 0.8
	_pitch_velocity *= 0.8

	## 输入
	var mouse_pos := get_global_mouse_position()
	var to_mouse: Vector2 = global_position.direction_to(mouse_pos)
	var mouse_dist: float = global_position.distance_to(mouse_pos)

	## 鼠标方向移动
	if mouse_dist > 20.0:
		var speed_ratio: float = clamp(mouse_dist / 250.0, 0.05, 1.0)
		var target_vel: Vector2 = to_mouse * move_speed * speed_ratio
		velocity = velocity.lerp(target_vel, acceleration * delta / move_speed)
		_is_moving = true
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_is_moving = false

	move_and_slide()

	## 屏幕边缘反弹（不死亡）
	var screen_size := get_viewport_rect().size
	var margin: float = 24.0
	var bounced: bool = false
	if global_position.x < margin:
		global_position.x = margin
		velocity.x = abs(velocity.x) * 0.5
		bounced = true
	elif global_position.x > screen_size.x - margin:
		global_position.x = screen_size.x - margin
		velocity.x = -abs(velocity.x) * 0.5
		bounced = true
	if global_position.y < margin:
		global_position.y = margin
		velocity.y = abs(velocity.y) * 0.5
		bounced = true
	elif global_position.y > screen_size.y - margin:
		global_position.y = screen_size.y - margin
		velocity.y = -abs(velocity.y) * 0.5
		bounced = true

	## 朝向鼠标（平滑转向）
	var target_angle: float = global_position.angle_to_point(mouse_pos) + PI * 0.5
	var angle_diff: float = wrapf(target_angle - rotation, -PI, PI)
	rotation += angle_diff * 8.0 * delta

	## 自动射击
	if _shoot_timer <= 0.0:
		_shoot()

	## 自动拾取
	_try_pickup_nearby()

	## 行走动画
	if _is_moved_recently():
		_walk_cycle += delta * 8.0
		_head_bob_timer += delta * 4.0
		_update_walk_animation()
	else:
		_reset_pose()

	## 无敌闪烁
	if _invincible_timer > 0:
		_sprite.modulate.a = 0.3 + abs(sin(_invincible_timer * 20)) * 0.7
	else:
		_sprite.modulate.a = 1.0

func _is_moved_recently() -> bool:
	return velocity.length() > 10.0

func _update_walk_animation() -> float:
	var swing: float = sin(_walk_cycle) * 0.02
	var bounce: float = abs(sin(_walk_cycle)) * 0.01
	_sprite.rotation = swing
	if _engine_glow:
		_engine_glow.position.y = 16.0 + bounce * 20.0
	return bounce

func _reset_pose() -> void:
	_sprite.rotation = 0.0
	if _engine_glow:
		_engine_glow.position.y = 16.0

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

	if _muzzle_flash:
		_muzzle_flash.visible = true
		var tween := create_tween()
		tween.tween_property(_muzzle_flash, "modulate:a", 0.0, 0.06)
		tween.tween_callback(func(): _muzzle_flash.visible = false)

func _try_pickup_nearby() -> void:
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

func on_level_up() -> void:
	_update_appearance()
	## 升级特效
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(_sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
	tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1.0), 0.1)
