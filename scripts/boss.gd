extends CharacterBody2D

signal boss_died

const MAX_SHIELD: int = 20
const DODGE_RANGE: float = 200.0
const BASE_SPEED: float = 55.0
const CHASE_SPEED: float = 70.0

var _health: int = 30
var _shield: int = MAX_SHIELD
var _target: Node2D = null
var _shoot_timer: float = 0.0
var _attack_pattern: int = 0
var _pattern_timer: float = 0.0
var _dodge_direction: float = 1.0
var _dodge_timer: float = 0.0
var _angry_mode: bool = false
var _dead: bool = false

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shield_sprite: Sprite2D = $ShieldSprite

func _ready() -> void:
	add_to_group("enemies")
	_sprite.texture = SpriteFactory.create_boss_sprite()
	_shield_sprite.modulate = Color(0.3, 0.6, 1.0, 0.45)
	_shoot_timer = randf_range(0.5, 1.5)
	_dodge_direction = 1.0 if randf() > 0.5 else -1.0

func set_target(target: Node2D) -> void:
	_target = target

func _physics_process(delta: float) -> void:
	if not GameState.game_running or _dead:
		return

	_handle_movement(delta)
	_handle_dodge(delta)
	_handle_attacks(delta)
	_update_shield_visual(delta)
	_update_angry_mode()
	_shoot_timer -= delta
	_pattern_timer += delta

	move_and_slide()

	_screen_clamp()

	if _target and is_instance_valid(_target):
		var angle: float = global_position.angle_to_point(_target.global_position) + PI * 0.5
		rotation = angle

func _handle_movement(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		velocity = velocity.move_toward(Vector2.ZERO, 30.0 * delta)
		return

	var to_target: Vector2 = global_position.direction_to(_target.global_position)
	var dist: float = global_position.distance_to(_target.global_position)
	var speed: float = CHASE_SPEED if _angry_mode else BASE_SPEED

	if dist > 350.0:
		velocity = velocity.lerp(to_target * speed, 1.0 * delta)
	elif dist < 180.0:
		velocity = velocity.lerp(-to_target * speed * 0.6, 1.0 * delta)
	else:
		var perp: Vector2 = Vector2(-to_target.y, to_target.x).normalized()
		var strafe_dir: Vector2 = perp * _dodge_direction
		velocity = velocity.lerp(strafe_dir * speed * 0.7, 1.0 * delta)

func _handle_dodge(delta: float) -> void:
	_dodge_timer -= delta
	if _dodge_timer <= 0:
		_dodge_direction *= -1.0
		_dodge_timer = randf_range(1.5, 3.0)

	dodge_nearby_bullets()

func dodge_nearby_bullets() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var bullets := get_tree().get_nodes_in_group("player_bullets")
	for bullet in bullets:
		if not bullet.is_inside_tree():
			continue
		var to_bullet: Vector2 = global_position.direction_to(bullet.global_position)
		var dist: float = global_position.distance_to(bullet.global_position)
		if dist < DODGE_RANGE:
			var dodge_dir: Vector2 = Vector2(-to_bullet.y, to_bullet.x).normalized()
			velocity += dodge_dir * 200.0 * get_process_delta_time()
			_dodge_timer = randf_range(0.3, 0.8)

func _handle_attacks(delta: float) -> void:
	if _shoot_timer <= 0.0 and _target and is_instance_valid(_target):
		_shoot_timer = _get_fire_rate()
		_pattern_timer = 0.0
		_attack_pattern = randi() % 3
		match _attack_pattern:
			0: _attack_spread()
			1: _attack_targeted_burst()
			2: _attack_ring()

func _get_fire_rate() -> float:
	var base: float = 1.8 if not _angry_mode else 1.0
	return base + randf_range(-0.2, 0.3)

func _attack_spread() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var angle: float = global_position.angle_to_point(_target.global_position)
	var count: int = 5 if not _angry_mode else 7
	var spread_angle: float = deg_to_rad(35.0) if not _angry_mode else deg_to_rad(50.0)
	var start_a: float = angle - spread_angle * 0.5
	var step: float = spread_angle / max(count - 1, 1)
	for i in range(count):
		var a: float = start_a + step * i
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 28, a, 2, false)
	SFX.play_enemy_death()

func _attack_targeted_burst() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var burst_count: int = 4 if not _angry_mode else 6
	for i in range(burst_count):
		var angle: float = global_position.angle_to_point(_target.global_position)
		var spread_offset: float = deg_to_rad(randf_range(-6.0, 6.0))
		var a: float = angle + spread_offset
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 28, a, 1, false)
	SFX.play_shoot()

func _attack_ring() -> void:
	var count: int = 8 if not _angry_mode else 12
	for i in range(count):
		var a: float = float(i) * TAU / float(count)
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 28, a, 1, false)
	SFX.play_explosion()

func _update_angry_mode() -> void:
	_angry_mode = _health <= 15 and _shield <= 0

func _update_shield_visual(delta: float) -> void:
	if _shield > 0:
		_shield_sprite.visible = true
		var alpha: float = 0.25 + 0.25 * abs(sin(Time.get_ticks_msec() * 0.003))
		var shield_ratio: float = float(_shield) / float(MAX_SHIELD)
		var r: float = 0.3 + (1.0 - shield_ratio) * 0.5
		_shield_sprite.modulate = Color(r, 0.4 + shield_ratio * 0.3, 1.0, alpha)
		_shield_sprite.scale = Vector2(1.0, 1.0) * (0.9 + 0.1 * abs(sin(Time.get_ticks_msec() * 0.002)))
	else:
		_shield_sprite.visible = false

func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	if _shield > 0:
		_shield -= amount
		_spawn_shield_hit_effect()
		_shield_sprite.modulate = Color(1.0, 1.0, 1.0, 0.8)
		var tween := create_tween()
		tween.tween_property(_shield_sprite, "modulate", Color(0.3, 0.6, 1.0, 0.45), 0.08)
		if _shield <= 0:
			_shield_break_effect()
		return
	_health -= amount
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.08)
	if _health <= 0:
		_die()

func _spawn_shield_hit_effect() -> void:
	var hit = preload("res://scenes/effects/hit_effect.tscn").instantiate()
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position

func _shield_break_effect() -> void:
	SFX.play_explosion()
	for i in range(4):
		var exp = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	_shield_sprite.visible = false

func _die() -> void:
	_dead = true
	boss_died.emit()
	GameState.add_kill()
	GameState.add_score(500 * GameState.level)
	call_deferred("_spawn_explosion")
	call_deferred("_spawn_rewards")
	queue_free()

func _spawn_explosion() -> void:
	for i in range(6):
		var exp = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	SFX.play_explosion()

func _spawn_rewards() -> void:
	for type in ["heal", "bomb", "spread", "speed"]:
		var pu = _powerup_scene.instantiate()
		get_tree().current_scene.add_child(pu)
		pu.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		pu.setup(type)

func _screen_clamp() -> void:
	var screen := get_viewport_rect().size
	var margin: float = 40.0
	if global_position.x < margin:
		global_position.x = margin
		velocity.x = abs(velocity.x) * 0.5
	elif global_position.x > screen.x - margin:
		global_position.x = screen.x - margin
		velocity.x = -abs(velocity.x) * 0.5
	if global_position.y < margin:
		global_position.y = margin
		velocity.y = abs(velocity.y) * 0.5
	elif global_position.y > screen.y - margin:
		global_position.y = screen.y - margin
		velocity.y = -abs(velocity.y) * 0.5
