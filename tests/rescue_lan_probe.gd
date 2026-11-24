extends "res://tests/lan_probe.gd"
## 双进程 ENet。固定起点和边界入圈时刻，救援、输入、快照和结算均走正式链路。

const P1_AT := Vector2(470, 400)
const OUTSIDE := Vector2(710, 400)
const ON_EDGE := Vector2(530, 400)
const STICK_AT := Vector2(150, 542)
const BULLET := preload("res://scenes/entities/bullet.tscn")
const Palette := preload("res://scripts/visuals/palette.gd")
var _guest := 0
var _local := 0
var _command := ""
var _reply := ""
var _command_position := Vector2.ZERO
var _shots := ""
var _stale_downed_snapshot: Dictionary
var _lethal_contact := false

func _process(_delta: float) -> void:
	pass

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() >= 4:
		_shots = args[3]
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1280 if _role == "host" else 1600, 720)
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var online := err == OK and await _wait_until(NetworkManager.is_online, 8.0)
	_check("online", online, error_string(err))
	if online:
		get_tree().node_added.connect(_prepare_fixture_node)
		_local = multiplayer.get_unique_id()
		_enter_main_scene()
		var ready := await _wait_until(_cond_both_players, 8.0)
		_check("both_pilots", ready, "")
		if ready:
			_guest = NetworkManager.connected_peers[0] if _role == "host" else _local
			_prepare_main()
			if _role == "host":
				await _host_rounds()
			else:
				await _client_rounds()
	get_tree().quit(_summarize())

func _prepare_fixture_node(node: Node) -> void:
	if node.scene_file_path == MAIN_SCENE:
		if not (OS.has_feature("android") or OS.has_feature("ios")):
			node._spawn_mobile_controls()
		# 等队友加入时主场景已在跑。首帧前固定环境，避免自然碰撞污染实弹复现。
		node.ready.connect(func():
			node._wave_director._cooldown = INF
			node._asteroid_timer = INF, CONNECT_ONE_SHOT)
	elif node.scene_file_path == "res://scenes/entities/player.tscn":
		node.ready.connect(func(): node._combat._shoot_timer = 120.0, CONNECT_ONE_SHOT)

func _prepare_main() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _host_rounds() -> void:
	if not await _first_rescue():
		return
	if not await _use_remaining_rescues():
		return
	if not await _restart_round("new_after_fourth"):
		return
	if not await _expiration_round():
		return
	if not await _restart_round("new_after_expiry"):
		return
	if not await _round_setup("separate_for_double"):
		return
	_main._players[1].force_kill()
	_main._players[_guest].force_kill()
	_check("two_unable_ends_round", not GameState.game_running and _main._players.is_empty()
		and GameState.rescues_left == 3 and GameState.rescue_peer_id == 0 and NetworkManager.is_online(), "")
	if not await _ask("double_result"):
		return
	if not await _restart_round("new_after_double"):
		return
	if not await _round_setup("separate_for_disconnect"):
		return
	_main._players[1].force_kill()
	_command_peer.rpc_id(_guest, "disconnect", Vector2.ZERO)
	var dropped := await _wait_until(func(): return not NetworkManager.is_online(), 5.0)
	_check("disconnect_discards_pending_rescue", dropped and GameState.rescue_peer_id == 0
		and GameState.rescues_left == 3 and _main._fallback_in_progress, "")
	var before := _main.get_instance_id()
	var solo := await _wait_until(func():
		var scene := get_tree().current_scene
		return is_instance_valid(scene) and scene.get_instance_id() != before, 8.0)
	_check("fallback_solo_clean", solo and GameState.rescue_peer_id == 0 and GameState.rescues_left == 3
		and GameState.is_player_alive(1) and not NetworkManager.is_online(), "")

func _first_rescue() -> bool:
	if not await _round_setup("outside"):
		return false
	GameState.apply_card(1, "vitality")
	GameState.apply_card(1, "pierce")
	var loadout := GameState._state(1)
	loadout.skill_cooldown = 8.0
	loadout.laser_cooldown = 7.0
	var victim: Node2D = _main._players[1]
	var bullet := Pool.acquire("bullet", BULLET)
	_main.add_child(bullet)
	bullet.setup(P1_AT - Vector2(0, 35), PI * 0.5, 100, false, 1, 660)
	bullet.body_entered.connect(func(body: Node2D):
		if body == victim:
			_lethal_contact = true)
	var knocked := await _wait_until(func(): return GameState.rescue_peer_id == 1, 1.0)
	_check("enemy_bullet_enters_downed", knocked and _lethal_contact, "contact=%s hp=%d" % [_lethal_contact, GameState.get_current_health(1)])
	if not knocked:
		return false
	var started: int = _main._rescue_expires_at - 15 * Engine.physics_ticks_per_second
	_check("p1_fixed_anchor_and_time", GameState.rescue_position == P1_AT and GameState.rescue_seconds == 15
		and victim.is_downed and not victim.is_queued_for_deletion() and GameState.get_current_health(1) == 0,
		"frame=%d deadline=%d pos=%s" % [started, _main._rescue_expires_at, GameState.rescue_position])
	var hostile: Node2D = _main._spawn_enemy_at(0, Vector2(900, 170))
	hostile.set_physics_process(false)
	_check("hostiles_target_active_pilot", hostile._target == _main._players[_guest] and not victim.is_in_group("player"), "")
	UpgradeDraft.offer_cards(_guest, ["pierce", "splash", "power"])
	GameState.force_sync_to_peer(_guest)
	if not await _ask("observe_p1"):
		return false
	_check("outside_circle_does_not_rescue", GameState.rescue_peer_id == 1 and GameState.rescues_left == 3
		and victim.global_position == P1_AT and victim.is_downed, "")
	_stale_downed_snapshot = GameState._to_dict()
	var skill_before := GameState.get_skill_cooldown(1)
	var laser_before := GameState.get_laser_cooldown(1)
	if not await _ask("fly_into_circle"):
		return false
	var protected_until: int = victim._rescue_protected_until
	_check("guest_input_rescues_host_once", GameState.rescues_left == 2 and not victim.is_downed
		and GameState.get_current_health(1) == 35 and GameState.get_shield_layers(1) == 0
		and protected_until > Engine.get_physics_frames(), "hp=%s rescue=%d" % [GameState.get_current_health(1), GameState.rescues_left])
	_check("cards_and_running_cooldowns_survive", GameState.get_card_stacks(1) == {"vitality": 1, "pierce": 1}
		and GameState.get_skill_cooldown(1) > 0 and GameState.get_skill_cooldown(1) < skill_before
		and GameState.get_laser_cooldown(1) > 0 and GameState.get_laser_cooldown(1) < laser_before, "")
	victim.take_damage(4)
	victim.force_kill()
	var helper: Node2D = _main._players[_guest]
	var helper_before := GameState.get_current_health(_guest) + GameState.get_shield_layers(_guest)
	helper.take_damage(1)
	var helper_after := GameState.get_current_health(_guest) + GameState.get_shield_layers(_guest)
	_check("only_revived_pilot_protected", GameState.get_current_health(1) == 35
		and helper._rescue_protected_until == 0 and helper_after == helper_before - 1,
		"helper %d→%d inv=%.3f protected_until=%d" % [helper_before, helper_after, helper._invincible_timer, helper._rescue_protected_until])
	GameState._rpc_sync_game_state.rpc_id(_guest, _stale_downed_snapshot)
	GameState._rpc_sync_game_state.rpc_id(_guest, _stale_downed_snapshot)
	if not await _ask("resnapshot_live"):
		return false
	await _at_frame(protected_until)
	victim.take_damage(1)
	_check("protection_ends_at_one_second", GameState.get_current_health(1) == 34,
		"frame=%d end=%d" % [Engine.get_physics_frames(), protected_until])
	return true

func _use_remaining_rescues() -> bool:
	_place_local(P1_AT)
	if not await _ask("exact_edge", ON_EDGE) or not await _wait_guest_position(ON_EDGE):
		return false
	# 奇数和极低最大生命通过相同结算路径向下取整，最少恢复 1 点。
	var guest_state := GameState._state(_guest)
	guest_state.max_health = 1
	guest_state.current_health = 1
	var before := Engine.get_physics_frames()
	_main._players[_guest].force_kill()
	var rescued := await _wait_until(func(): return GameState.rescues_left == 1, 0.55)
	_check("host_already_on_boundary_rescues_guest", rescued and GameState.get_current_health(_guest) == 1
		and GameState.get_shield_layers(_guest) == 0
		and _main._players[_guest]._rescue_protected_until <= before + Engine.physics_ticks_per_second + 1, "")
	_main._players[1].force_kill()
	var last := await _wait_until(func(): return GameState.rescues_left == 0, 0.55)
	_check("third_revive_consumes_last_use", last and GameState.is_player_alive(1), "")
	await _at_frame(_main._players[_guest]._rescue_protected_until)
	_main._players[_guest].force_kill()
	_check("fourth_knockout_spectates_even_inside", not _main._players.has(_guest) and GameState.rescue_peer_id == 0
		and GameState.rescues_left == 0 and GameState.game_running and _main._players.has(1), "")
	return await _ask("fourth_result")

func _expiration_round() -> bool:
	# 模拟重开前仍在发送的旧局，序号较新也不能越过局号。
	var stale_round := _stale_downed_snapshot.duplicate(true)
	stale_round.sequence = GameState._to_dict().sequence
	GameState._rpc_sync_game_state.rpc_id(_guest, stale_round)
	if not await _round_setup("separate_for_expiry"):
		return false
	_main._players[_guest].force_kill()
	var expiry: int = _main._rescue_expires_at
	var born := Engine.get_physics_frames()
	_place_local(OUTSIDE - Vector2(0, GameState.RESCUE_RADIUS + 1))
	_command_peer.rpc_id(_guest, "observe_timeout", Vector2.ZERO)
	await _at_frame(expiry - GameState.RESCUE_WARNING_SECONDS * Engine.physics_ticks_per_second)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("host_warning_starts_at_five_seconds", GameState.rescue_seconds == 5
		and _main._hud._downed_label.get_theme_color("font_color") == Palette.DOWNED_CRITICAL, _main._hud._downed_label.text)
	await _capture_warning()
	await _at_frame(expiry)
	# physics_frame 在主场景本帧裁决之前发出。同一帧把救援者放到圈边。
	var entry_frame := Engine.get_physics_frames()
	var was_pending := GameState.rescue_peer_id == _guest
	_place_local(OUTSIDE - Vector2(0, GameState.RESCUE_RADIUS))
	await get_tree().process_frame
	_check("expires_before_same_frame_entry", was_pending and expiry == entry_frame
		and expiry - born == 15 * Engine.physics_ticks_per_second
		and GameState.rescues_left == 3 and GameState.rescue_peer_id == 0 and not _main._players.has(_guest)
		and GameState.game_running, "born=%d entry=%d expiry=%d" % [born, entry_frame, expiry])
	return _require("guest_observed_full_timeout", await _wait_until(func(): return _reply == "observe_timeout", 4.0))

func _client_rounds() -> void:
	for label in ["outside", "observe_p1", "fly_into_circle", "resnapshot_live", "exact_edge", "fourth_result",
			"new_after_fourth", "separate_for_expiry", "observe_timeout", "new_after_expiry",
			"separate_for_double", "double_result", "new_after_double", "separate_for_disconnect", "disconnect"]:
		if not _require("command_" + label, await _wait_until(func(): return _command == label, 27.0)):
			return
		match label:
			"outside", "exact_edge", "separate_for_expiry", "separate_for_double", "separate_for_disconnect":
				_place_local(_command_position)
				if label == "separate_for_expiry":
					_check("old_round_snapshot_cannot_restore_downed", GameState.rescue_peer_id == 0
						and GameState.rescues_left == 3 and GameState.get_current_health(1) == 50 and GameState.game_running, "")
			"observe_p1":
				await _observe_p1()
			"fly_into_circle":
				await _fly_into_circle()
			"resnapshot_live":
				await _check_resnapshot()
			"fourth_result":
				_check("guest_spectates_after_fourth", not _main._players.has(_local) and GameState.rescues_left == 0
					and GameState.rescue_peer_id == 0 and GameState.game_running, "")
			"observe_timeout":
				await _observe_timeout()
			"double_result":
				_check("guest_sees_normal_game_over", not GameState.game_running and _main._hud._game_over_panel.visible
					and _main._players.is_empty() and GameState.rescues_left == 3, "")
			"disconnect":
				_check("disconnect_has_pending_downed", GameState.rescue_peer_id == 1 and GameState.rescues_left == 3, "")
				NetworkManager.disconnect_network()
				return
			_:
				await _adopt_new_round()
		_reply_to_host.rpc_id(1, label)

func _observe_p1() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Node = _main._hud
	var safe := get_viewport().get_visible_rect().grow_individual(-102, -27, -52, -36)
	hud._layout_in_safe_area(safe)
	var label: Label = hud._downed_label
	_check("guest_same_anchor_rings_and_label", GameState.rescue_peer_id == 1 and GameState.rescue_position == P1_AT
		and _main._players[1].is_downed and _main._players[1].global_position == P1_AT
		and label.visible and label.text.begins_with("P1 倒地") and label.text.ends_with("救援 3/3"), label.text)
	_check("rescue_label_ignores_touch_and_spares_cards", safe.encloses(label.get_global_rect())
		and label.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud._draft_panel.visible
		and not label.get_global_rect().intersects(hud._draft_panel.get_global_rect()), "")
	var downed: Node2D = _main._players[1]
	var hull: Sprite2D = downed.get_node("Sprite2D")
	var before := hull.self_modulate.a
	await _wait_seconds(0.28)
	_check("remote_downed_hull_fades_with_engine_off", hull.material is ShaderMaterial
		and absf(hull.self_modulate.a - before) > 0.02 and hull.self_modulate.a >= 0.52
		and not downed.get_node("EngineGlow").visible, "%.2f → %.2f" % [before, hull.self_modulate.a])

func _fly_into_circle() -> void:
	var start: Vector2 = _main._players[_local].global_position
	_touch(true)
	var drag := InputEventScreenDrag.new()
	drag.position = get_viewport().get_final_transform() * (STICK_AT - Vector2(85, 0))
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	var arrived := await _wait_until(func(): return GameState.rescues_left == 2, 4.0)
	_touch(false)
	var pilot: Node2D = _main._players[_local]
	_check("joystick_enters_circle_while_cards_visible", arrived and pilot.global_position.x < start.x - 140.0
		and _main._hud._draft_panel.visible and not _main._players[1].is_downed, str(pilot.global_position))
	var revived: Node2D = _main._players[1]
	var hull: Sprite2D = revived.get_node("Sprite2D")
	_check("revive_restores_hull_and_engine", hull.material == null and hull.self_modulate.a == 1.0
		and revived.get_node("EngineGlow").visible, "")

func _check_resnapshot() -> void:
	var sequence := GameState._received_sync_sequence
	var remained: bool = GameState.rescue_peer_id == 0 and GameState.rescues_left == 2 and not _main._players[1].is_downed
	_main._request_player_sync.rpc_id(1)
	var synced := await _wait_until(func(): return GameState._received_sync_sequence > sequence, 2.0)
	_check("duplicate_old_snapshot_and_resync_keep_revived_state", remained and synced
		and GameState.rescue_peer_id == 0 and GameState.rescues_left == 2 and GameState.get_current_health(1) == 35
		and GameState.get_card_stacks(1) == {"vitality": 1, "pierce": 1}, "")

func _observe_timeout() -> void:
	var pilot: Node2D = _main._players[_local]
	var at := GameState.rescue_position
	pilot._combat._shoot_timer = 0.0
	pilot.request_action("skill")
	pilot.request_action("laser")
	pilot.request_action("dash")
	_touch(true)
	var drag := InputEventScreenDrag.new()
	drag.position = get_viewport().get_final_transform() * (STICK_AT + Vector2(85, 0))
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	await _wait_seconds(0.22)
	_touch(false)
	_check("downed_ignores_actions_movement_and_autofire", GameState.rescue_peer_id == _local and pilot.is_downed
		and pilot.global_position == at and pilot._combat._shoot_timer == 0.0
		and pilot._action_router._queued_actions.is_empty() and GameState.get_laser_cooldown(_local) == 0.0
		and GameState.get_skill_cooldown(_local) == 0.0 and GameState.get_shield_layers(_local) == 0, "")
	var warned := await _wait_until(func(): return GameState.rescue_peer_id == _local and GameState.rescue_seconds == 5, 12.0)
	await get_tree().process_frame
	var label: Label = _main._hud._downed_label
	_check("last_five_seconds_orange", warned and label.text.begins_with("P2 倒地 · 5 秒")
		and label.get_theme_color("font_color") == Palette.DOWNED_CRITICAL, label.text)
	await _capture_warning()
	var expired := await _wait_until(func(): return not _main._players.has(_local), 7.0)
	_check("guest_expiry_removes_ring_and_keeps_session", expired and GameState.rescue_peer_id == 0
		and GameState.rescues_left == 3 and GameState.game_running and NetworkManager.is_online(), "")

func _capture_warning() -> void:
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_check("warning_screenshot", img.save_png(_shots.path_join(_role + "-rescue-warning.png")) == OK, "")

func _restart_round(label: String) -> bool:
	_command_peer.rpc_id(_guest, label, Vector2.ZERO)
	_main._restart()
	await _adopt_new_round()
	return _require("guest_restarted_" + label, await _wait_until(func(): return _reply == label, 5.0))

func _adopt_new_round() -> void:
	var before := _main.get_instance_id()
	var arrived := await _wait_until(func():
		var scene := get_tree().current_scene
		return is_instance_valid(scene) and scene.get_instance_id() != before, 5.0)
	if not _require("reloaded_main", arrived):
		return
	_main = get_tree().current_scene
	var ready := await _wait_until(_cond_both_players, 5.0)
	_check("new_round_resets_pool", ready and GameState.rescues_left == 3 and GameState.rescue_peer_id == 0
		and GameState.game_running and GameState.get_card_stacks(_local).is_empty(),
		"ready=%s running=%s uses=%d downed=%d" % [ready, GameState.game_running, GameState.rescues_left, GameState.rescue_peer_id])
	if ready:
		_prepare_main()

func _round_setup(label: String) -> bool:
	_place_local(P1_AT)
	return await _ask(label, OUTSIDE) and await _wait_guest_position(OUTSIDE)

func _place_local(at: Vector2) -> void:
	var pilot: Node2D = _main._players[_local]
	pilot._motion.stop_for_downed()
	pilot.global_position = at
	pilot.reset_physics_interpolation()

func _wait_guest_position(at: Vector2) -> bool:
	var synced := await _wait_until(func(): return _main._player_target_positions.get(_guest, Vector2.ZERO) == at, 2.5)
	return _require("guest_position_synced", synced)

func _at_frame(frame: int) -> void:
	while Engine.get_physics_frames() < frame:
		await get_tree().physics_frame

func _touch(down: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = down
	touch.position = get_viewport().get_final_transform() * STICK_AT
	Input.parse_input_event(touch)
	Input.flush_buffered_events()

func _ask(label: String, at := Vector2.ZERO) -> bool:
	_command_peer.rpc_id(_guest, label, at)
	return _require("guest_ack_" + label, await _wait_until(func(): return _reply == label, 6.0))

func _require(label: String, passed: bool) -> bool:
	_check(label, passed, "")
	return passed

@rpc("authority", "reliable", "call_remote")
func _command_peer(label: String, at: Vector2) -> void:
	_command = label
	_command_position = at

@rpc("any_peer", "reliable", "call_remote")
func _reply_to_host(label: String) -> void:
	if not multiplayer.is_server():
		return
	_reply = label
