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
		"shield_max_bonus": 0,
		## 构筑状态：卡牌层数与护盾充能间隔
		"card_stacks": {},
		"shield_interval": 8.0,
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
	if not multiplayer.has_multiplayer_peer():
		return
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
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_sync_dirty = true

func ensure_player_state(peer_id: int) -> void:
	_state(peer_id)
	var key := _peer_key(peer_id)
	if not _player_scores.has(key):
		_player_scores[key] = 0
		_emit_scores_changed()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
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
	reset_graze()
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
	_maybe_trigger_elite()
	_mark_dirty()


## 精英触发：阈值随等级递增（20 + level*2）。
## 原来固定每 20 击杀一场，但累计击杀随等级平方增长——到 20 级已经是 57 场，
## 精英从"内容单元"贬值成了节奏噪音，玩家见到精英不再有"要打一场硬仗"的预期。
## 递增阈值让精英密度回到"每几级一个里程碑"的节奏。
##
## 用累计计数而不是取模：阈值会随等级变化，取模在阈值跳变时可能整段错过。
func _maybe_trigger_elite() -> void:
	var threshold: int = elite_kill_threshold()
	if total_kills - last_elite_threshold < threshold:
		return
	## 等级可能在这一次击杀中跳了级，阈值要按等级差补记，否则会连续触发
	var overshoot: int = total_kills - last_elite_threshold
	last_elite_threshold = total_kills - (overshoot % threshold)
	elite_spawn_requested.emit()


func elite_kill_threshold() -> int:
	return ELITE_BASE_KILLS + level * ELITE_KILLS_PER_LEVEL


const ELITE_BASE_KILLS: int = 20
const ELITE_KILLS_PER_LEVEL: int = 2


func level_up() -> void:
	level += 1
	kills = 0
	kills_for_next_level = 10 + level * 5
	for key: String in _player_states.keys():
		var s: Dictionary = _player_states[key]
		if not bool(s.get("is_alive", true)):
			_player_states[key] = s
			continue
		## 升级改为发"三选一"：不再无脑 +1 威力。
		## 原来的固定收益是"Roguelike 但没有 Roguelike 味"的根因之一——
		## 玩家没有决策，也就没有 build。数值兜底在 upgrade_draft 抽不到卡时生效。
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
		if int(s.current_health) <= 0 and _is_local_peer(pid) and not NetworkManager.is_online():
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
	var base: float = max(0.27 - int(s.shoot_speed_level) * 0.018, 0.08)
	## 擦弹奖励直接乘在射击间隔上：CD 越短射速越高，
	## 这是唯一能让"主动贴近弹幕"转化为收益的通路（见 Design_Decisions）
	return base * (1.0 - get_graze_fire_rate_bonus())


## ── 擦弹（Graze）───────────────────────────────────────────────
##
## 弹幕射击的标志性机制：让"贴着子弹飞"变成值得追求的操作。
## 关键设计取舍：**擦弹让玩家更安全，而不是更危险**。
## 奖励绑定"主动接近危险"后，画面会更好看、死亡率反而更低——
## 因为玩家有了主动去浪的理由，而不是被动等着挨打。

## 擦弹层数、最近一次擦弹的时刻（毫秒）、以及距下一层的累计次数
var _graze_stacks: int = 0
var _graze_last_msec: int = 0
var _graze_since_stack: int = 0

## 每层提供的射速加成
const GRAZE_STACK_BONUS: float = 0.04
const GRAZE_MAX_STACKS: int = 10
## 升 1 层需要的累计擦弹次数
const GRAZE_THRESHOLD: int = 3
## 超过这个时间没有新擦弹，层数全部作废。
## 2 秒的取法：短于典型弹幕间隔（逼玩家持续贴弹），
## 长于一次走位往返（不至于一个失误就清零）
const GRAZE_WINDOW_MSEC: int = 2000


## 记录一次擦弹。每 GRAZE_THRESHOLD 次累计擦弹升 1 层。
func add_graze(now_msec: int) -> int:
	_graze_last_msec = now_msec
	if _graze_since_stack < GRAZE_THRESHOLD - 1:
		_graze_since_stack += 1
		return _graze_stacks
	_graze_since_stack = 0
	_graze_stacks = mini(_graze_stacks + 1, GRAZE_MAX_STACKS)
	return _graze_stacks


## 当前射速加成 0~0.4。超时会自动归零（惰性判定，无需每帧维护）
func get_graze_fire_rate_bonus() -> float:
	if _graze_stacks <= 0:
		return 0.0
	if Time.get_ticks_msec() - _graze_last_msec > GRAZE_WINDOW_MSEC:
		return 0.0
	return float(_graze_stacks) * GRAZE_STACK_BONUS


func get_graze_stacks() -> int:
	if Time.get_ticks_msec() - _graze_last_msec > GRAZE_WINDOW_MSEC:
		return 0
	return _graze_stacks

## HUD / 联机同步用的标量，0~1
func get_graze_ratio() -> float:
	return get_graze_fire_rate_bonus() / (GRAZE_MAX_STACKS * GRAZE_STACK_BONUS)


func reset_graze() -> void:
	_graze_stacks = 0
	_graze_since_stack = 0
	_graze_last_msec = 0


## ── 升级卡（构筑）───────────────────────────────────────────
##
## 每个 peer 独立持有卡牌层数。联机时两端各抽各的，避免抢卡冲突。

func get_card_stacks(peer_id: int = -1) -> Dictionary:
	var s := _state(peer_id)
	var raw: Variant = s.get("card_stacks", {})
	return raw if raw is Dictionary else {}


func get_card_stacks_for(pid: int) -> Dictionary:
	var s := _state(pid)
	var raw: Variant = s.get("card_stacks", {})
	return raw if raw is Dictionary else {}


func get_card_count(card_id: String, peer_id: int = -1) -> int:
	return int(get_card_stacks(peer_id).get(card_id, 0))


## 应用一张卡。数值卡改属性，风格卡改行为开关——
## 行为开关由 get_bullet_style_* 系列读取，combat_controller 与 bullet 用它们。
func apply_card(peer_id: int, card_id: String) -> void:
	var pid: int = peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	var stacks: Dictionary = get_card_stacks_for(pid)
	stacks[card_id] = int(stacks.get(card_id, 0)) + 1
	s.card_stacks = stacks
	match card_id:
		"power":
			s.bullet_power_level = mini(int(s.bullet_power_level) + 3, 50)
		"firerate":
			s.shoot_speed_level = mini(int(s.shoot_speed_level) + 2, 15)
		"spread":
			s.shoot_level = mini(int(s.shoot_level) + 2, 10)
		"vitality":
			s.max_health = mini(int(s.max_health) + 20, HEALTH_CAP)
			s.current_health = mini(int(s.current_health) + 20, int(s.max_health))
		"shield":
			s.shield_interval = maxf(float(s.get("shield_interval", 8.0)) - 2.0, 3.0)
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
		health_changed.emit(current_health, max_health)
	_mark_dirty()


## 子弹行为开关：这些是"改变操作方式"的卡生效的地方
func get_bullet_pierce(peer_id: int = -1) -> int:
	## 「贯穿弹芯 + 追踪回路」组合进化 → 追踪贯穿弹：
	## 子弹边追踪边贯穿，是两种卡组合出的第三种玩法
	if _has_evolution(EVOLUTION_PIERCE_HOMING, peer_id):
		return get_card_count("pierce", peer_id) + 1
	return get_card_count("pierce", peer_id)


func get_bullet_splash(peer_id: int = -1) -> bool:
	return get_card_count("splash", peer_id) > 0 \
		or _has_evolution(EVOLUTION_SPLASH_PIERCE, peer_id)


func get_bullet_homing(peer_id: int = -1) -> bool:
	return get_card_count("homing", peer_id) > 0 \
		or _has_evolution(EVOLUTION_PIERCE_HOMING, peer_id)


func get_splash_radius(peer_id: int = -1) -> float:
	## 「溅射 + 贯穿」组合进化 → 连锁爆破：溅射范围更大
	if _has_evolution(EVOLUTION_SPLASH_PIERCE, peer_id):
		return 112.0
	return 78.0


func get_bullet_speed_bonus(peer_id: int = -1) -> float:
	var bonus: float = float(get_card_count("pierce", peer_id)) * 40.0
	## 「擦弹专注 + 速射」组合进化 → 弹幕共振：擦弹满层时额外加速
	if _has_evolution(EVOLUTION_GRAZE_FIRERATE, peer_id):
		bonus += get_graze_stacks() * 18.0
	return bonus


## ── 组合进化 ────────────────────────────────────────────────
##
## 组合进化是复玩引擎：10 张卡能组合出 10+ 种体验，
## 而"各拿各的"只能得到 10 种。触发条件是**持有两张指定风格卡**，
## 满足后自动生效、不占卡位、也不需要玩家额外操作。
const EVOLUTION_PIERCE_HOMING: String = "pierce_homing"
const EVOLUTION_SPLASH_PIERCE: String = "splash_pierce"
const EVOLUTION_GRAZE_FIRERATE: String = "graze_firerate"

const EVOLUTIONS: Array[Dictionary] = [
	{
		"id": EVOLUTION_PIERCE_HOMING, "name": "追踪贯穿弹",
		"requires": ["pierce", "homing"],
		"desc": "贯穿 +1，子弹边追踪边贯穿",
	},
	{
		"id": EVOLUTION_SPLASH_PIERCE, "name": "连锁爆破",
		"requires": ["splash", "pierce"],
		"desc": "溅射范围 78 → 112px",
	},
	{
		"id": EVOLUTION_GRAZE_FIRERATE, "name": "弹幕共振",
		"requires": ["graze_focus", "firerate"],
		"desc": "每层擦弹额外 +18 弹速",
	},
]


func _has_evolution(evo_id: String, peer_id: int = -1) -> bool:
	for evo: Dictionary in EVOLUTIONS:
		if str(evo.id) != evo_id:
			continue
		var owned: Dictionary = get_card_stacks(peer_id)
		for req: String in evo.requires:
			if int(owned.get(req, 0)) <= 0:
				return false
		return true
	return false


## 当前已激活的进化（供 HUD 显示）
func get_active_evolutions(peer_id: int = -1) -> Array:
	var out: Array = []
	for evo: Dictionary in EVOLUTIONS:
		if _has_evolution(str(evo.id), peer_id):
			out.append(evo)
	return out


## 擦弹强化：判定半径与窗口
func get_graze_radius_bonus(peer_id: int = -1) -> float:
	return float(get_card_count("graze_focus", peer_id)) * 8.0


func get_graze_window_msec(peer_id: int = -1) -> int:
	return GRAZE_WINDOW_MSEC + get_card_count("graze_focus", peer_id) * 1000


## 护盾充能间隔（毫秒级改为秒）
func get_shield_interval(peer_id: int = -1) -> float:
	var s := _state(peer_id)
	return maxf(float(s.get("shield_interval", 8.0)), 3.0)

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

func get_shield_bonus(peer_id: int = -1) -> int:
	return int(_state(peer_id).get("shield_max_bonus", 0))

func set_shield_layers(peer_id: int, layers: int) -> void:
	var s := _state(peer_id)
	s.shield_layers = clampi(layers, 0, 999)
	_player_states[_peer_key(peer_id)] = s
	_sync_local_view()
	_emit_shield_changed_for_peer(peer_id)

func get_shield_max_hp(peer_id: int = -1) -> int:
	var bp := get_bullet_power_level(peer_id)
	var mhp := get_max_health(peer_id)
	var bonus := get_shield_bonus(peer_id)
	return maxi(1, int((10 + bp * 2 + int(mhp * 0.2)) * 0.5) + bonus)

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


## 救援成功：回血到比例、给护盾、清除死亡标记。
## 只由 Host 调用（救援的距离与时长校验都在 Host 侧），
## Client 收到的是 Host 下发的状态，不要本地自结算。
func revive_player(peer_id: int, health_ratio: float = 0.5,
		invincible_seconds: float = 3.0, shield_layers: int = 1) -> void:
	var pid: int = peer_id if peer_id > 0 else _local_peer_id()
	var s := _state(pid)
	var mhp: int = maxi(1, int(s.get("max_health", START_HEALTH)))
	s.is_alive = true
	s.current_health = maxi(1, int(float(mhp) * health_ratio))
	s.shield_layers = maxi(int(s.get("shield_layers", 0)), shield_layers)
	s.downed = false
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
		health_changed.emit(current_health, max_health)
		_emit_shield_changed_for_peer(pid)
	_mark_dirty()


## 是否处于倒地（被救前）状态
func is_player_downed(peer_id: int = -1) -> bool:
	return bool(_state(peer_id).get("downed", false))

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
			s["shield_max_bonus"] = int(s.get("shield_max_bonus", 0)) + 20
		_:
			return
	_player_states[_peer_key(pid)] = s
	if _is_local_peer(pid):
		_sync_local_view()
	if reward_type == "shield":
		_emit_shield_changed_for_peer(pid)
	_mark_dirty()

func on_boss_started() -> void:
	boss_encounter_count += 1
	_mark_dirty()

func stop_game() -> void:
	if not game_running:
		return
	game_running = false
	_mark_dirty()
