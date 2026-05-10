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
signal boss_reward_applied

const START_HEALTH: int = 10
const HEALTH_CAP: int = 2000

var score: int = 0
var level: int = 1
var kills: int = 0
var total_kills: int = 0
var last_elite_threshold: int = 0
var elite_encounter_count: int = 0
var post_elite_multiplier: float = 1.0
var current_health: int = START_HEALTH
var max_health: int = START_HEALTH
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

## ── 网络同步 ──────────────────────────────────────────────────
var _sync_dirty: bool = false
var _sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.1  # 每 100ms 发送一次

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not _sync_dirty:
		return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_sync_dirty = false
		_rpc_sync_game_state.rpc(_to_dict())

func _to_dict() -> Dictionary:
	return {
		"score": score,
		"level": level,
		"kills": kills,
		"total_kills": total_kills,
		"current_health": current_health,
		"max_health": max_health,
		"shield_layers": shield_layers,
		"game_running": game_running,
		"shoot_level": shoot_level,
		"shoot_speed_level": shoot_speed_level,
		"bullet_power_level": bullet_power_level,
		"skill_cooldown": skill_cooldown,
		"laser_cooldown": laser_cooldown,
		"boss_active": boss_active,
		"elite_encounter_count": elite_encounter_count,
		"post_elite_multiplier": post_elite_multiplier,
		"last_elite_threshold": last_elite_threshold,
		"laser_cd_bonus": laser_cd_bonus,
		"extra_bullet_count": extra_bullet_count,
		"extra_damage_bonus": extra_damage_bonus,
		"move_speed_bonus": move_speed_bonus,
		"kills_for_next_level": kills_for_next_level,
		"last_boss_level": last_boss_level,
		"boss_encounter_count": boss_encounter_count,
	}

@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_game_state(data: Dictionary) -> void:
	_from_dict(data)

## ── 伤害 RPC ──────────────────────────────────────────────────

## Client → Host：报告敌人受击
@rpc("any_peer", "reliable")
func _rpc_report_enemy_hit(entity_id: int, damage: int) -> void:
	if not multiplayer.is_server():
		return
	var scene = get_tree().current_scene
	if scene and scene.has_method("_on_network_enemy_hit"):
		scene._on_network_enemy_hit(entity_id, damage)

## Client → Host：报告玩家受击
@rpc("any_peer", "reliable")
func _rpc_report_player_hit(damage: int, target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var scene = get_tree().current_scene
	if scene and scene.has_method("_on_network_player_hit"):
		scene._on_network_player_hit(damage, target_peer_id)

func _from_dict(data: Dictionary) -> void:
	score = data.get("score", 0)
	level = data.get("level", 1)
	kills = data.get("kills", 0)
	total_kills = data.get("total_kills", 0)
	current_health = data.get("current_health", START_HEALTH)
	max_health = data.get("max_health", START_HEALTH)
	max_health = clamp(max_health, START_HEALTH, HEALTH_CAP)
	current_health = clamp(current_health, 0, max_health)
	shield_layers = data.get("shield_layers", 0)
	game_running = data.get("game_running", false)
	shoot_level = data.get("shoot_level", 1)
	shoot_speed_level = data.get("shoot_speed_level", 1)
	bullet_power_level = data.get("bullet_power_level", 1)
	skill_cooldown = data.get("skill_cooldown", 0.0)
	laser_cooldown = data.get("laser_cooldown", 0.0)
	boss_active = data.get("boss_active", false)
	elite_encounter_count = data.get("elite_encounter_count", 0)
	post_elite_multiplier = data.get("post_elite_multiplier", 1.0)
	last_elite_threshold = data.get("last_elite_threshold", 0)
	laser_cd_bonus = data.get("laser_cd_bonus", 0.0)
	extra_bullet_count = data.get("extra_bullet_count", 0)
	extra_damage_bonus = data.get("extra_damage_bonus", 0)
	move_speed_bonus = data.get("move_speed_bonus", 0.0)
	kills_for_next_level = data.get("kills_for_next_level", 10)
	last_boss_level = data.get("last_boss_level", 0)
	boss_encounter_count = data.get("boss_encounter_count", 0)
	## 重新发射信号让 UI 更新
	score_changed.emit(score)
	level_changed.emit(level)
	health_changed.emit(current_health, max_health)
	shield_changed.emit(shield_layers)

func _mark_dirty() -> void:
	if multiplayer.is_server():
		_sync_dirty = true

func reset_game() -> void:
	score = 0
	level = 1
	kills = 0
	total_kills = 0
	current_health = START_HEALTH
	max_health = START_HEALTH
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
	health_changed.emit(current_health, max_health)
	_mark_dirty()

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)
	_mark_dirty()

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
	_mark_dirty()

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
	_mark_dirty()

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
	_mark_dirty()

func heal(amount: int = 1) -> void:
	if amount <= 0:
		return
	if current_health >= max_health:
		if max_health < HEALTH_CAP:
			max_health = min(max_health + amount, HEALTH_CAP)
			current_health = min(current_health + amount, max_health)
			health_changed.emit(current_health, max_health)
	else:
		current_health = min(current_health + amount, max_health)
		health_changed.emit(current_health, max_health)
	SFX.play_ui_select()
	_mark_dirty()

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
			heal(1)
		"bomb":
			pass
	_mark_dirty()

func use_skill() -> bool:
	if skill_cooldown > 0 or not game_running:
		return false
	skill_cooldown = SKILL_COOLDOWN_MAX
	skill_used.emit()
	_mark_dirty()
	return true

func tick_skill_cooldown(delta: float) -> void:
	if skill_cooldown > 0:
		skill_cooldown = max(skill_cooldown - delta, 0.0)
		_mark_dirty()

func use_laser() -> bool:
	if laser_cooldown > 0 or not game_running:
		return false
	laser_cooldown = get_laser_cooldown_max()
	_mark_dirty()
	return true

func tick_laser_cooldown(delta: float) -> void:
	if laser_cooldown > 0:
		laser_cooldown = max(laser_cooldown - delta, 0.0)
		_mark_dirty()

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
	_mark_dirty()

func on_boss_killed() -> void:
	boss_active = false
	boss_defeated.emit()
	_mark_dirty()

func force_set_boss_active(v: bool) -> void:
	boss_active = v

func notify_boss_reward_applied() -> void:
	boss_reward_applied.emit()

func stop_game() -> void:
	if not game_running:
		return
	game_running = false
	_mark_dirty()
