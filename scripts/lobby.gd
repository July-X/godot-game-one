## Lobby — 联机大厅脚本 v4（HarmonyBridge 统一版）
## 大厅发现/配对逻辑全部走 HarmonyBridge；插件不可用时由桥内部回退调试后端。
extends Control

signal game_start_requested

enum LobbyMode { NONE, HOST, JOIN }
var _mode: LobbyMode = LobbyMode.NONE

@onready var _panel_mode_select: VBoxContainer = $VBox/PanelModeSelect
@onready var _btn_be_host: Button = $VBox/PanelModeSelect/BtnBeHost
@onready var _btn_be_client: Button = $VBox/PanelModeSelect/BtnBeClient

@onready var _panel_host: VBoxContainer = $VBox/PanelHost
@onready var _lbl_ssid_hint: Label = $VBox/PanelHost/LblSsidHint
@onready var _lbl_password: Label = $VBox/PanelHost/LblPassword
@onready var _btn_start: Button = $VBox/PanelHost/BtnStart
@onready var _lbl_host_status: Label = $VBox/PanelHost/LblHostStatus

@onready var _panel_join: VBoxContainer = $VBox/PanelJoin
@onready var _lbl_scan_hint: Label = $VBox/PanelJoin/LblScanHint
@onready var _host_list: VBoxContainer = $VBox/PanelJoin/HostListScroll/HostList
@onready var _lbl_join_status: Label = $VBox/PanelJoin/LblJoinStatus
@onready var _btn_quick_join: Button = $VBox/PanelJoin/BtnQuickJoin

@onready var _btn_back: Button = $VBox/BtnBack
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _debug_info: Label = $VBox/DebugInfo

var _host_buttons: Dictionary = {}
var _debug_tick: float = 0.0


func _ready() -> void:
	_connect_signals()
	_show_mode_select()
	_refresh_debug_info()


func _process(delta: float) -> void:
	_debug_tick += delta
	if _debug_tick >= 0.5:
		_debug_tick = 0.0
		_sync_host_buttons_from_bridge()
		_refresh_debug_info()


func _connect_signals() -> void:
	_btn_be_host.pressed.connect(_on_host_mode_selected)
	_btn_be_client.pressed.connect(_on_join_mode_selected)
	_btn_back.pressed.connect(_on_back_pressed)
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_quick_join.pressed.connect(_on_quick_join_pressed)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.status_changed.connect(_on_status_changed)

	HarmonyBridge.host_list_updated.connect(_on_host_list_updated)
	HarmonyBridge.status_changed.connect(_on_harmony_status_changed)


func _show_mode_select() -> void:
	_panel_mode_select.visible = true
	_panel_host.visible = false
	_panel_join.visible = false
	_mode = LobbyMode.NONE
	_stop_discovery_services()
	_set_legacy_controls_visible(false)
	if HarmonyBridge.refresh_plugin_binding():
		_status_label.text = "鸿蒙互联可用：可直接附近发现"
	else:
		_status_label.text = "未检测到鸿蒙插件：当前会走调试后端"
	_refresh_debug_info()


func _show_host_panel() -> void:
	_panel_mode_select.visible = false
	_panel_host.visible = true
	_panel_join.visible = false
	_btn_start.visible = false
	_btn_start.disabled = true
	_set_legacy_controls_visible(false)

	var err := NetworkManager.create_host_with_mode(NetworkManager.TRANSPORT_HARMONY)
	if err != OK:
		_lbl_host_status.text = "❌ 启动服务器失败：%s" % error_string(err)
		return

	_lbl_ssid_hint.text = "🤝 鸿蒙万物互联：附近设备可直接发现"
	_lbl_password.text = "无需手动配置热点名和密码"
	_lbl_host_status.text = "正在发布鸿蒙近场房间…"
	var publish_err := HarmonyBridge.start_host_advertise("Space Bullet Hell", NetworkManager.DEFAULT_PORT)
	if publish_err != OK:
		_lbl_host_status.text = "❌ 房间发布失败：%s" % error_string(publish_err)
		return

	_mode = LobbyMode.HOST
	_status_label.text = "等待对方加入…"
	_refresh_debug_info()


func _show_join_panel() -> void:
	_panel_mode_select.visible = false
	_panel_host.visible = false
	_panel_join.visible = true
	_set_legacy_controls_visible(false)
	_mode = LobbyMode.JOIN

	_clear_host_list()
	_btn_quick_join.visible = false
	_btn_quick_join.disabled = true
	_lbl_scan_hint.text = "🔍 正在扫描附近鸿蒙设备…"
	_lbl_join_status.text = "无需手动连热点，等待房间出现后点击加入"
	var scan_err := HarmonyBridge.start_scan()
	if scan_err != OK:
		_lbl_join_status.text = "❌ 设备扫描失败：%s" % error_string(scan_err)
		return

	_status_label.text = "搜索房间中…"
	## 扫描开始前后都可能已有缓存房间，这里主动刷新一次按钮列表，避免快回调丢失。
	_sync_host_buttons_from_bridge()
	_on_host_list_updated(HarmonyBridge.get_discovered_hosts())
	_refresh_debug_info()


func _on_host_mode_selected() -> void:
	_show_host_panel()


func _on_join_mode_selected() -> void:
	_show_join_panel()


func _on_start_pressed() -> void:
	if not NetworkManager.is_host:
		return
	_stop_discovery_services()
	_rpc_start_game.rpc()


func _on_back_pressed() -> void:
	_stop_discovery_services()
	NetworkManager.disconnect_network()
	_refresh_debug_info()
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")


@rpc("authority", "reliable", "call_local")
func _rpc_start_game() -> void:
	_stop_discovery_services()
	game_start_requested.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_host_list_updated(hosts: Array) -> void:
	if _mode != LobbyMode.JOIN:
		return

	var added := false
	for entry: Dictionary in hosts:
		var key := "%s:%d" % [entry.get("ip", ""), entry.get("port", 0)]
		if _host_buttons.has(key):
			continue
		var ip := String(entry.get("ip", ""))
		var port := int(entry.get("port", 0))
		if ip.is_empty() or port <= 0:
			continue
		var btn := Button.new()
		btn.text = "🎮  %s\n%s" % [String(entry.get("name", "Room")), key]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 18)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(func(): _on_host_button_pressed(ip, port))
		_host_list.add_child(btn)
		_host_buttons[key] = btn
		added = true

	if _host_buttons.is_empty() and not added:
		_lbl_scan_hint.text = "🔍 扫描中，未找到房间…"
		_btn_quick_join.visible = false
		_btn_quick_join.disabled = true
	else:
		_lbl_scan_hint.text = "✅ 找到 %d 个房间，点击加入" % _host_buttons.size()
		_btn_quick_join.visible = true
		_btn_quick_join.disabled = false


func _on_host_button_pressed(ip: String, port: int) -> void:
	var normalized_ip := ip.strip_edges()
	if not _is_valid_ipv4(normalized_ip):
		_lbl_join_status.text = "❌ 房间地址无效：%s（仅支持 IPv4）" % normalized_ip
		return
	if port <= 0 or port > 65535:
		_lbl_join_status.text = "❌ 房间端口无效：%d" % port
		return
	_lbl_join_status.text = "正在连接 %s:%d …" % [normalized_ip, port]
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.disabled = true
	call_deferred("_deferred_join_host", normalized_ip, port)


func _on_quick_join_pressed() -> void:
	var hosts := HarmonyBridge.get_discovered_hosts()
	if hosts.is_empty():
		_lbl_join_status.text = "❌ 未发现可加入房间"
		return
	var first: Dictionary = hosts[0]
	_on_host_button_pressed(String(first.get("ip", "")), int(first.get("port", 0)))


func _deferred_join_host(ip: String, port: int) -> void:
	if not _is_valid_ipv4(ip):
		_lbl_join_status.text = "❌ 房间地址无效：%s" % ip
		return
	if port <= 0 or port > 65535:
		_lbl_join_status.text = "❌ 房间端口无效：%d" % port
		return
	var err := NetworkManager.join_host_with_mode(NetworkManager.TRANSPORT_HARMONY, ip, port)
	if err != OK:
		_lbl_join_status.text = "❌ 连接发起失败：%s" % error_string(err)
		for key: String in _host_buttons:
			var btn: Button = _host_buttons[key]
			btn.disabled = false


func _on_player_connected(peer_id: int) -> void:
	if NetworkManager.is_host:
		_btn_start.visible = true
		_btn_start.disabled = false
		_lbl_host_status.text = "✅ 玩家 %d 已加入！" % peer_id


func _on_player_disconnected(_peer_id: int) -> void:
	if NetworkManager.is_host and NetworkManager.connected_peers.is_empty():
		_btn_start.disabled = true
		_btn_start.visible = false
		_lbl_host_status.text = "玩家已离开，等待重新加入…"


func _on_connection_succeeded() -> void:
	_stop_discovery_services()
	_lbl_join_status.text = "✅ 已连接，等待房主开始…"
	_status_label.text = "已连接"
	_refresh_debug_info()


func _on_connection_failed() -> void:
	_lbl_join_status.text = "❌ 连接失败，请重试"
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.disabled = false
	_refresh_debug_info()


func _on_server_disconnected() -> void:
	_lbl_join_status.text = "服务器断开，请返回重试"
	_refresh_debug_info()


func _on_status_changed(message: String) -> void:
	_status_label.text = message
	_refresh_debug_info()


func _on_harmony_status_changed(message: String) -> void:
	if message.is_empty():
		return
	_status_label.text = message
	if _mode == LobbyMode.HOST:
		_lbl_host_status.text = message
	elif _mode == LobbyMode.JOIN:
		_lbl_join_status.text = message
	_refresh_debug_info()


func _clear_host_list() -> void:
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.queue_free()
	_host_buttons.clear()


func _stop_discovery_services() -> void:
	HarmonyBridge.stop_all()
	_refresh_debug_info()


func _set_legacy_controls_visible(visible: bool) -> void:
	var legacy_nodes := [
		get_node_or_null("VBox/PanelHost/BtnCopySsid"),
		get_node_or_null("VBox/PanelHost/BtnCopyPassword"),
		get_node_or_null("VBox/PanelHost/BtnOpenHotspot"),
		get_node_or_null("VBox/PanelJoin/BtnOpenWifi"),
	]
	for node in legacy_nodes:
		if node and node is CanvasItem:
			node.visible = visible


func _is_valid_ipv4(ip: String) -> bool:
	if ip.is_empty():
		return false
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty():
			return false
		var value := int(part)
		if str(value) != part:
			return false
		if value < 0 or value > 255:
			return false
	return true


func _refresh_debug_info() -> void:
	_sync_host_buttons_from_bridge()
	var harmony := HarmonyBridge.get_debug_snapshot()
	var hosts := HarmonyBridge.get_discovered_hosts()
	var peer_state := "none"
	if multiplayer.multiplayer_peer != null:
		var status := multiplayer.multiplayer_peer.get_connection_status()
		match status:
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				peer_state = "disconnected"
			MultiplayerPeer.CONNECTION_CONNECTING:
				peer_state = "connecting"
			MultiplayerPeer.CONNECTION_CONNECTED:
				peer_state = "connected"
			_:
				peer_state = "unknown(%d)" % status
	var lines := PackedStringArray([
		"mode=%s, transport=%s, is_host=%s, online=%s" % [_mode_to_text(_mode), NetworkManager.transport_mode, str(NetworkManager.is_host), str(NetworkManager.is_online())],
		"peer_status=%s, my_peer_id=%d, connected_peers=%s" % [peer_state, NetworkManager.get_my_peer_id(), str(NetworkManager.connected_peers)],
		"harmony_available=%s, plugin=%s, hosting=%s, scanning=%s, fallback=%s" % [
			str(bool(harmony.get("plugin_available", false))),
			String(harmony.get("plugin_name", "none")),
			str(bool(harmony.get("is_hosting", false))),
			str(bool(harmony.get("is_scanning", false))),
			str(bool(harmony.get("fallback_backend", false)))
		],
		"discovered_count=%d, host_buttons=%d" % [int(harmony.get("discovered_count", hosts.size())), _host_buttons.size()],
		"last_harmony_status=%s" % String(harmony.get("last_status", "")),
	])
	if not hosts.is_empty():
		var first: Dictionary = hosts[0]
		lines.append("first_room=%s@%s:%d source=%s" % [
			String(first.get("name", "Room")),
			String(first.get("ip", "")),
			int(first.get("port", 0)),
			String(first.get("source", "unknown")),
		])
	_debug_info.text = "\n".join(lines)


func _sync_host_buttons_from_bridge() -> void:
	if _mode != LobbyMode.JOIN:
		return
	var hosts := HarmonyBridge.get_discovered_hosts()
	if hosts.is_empty():
		if _host_buttons.is_empty():
			_lbl_scan_hint.text = "🔍 扫描中，未找到房间…"
		return
	_on_host_list_updated(hosts)
	if _host_buttons.size() > 0 and _host_list.get_child_count() == 0:
		var fallback_btn := Button.new()
		fallback_btn.text = "🎮 点击加入（调试占位）\n若看到此按钮说明布局异常"
		fallback_btn.custom_minimum_size = Vector2(0, 72)
		fallback_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fallback_btn.add_theme_font_size_override("font_size", 16)
		fallback_btn.pressed.connect(func():
			var first: Dictionary = hosts[0]
			_on_host_button_pressed(String(first.get("ip", "")), int(first.get("port", 0)))
		)
		_host_list.add_child(fallback_btn)


func _mode_to_text(mode: LobbyMode) -> String:
	match mode:
		LobbyMode.HOST:
			return "HOST"
		LobbyMode.JOIN:
			return "JOIN"
		_:
			return "NONE"
