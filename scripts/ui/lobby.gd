## Lobby — 联机大厅脚本 v4（HarmonyBridge 统一版）
## 大厅发现/配对逻辑全部走 HarmonyBridge；插件不可用时由桥内部回退调试后端。
extends Control

signal game_start_requested

const SafeArea := preload("res://scripts/ui/battle_safe_area.gd")
const RouteRules := preload("res://scripts/battle/trials/rift_route_rules.gd")
## 开局或战斗消息不兼容时更新此版本。检查先于任何开局远程调用。
const LAN_PROTOCOL := "space-bullet-hell-lan:9"
const VERSION_WAIT_MS := 3000
const VERSION_ERROR := "联机版本不兼容，请将两台设备更新到同一版本后重试"

enum LobbyMode { NONE, HOST, JOIN }
var _mode: LobbyMode = LobbyMode.NONE

@onready var _panel_mode_select: VBoxContainer = $VBox/PanelModeSelect
@onready var _btn_be_host: Button = $VBox/PanelModeSelect/BtnBeHost
@onready var _btn_be_client: Button = $VBox/PanelModeSelect/BtnBeClient

@onready var _panel_host: VBoxContainer = $VBox/PanelHost
@onready var _lbl_ssid_hint: Label = $VBox/PanelHost/LblSsidHint
@onready var _lbl_password: Label = $VBox/PanelHost/LblPassword
@onready var _btn_start: Button = $VBox/PanelHost/BtnStart
@onready var _btn_rift: Button = $VBox/PanelHost/BtnRiftRoute
@onready var _rift_rule: OptionButton = $VBox/PanelHost/RiftRule
@onready var _lbl_host_status: Label = $VBox/PanelHost/LblHostStatus

@onready var _panel_join: VBoxContainer = $VBox/PanelJoin
@onready var _lbl_scan_hint: Label = $VBox/PanelJoin/LblScanHint
@onready var _host_list: VBoxContainer = $VBox/PanelJoin/HostListScroll/HostList
@onready var _lbl_join_status: Label = $VBox/PanelJoin/LblJoinStatus
@onready var _btn_quick_join: Button = $VBox/PanelJoin/BtnQuickJoin
@onready var _confirm_rift_rule: Button = $VBox/PanelJoin/ConfirmRiftRule

@onready var _btn_back: Button = $VBox/BtnBack
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _debug_info: Label = $VBox/DebugInfo

var _host_buttons: Dictionary = {}
var _debug_tick: float = 0.0
var _compatible_peer := 0
var _version_deadline := 0
var _rule_revision := 0
var _preview_revision := -1


func _ready() -> void:
	_rift_rule.add_item(RouteRules.ORIGINAL)
	_rift_rule.add_item(RouteRules.REMIX)
	_rift_rule.select(0)
	_connect_signals()
	_show_mode_select()
	## 隐藏联机调试信息（DebugTitle + DebugInfo），保留内部刷新逻辑供后续排查
	_debug_info.visible = false
	var _debug_title := get_node_or_null("VBox/DebugTitle")
	if _debug_title:
		_debug_title.visible = false
	_refresh_debug_info()
	get_viewport().size_changed.connect(_layout_lobby)
	get_window().focus_entered.connect(_layout_lobby)
	_layout_lobby()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_layout_lobby.call_deferred()

func _layout_lobby() -> void:
	_layout_in_safe_area(SafeArea.for_viewport(get_viewport()))

func _layout_in_safe_area(safe: Rect2) -> void:
	var content := safe.grow(-SafeArea.MENU_MARGIN)
	var column: VBoxContainer = $VBox
	column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	column.size = Vector2(minf(440.0, content.size.x), minf(560.0, content.size.y))
	column.position = (content.get_center() - column.size * 0.5).round()


func _process(delta: float) -> void:
	if _version_deadline > 0 and Time.get_ticks_msec() >= _version_deadline:
		_show_version_error()
	_debug_tick += delta
	if _debug_tick >= 0.5:
		_debug_tick = 0.0
		_sync_host_buttons_from_bridge()
		_refresh_debug_info()


func _connect_signals() -> void:
	_btn_be_host.pressed.connect(_on_host_mode_selected)
	_btn_be_client.pressed.connect(_on_join_mode_selected)
	_btn_back.pressed.connect(_on_back_pressed, CONNECT_DEFERRED)
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_rift.pressed.connect(_on_start_pressed.bind(true))
	_rift_rule.item_selected.connect(_publish_rift_rule.unbind(1))
	_confirm_rift_rule.pressed.connect(_confirm_rift_preview)
	_btn_quick_join.pressed.connect(_on_quick_join_pressed)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.status_changed.connect(_on_status_changed)
	(multiplayer as SceneMultiplayer).peer_packet.connect(_on_lobby_packet)

	HarmonyBridge.host_list_updated.connect(_on_host_list_updated)
	HarmonyBridge.status_changed.connect(_on_harmony_status_changed)


func _show_mode_select() -> void:
	_panel_mode_select.visible = true
	_panel_host.visible = false
	_panel_join.visible = false
	_mode = LobbyMode.NONE
	_compatible_peer = 0
	_version_deadline = 0
	_stop_discovery_services()
	_set_legacy_controls_visible(false)
	if HarmonyBridge.refresh_plugin_binding():
		_status_label.text = "鸿蒙互联可用：可直接附近发现"
	else:
		_status_label.text = "未检测到鸿蒙插件：当前会走调试后端"
	_refresh_debug_info()


func _show_host_panel() -> void:
	## 房主面板：创建 ENet 服务器 + 通过 Harmony/NSD 发布房间
	_panel_mode_select.visible = false
	_panel_host.visible = true
	_panel_join.visible = false
	_btn_start.visible = false
	_btn_rift.visible = false
	_rift_rule.hide()
	_rift_rule.select(0)
	_btn_start.disabled = true
	_btn_rift.disabled = true
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
	## 加入面板：启动 Harmony/NSD 扫描，发现附近房间后展示可点击列表
	_panel_mode_select.visible = false
	_panel_host.visible = false
	_panel_join.visible = true
	_set_legacy_controls_visible(false)
	_mode = LobbyMode.JOIN

	_clear_host_list()
	_btn_quick_join.visible = false
	_btn_quick_join.disabled = true
	_confirm_rift_rule.hide()
	_preview_revision = -1
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


func _on_start_pressed(rift_route := false) -> void:
	if not NetworkManager.is_host or not _compatible_peer in NetworkManager.connected_peers or (rift_route and _btn_rift.disabled):
		return
	_stop_discovery_services()
	_rpc_start_game.rpc(NetworkManager.LAN_BATTLE_SIZE, rift_route, rift_route and _rift_rule.selected == 1)

func _publish_rift_rule() -> void:
	if not multiplayer.is_server() or _compatible_peer == 0:
		return
	_rule_revision += 1
	var remix := _rift_rule.selected == 1
	_btn_rift.disabled = remix
	_lbl_host_status.text = "等待加入端确认变奏航道…" if remix else "玩家已加入，可以开始游戏"
	_rpc_preview_rift_rule.rpc_id(_compatible_peer, _rule_revision, remix)
	if remix:
		var revision := _rule_revision
		# 先让预览发出去，两端可同时预载各自的控制器。
		await get_tree().process_frame
		if is_inside_tree() and _compatible_peer != 0 and _rule_revision == revision:
			NetworkManager.warm_remix_pilot_scripts()

@rpc("authority", "reliable", "call_remote")
func _rpc_preview_rift_rule(revision: int, remix: bool) -> void:
	if _compatible_peer != 1 or revision <= _preview_revision:
		return
	_preview_revision = revision
	_lbl_join_status.text = RouteRules.description(remix)
	_confirm_rift_rule.visible = remix
	if remix:
		NetworkManager.warm_remix_pilot_scripts()

func _confirm_rift_preview() -> void:
	if _compatible_peer != 1 or not _confirm_rift_rule.visible:
		return
	_confirm_rift_rule.hide()
	_lbl_join_status.text = RouteRules.REMIX + "\n已确认，等待房主开始"
	_rpc_confirm_rift_rule.rpc_id(1, _preview_revision)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_confirm_rift_rule(revision: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _compatible_peer or revision != _rule_revision or _rift_rule.selected != 1:
		return
	_btn_rift.disabled = false
	_lbl_host_status.text = "加入端已确认变奏航道"


func _on_back_pressed() -> void:
	_stop_discovery_services()
	NetworkManager.disconnect_network()
	_refresh_debug_info()
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")


@rpc("authority", "reliable", "call_local")
func _rpc_start_game(battle_size: Vector2i, rift_route := false, remix := false) -> void:
	if not NetworkManager.is_online() or _compatible_peer == 0:
		_show_version_error()
		return
	_stop_discovery_services()
	if battle_size != NetworkManager.LAN_BATTLE_SIZE:
		NetworkManager.disconnect_network()
		_show_mode_select()
		_status_label.text = "战场尺寸不兼容，请确认双方的游戏版本"
		return
	game_start_requested.emit()
	GameState.rift_remix = rift_route and remix
	get_tree().change_scene_to_file("res://scenes/rift_route_trial.tscn" if rift_route else "res://scenes/main.tscn")


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
	## 玩家点击房间按钮后发起 ENet 连接
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
	## 快速加入第一个可用房间
	var hosts := HarmonyBridge.get_discovered_hosts()
	if hosts.is_empty():
		_lbl_join_status.text = "❌ 未发现可加入房间"
		return
	var first: Dictionary = hosts[0]
	_on_host_button_pressed(String(first.get("ip", "")), int(first.get("port", 0)))


func _deferred_join_host(ip: String, port: int) -> void:
	## 延迟一帧发起连接，避免信号回调中直接操作网络导致的时序问题
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
		_btn_rift.visible = true
		_btn_start.disabled = true
		_btn_rift.disabled = true
		_begin_version_check(peer_id)


func _on_player_disconnected(_peer_id: int) -> void:
	if NetworkManager.is_host and NetworkManager.connected_peers.is_empty():
		_compatible_peer = 0
		_version_deadline = 0
		_btn_start.disabled = true
		_btn_rift.disabled = true
		_btn_start.visible = false
		_btn_rift.visible = false
		_rift_rule.hide()
		_lbl_host_status.text = "玩家已离开，等待重新加入…"


func _on_connection_succeeded() -> void:
	_stop_discovery_services()
	_begin_version_check(1)
	_refresh_debug_info()

func _begin_version_check(peer_id: int) -> void:
	if _compatible_peer == peer_id:
		return
	_version_deadline = Time.get_ticks_msec() + VERSION_WAIT_MS
	_version_label().text = "已连接，正在检查联机版本…"
	var err := (multiplayer as SceneMultiplayer).send_bytes(LAN_PROTOCOL.to_utf8_buffer(), peer_id)
	if err != OK:
		_show_version_error()

func _on_lobby_packet(peer_id: int, packet: PackedByteArray) -> void:
	if not NetworkManager.is_online():
		return
	if peer_id not in NetworkManager.connected_peers and (NetworkManager.is_host or peer_id != 1):
		return
	if packet != LAN_PROTOCOL.to_utf8_buffer():
		_show_version_error()
		return
	_compatible_peer = peer_id
	_version_deadline = 0
	if NetworkManager.is_host:
		_btn_start.disabled = false
		_rift_rule.show()
		_publish_rift_rule()
	else:
		_lbl_join_status.text = "联机版本一致，等待房主开始…"

func _version_label() -> Label:
	return _lbl_host_status if NetworkManager.is_host else _lbl_join_status

func _show_version_error() -> void:
	_compatible_peer = 0
	_version_deadline = 0
	_btn_start.disabled = true
	_btn_rift.disabled = true
	_rift_rule.hide()
	_confirm_rift_rule.hide()
	_version_label().text = VERSION_ERROR


func _on_connection_failed() -> void:
	_compatible_peer = 0
	_version_deadline = 0
	_confirm_rift_rule.hide()
	_preview_revision = -1
	_lbl_join_status.text = "❌ 连接失败，请重试"
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.disabled = false
	_refresh_debug_info()


func _on_server_disconnected() -> void:
	_compatible_peer = 0
	_version_deadline = 0
	_confirm_rift_rule.hide()
	_preview_revision = -1
	_lbl_join_status.text = "服务器断开，请返回重试"
	_refresh_debug_info()


func _on_status_changed(message: String) -> void:
	_status_label.text = message
	_refresh_debug_info()


func _on_harmony_status_changed(message: String) -> void:
	if message.is_empty() or not NetworkManager.connected_peers.is_empty():
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
