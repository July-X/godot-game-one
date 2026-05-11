# 更新日志

## [Unreleased] - 2026-05-11

### 修改
- **玩家初始血量提升**：初始生命从 10 调整为 100，降低 Boss 战被连续弹幕秒杀的概率，生命上限成长规则保持 2000 上限。
- **Boss AI 拟真强化**：Boss 现在会进行中距离巡航、预测瞄准、侧向假动作、受压闪避和更连续的姿态转向，攻击弹幕降低单发压制但提升可读性。
- **联机断线回退**：房主或加入者退出后，当前设备自动断开网络并重载为单人模式，避免停留在半同步状态。

## [1.3.0] - 2026-05-09

### 修复
- **加入端闪退防护（Harmony 发现链路）**：`HarmonyNearbyGamePlugin.kt` 解析房间地址时增加 IPv4 过滤与异常保护，避免将不兼容地址直接传给 ENet 触发加入端崩溃
- **大厅加入前参数校验**：`lobby.gd` 在点击“加入”时增加 IP/端口二次校验，并使用 `call_deferred` 发起连接，避免 UI 回调链路中的异常导致闪退
- **房间名 null 清理**：发布房间名时对 `null/(null)` 做清洗，避免出现 `Space(null)` 这类脏名称

### 优化
- **房间名硬件短后缀**：Host 发布名改为 `基础名-设备标识`（截短），减少多人场景下同名房间冲突
- **联机大厅调试状态面板**：新增常驻调试信息，实时显示插件可用性、发布/扫描状态、发现房间数、ENet 连接状态与 peer 信息，便于定位“未发布/未扫描/未连上”具体卡点

### 新增
- **Harmony 迁移桥接层**：新增 `scripts/harmony_bridge.gd`（Autoload `HarmonyBridge`），统一承接插件检测、发布房间、扫描房间与发现回调上报
- **鸿蒙插件契约文档**：新增 `docs/Harmony_Plugin_Contract.md`，固定 Godot 与原生插件的方法名/回调契约与验收清单
- **Android 原生插件骨架**：新增 `HarmonyNearbyGamePlugin.kt`（`NsdManager` discovery 后端）并完成 `AndroidManifest` 插件元数据注册

### 修改
- **联机大厅主流程迁移**：`lobby.gd` 与 `lobby.tscn` 切换为“鸿蒙附近发现直连”主流程，不再把手动热点设置作为默认入口
- **会话模式标记**：`network_manager.gd` 增加 `transport_mode`（`enet`/`harmony`）与按模式建连接口，方便后续统计与排障
- **发现链路收口**：大厅不再直接依赖 `NetworkDiscovery`，统一通过 `HarmonyBridge` 驱动（插件不可用时桥内部回退调试后端）
- **入口清理强化**：`title_screen.gd` 在进入单机/联机前统一清理 `HarmonyBridge` 与 `NetworkDiscovery` 状态，避免残留会话污染
- **文档同步**：`README.md`、`docs/Design_Decisions.md`、`docs/Development_Plan.md` 补齐迁移边界、完成定义与后续 M2 计划
- **构建目录跟踪修正**：`.gitignore` 放行 `android/build/src/main/AndroidManifest.xml` 与 `HarmonyNearbyGamePlugin.kt`，确保插件骨架可纳入版本管理

### 兼容性说明
- 真机鸿蒙发布链路：要求原生插件实现契约方法后可完整走“附近发现 -> 加入房间”
- 桌面编辑器调试链路：保留 ENet 回退路径用于本地开发验证（非正式发布路径）
- Android 工程编译验证：`assembleStandardDebug` 已通过

## [1.2.4] - 2026-05-08

### 优化
- **Boss 模型缩放到 2/3**：Boss 贴图显示与碰撞体同步缩小，避免视觉大小与命中体积不一致
- **Boss 属性与机动 AI 强化**：提高基础生命与近身脱离能力，缩短脱离冷却并提升绕圈/后撤速度，降低被贴脸连击快速击杀的概率
- **Boss 战清场切相**：Boss 登场时自动清空场上小怪、小行星、掉落物与弹幕，形成独立“海浪式”战斗阶段
- **Boss 战氛围切换**：Boss 阶段切换背景色与 BGM（更高音高/音量），击败 Boss 后恢复常规战斗氛围
- **时长目标校准**：Boss 血量按玩家当前 DPS 动态估算并锚定约 20 秒击杀窗口
- **Boss 血条连续扣减修复**：Boss 受击改为浮点伤害结算，避免小数伤害被截断造成“血条不动然后瞬死”
- **Boss 形象风格调整**：Boss 程序化贴图改为飞船/战机母版并保留变体配色，弱化“眼球机甲”违和感

## [1.2.3] - 2026-05-08

### 修复
- **Boss 连续受击无限后退**：击退动画改为防叠加触发，连续命中时不再叠加位移导致 Boss 被推到屏幕外
- **Boss 屏外越界问题**：新增 Boss 战场边界钳制，移动/撤退/受击后都保持在可视区域内
- **Boss 来袭提示不稳定显示**：重写提示动画为串行时间线（淡入→停留→淡出），并移除字体兼容性较差的符号，保证提示可见

### 优化
- **Boss 击退抗性**：加入短时间连击衰减机制，高频连续命中时击退距离递减，并在撤退/冲刺状态进一步减弱击退，保留反馈同时避免战斗节奏失真
- **Boss 资源补齐**：通过仓库内 AI 资产流程生成并落盘 `assets/sprites/enemies/boss/boss.png`，与精英怪一样使用专属怪物图片
- **Boss 多外形轮换**：新增 `boss_01`~`boss_05` 变体，Boss 每次出场自动轮换并避免连续重复
- **玩家升级外形分档**：调整为“每 5 级切换一次外形，最多 5 种”（`lv01`~`lv05`），不再每级变形
- **Boss 风格重制**：`boss_01`~`boss_05` 改为“重甲双炮机甲”母版衍生，统一红黑装甲 + 核心发光的家族化设计

## [1.2.2] - 2026-05-05

### 修复
- **移动端轮盘可视化恢复**：左下角显示固定轮盘底盘和摇杆，不再是隐形触控区
- **移动端重开触发链路加固**：点击屏幕重开从 `_unhandled_input` 提升到 `_input`，避免被 UI 输入链吞掉

### 优化
- **轮盘按下反馈**：按下轮盘时底盘与摇杆高亮，松手恢复默认样式
- **轮盘参数可调**：新增 `knob_scale` 导出参数，配合 `joystick_radius/base_offset` 便于不同手机分辨率调参

## [1.2.1] - 2026-05-05

### 修复
- **移动端输入改为轮盘+自动开火**：触屏不再依赖右半屏按住发射，改为保持自动发射；左侧拖拽轮盘仅控制飞行方向和机头朝向
- **修复触屏发射失效**：避免“只能转动飞机但不发射子弹”的问题，移动端始终按射速自动开火
- **修复重开后触控可用性**：重开后不需要重新触发开火手势，轮盘拖动即可继续操控并自动射击

### 修改
- `scripts/mobile_controls.gd`：移除瞄准/按住开火触摸逻辑，改为单触点左侧虚拟轮盘输出方向向量
- `scripts/player.gd`：移动端瞄准改为跟随轮盘方向，射击触发改为统一自动发射；桌面端鼠标瞄准与自动发射保持不变

## [1.2.0] - 2026-05-02

### 新增
- **Level 03 关卡** (`level_03.tscn`)：20x20 紧凑场景，8个敌人（4巡逻+2射击+2跳跃），高密度战斗配置
- **Level 03 剧情文本**：3段剧情触发器 + 关卡名称

## [1.1.0] - 2026-05-02

### 新增
- **Level 02 关卡** (`level_02.tscn`)：32x32 更大场景，8个敌人（4巡逻+2射击+2跳跃），更多掩体（4立柱+4矮墙+6箱体）
- **多关卡流程**：通关 Level 01 后自动进入 Level 02，全部通关后显示结算
- **Level 02 专属剧情文本**：3段剧情触发器文本匹配新关卡

### 修复
- `hud.gd`：`_active_toasts` 类型从 `Array[Control]` 改为 `Array`
- `enemy_jumper.gd`：跳跃音效从 `play_enemy_hurt()` 改为 `play_ui_select()`

## [1.0.0] - 2026-05-02

### 新增
- **成就系统** (`achievement_system.gd`，Autoload)：6个成就
  - First Blood：首次击杀
  - Clean Sweep：单局全灭敌人
  - Speed Runner：60秒内通关
  - Survivor：无伤通关
  - Veteran：完成5次任务
  - Elite Operator：累计50击杀
- **成就解锁提示** (`achievement_toast.tscn`)：结算画面右上角弹出，3秒后渐隐
- **标题画面成就进度**：显示已解锁/总数

### 修改
- `main.gd`：新增 `_hp_lost` 追踪，结算时调用 `Achievements.check_achievements()`
- `hud.gd`：新增 `show_achievement_unlocks()`，显示成就解锁提示
- `title_screen.gd`：显示成就进度
- `project.godot`：新增 Achievements Autoload

## [0.9.0] - 2026-05-02

### 新增
- **跳跃型敌人** (`enemy_jumper.gd` + `enemy_jumper.tscn`)：绿色外观，周期性跳跃接近玩家，跳跃力 5.0，冷却 1.5s，追击范围 8
- **存档系统** (`save_system.gd`，Autoload)：保存/加载最佳通关时间、总击杀数、通关次数、单局最高击杀数到 `user://save_data.json`
- **标题画面记录显示**：显示最佳时间和总击杀数（`RecordHint` 标签）
- **结算画面记录显示**：显示最佳时间和总击杀数（`RecordLabel` 标签）
- **关卡扩展**：新增 2 个跳跃型敌人（EnemyJumperA/B）

### 修改
- `title_screen.gd`：新增 `_update_record_display()`，显示最佳记录
- `hud.gd`：新增 `record_label`，结算画面显示最佳记录
- `main.gd`：结算时调用 `SaveSystem.record_run()` 记录数据
- `project.godot`：新增 SaveSystem Autoload

## [0.8.0] - 2026-05-02

### 新增
- **射击型敌人** (`enemy_shooter.gd` + `enemy_shooter.tscn`)：紫色外观，不移动但转向玩家，每 2 秒发射子弹，射程 8
- **关卡扩展**：新增 2 个巡逻敌人（EnemyC/D）、1 个射击型敌人（EnemyShooterA）、2 面矮墙掩体（LowWallC/D）、2 个木箱掩体（CrateE/F）

### 修改
- `player.gd`：修复 `current_health` 初始值从硬编码 5 改为 `max_health`（4）

## [0.7.0] - 2026-05-02

### 新增
- **BGM 程序化生成** (`bgm_manager.gd`，Autoload)：标题/游戏/结果主题音乐，AudioStreamWAV 实时合成 8-bit 旋律循环
- **最终手感平衡**：
  - 敌人血量从 3 → 2
  - 玩家血量从 5 → 4
  - 玩家无敌帧从 0.45s → 0.5s
  - 敌人触碰冷却从 0.6s → 1.0s
  - 子弹速度从 18 → 20，寿命从 1.2 → 1.0
  - 敌人巡逻停顿从 0.8s → 1.0s
- **子弹拖尾优化**：避免重复创建 Basis，改用 `Basis().scaled(...)`

### 修改
- `main.gd`：集成 BGM 控制（标题/简报/游戏/结果画面切换）
- `project.godot`：新增 BGM Autoload
- `enemy.gd`：调整血量、触碰冷却、巡逻停顿
- `player.gd`：调整血量和无敌帧
- `projectile.gd`：优化拖尾动画性能

## [0.5.0] - 2026-05-02

### 新增
- **玩家低多边形模型**：从单一胶囊体改为多部件组合（躯干 Box + 头部 Sphere + 头盔 Box + 四肢 Box），蓝色主体 + 深蓝四肢
- **敌人低多边形模型**：多部件组合（躯干 + 头部 + 黄色护目镜 + 四肢），红色主体 + 深红四肢
- **玩家奔跑动画**：移动时腿臂摆动 + 身体上下起伏
- **玩家射击 recoil**：射击时枪口上跳 8° 后恢复
- **敌人全身受击闪光**：所有部件白色 emission 闪烁
- **敌人全身死亡动画**：所有部件红色 emission + 缩小消失
- **光照增强**：主光能量 3.2 + 补光 0.6，硬阴影（shadow_opacity 0.85）
- **后处理增强**：ACES 色调映射、暗色背景 (#0d0d1a)、微弱辉光（bloom 0.15）

### 修改
- `player.gd`：新增 `_update_walk_animation()`、`_reset_pose()`、`_recoil_pose()`，操作 ModelRoot 下各部件
- `enemy.gd`：`_flash_hit()` 和 `_death_animation()` 改为遍历 ModelRoot 子部件
- `main.tscn`：WorldEnvironment 增强，新增 FillLight 节点

## [0.4.0] - 2026-05-02

### 新增
- **屏幕淡入淡出过渡**：标题→简报、简报→游戏、游戏→结算之间添加黑色淡入淡出效果（`screen_transition.gd`）
- **敌人死亡动画**：敌人死亡时播放缩小消失 + 红色 emission 闪烁动画（0.35s），替代直接 queue_free
- **出生点信标**：关卡出生点处添加绿色脉冲缩放信标，帮助玩家识别起始位置

### 修改
- `enemy.gd`：`take_damage()` 中死亡逻辑改为调用 `_death_animation()`，不再直接 `queue_free`
- `level_01.gd`：新增 `_start_beacon_pulse()`，信标持续脉冲动画
- `main.tscn`：新增 `ScreenTransition` 节点

## [0.3.0] - 2026-05-02

### 新增
- **开场简报序列**：标题画面后进入简报界面，逐行显示任务简报（7行剧情文本，按行延迟显示），按 Enter 跳过/继续
- **多段剧情触发器**：关卡内新增 StoryTrigger1-3，分别位于入口/中段/出口前，触发不同剧情文本
- **结算画面计时**：结果画面显示任务用时（分:秒格式）
- **结果画面返回标题**：按 Enter 从结果画面返回标题（场景重载）

### 修改
- `main.gd`：重构为 `标题 → 简报 → 游戏` 三阶段流程，新增 `_start_briefing()`、`_get_elapsed_time()`、`_return_to_title()`
- `level_01.gd`：重写为自动发现 `StoryTrigger*` 节点，支持多触发器注册，信号携带触发器索引
- `hud.gd`：`show_result_screen()` 新增 `elapsed_time` 参数，显示 TimeLabel
- `briefing.gd`：改为逐行显示简报文本（旧版为打字机效果），信号名改为 `briefing_finished`

## [0.2.1] - 2026-05-01

### 修复
- **窗口/拉伸模式修复**：从 `canvas_items` 改回 `viewport` 拉伸模式（对3D游戏更兼容），保留960x540初始窗口
- **光照增强**：环境光亮度从 1.0 提升至 1.5，环境光颜色提亮，太阳光能量从 2.0 提升至 2.8，关闭雾效
- **`GPUParticles3D` 类型名修复**：`hit_effect.tscn` 中节点类型从 `GpuParticles3D` 改为 `GPUParticles3D`（Godot 4 正确类名）
- **相机拉近**：从 z=5.8 拉近到 z=3.5，玩家画面占比从 11% 提升至 19%

## [0.2.0] - 2026-05-01

### 新增
- **关卡视觉增强**：在 level_01 中添加了 4 根立柱（PillarA-D）、2 面矮墙（LowWallA-B）、更多木箱（CrateC-D）、小箱子（CrateSmallA-B）和高箱（CrateTallA-B），增加了战斗掩体和视觉层次
- **材质颜色系统**：地面、墙壁、障碍物、出口、剧情触发器都分配了不同颜色材质，形成区域视觉区分
- **玩家和敌人材质**：玩家蓝色（#4d8ce6），敌人红色（#d94033），爆能枪灰色
- **击中反馈**：敌人受击时材质白色闪烁（emission 闪白，0.12s 渐隐）
- **命中粒子特效**：子弹命中任何物体时产生金色粒子爆发（6 粒子，0.25s 生命周期）
- **相机震动**：玩家受击时 CameraRig 随机偏移（强度 0.18，衰减率 8.0）
- **结算画面**：游戏结束/通关时显示全屏结果面板（MISSION COMPLETE / MISSION FAILED），包含剧情文本、击杀统计和重启提示
- **击杀追踪**：main.gd 新增击杀计数，调试面板也显示 kills 数据

### 修复
- **窗口显示过小**：初始窗口设为 960x540
- **子弹穿透静态物体**：`projectile.gd` 现在无论命中什么物体都会触发特效并 `queue_free`

### 文档
- agents.md、Development_Plan.md、Design_Decisions.md、art_audio_pipeline.md、README.md 统一转为中文
- agents.md 新增第 11 节"AI Agent 接力开发方向"，包含阶段定位、工作顺序、文档同步和验证流程
- Development_Plan.md 细化为带 Checklist 的子任务列表
- 新增 CHANGELOG.md

### 项目中已有的核心功能（本次未改动）
- 玩家移动（四方向）、跳跃、射击
- 敌人巡逻、追击、触碰伤害、受击死亡、受击无敌帧
- 基础关卡（地面、墙壁、出生点、出口、剧情触发器）
- HUD 显示（血量、目标、剧情、调试面板）
- 出口锁定/解锁流程（红灯/绿灯）
- 游戏状态管理（running / finished / failed）
- 重启流程（F5 重载，Enter 重新开始）
- 剧情触发器（关卡中部一个节点）
