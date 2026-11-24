## NetworkDiscovery — Autoload 单例
## 基于 UDP 广播的局域网主机发现服务。
##
## Host 端：启动后每 1.5 秒向局域网广播一次本机信息（设备名 + 游戏端口）。
##        广播地址使用 255.255.255.255（受限广播），端口 DISCOVERY_PORT。
## Client 端：启动后持续监听 DISCOVERY_PORT，同时每 2 秒发送一次探测包。
##           收到 Host 回复后，将其加入可用主机列表。
##
## 发现服务与游戏连接端口（7777）完全独立，不会互相干扰。
extends Node

## 发现服务端口（UDP）
const DISCOVERY_PORT := 7778
## 广播地址（受限广播，自动投递给同一 LAN 的所有设备）
const DISCOVERY_ADDR := "255.255.255.255"
## 探测包内容（JSON 编码）
const DISCOVERY_PACKET := "SBHELLO"
## Host 响应包内容
const DISCOVERY_RESPONSE := "SBHOST"

## ── 信号 ──────────────────────────────────────────────────
## 发现新主机时触发（Client 端）
signal host_found(host_name: String, host_ip: String, host_port: int)
## 主机列表更新（包含现有主机的最新心跳）
signal host_list_updated(hosts: Array)

## ── 状态 ──────────────────────────────────────────────────
var _is_hosting: bool = false
var _is_listening: bool = false

var _udp_socket: PacketPeerUDP
var _listen_timer: Timer
var _heartbeat_timer: Timer

## 当前广播的游戏端口
var _game_port: int = 7777

## 已发现的主机缓存: { "ip:port": { name, ip, port, last_seen } }
var _discovered_hosts: Dictionary = {}


## ── Host 端 API ────────────────────────────────────────────

## 启动广播：作为 Host 每 1.5s 广播一次本机存在
func start_broadcasting(game_port: int = 7777) -> void:
	if _is_hosting:
		return
	_is_hosting = true

	_udp_socket = PacketPeerUDP.new()
	var result := _udp_socket.bind(DISCOVERY_PORT)
	if result != OK:
		push_error("[NetworkDiscovery] 绑定广播端口失败: %s" % error_string(result))
		return
	_udp_socket.set_broadcast_enabled(true)

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 1.5
	_heartbeat_timer.timeout.connect(_on_broadcast_timer)
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()

	# 立即发送一次
	_broadcast_presence(game_port)
	_game_port = game_port
	print("[NetworkDiscovery] 广播服务已启动，端口 %d" % DISCOVERY_PORT)


func _broadcast_presence(game_port: int) -> void:
	if _udp_socket == null or not _is_hosting:
		return
	var device_name := OS.get_model_name()
	if device_name == "" or device_name == "Godot":
		device_name = "太空战机"
	# 格式：SBHOST|name|port
	var msg := "%s|%s|%d" % [DISCOVERY_RESPONSE, device_name, game_port]
	_udp_socket.set_dest_address(DISCOVERY_ADDR, DISCOVERY_PORT)
	var packed := msg.to_utf8_buffer()
	_udp_socket.put_packet(packed)


## ── Client 端 API ─────────────────────────────────────────

## 启动监听：接收 Host 广播并自动发现服务器
func start_listening() -> void:
	if _is_listening:
		return
	_is_listening = true
	_discovered_hosts.clear()

	_udp_socket = PacketPeerUDP.new()
	var result := _udp_socket.bind(DISCOVERY_PORT)
	if result != OK:
		push_error("[NetworkDiscovery] 绑定监听端口失败: %s" % error_string(result))
		_is_listening = false
		return
	_udp_socket.set_broadcast_enabled(true)

	# 每 2 秒发送一次探测请求
	_listen_timer = Timer.new()
	_listen_timer.wait_time = 2.0
	_listen_timer.timeout.connect(_on_probe_timer)
	add_child(_listen_timer)
	_listen_timer.start()

	print("[NetworkDiscovery] 监听服务已启动，端口 %d" % DISCOVERY_PORT)


## 返回当前已发现的主机列表
func get_discovered_hosts() -> Array:
	return _discovered_hosts.values()


## ── 关闭 ──────────────────────────────────────────────────

func stop_all() -> void:
	_is_hosting = false
	_is_listening = false
	if _udp_socket != null:
		_udp_socket.close()
		_udp_socket = null
	if _heartbeat_timer:
		_heartbeat_timer.stop()
		_heartbeat_timer.queue_free()
		_heartbeat_timer = null
	if _listen_timer:
		_listen_timer.stop()
		_listen_timer.queue_free()
		_listen_timer = null
	_discovered_hosts.clear()
	print("[NetworkDiscovery] 已停止所有服务")


## ── 私有 ──────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _udp_socket == null:
		return
	if _udp_socket.get_available_packet_count() > 0:
		var ip: String = _udp_socket.get_packet_ip()
		var port: int = _udp_socket.get_packet_port()
		var data: PackedByteArray = _udp_socket.get_packet()
		var msg: String = data.get_string_from_utf8()
		_handle_packet(msg, ip, port)


func _handle_packet(msg: String, from_ip: String, _from_port: int) -> void:
	if _is_listening and msg.begins_with(DISCOVERY_RESPONSE):
		# Host 回复包：SBHOST|name|port
		var parts := msg.split("|")
		if parts.size() >= 3:
			var name: String = parts[1]
			var port: int = parts[2].to_int()
			var key: String = "%s:%d" % [from_ip, port]
			_discovered_hosts[key] = {
				"name": name,
				"ip": from_ip,
				"port": port,
				"last_seen": Time.get_ticks_msec()
			}
			host_found.emit(name, from_ip, port)
			host_list_updated.emit(get_discovered_hosts())
			print("[NetworkDiscovery] 发现主机: %s @ %s:%d" % [name, from_ip, port])


func _on_broadcast_timer() -> void:
	_broadcast_presence(_game_port)


func _on_probe_timer() -> void:
	if _udp_socket == null:
		return
	# 发送探测包
	_udp_socket.set_dest_address(DISCOVERY_ADDR, DISCOVERY_PORT)
	_udp_socket.put_packet(DISCOVERY_PACKET.to_utf8_buffer())
	# 清理超时主机（超过 6 秒无心跳视为离线）
	var now := Time.get_ticks_msec()
	var stale_keys: Array = []
	for k: String in _discovered_hosts:
		var entry: Dictionary = _discovered_hosts[k]
		if now - entry["last_seen"] > 6000:
			stale_keys.append(k)
	for k in stale_keys:
		_discovered_hosts.erase(k)
		host_list_updated.emit(get_discovered_hosts())
