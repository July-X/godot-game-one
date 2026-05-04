extends Node

signal score_changed(new_score)
signal level_changed(new_level)
signal health_changed(current_health, max_health)
signal game_over(final_score, final_level)
signal powerup_collected(powerup_type)
signal boss_spawn_requested

var score: int = 0
var level: int = 1
var kills: int = 0
var total_kills: int = 0
var last_boss_threshold: int = 0
var current_health: int = 3
var max_health: int = 3
var game_running: bool = false

var kills_for_next_level: int = 10
var shoot_level: int = 1
var shoot_speed_level: int = 1
var bullet_power_level: int = 1

func reset_game() -> void:
	score = 0
	level = 1
	kills = 0
	total_kills = 0
	last_boss_threshold = 0
	current_health = 3
	max_health = 3
	game_running = true
	shoot_level = 1
	shoot_speed_level = 1
	bullet_power_level = 1
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
	if total_kills > 0 and total_kills % 30 == 0 and total_kills != last_boss_threshold:
		last_boss_threshold = total_kills
		boss_spawn_requested.emit()

func level_up() -> void:
	level += 1
	kills = 0
	kills_for_next_level = 10 + level * 5
	level_changed.emit(level)
	SFX.play_ui_confirm()

func take_damage(amount: int = 1) -> void:
	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	SFX.play_player_hurt()
	if current_health <= 0:
		game_over.emit(score, level)

func heal(amount: int = 1) -> void:
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)
	SFX.play_ui_select()

func collect_powerup(type: String) -> void:
	powerup_collected.emit(type)
	SFX.play_ui_confirm()
	match type:
		"spread":
			shoot_level = min(shoot_level + 1, 5)
		"speed":
			shoot_speed_level = min(shoot_speed_level + 1, 5)
		"power":
			bullet_power_level = min(bullet_power_level + 1, 5)
		"heal":
			heal(max(ceil(max_health * 0.1), 1))
		"bomb":
			## 清屏炸弹，由主场景处理
			pass

func get_bullet_count() -> int:
	return min(1 + shoot_level, 6)

func get_shoot_cooldown() -> float:
	return max(0.3 - shoot_speed_level * 0.04, 0.08)

func get_bullet_damage() -> int:
	return bullet_power_level

func get_bullet_spread_angle() -> float:
	return max(30.0 - shoot_level * 4.0, 10.0)
