package com.godot.game.harmony

import android.content.Context
import android.os.Build
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.net.Inet4Address
import java.net.InetAddress

class HarmonyNearbyGamePlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "HarmonyNearbyGame"
		private const val SERVICE_TYPE = "_spacebullet._tcp"
		private val STATUS_SIGNAL = SignalInfo("status", String::class.java)
		private val HOST_DISCOVERED_SIGNAL = SignalInfo(
			"host_discovered",
			String::class.java,
			String::class.java,
			Int::class.java
		)
	}

	private val nsdManager: NsdManager? by lazy {
		activity?.getSystemService(Context.NSD_SERVICE) as? NsdManager
	}

	private var registrationListener: NsdManager.RegistrationListener? = null
	private var discoveryListener: NsdManager.DiscoveryListener? = null
	private var resolveListener: NsdManager.ResolveListener? = null
	private var multicastLock: WifiManager.MulticastLock? = null
	private var isResolving: Boolean = false

	override fun getPluginName(): String = "HarmonyNearbyGame"

	override fun getPluginSignals(): Set<SignalInfo> = setOf(
		STATUS_SIGNAL,
		HOST_DISCOVERED_SIGNAL
	)

	@UsedByGodot
	fun publishNearbyGame(roomName: String, gamePort: Int) {
		try {
			startHostAdvertise(roomName, gamePort)
		} catch (t: Throwable) {
			Log.e(TAG, "publishNearbyGame fatal", t)
			emitStatus("发布房间异常：${t.javaClass.simpleName}")
		}
	}

	@UsedByGodot
	fun startHostAdvertise(roomName: String, gamePort: Int) {
		try {
		val manager = nsdManager
		if (manager == null) {
			emitStatus("NSD 不可用，无法发布房间")
			return
		}
		stopRegistration()
		val advertisedName = buildAdvertisedRoomName(roomName)
		val info = NsdServiceInfo().apply {
			serviceName = advertisedName
			serviceType = SERVICE_TYPE
			port = gamePort
		}
		registrationListener = object : NsdManager.RegistrationListener {
			override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
				val publishedName = safeServiceName(serviceInfo.serviceName, advertisedName)
				emitStatus("房间已发布：$publishedName")
			}

			override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
				emitStatus("发布失败，错误码=$errorCode")
			}

			override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
				emitStatus("房间已取消发布")
			}

			override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
				emitStatus("取消发布失败，错误码=$errorCode")
			}
		}
		try {
			manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, registrationListener)
		} catch (e: Exception) {
			Log.e(TAG, "registerService failed", e)
			emitStatus("发布异常：${e.message}")
		}
		} catch (t: Throwable) {
			Log.e(TAG, "startHostAdvertise fatal", t)
			emitStatus("发布房间异常：${t.javaClass.simpleName}")
		}
	}

	@UsedByGodot
	fun findNearbyGame() {
		try {
			startScan()
		} catch (t: Throwable) {
			Log.e(TAG, "findNearbyGame fatal", t)
			emitStatus("扫描房间异常：${t.javaClass.simpleName}")
		}
	}

	@UsedByGodot
	fun startScan() {
		try {
		val manager = nsdManager
		if (manager == null) {
			emitStatus("NSD 不可用，无法扫描房间")
			return
		}
		stopDiscovery()
		stopResolve()

		acquireMulticastLock()
		resolveListener = object : NsdManager.ResolveListener {
			override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
				Log.w(TAG, "resolve failed: $errorCode ${serviceInfo.serviceName}")
				isResolving = false
				emitStatus("解析失败：${safeServiceName(serviceInfo.serviceName, "UnknownRoom")}($errorCode)")
			}

			override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
				try {
					val host: InetAddress? = serviceInfo.host
					val ip = extractPreferredIp(host)
					val port = serviceInfo.port
					val roomName = safeServiceName(serviceInfo.serviceName, "HarmonyHost")
					if (ip.isBlank() || port <= 0) {
						emitStatus("解析到无效房间：$roomName（仅支持 IPv4）")
						return
					}
					emitHostDiscovered(roomName, ip, port)
					emitStatus("发现房间：$roomName @ $ip:$port")
				} catch (e: Exception) {
					Log.e(TAG, "onServiceResolved crash-guard", e)
					emitStatus("解析房间异常：${e.message}")
				} finally {
					isResolving = false
				}
			}
		}

		discoveryListener = object : NsdManager.DiscoveryListener {
			override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
				emitStatus("扫描启动失败，错误码=$errorCode")
				stopDiscovery()
			}

			override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
				emitStatus("停止扫描失败，错误码=$errorCode")
				stopDiscovery()
			}

			override fun onDiscoveryStarted(serviceType: String) {
				emitStatus("正在扫描附近房间… type=$serviceType")
			}

			override fun onDiscoveryStopped(serviceType: String) {
				emitStatus("已停止扫描")
			}

			override fun onServiceFound(serviceInfo: NsdServiceInfo) {
				try {
					val resolver = resolveListener
					if (resolver == null) {
						return
					}
					if (!isTargetServiceType(serviceInfo.serviceType)) {
						Log.d(TAG, "ignore service: ${serviceInfo.serviceName}, type=${serviceInfo.serviceType}")
						return
					}
					if (isResolving) {
						Log.d(TAG, "skip resolve while busy: ${serviceInfo.serviceName}")
						return
					}
					val roomName = safeServiceName(serviceInfo.serviceName, "UnknownRoom")
					emitStatus("发现候选房间：$roomName")
					isResolving = true
					manager.resolveService(serviceInfo, resolver)
				} catch (e: Exception) {
					isResolving = false
					Log.w(TAG, "resolveService exception", e)
					emitStatus("解析候选房间异常：${e.javaClass.simpleName}: ${e.message}")
				} catch (t: Throwable) {
					isResolving = false
					Log.e(TAG, "resolveService fatal", t)
					emitStatus("解析候选房间致命异常：${t.javaClass.simpleName}")
				}
			}

			override fun onServiceLost(serviceInfo: NsdServiceInfo) {
				emitStatus("房间离线：${safeServiceName(serviceInfo.serviceName, "UnknownRoom")}")
			}
		}

		try {
			manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
		} catch (e: Exception) {
			Log.e(TAG, "discoverServices failed", e)
			emitStatus("扫描异常：${e.message}")
		}
		} catch (t: Throwable) {
			Log.e(TAG, "startScan fatal", t)
			emitStatus("扫描房间异常：${t.javaClass.simpleName}")
		}
	}

	@UsedByGodot
	fun destroyNearbyGame() {
		try {
			stopAll()
		} catch (t: Throwable) {
			Log.e(TAG, "destroyNearbyGame fatal", t)
		}
	}

	@UsedByGodot
	fun stopAll() {
		try {
			stopDiscovery()
			stopRegistration()
			stopResolve()
			releaseMulticastLock()
			emitStatus("已停止互联服务")
		} catch (t: Throwable) {
			Log.e(TAG, "stopAll fatal", t)
		}
	}

	private fun stopRegistration() {
		val manager = nsdManager ?: return
		val listener = registrationListener ?: return
		try {
			manager.unregisterService(listener)
		} catch (_: Exception) {
		}
		registrationListener = null
	}

	private fun stopDiscovery() {
		val manager = nsdManager ?: return
		val listener = discoveryListener ?: return
		try {
			manager.stopServiceDiscovery(listener)
		} catch (_: Exception) {
		}
		discoveryListener = null
		releaseMulticastLock()
	}

	private fun stopResolve() {
		resolveListener = null
		isResolving = false
	}

	private fun emitStatus(message: String) {
		emitSignalSafely(STATUS_SIGNAL.name, message)
	}

	private fun emitHostDiscovered(name: String, ip: String, port: Int) {
		emitSignalSafely(HOST_DISCOVERED_SIGNAL.name, name, ip, port)
	}

	private fun emitSignalSafely(signalName: String, vararg args: Any) {
		try {
			runOnRenderThread {
				try {
					emitSignal(signalName, *args)
				} catch (t: Throwable) {
					Log.e(TAG, "emitSignal failed in render thread: $signalName", t)
				}
			}
		} catch (t: Throwable) {
			Log.e(TAG, "runOnRenderThread failed for signal: $signalName", t)
		}
	}

	private fun normalizeServiceType(raw: String?): String {
		val base = raw
			?.substringBefore('&')
			?.trim()
			?.lowercase()
			?.trimEnd('.')
			.orEmpty()
		return base
			.replace("_tcp", "._tcp")
			.replace("_udp", "._udp")
	}

	private fun isTargetServiceType(raw: String?): Boolean {
		return normalizeServiceType(raw) == normalizeServiceType(SERVICE_TYPE)
	}

	private fun acquireMulticastLock() {
		val wifiManager = activity?.applicationContext?.getSystemService(Context.WIFI_SERVICE) as? WifiManager
		if (wifiManager == null) {
			emitStatus("Wi-Fi 管理器不可用，可能影响房间发现")
			return
		}
		if (multicastLock == null) {
			multicastLock = wifiManager.createMulticastLock("spacebullet_nsd_lock").apply {
				setReferenceCounted(true)
			}
		}
		try {
			if (multicastLock?.isHeld != true) {
				multicastLock?.acquire()
			}
		} catch (e: Exception) {
			Log.w(TAG, "acquireMulticastLock failed", e)
			emitStatus("获取组播锁失败：${e.message}")
		}
	}

	private fun releaseMulticastLock() {
		try {
			if (multicastLock?.isHeld == true) {
				multicastLock?.release()
			}
		} catch (_: Exception) {
		}
	}

	private fun safeServiceName(raw: String?, fallback: String): String {
		val value = raw?.trim().orEmpty()
		val normalized = if (value.isBlank() || value.equals("null", ignoreCase = true)) fallback else value
		return normalized.replace("(null)", "").replace("null", "").trim().ifBlank { fallback }
	}

	private fun buildAdvertisedRoomName(baseName: String): String {
		val base = safeServiceName(baseName, "Space")
			.replace("\\s+".toRegex(), "")
			.take(10)
			.ifBlank { "Space" }
		val vendor = (Build.MANUFACTURER ?: "").trim().replace("\\s+".toRegex(), "")
		val model = (Build.MODEL ?: "").trim().replace("\\s+".toRegex(), "")
		var hardware = when {
			model.isNotBlank() && !model.equals("unknown", true) -> model
			vendor.isNotBlank() -> vendor
			else -> "Device"
		}
		hardware = hardware.replace(Regex("[^A-Za-z0-9_-]"), "").take(8).ifBlank { "Device" }
		return "$base-$hardware"
	}

	private fun extractPreferredIp(host: InetAddress?): String {
		if (host == null) {
			return ""
		}
		if (host is Inet4Address) {
			return host.hostAddress.orEmpty()
		}
		val raw = host.hostAddress.orEmpty()
		if (raw.isBlank() || raw.contains(":")) {
			return ""
		}
		return raw.substringBefore('%')
	}
}
