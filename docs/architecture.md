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
│   │   ├── bullet.tscn        # 子弹（通用，池化）
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
│   ├── pool.gd                # Autoload，通用对象池
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
│   │   └── action_router.gd        # 输入分发
│   ├── enemy.gd / elite.gd / boss.gd
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
│   └── lan_probe.tscn
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
| `Pool` | `pool.gd` | 通用对象池（bullet / hit_effect） |
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
| 成长 | `shoot_level`, `shoot_speed_level`, `bullet_power_level` | 单项上限 **50** |
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

**触发节奏**：

- 精英：`total_kills % 20 == 0` 且未等于 `last_elite_threshold`（`add_kill()`）
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

死亡掉落：`drop_chance = 0.20`，类型为 `spread` / `speed` / `power` / `heal` / `bomb`。

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
| **玩家断线** | 清理网络实体 / 同步缓存 / 对象池 → `NetworkManager.disconnect_network()` → 提示固定停留 5 秒 → 异步重载为单人场景 |

### 11.6 Boss 生成兜底

Boss 触发时若精英仍在场，`_on_boss_spawn_requested` 只记录 `_pending_boss_level`；
精英死亡后通过 `_consume_pending_boss_spawn()` 消费。
`_is_elite_blocking_boss_spawn()` 与 `_has_active_boss()` 都会清理无效或
`is_queued_for_deletion()` 的引用，避免旧引用永久阻塞 Boss 生成。

---

## 12. 性能优化措施

| 优化项 | 位置 | 说明 |
|--------|------|------|
| 子弹贴图缓存 | `sprite_factory.gd` `_bullet_cache` | 同类型复用 |
| 道具贴图缓存 | `sprite_factory.gd` `_powerup_cache` | 5 种道具只生成一次 |
| 对象池 | `pool.gd` | bullet(40) / hit_effect(20) 预分配 |
| 护盾防抖 | `player.gd` `_shield_dirty` | 同帧多次信号只重建一次 |
| 护盾 GPU 绘制 | `shield_ring.gd` | `draw_arc()` 而非 CPU 像素循环 |
| 道具纹理延迟 | `powerup.gd` `call_deferred("_apply_sprite")` | 不阻塞死亡帧 |
| 客户端性能档 | `main.gd` `_apply_client_perf_profile()` | 非服务器端降级 |
| 实体同步包压缩 | `main.gd` | 5 字段 `PackedFloat32Array` + 护盾/朝向独立包 |

---

## 13. 数据流图

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

## 14. 键位映射

| 键位 | PC | 移动端 |
|------|-----|--------|
| 移动 | 鼠标移动 | 左侧摇杆 |
| 自动射击 | 始终开启 | 始终开启 |
| 技能 1（环形散射） | `Space` / △ 按钮 | △ 按钮 |
| 技能 2（激光） | `Q` / ○ 按钮 | ○ 按钮 |
| 释放鼠标 | `ESC` | — |
| 全屏切换 | `F11` | — |

---

## 15. 验证

```bash
# 1. 项目可加载
godot --headless --path . --quit

# 2. 主场景可运行（覆盖 _ready / _process 链路，--quit 不够）
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20

# 3. 联机回归探针（双进程，真实 ENet 回环，28 项断言）
godot --headless --path . res://tests/lan_probe.tscn -- host 7788   &
godot --headless --path . res://tests/lan_probe.tscn -- client 7788
```

探针注意事项：

- 探针自身是启动时的 `current_scene`，**不能用 `change_scene_to_file()`** 进主场景
  （那会把探针当旧场景释放掉），必须手动 `root.add_child()` 并接管 `current_scene`。
- Godot 4 的 `multiplayer.multiplayer_peer` 默认是 `OfflineMultiplayerPeer`，**永不为 null**，
  不能用它判断「是否已在连接」，必须走 `NetworkManager` 的 `connection_succeeded` /
  `connection_failed` 信号。
- headless 默认无上限跑帧，时序断言必须用 `Engine.get_physics_frames()` 计数，
  并在 `_ready()` 里设 `Engine.max_fps = 60` 让墙钟与游戏时间 1:1。
