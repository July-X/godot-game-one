## HotspotManager — Autoload 单例
## 管理 Wi-Fi 热点的密码生成和状态提示。
## 注意：Android 热点需用户在系统设置中手动开启，本模块仅提供密码和引导。
## 若未来需要程序化控制热点，可在此基础上通过 GDExtension + JNI 调用
## WifiManager.startLocalOnlyHotspot()（需要 ACCESS_FINE_LOCATION 权限）。
extends Node

## 热点的默认 SSID 前缀（游戏名 + 随机后缀）
const HOTSPOT_SSID_PREFIX := "SpaceBattle_"
## 热点密码长度
const PASSWORD_LENGTH := 6

## ── 信号 ──────────────────────────────────────────────────
## 热点密码已生成
signal password_ready(password: String)

## ── 状态 ──────────────────────────────────────────────────
var _current_password: String = ""

## 公开 API ──────────────────────────────────────────────

## 生成一个新的随机热点密码（数字+字母，HOTSPOT_PASSWORD_LENGTH 位）
func generate_password() -> String:
	var chars := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
	## 排除易混淆字符：0/O、1/I/L
	var pwd := ""
	for i in PASSWORD_LENGTH:
		pwd += chars[randi() % chars.length()]
	_current_password = pwd
	password_ready.emit(_current_password)
	print("[HotspotManager] 热点密码已生成: %s" % _current_password)
	return _current_password


## 获取当前密码（未生成时返回空字符串）
func get_password() -> String:
	return _current_password


## 返回热点 SSID 建议（实际由系统设置控制，这里返回默认值）
func get_default_ssid() -> String:
	return HOTSPOT_SSID_PREFIX + "Game"
