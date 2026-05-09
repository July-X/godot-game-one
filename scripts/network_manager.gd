## NetworkManager — Autoload 单例
## 负责管理 ENet 多人连接的完整生命周期。
## 设计意图：服务器/客户端均通过本模块建立连接，上层场景只监听信号，
## 不直接操作 multiplayer.multiplayer_peer，保持解耦。
##
## 连接拓扑：Wi-Fi 热点 LAN（Host 开热点，Client 连热点后输入 IP）
## 无需互联网，局域网内延迟 < 10ms，适合移动端面对面对战。
extends Node

## 默认端口，可在项目设置中覆盖
const DEFAULT_PORT: int = 7777
## 最大同时连接客户端数量（合作模式最多 1 个 Client）
const MAX_CLIENTS: int = 1

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


func _ready() -> void:
	## 监听 Godot 多人底层信号
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## ── 公开 API ──────────────────────────────────────────────

## 作为 Host（服务器）启动，绑定本机所有网卡的 port 端口
## 返回 OK 表示成功，否则返回错误码
func create_host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("[NetworkManager] 创建服务器失败: %s" % error_string(err))
		status_changed.emit("创建房间失败: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	connected_peers.clear()
	status_changed.emit("房间已创建，等待玩家加入…")
	print("[NetworkManager] Host 启动，端口 ", port)
	return OK


## 作为 Client 连接到指定 IP 的 Host
## address 为对方局域网 IP（如 192.168.43.1）
## 返回 OK 表示 ENet 握手已发起（结果通过信号返回）
func join_host(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[NetworkManager] 连接失败: %s" % error_string(err))
		status_changed.emit("连接失败: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	status_changed.emit("正在连接 %s:%d …" % [address, port])
	print("[NetworkManager] Client 正在连接 %s:%d" % [address, port])
	return OK


## 断开网络并清理状态（Host/Client 均可调用）
func disconnect_network() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	status_changed.emit("已断开")
	print("[NetworkManager] 网络已断开")


## 判断当前是否处于联机状态（已建立 peer 连接）
func is_online() -> bool:
	return multiplayer.multiplayer_peer != null


## 获取本机 peer_id（未联机时返回 1）
func get_my_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


## ── 私有信号处理 ──────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer 已连接: ", peer_id)
	if not connected_peers.has(peer_id):
		connected_peers.append(peer_id)
	player_connected.emit(peer_id)
	if is_host:
		status_changed.emit("玩家 %d 已加入！" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer 已断开: ", peer_id)
	connected_peers.erase(peer_id)
	player_disconnected.emit(peer_id)
	if is_host:
		status_changed.emit("玩家 %d 已离开" % peer_id)


func _on_connected_to_server() -> void:
	print("[NetworkManager] 成功连接到服务器，我的 peer_id = ", multiplayer.get_unique_id())
	status_changed.emit("已连接，等待开始…")
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	push_warning("[NetworkManager] 连接服务器失败")
	status_changed.emit("连接失败，请检查 IP 地址")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	push_warning("[NetworkManager] 服务器已断开")
	status_changed.emit("连接已断开")
	multiplayer.multiplayer_peer = null
	is_host = false
	connected_peers.clear()
	server_disconnected.emit()
