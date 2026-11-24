extends Node

const Route := preload("res://scenes/rift_route_trial.tscn")
const Landing := preload("res://scenes/ui/title_screen.tscn")
const Main := preload("res://scenes/main.tscn")
const Trial := preload("res://scripts/battle/trials/rift_route_trial.gd")
var _failed := 0
var _world: Trial

func _ready() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool) -> void:
	print("[RIFT_QA] ", label, " pass=", condition)
	_failed += int(not condition)

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _run() -> void:
	seed(90220)
	Leaderboard.add_entry(90220, 4)
	var baseline := Leaderboard.get_entries().duplicate(true)
	var title := Landing.instantiate()
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	await get_tree().process_frame
	_check("title_exposes_trial", is_instance_valid(title.get_node("Menu/BtnRiftRoute")))
	title.get_node("Menu/BtnRiftRoute").pressed.emit()
	await get_tree().scene_changed
	_world = get_tree().current_scene
	_check("starts_clean", _world is Trial and GameState.get_card_stacks(1).is_empty())
	# Wall-clock compression only: jump between waves, play the actual hooks.
	_world.trial_tick = Trial.CARD_TICK - 1
	await _frames(3)
	_check("authored_card_opens_once", UpgradeDraft.has_draft(1) and UpgradeDraft.get_draft(1).cards == ["pierce", "splash", "power"])
	_check("holds_schedule_not_global_tree", _world.trial_tick == Trial.CARD_TICK and not get_tree().paused)
	_check("solo_waits_for_card_before_build_hint", _world._build_hint_pending and _world._route_hint_left == 0.0)
	_check("choose_once", UpgradeDraft.choose_card(1, 0) and not UpgradeDraft.choose_card(1, 1))
	_check("solo_build_hint_uses_stage_row", _world._hud._phase_label.text == Trial.LEG_HINTS[Trial.Leg.BUILD])
	await _frames(121)
	_check("hint_expires_while_stage_clock_advances", _world._route_hint_left == 0.0
		and _world._hud._phase_label.text.ends_with(Trial.LEG_NAMES[Trial.Leg.BUILD]) and _world.trial_tick > Trial.CARD_TICK + 110)
	_world.trial_tick = Trial.ELITE_LEG - 1
	await _frames(2)
	_check("hunter_leg_replaces_build_hint", _world._hud._phase_label.text == Trial.LEG_HINTS[Trial.Leg.ELITE])
	_world.trial_tick = Trial.ELITE_LEG + 154
	await _frames(3)
	_check("existing_elite_spawns", is_instance_valid(_world._elite) and GameState.elite_encounter_count == 1)
	_world.trial_tick = Trial.SETTLE_TICK - 1
	await _frames(4)
	_check("untouched_elite_can_be_bypassed", not is_instance_valid(_world._elite))
	_check("settling_clears_hunter_hint", _world._route_hint_left == 0.0 and _world._hud._phase_label.text.contains("整备"))
	_world.trial_tick = Trial.BOSS_LEG - 1
	await _frames(4)
	_check("existing_boss_spawns_once", is_instance_valid(_world._boss) and GameState.boss_encounter_count == 1)
	_check("solo_boss_hint_uses_stage_row", _world._hud._phase_label.text == Trial.LEG_HINTS[Trial.Leg.BOSS])
	if is_instance_valid(_world._boss):
		var first_boss := _world._boss
		await _verify_exposure("bypass", 270)
		first_boss.take_damage(first_boss.get_max_shield_hp(), 1)
		first_boss.take_damage(first_boss.get_network_max_health(), 1)
	await _frames(4)
	if "--capture" not in OS.get_cmdline_user_args():
		_check("fatal_boss_hull_settles_trial_win", _world.finished and _world._result.text.begins_with("通关"))
		_check("solo_win_review_suggests_card_or_route", _world._result.text.ends_with("下局试试另一张首卡或另一条拦截路线"))
	_check("no_leaderboard_entry_for_win", Leaderboard.get_entries() == baseline)
	_world._restart.call_deferred()
	await get_tree().scene_changed
	_world = get_tree().current_scene
	_check("retry_resets_trial_state", _world is Trial and _world.trial_tick < 10 and GameState.boss_encounter_count == 0
		and GameState.get_card_stacks(1).is_empty() and not UpgradeDraft.has_draft(1))
	await _test_hunter_reward()
	_world._restart.call_deferred()
	await get_tree().scene_changed
	_world = get_tree().current_scene
	_world.trial_tick = Trial.BOSS_LEG - 1
	await _frames(2)
	await _verify_exposure("retry", 270)
	_world._player.force_kill()
	await _frames(4)
	_check("death_settles_trial_not_normal_hud", _world.finished and _world._result.text.begins_with("被击落")
		and not _world._hud._game_over_panel.visible and Leaderboard.get_entries() == baseline)
	_check("solo_zero_cut_review_suggests_first_intercept", _world.interruptions == 0
		and _world._result.text.ends_with("下局试着先切掉一股齐射"))
	_world._return_to_title.call_deferred()
	await get_tree().scene_changed
	get_tree().current_scene._on_single_pressed()
	await get_tree().scene_changed
	_check("ordinary_run_keeps_original_rank_and_state", get_tree().current_scene.scene_file_path == Main.resource_path
		and Leaderboard.get_entries() == baseline and GameState.get_card_stacks(1).is_empty()
		and GameState.boss_encounter_count == 0 and GameState.kills_for_next_level < 100)
	get_tree().quit(int(_failed != 0))

func _test_hunter_reward() -> void:
	_world.trial_tick = Trial.ELITE_LEG - 1
	await _frames(2)
	_world.trial_tick = Trial.ELITE_LEG + 154
	await _frames(2)
	var hunter := _world._elite
	if not is_instance_valid(hunter):
		_check("hunter_spawned_for_reward", false)
		return
	_world._player.set_physics_process(false)
	hunter.set_physics_process(false)
	hunter.global_position = Vector2(640, 360)
	hunter.take_damage(int(hunter.get_network_shield()), 1)
	# Stage the hull at one hit and let the real projectile finish the encounter.
	hunter.take_damage(floori((hunter.get_network_health() - 1.0) / 1.25), 1)
	_world._hitstop_left = 0.0
	Engine.time_scale = 1.0
	_world._player._combat._spawn_bullet(Vector2(640, 421), -PI * .5, 4, true, 1, 700.0)
	await _frames(15)
	_check("main_cannon_defeats_hunter", not is_instance_valid(hunter))
	_world.trial_tick = Trial.SETTLE_TICK - 1
	await _frames(2)
	_world.trial_tick = Trial.BOSS_LEG - 1
	await _frames(2)
	_check("defeat_does_not_move_boss_schedule", is_instance_valid(_world._boss) and _world.trial_tick == Trial.BOSS_LEG + 1)
	await _verify_exposure("rewarded_first", 330)
	await _verify_exposure("rewarded_second", 270)

func _verify_exposure(label: String, expected: int) -> void:
	var boss := _world._boss
	if not is_instance_valid(boss):
		_check(label + "_exposure", false)
		return
	boss._shoot_timer = 60.0
	_world._player.set_physics_process(false)
	boss.take_damage(boss.get_max_shield_hp(), 1)
	var elapsed := 0
	while not boss.has_impact_shield() and elapsed <= expected + 3:
		await get_tree().physics_frame
		elapsed += 1
	print("[RIFT_QA] ", label, " exposure_frames=", elapsed)
	_check(label + "_exposure", boss.has_impact_shield() and absi(elapsed - expected) <= 1)
