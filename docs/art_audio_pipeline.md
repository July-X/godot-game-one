# 美术与音频管线

本项目的美术与音频**以程序化生成为主**，外部资产只覆盖少数关键形象。

## 固定的生产假设

- 游戏类型：2D 俯视角 Roguelike 弹幕射击
- 视觉：像素风 / 街机高对比，2D 精灵
- 范围规则：先保证联机与战斗节奏稳定，再谈资产替换
- 主原则：**零外部依赖**——引擎刚装好、仓库刚 clone 下来就能跑出完整画面与音效

## 视觉方向

- **基础参考**：Contra / Metal Slug 时代的街机可读性
- **实现**：2D `Sprite2D` + 低分辨率程序化贴图 + 最近邻过滤（`default_texture_filter=0`）
- **光照**：不用实时光照，用颜色与辉光营造高对比
- **可读性优先**：玩家、弹幕、精英、Boss 必须一眼分得开；任何特效不得遮挡弹幕
- **动画**：靠贴图缩放 / 旋转 / 颜色渐变实现，不引入骨骼动画

## 资产来源

### 程序化生成（`scripts/sprite_factory.gd`）

| 资源 | 函数 |
|------|------|
| 玩家飞机（随等级增大） | `create_player_sprite(level)` |
| 敌人（3 种类型） | `create_enemy_sprite(type)` |
| 精英 | `create_elite_sprite()` |
| 子弹（带缓存） | `create_bullet_sprite(is_player, level)` |
| 道具（5 种形状，带缓存） | `create_powerup_sprite(type)` |
| 小行星纹理 | `apply_asteroid_texture(sprite, size)` |
| 爆炸序列帧 | `create_explosion_frames()` |
| 星空背景 | `create_star_field(width, height, count)` |

### 外部资产（仅此几处）

| 资源 | 路径 | 说明 |
|------|------|------|
| Boss 贴图 | `assets/sprites/enemies/boss/boss_01.png`~`boss_05.png` | 每次出场轮换，避免连续重复 |
| 玩家等级外形 | `assets/sprites/player/variants/lv01.png`~`lv05.png` | 每 5 级一档 |
| 图标 | `assets/sprites/ui/icon.png` | 项目图标 |

以上路径固定，新增外形必须沿用命名规则，缺失时才回退程序化占位图。

### 动态绘制（不占贴图）

| 效果 | 实现 |
|------|------|
| 玩家护盾环 | `shield_ring.gd` `draw_arc()` |
| 精英/Boss 护盾光晕 | `shield_circle.gd` |
| 破盾碎裂 | `shield_shatter_burst.gd` |
| 激光光束 | `laser_bolt.gd` `_draw()` 三层线叠加 |
| 闪电链 | `lightning_line.gd` 锯齿线 |
| 终局激光 | `boss_ultimate_laser_visual.gd` 36 段渐变切片 |

## 音频

全部程序化合成，无音频文件：

| 模块 | 说明 |
|------|------|
| `sfx_manager.gd` | 8-bit 风格音效：射击 / 玩家受击 / 敌人受击 / 敌人死亡 / 爆炸 / UI 确认 / UI 选择。玩家射击使用独立播放器池，避免 Boss 战音效抢占 |
| `bgm_manager.gd` | 正弦波合成的标题 / 游戏 / 结果主题，Pad + 贝斯 + 旋律 + 底鼓四层，12 秒循环 |
| Boss 阶段 | 进入 Boss 战切换独立背景色与更高音高/音量的 BGM，结束后恢复 |

## 生产顺序

1. 保持程序化管线的完整性（任何新实体优先程序化出图）
2. 联机链路与战斗节奏打磨
3. 只在程序化表现确实不足时，才为关键形象补外部资产
4. 外部资产一旦引入，必须同时提供程序化回退

## 文档交叉引用

- `docs/architecture.md`：代码结构唯一权威
- `docs/Design_Decisions.md`：冻结的范围与设计意图
- `agents.md`：Agent 轮次工作规则
