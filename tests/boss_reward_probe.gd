extends Node
## Title → ordinary battle. The fixture pins the draw immediately before the normal
## death listener and shortens the setup fight; impacts, delivery and use remain real.

const BULLET := preload("res://scenes/entities/bullet.tscn")
const BOSS_AT := Vector2(640, 190)
const PLAYER_AT := Vector2(640, 560)
const REWARD_AMOUNTS := {"bullet_count": 1.0, "damage": 2.0, "speed": 0.10, "laser_cd": 1.0}

var _battle: Node
var _pilot: Node
var _reward_type := ""
var _capture_dir := ""
var _baseline := false
var _capped := false
var _parallel_rows := false
var _cue_stream: AudioStream
var _cue_playbacks := {}
var _passed := 0
var _failed := 0
var _first_tick := 0
var _drops: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	if _cue_stream == null:
		return
	for voice: AudioStreamPlayer in SFX.get_children():
		if voice.playing and voice.stream == _cue_stream:
			var playback := voice.get_stream_playback()
			if playback:
				_cue_playbacks[playback.get_instance_id()] = true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not REWARD_AMOUNTS.has(args[0]):
		_check("configured_reward", false, str(args))
		_finish()
		return
	_reward_type = args[0]
	_baseline = args.has("baseline")
	_capped = args.has("capped")
	_parallel_rows = args.has("parallel_rows")
	if args.has("capture"):
		_capture_dir = args[args.find("capture") + 1]
	if args.has("mute"):
		AudioServer.set_bus_mute(0, true)
	if not _baseline:
		_cue_stream = SFX.get("_stream_boss_reward")

	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("Menu/BtnSingle").pressed.emit()
	await get_tree().scene_changed
	_battle = get_tree().current_scene
	_check("ordinary_title_entry", _battle.scene_file_path == "res://scenes/main.tscn"
		and GameState.normal_growth_enabled, _battle.scene_file_path)
	_prepare_pilot()
	_first_tick = Engine.get_physics_frames()
	if _capped:
		GameState._state(1).extra_bullet_count = 12
		GameState._sync_local_view()
	if _parallel_rows:
		GameState.apply_reward("damage" if _reward_type == "laser_cd" else "laser_cd", 1)
	var expected_before := _reward_stats()
	if not _baseline:
		_battle.on_local_boss_reward_feedback(_reward_type)
	await _ticks(5)
	if not _baseline:
		_check("event_without_earn_is_silent", not _body_visible() and _cue_playbacks.is_empty(), "")

	var before_use: Variant = await _operate(false)
	_clear_player_projectiles()
	_reset_pose(PLAYER_AT)
	await _ticks(6)

	seed(47681)
	var earned := await _win_first_boss()
	_check("real_projectile_defeat_grants_only_chosen_reward", earned, str(_reward_stats()))
	if not earned:
		_finish()
		return
	expected_before[_reward_type] += REWARD_AMOUNTS[_reward_type]
	_check("reward_amount_round_trips_unchanged", _stats_match(_reward_stats(), expected_before), str(_reward_stats()))
	_check("six_authored_drops", _drops == ["core", "heal", "speed", "power", "core", "heal"], str(_drops))
	if not _baseline:
		_check("local_ship_shows_earned_feedback", _body_visible(), "")
		_check_earned_row()
	_check("readiness_at_award_is_actual", _reward_type != "laser_cd" or is_equal_approx(GameState.get_laser_cooldown(1), 10.0),
		"cooldown=%.2f" % GameState.get_laser_cooldown(1))
	await _ticks(4)
	await _capture("earned")
	if not _baseline:
		_check("one_real_acquisition_voice", _cue_playbacks.size() == 1, str(_cue_playbacks.size()))
		if _reward_type == "laser_cd":
			_check("laser_icon_waits_for_accepted_use", _battle._hud._first_boss_laser_pending
				and _battle._hud._first_boss_laser_tween == null, "")
		_battle.on_local_boss_reward_feedback(_reward_type)
	await _ticks(3)
	if not _baseline:
		_check("duplicated_receipt_adds_no_voice", _cue_playbacks.size() == 1, str(_cue_playbacks.size()))

	var after_use: Variant = await _operate(true)
	_compare_operation(before_use, after_use)
	_clear_player_projectiles()
	await _ticks(36)
	if not _baseline:
		_check("acquisition_ends_without_replay", not _body_visible() and _cue_playbacks.size() == 1, "")
		_battle.on_local_boss_reward_feedback(_reward_type)
		await _ticks(4)
		_check("late_receipt_cannot_rearm", not _body_visible() and _cue_playbacks.size() == 1, "")

	var previous := _battle
	_battle._restart()
	await get_tree().scene_changed
	_battle = get_tree().current_scene
	_prepare_pilot()
	_check("ordinary_retry_has_fresh_stats", not is_same(previous, _battle) and _total_reward() == 0.0, str(_reward_stats()))
	if not _baseline:
		_battle.on_local_boss_reward_feedback(_reward_type)
		await _ticks(5)
		_check("old_event_after_retry_cannot_ignite", not _body_visible() and _cue_playbacks.size() == 1, "")
	_finish()

func _prepare_pilot() -> void:
	_battle._wave_director._cooldown = 90.0
	_battle._asteroid_timer = 90.0
	_pilot = _battle._player
	_pilot.set_physics_process(false)
	_pilot.set_process_unhandled_input(false)
	_pilot._motion.mobile_mode = true
	_battle._spawn_mobile_controls()
	_battle._hud._layout_battle_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reset_pose(PLAYER_AT)

func _reset_pose(at: Vector2) -> void:
	_pilot._motion.stop_for_downed()
	_pilot.position = at
	_pilot.rotation = 0.0
	_pilot.reset_physics_interpolation()
	_pilot._combat._shoot_timer = 90.0

func _win_first_boss() -> bool:
	_battle._spawn_boss(GameState.FIRST_BOSS_LEVEL)
	var boss: Node = _battle._boss
	boss._stop_entry_motion()
	boss.global_position = BOSS_AT
	boss.reset_physics_interpolation()
	boss.set_physics_process(false)
	_battle.child_entered_tree.connect(_observe_drop)
	# Re-seed before the existing death listener so all builds draw the same actual pool entry.
	var pool: Array[String] = _battle._boss_reward_pool()
	var draw_seed := 0
	for trial_seed in range(1, 128):
		seed(trial_seed)
		if pool.pick_random() == _reward_type:
			draw_seed = trial_seed
			break
	_check("fixed_draw_uses_original_pool", draw_seed > 0 and pool.size() == REWARD_AMOUNTS.size(), str(pool))
	var original := Callable(_battle, "_on_boss_died")
	boss.boss_died.disconnect(original)
	boss.boss_died.connect(func(): seed(draw_seed))
	boss.boss_died.connect(original)
	await _ticks(17)
	await _capture("shield_raised")
	var shield := float(boss.get_shield_hp())
	_shoot_boss(shield)
	for tick in 24:
		if not boss.has_impact_shield():
			break
		await _ticks(1)
	_check("fixture_round_really_breaks_shield", not boss.has_impact_shield(), "shield=%.2f" % boss.get_shield_hp())
	var score_before := GameState.score
	await _ticks(10)
	var hits := [0]
	var shot := _shoot_boss(float(boss.get_network_health()))
	shot.body_entered.connect(func(body): hits[0] += int(body == boss), CONNECT_ONE_SHOT)
	for tick in 28:
		if not is_instance_valid(boss):
			break
		await _ticks(1)
	# Body callback runs inside the physics batch; drop creation is deferred until that batch is over.
	await get_tree().process_frame
	return hits[0] == 1 and not is_instance_valid(boss) and GameState.score == score_before + 1000

func _shoot_boss(damage: float) -> Area2D:
	var bullet: Area2D = Pool.acquire("bullet", BULLET)
	_battle.add_child(bullet)
	bullet.setup(BOSS_AT + Vector2(0, 61), -PI * 0.5, ceili(damage), true, 1, 900.0, 1)
	return bullet

func _observe_drop(node: Node) -> void:
	if node.scene_file_path == "res://scenes/entities/powerup.tscn":
		_drops.append(node.get_powerup_type())

func _operate(earned: bool) -> Variant:
	_reset_pose(PLAYER_AT)
	match _reward_type:
		"speed":
			return await _move(earned)
		"laser_cd":
			return await _use_laser(earned)
		_:
			return await _fire_cannon(earned)

func _move(earned: bool) -> float:
	_pilot.set_physics_process(true)
	if earned:
		await _ticks(2)
		if not _baseline:
			_check("stationary_ship_reserves_thrust_cue", _pilot._feedback._reward_exhaust_boost == 0.0, "")
	_pilot._motion.handle_mobile_move(Vector2.RIGHT)
	await _ticks(2)
	if earned:
		if not _baseline:
			_check("real_displacement_exercises_tail_cue", _pilot.position.x > PLAYER_AT.x
				and _pilot._feedback._reward_exhaust_boost > 0.0, str(_pilot.position))
		await _capture("first_operation")
	await _ticks(33)
	var result: float = _pilot.velocity.x
	_pilot.set_physics_process(false)
	return result

func _use_laser(earned: bool) -> float:
	if earned:
		_pilot.request_action("laser")
		_pilot._combat.update(0.0)
		_check("active_cooldown_denies_cast", _laser_count() == 0 and GameState.get_laser_cooldown(1) == 10.0, "")
		if not _baseline:
			_check("denial_preserves_reward_cue", _battle._hud._first_boss_laser_pending, "")
		GameState.tick_laser_cooldown(10.0, 1)
	_pilot.request_action("laser")
	_pilot._combat.update(0.0)
	_check("accepted_cast_spawns_three_real_bolts", _laser_count() == 3, str(_laser_count()))
	if earned:
		if not _baseline:
			_check("accepted_cast_consumes_icon_cue", not _battle._hud._first_boss_laser_pending
				and _battle._hud._first_boss_laser_tween != null, "")
		await _capture("first_operation")
	return GameState.get_laser_cooldown(1)

func _fire_cannon(earned: bool) -> Dictionary:
	var target: CharacterBody2D
	if _reward_type == "damage":
		target = _battle._spawn_enemy_at(0, PLAYER_AT + Vector2(0, -112), 80, false)
		target.set_physics_process(false)
	_pilot._combat._shoot()
	var rounds := get_tree().get_nodes_in_group("player_bullets")
	var sample := {"rounds": rounds.size(), "damage": 0, "hp_loss": 0}
	if not rounds.is_empty():
		sample.damage = roundi(rounds[0]._damage)
	if earned:
		if not _baseline:
			var muzzle: Node = _pilot.get_node_or_null("FirstBossRewardMuzzle")
			var expected: bool = not _capped and is_instance_valid(muzzle) and muzzle.get_meta("reward_type", "") == _reward_type
			_check("genuine_volley_controls_muzzle_cue", expected or (_capped and not is_instance_valid(muzzle)), str(sample))
		await _capture("first_operation")
	if is_instance_valid(target):
		await _ticks(18)
		sample.hp_loss = 80 - target.health
		target.queue_free()
	return sample

func _compare_operation(before: Variant, after: Variant) -> void:
	var ok := false
	match _reward_type:
		"bullet_count":
			ok = before.rounds == (12 if _capped else 2) and after.rounds == (12 if _capped else 3)
		"damage":
			ok = before.rounds == 2 and after.rounds == 2 and before.damage == 4 and after.damage == 6 \
				and before.hp_loss == 8 and after.hp_loss == 12
		"speed":
			ok = absf(before - 260.0) < 1.0 and absf(after - 286.0) < 1.0
		"laser_cd":
			ok = is_equal_approx(before, 10.0) and is_equal_approx(after, 9.0)
	_check("real_operation_before_and_after", ok, "%s → %s" % [str(before), str(after)])

func _laser_count() -> int:
	var count := 0
	for node in _battle.get_children():
		count += int(node.scene_file_path == "res://scenes/entities/laser_bolt.tscn" and not node.is_queued_for_deletion())
	return count

func _clear_player_projectiles() -> void:
	for node in get_tree().get_nodes_in_group("player_bullets"):
		Pool.release(node)
	for node in _battle.get_children():
		if node.scene_file_path == "res://scenes/entities/laser_bolt.tscn":
			node.queue_free()

func _reward_stats() -> Dictionary:
	return {"bullet_count": float(GameState.get_extra_bullet_count(1)), "damage": float(GameState.get_extra_damage_bonus(1)),
		"speed": GameState.get_move_speed_bonus(1), "laser_cd": GameState.get_laser_cd_bonus(1)}

func _stats_match(actual: Dictionary, expected: Dictionary) -> bool:
	for key in expected:
		if not is_equal_approx(actual[key], expected[key]):
			return false
	return true

func _total_reward() -> float:
	var total := 0.0
	for amount in _reward_stats().values():
		total += amount
	return total

func _body_visible() -> bool:
	return _pilot.has_node("FirstBossRewardBody")

func _check_earned_row() -> void:
	var lit: Array[String] = []
	var present := 0
	for row in _battle._hud._powerup_display.get_children():
		if row.is_queued_for_deletion() or not row.has_meta("boss_reward_type"):
			continue
		present += 1
		var label: Label = row.get_child(0)
		if label.modulate.r > 1.02:
			lit.append(str(row.get_meta("boss_reward_type")))
	_check("only_actual_bonus_row_lights_up", lit == [_reward_type] and present >= (2 if _parallel_rows else 1),
		"rows=%d lit=%s" % [present, str(lit)])

func _capture(label: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	var point: Vector2 = _pilot.get_global_transform_with_canvas().origin
	var ok := frame.save_png(_capture_dir.path_join(label + ".png")) == OK
	_check("capture_" + label, ok, "tick=%d px=%.2f,%.2f" % [Engine.get_physics_frames() - _first_tick, point.x, point.y])

func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame

func _check(label: String, passed: bool, detail: String) -> void:
	_passed += int(passed)
	_failed += int(not passed)
	print("[BOSS REWARD] %s pass=%s %s" % [label, passed, detail])

func _finish() -> void:
	print("[BOSS REWARD] %s SUMMARY pass=%d failed=%d" % [_reward_type, _passed, _failed])
	get_tree().quit(int(_failed > 0))
