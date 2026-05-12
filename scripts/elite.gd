extends CharacterBody2D

signal elite_died
signal shield_broken_window_started

const MAX_SHIELD: int = 80
const DODGE_RANGE: float = 280.0
const ELITE_CLOSE_ESCAPE_DIST: float = 165.0
const ELITE_CLOSE_ESCAPE_COOLDOWN: float = 0.9
const ELITE_CLOSE_ESCAPE_PUSH: float = 260.0
const ELITE_CLOSE_ESCAPE_STRAFE: float = 170.0
var BASE_SPEED: float = 50.0
var CHASE_SPEED: float = 65.0
const SHIELD_REGEN_TIME: float = 3.0
const PHASE_B_EXPOSE_DURATION: float = 4.0

var _health: int = 50
var _max_health: int = 50
var _shield: int = MAX_SHIELD
var _max_shield: int = MAX_SHIELD
var _target: Node2D = null
var _shoot_timer: float = 0.0
var entity_id: int = 0

func get_entity_id() -> int:
	return entity_id

func get_network_health() -> float:
	return float(_health)

func get_network_max_health() -> float:
	return float(_max_health)

func get_network_shield() -> float:
	return float(_shield)

func get_network_max_shield() -> float:
	return float(_max_shield)

func apply_network_health(hp: float, max_hp: float) -> void:
	_max_health = max(int(max_hp), 1)
	_health = clampi(int(hp), 0, _max_health)
	_update_health_bar()

func apply_network_shield(shield: float, max_shield: float) -> void:
	var was_shielded := _shield > 0
	_max_shield = max(int(max_shield), 1)
	_shield = clampi(int(shield), 0, _max_shield)
	if _shield > 0:
		_shield_break_visual_played = false
	if _is_network_ghost and was_shielded and _shield <= 0:
		_play_shield_break_visual()
		shield_broken_window_started.emit()
	_update_shield_visual_color(0.45)
	_update_shield_bar()

var _is_network_ghost: bool = false
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
var _close_escape_cooldown: float = 0.0
var _phase_b_timer: float = 0.0
var _phase_c_drone_timer: float = 1.6
var _shield_break_visual_played: bool = false

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _shield_shatter_scene = preload("res://scripts/shield_shatter_burst.gd")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shield_sprite: Sprite2D = $ShieldSprite
var _shield_circle: Node2D = null
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _shield_bar: ProgressBar = $ShieldBar
@onready var _turret_l: Node2D = $TurretL
@onready var _turret_r: Node2D = $TurretR

func _ready() -> void:
	add_to_group("enemies")
	_sprite.texture = SpriteFactory.create_elite_sprite()
	_hide_square_shield_sprite()
	_shield_circle = Node2D.new()
	_shield_circle.set_script(preload("res://scripts/shield_circle.gd"))
	_shield_circle.z_index = 3
	_shield_circle.position = Vector2(0, 0)
	add_child(_shield_circle)
	_shield_circle.setup(80.0, Color(1.0, 0.7, 0.15, 0.5))
	_shoot_timer = randf_range(0.5, 1.5)
	_dodge_direction = 1.0 if randf() > 0.5 else -1.0
	_update_health_bar()
	_update_shield_bar()

func set_target(target: Node2D) -> void:
	_target = target

func set_difficulty(mult: float) -> void:
	var total_hp := GameState.get_max_health(1)
	if NetworkManager.is_online():
		for pid in NetworkManager.connected_peers:
			total_hp += GameState.get_max_health(pid)
	_health = int(total_hp * 2.5 * mult)
	_max_health = _health
	_shield = int(total_hp * 1.0 * mult)
	_max_shield = _shield
	_shield_break_visual_played = false
	BASE_SPEED = 50.0 * mult
	CHASE_SPEED = 65.0 * mult

func _physics_process(delta: float) -> void:
	if not GameState.game_running or _dead:
		return
	if _is_network_ghost:
		_update_health_bar()
		_update_shield_bar()
		return

	_handle_movement(delta)
	_handle_dodge(delta)
	_apply_close_range_escape(delta)
	_update_phase_timers(delta)
	_handle_attacks(delta)
	_update_shield(delta)
	_update_angry_mode()
	_update_health_bar()
	_shoot_timer -= delta
	_close_escape_cooldown = max(_close_escape_cooldown - delta, 0.0)
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
	if _phase_b_timer > 0.0:
		speed *= 0.65

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

func _apply_close_range_escape(delta: float) -> void:
	if _close_escape_cooldown > 0.0:
		return
	if not _target or not is_instance_valid(_target):
		return
	var dist: float = global_position.distance_to(_target.global_position)
	if dist > ELITE_CLOSE_ESCAPE_DIST:
		return
	var to_target: Vector2 = global_position.direction_to(_target.global_position)
	var away: Vector2 = -to_target
	var side: Vector2 = Vector2(-to_target.y, to_target.x) * _dodge_direction
	var escape_vel: Vector2 = away * ELITE_CLOSE_ESCAPE_PUSH + side * ELITE_CLOSE_ESCAPE_STRAFE
	velocity += escape_vel * delta
	_close_escape_cooldown = ELITE_CLOSE_ESCAPE_COOLDOWN
	_dodge_direction *= -1.0

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
		if _shield > 0:
			_shoot_timer = 2.2
			_attack_narrow_fan()
			return
		var hp_ratio: float = float(_health) / max(float(_max_health), 1.0)
		if _phase_b_timer > 0.0:
			_shoot_timer = 1.8
			_attack_targeted_burst()
			return
		if hp_ratio > 0.35:
			_shoot_timer = 3.0
			_attack_ring()
		else:
			_shoot_timer = 1.4
			_attack_triple_predictive()

func _get_fire_rate() -> float:
	var base: float = 1.5 if not _angry_mode else 0.8
	return base + randf_range(-0.2, 0.3)

func _spawn_enemy_bullet(pos: Vector2, angle: float, damage: float, speed: float = 600.0, color: Color = Color(1, 1, 1, 1)) -> void:
	var bullet := Pool.acquire("bullet", _bullet_scene)
	get_tree().current_scene.add_child(bullet)
	bullet.setup(pos, angle, damage, false, 1, speed)
	bullet.modulate = color
	if NetworkManager.is_online():
		var scene := get_tree().current_scene
		if scene and scene.has_method("register_bullet_spawn"):
			scene.register_bullet_spawn(pos, angle, damage, false, 1, speed, color)

func _attack_narrow_fan() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var angle: float = global_position.angle_to_point(_target.global_position)
	var count: int = 5
	var spread_angle: float = deg_to_rad(22.0)
	var start_a: float = angle - spread_angle * 0.5
	var step: float = spread_angle / max(count - 1, 1)
	for i in range(count):
		var a: float = start_a + step * i
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 28, a, 2.0, 520.0, Color(1.0, 0.42, 0.2, 1.0))
	SFX.play_enemy_death()

func _attack_targeted_burst() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var burst_count: int = 3
	for i in range(burst_count):
		var angle: float = global_position.angle_to_point(_target.global_position)
		var spread_offset: float = deg_to_rad(randf_range(-4.0, 4.0))
		var a: float = angle + spread_offset
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 28, a, 3.0, 620.0, Color(1.0, 0.18, 0.15, 1.0))
	SFX.play_shoot()

func _attack_ring() -> void:
	var count: int = 14
	for i in range(count):
		if i % 7 == 0:
			continue
		var a: float = float(i) * TAU / float(count)
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 28, a, 1.0, 380.0, Color(1.0, 0.62, 0.35, 0.95))
	SFX.play_explosion()

func _attack_triple_predictive() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var target_vel := Vector2.ZERO
	var maybe_velocity: Variant = _target.get("velocity")
	if typeof(maybe_velocity) == TYPE_VECTOR2:
		target_vel = maybe_velocity
	var lead_target: Vector2 = _target.global_position + target_vel * 0.35
	var base: float = global_position.angle_to_point(lead_target)
	for i in range(3):
		var offset := (i - 1) * 0.08
		var a: float = base + offset
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 30, a, 3.0, 620.0, Color(1.0, 0.1, 0.12, 1.0))

func _attack_summon_minions() -> void:
	var count: int = 2
	for i in range(count):
		var enemy := _enemy_scene.instantiate()
		enemy.position = global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		enemy.enemy_type = randi() % 3
		enemy.health = 2
		enemy.move_speed = 50.0
		enemy.shoot_cooldown = 1.8
		enemy.drop_chance = 0.0
		if _target and is_instance_valid(_target):
			enemy.set_target(_target)
		enemy.enemy_died.connect(_on_minion_died)
		get_tree().current_scene.add_child(enemy)

func _on_minion_died() -> void:
	pass

func _update_angry_mode() -> void:
	_angry_mode = _health <= _max_health * 0.35 and _shield <= 0

func _update_phase_timers(delta: float) -> void:
	if _phase_b_timer > 0.0:
		_phase_b_timer = max(_phase_b_timer - delta, 0.0)
	var hp_ratio: float = float(_health) / max(float(_max_health), 1.0)
	if _shield <= 0 and hp_ratio <= 0.7 and hp_ratio > 0.35:
		_phase_c_drone_timer -= delta
		if _phase_c_drone_timer <= 0.0:
			_phase_c_drone_timer = 6.0
			_attack_summon_minions()

func _update_shield(delta: float) -> void:
	if _dead:
		return
	if _shield <= 0 and _health > 0:
		_shield_regen_timer -= delta
		if _shield_regen_timer <= 0:
			_shield_regen_timer = SHIELD_REGEN_TIME
	if _shield > 0:
		var alpha: float = 0.25 + 0.25 * abs(sin(Time.get_ticks_msec() * 0.003))
		_update_shield_visual_color(alpha)
		_update_shield_bar()
	else:
		_hide_square_shield_sprite()
		_update_shield_bar()

func take_damage(amount: int = 1, killer_peer_id: int = -1) -> void:
	if _dead:
		return
	if _shield > 0:
		_shield -= amount
		_spawn_shield_hit_effect()
		if _shield_circle: _shield_circle.set_color(Color(1.0, 0.9, 0.5, 0.9))
		_flash_shield_bar()
		_update_shield_bar()
		var tween := create_tween()
		tween.tween_callback(func(): if _shield_circle: _shield_circle.set_color(Color(0.8, 0.5, 0.1, 0.5)))
		if _shield <= 0:
			_shield_break_effect()
			_phase_b_timer = PHASE_B_EXPOSE_DURATION
			shield_broken_window_started.emit()
		return
	var applied_damage: int = amount
	if _phase_b_timer > 0.0:
		applied_damage = int(ceil(float(amount) * 1.25))
	_health -= applied_damage
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.08)
	if _health <= 0:
		_die(killer_peer_id)

func _spawn_shield_hit_effect() -> void:
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
	hit.start()

func _shield_break_effect() -> void:
	SFX.play_explosion()
	_play_shield_break_visual()
	for i in range(6):
		var exp = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	_shield_regen_timer = SHIELD_REGEN_TIME
	if _shield_circle:
		_shield_circle.set_color(Color(0, 0, 0, 0))
	_update_shield_bar()

func force_network_shield_destroyed() -> void:
	_shield = 0
	_play_shield_break_visual()
	_update_shield_visual_color(0.0)
	_update_shield_bar()

func _play_shield_break_visual() -> void:
	if _shield_break_visual_played:
		return
	_shield_break_visual_played = true
	_spawn_shield_shatter_burst()

func _spawn_shield_shatter_burst() -> void:
	_destroy_shield_circle()
	var burst := Node2D.new()
	burst.set_script(_shield_shatter_scene)
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position
	burst.z_index = 8
	if burst.has_method("setup"):
		burst.setup(78.0, Color(1.0, 0.72, 0.18, 0.95), 22)

func _destroy_shield_circle() -> void:
	if _shield_circle and is_instance_valid(_shield_circle):
		_shield_circle.queue_free()
	_shield_circle = null

func _update_health_bar() -> void:
	if _health_bar:
		_health_bar.max_value = _max_health
		_health_bar.value = _health

func _hide_square_shield_sprite() -> void:
	## 旧 ShieldSprite 使用方形渐变纹理，在 Android 双屏测试里会露出外框。
	## 精英盾只保留 shield_circle.gd 绘制的圆形光晕。
	if _shield_sprite:
		_shield_sprite.visible = false

func _update_shield_visual_color(alpha: float) -> void:
	_hide_square_shield_sprite()
	if _shield_circle == null:
		return
	if _shield <= 0:
		_shield_circle.visible = false
		return
	_shield_circle.visible = true
	var shield_ratio: float = float(_shield) / max(float(_max_shield), 1.0)
	var intensity: float = 0.4 + (1.0 - shield_ratio) * 0.5
	_shield_circle.set_color(Color(0.8 + intensity * 0.2, 0.5 + intensity * 0.3, 0.1, alpha))

func _update_shield_bar() -> void:
	_hide_square_shield_sprite()
	if _shield_circle:
		_shield_circle.visible = _shield > 0
	if _shield_bar == null:
		return
	_shield_bar.max_value = _max_shield
	_shield_bar.value = _shield
	_shield_bar.visible = _shield > 0
	if _shield > 0:
		var ratio: float = float(_shield) / max(float(_max_shield), 1.0)
		_shield_bar.modulate = Color(1.0, 0.78 + ratio * 0.22, 0.2 + ratio * 0.08, 1.0)
	else:
		_shield_bar.modulate = Color(1, 1, 1, 0.0)

func _flash_shield_bar() -> void:
	if _shield_bar == null or _shield <= 0:
		return
	_shield_bar.modulate = Color(1.4, 1.1, 0.5, 1.0)
	var tween := create_tween()
	tween.tween_property(_shield_bar, "modulate", Color(1.0, 0.85, 0.3, 1.0), 0.08)
	tween.tween_property(_shield_bar, "modulate", Color(1.0, 0.78 + (float(_shield) / max(float(_max_shield), 1.0)) * 0.22, 0.2 + (float(_shield) / max(float(_max_shield), 1.0)) * 0.08, 1.0), 0.16)

func _die(killer_peer_id: int = -1) -> void:
	_dead = true
	elite_died.emit()
	GameState.add_kill(killer_peer_id)
	GameState.add_score(1000 * GameState.level, killer_peer_id)
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
	var types: Array[String] = ["heal", "bomb", "spread", "speed", "heal", "power", "heal", "power", "speed", "spread", "heal", "bomb"]
	var alive_ids: Array[int] = []
	if NetworkManager.is_online() and multiplayer.is_server():
		alive_ids = GameState.get_alive_player_ids()
	var assign_idx: int = 0
	for i in range(types.size()):
		var type: String = types[i]
		var pu = _powerup_scene.instantiate()
		get_tree().current_scene.add_child(pu)
		var step: float = PI / max(float(types.size() - 1), 1.0)
		var angle: float = -PI * 0.85 + step * float(i)
		var offset := Vector2(cos(angle), sin(angle)) * randf_range(26.0, 58.0)
		pu.global_position = global_position + offset
		pu.setup(type)
		if alive_ids.size() > 0:
			var assigned_peer_id: int = alive_ids[assign_idx % alive_ids.size()]
			pu.set_meta("assigned_peer_id", assigned_peer_id)
			assign_idx += 1
		if NetworkManager.is_online() and multiplayer.is_server():
			var scene := get_tree().current_scene
			if scene and scene.has_method("register_powerup_entity"):
				scene.register_powerup_entity(pu, type)

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
