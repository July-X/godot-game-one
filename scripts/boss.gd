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
var _knockback_tween: Tween = null
var _recent_hit_window: float = 0.0
var _recent_hit_count: int = 0
var _sprite_variant_id: int = 0
var _rush_cooldown: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _corner_stuck_time: float = 0.0
var _fire_pressure_window: float = 0.0
var _fire_pressure_hits: int = 0
var _dodge_cooldown: float = 0.0

const ARENA_MARGIN_X: float = 96.0
const ARENA_MARGIN_Y: float = 84.0
const BOSS_KNOCKBACK_BASE: float = 16.0
const BOSS_KNOCKBACK_RECENT_HIT_WINDOW: float = 0.24
const BOSS_KNOCKBACK_DECAY_PER_HIT: float = 0.20
const BOSS_VISUAL_SCALE: float = 2.0 / 3.0
const BOSS_TARGET_TTK_SECONDS: float = 20.0
const BOSS_EXPECTED_PLAYER_UPTIME: float = 0.95
const BOSS_CLOSE_ESCAPE_DIST: float = 290.0
const BOSS_CLOSE_ESCAPE_COOLDOWN: float = 0.52
const BOSS_CLOSE_ESCAPE_PUSH: float = 460.0
const BOSS_FIRE_PRESSURE_WINDOW: float = 0.45
const BOSS_FIRE_PRESSURE_HITS: int = 3
const BOSS_DODGE_COOLDOWN: float = 0.62
const BOSS_DODGE_SHIFT: float = 140.0
const BOSS_STANDOFF_MIN_DIST: float = 300.0
const BOSS_STANDOFF_MAX_DIST: float = 560.0

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _label: Label = $Label

func _apply_visual_state() -> void:
	if _sprite:
		_sprite.texture = SpriteFactory.create_boss_sprite(_sprite_variant_id)
		_sprite.modulate = Color(1, 1, 1, 1)
		_sprite.scale = Vector2(BOSS_VISUAL_SCALE, BOSS_VISUAL_SCALE)
	if _health_bar:
		_health_bar.max_value = _max_health
		_health_bar.value = _health
	if _label:
		_label.text = "暗影主宰 Lv%d" % _level

func setup(level: int) -> void:
	_level = level
	var player_dps := _calc_player_dps()
	_mult = 1.0 + GameState.boss_encounter_count * 0.2
	var level_scale: float = 1.0 + clampf((_level - 5) * 0.03, 0.0, 0.45)
	_max_health = max(player_dps * BOSS_TARGET_TTK_SECONDS * BOSS_EXPECTED_PLAYER_UPTIME * _mult * level_scale, 900.0)
	_health = _max_health
	_shoot_angle_offset = randf() * TAU
	_circle_dir = 1.0 if randf() < 0.5 else -1.0
	_circle_radius = 340.0

	_apply_visual_state()
	add_to_group("boss")
	add_to_group("enemies")

func set_sprite_variant(variant_id: int) -> void:
	_sprite_variant_id = maxi(variant_id, 0)

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
	_last_position = global_position
	GameState.on_boss_started()
	## setup() 可能在 add_child() 前调用，这里再次应用一次视觉状态，确保贴图一定落到 Sprite2D 上
	_apply_visual_state()

func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return
	if not _target or not is_instance_valid(_target):
		return
	if _health <= 0:
		return

	_state_timer -= delta
	_shoot_timer -= delta
	_rush_cooldown = max(_rush_cooldown - delta, 0.0)
	_dodge_cooldown = max(_dodge_cooldown - delta, 0.0)
	if _recent_hit_window > 0.0:
		_recent_hit_window = max(_recent_hit_window - delta, 0.0)
		if _recent_hit_window <= 0.0:
			_recent_hit_count = 0
	if _fire_pressure_window > 0.0:
		_fire_pressure_window = max(_fire_pressure_window - delta, 0.0)
		if _fire_pressure_window <= 0.0:
			_fire_pressure_hits = 0

	match _state:
		State.IDLE: _tick_idle(delta)
		State.CIRCLE: _tick_circle(delta)
		State.ATTACK: _tick_attack(delta)
		State.RETREAT: _tick_retreat(delta)
		State.ENRAGED: _tick_attack(delta)

	_apply_close_range_escape(delta)
	_apply_fireline_dodge()

	_enforce_arena_bounds()
	_resolve_corner_stuck(delta)

	if _health_bar:
		_health_bar.value = _health

## ── 状态切换 ────────────────────────────────────────────────

func _pick_state() -> void:
	if _state == State.ENRAGED:
		_state = State.ATTACK
		_state_duration = randf_range(0.55, 1.1)
		_state_timer = _state_duration
		return
	match randi() % 4:
		0: _enter_state(State.CIRCLE, randf_range(1.0, 1.8))
		1: _enter_state(State.ATTACK, randf_range(0.9, 1.5))
		2: _enter_state(State.RETREAT, randf_range(0.55, 1.0))
		3: _enter_state(State.ATTACK, randf_range(0.75, 1.2))

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
	var spd: float = 3.2 * (1.0 + _level * 0.045) * (1.5 if _state == State.ENRAGED else 1.0)
	_circle_angle += delta * spd * _circle_dir
	var pos: Vector2 = _target.global_position + Vector2(cos(_circle_angle), sin(_circle_angle)) * _circle_radius
	var dist_to_player: float = global_position.distance_to(_target.global_position)
	if dist_to_player < BOSS_STANDOFF_MIN_DIST:
		var away: Vector2 = global_position.direction_to(_target.global_position) * -1.0
		pos += away * (BOSS_STANDOFF_MIN_DIST - dist_to_player) * 0.9
	elif dist_to_player > BOSS_STANDOFF_MAX_DIST:
		var to_player: Vector2 = global_position.direction_to(_target.global_position)
		pos += to_player * (dist_to_player - BOSS_STANDOFF_MAX_DIST) * 0.55
	global_position = global_position.lerp(pos, 9.5 * delta)
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
		4: _do_standoff_burst(delta, spd_boost)
	var follow: float = 8.0 if _state == State.ENRAGED else 6.0
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, follow * delta)

	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── retreat ──
func _tick_retreat(delta: float) -> void:
	var spd: float = 420.0 * (1.5 if _state == State.ENRAGED else 1.0)
	var away: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	var center: Vector2 = get_viewport_rect().size * 0.5
	var to_center: Vector2 = global_position.direction_to(center)
	var edge_bias: float = _get_edge_bias()
	var move_dir: Vector2 = (away * (1.0 - edge_bias) + to_center * edge_bias).normalized()
	global_position += move_dir * spd * delta
	rotation = global_position.angle_to_point(_target.global_position) + PI * 0.5
	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── 攻击模式 ────────────────────────────────────────────────

func _get_boss_attack_damage() -> int:
	return max(1, 8 + _level * 2 + GameState.boss_encounter_count * 4)

## 1. 瞄准射击 — 3/5发追踪弹
func _do_aimed_shot(delta: float, spd: float) -> void:
	var count: int = 4 + (1 if _level >= 10 else 0) + (1 if _level >= 15 else 0)
	if _shoot_timer <= 0:
		var angle: float = global_position.angle_to_point(_target.global_position)
		for i in range(count):
			var a: float = angle + (i - count / 2.0) * 0.06
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), false, 1, 760.0)
			b.modulate = Color(1.0, 0.3, 0.3, 1.0)
			_shoot_timer = 0.18 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 2. 扇形弹幕 — 5/7/9发
func _do_fan_spread(delta: float, spd: float) -> void:
	var count: int = 6 + (2 if _level >= 10 else 0) + (2 if _level >= 15 else 0)
	if _shoot_timer <= 0:
		var base: float = global_position.angle_to_point(_target.global_position)
		var spread: float = PI * 0.5
		for i in range(count):
			var a: float = base - spread * 0.5 + spread * i / (count - 1)
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), false, 1, 820.0)
			b.modulate = Color(0.4, 0.5, 1.0, 1.0)
			_shoot_timer = 0.34 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 3. 旋转激光 — 6/8/10发环形
func _do_rotation_ring(delta: float, spd: float) -> void:
	var count: int = 8 + (2 if _level >= 10 else 0) + (2 if _level >= 15 else 0)
	var ring_speed: float = 2.0 * spd
	if _shoot_timer <= 0:
		var total: int = count + (count if _state == State.ENRAGED else 0)
		for i in range(total):
			var a: float = _shoot_angle_offset + float(i) * TAU / total
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 20, a, ceil(_get_boss_attack_damage() * 0.6), false, 1, 620.0)
			b.modulate = Color(0.8, 0.2, 0.9, 1.0)
			_shoot_timer = 0.50 / spd
	_shoot_angle_offset += delta * ring_speed
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

## 4. 召唤小兵 — 2/3/4个
func _do_summon(delta: float, spd: float) -> void:
	if _shoot_timer <= 0:
		var count: int = 1 + (1 if _level >= 10 else 0)
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
			_shoot_timer = 1.6 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 3.0 * delta)

func _do_standoff_burst(delta: float, spd: float) -> void:
	var away: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	global_position += away * (220.0 + _level * 7.0) * delta
	if _shoot_timer <= 0:
		var base: float = global_position.angle_to_point(_target.global_position)
		for i in range(3):
			var a: float = base + (i - 1) * 0.09
			var b := Pool.acquire("bullet", _bullet_scene)
			get_tree().current_scene.add_child(b)
			b.setup(global_position + Vector2.from_angle(a) * 22, a, _get_boss_attack_damage(), false, 1, 840.0)
			b.modulate = Color(1.0, 0.62, 0.25, 1.0)
		_shoot_timer = 0.24 / spd
	rotation = lerp_angle(rotation, global_position.angle_to_point(_target.global_position) + PI * 0.5, 5.0 * delta)

## 5. 冲刺撞击 — 直线冲向玩家
func _do_charge(delta: float, spd: float) -> void:
	if _shoot_timer <= 0:
		_enter_state(State.ATTACK, 0.8)
		var dir: Vector2 = global_position.direction_to(_target.global_position)
		var speed: float = 560.0 + _level * 18.0
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
			_enter_state(State.CIRCLE, randf_range(0.5, 0.9))

func _apply_close_range_escape(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		return
	if _rush_cooldown > 0.0:
		return
	var dist: float = global_position.distance_to(_target.global_position)
	if dist > BOSS_CLOSE_ESCAPE_DIST:
		return
	var away: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	global_position += away * BOSS_CLOSE_ESCAPE_PUSH * delta
	_enter_state(State.RETREAT, randf_range(0.45, 0.85))
	_rush_cooldown = BOSS_CLOSE_ESCAPE_COOLDOWN

func _on_summon_died() -> void:
	pass

## ── 受击 ────────────────────────────────────────────────────

func _clamp_to_arena(pos: Vector2) -> Vector2:
	var screen := get_viewport_rect().size
	return Vector2(
		clampf(pos.x, ARENA_MARGIN_X, screen.x - ARENA_MARGIN_X),
		clampf(pos.y, ARENA_MARGIN_Y, screen.y - ARENA_MARGIN_Y)
	)

func _enforce_arena_bounds() -> void:
	global_position = _clamp_to_arena(global_position)

func _get_edge_bias() -> float:
	var screen := get_viewport_rect().size
	var near_x: bool = global_position.x <= ARENA_MARGIN_X + 28.0 or global_position.x >= screen.x - ARENA_MARGIN_X - 28.0
	var near_y: bool = global_position.y <= ARENA_MARGIN_Y + 28.0 or global_position.y >= screen.y - ARENA_MARGIN_Y - 28.0
	if near_x and near_y:
		return 0.88
	if near_x or near_y:
		return 0.58
	return 0.0

func _resolve_corner_stuck(delta: float) -> void:
	var moved: float = global_position.distance_to(_last_position)
	var edge_bias: float = _get_edge_bias()
	if edge_bias > 0.0 and moved < 2.5:
		_corner_stuck_time += delta
	else:
		_corner_stuck_time = max(_corner_stuck_time - delta * 2.0, 0.0)
	if _corner_stuck_time >= 0.3:
		var center: Vector2 = get_viewport_rect().size * 0.5
		var nudge: Vector2 = global_position.direction_to(center) * (210.0 * delta)
		global_position = _clamp_to_arena(global_position + nudge)
		_enter_state(State.CIRCLE, randf_range(0.55, 1.0))
		_corner_stuck_time = 0.0
	_last_position = global_position

func _apply_fireline_dodge() -> void:
	if _dodge_cooldown > 0.0:
		return
	if _fire_pressure_hits < BOSS_FIRE_PRESSURE_HITS:
		return
	if not _target or not is_instance_valid(_target):
		return
	var to_player: Vector2 = global_position.direction_to(_target.global_position)
	var left: Vector2 = Vector2(-to_player.y, to_player.x)
	var right: Vector2 = -left
	var left_pos: Vector2 = _clamp_to_arena(global_position + left * BOSS_DODGE_SHIFT)
	var right_pos: Vector2 = _clamp_to_arena(global_position + right * BOSS_DODGE_SHIFT)
	var left_score: float = _score_dodge_position(left_pos)
	var right_score: float = _score_dodge_position(right_pos)
	global_position = left_pos if left_score >= right_score else right_pos
	_enter_state(State.CIRCLE, randf_range(0.45, 0.85))
	_dodge_cooldown = BOSS_DODGE_COOLDOWN
	_fire_pressure_hits = 0
	_fire_pressure_window = 0.0

func _score_dodge_position(pos: Vector2) -> float:
	var screen := get_viewport_rect().size
	var margin_x: float = min(pos.x - ARENA_MARGIN_X, screen.x - ARENA_MARGIN_X - pos.x)
	var margin_y: float = min(pos.y - ARENA_MARGIN_Y, screen.y - ARENA_MARGIN_Y - pos.y)
	var edge_space: float = min(margin_x, margin_y)
	var dist_player: float = pos.distance_to(_target.global_position)
	return edge_space * 1.8 + dist_player * 0.18

func take_damage(amount: float = 1.0) -> void:
	var applied: float = max(amount, 0.0)
	if applied <= 0.0:
		return
	_health -= applied
	if _fire_pressure_window > 0.0:
		_fire_pressure_hits += 1
	else:
		_fire_pressure_hits = 1
	_fire_pressure_window = BOSS_FIRE_PRESSURE_WINDOW
	_hit_flash()
	_hit_knockback()
	if _health_bar:
		_health_bar.value = max(_health, 0.0)
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
	if _knockback_tween and _knockback_tween.is_valid() and _knockback_tween.is_running():
		return
	if _recent_hit_window > 0.0:
		_recent_hit_count += 1
	else:
		_recent_hit_count = 1
	_recent_hit_window = BOSS_KNOCKBACK_RECENT_HIT_WINDOW

	var origin := _clamp_to_arena(global_position)
	global_position = origin
	var dir: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	var recent_hit_resist: float = clampf(1.0 - (_recent_hit_count - 1) * BOSS_KNOCKBACK_DECAY_PER_HIT, 0.25, 1.0)
	var state_resist: float = 0.45 if (_state == State.RETREAT or _attack_index == 4) else 1.0
	var push_dist := BOSS_KNOCKBACK_BASE * recent_hit_resist * state_resist
	var pushed := _clamp_to_arena(origin + dir * push_dist)
	_knockback_tween = create_tween().set_parallel(true)
	_knockback_tween.tween_property(self, "global_position", pushed, 0.03).set_ease(Tween.EASE_OUT)
	_knockback_tween.tween_property(self, "global_position", origin, 0.09).set_delay(0.03).set_ease(Tween.EASE_IN)
	var squash := Vector2(BOSS_VISUAL_SCALE * 1.08, BOSS_VISUAL_SCALE * 0.95)
	var restore := Vector2(BOSS_VISUAL_SCALE, BOSS_VISUAL_SCALE)
	_knockback_tween.tween_property(_sprite, "scale", squash, 0.03).set_ease(Tween.EASE_OUT)
	_knockback_tween.tween_property(_sprite, "scale", restore, 0.08).set_delay(0.03).set_ease(Tween.EASE_OUT)
	_knockback_tween.finished.connect(func():
		_knockback_tween = null
	)

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
