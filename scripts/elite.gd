extends CharacterBody2D

signal elite_died

const MAX_SHIELD: int = 80
const DODGE_RANGE: float = 280.0
var BASE_SPEED: float = 50.0
var CHASE_SPEED: float = 65.0
const SHIELD_REGEN_TIME: float = 3.0

var _health: int = 50
var _max_health: int = 50
var _shield: int = MAX_SHIELD
var _max_shield: int = MAX_SHIELD
var _target: Node2D = null
var _shoot_timer: float = 0.0
var _attack_pattern: int = 0
var _pattern_timer: float = 0.0
var _dodge_direction: float = 1.0
var _dodge_timer: float = 0.0
var _angry_mode: bool = false
var _dead: bool = false
var _shield_regen_timer: float = SHIELD_REGEN_TIME
var _laser_angle: float = 0.0
var _laser_active: bool = false
var _laser_fire_timer: float = 0.0
var _summon_timer: float = 0.0
var _health_at_phase_change: bool = false

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shield_sprite: Sprite2D = $ShieldSprite
var _shield_circle: Node2D = null
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _turret_l: Node2D = $TurretL
@onready var _turret_r: Node2D = $TurretR

func _ready() -> void:
	add_to_group("enemies")
	_sprite.texture = SpriteFactory.create_elite_sprite()
	_shield_sprite.visible = false
	_shield_circle = Node2D.new()
	_shield_circle.set_script(preload("res://scripts/shield_circle.gd"))
	_shield_circle.z_index = 3
	_shield_circle.position = Vector2(0, 0)
	add_child(_shield_circle)
	_shield_circle.setup(80.0, Color(1.0, 0.7, 0.15, 0.5))
	_shoot_timer = randf_range(0.5, 1.5)
	_dodge_direction = 1.0 if randf() > 0.5 else -1.0

func set_target(target: Node2D) -> void:
	_target = target

func set_difficulty(mult: float) -> void:
	_health = int(50.0 * mult)
	_max_health = _health
	_shield = int(80.0 * mult)
	_max_shield = _shield
	BASE_SPEED = 50.0 * mult
	CHASE_SPEED = 65.0 * mult

func _physics_process(delta: float) -> void:
	if not GameState.game_running or _dead:
		return

	_handle_movement(delta)
	_handle_dodge(delta)
	_handle_attacks(delta)
	_update_shield(delta)
	_update_angry_mode()
	_update_health_bar()
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

	if dist > 400.0:
		velocity = velocity.lerp(to_target * speed, 0.8 * delta)
	elif dist < 200.0:
		velocity = velocity.lerp(-to_target * speed * 0.5, 0.8 * delta)
	else:
		var perp: Vector2 = Vector2(-to_target.y, to_target.x).normalized()
		var strafe_dir: Vector2 = perp * _dodge_direction
		velocity = velocity.lerp(strafe_dir * speed * 0.6, 0.8 * delta)

var _dodge_frame_skip: int = 0

func _handle_dodge(delta: float) -> void:
	_dodge_timer -= delta
	if _dodge_timer <= 0:
		_dodge_direction *= -1.0
		_dodge_timer = randf_range(1.0, 2.5)
	_dodge_frame_skip += 1
	if _dodge_frame_skip % 6 == 0:
		dodge_nearby_bullets()

func dodge_nearby_bullets() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var bullets := get_tree().get_nodes_in_group("player_bullets")
	var dodge_force: Vector2 = Vector2.ZERO
	for bullet in bullets:
		if not bullet.is_inside_tree():
			continue
		var to_bullet: Vector2 = global_position.direction_to(bullet.global_position)
		var dist: float = global_position.distance_to(bullet.global_position)
		if dist < DODGE_RANGE:
			var intensity: float = 1.0 - dist / DODGE_RANGE
			var dodge_dir: Vector2 = Vector2(-to_bullet.y, to_bullet.x).normalized()
			dodge_force += dodge_dir * intensity * 300.0
	if dodge_force != Vector2.ZERO:
		velocity += dodge_force * get_process_delta_time()

func _handle_attacks(delta: float) -> void:
	if _shoot_timer <= 0.0 and _target and is_instance_valid(_target):
		_shoot_timer = _get_fire_rate()
		_pattern_timer = 0.0
		_attack_pattern = randi() % 5
		match _attack_pattern:
			0: _attack_spread()
			1: _attack_targeted_burst()
			2: _attack_ring()
			3: _attack_laser_sweep()
			4: _attack_summon_minions()

func _get_fire_rate() -> float:
	var base: float = 1.5 if not _angry_mode else 0.8
	return base + randf_range(-0.2, 0.3)

func _attack_spread() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var angle: float = global_position.angle_to_point(_target.global_position)
	var count: int = 7 if not _angry_mode else 11
	var spread_angle: float = deg_to_rad(45.0) if not _angry_mode else deg_to_rad(70.0)
	var start_a: float = angle - spread_angle * 0.5
	var step: float = spread_angle / max(count - 1, 1)
	for i in range(count):
		var a: float = start_a + step * i
		var bullet := Pool.acquire("bullet", _bullet_scene)
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 28, a, 0.5, false)
	SFX.play_enemy_death()

func _attack_targeted_burst() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var burst_count: int = 6 if not _angry_mode else 10
	for i in range(burst_count):
		var angle: float = global_position.angle_to_point(_target.global_position)
		var spread_offset: float = deg_to_rad(randf_range(-8.0, 8.0))
		var a: float = angle + spread_offset
		var bullet := Pool.acquire("bullet", _bullet_scene)
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 28, a, 0.25, false)
	SFX.play_shoot()

func _attack_ring() -> void:
	var count: int = 12 if not _angry_mode else 18
	var rings: int = 2 if _angry_mode else 1
	for ring in range(rings):
		var offset: float = float(ring) * TAU / float(count) / 2.0
		for i in range(count):
			var a: float = float(i) * TAU / float(count) + offset
			var bullet := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(bullet)
			bullet.setup(global_position + Vector2.from_angle(a) * 28, a, 0.25, false)
	SFX.play_explosion()

func _attack_laser_sweep() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var count: int = 12 if not _angry_mode else 18
	var spread: float = deg_to_rad(120.0) if not _angry_mode else deg_to_rad(180.0)
	var angle: float = global_position.angle_to_point(_target.global_position) - spread * 0.5
	var step: float = spread / float(count)
	for i in range(count):
		var a: float = angle + step * i
		var bullet := Pool.acquire("bullet", _bullet_scene)
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + Vector2.from_angle(a) * 32, a, 0.5, false)

func _attack_summon_minions() -> void:
	var count: int = 2 if not _angry_mode else 4
	for i in range(count):
		var enemy := _enemy_scene.instantiate()
		enemy.position = global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		enemy.enemy_type = randi() % 3
		enemy.health = 3
		enemy.move_speed = 50.0
		enemy.shoot_cooldown = 1.5
		enemy.drop_chance = 0.0
		if _target and is_instance_valid(_target):
			enemy.set_target(_target)
		enemy.enemy_died.connect(_on_minion_died)
		get_tree().current_scene.add_child(enemy)

func _on_minion_died() -> void:
	pass

func _update_angry_mode() -> void:
	_angry_mode = _health <= _max_health * 0.5 and _shield <= 0

func _update_shield(delta: float) -> void:
	if _dead:
		return
	if _shield <= 0 and _health > 0:
		_shield_regen_timer -= delta
		if _shield_regen_timer <= 0:
			_shield = min(_shield + 5, _max_shield)
			_shield_regen_timer = SHIELD_REGEN_TIME
		# shield visible via circle
			var tween := create_tween()
			tween.tween_callback(func(): if _shield_circle: _shield_circle.set_color(Color(1.0, 0.7, 0.15, 0.5)))
	if _shield > 0:
		# shield visible via circle
		var alpha: float = 0.25 + 0.25 * abs(sin(Time.get_ticks_msec() * 0.003))
		var shield_ratio: float = float(_shield) / float(_max_shield)
		var intensity: float = 0.4 + (1.0 - shield_ratio) * 0.5
		if _shield_circle: _shield_circle.set_color(Color(0.8 + intensity * 0.2, 0.5 + intensity * 0.3, 0.1, alpha))

	else:
		_shield_sprite.visible = false

func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	if _shield > 0:
		_shield -= amount
		_spawn_shield_hit_effect()
		if _shield_circle: _shield_circle.set_color(Color(1.0, 0.9, 0.5, 0.9))
		var tween := create_tween()
		tween.tween_callback(func(): if _shield_circle: _shield_circle.set_color(Color(0.8, 0.5, 0.1, 0.5)))
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
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
	hit.start()

func _shield_break_effect() -> void:
	SFX.play_explosion()
	for i in range(6):
		var exp = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	_shield_regen_timer = SHIELD_REGEN_TIME
	if _shield_circle:
		_shield_circle.set_color(Color(0, 0, 0, 0))

func _update_health_bar() -> void:
	if _health_bar:
		_health_bar.max_value = _max_health
		_health_bar.value = _health

func _die() -> void:
	_dead = true
	elite_died.emit()
	GameState.add_kill()
	GameState.add_score(1000 * GameState.level)
	call_deferred("_spawn_explosion")
	call_deferred("_spawn_rewards")
	queue_free()

func _spawn_explosion() -> void:
	for i in range(4):
		var exp = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40))
	SFX.play_explosion()

func _spawn_rewards() -> void:
	for type in ["heal", "bomb", "spread", "speed", "heal", "power"]:
		var pu = _powerup_scene.instantiate()
		get_tree().current_scene.add_child(pu)
		pu.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		pu.setup(type)

func _screen_clamp() -> void:
	var screen := get_viewport_rect().size
	var margin: float = 60.0
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
