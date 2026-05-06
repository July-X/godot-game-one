# Space Bullet Hell — 架构设计文档

> 版本 v1.0.0 | Godot 4.6 | GDScript

---

## 1. 项目概览

**Space Bullet Hell** 是一款俯视角 Roguelike 弹幕射击游戏。玩家操控星际战机，在深空星域中对抗源源不断的敌机与 Boss，通过升级和拾取道具不断提升火力。

| 属性 | 值 |
|------|-----|
| 引擎 | Godot 4.6 |
| 语言 | GDScript |
| 分辨率 | 1280×720 |
| 平台 | PC（鼠标）+ Android/iOS（触屏） |
| 主场景 | `scenes/main.tscn` |

---

## 2. 文件结构

```
├── project.godot              # 引擎配置 + autoload 注册
├── scenes/
│   ├── main.tscn              # 入口场景 (Main Node2D)
│   ├── effects/
│   │   ├── explosion.tscn     # 爆炸特效
│   │   ├── hit_effect.tscn    # 命中特效
│   │   └── screen_shake.tscn  # 屏幕震动
│   ├── entities/
│   │   ├── player.tscn        # 玩家飞机
│   │   ├── enemy.tscn         # 普通敌人
│   │   ├── boss.tscn          # Boss
│   │   ├── bullet.tscn        # 子弹（通用）
│   │   ├── asteroid.tscn      # 陨石
│   │   ├── homing_missile.tscn # 追踪导弹
│   │   ├── laser_bolt.tscn    # 激光弹
│   │   └── powerup.tscn       # 掉落道具
│   └── ui/
│       ├── hud.tscn           # 抬头显示
│       └── mobile_controls.tscn # 移动端摇杆
├── scripts/
│   ├── game_state.gd          # 全局游戏状态 (Autoload)
│   ├── sfx_manager.gd         # 音效管理 (Autoload)
│   ├── bgm_manager.gd         # 背景音乐生成 (Autoload)
│   ├── sprite_factory.gd      # 程序化纹理工厂 (Autoload)
│   ├── leaderboard.gd         # 排行榜持久化 (Autoload)
│   ├── main.gd                # 主场景控制器
│   ├── player.gd              # 玩家飞机逻辑
│   ├── enemy.gd               # 普通敌人 AI
│   ├── boss.gd                # Boss AI
│   ├── bullet.gd              # 子弹物理
│   ├── asteroid.gd            # 陨石
│   ├── powerup.gd             # 掉落道具
│   ├── homing_missile.gd      # 追踪导弹
│   ├── laser_bolt.gd          # 激光弹
│   ├── lightning_line.gd      # 闪电链视觉
│   ├── hud.gd                 # HUD 交互
│   ├── mobile_controls.gd     # 移动端摇杆
│   ├── shield_ring.gd         # 护盾环绘制
│   ├── skill_cooldown_overlay.gd  # 技能冷却三角覆盖层
│   ├── laser_cooldown_overlay.gd  # 激光冷却圆形覆盖层
│   ├── explosion.gd           # 爆炸动画
│   ├── hit_effect.gd          # 命中闪光
│   └── screen_shake.gd        # 屏幕震动
├── docs/                      # 项目文档
├── CHANGELOG.md               # 变更日志
└── README.md                  # 项目说明
```

---

## 3. Autoload 全局系统

### 3.1 GameState (`game_state.gd`)

游戏状态唯一真理源（Single Source of Truth），所有数值状态集中管理：

| 状态分类 | 字段 | 说明 |
|----------|------|------|
| **游戏进程** | `score`, `level`, `kills`, `total_kills`, `game_running`, `death_message` | 分数/等级/击杀 |
| **生命值** | `current_health`, `max_health`, `shield_layers` | 血量 + 护盾层数（最大5层显示） |
| **升级成长** | `shoot_level`, `shoot_speed_level`, `bullet_power_level` | 扩散/射速/威力（上限15） |
| **技能冷却** | `skill_cooldown`(15s), `laser_cooldown`(10s) | 环形散射/激光技能冷却 |
| **Boss 节奏** | `boss_encounter_count`, `post_boss_multiplier`, `last_boss_threshold` | Boss 出场控制 |

**信号**：`score_changed`, `level_changed`, `health_changed`, `game_over`, `powerup_collected`, `boss_spawn_requested`, `shield_changed`, `skill_used`

**核心公式**：

| 公式 | 含义 |
|------|------|
| `kills_for_next_level = 10 + level * 5` | 升级所需击杀数 |
| `bullet_count = min(2 + shoot_level / 3, 8)` | 子弹数量（最多8） |
| `shoot_cooldown = max(0.27 - speed_level * 0.018, 0.08)` | 射击间隔 |
| `bullet_damage = 3 + bullet_power_level` | 基础伤害 |
| `laser_damage = 5 * 2^(level/10)` | 激光伤害（每10级翻倍） |
| `shield_layers += 1`/每10击杀 | 每10击杀获得1层护盾 |

### 3.2 SFX (`sfx_manager.gd`)

音效对象池（12 AudioStreamPlayer），程序化合成：
- `play_shoot()` — 射击音效（扫频波）
- `play_player_hurt()` — 玩家受击
- `play_enemy_death()` — 敌人死亡
- `play_ui_confirm()` / `play_ui_select()` — UI 交互音效
- `play_explosion()` — 爆炸音效

### 3.3 BGM (`bgm_manager.gd`)

程序化背景音乐生成，纯正弦波合成（柔和管风琴风格），12 秒循环：
- **Pad 层**：正弦和弦 + 五度泛音，sin(πt) 呼吸渐强渐弱
- **贝斯层**：低频正弦波带淡入淡出包络
- **旋律层**：正弦波旋律带 warm 淡入淡出 + 立体声 panning
- **底鼓**：正弦低频脉冲（0.75 秒间隔）
- 主音量：-6dB

### 3.4 SpriteFactory (`sprite_factory.gd`)

程序化纹理生成，避免外部美术资源依赖：
- `create_player_sprite(level)` — 玩家飞机（锯齿形，随等级增长）
- `create_enemy_sprite(type)` — 敌人（3 种类型）
- `create_boss_sprite()` — Boss（大眼睛 + 炮塔）
- `create_bullet_sprite(is_player, level)` — 子弹（已缓存）
- `create_powerup_sprite(type)` — 道具（已缓存，5 种形状）
- `apply_asteroid_texture(sprite, size)` — 陨石纹理
- `create_explosion_frames()` — 爆炸序列帧
- `create_star_field(width, height, count)` — 星空背景

### 3.5 Leaderboard (`leaderboard.gd`)

排行榜持久化，使用 `ConfigFile` 存储。

---

## 4. 核心游戏循环

```
main._process(delta)
├── _scroll_background(delta)       # 多层星空视差滚动
├── 如果 Boss 存活 → return        # Boss 战中暂停刷怪
├── _spawn_asteroid()               # 陨石生成（2-5s 随机）
├── _spawn_enemy()                  # 敌人生成（0.2-1.2s 间隔，随等级加速）
└── 每 8 秒额外刷新一波敌人        # 难度递增

player._physics_process(delta)
├── GameState.tick_skill_cooldown(delta)
├── GameState.tick_laser_cooldown(delta)
├── 鼠标相对位移 → _mouse_vel（累积+衰减）
├── velocity = _mouse_vel.limit_length(move_speed)  # 速度上限260
├── 自动面向速度方向（rotation = velocity.angle() + PI*0.5）
├── move_and_slide()
├── 屏幕边界反弹（margin=24px）
├── _shoot()                         # 自动射击
├── 技能触发（Space/Q 键 + 点击按钮）
├── _spawn_homing_missiles(delta)    # 追踪导弹（5级起）
├── _try_pickup_nearby()             # 自动拾取（280px半径）
├── 行走动画 + 无敌闪烁 + 血条更新
```

---

## 5. 玩家系统详解

### 5.1 移动控制

| 平台 | 输入方式 | 速度映射 |
|------|---------|---------|
| PC | 鼠标相对位移 (`event.relative`) | `_mouse_vel += relative * 0.008 * 260`，衰减 `lerp(0, 1.5*dt)` |
| 移动端 | 左侧摇杆 | `velocity = touch_move * move_speed` |

鼠标停止后速度自然衰减至零（类惯性手感）。

### 5.2 子弹系统

**成长阶梯**（`shoot_level` 每提升一级）：

| 等级 | 扩散形态 | 特点 |
|------|---------|------|
| 1-3 | 水平排布 | 最多3发 |
| 4-7 | 水平排布 | 最多5发，间距增大 |
| 8-11 | 微小角度 | 最多6发，每发有角度偏移 |
| 12+ | 扇形扩散 | 最多8发，5角度 × 多排 |

子弹有**墙壁反弹**能力：首次命中屏幕边缘时反弹并加速（×1.3），反射后变为橙色。

### 5.3 追踪导弹（被动，每5级）

| 档位 | 等级 | 发射器数 | 伤害倍率 | 间隔 |
|------|------|---------|---------|------|
| 1 | 5-9 | 1 | ×1.0 | 1.5s |
| 2 | 10-14 | 2 | ×1.5 | 0.75s |
| 3 | 15-19 | 3 | ×2.25 | 0.5s |
| 4 | 20-24 | 4 | ×3.4 | 0.38s |
| 5 | 25+ | 5 | ×5.1 | 0.3s |

导弹自动追踪最近的**狙击型敌人**（`enemy_type=0`），带橙色火焰拖尾。

### 5.4 技能

| 技能 | 触发 | 冷却 | 效果 |
|------|------|------|------|
| 环形散射 | Space / 三角形按钮 | 15s | 16 发子弹环形全向发射 |
| 激光武器 | Q / 圆形按钮 | 10s | 3 发激光弹，击中后闪电链溅射 4 个敌人 |

### 5.5 护盾

每 10 击杀获得 1 层护盾（上限 30 层），显示最多 5 圈。护盾优先吸收伤害。

### 5.6 外观进化

飞机贴图随 `shoot_level` 增大尺寸，引擎光焰随等级增强，尾部挂载导弹发射器精灵。

---

## 6. 敌人系统

### 6.1 三种类型

| 类型 | 移动 | 射击 | 弹幕特点 |
|------|------|------|---------|
| 0 — 狙击手 | 追踪玩家 | 单体高伤 | `ceil(max_health * 0.0625)`，红色单发 |
| 1 — 散射者 | 蛇形移动 | 3 发散弹 | 伤害 0.5，绿色散射 |
| 2 — 环绕者 | 轨道环绕 | 6 发圆形 | 伤害 0.3，紫色圆形弹幕 |

### 6.2 死亡掉落

```python
drop_chance = 0.20  # 20% 掉落概率
powerup_types = ["spread", "speed", "power", "heal", "bomb"]
```

---

## 7. Boss 系统

### 7.1 出场条件

每 30 击杀触发一次 Boss 战（`total_kills % 30 == 0`）。难度加成：`mult = 1 + boss_encounter_count * 0.3`。

### 7.2 核心机制

| 属性 | 默认值 | 说明 |
|------|--------|------|
| 血量 | 50×mult | 随出场次数递增 |
| 护盾 | 80×mult | 3 秒未受伤自动恢复 |
| 愤怒模式 | 血量<50% | 攻击间隔缩短，召唤小兵 |

### 7.3 攻击模式（循环切换）

1. **扇形弹幕** — 7(11) 发扇形
2. **追踪爆发** — 6(10) 发目标追踪
3. **圆环弹幕** — 12(18) 发环形（愤怒时双环）
4. **激光扫射** — 12(18) 发 120°(180°) 扇形
5. **召唤小兵** — 2(4) 个敌人辅助

---

## 8. 道具系统

| 类型 | 颜色 | 效果 |
|------|------|------|
| spread | 绿色星形 | `shoot_level` +1（扩散） |
| speed | 蓝色钻石 | `shoot_speed_level` +1（射速） |
| power | 红色六边形 | `bullet_power_level` +1（威力） |
| heal | 红色爱心 | 回复 10% 最大生命 |
| bomb | 黄色炸弹 | 全屏敌人连续击杀 + 屏幕震动 |

满级（15 级）对应属性时，同类道具自动转为回血。

---

## 9. UI 系统

### 9.1 HUD 布局

```
┌─────────────────────────────────────────────┐
│ 得分 等级        [鼠标操作提示]  [排行榜]   │
│ 血条                                        │
│ 道具: 扩散 8/15  速射 3/15  威力 5/15       │
│                                     ┌──────┐│
│                                     │激光⚡││ ← 激光按钮
│                                     └──────┘│
│                                     ┌──────┐│
│                                     │技能⚡││ ← 环形散射按钮
│                              [摇杆] │  △   ││
│                                     └──────┘│
└─────────────────────────────────────────────┘
```

### 9.2 技能按钮机制

- **PC**：鼠标在 CAPTURED 模式下通过 `_input` 直接检测坐标点击
- **移动端**：通过 `gui_input` 信号捕获任意触点的 `ScreenTouch`，支持**多指同时操作**（左手摇杆 + 右手按钮）

### 9.3 冷却覆盖层

| 按钮 | 覆盖层 | 视觉 |
|------|--------|------|
| 技能按钮 | `skill_cooldown_overlay.gd` | ▲ 三角底部向上绿色填充 |
| 激光按钮 | `laser_cooldown_overlay.gd` | ● 圆形顺时针紫色填充 |

---

## 10. 视觉效果

| 效果 | 实现 | 说明 |
|------|------|------|
| 星空背景 | `main.gd` 三层视差 | 350+180+100 颗星，不同速度 |
| 爆炸 | `explosion.tscn` | 序列帧动画，渐隐 |
| 命中闪光 | `hit_effect.tscn` | 白色渐变圆，缩放淡出 |
| 屏幕震动 | `screen_shake.tscn` | 随机位移衰减 |
| 子弹尾迹 | `bullet.gd`/`homing_missile.gd` `_draw()` | GPU 绘线 |
| 激光光束 | `laser_bolt.gd` `_draw()` | 三层线叠加（核心+内圈+外光晕） |
| 闪电链 | `lightning_line.gd` | 锯齿线 + 0.15s 闪烁 |
| 护盾环 | `shield_ring.gd` `draw_arc()` | GPU 绘弧 |
| 引擎光焰 | player sprite | 规模随等级增长 |

---

## 11. 性能优化措施

| 优化项 | 位置 | 说明 |
|--------|------|------|
| 子弹贴图缓存 | `sprite_factory.gd` `_bullet_cache` | 同类型子弹复用 |
| 道具贴图缓存 | `sprite_factory.gd` `_powerup_cache` | 5 种道具只生成一次 |
| 发光环优化 | `sprite_factory.gd` `_draw_glow_ring()` | 从 9 邻域检测改为圆形距离 |
| 护盾防抖 | `player.gd` `_shield_dirty` | 同帧多次信号只重建一次 |
| 护盾 GPU 绘制 | `shield_ring.gd` | 从 CPU 像素循环改为 `draw_arc()` |
| 炸弹链式调用 | `powerup.gd` `_kill_next()` | 每次只创建 1 个 Timer |
| 道具纹理延迟 | `powerup.gd` `call_deferred("_apply_sprite")` | 不阻塞死亡帧 |
| preload 顶层 | 全部脚本 | 编译时解析 |

---

## 12. 数据流图

```
                      ┌──────────────┐
                      │   GameState   │ (Autoload — 真理源)
                      │  分数/等级/血量 │
                      │  升级/技能/冷却 │
                      └──────┬───────┘
          ┌─────────────────┼─────────────────┐
          │ signals         │ signals         │ signals
     ┌────▼────┐      ┌─────▼──────┐    ┌─────▼─────┐
     │  HUD    │      │   Player   │    │   Main    │
     │ 显示更新 │      │ 移动/射击   │    │ 刷怪/Boss │
     │ 按钮交互 │      │ 导弹/技能   │    │ 背景滚动  │
     └─────────┘      └─────┬──────┘    └───────────┘
                            │ instantiate
              ┌─────────────┼─────────────┐
         ┌────▼────┐  ┌─────▼─────┐  ┌───▼────┐
         │ Bullet  │  │  Missile  │  │ Laser  │
         │ 碰撞检测 │  │  追踪AI   │  │ 闪电链 │
         └────┬────┘  └─────┬─────┘  └───┬────┘
              │ body_entered │             │
         ┌────▼──────────────▼─────────────▼───┐
         │          Enemy / Boss               │
         │    take_damage() → die() → 掉落     │
         └─────────────────────────────────────┘
```

---

## 13. 键位映射

| 键位 | PC | 移动端 |
|------|-----|--------|
| 移动 | 鼠标移动 | 左侧摇杆 |
| 自动射击 | 始终开启 | 始终开启 |
| 技能1（环形散射） | Space / 点击三角按钮 | 点击三角按钮 |
| 技能2（激光） | Q / 点击圆形按钮 | 点击圆形按钮 |
| 释放/捕获鼠标 | ESC | — |
| 重新开始 | R | 点击屏幕 |
| 全屏切换 | F11 | — |

---

## 14. 游戏进程节奏

```
击杀0-9   → 升级护盾(1层)
击杀10    → 第一次升级 + 护盾
击杀20    → 护盾 + 升级
击杀30    → Boss出场！ + 护盾 + 升级
击杀Boss  → 掉落大量道具
循环...
击杀60    → 第二个Boss（更强）
每10击杀 → 护盾+1
每30击杀 → Boss
```

升级曲线：`kills_for_next_level = 10 + level * 5`，中后期升级间隔逐渐拉长。
