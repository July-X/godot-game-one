extends CharacterBody2D

signal enemy_died

@export var enemy_type: int = 0
@export var health: int = 2
@export var move_speed: float = 60.0
@export var shoot_cooldown: float = 2.0
@export var drop_chance: float = 0.20

var entity_id: int = 0

func get_entity_id() -> int:
	return entity_id
var _is_network_ghost: bool = false
var _shoot_timer: float = 0.0
var _target: Node2D = null
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")
var _move_angle: float = 0.0
var _wobble_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("enemies")
	if _sprite:
		_sprite.texture = SpriteFactory.create_enemy_sprite(enemy_type)
	if _health_bar:
		_health_bar.max_value = health
		_health_bar.value = health
	_move_angle = randf() * TAU
	_wobble_timer = randf() * TAU
	_shoot_timer = randf_range(0.5, shoot_cooldown)

func set_target(target: Node2D) -> void:
	_target = target

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return
	## 多人模式：客户端幽灵敌人只接受位置同步，不执行本地 AI/开火。
	if _is_network_ghost:
		if _health_bar:
			_health_bar.value = health
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
		var cd: float = shoot_cooldown
		if enemy_type == 0:
			cd *= 2.0
		_shoot_timer = cd + randf_range(-0.3, 0.3)

	## 更新血条
	if _health_bar:
		_health_bar.value = health

func _move_chase(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		var wobble: float = sin(_wobble_timer) * 0.3
		var drift := Vector2(-to_target.y, to_target.x) * wobble
		velocity = velocity.lerp((to_target + drift).normalized() * move_speed, 3.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 50.0 * delta)

func _move_zigzag(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		var perp: Vector2 = Vector2(-to_target.y, to_target.x)
		var wobble: float = sin(_wobble_timer) * 0.6
		var dir: Vector2 = (to_target + perp * wobble).normalized()
		velocity = velocity.lerp(dir * move_speed, 3.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 50.0 * delta)

func _move_orbit(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = global_position.direction_to(_target.global_position)
		var perp: Vector2 = Vector2(-to_target.y, to_target.x)
		var dist: float = global_position.distance_to(_target.global_position)
		var target_dist: float = 200.0
		var radial: float = (dist - target_dist) / target_dist
		var dir: Vector2 = (perp.normalized() * 0.8 + to_target.normalized() * -radial * 0.3).normalized()
		velocity = velocity.lerp(dir * move_speed, 3.0 * delta)
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

func _spawn_enemy_bullet(pos: Vector2, angle: float, damage: float, speed: float, color: Color) -> void:
	var bullet := Pool.acquire("bullet", _bullet_scene)
	get_tree().current_scene.add_child(bullet)
	bullet.setup(pos, angle, damage, false, 1, speed)
	bullet.modulate = color
	if NetworkManager.is_online():
		var scene := get_tree().current_scene
		if scene and scene.has_method("register_bullet_spawn"):
			scene.register_bullet_spawn(pos, angle, damage, false, 1, speed, color)

func _shoot_single(angle: float) -> void:
	var dmg: float = 1.0
	_spawn_enemy_bullet(global_position + Vector2.from_angle(angle) * 20, angle, dmg, 780.0, Color(1.0, 0.4, 0.3, 1.0))

func _shoot_spread(angle: float) -> void:
	for i in range(-1, 2):
		var a: float = angle + i * 0.2
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, 0.5, 780.0, Color(0.3, 1.0, 0.4, 1.0))

func _shoot_circle() -> void:
	for i in range(6):
		var a: float = float(i) * TAU / 6.0
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, 0.3, 780.0, Color(0.6, 0.3, 1.0, 1.0))

func take_damage(amount: int = 1, killer_peer_id: int = -1) -> void:
	health -= amount
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.08)
	if health <= 0:
		die(killer_peer_id)

func die(killer_peer_id: int = -1) -> void:
	GameState.add_kill(killer_peer_id)
	enemy_died.emit()
	## 延迟生成特效和道具，避免物理查询冲突
	call_deferred("_spawn_explosion")
	call_deferred("_try_spawn_powerup")
	queue_free()

func _spawn_explosion() -> void:
	## 击杀反馈：轻震屏。杂兵死亡极其频繁，强度必须压得很低，
	## 否则连续击杀时画面一直在抖，反而读不清弹幕。
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("add_shake"):
		scene.add_shake(scene.SHAKE_ENEMY_DEATH)
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_enemy_death()

func _try_spawn_powerup() -> void:
	if randf() < drop_chance:
		var pu = _powerup_scene.instantiate()
		get_tree().current_scene.add_child(pu)
		pu.global_position = global_position
		var types: Array[String] = ["spread", "speed", "power", "heal", "bomb"]
		var picked_type: String = types[randi() % types.size()]
		pu.setup(picked_type)
		if NetworkManager.is_online() and multiplayer.is_server():
			var scene := get_tree().current_scene
			if scene and scene.has_method("register_powerup_entity"):
				scene.register_powerup_entity(pu, picked_type)
