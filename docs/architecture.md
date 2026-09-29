# Space Bullet Hell — 架构设计文档

> 最后校准：2026-09-27 | Godot 4.6.2 | GDScript
>
> **本文档是代码结构的唯一权威。** 如果本文与代码不一致，以代码为准并回头修本文。
> 设计意图见 `docs/Design_Decisions.md`，开发顺序见 `docs/Development_Plan.md`。

---

## 1. 项目概览

**Space Bullet Hell** 是一款 2D 俯视角 Roguelike 弹幕射击游戏。玩家操控星际战机，在深空星域中对抗敌机、精英与 Boss，通过升级和拾取道具不断提升火力。

| 属性 | 值 |
|------|-----|
| 引擎 | Godot 4.6.2 |
| 语言 | GDScript |
| 渲染 | 2D（Node2D / CanvasLayer） |
| 设计视口 | 1280×720，`window/stretch/mode="viewport"` |
| 纹理过滤 | 默认 0（最近邻，像素风） |
| 平台 | PC（鼠标）+ Android（触屏） |
| **项目主场景** | `scenes/ui/title_screen.tscn` |
| 战斗主场景 | `scenes/main.tscn` |

---

## 2. 文件结构

```
├── project.godot              # 引擎配置 + 10 个 autoload 注册
├── scenes/
│   ├── main.tscn              # 战斗主场景 (Node2D)
│   ├── effects/
│   │   ├── explosion.tscn     # 爆炸序列帧
│   │   ├── hit_effect.tscn    # 命中闪光
│   │   └── screen_shake.tscn  # 屏幕震动
│   ├── entities/
│   │   ├── player.tscn        # 玩家飞机
│   │   ├── enemy.tscn         # 普通敌人（3 种类型）
│   │   ├── elite.tscn         # 精英怪（四阶段）
│   │   ├── boss.tscn          # Boss（三阶段 + 终局激光）
│   │   ├── bullet.tscn        # 子弹（通用，取用走 pool.gd 入口）
│   │   ├── asteroid.tscn      # 小行星
│   │   ├── homing_missile.tscn # 追踪导弹
│   │   ├── laser_bolt.tscn    # 激光弹
│   │   └── powerup.tscn       # 掉落道具
│   └── ui/
│       ├── title_screen.tscn  # 项目主场景，入口分流
│       ├── lobby.tscn         # 联机大厅（Host/Join）
│       ├── hud.tscn           # 抬头显示 (CanvasLayer)
│       └── mobile_controls.tscn # 移动端摇杆 + 技能按钮
├── scripts/
│   ├── game_state.gd          # Autoload，全局状态真理源
│   ├── sfx_manager.gd         # Autoload，程序化音效
│   ├── bgm_manager.gd         # Autoload，程序化 BGM
│   ├── sprite_factory.gd      # Autoload，程序化贴图
│   ├── leaderboard.gd         # Autoload，排行榜持久化
│   ├── pool.gd                # Autoload，子弹/命中特效取用与回收入口（不做节点复用）
│   ├── network_manager.gd     # Autoload，ENet 连接生命周期
│   ├── hotspot_manager.gd     # Autoload，Wi-Fi 热点（调试回退）
│   ├── network_discovery.gd   # Autoload，调试发现后端
│   ├── harmony_bridge.gd      # Autoload，鸿蒙近场发现桥接层
│   ├── main.gd                # 战斗主场景控制器（刷怪 / 实体同步 / 联机权威）
│   ├── player.gd              # 玩家主控（233 行壳子）
│   ├── player/                # 玩家逻辑子模块
│   │   ├── motion_controller.gd    # 移动 / 边界反弹 / 动画
│   │   ├── combat_controller.gd    # 射击 / 导弹 / 技能 / 拾取
│   │   ├── feedback_controller.gd  # 外观 / 受击反馈 / 爆炸
│   │   └── action_router.gd        # 输入分发│   ├── enemy.gd / elite.gd / boss.gd
│   ├── bullet.gd / laser_bolt.gd / homing_missile.gd / asteroid.gd
│   ├── powerup.gd / explosion.gd / hit_effect.gd / screen_shake.gd
│   ├── laser_bolt.gd / lightning_line.gd   # 激光与闪电链绘制
│   ├── shield_ring.gd         # 玩家护盾环 draw_arc
│   ├── shield_circle.gd       # 精英/Boss 护盾圆形光晕
│   ├── shield_shatter_burst.gd # 破盾碎裂特效
│   ├── cooldown_overlay.gd    # 技能/激光冷却覆盖层（单文件，含两种形态）
│   ├── boss_ultimate_laser_visual.gd # 终局激光程序化视觉
│   ├── hud.gd / title_screen.gd / lobby.gd / mobile_controls.gd
├── tests/
│   ├── lan_probe.gd           # 双进程 headless 联机回归探针
│   ├── lan_probe.tscn
│   ├── curve_probe.gd         # 难度曲线门禁（数值不越界）
│   ├── wave_probe.gd          # 波次编排门禁（节奏形状不塌陷）
│   ├── curve_probe.tscn / wave_probe.tscn
├── docs/
├── backup_3d/                 # 旧 3D 版本存档（已废弃）
└── CHANGELOG.md
```

---

## 3. Autoload 全局系统（10 个）

| Autoload | 脚本 | 职责 |
|----------|------|------|
| `GameState` | `game_state.gd` | 全局状态真理源，信号广播中心 |
| `SFX` | `sfx_manager.gd` | 程序化 8-bit 音效播放器池 |
| `BGM` | `bgm_manager.gd` | 程序化 BGM 生成与循环 |
| `SpriteFactory` | `sprite_factory.gd` | 程序化贴图生成与缓存 |
| `Leaderboard` | `leaderboard.gd` | `ConfigFile` 排行榜持久化 |
| `Pool` | `pool.gd` | 子弹 / 命中特效的取用与回收入口，不做节点复用（见 §12） |
| `NetworkManager` | `network_manager.gd` | ENet 连接生命周期，Host/Client 统一入口 |
| `HotspotManager` | `hotspot_manager.gd` | Wi-Fi 热点（调试回退路径） |
| `NetworkDiscovery` | `network_discovery.gd` | 调试发现后端 |
| `HarmonyBridge` | `harmony_bridge.gd` | 鸿蒙原生插件适配层，插件缺失时内部回退 |

### 3.1 GameState（`game_state.gd`）

所有数值状态的唯一真理源，**按 peer_id 独立存储**（`_player_states`，key 为 peer_id 字符串），
单机模式下 `_local_peer_id()` 恒返回 1。

| 状态分类 | 字段 | 说明 |
|----------|------|------|
| 进程 | `score`, `level`, `kills`, `total_kills`, `game_running` | 积分 / 等级 / 击杀 |
| 生命 | `current_health`, `max_health`, `shield_layers` | 初始 50，上限 2000（`HEALTH_CAP`） |
| 成长 | `shoot_level`, `shoot_speed_level`, `bullet_power_level` | 道具路径上限各不相同，见下表 |
| 冷却 | `skill_cooldown`(15s), `laser_cooldown`(10s) | 环形散射 / 激光 |
| Boss 奖励 | `laser_cd_bonus`, `extra_bullet_count`, `extra_damage_bonus`, `move_speed_bonus`, `shield_max_bonus` | 击败 Boss 后永久生效 |
| 节奏 | `elite_encounter_count`, `last_elite_threshold`, `boss_encounter_count`, `last_boss_level` | 精英 / Boss 出场控制 |

**信号**：`score_changed`、`level_changed`、`health_changed`、`game_over`、
`powerup_collected`、`shield_changed`、`skill_used`、`laser_used`、
`player_scores_changed`、`elite_spawn_requested`、`boss_spawn_requested`

**核心公式（当前实现）**：

| 公式 | 代码位置 | 说明 |
|------|----------|------|
| `kills_for_next_level = 10 + level*5` | `level_up()` | 升级所需击杀 |
| `bullet_count = min(2 + shoot_level/3 + extra_bullet_count, 12)` | `get_bullet_count()` | 最多 12 发 |
| `shoot_cooldown = max(0.27 - shoot_speed_level*0.018, 0.08)` | `get_shoot_cooldown()` | 射击间隔 |
| `bullet_damage = 3 + bullet_power_level + extra_damage_bonus` | `get_bullet_damage()` | 单发伤害 |
| `bullet_spread_angle = max(30 - shoot_level*4, 10)` | `get_bullet_spread_angle()` | 扩散角 |
| `laser_damage = 5 * 2^(level/10)` | `get_laser_damage()` | 每 10 级翻倍 |
| `shield_max = (10 + bullet_power*2 + max_health*0.2) * 0.5 + shield_max_bonus` | `get_shield_max_hp()` | 护盾满值 |
| `move_speed = 1.0 + move_speed_bonus` | `get_move_speed_multiplier()` | 移速倍率 |

**成长属性上限**（三者各不相同，不要笼统写成"上限 50"）：

| 属性 | 上限 | 来源 | 满值后行为 |
|------|------|------|------------|
| `shoot_level` | **10** | `spread` 掉落 | 继续吃掉落无收益 |
| `shoot_speed_level` | **15** | `speed` 掉落 | 同上 |
| `bullet_power_level` | **50** | `level_up()` 每次 +1、`power` 掉落 | `power` 掉落转为 `heal(1)` |

（`shoot_level` 满 10 时扩散角已到下限 10°，发数在 6 发左右封顶；
`shoot_speed_level` 满 15 时射击间隔触底 0.08s。）

**触发节奏**：

- 精英：`total_kills - last_elite_threshold >= 20 + level*2`（累计计数，不用取模，
  因为阈值随等级跳变时取模会整段错过）
- Boss：`level % 5 == 0` 且未等于 `last_boss_level`（`level_up()`）

---

## 4. 核心游戏循环

```
title_screen._ready()
├── 单机按钮 → change_scene_to_file("res://scenes/main.tscn")
└── 联机按钮 → change_scene_to_file("res://scenes/ui/lobby.tscn")
        ├── Host → NetworkManager.create_host() → main.tscn
        └── Join → NetworkManager.join_host() → main.tscn

main._ready()
├── 创建视差星空背景 / 移动端控件 / HUD / BGM
├── Pool.setup("bullet", 40) / Pool.setup("hit_effect", 20)
├── GameState.reset_game() + 连接 level/elite/boss/game_over 信号
├── 若 NetworkManager.is_online()
│   ├── Host：为自己与已连接 peer 生成玩家
│   └── Client：请求一次完整玩家同步，60 帧内找不到本地节点则请求补生成
└── 否则：单机 _spawn_player()

main._process(delta)
├── _scroll_background()            # 三层星空视差
├── _apply_entity_interpolation()   # 联机：客户端实体插值
├── _send_network_sync()            # 联机：Host 批量同步实体
├── Boss 存活时跳过刷怪             # Boss 战独立波次
├── _spawn_asteroid() / _spawn_enemy()
└── 达到阈值时触发精英 / Boss
```

---

## 5. 玩家系统（`player.gd` + `scripts/player/`）

玩家逻辑已从单文件拆分：`player.gd` 只保留节点装配与信号连接，具体行为分四个模块。

| 模块 | 职责 |
|------|------|
| `motion_controller.gd` | 移动、屏幕边界反弹、行走动画 |
| `combat_controller.gd` | 自动射击、追踪导弹、两个主动技能、子弹生成 |
| `feedback_controller.gd` | 外观更新、受击闪烁、爆炸 |
| `action_router.gd` | 输入分发 |

### 5.1 移动

| 平台 | 输入 | 映射 |
|------|------|------|
| PC | 鼠标相对位移 `event.relative` | `_mouse_vel += relative * 0.008 * 260`，每帧 `lerp(0, 1.5*dt)` 衰减 |
| 移动端 | 左侧摇杆 | `velocity = touch_move * move_speed` |

鼠标停止后速度自然衰减到零（惯性手感）。玩家自动朝向速度方向，并限制在屏幕边界内反弹。

### 5.2 子弹成长

`shoot_level` 越高，扩散角越小（`max(30 - level*4, 10)` 度）、发数越多（上限 12）。
子弹首次命中屏幕边缘会反弹并加速（×1.3），反弹后变为橙色。

### 5.3 追踪导弹（5 级起被动）

按等级分 5 档，发射器数量、伤害倍率、发射间隔同步提升。优先锁定 Boss 与精英，
不存在高威胁单位时才回退普通敌人。

### 5.4 主动技能

| 技能 | 触发 | 冷却 | 效果 |
|------|------|------|------|
| 环形散射 | `Space` / △ 按钮 | 15s | 全向环形发射 |
| 激光 | `Q` / ○ 按钮 | 10s | 激光弹，命中后闪电链溅射 |

### 5.5 护盾

**初始 0 层，8 秒自动充能一次**（`SHIELD_RECHARGE_INTERVAL = 8.0`），充满到 `get_shield_max_hp()`。
有护盾时任何正数伤害至少消耗 1 层。**旧版「每 10 击杀获得 1 层」已移除**，仅保留 Boss 奖励的 `shield_max_bonus`。

### 5.6 外观演进

飞机外形按 `shoot_level` 每 5 级切换一次，最多 5 档（`assets/sprites/player/variants/lv01.png`~`lv05.png`）。

---

## 6. 敌人系统（`enemy.gd`）

| 类型 | 移动 | 射击 | 弹幕特点 |
|------|------|------|---------|
| 0 — 狙击手 | 追踪玩家 | 单体高伤 | 按 `ceil(max_health * 0.0625)` 结算，红色单发 |
| 1 — 散射者 | 蛇形移动 | 3 发散弹 | 伤害系数 0.5，绿色散射 |
| 2 — 环绕者 | 轨道环绕 | 6 发圆形 | 伤害系数 0.3，紫色圆形弹幕 |

死亡掉落：`drop_chance = 0.20 + type*0.12`，类型为 `spread` / `speed` / `power` / `heal` / `bomb`。

`bullet_speed_mult` 是**章节主题**叠加在弹速上的倍率（`wave_director.gd CHAPTER_THEMES`）。
它必须随 `_rpc_spawn_enemy` 一起同步到客户端：客户端敌人是幽灵（不跑 AI、不开火），
但弹速是纯渲染参数，不同步的话两端弹幕速度不同，擦弹判断直接失效。

---

## 7. 精英系统（`elite.gd`）

精英是 Boss 之前的中型关卡，固定四阶段：

| 阶段 | 行为 |
|------|------|
| A 护盾压制 | `MAX_SHIELD = 80`，3 秒未受伤自动恢复（`SHIELD_REGEN_TIME = 3.0`） |
| B 破盾暴露 | 护盾归零后固定 4 秒易伤窗口，承伤 ×1.25，HUD 横幅提示集火 |
| C 裂隙召唤 | 召唤辅助单位 |
| D 濒死三连 | 低血量时发射三连预测弹 |

- 死亡固定掉落 **12** 个道具，半弧喷射。
- 联机下按存活玩家轮转分配 `assigned_peer_id`，归属只影响优先吸附。
- 护盾视觉只允许 `shield_circle.gd` 的圆形光晕 + 顶部护盾条，**禁止**方形 `ShieldSprite` 渐变纹理。
- 破盾必须有环形碎裂特效。

---

## 8. Boss 系统（`boss.gd`）

Boss 是独立波次：出场时清空场上常规敌人、小行星、掉落物与弹幕，并切换背景色与 BGM。

### 8.1 三阶段

| 阶段 | 血量区间 |
|------|----------|
| 压制校准（SUPPRESSION） | 100% – 70% |
| 裂隙展开（RIFT） | 70% – 35% |
| 核心过载（OVERLOAD） | 35% – 0% |

阶段由 Host 血量权威决定，Client 只根据同步血量显示阶段名。

### 8.2 血量估算

```gdscript
_max_health = max(player_dps * 42.0 * 0.95 * mult * level_scale, 900.0)
```

目标 TTK 42 秒（`BOSS_TARGET_TTK_SECONDS`），按玩家当前 DPS 动态缩放，
避免高成长火力直接跳过阶段。`mult = 1.0 + boss_encounter_count * 0.2`。

### 8.3 终局究极激光炮

常量定义在 `boss.gd:116-122`：

| 常量 | 值 | 含义 |
|------|-----|------|
| `BOSS_ULTIMATE_LASER_HP_INTERVAL` | `0.25` | **每损失 25 个百分点血量触发一次**（不是只在 10% 触发一次） |
| `BOSS_ULTIMATE_LASER_CHARGE` | `2.0` s | 蓄力 |
| `BOSS_ULTIMATE_LASER_TRAVEL` | `3.0` s | 尖端推进 |
| `BOSS_ULTIMATE_LASER_HOLD_SECONDS` | `10.0` s | 持续束 |
| `BOSS_ULTIMATE_LASER_WIDTH` | `110` px | 束宽 |
| `ULTIMATE_LASER_INNER_RATIO` | `0.3` | 内圈比例（秒杀区） |
| `BOSS_ULTIMATE_LASER_DOT_HP_PER_SEC` | `10.0` | 外圈每秒伤害 |

**伤害规则**：

- 内圈（距束中心 ≤ 束宽 30%）：`force_kill()` 直接秒杀
- 外圈：累积器模式，`10 HP/s` 稳定扣血
- **推进阶段只检测光束当前尖端到起点的范围**（`_distance_to_beam_center` 会按 `travel_progress`
  裁剪线段终点），玩家可以跑出推进路径躲避
- 激光期间 Boss 获得护盾并暂停常规攻击

### 8.4 死亡奖励

不再弹选择面板。由 Host 按 peer_id **随机**发放一条持久强化
（激光 CD / 额外子弹 / 额外伤害 / 移速 / 护盾强度），写入 `GameState`，
并在 HUD 左侧属性条下方的「Boss 强化」分组中显示。

---

## 9. 道具系统（`powerup.gd`）

| 类型 | 效果 |
|------|------|
| `spread` | `shoot_level` +1 |
| `speed` | `shoot_speed_level` +1 |
| `power` | `bullet_power_level` +1 |
| `heal` | 回复生命 |
| `bomb` | 全屏击杀 + 屏幕震动 |
| `core` | Boss 核心碎片 |

- 磁吸为加速度曲线：320 → 720，0.35 秒。
- 联机掉落携带 `assigned_peer_id`，随实体同步到加入端，只影响优先吸附。
- **注意**：网络同步链路在 `add_child()` **之前**调用 `setup()`，因此 `setup()` 内部
  不能直接访问 `@onready` 节点（`_sprite` / `_glow`），必须由 `_ready()` 补应用。

---

## 10. UI 系统（`hud.gd`）

HUD 继承 `CanvasLayer`，**不能直接调用 `get_viewport_rect()`**（导出包中会解析失败导致整个
HUD 不生成）；需要视口尺寸时使用设计视口常量或 `get_viewport().get_visible_rect()`。

显示内容：血条、属性条（扩散/速射/威力 + 护盾 + Boss 强化分组）、积分、等级、
记分牌、实时排行榜、历史排行榜、技能冷却覆盖层、Boss 顶部阶段条、中心横幅、拾取 Toast。

### 10.1 联机命名契约

`hud.gd:_peer_label(peer_id)` 按**角色槽位**返回标签：

```gdscript
func _peer_label(peer_id: int) -> String:
    if peer_id == 1:
        return "P1"
    return "P2"
```

ENet 分配的 Client peer_id 是随机 32 位数，**UI 任何位置都不得直接显示真实 peer_id**。
该函数被记分牌、实时排行榜、历史排行榜共用。

### 10.2 技能按钮

- PC：鼠标 CAPTURED 模式下通过 `_input` 坐标检测
- 移动端：`gui_input` 捕获任意触点，支持多指同时操作（左手摇杆 + 右手按钮）
- 冷却覆盖层统一由 `cooldown_overlay.gd` 提供两种形态（三角 / 圆形）
- 采用 `window/stretch/mode="viewport"`，技能条必须用**设计视口**右下锚点定位，
  不能用 Android 物理窗口尺寸计算，否则会被带出 1280×720 画布

---

## 11. 联机架构

### 11.1 分层

```
发现层：HarmonyBridge → HarmonyNearbyGamePlugin.kt（NsdManager）
        插件不可用时内部回退 HotspotManager / NetworkDiscovery（仅调试）
        ↓ 传递连接参数
战斗层：NetworkManager → ENetMultiplayerPeer（始终 ENet）
```

`NetworkManager` 统一管理连接生命周期，上层场景只监听信号，不直接操作
`multiplayer.multiplayer_peer`。

### 11.2 角色

| 槽位 | 角色 | peer_id |
|------|------|---------|
| P1 | Host / 房主 / ENet server | 固定 `1` |
| P2 | 唯一 Client | 随机 32 位 |

`MAX_CLIENTS = 1`，只支持 2 人。

### 11.3 权威模型

- 敌人、Boss、精英、弹幕、伤害结算**全部在 Host 执行**，Client 只做插值和 HUD
- 实体视觉副本走 RPC 广播 + `entity_id` 映射，不依赖自动场景复制
- 玩家本地直接控制移动，位置通过同步包广播

### 11.4 同步包拆分

| 包 | 内容 | 频率 |
|----|------|------|
| 主同步包 | `entity_id / position / health` 等 5 字段 `PackedFloat32Array` | 每帧批处理 |
| 护盾包 | 仅带盾实体（精英/Boss） | 独立 |
| 朝向包 | Boss rotation | 独立 |

拆包原因：避免所有敌人与掉落物每帧附带无效字段。

**自愈机制**：Client 在主同步包中收到未知 `entity_id` 时，限频请求 Host 重发实体快照。

### 11.5 死亡 ≠ 断线

这是联机逻辑最容易写错的地方，两条流程必须严格分开：

| 事件 | 行为 |
|------|------|
| **玩家死亡** | 保留联机会话，只移除该玩家并切换敌人目标（`_refresh_primary_player_target`）。只有 P1/P2 全灭才 Game Over。**不得**断网、**不得**切单机 |
| **玩家断线** | 清理网络实体 / 同步缓存 / 在途子弹（`Pool.reset_all()`）→ `NetworkManager.disconnect_network()` → 提示固定停留 5 秒 → 异步重载为单人场景 |

### 11.6 Boss 生成兜底

Boss 触发时若精英仍在场，`_on_boss_spawn_requested` 只记录 `_pending_boss_level`；
精英死亡后通过 `_consume_pending_boss_spawn()` 消费。
`_is_elite_blocking_boss_spawn()` 与 `_has_active_boss()` 都会清理无效或
`is_queued_for_deletion()` 的引用，避免旧引用永久阻塞 Boss 生成。

### 11.7 玩家位置同步为什么不用 MultiplayerSynchronizer（2026-09-27 改造）

`player.tscn` 曾经挂 `MultiplayerSynchronizer` 同步 `position` / `rotation`，
现已移除，玩家位置改由 `main.gd` 显式同步：

```
Host  _batch_sync_players()   ── [pid, x, y, rot] × N ──▶  _rpc_sync_player_states()
Client _rpc_report_player_state() ── [pid, x, y, rot] ──▶  Host _apply_remote_player_state()
两端 _apply_player_interpolation()  目标点插值（alpha = delta * 18）
```

| 项 | 值 |
|----|----|
| 频率 | `ENTITY_SYNC_INTERVAL = 0.022`（约 45Hz，与敌人/子弹同一节拍） |
| 载荷 | `PLAYER_SYNC_STRIDE = 4`：`peer_id, x, y, rotation` |
| 可靠性 | `unreliable`（丢一包无所谓，22ms 后就有下一包） |
| 方向 | 每个玩家节点只有**持有端**发送，对端只应用；本机节点永不接受远端坐标 |

**移除原因**：引擎的场景复制（`SceneCacheInterface`）依赖"同步器节点路径能被解析到"，
而本项目是每端各自 `change_scene_to_file("main.tscn")`，客户端挂载战斗场景
必然晚于 Host 开始广播，于是引擎持续报

```
Node not found: "Main/1/MultiplayerSynchronizer" (relative to "/root")
Failed to get path from RPC: Main
Invalid packet received. Requested node was not found.
```

并**丢弃后续同步包**。实测后果：客户端约 2/3 概率完全拿不到 Host 的玩家节点
（画面少一个人、位置不同步），且 `set_multiplayer_authority(peer_id)` 非递归时
同步器权威停在默认的 1（Host），会把 P2 幽灵坐标灌到客户端本机玩家上。

> 回归网：`tests/lan_probe.gd` 的 `c4`（远端幽灵跟随 Host）、
> `c7`（本机玩家不被幽灵坐标覆盖）、`h7`（Host 幽灵被客户端驱动）、
> `c5`/`h5`（两端玩家节点数恒为 2）、`h8`/`c13`（不得再挂引擎同步器）。

### 11.8 RPC 寻址与入局期噪音

`@rpc` 以**节点所在场景路径**寻址，本项目即 `Main`。客户端还停在大厅（或探针
场景）时 `/root/Main` 不存在，Host 已经开始广播，引擎就会报找不到路径并丢包。
这是既有设计的固有现象，丢掉的包由 `_request_entity_snapshot_from_host()`
自愈机制补齐（`_rpc_sync_entity_positions` 见到未知实体 ID 时触发）。

`tests/run_probe.sh` 显式放行这一类噪音，但会打印计数；数量暴涨说明同步链路
真的退化了，应作为回归处理。

### 11.9 玩家节点生成时序

Host 自己在 `main._ready()` 里 announce 的玩家生成 RPC，早于任何客户端连接，
广播进了虚空。因此：

- `player_connected` 时调用 `_send_player_snapshot_to(peer_id)` 补发完整名单；
- 客户端 `_ready()` 里的 `_request_player_sync()` 保留为兜底。

两者都必要：只靠客户端请求时，请求可能早于 Host 建好 `_players` 到达并拿到
空名单，客户端会永久缺一个远端幽灵节点。

---

## 12. 帧率与渲染后端

### 12.1 三档频率的分工

| 项 | 值 | 理由 |
|----|----|------|
| 渲染帧率上限 | `application/run/max_fps = 120` | 保留 vsync，实际帧率 = min(120, 显示器刷新率) |
| 物理频率 | `physics/common/physics_ticks_per_second = 60` | 弹幕游戏的判定与手感基准不随渲染帧率变化；联机探针的时序断言按 60Hz 物理帧计数 |
| 物理插值 | `physics/common/physics_interpolation = true` | 渲染 120 / 物理 60 时补中间帧，消除整块跳动 |

**高速抛射物显式关闭插值**：`bullet.gd` / `laser_bolt.gd` / `homing_missile.gd`
在 `_ready()` 里设 `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF`。
子弹一个物理帧位移可达 10px，插值会让渲染位置落在两个物理帧之间，
与命中判定错开半帧（视觉上像"打偏"）。

**本项目所有运动/计时都是秒或 delta 驱动的**（鼠标惯性 `1.5 * delta`、
受击闪烁 `_invincible_timer` 秒、爆炸 `FRAME_INTERVAL` 秒、屏幕震动
`_duration` 秒），所以提高渲染帧率不会改变任何手感数值。

### 12.2 渲染后端：GL Compatibility（2026-09-27 切换）

`rendering/renderer/rendering_method = "gl_compatibility"`（移动端同）。

同一战斗场景实测（AMD Radeon Pro 5300M，macOS）：

| 后端 | 帧率 | 平均帧耗时 |
|------|------|-----------|
| Forward+（Vulkan / MoltenVK） | 102 fps | 9.80 ms |
| **GL Compatibility** | **276 fps** | **3.62 ms** |

瓶颈在 macOS 的 Vulkan 路径而不是游戏逻辑——把渲染分辨率减半帧率几乎不变
（114.6 → 112.8 fps），已排除填充率瓶颈。本项目是纯 2D CanvasItem 绘制，
无着色器、无 GPU/CPU 粒子系统，Compatibility 后端功能上完全够用。

> 注意：换后端后需要重新验证视觉表现（移动端导出同样受益）。
> 若未来引入 3D 或需要某些 Compatibility 不支持的效果，再评估切回 Forward+。

### 12.3 星空平铺化

`main.gd::_create_parallax_background()` 的三层星空从「每颗星一个 Sprite2D」
改为「每层一张 512×512 可平铺贴图 + 一个 Sprite2D」：

- 旧：180 + 90 + 35 = **305 个节点、305 张独立贴图**，每帧全部移动，无法合批
- 新：**3 个节点、3 张贴图**，draw call 从 305 降到 3

滚动用 `STAR_FIELD_TILE` 取模循环实现无缝衔接（贴图内不放跨界星星）。
`_apply_client_perf_profile()` 原本靠删掉一半节点给加入端减负，现在改为
调暗贴图，nebula / planet 仍按节点减半。

**两个必须靠看图才能发现的坑**：用
`get_viewport().get_texture().get_image().save_png()` 截视口比对，
比对着代码推理可靠得多。

1. **贴图重复**：256px 贴图在 1280 宽的屏幕上横排重复 5 次。截相邻两块贴图
   对比能看出星星排布完全一致，肉眼直接锁定网格。改 512px 后只重复 2.5 次。
2. **星星密度是原来的 14 倍**：第一版按 256 贴图随手取了 120/60/22 颗，
   换算成密度是「每 324 px² 一颗」，而旧实现是「每 4525 px² 一颗」。
   对弹幕射击来说背景过亮会直接吃掉**子弹可读性**，这比"看出贴图重复"
   严重得多。现按旧实现的实际密度反推取 **far=34 / mid=17 / near=7**，
   同屏可见 204 颗，与旧实现的 204 颗完全一致。

> 教训：性能优化同时改动视觉产出物时，**必须截真图比对**，
> 不能只看节点数下降就认为"优化完成"。这次是靠截图才发现密度回归的。

## 13. 性能优化措施

| 优化项 | 位置 | 说明 |
|--------|------|------|
| 星空平铺贴图 | `main.gd` `_build_star_tile()` | 305 节点 → 3 节点 |
| 渲染后端 | `project.godot` | GL Compatibility，比 Forward+ 快 2.7 倍 |
| 物理插值 | `project.godot` | 120fps 渲染下补中间帧 |
| 子弹贴图缓存 | `sprite_factory.gd` `_bullet_cache` | 同类型复用 |
| 道具贴图缓存 | `sprite_factory.gd` `_powerup_cache` | 5 种道具只生成一次 |
| 子弹取用入口 | `pool.gd` | **不做节点复用**（见下），只统一 acquire/release/reset_all |
| 护盾防抖 | `player.gd` `_shield_dirty` | 同帧多次信号只重建一次 |
| 护盾 GPU 绘制 | `shield_ring.gd` | `draw_arc()` 而非 CPU 像素循环 |
| 道具纹理延迟 | `powerup.gd` `call_deferred("_apply_sprite")` | 不阻塞死亡帧 |
| 客户端性能档 | `main.gd` `_apply_client_perf_profile()` | 非服务器端降级 |
| 实体同步包压缩 | `main.gd` | 5 字段 `PackedFloat32Array` + 护盾/朝向独立包 |
| 玩家位置同步 | `main.gd` `_batch_sync_players()` | 4 字段，45Hz，2 人仅 8 float |

> `pool.gd` 现状：`release()` 一律 `queue_free()`，池化已下线。
> 早期把节点挂在 Pool 下复用，五次返工（`3c8527b → c5e503c → be12daf →
> 1bb5882 → 241f634`）都栽在"already has a parent"和归还时序上。
> 恢复真池化前必须先补齐归还时的状态重置（速度 / 位置 / 计时 / 特效）。

---

## 14. 数据流图

```
              ┌────────────────────────────────┐
              │  GameState (Autoload 真理源)   │
              │  积分/等级/血量/护盾/冷却/奖励  │
              └───────────────┬────────────────┘
                signals       │        signals
      ┌─────────────────────┼─────────────────────┐
      ▼                     ▼                     ▼
┌───────────┐        ┌───────────┐         ┌───────────┐
│   HUD     │        │  Player   │         │   Main    │
│ 刷新显示  │        │ 移动/射击 │         │ 刷怪/节奏 │
└───────────┘        └─────┬─────┘         └─────┬─────┘
                            │ instantiate         │
              ┌─────────────┼─────────────┐      │
         ┌────▼────┐  ┌─────▼─────┐  ┌────▼───┐  │
         │ Bullet  │  │  Missile  │  │ Laser  │  │
         │ 碰撞    │  │  追踪AI   │  │ 闪电链 │  │
         └────┬────┘  └─────┬─────┘  └────┬───┘  │
              └─────────────┼─────────────┘      │
                            ▼                    ▼
                  ┌───────────────────┐   ┌──────────────┐
                  │ Enemy / Elite /   │   │ NetworkMgr   │
                  │ Boss              │   │ → ENet Peer  │
                  │ take_damage()→die │   │ → RPC 广播   │
                  └───────────────────┘   └──────────────┘
```

---

## 15. 键位映射

| 键位 | PC | 移动端 |
|------|-----|--------|
| 移动 | 鼠标移动 | 左侧摇杆 |
| 自动射击 | 始终开启 | 始终开启 |
| 技能 1（环形散射） | `Space` / △ 按钮 | △ 按钮 |
| 技能 2（激光） | `Q` / ○ 按钮 | ○ 按钮 |
| 释放鼠标 | `ESC` | — |
| 全屏切换 | `F11` | — |

---

## 16. 验证

```bash
# 1. 项目可加载
godot --headless --path . --quit

# 2. 主场景可运行（覆盖 _ready / _process 链路，--quit 不够）
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20

# 3. 联机回归门禁（推荐：自动起双进程、收口退出码、扫描引擎报错）
tests/run_probe.sh 7788          # 全绿才 exit 0，耗时约 40~60 秒

# 3'. 手工跑探针（需要看实时日志时）
godot --headless --path . res://tests/lan_probe.tscn -- host 7788   &
godot --headless --path . res://tests/lan_probe.tscn -- client 7788

# 4. 难度曲线门禁（改任何难度数值后必跑，headless 单进程，几秒出结果）
godot --headless --path . res://tests/curve_probe.tscn

# 5. 波次编排门禁（改 wave_director.gd / 阵型 / 章节主题后必跑）
godot --headless --path . res://tests/wave_probe.tscn

# 6. 移动端交互门禁（改 HUD 按钮 / 触摸 / 视口自适应后必跑）
godot --headless --path . res://tests/mobile_check.tscn
```

`run_probe.sh` 判定失败的条件（任一命中即 `exit 1`）：

| 条件 | 说明 |
|------|------|
| `host_rc` / `client_rc` 非 0 | 探针内部有断言失败（`_summarize()` 统计后 `quit(1)`） |
| `failed_assert > 0` | 日志里出现 `pass=false` |
| `script_errors > 0` | 出现 `SCRIPT ERROR` |
| `engine_errors > 0` | 出现运行期 `ERROR:`（已排除 at-exit 泄漏噪音与 §11.8 的入局期寻址噪音） |

已知噪音放行清单见 `tests/run_probe.sh` 的 `NOISE` / `KNOWN` 变量，
两类噪音的计数都会打印，便于观察是否劣化。

### 16.1 难度曲线门禁

`tests/curve_probe.gd`（headless 单进程，不需要 ENet）直接 `load("res://scripts/main.gd")`
调用 `compute_enemy_speed()` / `compute_post_elite_multiplier()`，断言：

| 断言 | 含义 |
|------|------|
| `cap_is_80_percent` | 玩家极速 260 → 敌速上限恰好 208 |
| `enemy_speed_never_exceeds_cap` | 1~60 级 × 3 种敌人的速度都不超过 208 |
| `speed_monotonic` | 封顶后允许持平，但不能越往后越慢 |
| `post_elite_multiplier_capped` | 精英乘区不超过 2.2 |
| `curve_grows` | L60 速度 > L1 的 2 倍，防止曲线被改成死水 |

> 这道门禁存在的理由：难度墙在 2026-09-27 之前已经悄悄长了一年，
> 12 级就超过玩家速度，而当时没有任何测试能发现——所有测试都在测联机与手感，
> 没人测过数值曲线本身。

探针断言共 **36 项**（host 22 + client 14），覆盖：

- 死亡 ≠ 断线：P1 被 Boss 终局激光内圈秒杀后，P2 会话存活、不回退单机
- P1/P2 槽位命名：记分牌不暴露真实 ENet peer_id
- 终局激光时序：蓄力 120 物理帧（2.0s）、推进阶段只检测尖端
- 束外玩家零伤害：推进 3s + 持续 10s 全程逐帧采样 P2 血量
- 精英在场时 Boss 触发进入 pending，杀精英后补发
- 玩家同步归属：远端跟随 Host / 本机不被幽灵覆盖 / 幽灵被客户端驱动
- 玩家节点数恒为 2，且不再挂引擎 MultiplayerSynchronizer

探针注意事项：

- 探针自身是启动时的 `current_scene`，**不能用 `change_scene_to_file()`** 进主场景
  （那会把探针当旧场景释放掉），必须手动 `root.add_child()` 并接管 `current_scene`。
- Godot 4 的 `multiplayer.multiplayer_peer` 默认是 `OfflineMultiplayerPeer`，**永不为 null**，
  不能用它判断「是否已在连接」，必须走 `NetworkManager` 的 `connection_succeeded` /
  `connection_failed` 信号。
- headless 默认无上限跑帧，时序断言必须用 `Engine.get_physics_frames()` 计数，
  并在 `_ready()` 里设 `Engine.max_fps = 60` 让墙钟与游戏时间 1:1。
- **先 `is_instance_valid()` 再 `as` 强转**：节点随时可能被 `queue_free()`，
  顺序反了会每帧刷 `Trying to cast a freed object`（数千条/秒，会污染整轮结果）。
- **两端收尾时间要算好**：Host 要等激光推进 3s + 持续 10s 跑完才做最后断言，
  客户端必须在这段时间保持在线（客户端收尾 12 秒、Host 收尾 5 秒）。
  否则 Host 会把 P2 判为掉线，连带 `session_alive` 与 `no_fallback` 一起失败。

### 16.3 波次编排门禁

`tests/wave_probe.gd`（headless 单进程，不需要 ENet）直接 `load("res://scripts/wave_director.gd")`，
断言 **25 项**节奏不变量。与 §16.1 的曲线门禁互不重叠：

| 断言 | 含义 |
|------|------|
| `rhythm_baseline_matches_main` | 编排器里的旧版刷怪常量与 `main.gd` 一致（防校准基准漂移） |
| `phase_shape_normalized` | `PHASE_SHAPE` 四数和恰好 = 拍数 |
| `chapter_mean_matches_legacy` | 1~60 级章节平均速率 ≡ 旧版速率（误差 <0.5%） |
| `crest_over_lull_is_strong` | 峰谷比 ≥ 3.0（张弛没塌） |
| `lull_is_a_real_breather` / `crest_is_a_real_peak` / `surge_is_elevated` / `setup_is_around_baseline` | 四拍各自的绝对高度 |
| `phases_are_distinct` | 四拍形状互不相同 |
| `mean_rate_monotonic` | 平均速率随等级单调不减 |
| `formation_size_in_range` / `formation_interval_in_range` | 阵型规模 2~8、退潮恒 1；间隔 1~5 秒 |
| `throughput_supports_rate` | 闸门撑得住设计速率（否则预算被饿死） |
| `spawn_points_offscreen` | 6 阵型 × 8 规模 × 12 种子，逐点校验出生点在屏外 |
| `screen_cap_respected` / `director_actually_spawns` | 10 分钟模拟不破同屏上限、确实在出怪 |
| `formations_do_not_repeat_back_to_back` | 阵型不背靠背重复（按**排期**统计，不按出场） |
| `chapter_theme_in_range` / `chapter_matches_boss_cadence` | 主题倍率安全、章节号与 Boss 每 5 级对齐 |
| `lull_is_a_trickle_not_a_void` / `lull_trickle_rate_matches_design` | 退潮是涓流而非空屏 |

两类门禁为什么必须分开：有人为了让浪峰更刺激而调大 `PHASE_SHAPE` 时，
`curve_probe` 会全绿（速度没越界），但整局难度已经悄悄涨了——
只有 `chapter_mean_matches_legacy` 能抓住。

---

## 17. 关卡编排（`wave_director.gd`）

改造前 `main.gd` 用两个定时器随机刷怪（`max(1.2 - 0.06L, 0.45)` 秒 1 只 + 每 8 秒补 1 只），
敌人类型 `randi()%3`、出生点四边随机。问题不是慢，而是**没有形状**：
同屏压力是一条恒定直线，且四条压力通道在 L13~L56 全部触顶（见 `docs/level_design_proposal.md`）。

现由 `scripts/wave_director.gd` 接管全部杂兵投放：

| 概念 | 取值 |
|------|------|
| 乐句 | 4 拍 × 16 秒 = 64 秒一章：`起拍 / 涨潮 / 浪峰 / 退潮` |
| 形状倍率 | `[0.910, 1.254, 1.486, 0.350]`，和恰好为 4（章节平均 ≡ 旧版速率） |
| 威胁速率 | `threat_rate(level, phase) = legacy_rate(level) × PHASE_SHAPE[phase]` |
| 阵型 | `line` / `column` / `vee` / `pincer` / `ring` / `swarm`，按拍限定词表 |
| 阵型规模 | `clamp(3 + level/3, 3, 8)`，退潮恒 1 |
| 章节主题 | 压制 / 超载 / 蜂群 / 离子风暴，每 5 级换一个 |

**运行模型**：编排器按 `threat_rate` 累积"威胁预算"，攒够一次阵型的规模就排期投放；
`FORMATION_INTERVAL` 只是闸门，防止预算积压后一次性倒出一大坨。
阵型内部按 `FORMATION_STAGGER = 0.12s` 错峰，出生点全部在屏幕外 `SPAWN_MARGIN = 44px`。

**接入点**：`main.gd` 的 `_tick_wave_director()`（在 `_process` 中，精英/Boss 在场时提前 return）
→ 取出 orders → `_spawn_enemy_at(type, pos)` → 叠加章节主题 → 生成 / `_rpc_spawn_enemy`。

**联机**：编排器**只在 Host 权威运行**（客户端 `_tick_wave_director` 直接 return），
出怪点照旧走既有 `_rpc_spawn_enemy` 广播，因此两端看到的波次天然一致，
**不新增同步包**（只有 `bullet_speed_mult` 一个新字段挂在已有生成包里）。

---

## 18. 移动端适配（2026-09-28）

### 18.1 视口与全屏

| 设置 | 值 | 位置 |
|---|---|---|
| 拉伸模式 | `canvas_items` + `aspect=expand` | `project.godot` |
| 手持方向 | `0`（Landscape） | `project.godot` |
| 沉浸模式 | `immersive_mode=true` | `export_presets.cfg` |
| 边到边 | `edge_to_edge=true` | `export_presets.cfg` |

`edge_to_edge` 必须为 true：Android 15（API 35）起对 targetSdk=35 的应用
强制边到边显示，此时再声明 false 会触发兼容模式把窗口塞进安全区，
表现就是"画面没有全屏"。

### 18.2 视口自适应的访问口（`main.gd`）

| 访问口 | 替代原来写死的 |
|---|---|
| `_screen_center_x()` | 7 处 `Vector2(640, ...)`（精英/Boss 入场、玩家出生点） |
| `_screen_span_x()` | 背景装饰散布范围 `1180` / `1500` |
| `_center_camera_on_viewport()` | `main.tscn` 里 `Camera2D(640, 360)`，监听 `size_changed` |

`BgColor` 已从固定矩形改为满屏锚点（`anchor_right/bottom = 1.0`）。
`mobile_controls.gd` 的摇杆圆心改为贴左下角并监听 `size_changed`。

### 18.3 触摸入口

| 交互 | 控件 | 说明 |
|---|---|---|
| 升级选卡 | `Button`（`_draft_card_buttons`） | 内容层 `MOUSE_FILTER_IGNORE`，`FOCUS_NONE` 不抢焦点 |
| 激光 / 散射 / 闪避 | `SkillBar` 三个 `Button` | 共用冷却遮罩与按下反馈 |
| 移动 | `mobile_controls.gd` 摇杆 | `_unhandled_input`，按钮消费掉的触摸不会漏进摇杆 |

HUD 的 CanvasLayer 在 MobileControls 之后添加，同 layer 下后加的先命中，
所以按钮优先于摇杆区域。

`hud.gd` 的 `_get_design_canvas_size()` 读**真实可视矩形**而不是
ProjectSettings 的设计尺寸——后者只在"视口恰好等于设计尺寸"时成立。
参照物错了会把正常布局误判成越界并刷 `push_error`，
而联机门禁会把运行期 `ERROR:` 计入失败。
