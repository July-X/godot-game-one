extends Node
## 运行真正的标题、大厅和开局路由。用直连地址隔离发现服务。

const LOBBY := "res://scenes/ui/lobby.tscn"
const RIFT := "res://scenes/rift_route_trial.tscn"
const NORMAL := "res://scenes/main.tscn"
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
		await _verify_start(lobby, host, case_name == "rift")
	await get_tree().create_timer(.25).timeout
	print("[LOBBY] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _verify_start(lobby: Node, host: bool, rift: bool) -> void:
	if host:
		var button: Button = lobby.get_node("VBox/PanelHost/BtnRiftRoute" if rift else "VBox/PanelHost/BtnStart")
		var enabled := await _wait_until(func(): return button.is_visible_in_tree() and not button.disabled, 4.0)
		_check("start_available_after_version_check", enabled)
		if enabled:
			button.pressed.emit()
	var expected := RIFT if rift else NORMAL
	_check("expected_battle_loaded", await _wait_until(func():
		return (is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == expected), 6.0))
	if is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == expected:
		_check("both_pilots_synced", await _wait_until(func(): return get_tree().current_scene._players.size() == 2, 4.0))
		if host:
			_check("guest_can_report_after_entering_battle",
				await _wait_until(func(): return get_tree().current_scene.get_player_report_count() > 0, 4.0))

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
