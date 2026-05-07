extends CharacterBody2D

signal died

@export var move_speed: float = 260.0
@export var friction: float = 500.0
@export var mouse_sensitivity: float = 0.008

var _shoot_timer: float = 0.0
var _invincible_timer: float = 0.0
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _missile_scene = preload("res://scenes/entities/homing_missile.tscn")
var _laser_scene = preload("res://scenes/entities/laser_bolt.tscn")
var ShieldRing = preload("res://scripts/shield_ring.gd")
var _mouse_vel: Vector2 = Vector2.ZERO
var _walk_cycle: float = 0.0
var _head_bob_timer: float = 0.0
var _missile_timer: float = 0.0
var _missile_pods: Array[Node2D] = []
var _missile_pod_built: int = 0
var _pickup_radius: float = 280.0
var _mobile_mode: bool = false
var _touch_move: Vector2 = Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _muzzle_flash: Sprite2D = $MuzzleFlash
@onready var _pickup_area: Area2D = $PickupArea
@onready var _engine_glow: Sprite2D = $EngineGlow
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _shield_container: Node2D = $ShieldContainer

func _ready() -> void:
	add_to_group("player")
	_muzzle_flash.visible = false
	_update_appearance()
	_update_pickup_radius()
	if _pickup_area:
		_pickup_area.body_entered.connect(_on_pickup_body_entered)
	GameState.shield_changed.connect(_on_shield_changed)
	if OS.has_feature("android") or OS.has_feature("ios"):
		_mobile_mode = true
		var mc = get_tree().current_scene.find_child("MobileControls", true, false)
		if mc:
			mc.move_input.connect(_on_mobile_move)

func _update_appearance() -> void:
	var level: int = GameState.shoot_level
	if _sprite:
		_sprite.texture = SpriteFactory.create_player_sprite(level)
	if _engine_glow:
		var glow_intensity: float = 1.0 + level * 0.3
		_engine_glow.modulate = Color(1.0, 0.6, 0.2, 0.6 * glow_intensity)
		_engine_glow.scale = Vector2(1.0 + level * 0.15, 1.0 + level * 0.15)

func _update_pickup_radius() -> void:
	## 拾取范围 = 3倍飞机模型大小（飞机约64宽，3倍=192，取280留余量）
	_pickup_radius = 280.0
	if _pickup_area and _pickup_area.get_child_count() > 0:
		_pickup_area.get_child(0).shape.radius = _pickup_radius

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and GameState.game_running and not _mobile_mode:
		_mouse_vel += event.relative * mouse_sensitivity * move_speed

func _on_mobile_move(vec: Vector2) -> void:
	_touch_move = vec

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return

	_shoot_timer -= delta
	_invincible_timer = max(_invincible_timer - delta, 0.0)
	GameState.tick_skill_cooldown(delta)
	GameState.tick_laser_cooldown(delta)

	if not _mobile_mode:
		_mouse_vel = _mouse_vel.lerp(Vector2.ZERO, 1.5 * delta)

	var screen_size := get_viewport_rect().size

	if _mobile_mode:
		if _touch_move.length() > 0.1:
			velocity = _touch_move * move_speed
			rotation = _touch_move.angle() + PI * 0.5
		else:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		velocity = _mouse_vel.limit_length(move_speed)
		if velocity.length() > 10.0:
			rotation = velocity.angle() + PI * 0.5

	move_and_slide()

	var margin: float = 24.0
	if global_position.x < margin:
		global_position.x = margin
		velocity.x = abs(velocity.x) * 0.5
	elif global_position.x > screen_size.x - margin:
		global_position.x = screen_size.x - margin
		velocity.x = -abs(velocity.x) * 0.5
	if global_position.y < margin:
		global_position.y = margin
		velocity.y = abs(velocity.y) * 0.5
	elif global_position.y > screen_size.y - margin:
		global_position.y = screen_size.y - margin
		velocity.y = -abs(velocity.y) * 0.5

	if _shoot_timer <= 0.0:
		_shoot()

	## 技能
	if not _mobile_mode and Input.is_key_pressed(KEY_SPACE):
		if GameState.use_skill():
			_fire_ring_shotgun()
	if not _mobile_mode and Input.is_key_pressed(KEY_Q):
		if GameState.use_laser():
			_fire_laser()

	## 追踪导弹
	_spawn_homing_missiles(delta)

	## 自动拾取
	_try_pickup_nearby()

	## 行走动画
	if velocity.length() > 10.0:
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

	## 更新血条
	if _health_bar:
		_health_bar.max_value = GameState.max_health
		_health_bar.value = GameState.current_health
		var ratio: float = float(GameState.current_health) / float(GameState.max_health)
		var bar_color: Color
		if ratio > 0.6:
			bar_color = Color(0.25, 0.85, 0.35, 1.0)
		elif ratio > 0.3:
			bar_color = Color(0.9, 0.8, 0.15, 1.0)
		else:
			bar_color = Color(0.9, 0.2, 0.15, 1.0)
		_health_bar.add_theme_stylebox_override("fill", _make_fill_style(bar_color))

func _update_walk_animation() -> void:
	var swing: float = sin(_walk_cycle) * 0.02
	var bounce: float = abs(sin(_walk_cycle)) * 0.01
	_sprite.rotation = swing
	if _engine_glow:
		_engine_glow.position.y = 32.0 + bounce * 20.0

func _reset_pose() -> void:
	_sprite.rotation = 0.0
	if _engine_glow:
		_engine_glow.position.y = 32.0

func _shoot() -> void:
	_shoot_timer = GameState.get_shoot_cooldown()
	SFX.play_shoot()

	var base_angle: float = rotation - PI * 0.5
	var bullet_count: int = GameState.get_bullet_count()
	var level: int = GameState.shoot_level
	var damage: int = GameState.get_bullet_damage()

	var engine_offset: Vector2 = Vector2.from_angle(base_angle) * 24
	var perp: Vector2 = Vector2(-sin(base_angle), cos(base_angle))

	if level >= 12:
		var spread_angles: Array[float] = [-0.3, -0.15, 0.0, 0.15, 0.3]
		for i in range(bullet_count):
			var a: float = base_angle + spread_angles[i % spread_angles.size()] * (0.5 + (level - 12) * 0.1)
			var spread_offset: float = (i - bullet_count / 2.0) * 18.0
			var offset: Vector2 = perp * spread_offset
			var bullet := _bullet_scene.instantiate()
			get_tree().current_scene.add_child(bullet)
			bullet.setup(global_position + engine_offset + offset, a, damage, true, level, 660.0)
	elif level >= 8:
		var max_spread: float = 16.0 + level
		var positions: Array[float] = []
		for i in range(bullet_count):
			positions.append(-max_spread + i * (max_spread * 2.0 / max(bullet_count - 1, 1)))
		for i in bullet_count:
			var a: float = base_angle + positions[i] * 0.008
			var offset: Vector2 = perp * positions[i]
			var bullet := _bullet_scene.instantiate()
			get_tree().current_scene.add_child(bullet)
			bullet.setup(global_position + engine_offset + offset, a, damage, true, level, 660.0)
	elif level >= 4:
		var max_spread: float = 12.0 + level * 3.0
		var positions: Array[float] = []
		for i in range(bullet_count):
			positions.append(-max_spread + i * (max_spread * 2.0 / max(bullet_count - 1, 1)))
		for i in bullet_count:
			var offset: Vector2 = perp * positions[i]
			var bullet := _bullet_scene.instantiate()
			get_tree().current_scene.add_child(bullet)
			bullet.setup(global_position + engine_offset + offset, base_angle, damage, true, level, 660.0)
	else:
		var max_spread: float = 10.0 + level * 2.0
		var positions: Array[float] = []
		for i in range(bullet_count):
			positions.append(-max_spread + i * (max_spread * 2.0 / max(bullet_count - 1, 1)))
		for i in bullet_count:
			var offset: Vector2 = perp * positions[i]
			var bullet := _bullet_scene.instantiate()
			get_tree().current_scene.add_child(bullet)
			bullet.setup(global_position + engine_offset + offset, base_angle, damage, true, level, 660.0)

	if _muzzle_flash:
		_muzzle_flash.visible = true
		var tween := create_tween()
		tween.tween_property(_muzzle_flash, "modulate:a", 0.0, 0.06)
		tween.tween_callback(func(): _muzzle_flash.visible = false)

func _fire_ring_shotgun() -> void:
	var count: int = 16
	var base_angle: float
	if _mobile_mode:
		base_angle = rotation - PI * 0.5
	else:
		var mouse_pos := get_global_mouse_position()
		base_angle = global_position.angle_to_point(mouse_pos)
	var perp: Vector2 = Vector2(-sin(base_angle), cos(base_angle))
	var engine_offset: Vector2 = Vector2.from_angle(base_angle) * 24
	var damage: int = GameState.get_bullet_damage() + 2
	for i in range(count):
		var a: float = base_angle + i * TAU / count
		var offset: Vector2 = perp * 8.0 + Vector2(cos(a), sin(a)) * 4.0
		var bullet := _bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(global_position + engine_offset + offset, a, damage, true, 5, 500.0)

var _pickup_frame_skip: int = 0

func _try_pickup_nearby() -> void:
	_pickup_frame_skip += 1
	if _pickup_frame_skip % 4 != 0:
		return
	var powerups := get_tree().get_nodes_in_group("powerups")
	for pu in powerups:
		if pu.is_inside_tree() and global_position.distance_to(pu.global_position) < _pickup_radius:
			if pu.has_method("collect"):
				pu.collect()

func _get_missile_tier() -> int:
	var level: int = GameState.shoot_level
	return mini(level / 5, 5)

func _get_missile_damage() -> int:
	var tier: int = _get_missile_tier()
	var dmg: int = (GameState.get_bullet_damage() + 2) * int(pow(1.5, tier - 1))
	return dmg

func _get_missile_interval() -> float:
	var tier: int = _get_missile_tier()
	return 1.5 / tier

func _build_missile_pods() -> void:
	var tier: int = _get_missile_tier()
	if tier <= _missile_pod_built:
		return
	while _missile_pods.size() > 0:
		var p: Node2D = _missile_pods.pop_back()
		p.queue_free()
	_missile_pod_built = tier
	for i in range(tier):
		var pod := Sprite2D.new()
		pod.texture = _make_pod_texture(Color(0.9, 0.3, 0.15))
		pod.scale = Vector2(0.5, 0.5)
		pod.z_index = 2
		add_child(pod)
		_missile_pods.append(pod)

func _make_pod_texture(col: Color) -> ImageTexture:
	var size: int = 10
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = size / 2
	var cy: int = size / 2
	for y in range(size):
		for x in range(size):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var d: float = sqrt(dx * dx + dy * dy)
			if d < cx - 1:
				img.set_pixel(x, y, col)
				if d > cx - 3:
					img.set_pixel(x, y, col.lightened(0.3))
	var tex := ImageTexture.create_from_image(img)
	return tex

func _update_missile_pods() -> void:
	var tier: int = _get_missile_tier()
	if tier != _missile_pod_built:
		_build_missile_pods()
	var rear: Vector2 = Vector2.RIGHT.rotated(rotation + PI) * 48
	var perp: Vector2 = Vector2.UP.rotated(rotation)
	var spacing: float = 18.0
	var start: float = -(tier - 1) * spacing * 0.5
	for i in range(tier):
		if i < _missile_pods.size():
			_missile_pods[i].global_position = global_position + rear + perp * (start + i * spacing)
			_missile_pods[i].rotation = rotation + PI

func _spawn_homing_missiles(delta: float) -> void:
	var tier: int = _get_missile_tier()
	if tier <= 0:
		return
	_update_missile_pods()
	_missile_timer += delta
	if _missile_timer < _get_missile_interval():
		return
	_missile_timer = 0.0
	for i in range(tier):
		if i < _missile_pods.size():
			var pos: Vector2 = _missile_pods[i].global_position
			var angle: float = rotation + PI + (i - (tier - 1) * 0.5) * 0.15
			var missile := _missile_scene.instantiate()
			get_tree().current_scene.add_child(missile)
			missile.setup(pos, angle, _get_missile_damage())

func _fire_laser() -> void:
	var count: int = 3
	for i in range(count):
		var angle: float = rotation - PI * 0.5 + (i - 1) * 0.15
		var pos: Vector2 = global_position + Vector2.from_angle(angle) * 28
		var bolt := _laser_scene.instantiate()
		get_tree().current_scene.add_child(bolt)
		bolt.setup(pos, angle, GameState.get_laser_damage())
	SFX.play_shoot()

func _on_pickup_body_entered(body: Node2D) -> void:
	if body.is_in_group("powerups") and body.has_method("collect"):
		body.collect()

var _shield_dirty: bool = false

func _on_shield_changed(layers: int) -> void:
	_pending_shield_layers = layers
	if not _shield_dirty:
		_shield_dirty = true
		call_deferred("_rebuild_shields")

var _pending_shield_layers: int = 0

func _rebuild_shields() -> void:
	_shield_dirty = false
	var layers: int = _pending_shield_layers
	for child in _shield_container.get_children():
		child.queue_free()
	if layers <= 0:
		return
	var level: int = GameState.shoot_level
	var level_scale: float = 1.0 + level * 0.12
	var max_display: int = min(layers, 5)
	var count: int = max_display
	var base_radius: float = (32.0 + _sprite.texture.get_width() * 0.35) * level_scale
	for i in range(count):
		var ring := ShieldRing.new()
		var radius: float = base_radius + i * 6.0
		ring.setup(radius, 1.0 - float(i) / float(count) * 0.5)
		ring.z_index = 3
		_shield_container.add_child(ring)

func take_damage(amount: float = 1.0) -> void:
	if _invincible_timer > 0:
		return
	var actual_damage: int = amount as int
	if amount > 0.0 and amount < 1.0 and randf() < amount:
		actual_damage = 1
	var old_health: int = GameState.current_health
	GameState.take_damage(actual_damage)
	if GameState.current_health < old_health:
		_invincible_timer = 1.0
		_spawn_hit_effect()
		_play_hit_animation()
	if GameState.current_health <= 0:
		_spawn_explosion()
		died.emit()
		queue_free()

func _play_hit_animation() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.04)
	tween.tween_property(_sprite, "scale", Vector2(1.2, 1.2), 0.04)
	tween.tween_callback(func():
		var recover := create_tween().set_parallel(true)
		recover.tween_property(_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
		recover.tween_property(_sprite, "scale", Vector2(1.0, 1.0), 0.12)
	)

func _spawn_hit_effect() -> void:
	var hit = _hit_effect_scene.instantiate()
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position

func _spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_explosion()

func on_level_up() -> void:
	_update_appearance()
	_update_pickup_radius()
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(_sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
	tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1.0), 0.1)

func _make_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.4, 1.0)
	return style
