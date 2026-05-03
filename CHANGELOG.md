# 更新日志

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
