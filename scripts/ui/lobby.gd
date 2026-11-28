extends Control

signal game_start_requested

const SafeArea := preload("res://scripts/ui/battle_safe_area.gd")
const RouteRules := preload("res://scripts/battle/trials/rift_route_rules.gd")
const EntryCard := preload("res://scripts/ui/entry_card.gd")
const LAN_PROTOCOL := "space-bullet-hell-lan:10"
const VERSION_WAIT_MS := 3000
const VERSION_ERROR := "联机版本不兼容，请将两台设备更新到同一版本后重试"
const EMPTY_SEARCH_MS := 1800

enum LobbyMode { NONE, HOST, JOIN }
var _mode: LobbyMode = LobbyMode.NONE
var _host_buttons: Dictionary[String, Button] = {}
var _compatible_peer := 0
var _version_deadline := 0
var _rule_revision := 0
var _preview_revision := -1
var _dual_intercept := false
var _scan_active := false
var _search_deadline := 0
var _joining := false
var _join_generation := 0
var _launching := false
var _saved_quit_on_go_back := true
var _back_pending := false
var _safe: Rect2

@onready var _column: VBoxContainer = $VBox
@onready var _title: Label = $VBox/Title
@onready var _subtitle: Label = $VBox/Subtitle
@onready var _panel_mode_select: GridContainer = $VBox/PanelModeSelect
@onready var _btn_be_host: Button = $VBox/PanelModeSelect/BtnBeHost
@onready var _btn_be_client: Button = $VBox/PanelModeSelect/BtnBeClient
@onready var _panel_host: VBoxContainer = $VBox/PanelHost
@onready var _room_type: Label = $VBox/PanelHost/RoomInfo/RoomType
@onready var _occupancy: Label = $VBox/PanelHost/RoomInfo/Occupancy
@onready var _btn_start: Button = $VBox/PanelHost/BtnStart
@onready var _btn_rift: Button = $VBox/PanelHost/BtnRiftRoute
@onready var _rift_rule: OptionButton = $VBox/PanelHost/RiftRule
@onready var _lbl_host_status: Label = $VBox/PanelHost/LblHostStatus
@onready var _host_detail: Label = $VBox/PanelHost/HostDetail
@onready var _retry_host: Button = $VBox/PanelHost/RetryHost
@onready var _panel_join: VBoxContainer = $VBox/PanelJoin
@onready var _lbl_scan_hint: Label = $VBox/PanelJoin/LblScanHint
@onready var _lbl_join_status: Label = $VBox/PanelJoin/LblJoinStatus
@onready var _room_scroll: ScrollContainer = $VBox/PanelJoin/HostListScroll
@onready var _host_list: VBoxContainer = $VBox/PanelJoin/HostListScroll/HostList
@onready var _confirm_rift_rule: Button = $VBox/PanelJoin/ConfirmRiftRule
@onready var _retry_search: Button = $VBox/PanelJoin/RetrySearch
@onready var _btn_back: Button = $VBox/BtnBack

func _enter_tree() -> void:
	_saved_quit_on_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _saved_quit_on_go_back

func _ready() -> void:
	_dual_intercept = GameState.rift_dual_intercept
	_rift_rule.add_item(RouteRules.ORIGINAL)
	_rift_rule.add_item(RouteRules.REMIX)
	_rift_rule.select(1 if _dual_intercept else 0)
	_room_type.text = RouteRules.DUAL_INTERCEPT if _dual_intercept else "普通合作 / 裂隙航道"
	if _dual_intercept:
		_btn_rift.text = "开始双线截击"
	_connect_signals()
	HarmonyBridge.refresh_plugin_binding()
	_show_mode_select()
	get_viewport().size_changed.connect(_layout_lobby)
	get_window().focus_entered.connect(_layout_lobby)
	_column.minimum_size_changed.connect(_resize_column.call_deferred)
	_layout_lobby()

func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_request_back()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_layout_lobby.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_request_back()

func _layout_lobby() -> void:
	_layout_in_safe_area(SafeArea.for_viewport(get_viewport()))

func _layout_in_safe_area(safe: Rect2) -> void:
	_safe = safe
	_resize_column()

func _resize_column() -> void:
	if not _safe.has_area():
		return
	var content := _safe.grow(-SafeArea.MENU_MARGIN)
	var width := minf(626.0, content.size.x)
	_panel_mode_select.columns = 2 if width >= 520.0 else 1
	var join_height := minf(550.0, content.size.y) if _mode == LobbyMode.JOIN else 0.0
	_column.size = Vector2(width, join_height)
	_column.position = (content.get_center() - _column.size * 0.5).round()

func _process(_delta: float) -> void:
	if _back_pending:
		return
	var now := Time.get_ticks_msec()
	if _version_deadline > 0 and now >= _version_deadline:
		_show_version_error()
	if _scan_active and _search_deadline > 0 and now >= _search_deadline:
		_search_deadline = 0
		_update_room_search()

func _connect_signals() -> void:
	_btn_be_host.pressed.connect(_on_host_mode_selected)
	_btn_be_client.pressed.connect(_on_join_mode_selected)
	_btn_back.pressed.connect(_request_back)
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_rift.pressed.connect(_on_start_pressed.bind(true))
	_rift_rule.item_selected.connect(_publish_rift_rule.unbind(1))
	_confirm_rift_rule.pressed.connect(_confirm_rift_preview)
	_retry_host.pressed.connect(_on_host_mode_selected, CONNECT_DEFERRED)
	_retry_search.pressed.connect(_on_join_mode_selected, CONNECT_DEFERRED)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	(multiplayer as SceneMultiplayer).peer_packet.connect(_on_lobby_packet)
	HarmonyBridge.host_list_updated.connect(_on_host_list_updated)
	HarmonyBridge.status_changed.connect(_on_harmony_status_changed)

func _show_panel(mode: LobbyMode, title: String) -> void:
	_mode = mode
	_title.text = title
	_panel_mode_select.visible = mode == LobbyMode.NONE
	_panel_host.visible = mode == LobbyMode.HOST
	_panel_join.visible = mode == LobbyMode.JOIN
	_subtitle.visible = mode == LobbyMode.NONE and _dual_intercept
	_btn_back.text = "返回标题" if mode == LobbyMode.NONE else "返回角色选择"
	_resize_column()

func _show_mode_select() -> void:
	_subtitle.text = "双方请从「试飞任务 → 裂隙航道 → 双线截击」进入"
	_show_panel(LobbyMode.NONE, "双线截击 · 双人房间" if _dual_intercept else "双人联机")
	_btn_be_host.grab_focus()

func _on_host_mode_selected() -> void:
	if _back_pending or (_mode == LobbyMode.HOST and not _retry_host.visible):
		return
	var returning := _mode == LobbyMode.HOST
	_leave_panel()
	_show_host_panel()
	if returning and _retry_host.visible:
		_retry_host.grab_focus()

func _show_host_panel() -> void:
	_show_panel(LobbyMode.HOST, "创建房间")
	_rift_rule.select(1 if _dual_intercept else 0)
	_reset_host_actions()
	_retry_host.hide()
	_occupancy.text = "— / 2"
	_lbl_host_status.text = "正在创建房间"
	_host_detail.hide()
	_btn_back.grab_focus()
	var err := NetworkManager.create_host_with_mode(NetworkManager.TRANSPORT_HARMONY)
	if err != OK:
		_show_host_failure("无法创建房间", "请关闭其他占用房间端口的游戏实例，再重新创建。")
		return
	_occupancy.text = "1 / 2"
	var room := RouteRules.DUAL_INTERCEPT if _dual_intercept else "Space Bullet Hell"
	var publish_err := HarmonyBridge.start_host_advertise(room, NetworkManager.DEFAULT_PORT, _dual_intercept)
	if publish_err != OK:
		_show_host_failure("无法发布附近房间", "请检查附近设备权限和网络，再重新创建。")
	elif not _retry_host.visible:
		_show_host_waiting(false)

func _on_join_mode_selected() -> void:
	if _back_pending or (_mode == LobbyMode.JOIN and not _retry_search.visible):
		return
	_leave_panel()
	_show_join_panel()

func _show_join_panel() -> void:
	_show_panel(LobbyMode.JOIN, "加入附近房间")
	_confirm_rift_rule.hide()
	_room_scroll.hide()
	_retry_search.show()
	_scan_active = true
	_search_deadline = Time.get_ticks_msec() + EMPTY_SEARCH_MS
	_update_room_search()
	_retry_search.grab_focus()
	var scan_err := HarmonyBridge.start_scan()
	if scan_err != OK:
		_show_join_failure("无法搜索附近房间", "请检查附近设备权限和网络，再重新搜索。")
	elif _scan_active:
		_on_host_list_updated(HarmonyBridge.get_discovered_hosts())

func _leave_panel() -> void:
	_mode = LobbyMode.NONE
	_stop_discovery_services()
	_join_generation += 1
	_joining = false
	_compatible_peer = 0
	_version_deadline = 0
	_preview_revision = -1
	_rule_revision = 0
	_clear_host_list()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		NetworkManager.disconnect_network()

func _request_back() -> void:
	if _back_pending or _launching:
		return
	# The window, keyboard and button can report the same back action in one frame.
	_back_pending = true
	_on_back_pressed.call_deferred()

func _on_back_pressed() -> void:
	var previous := _mode
	_leave_panel()
	if previous == LobbyMode.NONE:
		# Keep the window policy until all back inputs from this frame are consumed.
		await get_tree().process_frame
		get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	else:
		_show_mode_select()
		if previous == LobbyMode.JOIN:
			_btn_be_client.grab_focus()
		await get_tree().process_frame
		_back_pending = false

func _on_start_pressed(rift_route := false) -> void:
	if _back_pending or _launching or not NetworkManager.is_host or not _compatible_peer in NetworkManager.connected_peers or (rift_route and _btn_rift.disabled):
		return
	if _dual_intercept and not rift_route:
		return
	_stop_discovery_services()
	_rpc_start_game.rpc(NetworkManager.LAN_BATTLE_SIZE, rift_route, rift_route and _rift_rule.selected == 1)

func _publish_rift_rule() -> void:
	if not multiplayer.is_server() or _compatible_peer == 0:
		return
	_rule_revision += 1
	var remix := _rift_rule.selected == 1
	_btn_rift.disabled = remix
	_lbl_host_status.text = "等待搭档确认玩法" if remix else "搭档已加入，可以开始"
	_host_detail.hide()
	_rpc_preview_rift_rule.rpc_id(_compatible_peer, _rule_revision, remix)
	if remix:
		var revision := _rule_revision
		# 先发送原有规则预览，让两端同时预载各自的控制器。
		await get_tree().process_frame
		if is_inside_tree() and _compatible_peer != 0 and _rule_revision == revision:
			NetworkManager.warm_remix_pilot_scripts()

@rpc("authority", "reliable", "call_remote")
func _rpc_preview_rift_rule(revision: int, remix: bool) -> void:
	if _compatible_peer != 1 or revision <= _preview_revision:
		return
	_preview_revision = revision
	_lbl_scan_hint.text = "确认本局玩法" if remix else "等待房主开始"
	_lbl_join_status.text = RouteRules.DUAL_INTERCEPT if _dual_intercept and remix else RouteRules.description(remix)
	_confirm_rift_rule.visible = remix
	if remix:
		_confirm_rift_rule.grab_focus()
		NetworkManager.warm_remix_pilot_scripts()

func _confirm_rift_preview() -> void:
	if _back_pending or _compatible_peer != 1 or not _confirm_rift_rule.visible:
		return
	_confirm_rift_rule.hide()
	_lbl_scan_hint.text = "等待房主开始"
	_lbl_join_status.text = (RouteRules.DUAL_INTERCEPT if _dual_intercept else RouteRules.REMIX) + " · 已确认"
	_btn_back.grab_focus()
	_rpc_confirm_rift_rule.rpc_id(1, _preview_revision)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_confirm_rift_rule(revision: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _compatible_peer or revision != _rule_revision or _rift_rule.selected != 1:
		return
	_btn_rift.disabled = false
	_lbl_host_status.text = "搭档已确认，可以开始"

@rpc("authority", "reliable", "call_local")
func _rpc_start_game(battle_size: Vector2i, rift_route := false, remix := false) -> void:
	if _back_pending or _launching:
		return
	if not NetworkManager.is_online() or _compatible_peer == 0:
		_show_version_error()
		return
	_stop_discovery_services()
	if battle_size != NetworkManager.LAN_BATTLE_SIZE:
		if NetworkManager.is_host:
			_show_host_failure("战场尺寸不兼容", "请将双方的游戏更新到同一版本，再重新创建。")
		else:
			NetworkManager.disconnect_network()
			_show_join_failure("战场尺寸不兼容", "请将双方的游戏更新到同一版本，再重新搜索。")
		return
	_launching = true
	game_start_requested.emit()
	GameState.rift_remix = rift_route and remix
	GameState.rift_dual_intercept = _dual_intercept and GameState.rift_remix
	get_tree().change_scene_to_file("res://scenes/rift_route_trial.tscn" if rift_route else "res://scenes/main.tscn")

func _on_host_list_updated(hosts: Array) -> void:
	if _mode != LobbyMode.JOIN or not _scan_active:
		return
	var first_listing := _host_buttons.is_empty()
	var listed := {}
	for entry: Dictionary in hosts:
		if not _room_matches_mode(entry):
			continue
		var ip := String(entry.get("ip", ""))
		var port := int(entry.get("port", 0))
		if not _is_valid_ipv4(ip) or port <= 0 or port > 65535:
			continue
		var key := "%s:%d" % [ip, port]
		listed[key] = true
		var name := String(entry.get("name", "")).replace("\n", " ").replace("\r", " ").strip_edges()
		if name.is_empty():
			name = "附近房间"
		if not _host_buttons.has(key):
			var button := EntryCard.new()
			button.detail = "双线截击 · 仅双人" if _dual_intercept else "双人联机"
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_on_host_button_pressed.bind(ip, port))
			_host_list.add_child(button)
			_host_buttons[key] = button
		_host_buttons[key].text = name
		_host_buttons[key].tooltip_text = name + "\n" + key
	for key: String in _host_buttons.keys():
		if not listed.has(key):
			_remove_host_button(key)
	_update_room_search()
	if first_listing and _room_scroll.visible and _retry_search.has_focus():
		_host_list.get_child(0).grab_focus()

func _update_room_search() -> void:
	_room_scroll.visible = not _host_buttons.is_empty()
	if _room_scroll.visible:
		_lbl_scan_hint.text = "找到 %d 个房间" % _host_buttons.size()
		_lbl_join_status.text = ""
	elif _search_deadline > 0:
		_lbl_scan_hint.text = "正在搜索附近房间"
		_lbl_join_status.text = "请确认搭档已创建房间。"
	else:
		_lbl_scan_hint.text = "暂无可用房间"
		_lbl_join_status.text = "请确认双方在同一网络、从同一玩法入口进入，再重新搜索。"

func _room_matches_mode(entry: Dictionary) -> bool:
	return (entry.get("name") == RouteRules.DUAL_INTERCEPT) == _dual_intercept

func _on_host_button_pressed(ip: String, port: int) -> void:
	if _back_pending or _mode != LobbyMode.JOIN or not _scan_active or _joining or NetworkManager.is_online():
		return
	_joining = true
	_room_scroll.hide()
	_retry_search.hide()
	_lbl_scan_hint.text = "正在连接房间"
	_lbl_join_status.text = "正在等待房主响应。"
	_btn_back.grab_focus()
	_deferred_join_host.call_deferred(ip, port, _join_generation)

func _deferred_join_host(ip: String, port: int, generation := -1) -> void:
	if _back_pending or _mode != LobbyMode.JOIN or multiplayer.multiplayer_peer is ENetMultiplayerPeer or (generation >= 0 and generation != _join_generation):
		return
	if not _is_valid_ipv4(ip) or port <= 0 or port > 65535:
		_show_join_failure("房间信息已失效", "请重新搜索搭档的房间。")
		return
	_joining = true
	_stop_discovery_services()
	var err := NetworkManager.join_host_with_mode(NetworkManager.TRANSPORT_HARMONY, ip, port)
	if err != OK:
		_on_connection_failed()

func _on_player_connected(peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	_retry_host.hide()
	_occupancy.text = "%d / 2" % (1 + NetworkManager.connected_peers.size())
	_btn_start.visible = not _dual_intercept
	_btn_rift.show()
	_btn_start.disabled = true
	_btn_rift.disabled = true
	_host_detail.hide()
	_begin_version_check(peer_id)

func _on_player_disconnected(_peer_id: int) -> void:
	if NetworkManager.is_host and NetworkManager.connected_peers.is_empty():
		_compatible_peer = 0
		_version_deadline = 0
		_reset_host_actions()
		_retry_host.hide()
		_occupancy.text = "1 / 2"
		_show_host_waiting(true)

func _show_host_waiting(left: bool) -> void:
	_lbl_host_status.text = "搭档已离开，等待重新加入" if left else "等待搭档加入"
	_host_detail.text = "请搭档从「试飞任务 → 裂隙航道 → 双线截击」进入。" if _dual_intercept else "请搭档在「双人联机」中点击「加入附近房间」。"
	_host_detail.show()

func _reset_host_actions() -> void:
	_btn_start.disabled = true
	_btn_rift.disabled = true
	_btn_start.hide()
	_btn_rift.hide()
	_rift_rule.hide()

func _on_connection_succeeded() -> void:
	if _back_pending or not NetworkManager.is_online() or NetworkManager.is_host:
		return
	_joining = true
	_room_scroll.hide()
	_retry_search.hide()
	_stop_discovery_services()
	_begin_version_check(1)

func _begin_version_check(peer_id: int) -> void:
	if _compatible_peer == peer_id:
		return
	_version_deadline = Time.get_ticks_msec() + VERSION_WAIT_MS
	if NetworkManager.is_host:
		_lbl_host_status.text = "正在检查联机版本"
	else:
		_lbl_scan_hint.text = "正在检查联机版本"
		_lbl_join_status.text = "已连接到房主。"
	var err := (multiplayer as SceneMultiplayer).send_bytes(_lobby_identity(), peer_id)
	if err != OK:
		_show_version_error()

func _lobby_identity() -> PackedByteArray:
	var identity := LAN_PROTOCOL + ":dual-intercept" if _dual_intercept else LAN_PROTOCOL
	return identity.to_utf8_buffer()

func _on_lobby_packet(peer_id: int, packet: PackedByteArray) -> void:
	if _back_pending or not NetworkManager.is_online():
		return
	if peer_id not in NetworkManager.connected_peers and (NetworkManager.is_host or peer_id != 1):
		return
	if packet != _lobby_identity():
		_show_version_error(packet == (LAN_PROTOCOL if _dual_intercept else LAN_PROTOCOL + ":dual-intercept").to_utf8_buffer())
		return
	_compatible_peer = peer_id
	_version_deadline = 0
	if NetworkManager.is_host:
		_btn_start.disabled = _dual_intercept
		_rift_rule.visible = not _dual_intercept
		_publish_rift_rule()
	else:
		_lbl_scan_hint.text = "等待房主开始"
		_lbl_join_status.text = "联机版本一致。"

func _show_version_error(wrong_room := false) -> void:
	_compatible_peer = 0
	_version_deadline = 0
	_btn_start.disabled = true
	_btn_rift.disabled = true
	_rift_rule.hide()
	_confirm_rift_rule.hide()
	var message := "请确认双方都从标题进入「双线截击」，并使用同一版本" if wrong_room and _dual_intercept else VERSION_ERROR
	if NetworkManager.is_host:
		_lbl_host_status.text = message
		_host_detail.text = "搭档可以返回并重新加入。"
		_host_detail.show()
		_retry_host.show()
	else:
		_show_join_failure("无法一起开局", message)

func _on_connection_failed() -> void:
	if not _back_pending and _mode == LobbyMode.JOIN and _joining:
		_show_join_failure("未能连接房间", "请确认房间仍然开放、双方在同一网络，再重新搜索。")

func _on_server_disconnected() -> void:
	if not _back_pending and _mode == LobbyMode.JOIN and _joining:
		_show_join_failure("与房主的连接已断开", "请等搭档重新创建房间，再重新搜索。")

func _show_join_failure(title: String, detail: String) -> void:
	_compatible_peer = 0
	_version_deadline = 0
	_preview_revision = -1
	_joining = false
	_stop_discovery_services()
	_confirm_rift_rule.hide()
	_room_scroll.hide()
	_retry_search.show()
	_lbl_scan_hint.text = title
	_lbl_join_status.text = detail
	_retry_search.grab_focus()

func _show_host_failure(title: String, detail: String) -> void:
	_stop_discovery_services()
	if NetworkManager.is_online():
		NetworkManager.disconnect_network()
	_reset_host_actions()
	_occupancy.text = "— / 2"
	_lbl_host_status.text = title
	_host_detail.text = detail
	_host_detail.show()
	_retry_host.show()
	_retry_host.grab_focus()

func _on_harmony_status_changed(message: String) -> void:
	if _back_pending:
		return
	var denied := message.contains("权限") or message.contains("SecurityException") or "permission denial" in message.to_lower()
	if _mode == LobbyMode.HOST and NetworkManager.is_online() and NetworkManager.connected_peers.is_empty():
		if denied or message.begins_with("发布失败") or message.begins_with("发布异常") or message.begins_with("发布房间异常") or message.contains("无法发布房间"):
			_show_host_failure("附近房间发布失败", "请允许附近设备访问并确认网络可用，再重新创建。")
	elif _mode == LobbyMode.JOIN and _scan_active:
		if denied or message.begins_with("扫描启动失败") or message.begins_with("扫描异常") or message.begins_with("扫描房间异常") or message.contains("无法扫描房间"):
			_show_join_failure("附近房间搜索失败", "请允许附近设备访问并确认网络可用，再重新搜索。")

func _remove_host_button(key: String) -> void:
	var button := _host_buttons[key]
	_host_buttons.erase(key)
	_host_list.remove_child(button)
	button.queue_free()

func _clear_host_list() -> void:
	for key: String in _host_buttons.keys():
		_remove_host_button(key)

func _stop_discovery_services() -> void:
	_scan_active = false
	_search_deadline = 0
	HarmonyBridge.stop_all()

func _is_valid_ipv4(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
		var value := int(part)
		if str(value) != part or value < 0 or value > 255:
			return false
	return true
