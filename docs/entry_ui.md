# 标题与联机大厅

首屏直接提供「单人出击」「双人联机」「试飞任务」。试飞列表保留首卡 A/B、进攻窗口、开场与两种近身试飞，以及裂隙原版、变奏和仅双人的双线截击。试飞子页返回列表，列表返回首页。

大厅用现有联机信号显示房型、人数、搜索、连接、版本检查和玩法确认。房主进房选择普通或裂隙规则，变奏沿用加入端确认，双线截击只提供自己的开局按钮。房名优先显示，地址留在桌面诊断提示里。返回角色页或重试会停止本面板的发现并清理连接。协议仍为 9。

共用现有太空全景和一份 Godot 主题。按本机安全区排版，标题和角色卡在可用宽度不足时上下排。房间只在列表内滚动，重新搜索和返回留在列表外。操作的逻辑高度至少 54 像素。

## 复跑

在仓库根目录使用 Godot 4.7.2。Python 探针可通过 `GODOT` 环境变量选择同一引擎。去掉 `--capture` 可全程无窗口运行。

```bash
godot --headless --path . --editor --import
python3 tests/run_entry_ui_probe.py /tmp/entry-ui-evidence --capture
godot --headless --path . res://tests/first_card_entry_probe.tscn
godot --headless --path . res://tests/opening_trial_probe.tscn -- --entry
godot --headless --path . res://tests/offense_window_probe.tscn -- --entry
godot --headless --path . res://tests/rift_route_probe.tscn
godot --headless --path . res://tests/mobile_check.tscn
python3 tests/run_lobby_entry_probe.py /tmp/entry-lobby-regression --normal-runs 2 --remix-runs 2 --start-port 22250
python3 tests/run_dual_intercept_probe.py /tmp/entry-dual-regression --case left --case both-no-pulse --case mismatch
bash tests/run_probe.sh 22230
bash tests/run_probe.sh 22231 wide-tablet-host
bash tests/run_probe.sh 22232 wide-tablet-client
```

图形探针使用 1600×720 和 960×720 的桌面画布，另用 540×720 验证堆叠。探针把模拟的非对称系统边距变换到界面坐标，注入真实的 Godot 触摸输入事件。房间名与列表通过现有发现回调注入，建房、重复点击、到不存在房间的连接失败、取消后再加入以及房主离开走真实本机 ENet（联机传输）进程。权限失败使用原生桥状态样本，旧版本对端用真实连接发送版本 8。手机和平板真机触控、物理圆角与鸿蒙原生附近发现仍需设备验证。

基线 `4633214` 留有两种画幅的标题、角色选择、等待、扫描、房间与失败画面。旧版失败截图通过其连接失败信号呈现，改版失败截图来自连接无人监听的端口。首跑发现待连接会话还没有被判为在线，返回时因此跳过断开。现改为通过已有断开入口清理待连接对端，探针核对实际连接实例是否移除。开场试飞的原居中安全区断言保留，子页继续以可用区域中心对齐。首轮联机图形探针曾在首帧布局前取按钮坐标，修正等待后重跑实际触摸。

## 验收结果

- 20:9、4:3 图形走查各 32 项通过。覆盖空白触摸、返回上一级与焦点、1/2 等待、建房和搜索权限异常、长房名、13 个房间滚动、无房与连接失败重试，以及取消时释放同一个待连接会话。
- 540×720 堆叠布局 23 项通过。本机真实双人会话另有 29 项，验证 1/2 → 2/2、取消后再次加入、变奏确认、房主离开与版本 8 拒绝。入口与大厅复跑合计 116 项。
- 首卡入口 43 项、开场与近身入口 15 项、进攻窗口 9 项、裂隙单人 43 项、移动交互 13 项通过。大厅普通与正式变奏各跑两局，另有原版裂隙、正式变奏换线和超时重试。普通联机 40 项、两种画幅换房主各 57 项、双线截击及错大厅共 89 项通过。

## 联机大厅的系统返回

大厅在场期间接管系统返回，与屏幕返回和键盘 Esc 共用同一入口。同一帧只处理一次。搜索、建房、连接、版本检查和玩法确认都先取消当前会话并回到角色选择，再返回才离开大厅。角色页返回会等到下一处理帧再切换场景，避免同帧稍晚的返回通知触发标题退出。退出大厅时恢复原来的引擎返回设置，标题可按系统返回退出，联机战斗继续由战斗恢复模块处理退出。

取消时关闭待连接或已连接的 ENet 会话，停止发布和搜索，并清理版本检查和玩法确认。原生发现信号携带本地会话编号，旧监听器和已排到引擎队列的旧信号都不能污染下一次搜索或发布。这个编号留在设备内部，联机协议仍为 9。

基线 `dc7365e` 的根窗口返回仿真会结束进程。直接调用场景返回、触发屏幕按钮或注入 Esc 各自只退一级。屏幕按钮与 Esc 在同一帧会连续退两级。探针按引擎顺序向根窗口传播通知，再发出根窗口信号。[Godot 窗口分发](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/main/window.cpp#L848-L858) [SceneTree 退出处理](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/main/scene_tree.cpp#L831-L841)

```bash
python3 tests/run_entry_ui_probe.py /tmp/lobby-back-evidence --case back --case live --case walk --format wide
python3 tests/run_lobby_entry_probe.py /tmp/lobby-back-entry --normal-runs 2 --remix-runs 2 --start-port 22480
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 22450
```

系统返回专项覆盖两种桌面画幅、无房重扫、建房释放与重建、取消待连、同帧多入口、角色页返回标题及标题退出。本机 ENet 双进程覆盖取消版本检查与玩法确认后重进，已连接的房主取消后加入端可以重搜，并从普通联机实战验证房主照常退出、加入端收到离场。原生发现回调用模拟回调和 Kotlin 测试替身验证。Android 真机系统手势、系统按钮与原生附近发现仍需设备实测。

Godot 4.6.2 和 4.7.2 的系统返回专项各通过 69 项。4.7.2 的入口走查和屏幕返回联机共 45 项，普通联机 40 项，双画幅换房主各 57 项。普通、原版裂隙、变奏的大厅联机回归共 7 局通过，包含变奏换线和超时重试。并行首跑有一局争用发现端口，串行复跑通过。Android 插件通过 SDK 35 编译检查，旧回调测试替身通过 6 项。
