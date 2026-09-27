# Space Bullet Hell

Godot 4.6 的 2D 俯视角 Roguelike 弹幕射击游戏，支持 2 人 Wi-Fi LAN / 鸿蒙近场联机合作。

## 参考文档

- [Agent 指南](./agents.md)
- [架构设计](./docs/architecture.md) ← 代码结构的唯一权威
- [开发计划](./docs/Development_Plan.md)
- [设计决策](./docs/Design_Decisions.md)
- [美术与音频管线](./docs/art_audio_pipeline.md)
- [Harmony 插件契约](./docs/Harmony_Plugin_Contract.md)
- [联机回归探针](./tests/lan_probe.gd)

## 目标

- **类型**：2D 俯视角弹幕射击（bullet hell）+ Roguelike 成长
- **基调**：太空星际战，高对比街机可读性
- **视觉**：像素风 / 程序化生成，零外部美术依赖
- **单局时长**：无固定时长，靠升级曲线和死亡结束
- **技术目标**：Godot 4.6，GDScript，程序化美术与音频，1280×720 设计视口

## 入口链路

```
scenes/ui/title_screen.tscn   ← 项目主场景
├── 单机 → scenes/main.tscn
└── 联机 → scenes/ui/lobby.tscn → scenes/main.tscn
```

## 核心循环

1. 鼠标移动控制飞机（带惯性衰减），自动射击
2. 击杀敌人 → 积分 + 升级（`10 + level*5` 击杀升一级）
3. 每 20 击杀触发一次精英战（护盾四阶段）
4. 每 5 级触发一次 Boss 战（三阶段 + 终局究极激光炮）
5. 拾取掉落物（扩散 / 速射 / 威力 / 治疗 / 炸弹 / 核心）
6. Boss 死亡 → Host 权威发放持久强化
7. 死亡结算

## 操作

| 操作 | PC | 移动端 |
|------|-----|--------|
| 移动 | 鼠标移动（惯性） | 左侧虚拟摇杆 |
| 射击 | 自动 | 自动 |
| 技能 1（环形散射，15s） | `Space` / △ 按钮 | △ 按钮 |
| 技能 2（激光，10s） | `Q` / ○ 按钮 | ○ 按钮 |
| 释放鼠标 | `ESC` | — |
| 全屏切换 | `F11` | — |

## 项目布局

```
godot-game-one/
├── scenes/
│   ├── main.tscn               # 主战斗场景 (Node2D)
│   ├── entities/               # player / enemy / elite / boss / bullet
│   │                           # asteroid / homing_missile / laser_bolt / powerup
│   ├── effects/                # explosion / hit_effect / screen_shake
│   └── ui/                     # title_screen / lobby / hud / mobile_controls
├── scripts/
│   ├── main.gd                 # 主场景控制器（刷怪、实体同步、联机权威）
│   ├── player.gd + player/     # 玩家逻辑，已拆分为 4 个子模块
│   ├── game_state.gd           # Autoload，全局状态真理源
│   ├── boss.gd / elite.gd      # Boss 三阶段 / 精英四阶段
│   ├── network_manager.gd      # Autoload，ENet 连接生命周期
│   └── harmony_bridge.gd       # Autoload，鸿蒙近场发现桥接层
├── tests/
│   ├── lan_probe.gd            # 双进程 headless 联机回归探针
│   └── lan_probe.tscn
├── docs/
├── backup_3d/                  # 旧 3D 版本存档（已废弃，勿参考）
└── project.godot
```

## 美术与音频

全部**程序化生成**，不依赖外部资源：

- **贴图**：`scripts/sprite_factory.gd` 生成玩家/敌人/精英/子弹/道具/爆炸序列帧/星空
- **例外**：Boss（`boss_01`~`boss_05`）与玩家等级外形（`lv01`~`lv05`）使用仓库 AI 生成的 PNG
- **音效**：`scripts/sfx_manager.gd` 程序化合成 8-bit 风格音效
- **BGM**：`scripts/bgm_manager.gd` 程序化合成正弦波主题音乐

## 联机模式

- **规模**：固定 2 人合作（P1 房主 / P2 加入）
- **权威**：Host 权威。敌人、Boss、弹幕、伤害结算全在 Host，Client 只做插值与 HUD
- **发现**：鸿蒙近场发现（`HarmonyBridge` → 原生插件 `NsdManager`），桌面调试回退 ENet/热点
- **战斗链路**：始终 Godot ENet
- **命名**：UI 一律显示 `P1`/`P2` 槽位，**不暴露真实 ENet peer_id**（Client 的真实 id 是随机 32 位数）
- **死亡 ≠ 断线**：单方死亡只移除该玩家并切换敌人目标；全灭才 Game Over；只有断线才回退单机

## 已实现功能

### 核心玩法
- ✅ 鼠标惯性移动 + 屏幕边界反弹
- ✅ 自动射击（8 级扩散形态阶梯 + 子弹撞墙反弹）
- ✅ 追踪导弹被动成长（5 级起，5 个档位）
- ✅ 三种敌人（狙击手 / 散射者 / 环绕者）+ 小行星
- ✅ 5 种掉落物 + 磁吸加速曲线 + 拾取 Toast

### 成长系统
- ✅ 三维属性成长（扩散 / 速射 / 威力），上限 50 级
- ✅ 护盾 8 秒自动充能（取代旧版击杀里程碑护盾）
- ✅ Boss 死亡持久强化（激光 CD / 额外子弹 / 额外伤害 / 移速 / 护盾强度）

### 精英 / Boss
- ✅ 精英四阶段（护盾压制 → 破盾暴露 → 裂隙召唤 → 濒死三连）
- ✅ 破盾 4 秒易伤窗口（承伤 ×1.25）+ HUD 集火提示
- ✅ 精英固定 12 掉落半弧喷射 + 联机轮转归属
- ✅ Boss 三阶段（压制校准 / 裂隙展开 / 核心过载）
- ✅ Boss 终局究极激光炮：每损失 25% 血量触发，2s 蓄力 → 3s 尖端推进 → 10s 持续束；内圈秒杀、外圈 10HP/s
- ✅ Boss 血量按玩家 DPS 动态估算，目标 TTK 42 秒

### 联机
- ✅ 2 人 Wi-Fi LAN 合作，Host 权威同步
- ✅ 实体主同步包压缩为 5 字段 `PackedFloat32Array`，护盾/朝向拆独立包
- ✅ 客户端漏怪自愈（未知 entity_id 限频请求快照）
- ✅ Boss 阻塞兜底：精英在场时 Boss 触发挂起，精英死亡后补发
- ✅ 双进程 headless 回归探针（`tests/lan_probe.gd`，28 项断言）

### 其他
- ✅ HUD（血量/属性条/记分牌/排行榜/技能冷却/Boss 阶段条）
- ✅ 移动端虚拟摇杆 + 技能按钮
- ✅ 屏幕震动、命中特效、爆炸序列帧

## 已知遗留

- `backup_3d/` 是旧 3D 版本完整存档，**已废弃**，文档与实现均不再参考
- `docs/architecture.md` 之外的历史设计文档（`AI_HANDOFF_2026-05-12.md` 等）按时间点记录，允许保留当时状态

## 验证

```bash
# 项目可加载
godot --headless --path . --quit

# 主场景可运行（含 _ready / _process 链路）
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20

# 联机回归（两个终端，端口可换）
godot --headless --path . res://tests/lan_probe.tscn -- host 7788
godot --headless --path . res://tests/lan_probe.tscn -- client 7788
```

## 开发规则

- 任何玩法、联机、镜头、美术方向的变更，必须先改文档再改实现
- 保持 README 作为入口，详细决策放在设计文档，代码结构以 `docs/architecture.md` 为准
- 联机改动必须区分「死亡」与「断线」两条流程
