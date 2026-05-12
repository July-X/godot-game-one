extends CharacterBody2D

signal boss_died
signal phase_changed(phase_name: String)

enum State { IDLE, CIRCLE, ATTACK, RETREAT, ENRAGED }
enum BossPhase { SUPPRESSION, RIFT, OVERLOAD }

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
var entity_id: int = 0

func get_entity_id() -> int:
	return entity_id

func get_network_health() -> float:
	return _health

func get_network_max_health() -> float:
	return _max_health

func get_network_level() -> int:
	return _level

func get_network_rotation() -> float:
	return global_rotation

func get_sprite_variant_id() -> int:
	return _sprite_variant_id

func apply_network_rotation(rot: float) -> void:
	_network_target_rotation = rot
	if not _is_network_ghost:
		return
	if not get_meta("net_rot_sync_inited", false):
		global_rotation = rot
		set_meta("net_rot_sync_inited", true)

func apply_network_health(hp: float, max_hp: float) -> void:
	if max_hp > 0.0:
		_max_health = max_hp
	_health = clampf(hp, 0.0, _max_health)
	_update_phase_from_health(false)
	if _health_bar:
		_health_bar.max_value = _max_health
		_health_bar.value = _health

var _is_network_ghost: bool = false
var _recent_hit_window: float = 0.0
var _recent_hit_count: int = 0
var _sprite_variant_id: int = 0
var _rush_cooldown: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _corner_stuck_time: float = 0.0
var _fire_pressure_window: float = 0.0
var _fire_pressure_hits: int = 0
var _dodge_cooldown: float = 0.0
var _strafe_bias: Vector2 = Vector2.ZERO
var _velocity_blend: Vector2 = Vector2.ZERO
var _feint_timer: float = 0.0
var _burst_step: int = 0
var _phase: int = BossPhase.SUPPRESSION
var _last_phase_name: String = ""
var _supply_timer: float = 10.0
var _rift_timer: float = 1.4
var _live_summons: int = 0
var _dead: bool = false
var _network_target_rotation: float = 0.0
var _last_laser_hp_ratio: float = 1.0
var _shield_active: bool = false
var _ultimate_laser_charging: bool = false
var _ultimate_laser_firing: bool = false
var _ultimate_laser_charge_timer: float = 0.0
var _ultimate_laser_fire_timer: float = 0.0
var _ultimate_laser_start: Vector2 = Vector2.ZERO
var _ultimate_laser_end: Vector2 = Vector2.ZERO

const ARENA_MARGIN_X: float = 96.0
const ARENA_MARGIN_Y: float = 84.0
const BOSS_KNOCKBACK_BASE: float = 16.0
const BOSS_KNOCKBACK_RECENT_HIT_WINDOW: float = 0.24
const BOSS_KNOCKBACK_DECAY_PER_HIT: float = 0.20
const BOSS_VISUAL_SCALE: float = 2.0 / 3.0
const BOSS_TARGET_TTK_SECONDS: float = 42.0
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
const BOSS_LEAD_SECONDS: float = 0.34
const BOSS_MAX_TURN_RATE: float = 8.0
const BOSS_CRUISE_ACCEL: float = 7.5
const BOSS_FEINT_INTERVAL_MIN: float = 0.55
const BOSS_FEINT_INTERVAL_MAX: float = 1.25
const BOSS_MAX_SUMMONS: int = 2
const BOSS_ULTIMATE_LASER_HP_INTERVAL: float = 0.25  ## 每损失 15% 血量触发一次
const BOSS_ULTIMATE_LASER_CHARGE: float = 2.0
const BOSS_ULTIMATE_LASER_TRAVEL: float = 2.0
const BOSS_ULTIMATE_LASER_WIDTH: float = 110.0
const BOSS_ULTIMATE_LASER_HOLD_SECONDS: float = 12.0
const BOSS_ULTIMATE_LASER_DOT_HP_PER_SEC: float = 10.0
const ULTIMATE_LASER_INNER_RATIO: float = 0.3  ## 内圈比例（秒杀区）

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")

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
		_label.text = "裂隙母舰 Lv%d" % _level

func setup(level: int) -> void:
	_level = level
	var player_dps := _calc_player_dps()
	_mult = 1.0 + GameState.boss_encounter_count * 0.2
	var level_scale: float = 1.0 + clampf((_level - 5) * 0.03, 0.0, 0.45)
	_max_health = max(player_dps * BOSS_TARGET_TTK_SECONDS * BOSS_EXPECTED_PLAYER_UPTIME * _mult * level_scale, 900.0)
	_health = _max_health
	_last_laser_hp_ratio = 1.0
	_shoot_angle_offset = randf() * TAU
	_circle_dir = 1.0 if randf() < 0.5 else -1.0
	_circle_radius = 340.0
	_pick_new_strafe_bias()

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
	if _is_network_ghost:
		global_rotation = lerp_angle(global_rotation, _network_target_rotation, 0.45)
		if _health_bar:
			_health_bar.value = _health
		return
	if not _target or not is_instance_valid(_target):
		return
	if _health <= 0:
		return

	_state_timer -= delta
	_shoot_timer -= delta
	_update_phase_from_health(true)
	if _should_start_ultimate_laser():
		_start_ultimate_laser()
	if _ultimate_laser_charging or _ultimate_laser_firing:
		_tick_ultimate_laser(delta)
		if _health_bar:
			_health_bar.value = _health
		return
	_update_phase_loops(delta)
	_rush_cooldown = max(_rush_cooldown - delta, 0.0)
	_dodge_cooldown = max(_dodge_cooldown - delta, 0.0)
	_feint_timer = max(_feint_timer - delta, 0.0)
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
	var dist: float = global_position.distance_to(_target.global_position) if _target and is_instance_valid(_target) else 999.0
	if dist < BOSS_STANDOFF_MIN_DIST:
		_enter_state(State.RETREAT, randf_range(0.60, 1.05))
		return
	var roll := randf()
	if roll < 0.32:
		_enter_state(State.CIRCLE, randf_range(1.10, 2.05))
	elif roll < 0.86:
		_enter_state(State.ATTACK, randf_range(0.85, 1.45))
	else:
		_enter_state(State.RETREAT, randf_range(0.55, 1.05))

func _enter_state(s: int, dur: float) -> void:
	_state = s
	_state_timer = dur
	_state_duration = dur
	_attack_index = (_attack_index + 1) % 6
	_burst_step = 0
	_pick_new_strafe_bias()

func _check_enrage() -> void:
	_update_phase_from_health(true)

## ── idle ──
func _tick_idle(delta: float) -> void:
	_cruise_towards(_ideal_standoff_position(), 0.45, delta)
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
	pos += _strafe_bias
	_cruise_towards(pos, 1.0, delta)
	_face_target(delta)

	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── attack ──
func _tick_attack(delta: float) -> void:
	var spd_boost: float = _phase_speed_mult()
	match _phase:
		BossPhase.SUPPRESSION:
			if _attack_index % 2 == 0:
				_do_aimed_shot(delta, spd_boost)
			else:
				_do_fan_spread(delta, spd_boost)
		BossPhase.RIFT:
			match _attack_index % 4:
				0: _do_fan_spread(delta, spd_boost)
				1: _do_rift_ring(delta, spd_boost)
				2: _do_rotation_ring(delta, spd_boost)
				3: _do_summon(delta, spd_boost)
		BossPhase.OVERLOAD:
			match _attack_index % 5:
				0: _do_aimed_shot(delta, spd_boost)
				1: _do_fan_spread(delta, spd_boost)
				2: _do_sweep_barrage(delta, spd_boost)
				3: _do_rotation_ring(delta, spd_boost)
				4: _do_standoff_burst(delta, spd_boost)
	_face_target(delta)

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
	_velocity_blend = _velocity_blend.lerp(move_dir * spd, BOSS_CRUISE_ACCEL * delta)
	global_position += _velocity_blend * delta
	_face_target(delta)
	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── 攻击模式 ────────────────────────────────────────────────

func _get_boss_attack_damage() -> int:
	match _phase:
		BossPhase.SUPPRESSION:
			return 4
		BossPhase.RIFT:
			return 3
		BossPhase.OVERLOAD:
			return 3
	return 3

func get_phase_name() -> String:
	match _phase:
		BossPhase.SUPPRESSION:
			return "压制校准"
		BossPhase.RIFT:
			return "裂隙展开"
		BossPhase.OVERLOAD:
			return "核心过载"
	return "压制校准"

func _apply_phase_sprite(phase: int) -> void:
	if _sprite == null:
		return
	var variant := 1
	match phase:
		BossPhase.SUPPRESSION:
			variant = 1
		BossPhase.RIFT:
			variant = 2
		BossPhase.OVERLOAD:
			variant = 3
	_sprite_variant_id = variant
	_sprite.texture = SpriteFactory.create_boss_sprite(variant)

func _phase_speed_mult() -> float:
	match _phase:
		BossPhase.SUPPRESSION:
			return 0.92
		BossPhase.RIFT:
			return 1.0
		BossPhase.OVERLOAD:
			return 1.2
	return 1.0

func _should_start_ultimate_laser() -> bool:
	if _dead or _ultimate_laser_charging or _ultimate_laser_firing:
		return false
	if _health <= 0.0 or _max_health <= 0.0:
		return false
	if not _target or not is_instance_valid(_target):
		return false
	var current_ratio: float = _health / maxf(_max_health, 1.0)
	return _last_laser_hp_ratio - current_ratio >= BOSS_ULTIMATE_LASER_HP_INTERVAL

func _start_ultimate_laser() -> void:
	_last_laser_hp_ratio = _health / maxf(_max_health, 1.0)
	_shield_active = true
	_ultimate_laser_charging = true
	_ultimate_laser_firing = false
	_ultimate_laser_charge_timer = BOSS_ULTIMATE_LASER_CHARGE
	_ultimate_laser_fire_timer = 0.0
	_velocity_blend = Vector2.ZERO
	_enter_state(State.ATTACK, BOSS_ULTIMATE_LASER_CHARGE + BOSS_ULTIMATE_LASER_TRAVEL)
	modulate = Color(1.4, 0.55, 0.45, 1.0)
	## 显示护盾光晕
	if _sprite:
		_sprite.modulate = Color(0.65, 0.85, 1.2, 1.0)
	var scene := get_tree().current_scene
	if scene and scene.has_method("broadcast_boss_ultimate_laser_charge"):
		scene.broadcast_boss_ultimate_laser_charge(global_position, BOSS_ULTIMATE_LASER_CHARGE)

func _tick_ultimate_laser(delta: float) -> void:
	_face_target(delta)
	if _ultimate_laser_charging:
		_ultimate_laser_charge_timer -= delta
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.026) * 0.18
		if _sprite:
			_sprite.modulate = Color(pulse, 0.42 + pulse * 0.18, 0.38 + pulse * 0.12, 1.0)
		if _ultimate_laser_charge_timer <= 0.0:
			_fire_ultimate_laser()
		return
	if _ultimate_laser_firing:
		_ultimate_laser_fire_timer -= delta
		if _ultimate_laser_fire_timer <= BOSS_ULTIMATE_LASER_HOLD_SECONDS and _ultimate_laser_fire_timer > 0.0:
			_apply_continuous_laser_damage(delta)
		if _ultimate_laser_fire_timer <= 0.0:
			_ultimate_laser_firing = false
			_state_timer = 0.0
			modulate = Color(1.0, 1.0, 1.0, 1.0)
			if _sprite:
				_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_pick_state()

func _fire_ultimate_laser() -> void:
	_ultimate_laser_charging = false
	_ultimate_laser_firing = true
	_ultimate_laser_fire_timer = BOSS_ULTIMATE_LASER_TRAVEL + BOSS_ULTIMATE_LASER_HOLD_SECONDS
	_ultimate_laser_start = global_position
	var aim_point: Vector2 = _predict_target_position()
	var dir: Vector2 = _ultimate_laser_start.direction_to(aim_point)
	if dir.length_squared() <= 0.001:
		dir = Vector2.DOWN
	var screen: Vector2 = get_viewport_rect().size
	_ultimate_laser_end = _ultimate_laser_start + dir.normalized() * screen.length() * 1.35
	var scene := get_tree().current_scene
	if scene and scene.has_method("broadcast_boss_ultimate_laser_fire"):
		scene.broadcast_boss_ultimate_laser_fire(_ultimate_laser_start, _ultimate_laser_end, BOSS_ULTIMATE_LASER_TRAVEL, BOSS_ULTIMATE_LASER_WIDTH, BOSS_ULTIMATE_LASER_HOLD_SECONDS)

func _apply_continuous_laser_damage(delta: float) -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	for player in get_tree().get_nodes_in_group("player"):
		if not (player is Node2D) or not is_instance_valid(player):
			continue
		var pos := (player as Node2D).global_position
		var dist := _distance_to_beam_center(pos)
		if dist < 0.0 or dist > BOSS_ULTIMATE_LASER_WIDTH * 0.5:
			continue
		var ratio: float = dist / (BOSS_ULTIMATE_LASER_WIDTH * 0.5)
		if ratio <= ULTIMATE_LASER_INNER_RATIO:
			## 内圈 - 秒杀
			if player.has_method("force_kill"):
				player.force_kill()
			elif player.has_method("take_damage"):
				player.take_damage(99999.0)
		else:
			## 外圈 - 每秒固定伤害
			if player.has_method("take_damage"):
				player.take_damage(BOSS_ULTIMATE_LASER_DOT_HP_PER_SEC * delta)

func _distance_to_beam_center(point: Vector2) -> float:
	var ab := _ultimate_laser_end - _ultimate_laser_start
	var len_sq := ab.length_squared()
	if len_sq <= 0.001:
		return -1.0
	var t := clampf((point - _ultimate_laser_start).dot(ab) / len_sq, 0.0, 1.0)
	var closest := _ultimate_laser_start + ab * t
	var dist := point.distance_to(closest)
	if dist > BOSS_ULTIMATE_LASER_WIDTH * 0.5:
		return -1.0
	return dist

func _update_phase_from_health(emit_event: bool) -> void:
	var ratio: float = _health / max(_max_health, 1.0)
	var next_phase: int = BossPhase.SUPPRESSION
	if ratio <= 0.35:
		next_phase = BossPhase.OVERLOAD
	elif ratio <= 0.70:
		next_phase = BossPhase.RIFT
	if next_phase == _phase and _last_phase_name == get_phase_name():
		return
	_phase = next_phase
	_last_phase_name = get_phase_name()
	_apply_phase_sprite(_phase)
	_circle_radius = 300.0
	if _phase == BossPhase.RIFT:
		_circle_radius = 250.0
	elif _phase == BossPhase.OVERLOAD:
		_circle_radius = 210.0
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _label:
		_label.text = "%s Lv%d" % [get_phase_name(), _level]
	if emit_event:
		phase_changed.emit(get_phase_name())

func _update_phase_loops(delta: float) -> void:
	if _phase != BossPhase.OVERLOAD:
		return
	_supply_timer -= delta
	if _supply_timer <= 0.0:
		_supply_timer = 10.0
		_drop_supply_fragments()

func _pick_new_strafe_bias() -> void:
	var screen := get_viewport_rect().size
	_strafe_bias = Vector2(randf_range(-screen.x * 0.10, screen.x * 0.10), randf_range(-screen.y * 0.04, screen.y * 0.08))
	_feint_timer = randf_range(BOSS_FEINT_INTERVAL_MIN, BOSS_FEINT_INTERVAL_MAX)

func _predict_target_position() -> Vector2:
	if not _target or not is_instance_valid(_target):
		return global_position
	var target_velocity := Vector2.ZERO
	var maybe_velocity: Variant = _target.get("velocity")
	if typeof(maybe_velocity) == TYPE_VECTOR2:
		target_velocity = maybe_velocity
	return _target.global_position + target_velocity * BOSS_LEAD_SECONDS

func _ideal_standoff_position() -> Vector2:
	var predicted := _predict_target_position()
	var to_boss: Vector2 = predicted.direction_to(global_position)
	if to_boss.length_squared() <= 0.001:
		to_boss = Vector2.UP
	var dist := clampf(global_position.distance_to(predicted), BOSS_STANDOFF_MIN_DIST + 40.0, BOSS_STANDOFF_MAX_DIST - 40.0)
	return _clamp_to_arena(predicted + to_boss.normalized() * dist + _strafe_bias)

func _cruise_towards(target_pos: Vector2, speed_scale: float, delta: float) -> void:
	if _feint_timer <= 0.0:
		_pick_new_strafe_bias()
	var desired := global_position.direction_to(_clamp_to_arena(target_pos))
	var speed: float = (210.0 + _level * 9.0) * speed_scale * (1.22 if _state == State.ENRAGED else 1.0)
	_velocity_blend = _velocity_blend.lerp(desired * speed, BOSS_CRUISE_ACCEL * delta)
	global_position += _velocity_blend * delta

func _face_target(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		return
	var target_angle := global_position.angle_to_point(_predict_target_position()) + PI * 0.5
	rotation = lerp_angle(rotation, target_angle, BOSS_MAX_TURN_RATE * delta)

func _spawn_enemy_bullet(pos: Vector2, angle: float, damage: float, speed: float, color: Color) -> void:
	var bullet := Pool.acquire("bullet", _bullet_scene)
	get_tree().current_scene.add_child(bullet)
	bullet.setup(pos, angle, damage, false, 1, speed)
	bullet.modulate = color
	if NetworkManager.is_online():
		var scene := get_tree().current_scene
		if scene and scene.has_method("register_bullet_spawn"):
			scene.register_bullet_spawn(pos, angle, damage, false, 1, speed, color)

## 1. 瞄准射击 — 3/5发追踪弹
func _do_aimed_shot(delta: float, spd: float) -> void:
	var count: int = 2 if _phase == BossPhase.SUPPRESSION else 3
	_cruise_towards(_ideal_standoff_position(), 0.42, delta)
	if _shoot_timer <= 0:
		var angle: float = global_position.angle_to_point(_predict_target_position())
		for i in range(count):
			var a: float = angle + (i - count / 2.0) * 0.06
			_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), 620.0, Color(1.0, 0.3, 0.3, 1.0))
		_shoot_timer = 0.52 / spd

## 2. 扇形弹幕 — 5/7/9发
func _do_fan_spread(delta: float, spd: float) -> void:
	var count: int = 5 if _phase == BossPhase.SUPPRESSION else 7
	_cruise_towards(_ideal_standoff_position(), 0.35, delta)
	if _shoot_timer <= 0:
		var base: float = global_position.angle_to_point(_predict_target_position())
		var spread: float = PI * (0.34 if _phase == BossPhase.SUPPRESSION else 0.48)
		for i in range(count):
			if _phase != BossPhase.SUPPRESSION and i == count / 2:
				continue
			var a: float = base - spread * 0.5 + spread * i / (count - 1)
			_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), 560.0, Color(0.4, 0.5, 1.0, 1.0))
		_shoot_timer = 0.78 / spd

## 3. 旋转激光 — 6/8/10发环形
func _do_rotation_ring(delta: float, spd: float) -> void:
	var count: int = 12
	var ring_speed: float = 2.0 * spd
	_cruise_towards(_ideal_standoff_position(), 0.28, delta)
	if _shoot_timer <= 0:
		for i in range(count):
			if i % 6 == 0:
				continue
			var a: float = _shoot_angle_offset + float(i) * TAU / count
			_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, 2.0, 340.0, Color(0.8, 0.2, 0.9, 1.0))
		_shoot_timer = 1.45 / spd
	_shoot_angle_offset += delta * ring_speed

## 4. 召唤小兵 — 2/3/4个
func _do_summon(delta: float, spd: float) -> void:
	_cruise_towards(_ideal_standoff_position(), 0.30, delta)
	if _shoot_timer <= 0:
		if _live_summons >= BOSS_MAX_SUMMONS:
			_shoot_timer = 2.0 / spd
			return
		var count: int = min(BOSS_MAX_SUMMONS - _live_summons, 2)
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
			_live_summons += 1
		_shoot_timer = 4.0 / spd

func _do_standoff_burst(delta: float, spd: float) -> void:
	_cruise_towards(_ideal_standoff_position(), 0.78, delta)
	if _shoot_timer <= 0:
		var base: float = global_position.angle_to_point(_predict_target_position())
		var lane := (_burst_step % 3) - 1
		for i in range(3):
			var a: float = base + (i - 1) * 0.07 + float(lane) * 0.035
			_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 22, a, _get_boss_attack_damage(), 620.0, Color(1.0, 0.62, 0.25, 1.0))
		_burst_step += 1
		_shoot_timer = 0.58 / spd

func _do_rift_ring(delta: float, spd: float) -> void:
	_cruise_towards(_ideal_standoff_position(), 0.24, delta)
	_rift_timer -= delta
	if _shoot_timer <= 0 and _rift_timer <= 0.0:
		_rift_timer = 8.0
		var portal_pos := _clamp_to_arena(global_position + Vector2(randf_range(-160.0, 160.0), randf_range(36.0, 150.0)))
		_spawn_rift_visual(portal_pos)
		for i in range(12):
			if i % 4 == 0:
				continue
			var a: float = float(i) * TAU / 12.0
			_spawn_enemy_bullet(portal_pos + Vector2.from_angle(a) * 18.0, a, 2.0, 340.0, Color(0.85, 0.2, 1.0, 1.0))
		_shoot_timer = 1.3 / spd

func _do_sweep_barrage(delta: float, spd: float) -> void:
	_cruise_towards(_ideal_standoff_position(), 0.55, delta)
	if _shoot_timer <= 0:
		var lanes := 7
		var screen := get_viewport_rect().size
		var y := clampf(global_position.y + 40.0, 120.0, screen.y - 140.0)
		var sweep_idx := _burst_step % lanes
		for i in range(lanes):
			if abs(i - sweep_idx) <= 1:
				continue
			var x := 130.0 + float(i) * ((screen.x - 260.0) / float(lanes - 1))
			_spawn_enemy_bullet(Vector2(x, y), PI * 0.5, 3.0, 520.0, Color(1.0, 0.18, 0.12, 1.0))
		_burst_step += 1
		_shoot_timer = 0.9 / spd

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
	_live_summons = max(_live_summons - 1, 0)

func _spawn_rift_visual(pos: Vector2) -> void:
	var ring := Node2D.new()
	ring.global_position = pos
	ring.z_index = 6
	ring.set_script(preload("res://scripts/shield_circle.gd"))
	get_tree().current_scene.add_child(ring)
	if ring.has_method("setup"):
		ring.setup(34.0, Color(0.85, 0.25, 1.0, 0.45))
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.8, 1.8), 0.55)
	tween.tween_property(ring, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(ring.queue_free)

func _drop_supply_fragments() -> void:
	var types: Array[String] = ["heal", "speed", "power", "heal"]
	for i in range(types.size()):
		_spawn_powerup_fragment(types[i], float(i) * TAU / float(types.size()), 70.0)

func _spawn_core_fragments() -> void:
	var types: Array[String] = ["core", "heal", "speed", "power", "core", "heal"]
	for i in range(types.size()):
		var assigned_peer_id := 0
		if types[i] == "core":
			var alive_ids := GameState.get_alive_player_ids()
			if alive_ids.size() > 0:
				assigned_peer_id = alive_ids[i % alive_ids.size()]
		_spawn_powerup_fragment(types[i], float(i) * TAU / float(types.size()), 92.0, assigned_peer_id)

func _spawn_powerup_fragment(type: String, angle: float, radius: float, assigned_peer_id: int = 0) -> void:
	var pu = _powerup_scene.instantiate()
	get_tree().current_scene.add_child(pu)
	pu.global_position = global_position + Vector2.from_angle(angle) * radius
	pu.setup(type)
	if assigned_peer_id > 0:
		pu.set_meta("assigned_peer_id", assigned_peer_id)
	if NetworkManager.is_online() and multiplayer.is_server():
		var scene := get_tree().current_scene
		if scene and scene.has_method("register_powerup_entity"):
			scene.register_powerup_entity(pu, type)

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

func take_damage(amount: float = 1.0, _killer_peer_id: int = -1) -> void:
	if _dead:
		return
	var applied: float = max(amount, 0.0)
	if applied <= 0.0:
		return
	if _shield_active:
		## 激光期间无敌护罩吸收所有伤害
		_hit_flash()
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
	if _dead:
		return
	_dead = true
	GameState.add_score(200 * _level, -1)
	_spawn_core_fragments()
	boss_died.emit()
	call_deferred("_spawn_explosion")
	queue_free()

func _spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	exp.scale = Vector2(4, 4)
	SFX.play_explosion()
