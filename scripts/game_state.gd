extends Node

signal score_changed(new_score)
signal level_changed(new_level)
signal health_changed(current_health, max_health)
signal game_over(final_score, final_level)
signal powerup_collected(powerup_type)
signal shield_changed(layers)
signal skill_used
signal elite_spawn_requested
signal boss_spawn_requested(boss_level)
signal boss_defeated

var score: int = 0
var level: int = 1
var kills: int = 0
var total_kills: int = 0
var last_elite_threshold: int = 0
var elite_encounter_count: int = 0
var post_elite_multiplier: float = 1.0
var current_health: int = 2000
var max_health: int = 2000
var shield_layers: int = 0
var game_running: bool = false
var death_message: String = ""

var kills_for_next_level: int = 10
var shoot_level: int = 1
var shoot_speed_level: int = 1
var bullet_power_level: int = 1
var skill_cooldown: float = 0.0
const SKILL_COOLDOWN_MAX: float = 15.0

var laser_cooldown: float = 0.0
const LASER_COOLDOWN_MAX: float = 10.0

## Boss 系统
var boss_active: bool = false
var boss_encounter_count: int = 0
var last_boss_level: int = 0

## Boss 奖励属性（击败后永久增加）
var laser_cd_bonus: float = 0.0        # 激光冷却减少总和
var extra_bullet_count: int = 0        # 额外子弹数量
var extra_damage_bonus: int = 0        # 额外子弹伤害
var move_speed_bonus: float = 0.0      # 移速加成百分比

func reset_game() -> void:
	score = 0
	level = 1
	kills = 0
	total_kills = 0
	current_health = 2000
	max_health = 2000
	shield_layers = 0
	death_message = ""
	game_running = true
	shoot_level = 1
	shoot_speed_level = 1
	bullet_power_level = 1
	skill_cooldown = 0.0
	laser_cooldown = 0.0
	kills_for_next_level = 10
	last_elite_threshold = 0
	elite_encounter_count = 0
	post_elite_multiplier = 1.0
	boss_active = false
	boss_encounter_count = 0
	last_boss_level = 0
	laser_cd_bonus = 0.0
	extra_bullet_count = 0
	extra_damage_bonus = 0
	move_speed_bonus = 0.0

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func add_kill() -> void:
	kills += 1
	total_kills += 1
	add_score(10 * level)
	if kills >= kills_for_next_level:
		level_up()
	if total_kills % 10 == 0:
		shield_layers = min(shield_layers + 1, 30)
		shield_changed.emit(shield_layers)
	if total_kills > 0 and total_kills % 20 == 0 and total_kills != last_elite_threshold:
		last_elite_threshold = total_kills
		elite_spawn_requested.emit()

func level_up() -> void:
	level += 1
	kills = 0
	kills_for_next_level = 10 + level * 5
	bullet_power_level = min(bullet_power_level + 1, 50)
	current_health = min(current_health + 1, max_health)
	health_changed.emit(current_health, max_health)
	level_changed.emit(level)
	SFX.play_ui_confirm()
	if level > 0 and level % 5 == 0 and level != last_boss_level:
		last_boss_level = level
		boss_spawn_requested.emit(level)

func take_damage(amount: int = 1) -> void:
	if shield_layers > 0:
		var absorbed: int = min(shield_layers, amount)
		shield_layers -= absorbed
		shield_changed.emit(shield_layers)
		amount -= absorbed
	if amount > 0:
		current_health = max(current_health - amount, 0)
		health_changed.emit(current_health, max_health)
		SFX.play_player_hurt()
		if current_health <= 0:
			game_over.emit(score, level)

func heal(amount: int = 1) -> void:
	if current_health < max_health:
		current_health = min(current_health + amount, max_health)
		health_changed.emit(current_health, max_health)
	SFX.play_ui_select()

func collect_powerup(type: String) -> void:
	powerup_collected.emit(type)
	SFX.play_ui_confirm()
	match type:
		"spread":
			if shoot_level < 10:
				shoot_level = min(shoot_level + 1, 10)
		"speed":
			if shoot_speed_level < 15:
				shoot_speed_level = min(shoot_speed_level + 1, 15)
		"power":
			if bullet_power_level >= 15:
				heal(1)
			else:
				bullet_power_level = min(bullet_power_level + 1, 50)
		"heal":
			heal(max(ceil(max_health * 0.1), 1))
		"bomb":
			pass

func use_skill() -> bool:
	if skill_cooldown > 0 or not game_running:
		return false
	skill_cooldown = SKILL_COOLDOWN_MAX
	skill_used.emit()
	return true

func tick_skill_cooldown(delta: float) -> void:
	if skill_cooldown > 0:
		skill_cooldown = max(skill_cooldown - delta, 0.0)

func use_laser() -> bool:
	if laser_cooldown > 0 or not game_running:
		return false
	laser_cooldown = get_laser_cooldown_max()
	return true

func tick_laser_cooldown(delta: float) -> void:
	if laser_cooldown > 0:
		laser_cooldown = max(laser_cooldown - delta, 0.0)

func get_laser_damage() -> int:
	var base: int = 5
	var mul: int = level / 10
	return base * int(pow(2, mul))

func get_laser_cooldown_max() -> float:
	return max(LASER_COOLDOWN_MAX - laser_cd_bonus, 5.0)

func get_skill_cooldown_ratio() -> float:
	if skill_cooldown <= 0:
		return 0.0
	return skill_cooldown / SKILL_COOLDOWN_MAX

func get_bullet_count() -> int:
	return min(2 + shoot_level / 3 + extra_bullet_count, 12)

func get_shoot_cooldown() -> float:
	return max(0.27 - shoot_speed_level * 0.018, 0.08)

func get_bullet_damage() -> int:
	return 3 + bullet_power_level + extra_damage_bonus

func get_bullet_spread_angle() -> float:
	return max(30.0 - shoot_level * 4.0, 10.0)

func get_move_speed_multiplier() -> float:
	return 1.0 + move_speed_bonus

func on_boss_started() -> void:
	boss_active = true
	boss_encounter_count += 1

func on_boss_killed() -> void:
	boss_active = false
	boss_defeated.emit()

func force_set_boss_active(v: bool) -> void:
	boss_active = v
