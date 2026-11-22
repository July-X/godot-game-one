extends Node

const Route := preload("res://scenes/rift_route_trial.tscn")
const Landing := preload("res://scenes/ui/title_screen.tscn")
const Main := preload("res://scenes/main.tscn")
const Trial := preload("res://scripts/rift_route_trial.gd")
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
	_check("choose_once", UpgradeDraft.choose_card(1, 0) and not UpgradeDraft.choose_card(1, 1))
	_world.trial_tick = Trial.ELITE_LEG + 154
	await _frames(3)
	_check("existing_elite_spawns", is_instance_valid(_world._elite) and GameState.elite_encounter_count == 1)
	_world.trial_tick = Trial.SETTLE_TICK - 1
	await _frames(4)
	_check("untouched_elite_can_be_bypassed", not is_instance_valid(_world._elite))
	_world.trial_tick = Trial.BOSS_LEG - 1
	await _frames(4)
	_check("existing_boss_spawns_once", is_instance_valid(_world._boss) and GameState.boss_encounter_count == 1)
	if is_instance_valid(_world._boss):
		var first_boss := _world._boss
		first_boss.take_damage(first_boss.get_max_shield_hp(), 1)
		first_boss.take_damage(first_boss.get_network_max_health(), 1)
	await _frames(4)
	if "--capture" not in OS.get_cmdline_user_args():
		_check("fatal_boss_hull_settles_trial_win", _world.finished and _world._result.text.begins_with("通关"))
	_check("no_leaderboard_entry_for_win", Leaderboard.get_entries() == baseline)
	_world._restart.call_deferred()
	await get_tree().scene_changed
	_world = get_tree().current_scene
	_check("retry_resets_trial_state", _world is Trial and _world.trial_tick < 10 and GameState.boss_encounter_count == 0
		and GameState.get_card_stacks(1).is_empty() and not UpgradeDraft.has_draft(1))
	_world._player.force_kill()
	await _frames(4)
	_check("death_settles_trial_not_normal_hud", _world.finished and _world._result.text.begins_with("被击落")
		and not _world._hud._game_over_panel.visible and Leaderboard.get_entries() == baseline)
	_world._return_to_title.call_deferred()
	await get_tree().scene_changed
	get_tree().current_scene._on_single_pressed()
	await get_tree().scene_changed
	_check("ordinary_run_keeps_original_rank_and_state", get_tree().current_scene.scene_file_path == Main.resource_path
		and Leaderboard.get_entries() == baseline and GameState.get_card_stacks(1).is_empty()
		and GameState.boss_encounter_count == 0 and GameState.kills_for_next_level < 100)
	get_tree().quit(int(_failed != 0))
