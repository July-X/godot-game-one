extends CharacterBody2D

signal boss_died
signal phase_changed(phase_name: String)
signal shield_released

enum State { IDLE, CIRCLE, ATTACK, RETREAT, ENRAGED }
enum AttackWindow { UNKNOWN, OPEN, CHARGING, SWEEP, HOLD }
const ATTACK_WINDOW_LABELS := ["", "", "激光蓄力", "激光推进", "激光持续"]
const WINDOWS_PER_CYCLE := AttackWindow.HOLD - AttackWindow.OPEN + 1
enum ShieldPhase { RAISED, EXPOSED, RECHARGING }
const SHIELD_PHASE_COUNT := 3
enum BossPhase { SUPPRESSION, RIFT, OVERLOAD }

var _state: int = State.IDLE
var _state_timer: float = 0.0
var _target: Node2D = null
var _max_health: float = 80.0
var _health: float = 80.0
var _level: int = 5
var _mult: float = 1.0
var _circle_angle: float = 0.0
var _circle_dir: float = 1.0
var _shoot_timer: float = 0.0
var _next_attack := 0
var _circle_radius: float = 220.0
var _entry_tween: Tween = null
var _hit_recoil_tween: Tween = null
var entity_id: int = 0
var _network_window_stamp := -1
var _finished_laser_cycles := 0

func get_entity_id() -> int:
	return entity_id

func get_network_health() -> float:
	return _health

func get_network_max_health() -> float:
	return _max_health

func get_attack_window() -> AttackWindow:
	if _is_network_ghost:
		return window_from_stamp(_network_window_stamp)
	if _ultimate_laser_charging:
		return AttackWindow.CHARGING
	if not _ultimate_laser_firing:
		return AttackWindow.OPEN
	return AttackWindow.SWEEP if _ultimate_laser_fire_timer > BOSS_ULTIMATE_LASER_HOLD_SECONDS else AttackWindow.HOLD

static func window_from_stamp(stamp: int) -> AttackWindow:
	if stamp < 0:
		return AttackWindow.UNKNOWN
	return (AttackWindow.OPEN + stamp % WINDOWS_PER_CYCLE) as AttackWindow

func get_attack_window_stamp() -> int:
	if _is_network_ghost:
		return _network_window_stamp
	return _finished_laser_cycles * WINDOWS_PER_CYCLE + get_attack_window() - AttackWindow.OPEN

func apply_network_attack_window(stamp: int) -> void:
	_network_window_stamp = stamp
	if get_attack_window() == AttackWindow.OPEN:
		_laser_locked_direction = Vector2.ZERO
	queue_redraw()

func get_laser_visual_age() -> float:
	if _ultimate_laser_charging:
		return BOSS_ULTIMATE_LASER_CHARGE - _ultimate_laser_charge_timer
	return BOSS_ULTIMATE_LASER_TRAVEL + BOSS_ULTIMATE_LASER_HOLD_SECONDS - _ultimate_laser_fire_timer

func get_network_level() -> int:
	return _level

func get_network_rotation() -> float:
	return global_rotation

func get_sprite_variant_id() -> int:
	return _sprite_variant_id

func apply_network_rotation(rot: float) -> void:
	# 推进与持续阶段的朝向由可靠光束坐标锁定。
	if _is_network_ghost and (get_attack_window() >= AttackWindow.SWEEP or not _laser_locked_direction.is_zero_approx()):
		return
	_network_target_rotation = rot
	if not _is_network_ghost:
		return
	if not get_meta("net_rot_sync_inited", false):
		global_rotation = rot
		set_meta("net_rot_sync_inited", true)

func apply_network_health(hp: float, max_hp: float) -> void:
	if max_hp > 0.0:
		_max_health = max_hp
	if _health > 0.0 and hp <= 0.0:
		queue_redraw()
	_health = clampf(hp, 0.0, _max_health)
	_update_phase_from_health(false)

func get_shield_stamp() -> int:
	return _shield_stamp

func get_shield_hp() -> float:
	return _shield_hp

func get_max_shield_hp() -> float:
	return _max_shield_hp

func has_impact_shield() -> bool:
	return _shield_hp > 0.0

func is_shield_recharging() -> bool:
	return _shield_stamp >= 0 and _shield_stamp % SHIELD_PHASE_COUNT == ShieldPhase.RECHARGING

func apply_network_boss_shield(stamp: int, hp: float, max_hp: float) -> bool:
	if stamp < _shield_stamp:
		return false
	var advanced := stamp > _shield_stamp
	_shield_stamp = stamp
	_max_shield_hp = max_hp
	_shield_hp = clampf(hp if advanced else minf(hp, _shield_hp), 0.0, max_hp)
	queue_redraw()
	return advanced

var _is_network_ghost: bool = false
var _sprite_variant_id: int = 0
var _rush_cooldown: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _corner_stuck_time: float = 0.0
var _fire_pressure_window: float = 0.0
var _fire_pressure_hits: int = 0
var _pressure_hits_by_peer: Dictionary[int, int] = {}
var _pilot_trails: Dictionary[int, Vector2] = {}
var _dodge_cooldown: float = 0.0
var _dodge_shift := Vector2.ZERO
var _dodge_elapsed := 0.0
var _strafe_bias: Vector2 = Vector2.ZERO
var _velocity_blend: Vector2 = Vector2.ZERO
var _feint_timer: float = 0.0
var _phase: int = BossPhase.SUPPRESSION
var _last_phase_name: String = ""
var _supply_timer: float = 10.0
var _dead: bool = false
var _network_target_rotation: float = 0.0
var _shield_hp := 0.0
var _max_shield_hp := 0.0
## 每轮按开盾、破盾、回盾预告推进，独立于激光序号。
var _shield_stamp := -1
var _exposure_left := 0.0
var _laser_used_this_shield := false
var _laser_locked_direction := Vector2.ZERO
var _ultimate_laser_charging: bool = false
var _ultimate_laser_firing: bool = false
var _ultimate_laser_charge_timer: float = 0.0
var _ultimate_laser_fire_timer: float = 0.0
var _ultimate_laser_start: Vector2 = Vector2.ZERO
var _ultimate_laser_end: Vector2 = Vector2.ZERO
var _laser_dot_accumulator: float = 0.0

const ARENA_MARGIN_X: float = 96.0
const ARENA_MARGIN_Y: float = 84.0
const BOSS_VISUAL_SCALE: float = 0.90
const BOSS_TARGET_TTK_SECONDS: float = 42.0
const BOSS_EXPECTED_PLAYER_UPTIME: float = 0.95
const BOSS_CLOSE_ESCAPE_DIST: float = 290.0
const BOSS_CLOSE_ESCAPE_COOLDOWN: float = 0.52
const BOSS_CLOSE_ESCAPE_PUSH: float = 460.0
const BOSS_FIRE_PRESSURE_WINDOW: float = 0.45
const BOSS_FIRE_PRESSURE_HITS: int = 3
const BOSS_DODGE_COOLDOWN: float = 0.62
const BOSS_DODGE_SHIFT: float = 140.0
const BOSS_DODGE_SECONDS := 0.60
const BOSS_PILOT_TREND_SECONDS := 0.14
const BOSS_MAX_PILOT_DRIFT := 48.0
const BOSS_STANDOFF_MIN_DIST: float = 300.0
const BOSS_STANDOFF_MAX_DIST: float = 560.0
const BOSS_LEAD_SECONDS: float = 0.34
const BOSS_MAX_TURN_RATE: float = 8.0
const BOSS_CRUISE_ACCEL: float = 7.5
const BOSS_FEINT_INTERVAL_MIN: float = 0.55
const BOSS_FEINT_INTERVAL_MAX: float = 1.25
const BOSS_HULL_RATIO := 0.70
const BOSS_SHIELD_RATIO := 0.10
const BOSS_EXPOSURE_SECONDS := 4.5
const BOSS_RECHARGE_WARNING := 0.8
const BOSS_ATTACK_GAP_LIMIT := 2.0
const BOSS_LASER_AIM_LOCK := 0.55
const BOSS_ULTIMATE_LASER_CHARGE: float = 2.0
const BOSS_ULTIMATE_LASER_TRAVEL: float = 3.0
const BOSS_ULTIMATE_LASER_WIDTH: float = 110.0
const BOSS_ULTIMATE_LASER_HOLD_SECONDS: float = 10.0
const BOSS_ULTIMATE_LASER_DOT_HP_PER_SEC: float = 10.0
const ULTIMATE_LASER_INNER_RATIO: float = 0.3  ## 内圈比例（秒杀区）

var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")

@onready var _sprite: Sprite2D = $Sprite2D

func _apply_visual_state() -> void:
	if _sprite:
		_sprite.texture = SpriteFactory.create_boss_sprite(_sprite_variant_id)
		_sprite.modulate = Color(1, 1, 1, 1)
		_sprite.scale = Vector2(BOSS_VISUAL_SCALE, BOSS_VISUAL_SCALE)

func setup(level: int) -> void:
	_level = level
	var player_dps := _calc_player_dps()
	_mult = 1.0 + GameState.boss_encounter_count * 0.2
	var level_scale: float = 1.0 + clampf((_level - 5) * 0.03, 0.0, 0.45)
	var old_max := maxf(player_dps * BOSS_TARGET_TTK_SECONDS * BOSS_EXPECTED_PLAYER_UPTIME * _mult * level_scale, 900.0)
	_max_health = old_max * BOSS_HULL_RATIO
	_health = _max_health
	_max_shield_hp = old_max * BOSS_SHIELD_RATIO
	if not _is_network_ghost:
		_shield_stamp = ShieldPhase.RAISED
		_shield_hp = _max_shield_hp
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

func animate_entry(destination: Vector2) -> void:
	_entry_tween = create_tween()
	_entry_tween.tween_property(self, "position", destination, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _stop_entry_motion() -> void:
	if _entry_tween and _entry_tween.is_valid():
		_entry_tween.kill()
	_entry_tween = null

func _physics_process(delta: float) -> void:
	if _dead or not GameState.game_running:
		return
	if _is_network_ghost:
		global_rotation = lerp_angle(global_rotation, _network_target_rotation, 0.45)
		return
	if _health <= 0.0:
		return
	if not _target or not is_instance_valid(_target):
		return

	_sample_pilot_motion(delta)
	_update_phase_from_health(true)
	_tick_shield_cycle(delta)
	if _ultimate_laser_charging or _ultimate_laser_firing:
		_tick_ultimate_laser(delta)
		return
	_update_phase_loops(delta)
	if not (_entry_tween and _entry_tween.is_running()):
		_tick_attack_schedule(delta)
	if _ultimate_laser_charging:
		return
	_feint_timer = max(_feint_timer - delta, 0.0)
	if not has_impact_shield():
		# 给输出窗口一段可持续瞄准的机动，齐射仍由同一个节奏控制。
		_cruise_towards(_ideal_standoff_position(), 0.30, delta)
		_face_target(delta)
		_enforce_arena_bounds()
		return
	_state_timer -= delta
	_rush_cooldown = max(_rush_cooldown - delta, 0.0)
	_dodge_cooldown = max(_dodge_cooldown - delta, 0.0)
	if _fire_pressure_window > 0.0:
		_fire_pressure_window -= delta
		if _fire_pressure_window <= 0.0:
			_clear_fire_pressure()

	match _state:
		State.IDLE: _tick_idle(delta)
		State.CIRCLE: _tick_circle(delta)
		State.ATTACK: _tick_attack(delta)
		State.RETREAT: _tick_retreat(delta)
		State.ENRAGED: _tick_attack(delta)

	var dodging := not _dodge_shift.is_zero_approx()
	if dodging:
		_tick_fireline_dodge(delta)
	else:
		_apply_close_range_escape(delta)

	_enforce_arena_bounds()
	if not dodging:
		_try_start_fireline_dodge()
	if _dodge_shift.is_zero_approx():
		_resolve_corner_stuck(delta)
	else:
		_corner_stuck_time = 0.0
		_last_position = global_position

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
	_cruise_towards(_ideal_standoff_position(), 0.42, delta)
	_face_target(delta)

	if _state_timer <= 0:
		_check_enrage()
		_pick_state()

## ── retreat ──
func _tick_retreat(delta: float) -> void:
	var spd: float = 420.0 * (1.5 if _state == State.ENRAGED else 1.0)
	var away: Vector2 = global_position.direction_to(_target.global_position) * -1.0
	var center: Vector2 = NetworkManager.battle_size(self) * 0.5
	var to_center: Vector2 = global_position.direction_to(center)
	var edge_bias: float = _get_edge_bias()
	var move_dir: Vector2 = (away * (1.0 - edge_bias) + to_center * edge_bias).normalized()
	if _dodge_shift.is_zero_approx():
		_move_with_inertia(move_dir * spd, delta)
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

func _draw() -> void:
	if _health <= 0.0 or (not has_impact_shield() and not is_shield_recharging()):
		return
	var tone := Color("#729cb374") if has_impact_shield() else Color("#afd0e592")
	var arc := 0.62 if has_impact_shield() else 0.28
	for side in 4:
		var start := side * PI * 0.5 + 0.38
		draw_arc(Vector2.ZERO, 72.0, start, start + arc, 14, tone, 1.5, true)

func play_shield_release(world_position: Vector2) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not GameState.game_running:
		return
	# 解除后母舰会继续移动，碎片留在权威解除坐标。
	var world := get_parent() as Node2D
	var burst := preload("res://scripts/shield_shatter_burst.gd").new()
	burst.position = world.to_local(world_position)
	burst.z_index = -1
	world.add_child(burst)
	burst.setup_mothership_release()
	SFX.play_shield_break()
	shield_released.emit()

func _tick_shield_cycle(delta: float) -> void:
	if _exposure_left <= 0.0:
		return
	_exposure_left = maxf(_exposure_left - delta, 0.0)
	if _exposure_left <= 0.00001:
		_exposure_left = 0.0
		_shield_stamp += 1
		_shield_hp = _max_shield_hp
		_laser_used_this_shield = false
		_next_attack = 0
		_publish_shield_state()
	elif _exposure_left <= BOSS_RECHARGE_WARNING + 0.00001 and not is_shield_recharging():
		_shield_stamp += 1
		_publish_shield_state()

func _publish_shield_state() -> void:
	queue_redraw()
	var battle := get_parent()
	if battle and battle.has_method("publish_boss_shield"):
		battle.publish_boss_shield(self)

func _break_shield() -> void:
	_exposure_left = BOSS_EXPOSURE_SECONDS
	_shield_stamp += 1
	_dodge_shift = Vector2.ZERO
	_clear_fire_pressure()
	if _ultimate_laser_charging:
		_finish_ultimate_laser()
	play_shield_release(global_position)
	_publish_shield_state()

func _start_ultimate_laser() -> void:
	_stop_entry_motion()
	_laser_used_this_shield = true
	_ultimate_laser_charging = true
	_ultimate_laser_firing = false
	_ultimate_laser_charge_timer = BOSS_ULTIMATE_LASER_CHARGE
	_ultimate_laser_fire_timer = 0.0
	_ultimate_laser_start = global_position
	_ultimate_laser_end = global_position
	_laser_locked_direction = Vector2.ZERO
	_laser_dot_accumulator = 0.0
	_dodge_shift = Vector2.ZERO
	_clear_fire_pressure()
	_velocity_blend = Vector2.ZERO
	_enter_state(State.ATTACK, BOSS_ULTIMATE_LASER_CHARGE + BOSS_ULTIMATE_LASER_TRAVEL)
	_publish_attack_window()
	var scene := get_tree().current_scene
	## 终局激光是全场最强预警：蓄力就给强震屏，让玩家的注意力被拽过来
	if scene != null and scene.has_method("add_shake"):
		scene.add_shake(scene.SHAKE_LASER_CHARGE)

func _tick_ultimate_laser(delta: float) -> void:
	if _ultimate_laser_charging:
		_ultimate_laser_charge_timer -= delta
		if _laser_locked_direction.is_zero_approx():
			_face_target(delta)
			if _ultimate_laser_charge_timer <= BOSS_LASER_AIM_LOCK:
				_lock_ultimate_laser()
				_publish_attack_window()
		if _ultimate_laser_charge_timer <= 0.0:
			_fire_ultimate_laser()
		return
	if _ultimate_laser_firing:
		var was_sweeping := _ultimate_laser_fire_timer > BOSS_ULTIMATE_LASER_HOLD_SECONDS
		_ultimate_laser_fire_timer -= delta
		if _ultimate_laser_fire_timer > 0.0:
			_apply_continuous_laser_damage(delta)
			if was_sweeping and _ultimate_laser_fire_timer <= BOSS_ULTIMATE_LASER_HOLD_SECONDS:
				_publish_attack_window()
		if _ultimate_laser_fire_timer <= 0.0:
			_finish_ultimate_laser()

func _lock_ultimate_laser() -> void:
	_laser_locked_direction = _ultimate_laser_start.direction_to(_predict_target_position())
	if _laser_locked_direction.is_zero_approx():
		_laser_locked_direction = Vector2.DOWN
	var screen: Vector2 = NetworkManager.battle_size(self)
	_ultimate_laser_end = _ultimate_laser_start + _laser_locked_direction * screen.length() * 1.35
	face_laser_direction(_laser_locked_direction)

func _fire_ultimate_laser() -> void:
	if _laser_locked_direction.is_zero_approx():
		_lock_ultimate_laser()
	_ultimate_laser_charging = false
	_ultimate_laser_firing = true
	_ultimate_laser_fire_timer = BOSS_ULTIMATE_LASER_TRAVEL + BOSS_ULTIMATE_LASER_HOLD_SECONDS
	_publish_attack_window()

func _finish_ultimate_laser() -> void:
	_ultimate_laser_charging = false
	_ultimate_laser_firing = false
	_finished_laser_cycles += 1
	_shoot_timer = 0.55
	_publish_attack_window()

func face_laser_direction(direction: Vector2) -> void:
	global_rotation = direction.angle() + PI * 0.5
	_network_target_rotation = global_rotation
	reset_physics_interpolation()

func apply_network_laser_lock(direction: Vector2) -> void:
	_laser_locked_direction = direction.normalized()
	face_laser_direction(_laser_locked_direction)

func _publish_attack_window() -> void:
	var battle := get_parent()
	if battle and battle.has_method("publish_boss_attack_window"):
		battle.publish_boss_attack_window(self)

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
			## 外圈 - 每秒固定伤害（累积模式，确保稳定触发）
			_laser_dot_accumulator += BOSS_ULTIMATE_LASER_DOT_HP_PER_SEC * delta
			if _laser_dot_accumulator >= 1.0 and player.has_method("take_damage"):
				player.take_damage(int(_laser_dot_accumulator))
				_laser_dot_accumulator -= int(_laser_dot_accumulator)

func _distance_to_beam_center(point: Vector2) -> float:
	var beam_end := _ultimate_laser_end
	## 推进阶段：只检测光束当前尖端到起点的范围
	if _ultimate_laser_firing and _ultimate_laser_fire_timer > BOSS_ULTIMATE_LASER_HOLD_SECONDS:
		var elapsed := BOSS_ULTIMATE_LASER_TRAVEL + BOSS_ULTIMATE_LASER_HOLD_SECONDS - _ultimate_laser_fire_timer
		var travel_progress := clampf(elapsed / BOSS_ULTIMATE_LASER_TRAVEL, 0.0, 1.0)
		beam_end = _ultimate_laser_start.lerp(_ultimate_laser_end, travel_progress)
	var ab := beam_end - _ultimate_laser_start
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
	if emit_event:
		phase_changed.emit(get_phase_name())
		## 阶段切换是节奏转折点，给中等震屏让玩家"感觉到局面变了"
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("add_shake"):
			scene.add_shake(scene.SHAKE_BOSS_PHASE)

func _update_phase_loops(delta: float) -> void:
	if _phase != BossPhase.OVERLOAD:
		return
	_supply_timer -= delta
	if _supply_timer <= 0.0:
		_supply_timer = 10.0
		_drop_supply_fragments()

func _pick_new_strafe_bias() -> void:
	if not is_inside_tree():
		_strafe_bias = Vector2(randf_range(-30.0, 30.0), randf_range(-12.0, 24.0))
		_feint_timer = randf_range(BOSS_FEINT_INTERVAL_MIN, BOSS_FEINT_INTERVAL_MAX)
		return
	var screen := NetworkManager.battle_size(self)
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
	if not _dodge_shift.is_zero_approx():
		return
	var desired := global_position.direction_to(_clamp_to_arena(target_pos))
	var speed: float = (210.0 + _level * 9.0) * speed_scale * (1.22 if _state == State.ENRAGED else 1.0)
	_move_with_inertia(desired * speed, delta)

func _move_with_inertia(desired_velocity: Vector2, delta: float) -> void:
	_velocity_blend = _velocity_blend.lerp(desired_velocity, BOSS_CRUISE_ACCEL * delta)
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

## 发起攻击只由这里计时，绕行、后退和卡边均不会拖延齐射。
func _tick_attack_schedule(delta: float) -> void:
	_shoot_timer -= delta
	if _shoot_timer > 0.0:
		return
	if _next_attack == 0:
		_do_aimed_shot()
		_next_attack = 1
	elif _next_attack == 1:
		_do_fan_spread()
		_next_attack = 2 if has_impact_shield() and not _laser_used_this_shield else 0
	elif has_impact_shield() and not _laser_used_this_shield:
		_start_ultimate_laser()
		_next_attack = 0
	else:
		_do_aimed_shot()
		_next_attack = 1
	_shoot_timer = minf(1.25 / _phase_speed_mult(), BOSS_ATTACK_GAP_LIMIT)

func _do_aimed_shot() -> void:
	var count := 2 if _phase == BossPhase.SUPPRESSION else 3
	var angle := global_position.angle_to_point(_predict_target_position())
	for i in count:
		var a := angle + (float(i) - (count - 1) * 0.5) * 0.06
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), 620.0, Color(1.0, 0.3, 0.3))

func _do_fan_spread() -> void:
	var count := 5 if _phase == BossPhase.SUPPRESSION else 7
	var base := global_position.angle_to_point(_predict_target_position())
	var spread := PI * (0.34 if _phase == BossPhase.SUPPRESSION else 0.48)
	for i in count:
		if i == count / 2:
			continue
		var a := base - spread * 0.5 + spread * i / (count - 1)
		_spawn_enemy_bullet(global_position + Vector2.from_angle(a) * 20, a, _get_boss_attack_damage(), 560.0, Color(0.4, 0.5, 1.0))

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

func _drop_supply_fragments() -> void:
	var types: Array[String] = ["heal", "speed", "power", "heal"]
	for i in range(types.size()):
		var pos := global_position + Vector2.from_angle(i * TAU / types.size()) * 70.0
		get_tree().current_scene.spawn_boss_fragment(types[i], pos)

func _queue_core_fragments(death_pos: Vector2) -> void:
	var types: Array[String] = ["core", "heal", "speed", "power", "core", "heal"]
	var alive_ids := GameState.get_alive_player_ids()
	var battle := get_tree().current_scene
	for i in range(types.size()):
		var assigned_peer_id := 0
		if types[i] == "core" and not alive_ids.is_empty():
			assigned_peer_id = alive_ids[i % alive_ids.size()]
		var pos := death_pos + Vector2.from_angle(i * TAU / types.size()) * 92.0
		# 记录当帧的落点，由本场战斗在物理回调结束后创建碰撞形状。
		battle.spawn_boss_fragment.call_deferred(types[i], pos, assigned_peer_id)

## ── 受击 ────────────────────────────────────────────────────

func _clamp_to_arena(pos: Vector2) -> Vector2:
	var screen := NetworkManager.battle_size(self)
	return Vector2(
		clampf(pos.x, ARENA_MARGIN_X, screen.x - ARENA_MARGIN_X),
		clampf(pos.y, ARENA_MARGIN_Y, screen.y - ARENA_MARGIN_Y)
	)

func _enforce_arena_bounds() -> void:
	global_position = _clamp_to_arena(global_position)

func _get_edge_bias() -> float:
	var screen := NetworkManager.battle_size(self)
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
		var center: Vector2 = NetworkManager.battle_size(self) * 0.5
		var nudge: Vector2 = global_position.direction_to(center) * (210.0 * delta)
		global_position = _clamp_to_arena(global_position + nudge)
		_enter_state(State.CIRCLE, randf_range(0.55, 1.0))
		_corner_stuck_time = 0.0
	_last_position = global_position

func _sample_pilot_motion(delta: float) -> void:
	# 房主上的加入端机体由位置同步驱动，它的 CharacterBody2D.velocity 不代表实际走位。
	for pilot: Node2D in get_tree().get_nodes_in_group("player"):
		var id := pilot.get_instance_id()
		var current := pilot.global_position
		var previous: Vector2 = _pilot_trails.get(id, current)
		_pilot_trails[id] = previous.lerp(current, minf(delta / BOSS_PILOT_TREND_SECONDS, 1.0))

func _fire_pressure_pilot() -> Node2D:
	var source := _target
	var most_hits := 0
	for pilot: Node2D in get_tree().get_nodes_in_group("player"):
		var peer_id: int = pilot.peer_id
		var hits: int = _pressure_hits_by_peer.get(peer_id, 0)
		if hits > most_hits and GameState.is_player_alive(peer_id) and not GameState.is_player_downed(peer_id):
			most_hits = hits
			source = pilot
	return source

func _clear_fire_pressure() -> void:
	_fire_pressure_hits = 0
	_fire_pressure_window = 0.0
	_pressure_hits_by_peer.clear()

func _try_start_fireline_dodge() -> void:
	if _dodge_cooldown > 0.0 or _fire_pressure_hits < BOSS_FIRE_PRESSURE_HITS:
		return
	_stop_entry_motion()
	var pilot := _fire_pressure_pilot()
	var side := pilot.global_position.direction_to(global_position).orthogonal()
	if side.is_zero_approx():
		side = Vector2.LEFT
	var trail: Vector2 = _pilot_trails.get(pilot.get_instance_id(), pilot.global_position)
	var drift := (pilot.global_position - trail).limit_length(BOSS_MAX_PILOT_DRIFT)
	var left := _clamp_to_arena(global_position + side * BOSS_DODGE_SHIFT)
	var right := _clamp_to_arena(global_position - side * BOSS_DODGE_SHIFT)
	var destination := left if _score_dodge_position(left, drift) >= _score_dodge_position(right, drift) else right
	_dodge_shift = destination - global_position
	_dodge_elapsed = 0.0
	_enter_state(State.CIRCLE, randf_range(0.45, 0.85))
	_dodge_cooldown = BOSS_DODGE_COOLDOWN
	_clear_fire_pressure()

func _tick_fireline_dodge(delta: float) -> void:
	var previous := smoothstep(0.0, BOSS_DODGE_SECONDS, _dodge_elapsed)
	_dodge_elapsed = minf(_dodge_elapsed + delta, BOSS_DODGE_SECONDS)
	var progress := smoothstep(0.0, BOSS_DODGE_SECONDS, _dodge_elapsed)
	_move_with_inertia(_dodge_shift * (progress - previous) / delta, delta)
	if _dodge_elapsed >= BOSS_DODGE_SECONDS:
		_dodge_shift = Vector2.ZERO

func _score_dodge_position(pos: Vector2, drift: Vector2) -> float:
	var screen := NetworkManager.battle_size(self)
	var margin_x: float = min(pos.x - ARENA_MARGIN_X, screen.x - ARENA_MARGIN_X - pos.x)
	var margin_y: float = min(pos.y - ARENA_MARGIN_Y, screen.y - ARENA_MARGIN_Y - pos.y)
	var shift := pos - global_position
	# 落点留出后续机动空间，并避开施压者正在横移的一侧。
	return shift.length() + minf(margin_x, margin_y) * 0.5 - shift.dot(drift) / BOSS_DODGE_SHIFT

func take_damage(amount: float = 1.0, killer_peer_id: int = -1) -> void:
	if _dead or _health <= 0.0 or _is_network_ghost:
		return
	var applied: float = max(amount, 0.0)
	if applied <= 0.0:
		return
	if has_impact_shield():
		_shield_hp = maxf(0.0, _shield_hp - applied)
		if _shield_hp == 0.0:
			_break_shield()
		else:
			SFX.play_shield_hit()
			_record_fire_pressure(killer_peer_id)
		return
	_health = maxf(0.0, _health - applied)
	if _health == 0.0:
		die()
		return
	_hit_flash()
	_hit_recoil()

func _record_fire_pressure(killer_peer_id: int) -> void:
	_fire_pressure_hits += 1
	_fire_pressure_window = BOSS_FIRE_PRESSURE_WINDOW
	if killer_peer_id > 0:
		_pressure_hits_by_peer[killer_peer_id] = _pressure_hits_by_peer.get(killer_peer_id, 0) + 1

func _hit_flash() -> void:
	_sprite.modulate = Color(1.8, 1.28, 1.16)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1), 0.08)

func _hit_recoil() -> void:
	if _hit_recoil_tween and _hit_recoil_tween.is_running():
		return
	var squash := Vector2(BOSS_VISUAL_SCALE * 1.08, BOSS_VISUAL_SCALE * 0.95)
	var restore := Vector2(BOSS_VISUAL_SCALE, BOSS_VISUAL_SCALE)
	_hit_recoil_tween = create_tween()
	_hit_recoil_tween.tween_property(_sprite, "scale", squash, 0.03).set_ease(Tween.EASE_OUT)
	_hit_recoil_tween.tween_property(_sprite, "scale", restore, 0.08).set_ease(Tween.EASE_OUT)
	_hit_recoil_tween.finished.connect(func():
		_hit_recoil_tween = null
	)

func die() -> void:
	if _dead:
		return
	_dead = true
	_ultimate_laser_charging = false
	_ultimate_laser_firing = false
	var death_pos := global_position
	_queue_core_fragments(death_pos)
	GameState.add_score(200 * _level, -1)
	play_death_feedback()
	boss_died.emit()
	queue_free()

func play_death_feedback() -> void:
	_spawn_explosion.call_deferred(global_position)

func _spawn_explosion(death_pos: Vector2) -> void:
	if not is_inside_tree() or not GameState.game_running:
		return
	var battle := get_tree().current_scene
	if not battle or battle.is_queued_for_deletion() or not battle.is_ancestor_of(self):
		return
	var exp = _explosion_scene.instantiate()
	battle.add_child(exp)
	exp.global_position = death_pos
	exp.scale = Vector2(4, 4)
	SFX.play_explosion()
