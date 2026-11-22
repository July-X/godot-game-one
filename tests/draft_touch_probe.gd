extends "res://tests/lan_probe.gd"

const MOBILE := preload("res://scenes/ui/mobile_controls.tscn")
const MAIN := preload("res://scenes/main.tscn")
var _hud
var _stick
var _pilot
var _pid := 1
var _stage := 0
var _chosen: Array[Dictionary] = []
var _shots := {}
var _safe: Rect2

func _process(_delta: float) -> void:
	pass

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var wide := args.has("wide")
	var size := Vector2i(1600 if wide else 1280, 720)
	var window := get_window()
	window.content_scale_size = size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	Input.emulate_mouse_from_touch = true
	if _role in ["host", "client"]:
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if err != OK or not await _wait_until(NetworkManager.is_online, 8):
			_exit_failure("connected")
			return
		_pid = multiplayer.get_unique_id()
	_main = MAIN.instantiate()
	_stick = MOBILE.instantiate()
	_main.add_child(_stick)
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main._asteroid_timer = INF
	_main._wave_director._cooldown = INF
	if not await _wait_until(func(): return not NetworkManager.is_online() or _cond_both_players(), 6):
		_exit_failure("pilots_ready")
		return
	_pilot = _main._players.get(_pid, _main._player)
	_hud = _main._hud
	_safe = Rect2(Vector2(72 if wide else 14, 23), Vector2(size) - Vector2(92, 37))
	_hud._layout_in_safe_area(_safe)
	_stick._layout_in_safe_area(_safe)
	_main.child_entered_tree.connect(_observe)
	UpgradeDraft.card_chosen.connect(_record_choice)
	_check("mobile_test_coordinates", _pilot._motion.mobile_mode and _hud._safe_rect == _safe, str(_safe))
	var edge := _safe.position + Vector2(90, _safe.size.y * 0.79)
	_touch(0, edge, true)
	_drag(0, edge + Vector2(0, -85), edge)
	_check("move_held_before_upgrade", _stick._move_touch_id == 0 and _pilot._motion.touch_move.y < -0.7, "")
	if NetworkManager.is_online() and _role == "client":
		_mark.rpc_id(1, 1)
	elif _role == "host" and not await _wait_until(func(): return _stage >= 1, 5):
		_exit_failure("both_holding_before_upgrade")
		return
	if _role != "client":
		_level_up()
	if not await _wait_until(func(): return _hud._draft_panel.visible and _hud._draft_card_buttons.size() == 3, 5):
		_exit_failure("draft_open")
		return
	await get_tree().process_frame
	_check("opening_preserves_left_touch_and_direction",
		_stick._move_touch_id == 0 and _pilot._motion.touch_move.y < -0.7,
		"owner=%d axis=%s" % [_stick._move_touch_id, _pilot._motion.touch_move])
	var after_open: Vector2 = _pilot.global_position
	_drag(0, edge + Vector2(92, 0), edge + Vector2(0, -85))
	var laser: Vector2 = _hud._skill_slots[0].button.get_global_rect().get_center()
	var initial_cd := GameState.get_laser_cooldown(_pid)
	_tap(1, laser)
	var laser_requested_once: bool = _pilot._action_router._queued_actions == ["laser"]
	var expected_lasers := 3 if _role == "client" else 6
	var fired := await _wait_until(func(): return _shot_count("laser", _pid) >= expected_lasers, 1.4)
	_check("second_finger_laser_uses_real_projectiles_and_cooldown",
		laser_requested_once and initial_cd == 0 and fired and _shot_count("laser", _pid) == expected_lasers
		and GameState.get_laser_cooldown(_pid) > 0,
		"projectiles=%d cd=%.2f" % [_shot_count("laser", _pid), GameState.get_laser_cooldown(_pid)])
	await _wait_seconds(0.09)
	_check("actual_movement_continues_while_skill_fires",
		_stick._move_touch_id == 0 and _pilot.global_position.x > after_open.x + 5 and UpgradeDraft.has_draft(_pid),
		"from=%s to=%s" % [after_open, _pilot.global_position])
	var card: Vector2 = _hud._draft_card_buttons[1].get_global_rect().get_center()
	_drag(0, card, edge + Vector2(92, 0))
	_touch(0, card, false)
	_check("left_release_over_card_stops_without_choosing",
		_stick._move_touch_id == -1 and _pilot._motion.touch_move == Vector2.ZERO and UpgradeDraft.has_draft(_pid), "")

	# 计时栏碰得到面板矩形但不占卡片热区，左手可在这里重新起手。
	var blank: Vector2 = _hud._draft_time_bar.get_global_rect().position + Vector2(14, 2)
	_touch(0, blank, true)
	_drag(0, blank + Vector2(-90, 0), blank)
	_check("blank_draft_panel_space_accepts_new_left_touch",
		_stick._move_touch_id == 0 and _pilot._motion.touch_move.x < -0.7, "point=%s owner=%d" % [blank, _stick._move_touch_id])
	var scatter: Vector2 = _hud._skill_slots[1].button.get_global_rect().get_center()
	_tap(1, scatter)
	var scatter_requested_once: bool = _pilot._action_router._queued_actions == ["skill"]
	var expected_scatter := 16 if _role == "client" else 32
	var scattered := await _wait_until(func(): return _shot_count("scatter", _pid) >= expected_scatter, 1.4)
	_check("second_finger_scatter_uses_real_projectiles_and_cooldown", scatter_requested_once and scattered
		and _shot_count("scatter", _pid) == expected_scatter and GameState.get_skill_cooldown(_pid) > 0
		and UpgradeDraft.has_draft(_pid), "projectiles=%d cd=%.2f" % [_shot_count("scatter", _pid), GameState.get_skill_cooldown(_pid)])
	var dash: Vector2 = _hud._skill_slots[2].button.get_global_rect().get_center()
	_tap(1, dash)
	var dashed := await _wait_until(_pilot.is_dash_invincible, 0.5)
	_check("second_finger_dash_uses_movement_and_cooldown",
		dashed and _pilot.get_dash_cooldown_ratio() > 0 and UpgradeDraft.has_draft(_pid), "")
	var expected := str(UpgradeDraft.get_draft(_pid).cards[1])
	_tap(1, card)
	_check("second_finger_card_only_applies_once", await _wait_until(func():
		return _chosen.size() == 1 and not _hud._draft_panel.visible, 2)
		and _chosen[0].source == "tap" and GameState.get_card_stacks(_pid) == {expected: 1}
		and _shot_count("laser", _pid) == expected_lasers and _shot_count("scatter", _pid) == expected_scatter,
		"choices=%s stacks=%s laser=%d scatter=%d" % [
			_chosen, GameState.get_card_stacks(_pid), _shot_count("laser", _pid), _shot_count("scatter", _pid)])
	_check("choosing_card_does_not_steal_left_touch", _stick._move_touch_id == 0, "")
	_touch(0, blank, false)
	_check("release_clears_joystick", _stick._move_touch_id == -1 and _pilot._motion.touch_move == Vector2.ZERO, "")
	await _check_timeout(edge)
	get_tree().quit(_summarize())

func _check_timeout(edge: Vector2) -> void:
	_touch(0, edge, true)
	_drag(0, edge + Vector2(0, -90), edge)
	if _role == "client":
		_mark.rpc_id(1, 2)
	elif _role == "host" and not await _wait_until(func(): return _stage >= 2, 5):
		_check("both_ready_for_timeout_batch", false, "")
		return
	if _role != "client":
		_level_up()
	var started := Time.get_ticks_msec()
	_check("second_draft_opens_and_keeps_joystick", await _wait_until(func(): return _hud._draft_panel.visible, 5)
		and _stick._move_touch_id == 0, "")
	var timed := await _wait_until(func(): return _chosen.size() == 2 and not _hud._draft_panel.visible, 12)
	var elapsed := Time.get_ticks_msec() - started
	_check("one_authoritative_timeout_with_left_touch_still_held", timed and _chosen[1].source == "timeout"
		and _chosen[1].index == 0 and elapsed >= 9450 and _stick._move_touch_id == 0,
		"elapsed_ms=%d choices=%s" % [elapsed, _chosen])
	_touch(0, edge, false)
	_check("release_after_timeout_clears_joystick", _stick._move_touch_id == -1 and _pilot._motion.touch_move == Vector2.ZERO, "")
	# 给对端收完最后一个可靠快照。
	await _wait_seconds(0.65)

func _level_up() -> void:
	for i in GameState.kills_for_next_level - GameState.kills:
		GameState.add_kill(1)

func _observe(node: Node) -> void:
	if node.scene_file_path in ["res://scenes/entities/bullet.tscn", "res://scenes/entities/laser_bolt.tscn"]:
		_observe_projectile.call_deferred(node)

func _observe_projectile(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var kind := "laser" if node.scene_file_path.ends_with("laser_bolt.tscn") else "scatter"
	# 加入端激光有本机预览与房主回传，只用后者验证实际联机出弹。
	if kind == "laser" and _role == "client" and not node._is_network_ghost:
		return
	if kind == "scatter" and (not node._is_player_bullet or node._speed != 500.0):
		return
	var key := [kind, node.owner_peer_id]
	_shots[key] = _shots.get(key, 0) + 1

func _shot_count(kind: String, pid: int) -> int:
	return _shots.get([kind, pid], 0)

func _record_choice(pid: int, _id: String, index: int) -> void:
	if pid == _pid:
		_chosen.append({"source": UpgradeDraft.get_draft(pid).source, "index": index})

func _tap(index: int, at: Vector2) -> void:
	_touch(index, at, true)
	_touch(index, at, false)

func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * at
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _drag(index: int, at: Vector2, from: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	var transform := get_viewport().get_final_transform()
	event.index = index
	event.position = transform * at
	event.relative = event.position - transform * from
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _exit_failure(label: String) -> void:
	_check(label, false, "")
	get_tree().quit(_summarize())

@rpc("any_peer", "reliable")
func _mark(stage: int) -> void:
	if multiplayer.is_server():
		_stage = maxi(_stage, stage)
