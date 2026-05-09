## Lobby — 联机大厅脚本 v2
## 完整联机流程：
##
## ┌──────────────┐    ┌──────────────────────────────────────────────┐
## │  Host 手机   │    │  Client 手机                                 │
## │  ① 点"我开热点" │    │  ① 点"我来加入"                             │
## │  ② 系统开热点  │    │  ② 手机连到 Host 的热点（系统 Wi-Fi 列表）  │
## │  ③ 游戏显示   │    │  ③ 游戏自动扫描，找到 Host 点一下连接        │
## │    密码 + SSID │    │                                              │
## │  ④ 等对方加入  │    │                                              │
## │  ⑤ 点"开始"   │    │                                              │
## └──────────────┘    └──────────────────────────────────────────────┘
##
## 技术要点：
##   - HotspotManager 生成随机密码并引导用户打开系统热点设置
##   - NetworkDiscovery 在后台持续广播/扫描，实现免 IP 连接
##   - 发现到 Host 后显示可点击的列表项，一键连接
extends Control

## ── 信号 ────────────────────────────────────────────────────────────
signal game_start_requested

## ── 界面模式 ─────────────────────────────────────────────────────────
enum LobbyMode { NONE, HOST, JOIN }
var _mode: LobbyMode = LobbyMode.NONE

## ── 节点引用（根据 tscn 节点路径对应） ─────────────────────────────
@onready var _panel_mode_select: VBoxContainer  = $VBox/PanelModeSelect
@onready var _btn_be_host: Button               = $VBox/PanelModeSelect/BtnBeHost
@onready var _btn_be_client: Button             = $VBox/PanelModeSelect/BtnBeClient

@onready var _panel_host: VBoxContainer         = $VBox/PanelHost
@onready var _lbl_ssid_hint: Label              = $VBox/PanelHost/LblSsidHint
@onready var _lbl_password: Label               = $VBox/PanelHost/LblPassword
@onready var _btn_open_hotspot: Button          = $VBox/PanelHost/BtnOpenHotspot
@onready var _btn_start: Button                 = $VBox/PanelHost/BtnStart
@onready var _lbl_host_status: Label            = $VBox/PanelHost/LblHostStatus

@onready var _panel_join: VBoxContainer         = $VBox/PanelJoin
@onready var _lbl_scan_hint: Label              = $VBox/PanelJoin/LblScanHint
@onready var _host_list: VBoxContainer          = $VBox/PanelJoin/HostList
@onready var _lbl_join_status: Label            = $VBox/PanelJoin/LblJoinStatus

@onready var _btn_back: Button                  = $VBox/BtnBack
@onready var _status_label: Label               = $VBox/StatusLabel

## 当前已生成密码
var _hotspot_password: String = ""
## 已添加到列表的主机条目 {key: Button}
var _host_buttons: Dictionary = {}


## ── 生命周期 ──────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_signals()
	_show_mode_select()


func _connect_signals() -> void:
	## 模式选择按钮
	_btn_be_host.pressed.connect(_on_host_mode_selected)
	_btn_be_client.pressed.connect(_on_join_mode_selected)
	_btn_back.pressed.connect(_on_back_pressed)

	## Host 面板按钮
	_btn_open_hotspot.pressed.connect(_on_open_hotspot_pressed)
	_btn_start.pressed.connect(_on_start_pressed)

	## NetworkManager 信号
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.status_changed.connect(_on_status_changed)

	## NetworkDiscovery 信号
	NetworkDiscovery.host_list_updated.connect(_on_host_list_updated)


## ── 界面切换 ──────────────────────────────────────────────────────────

func _show_mode_select() -> void:
	_panel_mode_select.visible = true
	_panel_host.visible = false
	_panel_join.visible = false
	_status_label.text = "选择你的角色"
	_mode = LobbyMode.NONE
	NetworkDiscovery.stop_all()


func _show_host_panel() -> void:
	_panel_mode_select.visible = false
	_panel_host.visible = true
	_panel_join.visible = false
	_btn_start.visible = false
	_btn_start.disabled = true

	## 生成密码
	_hotspot_password = HotspotManager.generate_password()
	var ssid: String = HotspotManager.get_default_ssid()

	_lbl_ssid_hint.text = "📶 热点名：%s" % ssid
	_lbl_password.text = "🔑 密码：%s" % _hotspot_password
	_lbl_host_status.text = "开热点后，对方搜索 Wi-Fi 连接即可"

	## 启动 ENet 服务器
	var err := NetworkManager.create_host()
	if err != OK:
		_lbl_host_status.text = "❌ 启动服务器失败：%s" % error_string(err)
		return

	## 启动广播（发现服务）
	NetworkDiscovery.start_broadcasting()

	_mode = LobbyMode.HOST
	_status_label.text = "等待对方加入…"


func _show_join_panel() -> void:
	_panel_mode_select.visible = false
	_panel_host.visible = false
	_panel_join.visible = true

	_lbl_scan_hint.text = "🔍 正在扫描局域网…"
	_lbl_join_status.text = "请先在手机 Wi-Fi 设置中连接对方热点"

	## 清空旧列表
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.queue_free()
	_host_buttons.clear()

	## 启动监听（自动发现）
	NetworkDiscovery.start_listening()

	_mode = LobbyMode.JOIN
	_status_label.text = "搜索房间中…"


## ── 按钮回调 ──────────────────────────────────────────────────────────

func _on_host_mode_selected() -> void:
	_show_host_panel()


func _on_join_mode_selected() -> void:
	_show_join_panel()


func _on_open_hotspot_pressed() -> void:
	## 打开系统热点设置页（Android Intent）
	if OS.has_feature("android"):
		# Godot 4 Android：通过 JavaClassWrapper 打开 Wi-Fi 热点设置
		var intent_settings := "android.settings.WIRELESS_SETTINGS"
		## 使用 Java 跨平台接口打开设置（无需第三方插件）
		var jni_singleton := Engine.get_singleton("GodotAndroid")
		if jni_singleton:
			jni_singleton.launch_intent(intent_settings)
		else:
			## 降级：打开通用设置
			OS.shell_open("intent:#Intent;action=android.settings.WIRELESS_SETTINGS;end")
	else:
		_lbl_host_status.text = "⚠️ 在真机上运行时可直接跳转热点设置"


func _on_start_pressed() -> void:
	if not NetworkManager.is_host:
		return
	NetworkDiscovery.stop_all()
	_rpc_start_game.rpc()


func _on_back_pressed() -> void:
	NetworkDiscovery.stop_all()
	NetworkManager.disconnect_network()
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")


## ── RPC：Host 广播开始 ───────────────────────────────────────────────
@rpc("authority", "reliable", "call_local")
func _rpc_start_game() -> void:
	NetworkDiscovery.stop_all()
	game_start_requested.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## ── 主机发现回调 ──────────────────────────────────────────────────────

func _on_host_list_updated(hosts: Array) -> void:
	if _mode != LobbyMode.JOIN:
		return

	## 添加新主机
	for entry: Dictionary in hosts:
		var key: String = "%s:%d" % [entry["ip"], entry["port"]]
		if not _host_buttons.has(key):
			var btn := Button.new()
			btn.text = "🎮  %s\n%s" % [entry["name"], key]
			btn.custom_minimum_size = Vector2(0, 72)
			btn.theme_override_font_sizes = {"font_size": 18}
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var ip: String = entry["ip"]
			var port: int = entry["port"]
			btn.pressed.connect(func(): _on_host_button_pressed(ip, port))
			_host_list.add_child(btn)
			_host_buttons[key] = btn

	if hosts.is_empty():
		_lbl_scan_hint.text = "🔍 扫描中，未找到房间…"
	else:
		_lbl_scan_hint.text = "✅ 找到 %d 个房间，点击加入" % hosts.size()


func _on_host_button_pressed(ip: String, port: int) -> void:
	_lbl_join_status.text = "正在连接 %s:%d …" % [ip, port]
	## 禁用所有主机按钮，防止重复点击
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.disabled = true
	NetworkManager.join_host(ip, port)


## ── NetworkManager 信号回调 ──────────────────────────────────────────

func _on_player_connected(peer_id: int) -> void:
	if NetworkManager.is_host:
		_btn_start.visible = true
		_btn_start.disabled = false
		_lbl_host_status.text = "✅ 玩家 %d 已加入！" % peer_id


func _on_player_disconnected(_peer_id: int) -> void:
	if NetworkManager.is_host:
		var count := NetworkManager.connected_peers.size()
		if count == 0:
			_btn_start.disabled = true
			_btn_start.visible = false
			_lbl_host_status.text = "玩家已离开，等待重新加入…"


func _on_connection_succeeded() -> void:
	NetworkDiscovery.stop_all()
	_lbl_join_status.text = "✅ 已连接，等待房主开始…"
	_status_label.text = "已连接"


func _on_connection_failed() -> void:
	_lbl_join_status.text = "❌ 连接失败，请重试"
	for key: String in _host_buttons:
		var btn: Button = _host_buttons[key]
		btn.disabled = false


func _on_server_disconnected() -> void:
	_lbl_join_status.text = "服务器断开，请返回重试"


func _on_status_changed(message: String) -> void:
	_status_label.text = message
