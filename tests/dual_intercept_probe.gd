extends "res://tests/lobby_start_probe.gd"
## 通过真实标题和大厅开局。单机环回用现有发现回调填入房间，避开共用广播端口。

class PulseSample extends Node2D:
	var peer_id := 0
	var damage_taken := 0.0
	func take_damage(amount: float) -> void:
		damage_taken += amount

const Trial := preload("res://scripts/battle/trials/rift_route_trial.gd")
const Ship := preload("res://scripts/battle/enemies/enemy.gd")
const Mothership := preload("res://scripts/battle/enemies/boss/boss.gd")
const Mobile := preload("res://scenes/ui/mobile_controls.tscn")
const TOUCH_AT := Vector2(130, 550)
const P1_MIDDLE := Vector2(515, 495)
const P2_MIDDLE := Vector2(765, 495)
var _trial: Trial
var _pilot: Player
var _controls: CanvasLayer
var _host := false
var _mode := "center"
var _evidence := ""
var _frames: Dictionary[String, Image] = {}
var _volleys: Array[Dictionary] = []
var _cuts: Array[String] = []
var _leaderboard: Array = []
var _entry_wire := 0

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	_host = args[0] == "host"
	_mode = args[1]
	_evidence = args[3] if args.size() > 3 else ""
	var wide := args[2] == "wide"
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1600 if wide else 960, 720)
	seed(90412)
	_leaderboard = Leaderboard.get_entries().duplicate(true)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	if _mode == "mismatch" and not _host:
		get_tree().current_scene.get_node("Menu/BtnMultiplayer").pressed.emit()
		await get_tree().scene_changed
		var ordinary := get_tree().current_scene
		ordinary._btn_be_client.pressed.emit()
		ordinary._deferred_join_host("127.0.0.1", NetworkManager.DEFAULT_PORT)
		await _verify_rejection(ordinary, false)
		_done()
		return
	get_tree().current_scene.get_node("Menu/BtnRiftRoute").pressed.emit()
	var entry := get_tree().current_scene.get_node("RiftChoices/DualIntercept") as Button
	_check("separate_title_entry", entry.is_visible_in_tree())
	entry.pressed.emit()
	await get_tree().scene_changed
	var lobby := get_tree().current_scene
	_check("existing_lobby_in_trial_mode", lobby.scene_file_path == LOBBY and lobby._dual_intercept)
	if _host:
		lobby._btn_be_host.pressed.emit()
		_check("host_advertises_trial_name", NetworkManager.is_online() and NetworkDiscovery._room_name == RouteRules.DUAL_INTERCEPT)
		NetworkDiscovery.stop_all()
		print("[DUAL] host_ready")
		if _mode == "mismatch":
			_check("prototype_shows_wrong_room_warning", await _wait_until(func():
				return lobby._lbl_host_status.text.contains("请确认双方都从标题进入"), 4.5))
			_check("wrong_room_leaves_start_disabled", lobby._compatible_peer == 0 and lobby._btn_rift.disabled)
			lobby._btn_rift.pressed.emit()
			await get_tree().process_frame
			_check("wrong_room_cannot_enter_battle", get_tree().current_scene == lobby)
			await get_tree().create_timer(.4).timeout
			_done()
			return
		_check("host_waits_for_named_preview_confirmation", await _wait_until(func():
			return lobby._btn_rift.is_visible_in_tree() and not lobby._btn_rift.disabled and not lobby._btn_start.visible, 8.0))
		lobby._btn_rift.pressed.emit()
	else:
		lobby._btn_be_client.pressed.emit()
		HarmonyBridge.report_discovered_host("普通房间", "127.0.0.1", 7999)
		HarmonyBridge.report_discovered_host(RouteRules.DUAL_INTERCEPT, "127.0.0.1", NetworkManager.DEFAULT_PORT)
		var key := "127.0.0.1:%d" % NetworkManager.DEFAULT_PORT
		_check("join_list_excludes_regular_room", lobby._host_buttons.size() == 1 and lobby._host_buttons.has(key))
		lobby._host_buttons[key].pressed.emit()
		_check("guest_confirms_prototype_preview", await _wait_until(func():
			return lobby._confirm_rift_rule.visible and lobby._lbl_join_status.text == RouteRules.DUAL_INTERCEPT, 7.0))
		lobby._confirm_rift_rule.pressed.emit()
	if not await _attach_battle(0):
		_done()
		return
	await _fly_trial(_mode)
	if _mode == "both":
		var old_round := GameState.get_sync_round()
		if _host:
			await get_tree().create_timer(.35).timeout
			_trial.get_node("TrialUI/Options/Buttons/Retry").pressed.emit()
		if await _attach_battle(old_round):
			_check("retry_clears_old_cuts", _trial.interruptions == 0 and _trial.leg == Trial.Leg.INTERCEPT)
			if not _host:
				_trial._rpc_route_result(old_round, "完成", 2, Trial.Leg.BOSS, {})
			_check("retry_ignores_old_result", not _trial.finished and _trial.interruptions == 0)
			await _fly_trial("retry-center")
	await get_tree().create_timer(.35).timeout
	_done()

func _attach_battle(old_round: int) -> bool:
	var ready := await _wait_until(func():
		var scene := get_tree().current_scene as Trial
		return (is_instance_valid(scene) and scene.dual_intercept and scene.remix
			and scene._player_entry_ready and scene._players.size() == 2 and GameState.get_sync_round() > old_round), 8.0)
	_check("variant_enters_battle_with_both_stable_slots", ready)
	if not ready:
		return false
	_trial = get_tree().current_scene as Trial
	_pilot = _trial._player
	_entry_wire = NetworkManager.recovery.guest_wire
	_cuts.clear()
	_volleys.clear()
	_trial.child_entered_tree.connect(_watch_bullet)
	_trial.volley_interrupted.connect(func(side: String, at: Vector2, _deadline: int):
		_cuts.append(side)
		_trace("cut", {"side": side, "tick": _trial.trial_tick, "at": str(at)}))
	_controls = _trial.get_node_or_null("MobileControls")
	if not is_instance_valid(_controls):
		_controls = Mobile.instantiate()
		_trial.add_child(_controls)
		_pilot._motion.mobile_mode = true
		_controls.move_input.connect(_pilot._motion.handle_mobile_move)
	_touch(true)
	return true

func _fly_trial(mode: String) -> void:
	var left := mode in ["left", "both"]
	var right := mode in ["right", "both"]
	var starting_health := GameState.get_current_health(NetworkManager.local_player_id())
	var center := P1_MIDDLE if _host else P2_MIDDLE
	var lane := center
	if (_host and left) or (not _host and right):
		lane.x = 320.0 if _host else 960.0
	if mode == "late" and _host:
		lane = Vector2(376, 412)
	_drive_to(lane)
	var warned := await _wait_until(func():
		return _trial._fighters.values().filter(_trial._is_charging).size() == 2, 3.6)
	_check("telegraphs_before_release", warned and _trial.leg == Trial.Leg.INTERCEPT)
	if not _evidence.is_empty() and mode in ["center", "both"]:
		_capture_opening(mode)
	var fired := await _wait_until(func(): return _trial.trial_tick >= Trial.DUAL_EMITTER_TICK + Trial.CHARGE_TICKS + 12, 5.0)
	_check("actual_host_or_ghost_volley_counts", fired and _side_bullets(true) == (0 if left else 3)
		and _side_bullets(false) == (0 if right else 3))
	_trace("volleys", {"left": _side_bullets(true), "right": _side_bullets(false), "cuts": _cuts})
	if mode in ["center", "retry-center"]:
		_check("center_route_keeps_both_volleys_clear", _pilot.global_position.distance_to(center) < 16.0
			and GameState.get_current_health(NetworkManager.local_player_id()) == starting_health)
	if mode == "center":
		_capture("center-volley")
	if _host and (left or right):
		var cuts := _trial.interruptions
		for side: String in _cuts.duplicate():
			_trial._on_emitter_died(side)
		_check("duplicate_death_cannot_count_again", _trial.interruptions == cuts and _cuts.size() == cuts)
	if mode == "late":
		await _test_late_cut()
	_drive_to(center, false)
	if mode == "both":
		await _test_rewire()
	if mode == "downed" and _host:
		_trial._players[NetworkManager.recovery.guest_slot].force_kill()
	if mode == "downed":
		_check("downed_state_reaches_both_peers", await _wait_until(func():
			return GameState.is_player_downed(NetworkManager.recovery.guest_slot), 1.5))
	else:
		await _test_pulse(mode, 1, left and right)
		_drive_to(center, false)
		await _test_pulse(mode, 2, false)
	var completed := await _wait_until(func(): return _trial.finished, 28.0)
	var expected := int(left) + int(right)
	if completed and not _host:
		_trial._rpc_route_result(GameState.get_sync_round(), "被击落", expected + 1, Trial.Leg.BOSS, {})
	_check("ordinary_rank_and_growth_stay_out", GameState.level == 1 and GameState.get_bullet_damage(NetworkManager.local_player_id()) == 4
		and _trial._route_review.is_empty() and not _trial._draft_wait and Leaderboard.get_entries() == _leaderboard)
	_check("both_peers_reach_matching_summary", completed and _trial.leg == Trial.Leg.BOSS
		and _trial._route_outcome == "完成" and _trial.interruptions == expected and _trial._result.text == "完成 · 截断 %d 次" % expected
		and (not _host or _trial.trial_tick == Trial.DUAL_END_TICK))
	_trace("result", {"mode": mode, "tick": _trial.trial_tick, "cuts": _trial.interruptions, "text": _trial._result.text})
	_capture(mode + "-result")

func _test_late_cut() -> void:
	if _host:
		_drive_to(Vector2(320, 391))
	_check("late_ship_is_really_destroyed", await _wait_until(func():
		return _side_bullets(true) == 3 and not _live_emitter(true), 2.0))
	if _host:
		_check("late_death_keeps_released_rounds", _trial.interruptions == 0 and _volleys.any(func(row: Dictionary):
			var shot := instance_from_id(row.id) as Bullet
			return is_instance_valid(shot) and shot.is_in_group("enemy_bullets") and row.left and shot._direction == row.direction))

func _live_emitter(left: bool) -> bool:
	return _trial._entities.values().any(func(entity: Node):
		return entity is Ship and not entity.is_queued_for_deletion() and (entity.global_position.x < 640.0) == left)

func _test_rewire() -> void:
	var guest_slot: int = NetworkManager.recovery.guest_slot
	if not _host:
		NetworkManager.recovery.set_background(true)
		await get_tree().create_timer(.12).timeout
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var resumed := await _wait_until(func():
		var wire: int = NetworkManager.recovery.guest_wire
		return wire > 1 and wire != _entry_wire and NetworkManager.recovery.deadline == 0 and not get_tree().paused, 10.0)
	_check("rewire_restores_same_trial_and_two_cuts", resumed and get_tree().current_scene == _trial
		and NetworkManager.recovery.guest_slot == guest_slot and _trial.interruptions == 2)
	_touch(true)

func _test_pulse(mode: String, index: int, wide_gap: bool) -> void:
	var boss: Mothership = null
	var locked := await _wait_until(func():
		return is_instance_valid(_trial._boss) and _trial._boss.coop_pulse_snapshot().phase == Mothership.PulsePhase.LOCK, 21.0)
	_check("pulse_%d_locks" % index, locked)
	if not locked:
		return
	boss = _trial._boss
	var lock := boss.coop_pulse_snapshot()
	var axis := Vector2(lock.from).direction_to(lock.to)
	var distance := float(Vector2(lock.from).distance_to(boss.global_position))
	var sample := Vector2(lock.from) - axis * (distance - 105.0)
	var outer := Vector2(lock.from) + axis * 45.0
	var expected := Mothership.INTERCEPT_PULSE_ORIGIN_DISTANCE if wide_gap else Mothership.COOP_PULSE_ORIGIN_DISTANCE
	var valid := absf(distance - expected) < 6.0 and boss.coop_pulse_contains(outer) and boss.coop_pulse_contains(sample) != wide_gap
	_check("pulse_%d_warning_matches_damage_gap" % index, valid)
	var gauges: Array[PulseSample] = []
	if _host:
		for point: Vector2 in [sample, outer]:
			var gauge := PulseSample.new()
			gauge.peer_id = -10 - gauges.size()
			gauge.position = point
			_trial.add_child(gauge)
			gauge.add_to_group("player")
			gauges.append(gauge)
	var hud: Rect2 = _trial._hud._boss_status_root.get_global_rect()
	_check("pulse_%d_touch_and_hud_clear" % index, Trial.SafeArea.for_viewport(get_viewport()).encloses(hud)
		and not hud.intersects(_trial._hud._score_label.get_global_rect()) and _controls._ui_root.visible
		and not hud.intersects(_controls._base_node.get_global_rect())
		and _trial._hud._skill_slots.all(func(slot: Dictionary): return not hud.intersects(slot.button.get_global_rect())))
	_capture("%s-pulse-%d-lock" % [mode, index])
	var me := NetworkManager.local_player_id()
	var health := GameState.get_current_health(me)
	if me == lock.slot:
		_drag(Vector2.LEFT if _host else Vector2.RIGHT)
	var fired := await _wait_until(func(): return boss.coop_pulse_snapshot().phase == Mothership.PulsePhase.FIRE, 1.0)
	var fire := boss.coop_pulse_snapshot()
	_check("pulse_%d_actual_fire_keeps_geometry" % index, fired and fire.from == lock.from and fire.to == lock.to
		and boss.coop_pulse_contains(sample) != wide_gap)
	_trace("pulse", {"index": index, "slot": lock.slot, "distance": distance, "from": str(fire.from), "to": str(fire.to), "wide": wide_gap})
	_capture("%s-pulse-%d-fire" % [mode, index])
	await _wait_until(func(): return boss.coop_pulse_snapshot().phase == Mothership.PulsePhase.OPEN, .5)
	_drag(Vector2.ZERO)
	_check("pulse_%d_steered_pilot_remains_safe" % index, GameState.get_current_health(me) == health)
	if _host:
		var cut_damage := Mothership.COOP_PULSE_DAMAGE
		_check("pulse_%d_authority_damages_only_the_live_gap_boundary" % index,
			is_equal_approx(gauges[0].damage_taken, 0.0 if wide_gap else cut_damage)
			and is_equal_approx(gauges[1].damage_taken, cut_damage))
		_trace("pulse_damage", {"index": index, "near": gauges[0].damage_taken, "outer": gauges[1].damage_taken})
		for gauge in gauges:
			gauge.queue_free()

func _drive_to(at: Vector2, aim_up := true) -> void:
	var pilot := _pilot
	if not is_instance_valid(pilot) or pilot.is_downed:
		return
	var until := Time.get_ticks_msec() + 3300
	while Time.get_ticks_msec() < until and is_instance_valid(pilot) and not pilot.is_downed:
		var offset := at - pilot.global_position
		if offset.length() < 7.0:
			break
		_drag((offset / 48.0).limit_length())
		await get_tree().physics_frame
	_drag(Vector2.ZERO)
	for _frame in 10:
		await get_tree().physics_frame
	# Stage facing after joystick movement. During pulse measurements, shots face away from the shield.
	if is_instance_valid(pilot):
		pilot.rotation = 0.0 if aim_up else PI

func _touch(pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = TOUCH_AT
	touch.pressed = pressed
	get_viewport().push_input(touch, true)

func _drag(direction: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.position = TOUCH_AT + direction * _controls.joystick_radius
	get_viewport().push_input(drag, true)

func _watch_bullet(node: Node) -> void:
	if node is Bullet and _trial.leg == Trial.Leg.INTERCEPT:
		_read_bullet.call_deferred(node.get_instance_id())

func _read_bullet(id: int) -> void:
	var bullet := instance_from_id(id) as Bullet
	if is_instance_valid(bullet) and not bullet._is_player_bullet and bullet._is_network_ghost == (not _host):
		_volleys.append({"id": id, "left": bullet.global_position.x < 640.0, "direction": bullet._direction})

func _side_bullets(left: bool) -> int:
	return _volleys.filter(func(row: Dictionary): return row.left == left).size()

func _capture(label: String) -> void:
	if _evidence.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_frames[label] = get_viewport().get_texture().get_image()

func _capture_opening(mode: String) -> void:
	if mode == "center":
		# Wait for the incoming fighters and their arc tips to be inside both viewports.
		if await _wait_until(func(): return _trial.trial_tick >= Trial.DUAL_EMITTER_TICK + 70, 2.5):
			await _capture("center-telegraph")
	elif await _wait_until(func(): return not _trial._cut_cues.is_empty(), 2.5):
		await _capture("both-cut")

func _done() -> void:
	if not _evidence.is_empty():
		_check("viewport_produced_result_and_keyframes", _frames.has(_mode + "-result") and (_mode == "downed"
			or (_frames.has(_mode + "-pulse-1-lock") and _frames.has(_mode + "-pulse-2-fire"))))
		if _mode == "center":
			_check("viewport_captured_both_telegraphs_and_volley", _frames.has("center-telegraph") and _frames.has("center-volley"))
	for label: String in _frames:
		var path := _evidence.path_join("%s-%s.png" % [label, "host" if _host else "client"])
		_check("capture_" + label, _frames[label].save_png(path) == OK)
	print("[DUAL] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))
