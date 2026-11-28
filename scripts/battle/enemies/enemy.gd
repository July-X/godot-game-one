extends CharacterBody2D

signal enemy_died
signal transport_exited

const TRANSPORT_HP := 12
const TRANSPORT_SPEED := 300.0

@export var enemy_type: int = 0
@export var health: int = 2
@export var move_speed: float = 60.0
@export var shoot_cooldown: float = 2.0
@export var drop_chance: float = 0.20

## 章节主题的敌弹速度倍率（wave_director.gd CHAPTER_THEMES）。
##
## 为什么要做成字段而不是在 `_shoot_*` 里读全局：生成包必须带着它走，
## 否则联机两端弹幕速度不一致，擦弹和走位预案全部失效（见 main.gd `_rpc_spawn_enemy`）。
## 默认 1.0 = 原始三档速度，不受主题影响。
var bullet_speed_mult: float = 1.0
var ordinary_attack := false
var is_transport := false

var entity_id: int = 0

func get_entity_id() -> int:
	return entity_id
var _is_network_ghost: bool = false
var _death_started := false
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

const Palette = preload("res://scripts/visuals/palette.gd")
const OrdinaryVisual = preload("res://scripts/battle/enemies/ordinary_enemy_visual.gd")
const WaveDirector = preload("res://scripts/battle/wave_director.gd")
enum AttackPhase { FLIGHT, PREPARE, FOLLOW_THROUGH, RECOVER }
const FOLLOW_THROUGH_SECONDS := 0.34
const MAX_PREPARE_USEC := 950000
const VISIBLE_LEAD_USEC := 450000
var attack_phase := AttackPhase.FLIGHT
var attack_stamp := 0
var attack_origin := Vector2.ZERO
var attack_heading := 0.0
var attack_angles := PackedFloat32Array()
var attack_first_count := 0
var attack_release := false
var _attack_left := 0.0
var _attack_target: Node2D
var _prepare_at_usec := 0
var _guest_seen_at_usec := 0
var _ordinary_visual: Node2D
var _last_ghost_position := Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("enemies")
	if ordinary_attack:
		_sprite.hide()
		_ordinary_visual = OrdinaryVisual.new()
		_ordinary_visual.ship = self
		add_child(_ordinary_visual)
		_last_ghost_position = global_position
	elif _sprite:
		_sprite.texture = SpriteFactory.create_enemy_sprite(enemy_type)
	if _health_bar:
		_health_bar.max_value = TRANSPORT_HP if is_transport else health
		_health_bar.value = health
	if is_transport:
		remove_from_group("ordinary_enemies")
		rotation = PI * 0.5
		return
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
		if ordinary_attack and not is_transport:
			var travel := global_position - _last_ghost_position
			if attack_phase == AttackPhase.FLIGHT and travel.length_squared() > 0.16:
				rotation = travel.angle() + PI * 0.5
			_last_ghost_position = global_position
		return

	if is_transport:
		position.x += move_speed * delta
		_health_bar.value = health
		if position.x > NetworkManager.battle_size(self).x + WaveDirector.SPAWN_MARGIN:
			retire_transport()
		return

	_wobble_timer += delta * 2.0

	## 移动模式因类型而异
	if ordinary_attack and attack_phase in [AttackPhase.PREPARE, AttackPhase.FOLLOW_THROUGH]:
		velocity = Vector2.ZERO
	else:
		match enemy_type:
			0: _move_chase(delta)
			1: _move_zigzag(delta)
			2: _move_orbit(delta)
		move_and_slide()

	## 屏幕边界反弹
	var screen := NetworkManager.battle_size(self)
	var margin: float = 20.0
	if global_position.x < margin or global_position.x > screen.x - margin:
		velocity.x *= -0.8
		global_position.x = clamp(global_position.x, margin, screen.x - margin)
	if global_position.y < margin or global_position.y > screen.y - margin:
		velocity.y *= -0.8
		global_position.y = clamp(global_position.y, margin, screen.y - margin)

	## 朝向玩家
	if is_instance_valid(_target) and (not ordinary_attack or attack_phase == AttackPhase.FLIGHT):
		var angle: float = global_position.angle_to_point(_target.global_position) + PI * 0.5
		rotation = angle

	if ordinary_attack:
		_tick_ordinary_attack(delta)
	else:
		_tick_legacy_attack(delta)
	if _health_bar:
		_health_bar.value = health

func _tick_legacy_attack(delta: float) -> void:
	## 试飞及专用战场的既有出招路径。
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

## 绘制弹道预告线。
##
## 这是弹幕射击可读性最大的单一来源：玩家不需要"猜"敌人要往哪打，
## 顺着线就知道该往哪躲。原来的"变红+放大"只能说明"它要出招了"，
## 但没说"往哪出招"——而躲避方向才是玩家真正需要的信息。
func _draw() -> void:
	if _warn_left <= 0.0 or _warn_dir.length() < 0.01:
		return
	var screen: Vector2 = NetworkManager.battle_size(self)
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

func _tick_ordinary_attack(delta: float) -> void:
	if NetworkManager.recovery.is_reserved() and not NetworkManager.is_online():
		return
	_shoot_timer -= delta
	_attack_left -= delta
	if attack_phase in [AttackPhase.PREPARE, AttackPhase.FOLLOW_THROUGH]:
		if _target != _attack_target or not _target_can_be_attacked():
			_finish_ordinary_attack()
			return
	match attack_phase:
		AttackPhase.FLIGHT:
			if _shoot_timer <= 0.0 and _target_can_be_attacked():
				_begin_ordinary_attack()
		AttackPhase.PREPARE:
			_wait_for_ordinary_warning()
		AttackPhase.FOLLOW_THROUGH:
			if _attack_left <= 0.0:
				_release_ordinary_batch(attack_first_count, attack_angles.size())
		AttackPhase.RECOVER:
			if _attack_left <= 0.0:
				_set_attack_phase(AttackPhase.FLIGHT)

func _wait_for_ordinary_warning() -> void:
	var online := NetworkManager.is_online()
	var headless := DisplayServer.get_name() == "headless"
	if headless and not online:
		if _attack_left <= 0.0:
			_release_ordinary_batch(0, attack_first_count)
		return
	var now := Time.get_ticks_usec()
	var shown_at: int = _prepare_at_usec if headless else _ordinary_visual.warning_visible_usec
	var guest_ready := not online or (_guest_seen_at_usec > 0 and now - _guest_seen_at_usec >= VISIBLE_LEAD_USEC)
	var local_ready := shown_at > 0 and now - shown_at >= VISIBLE_LEAD_USEC
	var elapsed := now - _prepare_at_usec
	if local_ready and guest_ready and elapsed <= MAX_PREPARE_USEC:
		_release_ordinary_batch(0, attack_first_count)
	elif elapsed >= MAX_PREPARE_USEC:
		_finish_ordinary_attack()

func _target_can_be_attacked() -> bool:
	return is_instance_valid(_target) and not _target.is_queued_for_deletion() \
		and not _target.get("is_downed") and not is_queued_for_deletion()

func _begin_ordinary_attack() -> void:
	var heading := global_position.direction_to(_target.global_position)
	if heading.is_zero_approx():
		return
	_attack_target = _target
	attack_origin = global_position
	attack_heading = heading.angle()
	rotation = attack_heading + PI * 0.5
	velocity = Vector2.ZERO
	var chapter := WaveDirector.chapter_for_level(GameState.level)
	var phase: int = get_tree().current_scene._wave_director.current_phase()
	attack_angles.clear()
	match enemy_type:
		0:
			attack_angles = PackedFloat32Array([attack_heading])
			attack_first_count = 1
		1:
			var side := 1.0 if sin(_wobble_timer) >= 0.0 else -1.0
			var split := chapter >= 2 and phase == WaveDirector.PHASE_CREST
			var offsets := [-0.25 * side, 0.05 * side, 0.32 * side] if split else [-0.2, 0.0, 0.2]
			for offset: float in offsets:
				attack_angles.append(attack_heading + offset)
			attack_first_count = 2 if split else 3
		2:
			# All six rays stay outside the 80° opening, including the later three.
			var field := Rect2(Vector2.ZERO, NetworkManager.battle_size(self)).grow(-60.0)
			var split := chapter >= 3 and phase == WaveDirector.PHASE_SURGE \
				and field.has_point(attack_origin) and field.has_point(attack_origin + heading * 150.0)
			var offsets := [40, 152, 264, 96, 208, 320] if split else [40, 96, 152, 208, 264, 320]
			for offset: int in offsets:
				attack_angles.append(attack_heading + deg_to_rad(offset))
			attack_first_count = 3 if split else 6
	_shoot_timer = shoot_cooldown * (2.0 if enemy_type == 0 else 1.0) \
		+ randf_range(-0.3, 0.3) + WARN_DURATION + RECOVER_DURATION
	_attack_left = WARN_DURATION
	_prepare_at_usec = Time.get_ticks_usec()
	_guest_seen_at_usec = 0
	_set_attack_phase(AttackPhase.PREPARE)

func attack_muzzle(index: int) -> Vector2:
	var from := attack_origin + Vector2.from_angle(attack_angles[index]) * 20.0
	if enemy_type == 1:
		var wing := Vector2.from_angle(attack_heading + PI * 0.5)
		var side := signf(wrapf(attack_angles[index] - attack_heading, -PI, PI))
		from += wing * 10.0 * side
	return from

func _release_ordinary_batch(from: int, to: int) -> void:
	if from == 0:
		# A delayed warning shouldn't bring the next volley forward.
		_shoot_timer += maxf(-_attack_left, 0.0)
	if to < attack_angles.size():
		_attack_left = FOLLOW_THROUGH_SECONDS
		_set_attack_phase(AttackPhase.FOLLOW_THROUGH, true)
	else:
		_finish_ordinary_attack(true)
	for index in range(from, to):
		match enemy_type:
			0: _spawn_enemy_bullet(attack_muzzle(index), attack_angles[index], 1.0, SPEED_FAST, Palette.ENEMY_BULLET_FAST, true, true)
			1: _spawn_enemy_bullet(attack_muzzle(index), attack_angles[index], 0.5, SPEED_MID, Palette.ENEMY_BULLET_MID, true, true)
			2: _spawn_enemy_bullet(attack_muzzle(index), attack_angles[index], 0.3, SPEED_SLOW, Palette.ENEMY_BULLET_SLOW, true, true)

func _finish_ordinary_attack(released := false) -> void:
	_attack_left = RECOVER_DURATION
	_attack_target = null
	_set_attack_phase(AttackPhase.RECOVER, released)

func _set_attack_phase(phase: AttackPhase, released := false) -> void:
	attack_phase = phase
	attack_release = released
	attack_stamp += 1
	_ordinary_visual.phase_changed()
	if NetworkManager.is_online():
		get_tree().current_scene.broadcast_ordinary_enemy_attack(self)

func ordinary_attack_snapshot() -> Dictionary:
	var snapshot := {"stamp": attack_stamp, "phase": attack_phase, "at": attack_origin, "heading": attack_heading,
		"angles": attack_angles, "first": attack_first_count, "release": attack_release}
	if is_transport:
		snapshot["transport"] = true
	return snapshot

func apply_ordinary_attack(snapshot: Dictionary) -> bool:
	var stamp: int = snapshot.stamp
	if stamp <= attack_stamp:
		return false
	attack_stamp = stamp
	attack_phase = int(snapshot.phase) as AttackPhase
	attack_origin = snapshot.at
	attack_heading = snapshot.heading
	attack_angles = snapshot.angles
	attack_first_count = snapshot.first
	attack_release = snapshot.release
	if attack_phase != AttackPhase.FLIGHT:
		rotation = attack_heading + PI * 0.5
	_ordinary_visual.phase_changed()
	return attack_phase == AttackPhase.PREPARE

func confirm_ordinary_attack_seen(stamp: int) -> void:
	if attack_phase == AttackPhase.PREPARE and stamp == attack_stamp and _guest_seen_at_usec == 0:
		_guest_seen_at_usec = Time.get_ticks_usec()

func clear_ordinary_attack_for_hold() -> void:
	if not _is_network_ghost:
		attack_stamp += 1
		_shoot_timer = maxf(_shoot_timer, 0.25)
	attack_phase = AttackPhase.FLIGHT
	attack_release = false
	_attack_target = null
	_ordinary_visual.phase_changed()


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

func _spawn_enemy_bullet(pos: Vector2, angle: float, damage: float, speed: float, color: Color, reliable := false, warned := false) -> void:
	## 章节主题在这里生效：三档速度分层是"可读性"的基线，
	## 主题只在这个基线上做整体微调，不改变快慢对比关系（对比才是玩家判威胁的依据）。
	var bullet := Pool.acquire("bullet", _bullet_scene)
	get_tree().current_scene.add_child(bullet)
	var final_speed: float = speed * bullet_speed_mult
	bullet.setup(pos, angle, damage, false, 1, final_speed)
	bullet.modulate = color
	bullet.ordinary_enemy_round = GameState.get_sync_round() if warned and NetworkManager.is_online() else 0
	if NetworkManager.is_online():
		var scene := get_tree().current_scene
		if scene and scene.has_method("register_bullet_spawn"):
			scene.register_bullet_spawn(pos, angle, damage, false, 1, final_speed, color, -1, reliable, bullet.ordinary_enemy_round)

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
	if ordinary_attack and (_death_started or is_queued_for_deletion()):
		return
	health -= amount
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.08)
	if health <= 0:
		die(killer_peer_id)

func die(killer_peer_id: int = -1) -> void:
	if ordinary_attack:
		if _death_started or is_queued_for_deletion():
			return
		# 主炮和清屏炸弹共用此入口。分数或死亡回调可能在节点释放前再次进入。
		_death_started = true
	if not is_transport:
		GameState.add_kill(killer_peer_id)
	enemy_died.emit()
	## 延迟生成特效和道具，避免物理查询冲突
	call_deferred("_spawn_explosion")
	call_deferred("_try_spawn_powerup")
	queue_free()

func retire_transport() -> void:
	if _death_started or is_queued_for_deletion():
		return
	_death_started = true
	transport_exited.emit()
	queue_free()

func _spawn_explosion() -> void:
	## 击杀反馈：轻震屏。杂兵死亡极其频繁，强度必须压得很低，
	## 否则连续击杀时画面一直在抖，反而读不清弹幕。
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("add_shake"):
		scene.add_shake(scene.SHAKE_ENEMY_DEATH)
	play_death_feedback()

func play_death_feedback() -> void:
	var exp = _explosion_scene.instantiate()
	exp.setup_ordinary_death()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	SFX.play_enemy_death()

func _try_spawn_powerup() -> void:
	if is_transport:
		var battle := get_parent()
		if is_instance_valid(battle):
			battle.spawn_powerup_at("heal", global_position)
		return
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
