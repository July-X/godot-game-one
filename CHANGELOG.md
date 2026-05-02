# 更新日志

## [0.3.0] - 2026-05-02

### 新增
- **标题画面**：游戏启动时显示 "GODOT GAME ONE" 标题、"PRESS ENTER TO START" 闪烁提示
- **游戏流程**：标题画面 → 按 Enter → 进入游戏；结算后按 Enter 返回标题
- **game_state 状态**：新增 `"title"` 状态，`reset_run()` 默认设为 `"title"`

### 文档
- 新增 `docs/AI_Development_Instructions.md`（详细开发指令、禁止事项、验证流程）
- `Development_Plan.md`：Phase 1 所有子任务标记完成，进入 Phase 2

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
