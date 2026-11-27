extends Node

const TITLE := "res://scenes/ui/title_screen.tscn"
const LOBBY := "res://scenes/ui/lobby.tscn"
const LEGACY_PORT := 22212
const UNREACHABLE_PORT := 22213
const SafeArea := preload("res://scripts/ui/battle_safe_area.gd")
const Rules := preload("res://scripts/battle/trials/rift_route_rules.gd")

class DiscoveryFixture extends RefCounted:
	signal status(message: String, generation: int)
	signal host_discovered(room_name: String, ip: String, port: int, generation: int)

	func getDiscoveryGeneration() -> int:
		return 2

var _passed := 0
var _failed := 0
var _format := "wide"
var _output := ""
var _use_system_back := false

func _ready() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var role := args[0] if not args.is_empty() else "walk"
	_format = args[1] if args.size() > 1 else "wide"
	_output = args[2] if args.size() > 2 else ""
	_use_system_back = args.has("system-back")
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = Vector2i(1600 if _format == "wide" else (540 if _format == "stacked" else 960), 720)
	match role:
		"old":
			await _legacy_fixture()
		"host":
			await _live_host()
		"join":
			await _live_join()
		"back":
			await _back_walkthrough()
		"title-back":
			await _title_back()
		"battle-host", "battle-join":
			await _battle_back(role == "battle-host")
		_:
			await _walkthrough()
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	print("[ENTRY_UI] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _open_title() -> Node:
	get_tree().current_scene = null
	get_tree().change_scene_to_file(TITLE)
	await get_tree().scene_changed
	return get_tree().current_scene

func _open_lobby() -> Node:
	var title := await _open_title()
	await _tap(title.get_node("Menu/BtnMultiplayer"))
	var ready := await _wait_for(func(): return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == LOBBY, 2.0)
	_check("title_opens_real_lobby", ready)
	return get_tree().current_scene if ready else null

func _walkthrough() -> void:
	var title := await _open_title()
	var safe := _simulate_insets(title)
	var menu: Control = title.get_node("Menu")
	await _frames()
	_check("title_three_touch_controls", menu.get_child_count() == 3 and _fits(safe, menu.get_children()))
	_check("title_stacks_when_narrow", _format != "stacked" or title.get_node("Hero").get_global_rect().end.y < menu.position.y)
	await _capture("title")
	await _touch_at(Vector2(5, 5))
	_check("blank_touch_does_not_start", get_tree().current_scene == title and menu.visible)
	await _tap(title.get_node("Menu/BtnTrials"))
	await _tap(title.get_node("TrialHub/BtnRiftRoute"))
	_check("dual_intercept_explains_both_use_same_entry", title.get_node("RiftChoices/DualIntercept").text.ends_with("仅双人"))
	await _tap(title.get_node("RiftChoices/Back"))
	_check("back_returns_to_parent_with_focus", title.get_node("TrialHub").visible and title.get_node("TrialHub/BtnRiftRoute").has_focus())
	await _tap(title.get_node("TrialHub/Back"))
	await _tap(title.get_node("Menu/BtnMultiplayer"))
	if not await _wait_for(func(): return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == LOBBY, 2.0):
		_check("enter_lobby", false)
		return
	var lobby := get_tree().current_scene
	safe = _simulate_insets(lobby)
	await _frames()
	_check("role_cards_and_back_in_safe_area", _fits(safe, [lobby._btn_be_host, lobby._btn_be_client, lobby._btn_back]))
	_check("role_cards_stack_when_narrow", _format != "stacked" or lobby._panel_mode_select.columns == 1)
	await _capture("roles")
	await _tap(lobby._btn_be_host)
	_check("host_waits_one_of_two_without_start", lobby._occupancy.text == "1 / 2" and NetworkManager.is_host
		and not lobby._btn_start.is_visible_in_tree() and not lobby._btn_rift.is_visible_in_tree())
	await _capture("waiting")
	HarmonyBridge.report_status("发布房间异常：SecurityException")
	_check("host_permission_failure_closes_room_and_offers_retry", lobby._retry_host.visible and not NetworkManager.is_online())
	await _tap(lobby._retry_host)
	_check("host_retries_in_place", lobby._occupancy.text == "1 / 2" and NetworkManager.is_host and not lobby._retry_host.visible)
	await _tap(lobby._btn_back)
	_check("back_releases_created_room", lobby._panel_mode_select.visible and not NetworkManager.is_online()
		and not HarmonyBridge.get_debug_snapshot().is_hosting)
	await _tap(lobby._btn_be_client)
	await _capture("searching")
	_check("empty_search_offers_retry", await _wait_for(func(): return lobby._lbl_scan_hint.text == "暂无可用房间", 2.5)
		and lobby._retry_search.visible and not lobby._room_scroll.visible)
	await _capture("empty")
	await _tap(lobby._retry_search)
	_check("retry_restarts_search_in_place", lobby._lbl_scan_hint.text == "正在搜索附近房间" and get_tree().current_scene == lobby)
	HarmonyBridge.report_status("扫描房间异常：SecurityException")
	_check("permission_failure_has_next_step", lobby._lbl_join_status.text.contains("权限") or lobby._lbl_join_status.text.contains("允许"))
	await _capture("permission")
	await _tap(lobby._retry_search)
	var long_name := "巡航小队 · ".repeat(16) + "结束"
	HarmonyBridge.report_discovered_host(long_name, "127.0.0.1", UNREACHABLE_PORT)
	HarmonyBridge.report_discovered_host(Rules.DUAL_INTERCEPT, "127.0.0.1", 22214)
	for index in range(12):
		HarmonyBridge.report_discovered_host("演示房间 %02d" % (index + 1), "127.0.0.1", 22300 + index)
	await _frames()
	var room: Button = lobby._host_buttons.get("127.0.0.1:%d" % UNREACHABLE_PORT)
	_check("room_name_clips_and_endpoint_stays_in_diagnostics", is_instance_valid(room) and room.text == long_name
		and room.clip_text and room.focus_mode == Control.FOCUS_ALL and "127.0.0.1" in room.tooltip_text)
	_check("filter_and_many_rooms_scroll", lobby._host_buttons.size() == 13 and lobby._room_scroll.get_v_scroll_bar().visible
		and lobby._room_scroll.get_global_rect().end.y <= lobby._retry_search.get_global_rect().position.y)
	var controls := [lobby._retry_search, lobby._btn_back]
	var before: Rect2 = lobby._btn_back.get_global_rect()
	await _capture("rooms")
	lobby._room_scroll.scroll_vertical = 700
	await _frames()
	_check("scroll_does_not_move_actions", lobby._btn_back.get_global_rect() == before and _fits(safe, controls))
	HarmonyBridge.report_status("房间离线：演示房间 12")
	_check("lost_rooms_are_removed", lobby._host_buttons.size() == 12)
	lobby._room_scroll.scroll_vertical = 0
	await _frames()
	await _tap(room)
	await _frames()
	var peer := multiplayer.multiplayer_peer
	room.pressed.emit()
	await _frames()
	_check("double_click_keeps_one_connect_attempt", peer is ENetMultiplayerPeer
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING
		and peer == multiplayer.multiplayer_peer and lobby._lbl_scan_hint.text == "正在连接房间" and not lobby._retry_search.visible)
	await _capture("connecting")
	await _tap(lobby._btn_back)
	_check("cancel_releases_connect_and_scan", lobby._panel_mode_select.visible and not multiplayer.multiplayer_peer is ENetMultiplayerPeer
		and not HarmonyBridge.get_debug_snapshot().is_scanning)
	await _tap(lobby._btn_be_client)
	HarmonyBridge.report_discovered_host("暂时无法连接的房间", "127.0.0.1", UNREACHABLE_PORT)
	await _frames()
	await _tap(lobby._host_buttons["127.0.0.1:%d" % UNREACHABLE_PORT])
	_check("real_enet_failure_can_retry_without_leaving", await _wait_for(func(): return lobby._lbl_scan_hint.text == "未能连接房间", 42.0)
		and lobby._retry_search.visible and get_tree().current_scene == lobby)
	await _capture("failed")
	await _tap(lobby._retry_search)
	_check("connect_failure_retry_restarts_same_panel", lobby._scan_active and lobby._lbl_scan_hint.text == "正在搜索附近房间")
	await _tap(lobby._btn_back)
	await _tap(lobby._btn_back)
	_check("roles_back_returns_title", await _wait_for(func(): return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE, 2.0))

func _system_back() -> void:
	# Window::_event_callback emits the notification before the SceneTree signal.
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	get_tree().root.go_back_requested.emit()

func _keyboard_back() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event)

func _return_from_panel(lobby: Node) -> void:
	if _use_system_back:
		_system_back()
		await _frames()
	else:
		await _tap(lobby._btn_back)

func _back_walkthrough() -> void:
	var lobby := await _open_lobby()
	if not is_instance_valid(lobby):
		return
	_check("lobby_owns_system_back", not get_tree().quit_on_go_back and get_tree().auto_accept_quit)
	await _tap(lobby._btn_be_client)
	_check("search_reaches_empty", await _wait_for(func(): return lobby._lbl_scan_hint.text == "暂无可用房间", 2.5))
	_system_back()
	await _frames()
	_check("system_back_cancels_empty_search", lobby._panel_mode_select.visible and not HarmonyBridge.get_debug_snapshot().is_scanning)
	await _tap(lobby._btn_be_client)
	NetworkManager.connection_failed.emit()
	NetworkManager.server_disconnected.emit()
	_check("retired_enet_outcomes_do_not_end_new_search", lobby._scan_active and lobby._lbl_scan_hint.text == "正在搜索附近房间")
	var discovery := DiscoveryFixture.new()
	var previous_plugin := HarmonyBridge._plugin
	HarmonyBridge._plugin = discovery
	HarmonyBridge._attach_plugin_signals()
	discovery.status.emit("扫描启动失败，错误码=1", 1)
	discovery.host_discovered.emit("旧房间", "127.0.0.1", UNREACHABLE_PORT, 1)
	_check("old_plugin_callbacks_do_not_pollute_rescan", lobby._scan_active and lobby._host_buttons.is_empty())
	discovery.host_discovered.emit("当前房间", "127.0.0.1", UNREACHABLE_PORT, 2)
	_check("current_plugin_callback_lists_room", lobby._host_buttons.size() == 1)
	HarmonyBridge._detach_plugin_signals()
	HarmonyBridge._plugin = previous_plugin
	var room: Button = lobby._host_buttons.get("127.0.0.1:%d" % UNREACHABLE_PORT)
	if not is_instance_valid(room):
		return
	await _tap(room)
	var peer := multiplayer.multiplayer_peer
	_check("connection_in_progress_is_real", peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING)
	_system_back()
	await _frames()
	_check("system_back_disposes_connecting_enet_peer", lobby._panel_mode_select.visible and not multiplayer.multiplayer_peer is ENetMultiplayerPeer)
	await _tap(lobby._btn_be_client)
	_keyboard_back()
	await _frames()
	_check("keyboard_cancel_stops_rescan", lobby._panel_mode_select.visible and not lobby._scan_active)
	await _tap(lobby._btn_be_host)
	_check("host_opens_at_one_of_two", lobby._occupancy.text == "1 / 2" and NetworkManager.is_host)
	_system_back()
	await _frames()
	_check("system_back_frees_waiting_room", lobby._panel_mode_select.visible and not NetworkManager.is_online()
		and not HarmonyBridge.get_debug_snapshot().is_hosting)
	await _tap(lobby._btn_be_host)
	_check("room_can_be_recreated", lobby._occupancy.text == "1 / 2" and NetworkManager.is_host)
	lobby._btn_back.pressed.emit()
	_keyboard_back()
	_system_back()
	# Also enqueue a duplicate after the deferred cleanup, in the same frame.
	_system_back.call_deferred()
	await _frames()
	_check("same_frame_routes_consume_once", get_tree().current_scene == lobby and lobby._panel_mode_select.visible
		and not NetworkManager.is_online())
	lobby._btn_back.pressed.emit()
	_system_back.call_deferred()
	_check("role_back_and_same_frame_system_back_restore_title", await _wait_for(func():
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE, 2.0)
		and get_tree().quit_on_go_back)

func _title_back() -> void:
	await _open_title()
	_check("title_retains_engine_exit", get_tree().quit_on_go_back)
	print("[ENTRY_UI] TITLE_BACK")
	_system_back()
	# A zero exit without this marker verifies the actual SceneTree quit path.
	await _frames()
	_check("title_exit_did_not_run", false)

func _battle_back(host: bool) -> void:
	var lobby := await _open_lobby()
	if not is_instance_valid(lobby):
		return
	if host:
		await _tap(lobby._btn_be_host)
		NetworkDiscovery.stop_all()
		print("[ENTRY_UI] BATTLE_HOST_READY")
		var ready := await _wait_for(func(): return lobby._btn_start.is_visible_in_tree() and not lobby._btn_start.disabled, 5.0)
		_check("normal_start_after_handshake", ready)
		if not ready:
			return
		lobby._btn_start.pressed.emit()
	else:
		await _tap(lobby._btn_be_client)
		HarmonyBridge.report_discovered_host("战斗返回探针", "127.0.0.1", NetworkManager.DEFAULT_PORT)
		await _frames()
		await _tap(lobby._host_buttons["127.0.0.1:%d" % NetworkManager.DEFAULT_PORT])
	var in_battle := await _wait_for(func():
		return (get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main.tscn"
			and NetworkManager.recovery.is_reserved()), 5.0)
	_check("battle_owns_system_back_after_lobby", in_battle and not get_tree().quit_on_go_back and NetworkManager._go_back_quits)
	if not in_battle:
		return
	if host:
		var synced := await _wait_for(func(): return get_tree().current_scene._player_entry_ready, 4.0)
		_check("battle_guest_acknowledges_both_pilots", synced)
		if not synced:
			return
		print("[ENTRY_UI] BATTLE_BACK")
		_system_back()
		await get_tree().create_timer(1.0).timeout
		_check("battle_exit_did_not_run", false)
	else:
		var battle := get_tree().current_scene
		_check("battle_departure_reaches_guest", await _wait_for(func():
			return is_instance_valid(battle) and battle._fallback_in_progress, 4.0)
			and not NetworkManager.is_online() and get_tree().quit_on_go_back)

func _live_host() -> void:
	var lobby := await _open_lobby()
	if not is_instance_valid(lobby):
		return
	_simulate_insets(lobby)
	await _tap(lobby._btn_be_host)
	# Loopback peers share a UDP discovery port. The joined session itself uses real ENet.
	NetworkDiscovery.stop_all()
	print("[ENTRY_UI] HOST_READY")
	if _use_system_back:
		var ready := await _wait_for(func(): return lobby._compatible_peer > 1, 10.0)
		_check("host_can_preview_rule_for_cancel", ready)
		if not ready:
			return
		lobby._rift_rule.select(1)
		lobby._rift_rule.item_selected.emit(1)
		_check("host_recovers_from_cancel_at_rule_preview", await _wait_for(func():
			return lobby._occupancy.text == "1 / 2" and lobby._lbl_host_status.text.begins_with("搭档已离开"), 5.0))
	for index in 2:
		var connected := await _wait_for(func(): return lobby._compatible_peer > 1 and lobby._btn_start.visible, 10.0)
		_check("host_two_of_two_round_%d" % index, connected and lobby._occupancy.text == "2 / 2" and not lobby._btn_start.disabled)
		if not connected:
			return
		lobby._rift_rule.select(1)
		lobby._rift_rule.item_selected.emit(1)
		_check("remix_waits_for_confirmation_%d" % index, lobby._btn_rift.disabled)
		var confirmed := await _wait_for(func(): return not lobby._btn_rift.disabled and lobby._occupancy.text == "2 / 2", 6.0)
		_check("confirmed_remix_can_start_%d" % index, confirmed)
		if not confirmed:
			return
		await _capture("host-ready-%d" % index)
		if index == 0:
			_check("host_returns_to_one_after_guest_cancels", await _wait_for(func(): return lobby._occupancy.text == "1 / 2", 6.0)
				and not lobby._btn_rift.visible)
		else:
			await get_tree().create_timer(1.0).timeout
			await _return_from_panel(lobby)
			_check("host_can_leave_before_start", lobby._panel_mode_select.visible and not NetworkManager.is_online())

func _live_join() -> void:
	var lobby := await _open_lobby()
	if not is_instance_valid(lobby):
		return
	_simulate_insets(lobby)
	if _use_system_back:
		await _tap(lobby._btn_be_client)
		HarmonyBridge.report_discovered_host("待确认的变奏房间", "127.0.0.1", LEGACY_PORT)
		await _frames()
		await _tap(lobby._host_buttons["127.0.0.1:%d" % LEGACY_PORT])
		_check("waiting_for_peer_version", await _wait_for(func(): return lobby._lbl_scan_hint.text == "正在检查联机版本", 3.0))
		await _return_from_panel(lobby)
		_check("system_back_cancels_version_check", lobby._panel_mode_select.visible and not NetworkManager.is_online()
			and lobby._version_deadline == 0)
		await _tap(lobby._btn_be_client)
		HarmonyBridge.report_discovered_host("搭档的飞行队", "127.0.0.1", NetworkManager.DEFAULT_PORT)
		await _frames()
		await _tap(lobby._host_buttons["127.0.0.1:%d" % NetworkManager.DEFAULT_PORT])
		_check("join_waits_at_rule_preview", await _wait_for(func(): return lobby._confirm_rift_rule.visible, 6.0))
		await _return_from_panel(lobby)
		_check("system_back_cancels_unconfirmed_rule", lobby._panel_mode_select.visible and not NetworkManager.is_online()
			and lobby._preview_revision == -1)
		await get_tree().create_timer(.25).timeout
	for index in 2:
		await _tap(lobby._btn_be_client)
		HarmonyBridge.report_discovered_host("搭档的飞行队", "127.0.0.1", NetworkManager.DEFAULT_PORT)
		await _frames()
		await _tap(lobby._host_buttons["127.0.0.1:%d" % NetworkManager.DEFAULT_PORT])
		var confirm := await _wait_for(func(): return lobby._confirm_rift_rule.visible and lobby._lbl_join_status.text == Rules.REMIX, 6.0)
		_check("join_requires_remix_confirmation_%d" % index, confirm)
		if not confirm:
			return
		await _capture("confirm-%d" % index)
		await _tap(lobby._confirm_rift_rule)
		_check("join_waits_for_host_after_confirm_%d" % index, lobby._lbl_scan_hint.text == "等待房主开始"
			and not lobby._confirm_rift_rule.visible)
		if index == 0:
			await get_tree().create_timer(.45).timeout
			await _return_from_panel(lobby)
			_check("guest_cancel_returns_roles", lobby._panel_mode_select.visible and not NetworkManager.is_online())
	_check("host_departure_has_retry", await _wait_for(func(): return lobby._lbl_scan_hint.text == "与房主的连接已断开", 7.0)
		and lobby._retry_search.visible and not NetworkManager.is_online())
	await _capture("host-left")
	await _tap(lobby._retry_search)
	if _use_system_back:
		_check("guest_rescans_after_connected_host_backs_out", lobby._scan_active and not NetworkManager.is_online())
	HarmonyBridge.report_discovered_host("旧版飞行队", "127.0.0.1", LEGACY_PORT)
	await _frames()
	await _tap(lobby._host_buttons["127.0.0.1:%d" % LEGACY_PORT])
	_check("real_connection_reaches_version_check", await _wait_for(func(): return lobby._lbl_scan_hint.text == "正在检查联机版本", 3.0))
	await _capture("checking")
	_check("wrong_version_has_retry_and_stays_in_lobby", await _wait_for(func():
		return lobby._lbl_join_status.text.contains("联机版本不兼容"), 4.0) and lobby._retry_search.visible and get_tree().current_scene == lobby)
	await _capture("version-failed")
	await _tap(lobby._retry_search)
	_check("version_retry_releases_previous_link", lobby._scan_active and not NetworkManager.is_online())

func _legacy_fixture() -> void:
	_check("legacy_peer_listens", NetworkManager.create_host(LEGACY_PORT) == OK)
	print("[ENTRY_UI] OLD_READY")
	if _use_system_back:
		_check("handshake_fixture_receives_first_connection", await _wait_for(func(): return not NetworkManager.connected_peers.is_empty(), 10.0))
		_check("handshake_fixture_observes_cancel", await _wait_for(func(): return NetworkManager.connected_peers.is_empty(), 5.0))
	if await _wait_for(func(): return not NetworkManager.connected_peers.is_empty(), 30.0):
		await get_tree().create_timer(.75).timeout
		var wire: int = NetworkManager.connected_peers[0]
		var result := (multiplayer as SceneMultiplayer).send_bytes("space-bullet-hell-lan:8".to_utf8_buffer(), wire)
		_check("legacy_peer_sends_old_version", result == OK)
		_check("legacy_peer_disconnected_on_retry", await _wait_for(func(): return NetworkManager.connected_peers.is_empty(), 7.0))
	else:
		_check("legacy_peer_received_join", false)

func _simulate_insets(scene: Node) -> Rect2:
	var view := get_viewport().get_visible_rect()
	var inset := view.grow_individual(-44, -22, -24, -34)
	var safe := SafeArea.from_display(get_viewport(), get_viewport().get_screen_transform() * inset)
	scene._layout_in_safe_area(safe)
	return safe.grow(-SafeArea.MENU_MARGIN)

func _fits(safe: Rect2, controls: Array) -> bool:
	return controls.all(func(item: Control):
		return item.is_visible_in_tree() and item.size.y >= 54.0 and safe.grow(1).encloses(item.get_global_rect()))

func _tap(button: Button) -> void:
	await _frames()
	await _touch_at(button.get_global_rect().get_center())
	await _frames()

func _touch_at(at: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = get_viewport().get_final_transform() * at
		touch.pressed = pressed
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		await get_tree().process_frame

func _capture(label: String) -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	var path := _output.path_join(_format + "-" + label + ".png")
	_check("capture_" + label, get_viewport().get_texture().get_image().save_png(path) == OK)

func _frames() -> void:
	for index in 3:
		await get_tree().process_frame

func _wait_for(predicate: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false

func _check(label: String, ok: bool) -> void:
	print("[ENTRY_UI] ", label, " pass=", ok)
	_passed += int(ok)
	_failed += int(not ok)
