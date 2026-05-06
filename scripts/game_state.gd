extends Node

signal score_changed(new_score)
signal level_changed(new_level)
signal health_changed(current_health, max_health)
signal game_over(final_score, final_level)
signal powerup_collected(powerup_type)
signal boss_spawn_requested
signal shield_changed(layers)
signal skill_used

var score: int = 0
var level: int = 1
var kills: int = 0
var total_kills: int = 0
var last_boss_threshold: int = 0
var boss_encounter_count: int = 0
var post_boss_multiplier: float = 1.0
var current_health: int = 3
var max_health: int = 3
var shield_layers: int = 0
var game_running: bool = false
var death_message: String = ""

var kills_for_next_level: int = 10
var shoot_level: int = 1
var shoot_speed_level: int = 1
var bullet_power_level: int = 1
var skill_cooldown: float = 0.0
const SKILL_COOLDOWN_MAX: float = 15.0

func reset_game() -> void:
	score = 0
	level = 1
	kills = 0
	total_kills = 0
	last_boss_threshold = 0
	boss_encounter_count = 0
	post_boss_multiplier = 1.0
	current_health = 3
	max_health = 3
	shield_layers = 0
	death_message = ""
	game_running = true
	shoot_level = 1
	shoot_speed_level = 1
	bullet_power_level = 1
	skill_cooldown = 0.0
	kills_for_next_level = 10

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
	if total_kills > 0 and total_kills % 30 == 0 and total_kills != last_boss_threshold:
		last_boss_threshold = total_kills
		boss_spawn_requested.emit()

func level_up() -> void:
	level += 1
	kills = 0
	kills_for_next_level = 10 + level * 5
	bullet_power_level = min(bullet_power_level + 1, 15)
	max_health += 1
	current_health = min(current_health + 1, max_health)
	health_changed.emit(current_health, max_health)
	level_changed.emit(level)
	SFX.play_ui_confirm()

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
	if current_health >= max_health:
		max_health += amount
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)
	SFX.play_ui_select()

func collect_powerup(type: String) -> void:
	powerup_collected.emit(type)
	SFX.play_ui_confirm()
	match type:
		"spread":
			if shoot_level >= 15:
				heal(1)
			else:
				shoot_level = min(shoot_level + 1, 15)
		"speed":
			if shoot_speed_level >= 15:
				heal(1)
			else:
				shoot_speed_level = min(shoot_speed_level + 1, 15)
		"power":
			if bullet_power_level >= 15:
				heal(1)
			else:
				bullet_power_level = min(bullet_power_level + 1, 15)
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

func get_skill_cooldown_ratio() -> float:
	if skill_cooldown <= 0:
		return 0.0
	return skill_cooldown / SKILL_COOLDOWN_MAX

func get_bullet_count() -> int:
	return min(2 + shoot_level / 3, 8)

func get_shoot_cooldown() -> float:
	return max(0.27 - shoot_speed_level * 0.018, 0.08)

func get_bullet_damage() -> int:
	return bullet_power_level

func get_bullet_spread_angle() -> float:
	return max(30.0 - shoot_level * 4.0, 10.0)
