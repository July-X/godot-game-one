extends "res://tests/lan_probe.gd"
## 通过实弹破盾和击毁测量生成间隔。待发编队由生产导演排期。
## -- solo|host|client PORT typical|pending|quiet|later|rift|retry [baseline] [hold]

const BULLET := preload("res://scenes/entities/bullet.tscn")
const Enemy := preload("res://scripts/battle/enemies/enemy.gd")
const RIFT_SCENE := "res://scenes/rift_route_trial.tscn"
const SEED := 47681
const BOSS_Y := 185.0

var _sample := ""
var _baseline := false
var _hold := false
var _ready_slots := {}
var _death_ms := -1
var _death_frame := -1
var _active_seconds := 0.0
var _births := {"enemy": [], "asteroid": []}
var _drops: Array[Area2D] = []
var _old_shot: Area2D
var _old_shot_x := 0.0
var _authority_result := {}
var _real_cannon_slots := {}
var _collected_cores := 0
var _initial_peer := 0


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	_sample = args[2] if args.size() > 2 else "pending"
	_baseline = args.has("baseline")
	_hold = args.has("hold")
	seed(SEED)
	if _role == "solo":
		get_tree().current_scene = null
		get_tree().change_scene_to_file(RIFT_SCENE if _sample == "rift" else "res://scenes/ui/title_screen.tscn")
		await get_tree().scene_changed
		if _sample != "rift":
			get_tree().current_scene.get_node("Menu/BtnSingle").pressed.emit()
			await get_tree().scene_changed
		_main = get_tree().current_scene
	else:
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if not await _require("real_enet", err == OK and await _wait_until(func():
				return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)):
			return
		_enter_main_scene()
		if not await _require("assigned_both_slots", await _wait_until(func():
				return _cond_both_players() and NetworkManager.recovery.is_reserved(), 8)):
			return
		_initial_peer = NetworkManager.recovery.guest_wire
	_check("battle_entry", _main.scene_file_path == (RIFT_SCENE if _sample == "rift" else MAIN_SCENE),
		"%s window=%s arena=%s" % [_main.scene_file_path, get_window().size, NetworkManager.battle_size(_main)])
	_main.child_entered_tree.connect(_track_child)
	GameState.powerup_collected.connect(func(kind): _collected_cores += int(kind == "core"))
	var slot := NetworkManager.local_player_id() if NetworkManager.is_online() else 1
	var pilot: Node2D = _main._players[slot] if NetworkManager.is_online() else _main._player
	var boss_at := Vector2(NetworkManager.battle_size(_main).x * 0.5, BOSS_Y)
	# The two pickup circles overlap at the single-player pose. Approach from
	# separate sides so the host is farther from the guest's supply fragments.
	var pickup_offset := -190.0 if _role == "client" else (190.0 if _role == "host" else 46.0)
	pilot.global_position = boss_at + Vector2(pickup_offset, 172.0)
	pilot.reset_physics_interpolation()
	pilot.set_physics_process(false)
	pilot.set_process_unhandled_input(false)
	pilot._motion.mobile_mode = true
	if not NetworkManager.is_online() and DisplayServer.get_name() != "headless":
		_main._spawn_mobile_controls()
		_main._hud._layout_battle_hud()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if _role != "client":
		_main._asteroid_timer = 99.0
		_main._wave_director._cooldown = 99.0
	await _barrier("ready")
	if _role != "client":
		await _kill_boss(boss_at)
	if _sample == "rift":
		_check("rift_resolves_normally_without_ordinary_aftermath", _main.finished and _death_ms >= 0
			and (_baseline or float(_main.get("_first_boss_aftermath_left")) == 0.0), "")
		await _finish()
		return
	if not await _require("real_death_and_six_drops", await _wait_until(func():
			return _death_ms >= 0 and not is_instance_valid(_main._boss) and _drops.size() == 6, 4)):
		return
	if _sample == "retry":
		await _check_retry()
		await _finish()
		return
	await _exercise(pilot, slot)
	if _hold:
		await _check_hold()
	await _check_spawns()
	if _role == "solo" and args.has("record"):
		_check("recording_reaches_next_wave", await _wait_until(func(): return _active_seconds >= 4.1, 20), "")
	await _barrier("done")
	await _finish()


func _kill_boss(at: Vector2) -> void:
	GameState.level = 5
	GameState._state(1).laser_cooldown = 8.0
	GameState._sync_local_view()
	var director: Node = _main._wave_director
	director._rng.seed = SEED
	var pending := _sample in ["pending", "retry", "later", "rift"]
	director.reset(director.PHASE_SETUP if pending else director.PHASE_LULL)
	director._budget = director.BUDGET_CAP
	director._cooldown = 0.0 if pending else (2.55 if _sample == "quiet" else 0.38)
	if pending:
		director.advance(0.01, GameState.level, 0, NetworkManager.battle_size(_main), _main.ENEMY_SCREEN_CAP)
	_main._asteroid_timer = 3.30 if _sample == "quiet" else (0.09 if pending else 0.74)
	_main._spawn_boss(10 if _sample == "later" else GameState.FIRST_BOSS_LEVEL)
	var boss: Node2D = _main._boss
	boss._stop_entry_motion()
	boss.global_position = at
	boss.reset_physics_interpolation()
	boss.set_physics_process(false)
	boss.boss_died.connect(_mark_death, CONNECT_ONE_SHOT)
	_log("seed=%d sample=%s pending=%s asteroid=%.3f" % [SEED, _sample, director._pending, _main._asteroid_timer])
	_projectile(at + Vector2(0, 61), -PI * 0.5, ceili(boss.get_shield_hp()), true, 900.0)
	if not await _require("physical_shield_break", await _wait_until(func(): return not boss.has_impact_shield(), 2)):
		return
	for frame in 13:
		await get_tree().physics_frame
	var old_at := at + Vector2(-230, 135)
	_old_shot = _projectile(old_at, 0.0, 1, false, 145.0)
	_old_shot_x = old_at.x
	_main.register_bullet_spawn(old_at, 0.0, 1.0, false, 1, 145.0)
	var impact := [0]
	var fatal := _projectile(at + Vector2(0, 61), -PI * 0.5, ceili(boss.get_network_health()), true, 900.0)
	fatal.body_entered.connect(func(body): impact[0] += int(body == boss), CONNECT_ONE_SHOT)
	_check("physical_fatal_hit_once", await _wait_until(func(): return _death_ms >= 0, 2) and impact[0] == 1, str(impact))


func _projectile(at: Vector2, angle: float, damage: int, friendly: bool, speed: float) -> Area2D:
	var shot: Area2D = Pool.acquire("bullet", BULLET)
	_main.add_child(shot)
	shot.setup(at, angle, damage, friendly, 1, speed, 1)
	return shot


func _process(delta: float) -> void:
	if _death_ms >= 0 and not get_tree().paused:
		_active_seconds += delta
		if _role != "client" and _active_seconds < 2.0:
			for shot in get_tree().get_nodes_in_group("player_bullets"):
				if not shot._is_network_ghost:
					_real_cannon_slots[shot.owner_peer_id] = true


func _mark_death() -> void:
	if _death_ms >= 0:
		return
	_death_ms = Time.get_ticks_msec()
	_death_frame = Engine.get_physics_frames()
	_log("death frame=%d" % _death_frame)
	if _role == "host":
		_authority_death.rpc()


@rpc("authority", "reliable", "call_remote")
func _authority_death() -> void:
	_mark_death()


func _track_child(node: Node) -> void:
	if _death_ms < 0:
		return
	if node.scene_file_path == "res://scenes/entities/powerup.tscn":
		_drops.append(node)
		return
	var kind := ""
	if node is Enemy:
		kind = "enemy"
	elif node.scene_file_path == "res://scenes/entities/asteroid.tscn":
		kind = "asteroid"
	if kind.is_empty():
		return
	var event := {"active": _active_seconds, "wall_ms": Time.get_ticks_msec() - _death_ms,
		"frame": Engine.get_physics_frames() - _death_frame, "id": int(node.entity_id)}
	_births[kind].append(event)
	_log("birth %s %s" % [kind, event])


func _exercise(pilot: Node2D, slot: int) -> void:
	var starting: Vector2 = pilot.global_position
	pilot.set_physics_process(true)
	pilot._combat._shoot_timer = 0.0
	pilot._motion.handle_mobile_move(Vector2.UP)
	var did_shoot := await _until_active(func():
		for shot in get_tree().get_nodes_in_group("player_bullets"):
			if shot.owner_peer_id == slot:
				return true
		return false, 0.35)
	var moved := await _until_active(func(): return starting.y - pilot.global_position.y >= 86.0, 0.65)
	pilot._motion.handle_mobile_move(Vector2.ZERO)
	var pickup := await _until_active(func():
		if _role == "client":
			return (GameState.get_shoot_speed_level(slot) > 1 or GameState.get_bullet_power_level(slot) > 1
				or GameState.get_current_health(slot) > GameState.START_HEALTH)
		return _collected_cores > 0 and GameState.get_laser_cooldown(slot) < 6.5, 1.0)
	_check("real_move_shoot_and_collect", moved and did_shoot and pickup,
		"slot=%d moved=%.1f shot=%s pickup=%s laser_cd=%.2f fire_level=%d active=%.3f" % [slot,
			starting.y - pilot.global_position.y, did_shoot, pickup, GameState.get_laser_cooldown(slot),
			GameState.get_shoot_speed_level(slot), _active_seconds])
	if not _baseline and _sample in ["typical", "pending"]:
		_check("picked_up_before_new_pressure", pickup and _births.enemy.is_empty() and _births.asteroid.is_empty(), "")
	if _role != "client":
		_check("enemy_projectile_already_in_flight_keeps_moving", is_instance_valid(_old_shot)
			and _old_shot.global_position.x - _old_shot_x > 23.0, "")
	if _role == "host":
		_check("both_slots_fired_authoritative_cannon", await _wait_until(func():
			return _real_cannon_slots.has(1) and _real_cannon_slots.has(NetworkManager.recovery.guest_slot), 0.5),
			str(_real_cannon_slots))


func _until_active(condition: Callable, seconds: float) -> bool:
	var deadline := _active_seconds + seconds
	await _wait_until(func(): return condition.call() or _active_seconds >= deadline, 6)
	return condition.call()


func _check_hold() -> void:
	await _barrier("before_hold")
	var stage := "_first_boss_aftermath_left"
	var scene_id := _main.get_instance_id()
	var round_id := GameState.get_sync_round() if NetworkManager.is_online() else 0
	if _role == "solo":
		get_tree().paused = true
	elif _role == "client":
		NetworkManager.recovery.set_background(true)
	var frozen := await _wait_until(func(): return get_tree().paused, 3)
	var remaining := 0.0 if _baseline else float(_main.get(stage))
	var before := _wave_clock() if _role != "client" else []
	await _wait_seconds(0.5)
	if _role != "client":
		_check("pause_preserves_wave_asteroid_and_aftermath_clocks", frozen and before == _wave_clock()
			and (_baseline or remaining > 0 and is_equal_approx(remaining, float(_main.get(stage)))), str(before))
	if _role == "solo":
		get_tree().paused = false
		return
	if _role == "client":
		NetworkManager.drop_lan_transport()
	NetworkManager.recovery.set_background(false)
	var restored := await _wait_until(func():
		return (not get_tree().paused and NetworkManager.is_online()
			and NetworkManager.recovery.guest_wire != _initial_peer and NetworkManager.recovery.guest_wire > 1), 13)
	_check("same_round_on_new_transport", restored and _main.get_instance_id() == scene_id
		and GameState.get_sync_round() == round_id, "wire=%d→%d" % [_initial_peer, NetworkManager.recovery.guest_wire])


func _wave_clock() -> Array:
	var director: Node = _main._wave_director
	return [_main._asteroid_timer, director._phase_left, director._budget, director._cooldown, director._pending.duplicate(true)]


func _check_spawns() -> void:
	var appeared := await _wait_until(func(): return not _births.enemy.is_empty() and not _births.asteroid.is_empty(), 6)
	if not await _require("both_pressure_sources_resumed", appeared):
		return
	# Remote render deltas and batched deliveries are not the authoritative spawn clock.
	if _role != "client":
		var earliest := minf(float(_births.enemy[0].active), float(_births.asteroid[0].active))
		if _sample == "quiet":
			_check("existing_gap_neither_shortened_nor_delayed", earliest > 2.5 and earliest < 2.85, str(earliest))
		elif _baseline or _sample == "later":
			_check("birth_before_two_seconds", earliest < 0.8, str(earliest))
		else:
			_check("minimum_active_aftermath", earliest >= 1.92 and earliest < 2.22, str(earliest))
	if _sample in ["pending", "later"]:
		var staggered := await _wait_until(func(): return _births.enemy.size() >= 4, 4)
		if _role != "client":
			var spacing := []
			for index in range(1, mini(_births.enemy.size(), 4)):
				spacing.append(float(_births.enemy[index].active) - float(_births.enemy[index - 1].active))
			_check("original_four_enemies_keep_stagger", staggered and spacing.min() >= 0.04, str(spacing))
	if _role == "host":
		_report_first_births.rpc(_birth_ids())
	elif _role == "client":
		var matched := await _wait_until(func(): return not _authority_result.is_empty(), 4)
		var ids := _birth_ids()
		var unique := {}
		for id: int in ids.enemy:
			unique[id] = true
		_check("same_authoritative_birth_ids_without_duplicates", matched and ids == _authority_result
			and ids.enemy.size() == unique.size(),
			"%s / %s" % [ids, _authority_result])


func _birth_ids() -> Dictionary:
	var count := 4 if _sample in ["pending", "later"] else 1
	return {"enemy": _births.enemy.slice(0, count).map(func(event): return event.id), "asteroid": _births.asteroid[0].id}


@rpc("authority", "reliable", "call_remote")
func _report_first_births(ids: Dictionary) -> void:
	_authority_result = ids


func _check_retry() -> void:
	var previous := _main.get_instance_id()
	var round_id := GameState.get_sync_round() if NetworkManager.is_online() else 0
	await _barrier("before_retry")
	if _role != "client":
		_main._restart()
	if not await _require("retry_replaces_battle_scene", await _wait_until(func():
		var current := get_tree().current_scene
		return (is_instance_valid(current) and current.scene_file_path == MAIN_SCENE
			and current.get_instance_id() != previous), 4)):
		return
	_main = get_tree().current_scene
	_check("retry_clears_unfinished_aftermath", _baseline or float(_main.get("_first_boss_aftermath_left")) == 0.0, "")
	_check("retry_first_asteroid_follows_normal_schedule", await _wait_until(func():
		return (not get_tree().get_nodes_in_group("asteroids").is_empty()
			and (_role == "solo" or GameState.get_sync_round() > round_id)), 0.90), "")
	await _barrier("new_round_ready")


func _barrier(stage: String) -> void:
	if _role == "solo":
		return
	_sync_stage.rpc(stage)
	_check("barrier_" + stage, await _wait_until(func(): return _ready_slots.has(stage), 5), "")


@rpc("any_peer", "reliable", "call_remote")
func _sync_stage(stage: String) -> void:
	_ready_slots[stage] = true


func _require(name: String, ok: bool) -> bool:
	_check(name, ok, "")
	if not ok:
		await _finish()
	return ok


func _finish() -> void:
	BGM.stop_bgm()
	await _wait_seconds(0.17)
	get_tree().quit(_summarize())
