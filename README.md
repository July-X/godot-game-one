# Space Bullet Hell

Godot 4.6 的 2D 俯视角 Roguelike 弹幕射击游戏，支持 2 人 Wi-Fi LAN / 鸿蒙近场联机合作。

## 参考文档

- [Agent 指南](./agents.md)
- [架构设计](./docs/architecture.md) ← 代码结构的唯一权威
- [开发计划](./docs/Development_Plan.md)
- [普通单人局从首卡到首只 Boss 的实测与试玩单](./docs/boss_pace_baseline.md)
- [设计决策](./docs/Design_Decisions.md)
- [关卡设计方案](./docs/level_design_proposal.md) ← 乐句节奏 / 阵型 / 章节主题
- [美术与音频管线](./docs/art_audio_pipeline.md)
- [裂隙母舰的画面设计与验收](./docs/art_audio_pipeline.md#裂隙母舰可读性)
- [Harmony 插件契约](./docs/Harmony_Plugin_Contract.md)
- [弹幕射击可玩性调研](./docs/research_bullet_hell_fun_2026-09-27.md)
- [标题与联机大厅](./docs/entry_ui.md)
- [联机回归门禁](./tests/run_probe.sh)
- [波次编排门禁](./tests/wave_probe.tscn)

## 目标

- **类型**：2D 俯视角弹幕射击（bullet hell）+ Roguelike 成长
- **基调**：太空星际战，高对比街机可读性
- **视觉**：像素风 / 程序化生成，零外部美术依赖
- **单局时长**：无固定时长，靠升级曲线和死亡结束
- **技术目标**：Godot 4.6，GDScript，程序化美术与音频，1280×720 设计视口

## 入口链路

```
scenes/ui/title_screen.tscn   ← 项目主场景
├── 单人出击 → 标准战斗
├── 双人联机 → 创建房间 / 加入附近房间 → 普通合作或裂隙航道
└── 试飞任务
    ├── 首卡试飞 → 试飞 A / 试飞 B
    ├── 进攻窗口 → 45 秒单人试飞
    ├── 开场试飞 → 开始 90 秒试飞 / 近身试飞 A / 近身试飞 B
    └── 裂隙航道 → 原版 / 变奏 / 双线截击（仅双人）
```

「试飞任务」内的「首卡试飞」供观察者选 A 或 B。两版直接进入首选，重试沿用所选版本。完整试飞仍可直接运行 `scenes/first_card_trial.tscn`，从一级继续到首领战。[复跑与 Android 导出](docs/first_card_trial.md) · [五分钟试玩单](docs/first_card_playtest.md)

「进攻窗口」是 45 秒试飞。开火前击毁蓄力的后排，下一轮少一股实际弹流。中路可绕行，飞行中可重试，选卡前可勾选「旧版对照」。[复跑和盲试玩](docs/offense_window_trial.md)

「开场试飞」提供完整的 90 秒试飞，先用普通主炮试一次截断，再从贯穿、溅射、威力中选择。也可点「近身试飞 A」或「近身试飞 B」，直接体验 18 秒的精英对照。[开场路线](docs/opening_trial.md) · [近身对照](docs/elite_close_trial.md)

「裂隙航道」可选择原版或变奏。变奏让首卡后的第二波沿同侧入场，由纵列先发，中路仍可绕行。母舰发出定向脉冲后，可绕到亮出的盾沿用实弹加速破盾。双线截击需要两人从同一试飞入口进入。[航道规则](docs/rift_route.md) · [双线截击](docs/dual_intercept.md)

## 核心循环

1. 鼠标移动控制飞机（带惯性衰减），自动射击
2. 击杀敌人 → 积分 + 升级（`10 + level*5` 击杀升一级，每级三选一卡）
3. **关卡是一段 4 拍乐句**：起拍 → 涨潮 → 浪峰 → 退潮，各 16 秒，敌人以**阵型**成组进场
   （一字横排 / 两侧夹击 / V 字合围 / 弧线弹幕环 / 纵列 / 蜂群），详见 [关卡设计方案](./docs/level_design_proposal.md)
4. 每 `20 + level*2` 击杀触发一次精英战（护盾四阶段）
5. 每 5 级触发一次 Boss 战（三阶段 + 终局究极激光炮）；每 5 级同时切换一次**章节主题**
   （压制 / 超载 / 蜂群 / 离子风暴，弹速与敌人韧性此消彼长）
6. 拾取掉落物（扩散 / 速射 / 威力 / 治疗 / 炸弹 / 核心）
7. 贴着敌弹飞行可**擦弹**叠射速；`Shift` 闪避
8. Boss 死亡 → Host 权威发放持久强化
9. 死亡结算（双人联机有队友和剩余次数时先倒地，队友在 15 秒内入圈即可救援）

## 操作

| 操作 | PC | 移动端 |
|------|-----|--------|
| 移动 | 鼠标移动（惯性） | 按住安全区左半的空白处，拖动浮动摇杆 |
| 射击 | 自动 | 自动 |
| 技能 1（环形散射，15s） | `W` / 散射按钮 | 散射按钮 |
| 技能 2（激光，10s） | `Q` / ○ 按钮 | ○ 按钮 |
| 闪避 | `Shift` | 闪避按钮 |
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
│   ├── battle/                # 主场景、局内状态、敌人、弹体和试飞
│   ├── player/                # 玩家主控、输入、移动、射击和受击
│   ├── network/               # 联机、重连、发现及鸿蒙桥接
│   ├── ui/                    # 标题、大厅、战斗界面和移动端控件
│   ├── audio/                 # 音乐与音效
│   ├── visuals/               # 通用特效、配色与贴图
│   ├── persistence/           # 排行榜存储
│   └── generate_assets/       # 离线素材生成
├── tests/
│   ├── run_probe.sh             # 联机回归门禁入口（起双进程 + 收口退出码 + 扫报错）
│   ├── lan_probe.gd             # 双进程联机回归（40 项断言）
│   └── lan_probe.tscn
├── docs/
├── backup_3d/                  # 旧 3D 版本存档（已废弃，勿参考）
└── project.godot
```

## 美术与音频

游戏直接使用仓库内的贴图和程序化音源。

- **贴图**：`scripts/visuals/sprite_factory.gd` 生成玩家/敌人/精英/子弹/道具/爆炸序列帧/星空
- **例外**：Boss（`boss_01`~`boss_05`）与玩家等级外形（`lv01`~`lv05`）使用仓库 AI 生成的 PNG
- 普通命中和普通敌机击毁使用离线生成的 PixelFX 图集。冰蓝火花标记接触处，暖色碎片标记击毁中心。[实拍与素材归属](./docs/art_audio_pipeline.md#普通命中与普通敌机击毁的-pixelfx-对照)
- **音效**：`scripts/audio/sfx_manager.gd` 程序化合成 8-bit 风格音效
- **背景音乐**：巡航与 Boss 使用同一原创四音动机，保留两段各自的编排和循环。激光预警、玩家受击时音乐短暂衰减。[战斗界面、背景与音画复跑](./docs/art_audio_pipeline.md#战斗界面远行与裂隙)

## 联机模式

- **规模**：固定 2 人合作（P1 房主 / P2 加入）
- **权威**：Host 权威。敌人、Boss、弹幕、伤害结算全在 Host，Client 只做插值与 HUD
- **发现**：鸿蒙近场发现（`HarmonyBridge` → 原生插件 `NsdManager`），桌面调试回退 ENet/热点
- **战斗链路**：始终 Godot ENet
- 双人战场固定为 1280×720。两架飞机都能飞到同一条边，宽屏两侧延伸星空，界面随各自窗口布局。
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
- ✅ 三维属性成长：扩散（上限 10）/ 速射（上限 15）/ 威力（上限 50，掉落满后转治疗）
- ✅ 护盾 8 秒自动充能（取代旧版击杀里程碑护盾）
- ✅ Boss 死亡持久强化（激光 CD / 额外子弹 / 额外伤害 / 移速 / 护盾强度）

### 精英 / Boss
- ✅ 精英四阶段（护盾压制 → 破盾暴露 → 裂隙召唤 → 濒死三连）
- ✅ 破盾 4 秒易伤窗口（承伤 ×1.25）+ HUD 集火提示
- ✅ 精英固定 12 掉落半弧喷射 + 联机轮转归属
- ✅ Boss 三阶段（压制校准 / 裂隙展开 / 核心过载）
- ✅ Boss 持盾时主动出招。打破护盾后有 4.5 秒本体输出窗口。终局激光在蓄力末段锁向，已经发出的束保持原有伤害与轨迹。[周期护盾与复跑](docs/boss_shield_rhythm.md)
- ✅ Boss 血量按玩家 DPS 动态估算，目标 TTK 42 秒

### 联机
- ✅ 2 人 Wi-Fi LAN 合作，Host 权威同步
- ✅ 实体主同步包压缩为 5 字段 `PackedFloat32Array`，护盾/朝向拆独立包
- ✅ 玩家位置由 `main.gd` 显式同步（4 字段 / 45Hz / 两端插值），不依赖引擎场景复制
- ✅ 客户端漏怪自愈（未知 entity_id 限频请求快照）
- ✅ Boss 阻塞兜底：精英在场时 Boss 触发挂起，精英死亡后补发
- ✅ 双进程联机回归（`tests/run_probe.sh`，40 项断言），两端分别核对 P1/P2 机体和核心拾取者

### 其他
- ✅ HUD（血量/属性条/记分牌/排行榜/技能冷却/Boss 阶段条）
- ✅ 移动端浮动摇杆、技能按钮和安全区触摸布局
- 第一档雨燕按飞船所属槽位显示。房主 P1 冰蓝单中线，加入者 P2 淡紫双标记。完整榜单在结算时显示。
- ✅ 屏幕震动、命中特效、爆炸序列帧
- ✅ 渲染上限 120fps + 物理插值（物理 60Hz），GL Compatibility 后端（本机实测 276fps）

## 已知遗留

- `backup_3d/` 是旧 3D 版本完整存档，**已废弃**，文档与实现均不再参考
- `docs/architecture.md` 之外的历史设计文档（`AI_HANDOFF_2026-05-12.md` 等）按时间点记录，允许保留当时状态

## 验证

```bash
# 项目可加载
godot --headless --path . --quit

# 主场景可运行（含 _ready / _process 链路）
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20

# 联机回归门禁（推荐：一条命令，自动起双进程并判成败）
tests/run_probe.sh 7788

# 固定构图，核对布局、特效寿命、碰撞和开火挂点
godot --headless --fixed-fps 60 --path . res://tests/combat_visual_probe.tscn
```

手工跑探针（需要实时看日志时，两个终端）：

```bash
godot --headless --path . res://tests/lan_probe.tscn -- host 7788
godot --headless --path . res://tests/lan_probe.tscn -- client 7788
```

## 开发规则

- 任何玩法、联机、镜头、美术方向的变更，必须先改文档再改实现
- 保持 README 作为入口，详细决策放在设计文档，代码结构以 `docs/architecture.md` 为准
- 联机改动必须区分「死亡」与「断线」两条流程
