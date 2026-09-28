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

## 射击节奏三段式
## WARN：开火前的蓄力预告，0.45s 足够玩家看清"是谁、从哪、来什么"
## RECOVER：开火后的恢复期，0.8s 内不再开火，是玩家的输出窗口
const WARN_DURATION: float = 0.45
const RECOVER_DURATION: float = 0.8
var _warn_left: float = 0.0
var _recover_left: float = 0.0
var _warn_tween: Tween = null
## 预警弹道方向（世界坐标单位向量）
var _warn_dir: Vector2 = Vector2.ZERO

const Palette = preload("res://scripts/palette.gd")

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

	## 射击：三段式节奏（蓄力 → 释放 → 恢复）
	##
	## 原来只有"冷却到了就开火"，玩家看到弹幕时已经来不及反应了——
	## 弹幕射击的第四要素是**可预期节奏**，不是每件事都偷袭玩家。
	## 蓄力阶段用变红 + 缩放给明确预告，恢复阶段是玩家安全输出窗口。
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _target and is_instance_valid(_target):
		_shoot()
		var cd: float = shoot_cooldown
		if enemy_type == 0:
			cd *= 2.0
		_shoot_timer = cd + randf_range(-0.3, 0.3) + WARN_DURATION + RECOVER_DURATION
		## 预警方向取"即将开火"那一刻的瞄准方向，之后不再更新：
		## 蓄力期间敌人还会移动，线如果跟着抖就变成噪点，反而更难读
		_warn_dir = global_position.direction_to(_target.global_position)
		_warn_left = WARN_DURATION
		_recover_left = RECOVER_DURATION
		_set_warning_visual(true)
		queue_redraw()
	elif _recover_left > 0.0:
		## 恢复段：不再开火，视觉上明确告诉玩家"现在是安全的"
		_recover_left -= delta
		if _recover_left <= 0.0:
			_set_recover_visual(false)
	if _warn_left > 0.0:
		_warn_left -= delta
		if _warn_left <= 0.0:
			_set_warning_visual(false)
			queue_redraw()

	## 更新血条
	if _health_bar:
		_health_bar.value = health


## 绘制弹道预告线。
##
## 这是弹幕射击可读性最大的单一来源：玩家不需要"猜"敌人要往哪打，
## 顺着线就知道该往哪躲。原来的"变红+放大"只能说明"它要出招了"，
## 但没说"往哪出招"——而躲避方向才是玩家真正需要的信息。
func _draw() -> void:
	if _warn_left <= 0.0 or _warn_dir.length() < 0.01:
		return
	var screen: Vector2 = get_viewport_rect().size
	## 线画到屏幕边缘为止，不画到无穷远（那样会变成一条贯穿全屏的亮线）
	var to_edge: float = 2000.0
	if absf(_warn_dir.x) > 0.01:
		to_edge = minf(to_edge, (screen.x if _warn_dir.x > 0.0 else screen.x) / absf(_warn_dir.x))
	if absf(_warn_dir.y) > 0.01:
		to_edge = minf(to_edge, (screen.y if _warn_dir.y > 0.0 else screen.y) / absf(_warn_dir.y))
	## 蓄力过半才逐渐显现，避免"一直有根线"变成背景噪声
	var t: float = 1.0 - _warn_left / WARN_DURATION
	var alpha: float = clampf((t - 0.25) / 0.75, 0.0, 1.0) * 0.55
	draw_line(Vector2.ZERO, _warn_dir * to_edge, Color(Palette.WARN_LINE.r, Palette.WARN_LINE.g, Palette.WARN_LINE.b, alpha), 2.0)


## 蓄力预警视觉：整体变红并轻微放大。放大而不是闪烁，是因为闪烁在
## 高密度弹幕下会变成噪点，放大是"这个敌人要出招了"的可读信号。
func _set_warning_visual(on: bool) -> void:
	if _sprite == null:
		return
	if on:
		_warn_tween = create_tween()
		_warn_tween.set_loops(6)
		_warn_tween.tween_property(_sprite, "scale", Vector2(1.18, 1.18), 0.12)
		_warn_tween.tween_property(_sprite, "scale", Vector2(1.0, 1.0), 0.12)
		_sprite.modulate = Color(Palette.WARN_TINT.r * 1.8, Palette.WARN_TINT.g, Palette.WARN_TINT.b, 1.0)
	else:
		if _warn_tween != null and _warn_tween.is_valid():
			_warn_tween.kill()
		_warn_tween = null
		_sprite.modulate = Color(1, 1, 1, 1)


## 恢复段视觉：变暗，明确表达"这个敌人暂时不会开火"
func _set_recover_visual(on: bool) -> void:
	if _sprite == null or _sprite.modulate.r > 1.5:
		return
	_sprite.modulate = Palette.RECOVER_TINT if on else Color(1, 1, 1, 1)

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

## 敌弹速度分层。原来的三种攻击全部固定 780 px/s，等于只有一种速度——
## 玩家无法通过"躲得开/躲不开"来区分威胁，只能靠颜色猜。
## 弹幕的可读性来自**速度对比**：慢弹是墙（能绕、能读），快弹是针（只能闪）。
## 把慢弹压到 430、快弹提到 950，两者跨越 2.2 倍，对比一眼可辨。
const SPEED_SLOW: float = 430.0
const SPEED_MID: float = 780.0
const SPEED_FAST: float = 950.0

func _shoot_single(angle: float) -> void:
	var dmg: float = 1.0
	## 狙击手是"针"：高伤高速，必须提前看到
	_spawn_enemy_bullet(global_position + Vector2.from_angle(angle) * 20, angle, dmg,
		SPEED_FAST, Palette.ENEMY_BULLET_FAST)

func _shoot_spread(angle: float) -> void:
	for i in range(-1, 2):
		var a: float = angle + i * 0.2
		## 散射者弹速取中间档，是可绕行的"墙"
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, 0.5,
			SPEED_MID, Palette.ENEMY_BULLET_MID)

func _shoot_circle() -> void:
	for i in range(6):
		var a: float = float(i) * TAU / 6.0
		## 环绕者的环形弹压到慢档：六发一环，速度快了玩家只能挨打、不能走位
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, 0.3,
			SPEED_SLOW, Palette.ENEMY_BULLET_SLOW)

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
