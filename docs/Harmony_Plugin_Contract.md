# Harmony 插件契约（Godot 对接）

本文档定义鸿蒙原生插件与 Godot 脚本层的对接契约。目标是让联机大厅走“附近发现直连”，不再依赖手动热点配置。

## 1. Godot 侧入口

- Autoload: `scripts/harmony_bridge.gd`（单例名：`HarmonyBridge`）
- 检测插件单例候选名（任一命中即可）：
  - `HarmonyNearbyGame`
  - `HarmonyBridge`
  - `HarmonyInterop`

## 2. 插件需提供的方法（任意一组命名即可）

### Host 发布房间

- `publishNearbyGame(roomName: String, gamePort: int)`
- 或 `publish_nearby_game(roomName: String, gamePort: int)`
- 或 `startHostAdvertise(roomName: String, gamePort: int)`

### Join 扫描房间

- `findNearbyGame()`
- 或 `startScan()`
- 或 `start_scan()`

### 停止/销毁

- `destroyNearbyGame()`
- 或 `stopAll()`
- 或 `stop_all()`

## 3. 插件 -> Godot 回调

插件发现房间后，需主动回调：

- `HarmonyBridge.report_discovered_host(host_name: String, host_ip: String, host_port: int)`

插件状态变更或错误，建议回调：

- `HarmonyBridge.report_status(message: String)`

## 4. 数据约束

- `host_ip` 必须是可被 ENet `create_client` 直连的 IP（例如局域网地址）。
- `host_port` 必须与房主实际 ENet 监听端口一致（默认 `7777`）。
- `host_name` 可为空，空值会在 Godot 侧回填为 `HarmonyHost`。

## 5. 当前迁移边界（v1）

- 已迁移：大厅入口、发现与配对流程（统一走 `HarmonyBridge`；插件不可用时由桥内部回退调试后端）。
- 未迁移：战斗期实时同步传输。当前仍由 `ENetMultiplayerPeer` 承担。

## 6. 验收清单（真机）

1. 双端鸿蒙设备安装同版本游戏包。
2. Host 点击“我来开房”，`HarmonyBridge` 收到“发布成功”状态。
3. Join 点击“我来加入”，2 秒内看到房间列表。
4. Join 点击房间后进入 ENet 握手，收到 `connection_succeeded`。
5. Host 点击开始，双端进入 `main.tscn` 且玩家双实例可控。

## 7. 仓库内骨架实现说明

- 已落地插件骨架文件：
  - `android/build/src/main/java/com/godot/game/harmony/HarmonyNearbyGamePlugin.kt`
- 已完成 manifest 注册：
  - `android/build/src/main/AndroidManifest.xml` 中
    - `org.godotengine.plugin.v2.HarmonyNearbyGame`
    - `com.godot.game.harmony.HarmonyNearbyGamePlugin`
- 插件当前 discovery 后端：
  - 使用 Android `NsdManager`（mDNS / DNS-SD）做局域网服务发现；
  - 与 Godot 层方法名契约保持一致，可直接被 `HarmonyBridge` 调用。
