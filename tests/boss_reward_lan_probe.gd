extends "res://tests/lan_probe.gd"
## 真实 ENet 对战夹具。固定现有奖励抽取结果，用房主实弹碰撞完成击破。
## 两端分别运行 -- host|client PORT both|host-downed|client-downed [截图目录]。

const BULLET := preload("res://scenes/entities/bullet.tscn")
const BossModel := preload("res://scripts/battle/enemies/boss/boss.gd")
const BOSS_AT := Vector2(640, 190)
const HOST_AT := Vector2(430, 550)
const GUEST_AT := Vector2(850, 550)
const DROPS := ["core", "heal", "speed", "power", "core", "heal"]

var _scenario := "both"
var _guest := 0
var _local_slot := 0
var _excluded := 0
var _expected: Dictionary[int, String] = {}
var _steps := {}
var _drops: Array[String] = []
var _body_ids := {}
var _muzzle_ids := {}
var _reward_playbacks := {}
var _remote_showed_feedback := false
var _capture_dir := ""

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 2:
		_scenario = args[2]
	if args.size() > 3:
		_capture_dir = args[3]
	if not _require("known_scenario", _scenario in ["both", "host-downed", "client-downed"]):
		return
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var linked := err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)
	if not _require("linked_real_enet", linked):
		return
	_enter_main_scene()
	if not _require("ordinary_battle_with_two_reserved_slots", await _wait_until(func():
			return _cond_both_players() and NetworkManager.recovery.is_reserved(), 7) and GameState.normal_growth_enabled):
		return
	_guest = NetworkManager.recovery.guest_slot
	_local_slot = NetworkManager.local_player_id()
	match _scenario:
		"both":
			_expected = {1: "damage", _guest: "bullet_count"}
		"host-downed":
			_excluded = 1
			_expected = {_guest: "speed"}
		"client-downed":
			_excluded = _guest
			_expected = {1: "laser_cd"}
	_prepare_pilots()
	get_tree().node_added.connect(_observe_drop)
	await _barrier("ready")
	_replay_receipt("damage")
	await _barrier("before_any_reward")
	_check("receipt_without_kill_awards_or_plays_nothing", _matches_rewards(false) and _reward_playbacks.is_empty()
		and _body_ids.is_empty() and not _remote_showed_feedback, str(_both_rewards()))
	if not await _settle_boss():
		get_tree().quit(_summarize())
		return
	await _exercise_reward()
	var old_snapshot := GameState._to_dict() if _role == "host" else {}
	await _recover_without_replay()
	await _retry_without_old_reward(old_snapshot)
	# 等音频线程释放循环战斗音乐，再退出测试进程。
	BGM.stop_bgm()
	await _wait_seconds(0.15)
	get_tree().quit(_summarize())

func _prepare_pilots() -> void:
	_main._wave_director._cooldown = 120.0
	_main._asteroid_timer = 120.0
	var pilot: Node = _main._players[_local_slot]
	pilot.global_position = HOST_AT if _role == "host" else GUEST_AT
	pilot.rotation = 0.0
	pilot.reset_physics_interpolation()
	pilot.set_physics_process(false)
	pilot.set_process_unhandled_input(false)
	pilot._motion.mobile_mode = true
	pilot._combat._shoot_timer = 120.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _settle_boss() -> bool:
	if _role == "host":
		_main._spawn_boss(GameState.FIRST_BOSS_LEVEL)
		_boss = _main._boss
		_boss._stop_entry_motion()
		_boss.global_position = BOSS_AT
		_boss.reset_physics_interpolation()
		_boss.set_physics_process(false)
	var received := await _wait_until(func(): return is_instance_valid(_main._boss), 4)
	_check("first_boss_received_on_both_peers", received, "")
	if not received:
		return false
	var boss: BossModel = _main._boss
	var boss_id := boss.entity_id
	await _barrier("before_downed")
	if _role == "host" and _excluded > 0:
		_main._players[_excluded].force_kill()
	if _excluded > 0:
		var downed := await _wait_until(func():
			return (GameState.rescue_peer_id == _excluded and not GameState.is_player_alive(_excluded)
				and is_instance_valid(_main._players.get(_excluded)) and _main._players[_excluded].is_downed), 3)
		_check("authority_excludes_actually_downed_slot", downed, "slot=%d" % _excluded)
		if not downed:
			return false
	if _scenario == "client-downed" and _role == "host":
		GameState._state(1).laser_cooldown = 10.0
		GameState._sync_local_view()
	await _barrier("before_fatal_collision")
	if _role == "host":
		var draw_seed := _reward_seed()
		_check("pinned_original_random_draw_in_slot_order", draw_seed > 0, "seed=%d" % draw_seed)
		if draw_seed <= 0:
			return false
		# 在信号发出后、生产结算之前固定随机种子。奖励仍由房主原流程抽取。
		var original := Callable(_main, "_on_boss_died")
		boss.boss_died.disconnect(original)
		boss.boss_died.connect(func(): seed(draw_seed))
		boss.boss_died.connect(original)
		var killer := 1 if _excluded != 1 else _guest
		_shoot_boss(killer, ceili(boss.get_shield_hp()))
		_check("real_projectile_breaks_shield", await _wait_until(func(): return not boss.has_impact_shield(), 2), "")
		var impacts := [0]
		var fatal := _shoot_boss(killer, ceili(boss.get_network_health()))
		fatal.body_entered.connect(func(body): impacts[0] += int(body == boss))
		var retired := await _wait_until(func(): return not is_instance_valid(_main._boss), 3)
		_check("real_fatal_collision_once", retired and impacts[0] == 1, str(impacts))
	var settled := await _wait_until(func(): return (not is_instance_valid(_main._boss) and _drops.size() == 6
		and _matches_rewards(true)), 4)
	_check("actual_victory_grants_only_chosen_rewards_and_six_drops", settled and _drops == DROPS,
		"rewards=%s drops=%s" % [_both_rewards(), _drops])
	if not settled:
		return false
	var won_reward := _expected.has(_local_slot)
	await _wait_until(func(): return not won_reward or _body_ids.size() == 1 and _reward_playbacks.size() == 1, 0.35)
	_check("only_the_local_eligible_ship_receives_body_sound_and_row", _body_ids.size() == int(won_reward)
		and _reward_playbacks.size() == int(won_reward) and _bonus_rows() == _local_expected_rows()
		and not _remote_showed_feedback, "slot=%d body=%d audio=%d rows=%s" % [
			_local_slot, _body_ids.size(), _reward_playbacks.size(), _bonus_rows()])
	await _capture("earned")
	if _role == "host":
		_main._rpc_despawn_entity.rpc(boss_id, true)
	_replay_receipt(_expected.get(_local_slot, "damage"))
	await _barrier("duplication_delivered")
	await _wait_seconds(0.08)
	_check("replayed_death_and_receipt_cannot_reaward_or_relight", _matches_rewards(true) and _drops == DROPS
		and _body_ids.size() == int(won_reward) and _reward_playbacks.size() == int(won_reward)
		and _main._local_boss_bonus_before.is_empty(), str(_both_rewards()))
	return true

func _reward_seed() -> int:
	var pool: Array[String] = _main._boss_reward_pool()
	for candidate in range(1, 256):
		seed(candidate)
		var drawn := {}
		for slot: int in GameState.get_alive_player_ids():
			drawn[slot] = pool.pick_random()
		if drawn == _expected:
			return candidate
	return 0

func _shoot_boss(owner: int, damage: int) -> Area2D:
	var bullet: Area2D = Pool.acquire("bullet", BULLET)
	_main.add_child(bullet)
	bullet.setup(BOSS_AT + Vector2(0, 60), -PI * 0.5, damage, true, 1, 900.0, owner)
	return bullet

func _exercise_reward() -> void:
	await _barrier("before_reward_use")
	var pilot: Node = _main._players[_local_slot]
	match _expected.get(_local_slot, ""):
		"bullet_count", "damage":
			pilot._combat._shoot()
			if _role == "client":
				_check("guest_cannon_reward_waits_for_authority_echo", not pilot.has_node("FirstBossRewardMuzzle"), "")
			var expected_count := 2 if _role == "host" else 3
			var expected_damage := 6 if _role == "host" else 4
			var cannon := await _wait_until(func():
				return _cannon_count(_local_slot, expected_damage) == expected_count and _muzzle_ids.size() == 1, 1.0)
			_check("local_rewarded_volley_uses_actual_cannon_output_and_muzzle", cannon,
				"slot=%d bullets=%d damage=%d muzzle=%d" % [
					_local_slot, _cannon_count(_local_slot, expected_damage), expected_damage, _muzzle_ids.size()])
			if _role == "host":
				_check("authority_sees_guest_extra_projectile",
					await _wait_until(func(): return _cannon_count(_guest, 4) == 3, 1), "bullets=%d" % _cannon_count(_guest, 4))
		"speed":
			var before: Vector2 = pilot.global_position
			pilot.set_physics_process(true)
			pilot._motion.handle_mobile_move(Vector2.RIGHT)
			var moved := await _wait_until(func():
				return pilot.global_position.x - before.x > 5.0 and pilot._feedback._reward_exhaust_boost > 0.0, 1)
			pilot.set_physics_process(false)
			pilot._motion.stop_for_downed()
			_check("actual_guest_movement_exercises_only_earned_tail", moved
				and is_equal_approx(GameState.get_move_speed_multiplier(_local_slot), 1.10), str(pilot.global_position - before))
		"laser_cd":
			_check("laser_award_keeps_current_cooldown", is_equal_approx(GameState.get_laser_cooldown(_local_slot), 10.0)
				and is_equal_approx(GameState.get_laser_cooldown_max(_local_slot), 9.0)
				and not GameState.use_laser(_local_slot) and _main._hud._first_boss_laser_pending, "")
			GameState.tick_laser_cooldown(10.0, _local_slot)
			_check("actual_confirmed_laser_uses_reduced_cooldown_and_icon", GameState.use_laser(_local_slot)
				and is_equal_approx(GameState.get_laser_cooldown(_local_slot), 9.0)
				and _main._hud._first_boss_laser_tween != null, "")
	await _capture("first-use")
	await _barrier("reward_use_finished")
	await _wait_seconds(0.40)

func _recover_without_replay() -> void:
	var recovery: Node = NetworkManager.recovery
	var previous_wire: int = recovery.guest_wire
	var scene_id: int = _main.get_instance_id()
	var round_id := GameState.get_sync_round()
	var owned_id: int = _main._players[_local_slot].get_instance_id()
	var events := [_body_ids.size(), _reward_playbacks.size(), _muzzle_ids.size()]
	await _barrier("start_rewire")
	if _role == "client":
		recovery.set_background(true)
	var frozen := await _wait_until(func(): return get_tree().paused and recovery.deadline > 0, 3)
	_check("real_lan_hold_before_transport_drop", frozen and _main._local_boss_bonus_before.is_empty(), "")
	if _role == "client":
		await _wait_seconds(0.20)
		NetworkManager.drop_lan_transport()
		recovery.set_background(false)
	var restored := await _wait_until(func(): return (not get_tree().paused and recovery.deadline == 0
		and recovery.guest_wire > 1 and recovery.guest_wire != previous_wire and NetworkManager.is_online()), 13)
	if restored:
		_replay_receipt(_expected.get(_local_slot, "damage"))
		await _barrier("old_receipt_on_new_transport")
		await _wait_seconds(0.10)
	_check("new_wire_same_round_preserves_values_without_replay", restored and _main.get_instance_id() == scene_id
		and GameState.get_sync_round() == round_id and _main._players[_local_slot].get_instance_id() == owned_id
		and _main._players[_guest].get_multiplayer_authority() == recovery.guest_wire
		and _matches_rewards(true) and _bonus_rows() == _local_expected_rows()
		and [_body_ids.size(), _reward_playbacks.size(), _muzzle_ids.size()] == events and not _remote_showed_feedback,
		"wire=%d→%d rewards=%s playback=%d" % [previous_wire, recovery.guest_wire, _both_rewards(), _reward_playbacks.size()])

func _retry_without_old_reward(old_snapshot: Dictionary) -> void:
	var original: int = _main.get_instance_id()
	var round_id := GameState.get_sync_round()
	var events := [_body_ids.size(), _reward_playbacks.size(), _muzzle_ids.size()]
	await _barrier("before_retry")
	if _role == "host":
		_main._restart()
	var restarted := await _wait_until(func():
		var active := get_tree().current_scene
		return (is_instance_valid(active) and active.get_instance_id() != original
			and active.scene_file_path == MAIN_SCENE and active._players.size() == 2 and GameState.get_sync_round() > round_id), 8)
	_check("retry_starts_new_battle_with_no_prior_bonus", restarted and _matches_rewards(false), str(_both_rewards()))
	if not restarted:
		return
	_main = get_tree().current_scene
	_prepare_pilots()
	await _barrier("retry_ready")
	if _role == "host":
		# 用当前连接送出上一局的真实快照，验证现有局次守卫。
		GameState._rpc_sync_game_state.rpc_id(NetworkManager.recovery.guest_wire, old_snapshot)
	_replay_receipt(_expected.get(_local_slot, "damage"))
	await _barrier("old_round_replay_delivered")
	await _wait_seconds(0.15)
	_check("old_round_state_and_receipt_cannot_transfer", _matches_rewards(false) and _bonus_rows().is_empty()
		and [_body_ids.size(), _reward_playbacks.size(), _muzzle_ids.size()] == events and not _remote_showed_feedback,
		str(_both_rewards()))
	await _barrier("done")

func _process(_delta: float) -> void:
	if not is_instance_valid(_main) or _local_slot == 0:
		return
	for entry in _main._players:
		var pilot: Node = _main._players[entry]
		if not is_instance_valid(pilot):
			continue
		var body := pilot.get_node_or_null("FirstBossRewardBody") as Node2D
		var muzzle := pilot.get_node_or_null("FirstBossRewardMuzzle") as Node2D
		if entry == _local_slot:
			if is_instance_valid(body) and body.visible:
				_body_ids[body.get_instance_id()] = true
			if is_instance_valid(muzzle) and muzzle.visible:
				_muzzle_ids[muzzle.get_instance_id()] = true
		else:
			_remote_showed_feedback = _remote_showed_feedback or is_instance_valid(body) or is_instance_valid(muzzle)
	for voice: AudioStreamPlayer in SFX.get_children():
		if voice.playing and voice.stream == SFX._stream_boss_reward:
			var playback := voice.get_stream_playback()
			if playback:
				_reward_playbacks[playback.get_instance_id()] = true

func _observe_drop(node: Node) -> void:
	if node.get_parent() == _main and node.scene_file_path == "res://scenes/entities/powerup.tscn":
		_drops.append(node.get_powerup_type())

func _cannon_count(slot: int, damage: int) -> int:
	var count := 0
	for projectile in get_tree().get_nodes_in_group("player_bullets"):
		if projectile.scene_file_path == BULLET.resource_path and projectile.owner_peer_id == slot and projectile._damage == damage:
			count += 1
	return count

func _both_rewards() -> Dictionary:
	var result := {}
	for slot: int in [1, _guest]:
		result[slot] = [GameState.get_extra_bullet_count(slot), GameState.get_extra_damage_bonus(slot),
			GameState.get_move_speed_bonus(slot), GameState.get_laser_cd_bonus(slot)]
	return result

func _matches_rewards(earned: bool) -> bool:
	var values := _both_rewards()
	var kinds := ["bullet_count", "damage", "speed", "laser_cd"]
	var amounts := [1.0, 2.0, 0.10, 1.0]
	for slot: int in [1, _guest]:
		var reward: String = _expected.get(slot, "") if earned else ""
		for i in kinds.size():
			if not is_equal_approx(float(values[slot][i]), amounts[i] if kinds[i] == reward else 0.0):
				return false
	return true

func _bonus_rows() -> Array[String]:
	var rows: Array[String] = []
	for row in _main._hud._powerup_display.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("boss_reward_type"):
			rows.append(str(row.get_meta("boss_reward_type")))
	return rows

func _local_expected_rows() -> Array[String]:
	var rows: Array[String] = []
	if _expected.has(_local_slot):
		rows.append(_expected[_local_slot])
	return rows

func _replay_receipt(own_type: String) -> void:
	if _role == "host":
		_main.on_local_boss_reward_feedback(own_type)
		_main._rpc_show_boss_reward_feedback.rpc_id(NetworkManager.recovery.guest_wire, _expected.get(_guest, "damage"))

func _capture(stage: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var drawn := [false]
	var mark_drawn := func(): drawn[0] = true
	RenderingServer.frame_post_draw.connect(mark_drawn, CONNECT_ONE_SHOT)
	if not await _wait_until(func(): return drawn[0], 0.5):
		if RenderingServer.frame_post_draw.is_connected(mark_drawn):
			RenderingServer.frame_post_draw.disconnect(mark_drawn)
		_check("captured_" + stage, false, "no render callback before capture deadline")
		return
	var path := _capture_dir.path_join("%s-%s-%s.png" % [_scenario, stage, _role])
	var image := get_viewport().get_texture().get_image()
	_check("captured_" + stage, image != null and image.save_png(path) == OK, path)

func _require(name: String, ok: bool) -> bool:
	_check(name, ok, "")
	if not ok:
		get_tree().quit(_summarize())
	return ok

func _barrier(stage: String) -> void:
	if _role == "host":
		_host_marker.rpc(stage)
	else:
		_guest_marker.rpc_id(1, stage)
	if not await _wait_until(func(): return _steps.has(stage), 5):
		_check("barrier_" + stage, false, "")

@rpc("authority", "reliable", "call_remote")
func _host_marker(stage: String) -> void:
	_steps[stage] = true

@rpc("any_peer", "reliable", "call_remote")
func _guest_marker(stage: String) -> void:
	if multiplayer.is_server():
		_steps[stage] = true
