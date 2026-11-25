extends Node
## 运行真正的标题、大厅和开局路由。用直连地址隔离发现服务。

const LOBBY := "res://scenes/ui/lobby.tscn"
const RIFT := "res://scenes/rift_route_trial.tscn"
const NORMAL := "res://scenes/main.tscn"
const RouteRules := preload("res://scripts/battle/trials/rift_route_rules.gd")
var _passed := 0
var _failed := 0

func _ready() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args[0] == "host"
	var port := int(args[1])
	var case_name := args[2] if args.size() > 2 else "normal"
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("Menu/BtnMultiplayer").pressed.emit()
	await get_tree().scene_changed
	var lobby := get_tree().current_scene
	_check("title_to_lobby", lobby.scene_file_path == LOBBY)
	if host:
		lobby.get_node("VBox/PanelModeSelect").hide()
		lobby.get_node("VBox/PanelHost").show()
		_check("host_listens", NetworkManager.create_host_with_mode(NetworkManager.TRANSPORT_HARMONY, port) == OK)
	else:
		lobby._on_join_mode_selected()
		lobby._deferred_join_host("127.0.0.1", port)
	var connected := await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 6.0)
	_check("enet_connected_in_lobby", connected)
	if connected and case_name == "expect-mismatch":
		await _verify_rejection(lobby, host)
	elif connected:
		await _verify_start(lobby, host, case_name)
	await get_tree().create_timer(.25).timeout
	print("[LOBBY] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _verify_start(lobby: Node, host: bool, case_name: String) -> void:
	var remix := case_name == "remix"
	var rift := remix or case_name == "rift"
	if host:
		var button: Button = lobby.get_node("VBox/PanelHost/BtnRiftRoute" if rift else "VBox/PanelHost/BtnStart")
		var enabled := await _wait_until(func(): return button.is_visible_in_tree() and not button.disabled, 4.0)
		_check("start_available_after_version_check", enabled)
		if enabled and remix:
			lobby._rift_rule.select(1)
			lobby._rift_rule.item_selected.emit(1)
			_check("remix_start_waits_for_joiner_confirmation", button.disabled)
			enabled = await _wait_until(func(): return not button.disabled, 4.0)
			_check("matching_confirmation_enables_remix", enabled)
		if enabled:
			button.pressed.emit()
	elif remix:
		var shown := await _wait_until(func(): return lobby._confirm_rift_rule.is_visible_in_tree(), 4.0)
		_check("joiner_sees_rule_before_start", shown and lobby._lbl_join_status.text == RouteRules.REMIX)
		if shown:
			lobby._confirm_rift_rule.pressed.emit()
	var expected := RIFT if rift else NORMAL
	_check("expected_battle_loaded", await _wait_until(func():
		return (is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == expected), 6.0))
	if is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == expected:
		if rift:
			_check("same_selected_route_on_arrival", get_tree().current_scene.remix == remix)
		_check("both_pilots_synced", await _wait_until(func(): return get_tree().current_scene._players.size() == 2, 4.0))
		if host:
			_check("guest_can_report_after_entering_battle",
				await _wait_until(func(): return get_tree().current_scene.get_player_report_count() > 0, 4.0))
		else:
			await get_tree().create_timer(1.0).timeout
		if remix:
			await _verify_remix_recovery_and_retry(host)

func _verify_remix_recovery_and_retry(host: bool) -> void:
	var battle := get_tree().current_scene
	var battle_id := battle.get_instance_id()
	var reserved := await _wait_until(func(): return NetworkManager.recovery.is_reserved(), 4.0)
	_check("remix_recovery_reserved", reserved)
	if not reserved:
		return
	var original_wire: int = NetworkManager.recovery.guest_wire
	if not host:
		NetworkManager.recovery.set_background(true)
		await get_tree().create_timer(.2).timeout
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var restored := await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != original_wire
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13.0)
	_check("remix_reconnect_keeps_agreed_rule", restored and get_tree().current_scene == battle and battle.remix)
	if not restored:
		return
	if host:
		await get_tree().create_timer(.3).timeout
		battle._restart()
	var restarted := await _wait_until(func():
		var current := get_tree().current_scene
		return is_instance_valid(current) and current.get_instance_id() != battle_id and current.scene_file_path == RIFT, 4.0)
	_check("remix_host_retry_retains_rule", restarted and get_tree().current_scene.remix)

func _verify_rejection(lobby: Node, host: bool) -> void:
	var status: Label = lobby._lbl_host_status if host else lobby._lbl_join_status
	_check("visible_version_warning", await _wait_until(func(): return status.text.contains("联机版本不兼容"), 4.5))
	if host:
		_check("both_start_buttons_disabled", lobby._btn_start.disabled and lobby._btn_rift.disabled)
		lobby._btn_start.pressed.emit()
		lobby._btn_rift.pressed.emit()
	await get_tree().process_frame
	_check("mixed_version_stays_in_lobby", get_tree().current_scene == lobby)

func _wait_until(check: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if check.call():
			return true
		await get_tree().process_frame
	return false

func _check(label: String, ok: bool) -> void:
	print("[LOBBY] ", label, " pass=", ok)
	_passed += int(ok)
	_failed += int(not ok)
