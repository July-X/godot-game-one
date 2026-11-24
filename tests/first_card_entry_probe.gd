extends Node

const TITLE := "res://scenes/ui/title_screen.tscn"
const SOLO := "res://scenes/main.tscn"
const TRIAL_A := "res://scenes/first_card_trial_a.tscn"
const TRIAL_B := "res://scenes/first_card_trial_b.tscn"
const TrialGame := preload("res://scripts/battle/trials/first_card_trial.gd")
const SafeArea := preload("res://scripts/ui/battle_safe_area.gd")
var passed := 0
var failed := 0
var opening_state: Array

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var window := get_window()
	var wide := DisplayServer.get_name() == "headless" or window.size.aspect() > 1.9
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = Vector2i(1600 if wide else 1280, 720)
	if DisplayServer.get_name() == "headless":
		window.size = Vector2i(2400, 1080)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		get_tree().node_added.connect(_prepare_mobile_scene)
	_check("normal_launch_without_user_args", OS.get_cmdline_user_args().is_empty())
	get_tree().current_scene = null
	get_tree().change_scene_to_file(TITLE)
	var title := await _wait_for_scene(TITLE)
	if title == null:
		return
	var view := get_viewport().get_visible_rect()
	var safe := Rect2(Vector2(76, 24), view.size - Vector2(110, 96))
	var screen := get_viewport().get_screen_transform() * safe
	title._layout_in_safe_area(SafeArea.from_display(get_viewport(), screen))
	await get_tree().process_frame
	var usable := safe.grow(-SafeArea.MENU_MARGIN)
	_check("title_button_rectangles_inside_inset", usable.encloses(title.get_node("Menu/BtnSingle").get_global_rect())
		and usable.encloses(title.get_node("Menu/BtnMultiplayer").get_global_rect())
		and usable.encloses(title.get_node("Menu/BtnFirstCard").get_global_rect()))
	await _tap(title.get_node("Menu/BtnMultiplayer"))
	var lobby := await _wait_for_scene("res://scenes/ui/lobby.tscn")
	if lobby == null:
		return
	lobby._layout_in_safe_area(safe)
	await get_tree().process_frame
	_check("lobby_button_rectangles_inside_inset", usable.encloses(lobby.get_node("VBox/PanelModeSelect/BtnBeHost").get_global_rect())
		and usable.encloses(lobby.get_node("VBox/PanelModeSelect/BtnBeClient").get_global_rect())
		and usable.encloses(lobby.get_node("VBox/BtnBack").get_global_rect()))
	await _tap(lobby.get_node("VBox/BtnBack"))
	title = await _wait_for_scene(TITLE)
	if title == null:
		return
	await _tap(title.get_node("Menu/BtnFirstCard"))
	var choices: VBoxContainer = title.get_node("TrialChoices")
	_check("neutral_menu_opens", choices.visible and not title.get_node("Menu/BtnSingle").is_visible_in_tree()
		and choices.get_node("A").text == "试飞 A" and choices.get_node("B").text == "试飞 B")
	title._layout_in_safe_area(SafeArea.from_display(get_viewport(), screen))
	await get_tree().process_frame
	_check("chooser_inside_inset", safe.encloses(choices.get_global_rect())
		and safe.encloses(choices.get_node("A").get_global_rect()) and safe.encloses(choices.get_node("B").get_global_rect()))
	await _tap(choices.get_node("Back"))
	_check("touch_cancel_restores_title", get_tree().current_scene == title and not choices.visible and title.get_node("Menu/BtnSingle").is_visible_in_tree())
	title.get_node("Menu/BtnFirstCard").grab_focus()
	await _key(KEY_ENTER)
	_check("keyboard_can_open_chooser", choices.visible)
	await _key(KEY_W)
	_check("chooser_holds_during_single_shortcut", get_tree().current_scene == title and choices.visible)
	await _key(KEY_ESCAPE)
	_check("keyboard_cancel_restores_title", get_tree().current_scene == title and not choices.visible)
	title.get_node("Menu/BtnSingle").grab_focus()
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	_check("gamepad_moves_title_focus", title.get_node("Menu/BtnMultiplayer").has_focus())

	for variant in ["A", "B"]:
		await _tap(title.get_node("Menu/BtnFirstCard"))
		if variant == "A":
			await _capture_chooser()
		await _tap(title.get_node("TrialChoices/" + variant))
		if not await _play_version(variant):
			return
		title = await _wait_for_scene(TITLE)
		if title == null:
			return
		_check(variant + "_return_clears_chooser", not title.get_node("TrialChoices").visible and title.get_node("Menu/BtnFirstCard").is_visible_in_tree())
	title.get_node("Menu/BtnFirstCard").grab_focus()
	await _key(KEY_ENTER)
	title.get_node("TrialChoices/B").grab_focus()
	await _key(KEY_ENTER)
	var keyboard_trial := await _wait_for_scene(TRIAL_B) as TrialGame
	if keyboard_trial == null:
		return
	_check("keyboard_can_choose_version", keyboard_trial._show_action_hint and UpgradeDraft.has_draft(1))
	await _mouse_click(keyboard_trial.get_node("TrialUI/Options/Back"))
	title = await _wait_for_scene(TITLE)
	if title == null:
		return
	_check("mouse_can_return_to_title", title.get_node("Menu/BtnFirstCard").is_visible_in_tree())
	await _tap(title.get_node("Menu/BtnSingle"))
	var solo := await _wait_for_scene(SOLO)
	if solo == null:
		return
	await _start_steering(solo, "solo", Vector2.RIGHT)
	_release_stick(solo, "solo")
	_finish()

func _prepare_mobile_scene(node: Node) -> void:
	if node.scene_file_path in [SOLO, TRIAL_A, TRIAL_B]:
		# 模拟手机先创建摇杆再创建飞机，实际信号由玩家入场逻辑绑定。
		node._spawn_mobile_controls()

func _play_version(variant: String) -> bool:
	var path := TRIAL_A if variant == "A" else TRIAL_B
	var trial := await _wait_for_scene(path) as TrialGame
	if trial == null:
		return false
	var draft := UpgradeDraft.get_draft(1)
	var state := [trial._player.position, GameState.level, GameState.total_kills, GameState.get_current_health(1), draft.get("cards")]
	if variant == "A":
		opening_state = state
	_check(variant + "_same_first_offer", state == opening_state and state[0] == trial.get_viewport_rect().size * Vector2(.50, .78)
		and state[1] == 2 and state[2] == 0 and state[4] == trial.FIRST_OFFER and float(draft.get("left", 0)) > 9.8
		and not trial._action_hint.visible and trial.trial_tick == -1)
	await _start_steering(trial, variant + "_draft", Vector2.LEFT)
	_check(variant + "_draft_only_moves", trial.trial_tick == -1 and UpgradeDraft.has_draft(1)
		and get_tree().get_nodes_in_group("player_bullets").is_empty()
		and get_tree().get_nodes_in_group("enemies").is_empty())
	var card: Button = trial._hud._draft_row.get_child(0)
	var before_choice: Vector2 = trial._player.global_position
	await _tap(card, 1)
	if not await _at(trial, 4):
		return false
	_check(variant + "_tap_selects_card_once", UpgradeDraft.get_draft(1).get("source") == "tap"
		and GameState.get_card_stacks(1) == {"pierce": 1} and not trial._hud._draft_panel.visible)
	_check(variant + "_hint_only_after_selection", trial._action_hint.visible == (variant == "B")
		and not get_tree().paused and trial._recording)
	_check_steering(trial, variant + "_held_through_choice", before_choice, Vector2.LEFT, 1.0)
	_release_stick(trial, variant)
	await _start_steering(trial, variant + "_repress", Vector2.UP)
	_release_stick(trial, variant + "_repress")
	if not await _at(trial, trial.END_TICK):
		return false
	var before := trial.get_instance_id()
	await _tap(trial.get_node("TrialUI/Options/Retry"))
	trial = await _wait_for_scene(path, before) as TrialGame
	if trial == null:
		return false
	_check(variant + "_retry_keeps_variant", trial.trial_tick == -1 and UpgradeDraft.has_draft(1)
		and trial._show_action_hint == (variant == "B") and not trial._action_hint.visible)
	await _tap(trial.get_node("TrialUI/Options/Back"))
	return true

func _start_steering(scene: Node, label: String, direction: Vector2) -> void:
	var stick = scene.get_node("MobileControls")
	var center := Vector2(160.0, get_viewport().get_visible_rect().end.y - 164)
	var origin: Vector2 = scene._player.global_position
	_touch(center, true, 0)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = get_viewport().get_final_transform() * (center + direction * 84.0)
	_send_touch_event(drag)
	for i in 18:
		await get_tree().physics_frame
	_check_steering(scene, label, origin, direction, 20.0)

func _check_steering(scene: Node, label: String, origin: Vector2, direction: Vector2, min_distance: float) -> void:
	var stick = scene.get_node("MobileControls")
	var player = scene._player
	var move: Vector2 = direction * 0.75
	var cap: Vector2 = stick._knob_node.get_rect().get_center()
	var base: Vector2 = stick._base_node.get_rect().get_center()
	var visual_travel: float = (stick._base_node.size.x - stick._knob_node.size.x) * 0.5
	_check(label + "_cap_follows_finger", stick._move_touch_id == 0 and stick._move_vector.is_equal_approx(move)
		and cap.is_equal_approx(base + move * visual_travel))
	var travel: Vector2 = player.global_position - origin
	var nose: Vector2 = Vector2.UP.rotated(player.global_rotation)
	_check(label + "_pilot_moves_and_turns", player._motion.mobile_mode and player._motion.touch_move.is_equal_approx(move)
		and travel.dot(direction) > min_distance and nose.dot(direction) > 0.99)
	print("[ENTRY] ", label, " stick=", stick._move_vector, " player_input=", player._motion.touch_move, " travel=", travel, " nose=", nose)

func _release_stick(scene: Node, label: String) -> void:
	var stick = scene.get_node("MobileControls")
	_touch(stick._joystick_center, false, 0)
	_check(label + "_release_zeros_stick", stick._move_touch_id == -1 and stick._move_vector == Vector2.ZERO
		and scene._player._motion.touch_move == Vector2.ZERO
		and not stick._ui_root.visible)

func _wait_for_scene(path: String, previous := 0) -> Node:
	for i in 100:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path == path and scene.get_instance_id() != previous:
			await get_tree().process_frame
			return scene
	_check("loaded_" + path, false)
	_finish()
	return null

func _at(trial: TrialGame, tick: int) -> bool:
	var deadline := Engine.get_physics_frames() + 700
	while trial.trial_tick < tick and Engine.get_physics_frames() < deadline:
		await get_tree().physics_frame
	if trial.trial_tick >= tick:
		return true
	_check("reached_tick_%d" % tick, false)
	_finish()
	return false

func _tap(button: Button, index := 0) -> void:
	var at := button.get_global_rect().get_center()
	for pressed in [true, false]:
		_touch(at, pressed, index)
		await get_tree().process_frame

func _touch(at: Vector2, pressed: bool, index: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = get_viewport().get_final_transform() * at
	touch.pressed = pressed
	_send_touch_event(touch)

func _send_touch_event(event: InputEvent) -> void:
	# 真正走视口的缩放、触摸分发与鼠标合成。
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _mouse_click(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func _capture_chooser() -> void:
	var output := OS.get_environment("SBH_ENTRY_CAPTURE")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check("captured_chooser", get_viewport().get_texture().get_image().save_png(output) == OK)

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[ENTRY] ", label, " pass=", ok)

func _finish() -> void:
	print("[TRIAL] VERDICT pass=", passed, " failed=", failed)
	get_tree().quit(0 if failed == 0 else 1)
