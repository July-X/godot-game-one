## NetworkManager — Autoload 单例
## 负责管理 ENet 多人连接的完整生命周期。
## 设计意图：服务器/客户端均通过本模块建立连接，上层场景只监听信号，
## 不直接操作 multiplayer.multiplayer_peer，保持解耦。
##
## 连接拓扑：Wi-Fi 热点 LAN（Host 开热点，Client 连热点后输入 IP）
## 无需互联网，局域网内延迟 < 10ms，适合移动端面对面对战。
extends Node
const LanRecovery = preload("res://scripts/lan_recovery.gd")

## 默认端口，可在项目设置中覆盖
const DEFAULT_PORT: int = 7777
const DEPARTURE_FLUSH_SECONDS := 0.25
## 最大同时连接客户端数量（合作模式最多 1 个 Client）
const MAX_CLIENTS: int = 1
## 大厅开局协议的逻辑像素，世界原点为左上角。
const LAN_BATTLE_SIZE := Vector2i(1280, 720)
const TRANSPORT_ENET := "enet"
const TRANSPORT_HARMONY := "harmony"

## ── 信号 ──────────────────────────────────────────────────
## 有新 peer 连接时触发（服务器端接收到客户端连接，或客户端收到服务器确认）
signal player_connected(peer_id: int)
## peer 断开时触发
signal player_disconnected(peer_id: int)
## 客户端与服务器断开时触发（仅 Client 端）
signal server_disconnected
## 连接成功（join 方向：Client 成功连到 Host）
signal connection_succeeded
## 连接失败（ENet 握手超时或拒绝）
signal connection_failed
## 通知 UI 层的状态消息
signal status_changed(message: String)

## ── 状态 ──────────────────────────────────────────────────
## 当前是否作为 Host（服务器）运行
var is_host: bool = false
## 已连接的 peer_id 列表（服务器端维护）
var connected_peers: Array[int] = []
## 当前传输模式（本阶段两种模式都使用 ENet 建立战斗链路，仅发现方式不同）
var transport_mode: String = TRANSPORT_ENET
## 当前是否处于联机会话（create_host/join_host 后置 true，disconnect 后置 false）
var _session_active: bool = false
var recovery: Node
var _address := ""
var _port := DEFAULT_PORT
var _quitting_after_lan := false
var _owns_quit_settings := false
var _auto_quit := true
var _go_back_quits := true


func _ready() -> void:
	recovery = LanRecovery.new()
	recovery.name = "LanRecovery"
	add_child(recovery)
	## 监听 Godot 多人底层信号
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST] and is_instance_valid(recovery):
		if recovery.is_reserved() and not _quitting_after_lan:
			_quitting_after_lan = true
			_leave_app_after_notification.call_deferred()

func _leave_app_after_notification() -> void:
	disconnect_network()
	await get_tree().create_timer(DEPARTURE_FLUSH_SECONDS + 0.05, true, false, true).timeout
	get_tree().quit()


## ── 公开 API ──────────────────────────────────────────────

## 作为 Host（服务器）启动，绑定本机所有网卡的 port 端口
## 返回 OK 表示成功，否则返回错误码
func create_host(port: int = DEFAULT_PORT, mode: String = TRANSPORT_ENET) -> Error:
	transport_mode = mode
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("[NetworkManager] 创建服务器失败: %s" % error_string(err))
		status_changed.emit("创建房间失败: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_port = port
	is_host = true
	_session_active = true
	connected_peers.clear()
	status_changed.emit("房间已创建，等待玩家加入…")
	print("[NetworkManager] Host 启动，端口 ", port)
	return OK


## 作为 Client 连接到指定 IP 的 Host
## address 为对方局域网 IP（如 192.168.43.1）
## 返回 OK 表示 ENet 握手已发起（结果通过信号返回）
func join_host(address: String, port: int = DEFAULT_PORT, mode: String = TRANSPORT_ENET) -> Error:
	transport_mode = mode
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[NetworkManager] 连接失败: %s" % error_string(err))
		status_changed.emit("连接失败: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_address = address
	_port = port
	is_host = false
	_session_active = true
	status_changed.emit("正在连接 %s:%d …" % [address, port])
	print("[NetworkManager] Client 正在连接 %s:%d" % [address, port])
	return OK


## 断开网络并清理状态（Host/Client 均可调用）
func disconnect_network() -> void:
	var departing := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var graceful: bool = recovery.notify_exit()
	recovery.clear()
	if _owns_quit_settings:
		get_tree().auto_accept_quit = _auto_quit
		get_tree().quit_on_go_back = _go_back_quits
		_owns_quit_settings = false
	multiplayer.multiplayer_peer = null
	if departing != null:
		if graceful:
			# ENet 的 close 在同一轮 poll 收到时会丢弃尚未派发的退出消息。
			get_tree().create_timer(DEPARTURE_FLUSH_SECONDS, true, false, true).timeout.connect(func(): departing.close())
		else:
			departing.close()
	is_host = false
	_session_active = false
	transport_mode = TRANSPORT_ENET
	connected_peers.clear()
	status_changed.emit("已断开")
	print("[NetworkManager] 网络已断开")


func bind_battle(node: Node) -> void:
	recovery.bind_battle(node, GameState.get_sync_round() if is_host else 0)
	if not _owns_quit_settings:
		_owns_quit_settings = true
		_auto_quit = get_tree().auto_accept_quit
		_go_back_quits = get_tree().quit_on_go_back
		get_tree().auto_accept_quit = false
		get_tree().quit_on_go_back = false

func local_player_id() -> int:
	if not is_host and is_instance_valid(recovery) and recovery.guest_slot > 0:
		return recovery.guest_slot
	return get_my_peer_id()

func slot_for_peer(peer_id: int) -> int:
	return recovery.slot_for_wire(peer_id)

func peer_for_slot(slot: int) -> int:
	return recovery.wire_for_slot(slot)

## RPC 输入只从当前已完成恢复的传输接收。
func gameplay_sender() -> int:
	return 0 if recovery.deadline > 0 else slot_for_peer(multiplayer.get_remote_sender_id())

func drop_lan_transport() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
	connected_peers.clear()
	recovery.on_transport_lost()

func _drop_lan_transport_if_current(failed_peer: MultiplayerPeer) -> void:
	if multiplayer.multiplayer_peer == failed_peer:
		drop_lan_transport()

func retry_lan_transport() -> void:
	if is_host and multiplayer.multiplayer_peer != null:
		return  # 监听仍有效，等待已知加入者重新握手。
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_port, MAX_CLIENTS) if is_host else peer.create_client(_address, _port)
	multiplayer.multiplayer_peer = peer if err == OK else null

func finish_lan_wait(message: String) -> void:
	var battle: Node = recovery.battle
	recovery.clear()
	if is_instance_valid(battle):
		battle._fallback_to_single_player(message)


## 判断当前是否处于联机状态（已建立 peer 连接）
func is_online() -> bool:
	if not _session_active:
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return false
	## 仅在“已连接”时视为在线，避免把 CONNECTING 误判为在线导致单机/输入链路错走联机分支。
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## 窗口可以随时变化。联机世界在整个会话内都用开局协议的尺寸。
func battle_size(world: CanvasItem) -> Vector2:
	return Vector2(LAN_BATTLE_SIZE) if _session_active else world.get_viewport_rect().size


## 获取本机 peer_id（未联机时返回 1）
func get_my_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func create_host_with_mode(mode: String, port: int = DEFAULT_PORT) -> Error:
	return create_host(port, mode)


func join_host_with_mode(mode: String, address: String, port: int = DEFAULT_PORT) -> Error:
	return join_host(address, port, mode)


## ── 私有信号处理 ──────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer 已连接: ", peer_id)
	if not connected_peers.has(peer_id):
		connected_peers.append(peer_id)
	if recovery.is_reserved() and recovery.deadline > 0:
		recovery.on_wire_ready(peer_id)
		return
	player_connected.emit(peer_id)
	if is_host:
		status_changed.emit("玩家 %d 已加入！" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer 已断开: ", peer_id)
	connected_peers.erase(peer_id)
	if recovery.is_reserved():
		if (is_host and peer_id == recovery.guest_wire) or (not is_host and peer_id == 1):
			recovery.on_transport_lost()
		return
	player_disconnected.emit(peer_id)
	if is_host:
		status_changed.emit("玩家 %d 已离开" % peer_id)


func _on_connected_to_server() -> void:
	print("[NetworkManager] 成功连接到服务器，我的 peer_id = ", multiplayer.get_unique_id())
	status_changed.emit("已连接，等待开始…")
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	if recovery.is_reserved():
		_drop_lan_transport_if_current.call_deferred(multiplayer.multiplayer_peer)
		return
	push_warning("[NetworkManager] 连接服务器失败")
	status_changed.emit("连接失败，请检查 IP 地址")
	multiplayer.multiplayer_peer = null
	_session_active = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if recovery.is_reserved():
		_drop_lan_transport_if_current.call_deferred(multiplayer.multiplayer_peer)
		return
	push_warning("[NetworkManager] 服务器已断开")
	status_changed.emit("连接已断开")
	multiplayer.multiplayer_peer = null
	is_host = false
	_session_active = false
	connected_peers.clear()
	server_disconnected.emit()
