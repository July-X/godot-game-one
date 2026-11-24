## HarmonyBridge — Autoload 单例
## 作用：对接鸿蒙“附近发现/万物互联”原生插件，给 Godot 大厅提供统一发现接口。
##
## 迁移阶段说明：
## - 当前仅实现桥接骨架，不直接替换 ENet 战斗同步链路。
## - 插件可用时负责“发现主机/拿到连接参数”；实际游戏通信仍由 NetworkManager(ENet) 建立。
## - 插件不可用时自动回退到现有热点+UDP 发现流程。
extends Node

const CANDIDATE_SINGLETONS := [
	"HarmonyNearbyGame",
	"HarmonyBridge",
	"HarmonyInterop",
]

signal availability_changed(available: bool, singleton_name: String)
signal status_changed(message: String)
signal host_list_updated(hosts: Array)

const STATUS_ROOM_FOUND_PREFIX := "发现房间："
const STATUS_ROOM_LOST_PREFIX := "房间离线："

var _plugin: Object = null
var _plugin_name: String = ""
var _available: bool = false
var _discovered_hosts: Dictionary = {}
var _is_hosting: bool = false
var _is_scanning: bool = false
var _allow_enet_fallback_backend: bool = true
var _fallback_using_network_discovery: bool = false
var _last_status_message: String = ""


func _ready() -> void:
	NetworkDiscovery.host_list_updated.connect(_on_fallback_host_list_updated)
	refresh_plugin_binding()


func refresh_plugin_binding() -> bool:
	_detach_plugin_signals()
	_plugin = null
	_plugin_name = ""
	_available = false
	for singleton_name in CANDIDATE_SINGLETONS:
		if Engine.has_singleton(singleton_name):
			_plugin = Engine.get_singleton(singleton_name)
			_plugin_name = singleton_name
			_available = _plugin != null
			break
	availability_changed.emit(_available, _plugin_name)
	if _available:
		_attach_plugin_signals()
		_emit_status("已检测到鸿蒙互联插件：%s" % _plugin_name)
		_emit_plugin_method_probe()
	else:
		_emit_status("未检测到鸿蒙互联插件，将使用 ENet 调试后端")
	return _available


func is_available() -> bool:
	return _available


func start_host_advertise(room_name: String, game_port: int) -> Error:
	_discovered_hosts.clear()
	if not _available:
		if not _can_use_fallback_backend():
			return ERR_UNAVAILABLE
		_fallback_using_network_discovery = true
		_is_hosting = true
		_is_scanning = false
		_emit_status("鸿蒙插件不可用，启用 ENet 调试发布后端")
		NetworkDiscovery.start_broadcasting(game_port)
		return OK
	_is_hosting = true
	_is_scanning = false
	_fallback_using_network_discovery = false
	_emit_status("鸿蒙互联：发布房间中…")

	if _has_plugin_method("publishNearbyGame"):
		_plugin.call("publishNearbyGame", room_name, game_port)
		return OK
	if _has_plugin_method("publish_nearby_game"):
		_plugin.call("publish_nearby_game", room_name, game_port)
		return OK
	if _has_plugin_method("startHostAdvertise"):
		_plugin.call("startHostAdvertise", room_name, game_port)
		return OK
	if _has_plugin_method("start_host_advertise"):
		_plugin.call("start_host_advertise", room_name, game_port)
		return OK

	if _can_use_fallback_backend():
		_fallback_using_network_discovery = true
		_emit_status("鸿蒙插件缺少发布方法，启用 ENet 调试发布后端")
		NetworkDiscovery.start_broadcasting(game_port)
		return OK
	_emit_status("鸿蒙插件缺少发布方法")
	return ERR_METHOD_NOT_FOUND


func start_scan() -> Error:
	_discovered_hosts.clear()
	if not _available:
		if not _can_use_fallback_backend():
			return ERR_UNAVAILABLE
		_fallback_using_network_discovery = true
		_is_scanning = true
		_is_hosting = false
		_emit_status("鸿蒙插件不可用，启用 ENet 调试扫描后端")
		NetworkDiscovery.start_listening()
		return OK
	_is_scanning = true
	_is_hosting = false
	_fallback_using_network_discovery = false
	_emit_status("鸿蒙互联：搜索附近房间中…")

	if _has_plugin_method("findNearbyGame"):
		_plugin.call("findNearbyGame")
		return OK
	if _has_plugin_method("find_nearby_game"):
		_plugin.call("find_nearby_game")
		return OK
	if _has_plugin_method("startScan"):
		_plugin.call("startScan")
		return OK
	if _has_plugin_method("start_scan"):
		_plugin.call("start_scan")
		return OK

	if _can_use_fallback_backend():
		_fallback_using_network_discovery = true
		_emit_status("鸿蒙插件缺少搜索方法，启用 ENet 调试扫描后端")
		NetworkDiscovery.start_listening()
		return OK
	_emit_status("鸿蒙插件缺少搜索方法")
	return ERR_METHOD_NOT_FOUND


func stop_all() -> void:
	_is_hosting = false
	_is_scanning = false
	_discovered_hosts.clear()
	_fallback_using_network_discovery = false
	NetworkDiscovery.stop_all()
	if _available and _plugin:
		if _has_plugin_method("destroyNearbyGame"):
			_plugin.call("destroyNearbyGame")
		elif _has_plugin_method("stopAll"):
			_plugin.call("stopAll")
		elif _has_plugin_method("stop_all"):
			_plugin.call("stop_all")


func get_discovered_hosts() -> Array:
	return _discovered_hosts.values()


## 原生插件可回调本方法上报发现结果
func report_discovered_host(host_name: String, host_ip: String, host_port: int) -> void:
	if host_ip.is_empty() or host_port <= 0:
		return
	var key := "%s:%d" % [host_ip, host_port]
	_discovered_hosts[key] = {
		"name": host_name if not host_name.is_empty() else "HarmonyHost",
		"ip": host_ip,
		"port": host_port,
		"last_seen": Time.get_ticks_msec(),
		"source": "harmony",
	}
	host_list_updated.emit(get_discovered_hosts())


## 原生插件可回调本方法上报状态消息
func report_status(message: String) -> void:
	if message.is_empty():
		return
	_emit_status(message)
	_sync_host_cache_from_status(message)


func get_debug_snapshot() -> Dictionary:
	var hosts := get_discovered_hosts()
	return {
		"plugin_available": _available,
		"plugin_name": _plugin_name if not _plugin_name.is_empty() else "none",
		"is_hosting": _is_hosting,
		"is_scanning": _is_scanning,
		"fallback_backend": _fallback_using_network_discovery,
		"discovered_count": hosts.size(),
		"last_status": _last_status_message,
	}


func _attach_plugin_signals() -> void:
	if _plugin == null:
		return
	var host_cb := Callable(self, "_on_plugin_host_discovered")
	var status_cb := Callable(self, "_on_plugin_status")
	if _plugin.has_signal("host_discovered") and not _plugin.is_connected("host_discovered", host_cb):
		_plugin.connect("host_discovered", host_cb)
	if _plugin.has_signal("status") and not _plugin.is_connected("status", status_cb):
		_plugin.connect("status", status_cb)


func _detach_plugin_signals() -> void:
	if _plugin == null:
		return
	var host_cb := Callable(self, "_on_plugin_host_discovered")
	var status_cb := Callable(self, "_on_plugin_status")
	if _plugin.has_signal("host_discovered") and _plugin.is_connected("host_discovered", host_cb):
		_plugin.disconnect("host_discovered", host_cb)
	if _plugin.has_signal("status") and _plugin.is_connected("status", status_cb):
		_plugin.disconnect("status", status_cb)


func _on_plugin_host_discovered(host_name: String, host_ip: String, host_port: int) -> void:
	report_discovered_host(host_name, host_ip, host_port)


func _on_plugin_status(message: String) -> void:
	report_status(message)


func _on_fallback_host_list_updated(hosts: Array) -> void:
	if not _fallback_using_network_discovery:
		return
	_discovered_hosts.clear()
	for entry: Dictionary in hosts:
		var ip := String(entry.get("ip", ""))
		var port := int(entry.get("port", 0))
		if ip.is_empty() or port <= 0:
			continue
		var key := "%s:%d" % [ip, port]
		_discovered_hosts[key] = {
			"name": String(entry.get("name", "ENetHost")),
			"ip": ip,
			"port": port,
			"last_seen": entry.get("last_seen", Time.get_ticks_msec()),
			"source": "enet_fallback",
		}
	host_list_updated.emit(get_discovered_hosts())


func _can_use_fallback_backend() -> bool:
	if not _allow_enet_fallback_backend:
		return false
	return OS.has_feature("editor") or (not OS.has_feature("android"))


func _has_plugin_method(method_name: String) -> bool:
	if _plugin == null:
		return false
	## Android JNISingleton 优先走 has_java_method，has_method 在部分版本会误报 false。
	if _plugin.has_method("has_java_method"):
		var ok: Variant = _plugin.call("has_java_method", method_name)
		if ok is bool and ok:
			return true
	return _plugin.has_method(method_name)


func _emit_plugin_method_probe() -> void:
	var methods := [
		"publishNearbyGame",
		"startHostAdvertise",
		"findNearbyGame",
		"startScan",
		"destroyNearbyGame",
		"stopAll",
	]
	var status_parts: Array[String] = []
	for m in methods:
		status_parts.append("%s=%s" % [m, "Y" if _has_plugin_method(m) else "N"])
	_emit_status("插件方法探测: %s" % ", ".join(status_parts))


func _emit_status(message: String) -> void:
	_last_status_message = message
	status_changed.emit(message)


func _sync_host_cache_from_status(message: String) -> void:
	## 某些设备上插件状态信号先到、host_discovered 回调偶发丢失；
	## 这里用状态文案兜底同步主机缓存，保证大厅列表稳定。
	if message.begins_with(STATUS_ROOM_FOUND_PREFIX):
		var payload := message.trim_prefix(STATUS_ROOM_FOUND_PREFIX).strip_edges()
		var at_index := payload.rfind(" @ ")
		if at_index <= 0:
			return
		var room_name := payload.substr(0, at_index).strip_edges()
		var endpoint := payload.substr(at_index + 3).strip_edges()
		var sep := endpoint.rfind(":")
		if sep <= 0:
			return
		var ip := endpoint.substr(0, sep).strip_edges()
		var port_text := endpoint.substr(sep + 1).strip_edges()
		if ip.is_empty() or not port_text.is_valid_int():
			return
		var port := int(port_text)
		if port <= 0:
			return
		report_discovered_host(room_name, ip, port)
		return

	if message.begins_with(STATUS_ROOM_LOST_PREFIX):
		var room_name := message.trim_prefix(STATUS_ROOM_LOST_PREFIX).strip_edges()
		if room_name.is_empty():
			return
		var removed := false
		for key in _discovered_hosts.keys():
			var entry: Dictionary = _discovered_hosts[key]
			if String(entry.get("name", "")) == room_name:
				_discovered_hosts.erase(key)
				removed = true
		if removed:
			host_list_updated.emit(get_discovered_hosts())
