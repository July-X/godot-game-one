extends CharacterBody2D

signal boss_died

enum State { IDLE, CIRCLE, ATTACK, RETREAT, ENRAGED }

var _state: int = State.IDLE
var _state_timer: float = 0.0
var _state_duration: float = 1.5
var _target: Node2D = null
var _max_health: float = 80.0
var _health: float = 80.0
var _level: int = 5
var _mult: float = 1.0
var _circle_angle: float = 0.0
var _circle_dir: float = 1.0
var _attack_index: int = 0
var _shoot_timer: float = 0.0
var _shoot_angle_offset: float = 0.0
var _circle_radius: float = 220.0

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _label: Label = $Label

func setup(level: int) -> void:
	_level = level
	var player_dps := _calc_player_dps()
	_mult = 1.0 + GameState.boss_encounter_count * 0.3
	_max_health = player_dps * _mult * 3.0
	_health = _max_health
	_shoot_angle_offset = randf() * TAU
	_circle_dir = 1.0 if randf() < 0.5 else -1.0

	if _sprite:
		_sprite.texture = SpriteFactory.create_boss_sprite()
	if _health_bar:
		_health_bar.max_value = _max_health
		_health_bar.value = _health
	if _label:
		_label.text = "暗影主宰 Lv%d" % level
	add_to_group("boss")
	add_to_group("enemies")

func _calc_player_dps() -> float:
	var count: float = GameState.get_bullet_count()
	var dmg: float = GameState.get_bullet_damage()
	var cd: float = GameState.get_shoot_cooldown()
	var dps: float = count * dmg / cd
	return max(dps, 5.0)

func set_target(target: Node2D) -> void:
	_target = target

func _ready() -> void:
	_state = State.IDLE
	_state_timer = 0.0
	GameState.on_boss_started()

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return
	if not _target or not is_instance_valid(_target):
		return
	if _health <= 0:
		return

	_state_timer -= delta
	_shoot_timer -= delta

	match _state:
		State.IDLE: _tick_idle(delta)
		State.CIRCLE: _tick_circle(delta)
		State.ATTACK: _tick_attack(delta)
		State.RETREAT: _tick_retreat(delta)
		State.ENRAGED: _tick_attack(delta)

	if _health_bar:
		_health_bar.value = _health

## ── 状态切换 ────────────────────────────────────────────────

func _pick_state() -> void:
	if _state == State.ENRAGED:
		_state = State.ATTACK
		_state_duration = randf_range(0.8, 1.8)
		_state_timer = _state_duration
		return
	match randi() % 4:
		0: _enter_state(State.CIRCLE, randf_range(1.5, 3.0))
		1: _enter_state(State.ATTACK, randf_range(1.2, 2.5))
		2: _enter_state(State.RETREAT, randf_range(0.8, 1.5))
		3: _enter_state(State.CIRCLE, randf_range(1.5, 3.0))

func _enter_state(s: int, dur: float) -> void:
	_state = s
	_state_timer = dur
	_state_duration = dur
	_attack_index = (_attack_index + 1) % 5

func _check_enrage() -> void:
	if _health / _max_health < 0.5 and _state != State.ENRAGED:
		_state = State.ENRAGED
		_state_timer = 0.0
		modulate = Color(1.4, 0.6, 0.4, 1.0)
		if _label:
			_label.text = "⚠ 暗影主宰 愤怒!"
		_circle_radius = 160.0
		_circle_dir *= -1.0

## ── idle ──
func _tick_idle(delta: float) -> void:
	if _state_timer <= 0:
		_pick_state()

## ── circle（机动增强）──
func _tick_circle(delta: float) -> void:
	var spd: float = 2.0 * (1.0 + _level * 0.04) * (1.5 if _state == State.ENRAGED else 1.0)
	_circle_angle += delta * spd * _circle_dir
	var pos: Vector2 = _target.global_position + Vector2(cos(_circle_angle), sin(_circle_angle)) * _circle_radius
	global_position = global_position.lerp(pos, 3.0 * delta)
	rotation = global_position.angle_to_point(_target.global_position) + PI * 0.5

	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── attack ──
func _tick_attack(delta: float) -> void:
	var spd_boost: float = 1.5 if _state == State.ENRAGED else 1.0
	match _attack_index:
		0: _do_aimed_shot(delta, spd_boost)
		1: _do_fan_spread(delta, spd_boost)
		2: _do_rotation_ring(delta, spd_boost)
		3: _do_summon(delta, spd_boost)
		4: _do_charge(delta, spd_boost)
	var follow: float = 5.0 if _state == State.ENRAGED else 3.0
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, follow * delta)

	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── retreat ──
func _tick_retreat(delta: float) -> void:
	var spd: float = 120.0 * (1.5 if _state == State.ENRAGED else 1.0)
	var away: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	global_position += away * spd * delta
	rotation = global_position.angle_to_point(_target.global_position) + PI * 0.5
	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── 攻击模式 ────────────────────────────────────────────────

func _get_boss_attack_damage() -> int:
	return max(1, 5 + _level * 2 + GameState.boss_encounter_count * 3)

## 1. 瞄准射击 — 3/5发追踪弹
func _do_aimed_shot(delta: float, spd: float) -> void:
	var count: int = 3 + (1 if _level >= 10 else 0) + (1 if _level >= 15 else 0)
	if _shoot_timer <= 0:
		var angle: float = global_position.angle_to_point(_target.global_position)
		for i in range(count):
			var a: float = angle + (i - count / 2.0) * 0.06
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), false, 1, 620.0)
			b.modulate = Color(1.0, 0.3, 0.3, 1.0)
		_shoot_timer = 0.4 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 2. 扇形弹幕 — 5/7/9发
func _do_fan_spread(delta: float, spd: float) -> void:
	var count: int = 5 + (2 if _level >= 10 else 0) + (2 if _level >= 15 else 0)
	if _shoot_timer <= 0:
		var base: float = global_position.angle_to_point(_target.global_position)
		var spread: float = PI * 0.5
		for i in range(count):
			var a: float = base - spread * 0.5 + spread * i / (count - 1)
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), false, 1, 660.0)
			b.modulate = Color(0.4, 0.5, 1.0, 1.0)
		_shoot_timer = 0.7 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 3. 旋转激光 — 6/8/10发环形
func _do_rotation_ring(delta: float, spd: float) -> void:
	var count: int = 6 + (2 if _level >= 10 else 0) + (2 if _level >= 15 else 0)
	var ring_speed: float = 2.0 * spd
	if _shoot_timer <= 0:
		var total: int = count + (count if _state == State.ENRAGED else 0)
		for i in range(total):
			var a: float = _shoot_angle_offset + float(i) * TAU / total
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 20, a, ceil(_get_boss_attack_damage() * 0.6), false, 1, 500.0)
			b.modulate = Color(0.8, 0.2, 0.9, 1.0)
		_shoot_timer = 1.0 / spd
	_shoot_angle_offset += delta * ring_speed
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 4. 召唤小兵 — 2/3/4个
func _do_summon(delta: float, spd: float) -> void:
	if _shoot_timer <= 0:
		var count: int = 2 + (1 if _level >= 10 else 0) + (1 if _level >= 15 else 0)
		for i in range(count):
			var e := _enemy_scene.instantiate()
			var angle: float = float(i) * TAU / count
			e.position = global_position + Vector2(cos(angle), sin(angle)) * 60
			e.enemy_type = randi() % 3
			e.health = max(1, int(_level * 0.5))
			e.move_speed = 80.0 + _level * 5.0
			e.shoot_cooldown = max(1.5 - _level * 0.06, 0.5)
			e.drop_chance = 0.0
			if _target and is_instance_valid(_target):
				e.set_target(_target)
			e.enemy_died.connect(_on_summon_died)
			get_tree().current_scene.add_child(e)
		_shoot_timer = 3.0 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 5. 冲刺撞击 — 直线冲向玩家
func _do_charge(delta: float, spd: float) -> void:
	if _shoot_timer <= 0:
		_enter_state(State.ATTACK, 0.8)
		var dir: Vector2 = global_position.direction_to(_target.global_position)
		var speed: float = 500.0 + _level * 15.0
		velocity = dir * speed
		_shoot_timer = 0.01
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color(2, 2, 2, 1), 0.15)
		tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.1)
	else:
		move_and_slide()
		var screen := get_viewport_rect().size
		if global_position.x < 20 or global_position.x > screen.x - 20 or global_position.y < 20 or global_position.y > screen.y - 20:
			velocity = Vector2.ZERO

func _on_summon_died() -> void:
	pass

## ── 受击 ────────────────────────────────────────────────────

func take_damage(amount: int = 1) -> void:
	_health -= amount
	_hit_flash()
	_hit_knockback()
	if _health_bar:
		_health_bar.value = _health
	if _health <= 0:
		die()

func _hit_flash() -> void:
	var intensity: float = 1.8
	_sprite.modulate = Color(intensity, intensity, intensity, 1.0)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1), 0.08)

func _hit_knockback() -> void:
	if not _target or not is_instance_valid(_target):
		return
	var dir: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	var push: Vector2 = dir * 25.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", global_position + push, 0.04).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", global_position, 0.1).set_delay(0.04).set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "scale", Vector2(1.15, 1.05), 0.03).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(1.2, 1.2), 0.08).set_delay(0.03).set_ease(Tween.EASE_OUT)

func die() -> void:
	GameState.on_boss_killed()
	GameState.add_score(200 * _level)
	boss_died.emit()
	call_deferred("_spawn_explosion")
	queue_free()

func _spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	exp.scale = Vector2(4, 4)
	SFX.play_explosion()
