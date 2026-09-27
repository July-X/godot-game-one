# 更新日志

## [未发布] - 2026-09-27

### 性能

- **渲染后端切到 GL Compatibility**（`project.godot`）：同一战斗场景实测
  Forward+（Vulkan/MoltenVK）**102 fps / 9.80ms** vs Compatibility
  **276 fps / 3.62ms**，快 2.7 倍。瓶颈在 macOS 的 Vulkan 路径而非游戏逻辑
  ——把渲染分辨率减半帧率几乎不变（114.6 → 112.8 fps），已排除填充率瓶颈。
  本项目是纯 2D CanvasItem 绘制，无着色器、无粒子系统，Compatibility 功能够用，
  移动端同样受益。
- **星空从 305 个节点压到 3 个**（`main.gd::_build_star_tile()`）：三层视差星空
  原本是「每颗星一个 Sprite2D」共 305 个节点、305 张各自独立的 2~12px 贴图，
  每帧全部移动、无法合批。改为每层一张 256×256 可平铺贴图，draw call 305 → 3，
  单这一项把帧率从 106 抬到约 120。`_apply_client_perf_profile()` 相应从
  「删掉一半节点」改为「调暗贴图」。
- **帧率上限 120 + 物理插值**：`run/max_fps=120`（保留 vsync）、
  `physics/common/physics_interpolation=true`。物理保持 60Hz——弹幕游戏的判定
  与手感基准不随渲染帧率变化，联机探针的时序断言也按 60Hz 物理帧计数。
  高速抛射物（`bullet.gd` / `laser_bolt.gd` / `homing_missile.gd`）显式关闭插值，
  避免渲染位置与命中判定错开半帧。
- 已确认本项目所有运动与计时均为秒 / delta 驱动（鼠标惯性 `1.5 * delta`、
  受击闪烁、爆炸 `FRAME_INTERVAL`、屏幕震动 `_duration`），
  因此提高渲染帧率不会改变任何手感数值。

### 修复

- **客户端间歇性丢失远端玩家**（本轮最严重，由回归探针暴露）：
  客户端约 2/3 概率完全拿不到 Host 的玩家节点——画面上少一个人、位置也不同步。
  三层根因逐层修掉：
  1. `player.tscn` 的 `MultiplayerSynchronizer` 与「每端各自 `change_scene` 进
     `main.tscn`」冲突，引擎场景复制持续报 `Node not found:
     "Main/1/MultiplayerSynchronizer"` / `Failed to get path from RPC: Main`
     并丢弃同步包 → 删除同步器与 `SceneReplicationConfig`。
  2. `player.gd` 的 `set_multiplayer_authority(peer_id)` 非递归，子节点权威停在
     默认的 1（Host），Host 会把 P2 幽灵坐标灌到客户端本机玩家上（手感像被
     橡皮筋拽住）→ 改为递归设置。
  3. 玩家位置改由 `main.gd` 显式同步：`_batch_sync_players` /
     `_rpc_sync_player_states` / `_rpc_report_player_state`，4 字段
     （`peer_id, x, y, rotation`）、45Hz、与敌人子弹同一节拍，两端都跑
     `_apply_player_interpolation`，本机节点永不接受远端坐标。
- **新加入端可能永久缺一个远端玩家**：Host 自己在 `main._ready()` 的生成广播
  早于客户端连接，广播进了虚空；客户端的补齐请求又可能早于 Host 建好
  `_players` 到达并拿到空名单 → `player_connected` 时调用
  `_send_player_snapshot_to()` 补发完整名单，客户端请求保留为兜底。
- **`pool.gd` 空池取用崩溃**：原 `acquire()` 写 `var pool: Array = _pools.get(type_name)`，
  当该类型尚未 `setup()` 时会把 `null` 赋给 `Array` 类型变量，Godot 4 直接抛运行时错误并中断函数，
  导致 `acquire()` 返回 `null`，随后 `add_child(null)` 与 `node.setup()` 连锁报错。
  实际触发路径：`Pool.reset_all()`（断线回退单机 / 结算清理）之后旧场景还会继续开火约 5 秒，
  这段时间内每帧喷错误。
- **`powerup.gd` 入树前访问 `@onready` 节点**：联机同步链路在 `add_child()` **之前**调用
  `setup()`（见 `main.gd::_rpc_spawn_powerup`），此时 `@onready var _sprite` 仍为 `null`，
  `_setup_visual_style()` 直接赋值抛空引用错误；每次网络掉落都会触发一次（精英死亡一次掉 12 个）。
  改为未入树时跳过，由 `_ready()` 补应用。

### 变更

- **对象池停用节点复用**（`pool.gd`）：`release()` 早就一律 `queue_free()`，池化名存实亡，
  而 `setup()` 仍在预实例化 40 发子弹 + 20 个命中特效且从不 `add_child`——这 60 个节点
  既不在场景树里也永远不会被归还，整局白占内存。删除预分配与 `setup()`，`main.gd`
  两处 `Pool.setup` 调用一并移除，`acquire`/`release`/`reset_all` 签名不变。
  不在本轮恢复真池化：git 五次返工的教训是父节点归属与归还时序才是真正的成本。
- **清理只写不读的死字段**：`powerup.gd` 的 `assigned_peer_id` / `_magnet_radius`
  （三个生成路径都是 `add_child` → `setup` → `set_meta`，缓存归属必然读到空值）。
- `boss.gd` 的 `BOSS_ULTIMATE_LASER_HP_INTERVAL` 注释写「15%」，实际常量是 0.25
  （25 个百分点），与文档侧已校准的表述对齐。

### 新增

- **联机回归门禁 `tests/run_probe.sh`**：一条命令起双进程、收口退出码、
  扫描 `SCRIPT ERROR` 与运行期引擎报错，全绿才 `exit 0`；已知噪音
  （at-exit 泄漏 + 入局期 RPC 寻址）显式放行但打印计数。
- **探针断言 28 → 36 项**（host 22 + client 14），新增覆盖：
  远端玩家跟随 Host、本机玩家不被幽灵坐标覆盖、Host 幽灵被客户端驱动、
  两端玩家节点数恒为 2、不得再挂引擎同步器、激光推进 3s + 持续 10s
  全程对束外玩家零伤害。
  `_check()` 现在统计通过/失败数，结尾打 `VERDICT SUMMARY` 并 `quit(1)`。

### 文档

- **属性上限纠错**：`docs/architecture.md` 原写三个成长属性「单项上限 50」，
  实际为 `shoot_level` 10 / `shoot_speed_level` 15 / `bullet_power_level` 50，
  并补上 `power` 掉落满 50 后转 `heal(1)` 的行为。
- `docs/architecture.md` 新增 §11.7 玩家位置同步改造、§11.8 RPC 寻址与入局期噪音、
  §11.9 玩家节点生成时序，§12 性能表与文件树同步对象池现状，§15 补门禁判定标准
  与探针的 5 个踩坑点。
- `docs/Design_Decisions.md` 记录「不用引擎同步器」「权威必须递归设置」
  「玩家生成双通道补发」「池化下线」「回归必须自动判成败」五条决策。
- `README.md` / `agents.md` 同步门禁用法、断言数与多人模式约束（禁止再挂
  `MultiplayerSynchronizer`）。
- **项目定位全面校准**：仓库实际形态早已从「单机 3D 微剧情动作游戏」变为
  `Space Bullet Hell`（2D 俯视角 Roguelike 弹幕射击 + 2 人 LAN 联机），
  但 `README.md` / `agents.md` / `docs/Design_Decisions.md` / `docs/Development_Plan.md`
  / `docs/art_audio_pipeline.md` 仍停留在旧 3D 叙事版本，已全部对齐代码现状。
- **`docs/architecture.md` 重写**：补入 `boss.gd`/`boss.tscn`、`scripts/player/` 四模块拆分、
  4 个联机 Autoload、`pool.gd`、`tests/`；删除仓库中不存在的
  `skill_cooldown_overlay.gd` / `laser_cooldown_overlay.gd`（实际合并为 `cooldown_overlay.gd`）；
  更正主场景为 `title_screen.tscn`；更正成长公式（子弹上限 8→12、
  护盾「每 10 击杀 1 层」→「8 秒自动充能」）；补入 Boss 三阶段与终局激光完整参数。
- **Boss 终局激光参数纠错**：`Design_Decisions.md` / `Development_Plan.md` /
  `AI_HANDOFF_2026-05-12.md` 原写「血量首次降到 10% 触发一次、0.8 秒宽束推进」，
  实际实现是「每损失 25 个百分点血量触发一次、2s 蓄力 / 3s 尖端推进 / 10s 持续束，
  内圈秒杀外圈 10HP/s」。三处已更正并标注修正记录。
- **精英 / Boss 触发条件纠错**：`architecture.md` 原写「每 20 击杀触发精英（total_kills % 30 == 0）」
  自相矛盾且过时；实际为精英 `total_kills % 20 == 0`、Boss `level % 5 == 0`。

### 已知遗留

- `backup_3d/` 是旧 3D 版本完整存档（340K），已废弃但仍在仓库内，未删除。
- 客户端从大厅切到 `main.tscn` 期间，Host 已开始的广播会以 `Main` 路径寻址失败
  并被丢弃（入局期噪音）。丢包由实体快照自愈兜住，根治需改为「先挂载主场景再 join」，
  涉及大厅流程改造，暂不做。
- `docs/architecture.md` §11.8 的噪音白名单与 `tests/run_probe.sh` 的 `KNOWN` 变量
  需同步维护，新增引擎报错类型时要一并判断。

## [1.3.1] - 2026-05-12

### 新增
- **精英怪四阶段重构（M2 首批）**：`elite.gd` 改为护盾压制→破盾暴露→裂隙召唤→濒死三连预测弹的阶段节奏；新增 4 秒破盾易伤窗口（+25%）和破盾提示信号。
- **精英固定 12 掉落半弧喷射**：精英死亡掉落改为固定 12 个并按半弧外喷；联机下仍按存活玩家轮转归属。
- **战斗横幅提示（M1/M2）**：`hud.gd` 新增中心横幅接口，精英/Boss 登场与破盾窗口改为 HUD 横幅统一呈现。
- **拾取 Toast（M1）**：新增本地拾取提示文案（治疗/威力/速射/扩散/炸弹/核心），在玩家附近上浮淡出。
- **属性条变化动效（M1）**：`hud.gd` 的属性条改为带尾闪的变化反馈，升级时会出现短促高亮与扫尾。
- **精英顶部护盾条（M2）**：`elite.gd` + `elite.tscn` 新增护盾条 UI，并把护盾值纳入联机实体同步。
- **Boss 三阶段战斗（M3）**：`boss.gd` 改为压制校准、裂隙展开、核心过载三阶段，按血量切换攻击节奏与视觉状态。
- **Boss 顶部状态条（M3）**：`hud.gd` + `main.gd` 新增 Boss 顶部血条和阶段名显示，加入端可通过同步血量推断阶段。
- **Boss 补给/核心碎片（M3）**：核心过载阶段定期掉落补给碎片；Boss 死亡追加核心碎片环形掉落。
- **Boss Buff 持久属性分组**：Boss 死亡后不再弹奖励选择面板，改为给玩家自动随机发放一条持久强化，并显示在左侧属性条下方的 Boss 强化分组中。
- **精英护盾碎裂特效**：精英破盾时新增环形碎片爆发，加入端通过护盾同步归零也会播放破碎光晕。

### 修改
- **掉落物视觉层级与磁吸手感（M1）**：`powerup.gd` 增加不同类型配色和发光风格；磁吸速度改为 320→720（0.35s）加速曲线，提升靠近吸附反馈。
- **联机掉落归属字段同步补齐（M1）**：`main.gd` 的掉落生成 RPC 追加 `assigned_peer_id`，客户端幽灵副本可正确携带归属元数据。
- **Boss 性能边界（M4）**：Boss 裂隙门采用轻量即时视觉节点，召唤无人机最多 2 个，客户端幽灵 Boss 继续只做插值和 HUD 显示。

### 修复
- **联机 Boss 血条同步**：Boss 补齐网络血量接口，加入端幽灵副本会随 Host 权威血量实时刷新，不再显示错误血条。
- **联机回退单机帧率下降**：断线回退前清理网络实体、同步缓存和对象池，并改为异步切回单人主场景，避免旧联机节点残留导致 FPS 掉到约 45。
- **模式切换提示停留时间**：联机断开回退单机时提示固定停留 5 秒，再进入新的单人场景，避免提示随旧场景立即销毁。
- **HUD 稳定刷新**：HUD 显式开启 `_process`，并给 FPS / 技能按钮 / 积分显示加了更强的可见性和缓存刷新，避免导出包里出现数值不刷新或按钮像“消失”一样的情况。
- **双屏实体同步卡顿**：实体位置/血量主同步包恢复为 5 字段 `PackedFloat32Array`，护盾值拆为仅精英等带盾实体发送的独立同步包，避免所有敌人/掉落物每 66ms 附带无效护盾字段。
- **加入端漏怪自愈**：Client 在位置同步中发现未知实体 ID 时，会限频请求 Host 重发当前实体快照，避免一次生成 RPC 漏收后出现“房主有怪、加入端无怪”。
- **联机 Boss 奖励反馈**：Boss 奖励改为 Host 权威随机发放，按 peer_id 结算后同步对应玩家属性栏，不再使用奖励选择面板。
- **Boss 战射击音效丢失**：`SFX` 为玩家射击增加独立播放器池，避免 Boss 战爆炸/奖励/受击音效抢占普通射击声。
- **导弹/激光锁定优先级**：追踪导弹和激光技能优先锁定 Boss 与精英怪，再回退普通敌人，避免关键技能被小怪抢目标。
- **玩家护盾触发修复**：玩家有护盾时，任何正数小数伤害都会至少消耗 1 层护盾，避免低伤弹幕被转成 0 后不触发护盾。
- **精英护盾方框**：禁用旧 `ShieldSprite` 方形渐变纹理，护盾视觉只保留 `shield_circle.gd` 绘制的圆形光晕和顶部护盾条。
- **掉落拾取兼容**：玩家拾取区补上 `Area2D` 进入事件，掉落物更稳地进入磁吸/拾取链路，避免只靠半径检测导致属性不加成。
- **掉落属性即时刷新**：`collect_powerup` 改为先写入玩家属性、再发出本地拾取信号，避免 HUD 读到拾取前的旧属性。
- **APK HUD 丢失根因修复**：确认真正根因为 `hud.gd` 在 `CanvasLayer` 中直接调用 `get_viewport_rect()`，进入主场景时脚本解析失败，导致技能按钮和 FPS 都不生成；已改为使用设计视口尺寸，并增加主场景运行验证。
- **APK 技能按钮可见性**：技能条保持右下锚点 + 设计视口偏移，避免 `viewport` 拉伸模式下被物理窗口坐标带出 1280x720 画布。

### 修改
- **玩家初始血量调整**：初始生命调整为 50，降低 Boss 战被连续弹幕秒杀的概率，同时避免 100 血量导致压力过低；生命上限成长规则保持 2000 上限。
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
