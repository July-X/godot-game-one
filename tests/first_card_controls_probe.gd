extends Node

const TRIAL := preload("res://scenes/first_card_trial.tscn")
const TrialGame := preload("res://scripts/first_card_trial.gd")
var trial: TrialGame
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1600 if "--wide" in args else 1280, 720)
	get_window().size = Vector2i(2400 if "--wide" in args else 1920, 1080)
	trial = TRIAL.instantiate()
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	trial._spawn_mobile_controls()
	var stick = trial.get_node("MobileControls")
	stick.move_input.connect(trial._player._motion.handle_mobile_move)
	trial._player._motion.mobile_mode = true
	trial._hud._layout_battle_hud()
	await get_tree().process_frame
	await get_tree().process_frame

	var hint := trial._action_hint
	var draft: Control = trial._hud._draft_panel
	_check("draft_starts_without_hint", draft.visible and not hint.visible
		and float(UpgradeDraft.get_draft(1).left) > 9.8)
	var card_button: Button = trial._hud._draft_row.get_child(1)
	var start_x: float = trial._player.position.x
	_touch(0, stick._joystick_center - Vector2(95, 0), true)
	for i in 14:
		await get_tree().physics_frame
	_check("pilot_moves_before_first_choice_without_starting_combat",
		trial._player.position.x < start_x - 20.0 and UpgradeDraft.has_draft(1)
		and trial.trial_tick == -1 and not hint.visible and get_tree().get_nodes_in_group("player_bullets").is_empty())
	start_x = trial._player.position.x
	_touch(1, card_button.get_global_rect().get_center(), true)
	_touch(1, card_button.get_global_rect().get_center(), false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_check("second_finger_selects_once", not UpgradeDraft.has_draft(1) and UpgradeDraft.get_draft(1).get("source") == "tap"
		and GameState.get_card_stacks(1) == {"splash": 1} and stick._move_touch_id == 0)
	if not await _at(22):
		return
	_check("pilot_moves_left_while_hint_drawn", trial._player.position.x < start_x - 25 and hint.visible and not draft.visible)
	var left_x: float = trial._player.position.x
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = get_viewport().get_final_transform() * (stick._joystick_center + Vector2(95, 0))
	get_viewport().push_input(drag)
	if not await _at(70):
		return
	_check("held_finger_can_move_right", stick._move_touch_id == 0 and trial._player.position.x > left_x + 25)
	var hit_radius: float = stick.joystick_radius * sqrt(1.5)
	var left_touch := Rect2(stick._joystick_center - Vector2.ONE * hit_radius, Vector2.ONE * hit_radius * 2)
	var skill_bar: Control = trial._hud._skill_bar
	var hint_rect := hint.get_global_rect()
	_check("hint_clear_of_touch_zones", not hint_rect.intersects(left_touch) and not hint_rect.intersects(skill_bar.get_global_rect())
		and hint.mouse_filter == Control.MOUSE_FILTER_IGNORE and get_viewport().gui_get_focus_owner() == null)
	for arg in args:
		if arg.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check("capture", get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture=")) == OK)
	_touch(0, stick._joystick_center + Vector2(95, 0), false)
	_check("release_stops_touch_input", stick._move_touch_id == -1 and trial._player._motion.touch_move == Vector2.ZERO)

	trial._player._invincible_timer = 0.0
	GameState.set_shield_layers(1, 0)
	var hp := GameState.get_current_health(1)
	var loss := trial._hp_lost
	trial._player.take_damage(2.0)
	GameState.heal(2, 1)
	_check("cumulative_loss_survives_heal", GameState.get_current_health(1) == hp and trial._hp_lost == loss + 2)
	_touch(0, stick._joystick_center + Vector2(60, 0), true)
	if not await _at(trial.END_TICK):
		return
	var retry: Button = trial.get_node("TrialUI/Options/Retry")
	_check("results_hide_and_release_the_stick", not stick.visible and not stick.is_processing_input()
		and stick._move_touch_id == -1 and trial._player._motion.touch_move == Vector2.ZERO)
	_check("hint_ended_before_retry", not hint.visible and retry.is_visible_in_tree() and not trial._recording)
	await get_tree().process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = retry.get_global_rect().get_center()
	click.pressed = true
	get_viewport().push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click, true)
	for i in 8:
		await get_tree().process_frame
	var restarted := get_tree().current_scene as TrialGame
	_check("retry_opens_original_cards_without_hint", is_instance_valid(restarted) and restarted != trial
		and not restarted._action_hint.visible and restarted.trial_tick == -1 and UpgradeDraft.has_draft(1))
	if not is_instance_valid(restarted) or is_instance_valid(trial):
		_finish()
		return
	trial = restarted
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	get_viewport().push_input(key, true)
	if not await _at(4):
		return
	_check("next_key_selects_and_gets_own_hint", UpgradeDraft.get_draft(1).source == "key" and trial._action_hint.visible)
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	_check("exit_while_hint_live_clears_trial", not is_instance_valid(trial) and not UpgradeDraft.has_draft(1))
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await get_tree().scene_changed
	_check("ordinary_battle_has_no_hint", not get_tree().current_scene.has_node("TrialUI") and GameState.level == 1)
	_finish()

func _at(tick: int) -> bool:
	var deadline := Engine.get_physics_frames() + 700
	while is_instance_valid(trial) and trial.trial_tick < tick and Engine.get_physics_frames() < deadline:
		await get_tree().physics_frame
	if is_instance_valid(trial) and trial.trial_tick >= tick:
		return true
	_check("reached_tick_%d" % tick, false)
	_finish()
	return false

func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * at
	event.pressed = pressed
	get_viewport().push_input(event)

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[CONTROLS] ", label, " pass=", ok)

func _finish() -> void:
	print("[TRIAL] VERDICT pass=", passed, " failed=", failed)
	get_tree().quit(0 if failed == 0 else 1)
