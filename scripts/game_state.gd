extends Node

signal score_changed(new_score)
signal level_changed(new_level)
signal health_changed(current_health, max_health)
signal game_over(final_score, final_level)
signal powerup_collected(powerup_type)
signal shield_changed(peer_id, layers)
signal skill_used(peer_id)
signal laser_used(peer_id)
signal player_scores_changed(scores, total_score)
signal elite_spawn_requested
signal boss_spawn_requested(boss_level)
signal boss_defeated
signal boss_reward_applied

const START_HEALTH: int = 50
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

## 多人：按玩家独立属性（key=peer_id 字符串）
var _player_states: Dictionary = {}
var _player_scores: Dictionary = {}

## ── 网络同步 ──────────────────────────────────────────────────
var _sync_dirty: bool = false
var _sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.1  # 每 100ms 发送一次
var _server_player_states: Dictionary = {}
var _pending_skill_ack: Dictionary = {}
var _pending_laser_ack: Dictionary = {}

func _local_peer_id() -> int:
	if NetworkManager.is_online() and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return 1

func _peer_key(peer_id: int) -> String:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	return str(pid)

func _new_player_state() -> Dictionary:
	return {
		"current_health": START_HEALTH,
		"max_health": START_HEALTH,
		"is_alive": true,
		"shield_layers": 0,
		"shoot_level": 1,
		"shoot_speed_level": 1,
		"bullet_power_level": 1,
		"skill_cooldown": 0.0,
		"laser_cooldown": 0.0,
		"laser_cd_bonus": 0.0,
		"extra_bullet_count": 0,
		"extra_damage_bonus": 0,
		"move_speed_bonus": 0.0,
	}

func _alive_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for key: String in _player_states.keys():
		if not key.is_valid_int():
			continue
		var s: Dictionary = _player_states[key]
		if bool(s.get("is_alive", true)):
			ids.append(int(key))
	ids.sort()
	return ids

func _emit_shield_changed_for_peer(peer_id: int) -> void:
	shield_changed.emit(peer_id, get_shield_layers(peer_id))

func _emit_scores_changed() -> void:
	player_scores_changed.emit(_player_scores.duplicate(true), score)

func _add_score_to_peer(peer_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var key := _peer_key(peer_id)
	_player_scores[key] = int(_player_scores.get(key, 0)) + amount
	score += amount

func _state(peer_id: int = -1) -> Dictionary:
	var key := _peer_key(peer_id)
	if not _player_states.has(key):
		_player_states[key] = _new_player_state()
	return _player_states[key]

func _sync_local_view() -> void:
	var s := _state(_local_peer_id())
	current_health = s.current_health
	max_health = s.max_health
	shield_layers = s.shield_layers
	shoot_level = s.shoot_level
	shoot_speed_level = s.shoot_speed_level
	bullet_power_level = s.bullet_power_level
	skill_cooldown = s.skill_cooldown
	laser_cooldown = s.laser_cooldown
	laser_cd_bonus = s.laser_cd_bonus
	extra_bullet_count = s.extra_bullet_count
	extra_damage_bonus = s.extra_damage_bonus
	move_speed_bonus = s.move_speed_bonus

func _is_local_peer(peer_id: int) -> bool:
	return (peer_id if peer_id > 0 else _local_peer_id()) == _local_peer_id()

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
		"game_running": game_running,
		"boss_active": boss_active,
		"elite_encounter_count": elite_encounter_count,
		"post_elite_multiplier": post_elite_multiplier,
		"last_elite_threshold": last_elite_threshold,
		"kills_for_next_level": kills_for_next_level,
		"last_boss_level": last_boss_level,
		"boss_encounter_count": boss_encounter_count,
		"player_states": _player_states.duplicate(true),
		"player_scores": _player_scores.duplicate(true),
	}

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_game_state(data: Dictionary) -> void:
	_from_dict(data)

func force_sync_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id > 0:
		_rpc_sync_game_state.rpc_id(peer_id, _to_dict())
	else:
		_rpc_sync_game_state.rpc(_to_dict())

## ── 伤害 RPC ──────────────────────────────────────────────────

## Host → Client：播放音效
@rpc("authority", "unreliable", "call_remote")
func _rpc_play_sfx(sound: String) -> void:
	match sound:
		"enemy_death":
			if SFX and SFX.has_method("play_enemy_death"):
				SFX.play_enemy_death()
		"player_hurt":
			if SFX and SFX.has_method("play_player_hurt"):
				SFX.play_player_hurt()
			if multiplayer.is_server():
				_rpc_play_sfx.rpc("player_hurt")
		"explosion":
			if SFX and SFX.has_method("play_explosion"):
				SFX.play_explosion()

## Client → Host：报告敌人受击
@rpc("any_peer", "reliable")
func _rpc_report_enemy_hit(entity_id: int, damage: int, attacker_peer_id: int = -1) -> void:
	if not multiplayer.is_server():
		return
	var scene = get_tree().current_scene
	if scene and scene.has_method("_on_network_enemy_hit"):
		scene._on_network_enemy_hit(entity_id, damage, attacker_peer_id)

## Client → Host：报告玩家受击
@rpc("any_peer", "reliable")
func _rpc_report_player_hit(damage: int, target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var scene = get_tree().current_scene
	if scene and scene.has_method("_on_network_player_hit"):
		scene._on_network_player_hit(damage, target_peer_id)

@rpc("any_peer", "reliable")
func _rpc_request_use_skill(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var owner_peer_id := multiplayer.get_remote_sender_id()
	if peer_id != owner_peer_id:
		return
	if not use_skill(peer_id):
		return
	_rpc_confirm_skill_used.rpc_id(owner_peer_id, peer_id)

@rpc("authority", "reliable", "call_remote")
func _rpc_confirm_skill_used(peer_id: int) -> void:
	if _local_peer_id() != peer_id:
		return
	_pending_skill_ack.erase(_peer_key(peer_id))
	var s := _state(peer_id)
	s.skill_cooldown = SKILL_COOLDOWN_MAX
	_player_states[_peer_key(peer_id)] = s
	_sync_local_view()
	skill_used.emit(peer_id)

@rpc("any_peer", "reliable")
func _rpc_request_use_laser(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var owner_peer_id := multiplayer.get_remote_sender_id()
	if peer_id != owner_peer_id:
		return
	if not use_laser(peer_id):
		return
	_rpc_confirm_laser_used.rpc_id(owner_peer_id, peer_id, get_laser_cooldown_max(peer_id))

@rpc("authority", "reliable", "call_remote")
func _rpc_confirm_laser_used(peer_id: int, cooldown: float) -> void:
	if _local_peer_id() != peer_id:
		return
	_pending_laser_ack.erase(_peer_key(peer_id))
	var s := _state(peer_id)
	s.laser_cooldown = cooldown
	_player_states[_peer_key(peer_id)] = s
	_sync_local_view()
	laser_used.emit(peer_id)

func _from_dict(data: Dictionary) -> void:
	score = data.get("score", 0)
	level = data.get("level", 1)
	kills = data.get("kills", 0)
	total_kills = data.get("total_kills", 0)
	game_running = data.get("game_running", false)
	boss_active = data.get("boss_active", false)
	elite_encounter_count = data.get("elite_encounter_count", 0)
	post_elite_multiplier = data.get("post_elite_multiplier", 1.0)
	last_elite_threshold = data.get("last_elite_threshold", 0)
	kills_for_next_level = data.get("kills_for_next_level", 10)
	last_boss_level = data.get("last_boss_level", 0)
	boss_encounter_count = data.get("boss_encounter_count", 0)
	_player_states = data.get("player_states", {})
	_player_scores = data.get("player_scores", {})
	for key: String in _player_states.keys():
		if not _player_scores.has(key):
			_player_scores[key] = 0
	if not multiplayer.is_server():
		_server_player_states = _player_states.duplicate(true)
	## 重新发射信号让 UI 更新
	score_changed.emit(score)
	_emit_scores_changed()
	level_changed.emit(level)
	_sync_local_view()
	health_changed.emit(current_health, max_health)
	for key: String in _player_states.keys():
		if key.is_valid_int():
			_emit_shield_changed_for_peer(int(key))

func _mark_dirty() -> void:
	if multiplayer.is_server():
		_sync_dirty = true

func ensure_player_state(peer_id: int) -> void:
	_state(peer_id)
	var key := _peer_key(peer_id)
	if not _player_scores.has(key):
		_player_scores[key] = 0
		_emit_scores_changed()
	if multiplayer.is_server():
		if not _server_player_states.has(key):
			_server_player_states[key] = _new_player_state()
	_mark_dirty()

func reset_game() -> void:
	score = 0
	level = 1
	kills = 0
	total_kills = 0
	death_message = ""
	game_running = true
	kills_for_next_level = 10
	last_elite_threshold = 0
	elite_encounter_count = 0
	post_elite_multiplier = 1.0
	boss_active = false
	boss_encounter_count = 0
	last_boss_level = 0
	_player_states.clear()
	_player_scores.clear()
	_pending_skill_ack.clear()
	_pending_laser_ack.clear()
	var local_peer := _local_peer_id()
	_state(local_peer)
	_player_scores[_peer_key(local_peer)] = 0
	## 双人联机场景下初始化 A/B 行，确保 0 分也能立即出现在排行榜。
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_player_scores["1"] = 0
			for pid in NetworkManager.connected_peers:
				if pid > 0:
					_player_scores[str(pid)] = 0
		else:
			_player_scores["1"] = int(_player_scores.get("1", 0))
			_player_scores[_peer_key(local_peer)] = int(_player_scores.get(_peer_key(local_peer), 0))
	_sync_local_view()
	_emit_scores_changed()
	health_changed.emit(current_health, max_health)
	_emit_shield_changed_for_peer(local_peer)
	_mark_dirty()

func add_score(amount: int, peer_id: int = -1) -> void:
	if amount <= 0:
		return
	if NetworkManager.is_online() and multiplayer.is_server():
		if peer_id > 0:
			_add_score_to_peer(peer_id, amount)
		else:
			var alive_ids := _alive_peer_ids()
			if alive_ids.is_empty():
				alive_ids.append(_local_peer_id())
			var count: int = alive_ids.size()
			var div: int = max(count, 1)
			var base: int = amount / div
			var rem: int = amount % div
			for pid in alive_ids:
				var grant: int = base
				if rem > 0:
					grant += 1
					rem -= 1
				_add_score_to_peer(pid, grant)
	else:
		var pid := peer_id if peer_id > 0 else _local_peer_id()
		_add_score_to_peer(pid, amount)
	score_changed.emit(score)
	_emit_scores_changed()
	_mark_dirty()

func add_kill(killer_peer_id: int = -1) -> void:
	kills += 1
	total_kills += 1
	add_score(10 * level, killer_peer_id)
	if kills >= kills_for_next_level:
		level_up()
	## 单机保留“击杀里程碑 +1 护盾”奖励；联机改为按玩家独立掉落/奖励，不再全员同步加层。
	if not NetworkManager.is_online() and total_kills % 10 == 0:
		var local_key := _peer_key(_local_peer_id())
		var local_state: Dictionary = _state(_local_peer_id())
		local_state.shield_layers = min(int(local_state.shield_layers) + 1, 30)
		_player_states[local_key] = local_state
		_sync_local_view()
		_emit_shield_changed_for_peer(_local_peer_id())
	if total_kills > 0 and total_kills % 20 == 0 and total_kills != last_elite_threshold:
		last_elite_threshold = total_kills
		elite_spawn_requested.emit()
	_mark_dirty()

func level_up() -> void:
	level += 1
	kills = 0
	kills_for_next_level = 10 + level * 5
	for key: String in _player_states.keys():
		var s: Dictionary = _player_states[key]
		if not bool(s.get("is_alive", true)):
			_player_states[key] = s
			continue
		s.bullet_power_level = min(int(s.bullet_power_level) + 1, 50)
		s.current_health = min(int(s.current_health) + 1, int(s.max_health))
		_player_states[key] = s
	_sync_local_view()
	health_changed.emit(current_health, max_health)
	level_changed.emit(level)
	SFX.play_ui_confirm()
	if level > 0 and level % 5 == 0 and level != last_boss_level:
		last_boss_level = level
		boss_spawn_requested.emit(level)
	_mark_dirty()

func take_damage(amount: int = 1, peer_id: int = -1) -> bool:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if not bool(s.get("is_alive", true)):
		return true
	if int(s.shield_layers) > 0:
		var absorbed: int = min(int(s.shield_layers), amount)
		s.shield_layers = int(s.shield_layers) - absorbed
		_player_states[_peer_key(pid)] = s
		_emit_shield_changed_for_peer(pid)
		amount -= absorbed
	if amount > 0:
		s.current_health = max(int(s.current_health) - amount, 0)
		if _is_local_peer(pid):
			current_health = s.current_health
			max_health = s.max_health
			health_changed.emit(current_health, max_health)
		SFX.play_player_hurt()
		if int(s.current_health) <= 0 and _is_local_peer(pid):
			game_over.emit(score, level)
	if int(s.current_health) <= 0:
		s.current_health = 0
		s.is_alive = false
		s.shield_layers = 0
		_player_states[_peer_key(pid)] = s
		_emit_shield_changed_for_peer(pid)
	else:
		_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
	_mark_dirty()
	return int(s.current_health) <= 0

func heal(amount: int = 1, peer_id: int = -1) -> void:
	if amount <= 0:
		return
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if not bool(s.get("is_alive", true)):
		return
	if int(s.current_health) >= int(s.max_health):
		if int(s.max_health) < HEALTH_CAP:
			s.max_health = min(int(s.max_health) + amount, HEALTH_CAP)
			s.current_health = min(int(s.current_health) + amount, int(s.max_health))
			if _is_local_peer(pid):
				current_health = s.current_health
				max_health = s.max_health
				health_changed.emit(current_health, max_health)
	else:
		s.current_health = min(int(s.current_health) + amount, int(s.max_health))
		if _is_local_peer(pid):
			current_health = s.current_health
			max_health = s.max_health
			health_changed.emit(current_health, max_health)
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
	SFX.play_ui_select()
	_mark_dirty()

func collect_powerup(type: String, peer_id: int = -1) -> void:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if not bool(s.get("is_alive", true)):
		return
	var changed_in_place := false
	SFX.play_ui_confirm()
	match type:
		"spread":
			if int(s.shoot_level) < 10:
				s.shoot_level = min(int(s.shoot_level) + 1, 10)
		"speed":
			if int(s.shoot_speed_level) < 15:
				s.shoot_speed_level = min(int(s.shoot_speed_level) + 1, 15)
		"power":
			if int(s.bullet_power_level) >= 15:
				heal(1, pid)
				changed_in_place = true
			else:
				s.bullet_power_level = min(int(s.bullet_power_level) + 1, 50)
		"heal":
			heal(1, pid)
			changed_in_place = true
		"bomb":
			pass
		"core":
			s.skill_cooldown = max(float(s.skill_cooldown) * 0.7, 0.0)
			s.laser_cooldown = max(float(s.laser_cooldown) * 0.7, 0.0)
	if not changed_in_place:
		_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
		powerup_collected.emit(type)
	_mark_dirty()

func use_skill(peer_id: int = -1) -> bool:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if NetworkManager.is_online() and not multiplayer.is_server():
		if float(s.skill_cooldown) > 0.0 or not game_running:
			return false
		s.skill_cooldown = SKILL_COOLDOWN_MAX
		_player_states[_peer_key(pid)] = s
		_pending_skill_ack[_peer_key(pid)] = true
		if _is_local_peer(pid):
			_sync_local_view()
			skill_used.emit(pid)
		_rpc_request_use_skill.rpc_id(1, pid)
		return true
	if float(s.skill_cooldown) > 0.0 or not game_running:
		return false
	s.skill_cooldown = SKILL_COOLDOWN_MAX
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
		skill_used.emit(pid)
	_mark_dirty()
	return true

func tick_skill_cooldown(delta: float, peer_id: int = -1) -> void:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if NetworkManager.is_online() and not multiplayer.is_server():
		if _server_player_states.has(_peer_key(pid)):
			var server_s: Dictionary = _server_player_states[_peer_key(pid)]
			var pending := _pending_skill_ack.has(_peer_key(pid))
			var server_cd := float(server_s.get("skill_cooldown", s.skill_cooldown))
			if pending:
				## 防止“请求后立刻被旧同步覆盖为0”的窗口期抖动
				s.skill_cooldown = max(server_cd, float(s.skill_cooldown))
				if server_cd > 0.0:
					_pending_skill_ack.erase(_peer_key(pid))
			else:
				s.skill_cooldown = server_cd
			_player_states[_peer_key(pid)] = s
			if _is_local_peer(pid):
				_sync_local_view()
		return
	if float(s.skill_cooldown) > 0.0:
		s.skill_cooldown = max(float(s.skill_cooldown) - delta, 0.0)
		_player_states[_peer_key(pid)] = s
		if _is_local_peer(pid):
			_sync_local_view()
		_mark_dirty()

func use_laser(peer_id: int = -1) -> bool:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if NetworkManager.is_online() and not multiplayer.is_server():
		if float(s.laser_cooldown) > 0.0 or not game_running:
			return false
		s.laser_cooldown = get_laser_cooldown_max(pid)
		_player_states[_peer_key(pid)] = s
		_pending_laser_ack[_peer_key(pid)] = true
		if _is_local_peer(pid):
			_sync_local_view()
		_rpc_request_use_laser.rpc_id(1, pid)
		return true
	if float(s.laser_cooldown) > 0.0 or not game_running:
		return false
	s.laser_cooldown = get_laser_cooldown_max(pid)
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
		laser_used.emit(pid)
	_mark_dirty()
	return true

func tick_laser_cooldown(delta: float, peer_id: int = -1) -> void:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if NetworkManager.is_online() and not multiplayer.is_server():
		if _server_player_states.has(_peer_key(pid)):
			var server_s: Dictionary = _server_player_states[_peer_key(pid)]
			var pending := _pending_laser_ack.has(_peer_key(pid))
			var server_cd := float(server_s.get("laser_cooldown", s.laser_cooldown))
			if pending:
				s.laser_cooldown = max(server_cd, float(s.laser_cooldown))
				if server_cd > 0.0:
					_pending_laser_ack.erase(_peer_key(pid))
			else:
				s.laser_cooldown = server_cd
			_player_states[_peer_key(pid)] = s
			if _is_local_peer(pid):
				_sync_local_view()
		return
	if float(s.laser_cooldown) > 0.0:
		s.laser_cooldown = max(float(s.laser_cooldown) - delta, 0.0)
		_player_states[_peer_key(pid)] = s
		if _is_local_peer(pid):
			_sync_local_view()
		_mark_dirty()

func get_laser_damage(_peer_id: int = -1) -> int:
	var base: int = 5
	var mul: int = level / 10
	return base * int(pow(2, mul))

func get_laser_cooldown_max(peer_id: int = -1) -> float:
	var s := _state(peer_id)
	return max(LASER_COOLDOWN_MAX - float(s.laser_cd_bonus), 5.0)

func get_skill_cooldown_ratio(peer_id: int = -1) -> float:
	var s := _state(peer_id)
	var cd := float(s.skill_cooldown)
	if cd <= 0.0:
		return 0.0
	return cd / SKILL_COOLDOWN_MAX

func get_skill_cooldown(peer_id: int = -1) -> float:
	return float(_state(peer_id).skill_cooldown)

func get_laser_cooldown(peer_id: int = -1) -> float:
	return float(_state(peer_id).laser_cooldown)

func get_bullet_count(peer_id: int = -1) -> int:
	var s := _state(peer_id)
	return min(2 + int(s.shoot_level) / 3 + int(s.extra_bullet_count), 12)

func get_shoot_cooldown(peer_id: int = -1) -> float:
	var s := _state(peer_id)
	return max(0.27 - int(s.shoot_speed_level) * 0.018, 0.08)

func get_bullet_damage(peer_id: int = -1) -> int:
	var s := _state(peer_id)
	return 3 + int(s.bullet_power_level) + int(s.extra_damage_bonus)

func get_bullet_spread_angle(peer_id: int = -1) -> float:
	var s := _state(peer_id)
	return max(30.0 - int(s.shoot_level) * 4.0, 10.0)

func get_move_speed_multiplier(peer_id: int = -1) -> float:
	var s := _state(peer_id)
	return 1.0 + float(s.move_speed_bonus)

func get_shoot_level(peer_id: int = -1) -> int:
	return int(_state(peer_id).shoot_level)

func get_shoot_speed_level(peer_id: int = -1) -> int:
	return int(_state(peer_id).shoot_speed_level)

func get_bullet_power_level(peer_id: int = -1) -> int:
	return int(_state(peer_id).bullet_power_level)

func get_current_health(peer_id: int = -1) -> int:
	return int(_state(peer_id).current_health)

func get_max_health(peer_id: int = -1) -> int:
	return int(_state(peer_id).max_health)

func get_shield_layers(peer_id: int = -1) -> int:
	return int(_state(peer_id).shield_layers)

func get_laser_cd_bonus(peer_id: int = -1) -> float:
	return float(_state(peer_id).laser_cd_bonus)

func get_extra_bullet_count(peer_id: int = -1) -> int:
	return int(_state(peer_id).extra_bullet_count)

func get_extra_damage_bonus(peer_id: int = -1) -> int:
	return int(_state(peer_id).extra_damage_bonus)

func get_move_speed_bonus(peer_id: int = -1) -> float:
	return float(_state(peer_id).move_speed_bonus)

func get_peer_score(peer_id: int = -1) -> int:
	return int(_player_scores.get(_peer_key(peer_id), 0))

func get_all_player_scores() -> Dictionary:
	return _player_scores.duplicate(true)

func is_player_alive(peer_id: int = -1) -> bool:
	return bool(_state(peer_id).get("is_alive", true))

func get_alive_player_ids() -> Array[int]:
	return _alive_peer_ids()

func apply_reward(reward_type: String, peer_id: int = -1) -> void:
	var pid := peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	if not bool(s.get("is_alive", true)):
		return
	match reward_type:
		"laser_cd":
			s["laser_cd_bonus"] = float(s.get("laser_cd_bonus", 0.0)) + 1.0
		"bullet_count":
			s["extra_bullet_count"] = int(s.get("extra_bullet_count", 0)) + 1
		"damage":
			s["extra_damage_bonus"] = int(s.get("extra_damage_bonus", 0)) + 2
		"speed":
			s["move_speed_bonus"] = float(s.get("move_speed_bonus", 0.0)) + 0.10
		"shield":
			s["shield_layers"] = min(int(s.get("shield_layers", 0)) + 3, 30)
		_:
			return
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
	if reward_type == "shield":
		_emit_shield_changed_for_peer(pid)
	_mark_dirty()

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
