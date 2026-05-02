# Godot Game One - AI 开发指令

> 生成时间：2026-05-02  
> 目标模型：deepseek-v4-flash / Codex / 任意 AI Agent  
> 项目路径：`/Users/zhongxingxing/2026/code/godot-game-one`

---

## 一、项目概述

**类型**：单机 3D 微剧情游戏（Godot 4.x + GDScript）  
**基调**：短篇科幻救援故事，NES/Contra 风格复古动作，3D 实现  
**目标时长**：1 小时以内  
**当前阶段**：Phase 1 收尾 + Phase 2 开端

**核心循环**：
1. 简报 → 2. 穿越敌占走廊 → 3. 与敌人战斗 → 4. 到达终点 → 5. 逃脱

**操作**：
- 移动：`ui_left` / `ui_right` / `ui_up` / `ui_down`
- 跳跃/取消：`ui_cancel`
- 射击/确认：`ui_accept`

---

## 二、当前完成状态

### ✅ Phase 1 已完成
- [x] 玩家移动、跳跃、射击
- [x] 敌人巡逻、追击、触碰伤害、死亡
- [x] 基础关卡（地面、墙壁、出生点、出口、剧情触发器）
- [x] HUD 显示（血量、目标、剧情、调试信息）
- [x] 出口锁定/解锁流程（全灭敌后解锁）
- [x] 游戏状态管理（running / finished / failed）
- [x] 重启流程（按 Enter 重试）
- [x] 窗口修复（960x540，canvas_items 拉伸）
- [x] 关卡视觉增强（障碍物、掩体、视觉标记）
- [x] 击中反馈（粒子特效、闪白/闪红）
- [x] 相机震动（受击时）
- [x] 结算/游戏结束画面

### ❌ Phase 1 未完成
- [ ] **添加基础主菜单/标题画面** ⬅ **优先级最高**

### 📋 Phase 2 待实现
- [ ] 标题画面（"按 Enter 开始"）
- [ ] 开场简报序列
- [ ] 关卡内多个剧情触发器节点
- [ ] 关卡结束结果画面（带统计）
- [ ] 状态间的平滑过渡

---

## 三、项目结构

```
godot-game-one/
├── scenes/
│   ├── main.tscn          # 主场景（已配置）
│   ├── entities/          # 实体场景
│   │   ├── player.tscn
│   │   ├── enemy.tscn
│   │   └── projectile.tscn
│   ├── levels/            # 关卡场景
│   │   └── level_01.tscn
│   └── ui/               # UI 场景
│       └── hud.tscn
├── scripts/
│   ├── main.gd            # 主场景控制器
│   ├── player.gd          # 玩家逻辑
│   ├── enemy.gd           # 敌人 AI
│   ├── projectile.gd      # 子弹逻辑
│   ├── hud.gd             # HUD + 结算画面
│   ├── game_state.gd      # 全局游戏状态（Autoload）
│   ├── level_01.gd        # 关卡 01 逻辑
│   └── hit_effect.gd      # 击中特效
├── assets/                # 美术占位符（待填充）
├── docs/                  # 设计文档
│   ├── Development_Plan.md
│   ├── Design_Decisions.md
│   └── art_audio_pipeline.md
└── project.godot          # Godot 项目配置
```

---

## 四、核心代码文件说明

### `scripts/game_state.gd`（Autoload 单例）
- 管理全局状态：`current_health`, `max_health`, `run_state`, `objective_text`, `story_line`
- 信号：`health_changed`, `objective_changed`, `story_line_changed`, `run_state_changed`
- **必须保留为 Autoload**，不要移除 `GameState` 单例

### `scripts/main.gd`（主场景控制器）
- 连接玩家/关卡/HUD 信号
- 管理敌人计数、出口解锁、结算触发
- 处理重启逻辑（F5 或 Enter）

### `scripts/player.gd`（玩家角色）
- `CharacterBody3D`，支持移动/跳跃/射击
- 受击无敌帧：`hit_invincibility = 0.45s`
- 相机震动：`shake_intensity = 0.18`

### `scripts/enemy.gd`（敌人 AI）
- 巡逻范围：`patrol_distance = 3.0`
- 追击范围：`aggro_range = 6.0`
- 触碰伤害：`touch_damage = 1`

### `scripts/hud.gd`（HUD 和结算）
- 显示血量、目标、剧情文本、调试信息
- `show_result_screen(state, story, kills, total)` 显示结算画面

---

## 五、开发指令（按优先级排序）

### 🎯 任务 1：添加标题画面（Phase 1 收尾）

**目标**：在游戏启动时显示标题画面，按 Enter 开始游戏。

**实现要求**：
1. 创建 `scenes/ui/title_screen.tscn`（CanvasLayer）
2. 包含：
   - 游戏标题（"GODOT GAME ONE"）
   - "PRESS ENTER TO START" 闪烁提示
   - 简单背景（深色 + 网格或渐变）
3. 修改 `main.gd`：
   - 新增状态 `title` 和 `playing`
   - 初始显示标题画面，隐藏游戏场景
   - 按 Enter 后切换到游戏场景
4. 更新 `GameState.run_state` 枚举（添加 `title`）

**验证**：
```bash
godot --headless --path . --autoquit 5
```
（应在 5 秒内加载到标题画面无报错）

---

### 🎯 任务 2：开场简报序列（Phase 2 开端）

**目标**：在标题画面后、游戏开始前，显示科幻救援故事的简报。

**实现要求**：
1. 创建 `scripts/briefing.gd`（控制简报显示）
2. 简报内容（示例）：
   > "指挥中心，这里是特工 7 号。\n"
   > "敌方势力已占领中继站，\n"
   > "你需要穿越敌占走廊，\n"
   > "清除守卫，激活终端，\n"
   > "然后撤离。\n"
   > "按 ENTER 开始行动。"
3. 简报界面：
   - 全屏半透明黑色遮罩
   - 逐行显示文本（可用 `Timer` 控制节奏）
   - 按 Enter 跳过/继续
4. 修改流程：`标题画面` → `简报` → `游戏`

**文档同步**：
- 更新 `docs/Development_Plan.md`（勾选 Phase 2 子任务）
- 更新 `CHANGELOG.md`

---

### 🎯 任务 3：多段剧情触发器（Phase 2 增强）

**目标**：在关卡内增加多个剧情触发点，增强叙事体验。

**实现要求**：
1. 在 `level_01.tscn` 中增加 2-3 个 `Area3D` 剧情触发器
2. 每个触发器显示不同文本：
   - 触发器 1（入口）："走廊尽头有动静，保持警惕。"
   - 触发器 2（中段）："中继站信号增强，就在前方。"
   - 触发器 3（Boss 前）："敌方增援抵达，准备战斗。"
3. 触发器只触发一次（用 `bool` 标记）
4. 修改 `level_01.gd` 支持多触发器管理

**验证**：
- 运行游戏，走过每个触发区域，确认文本正确显示
- 重启后触发器重置

---

### 🎬 任务 4：结果画面增强（Phase 2 打磨）

**目标**：在结算画面显示更详细的统计和剧情收尾。

**实现要求**：
1. 修改 `hud.gd` 的 `show_result_screen()`：
   - 显示：击杀数、总敌数、用时（可选）
   - 成功时显示："任务完成。中继数据已安全回收。"
   - 失败时显示："任务失败。重启并重新尝试。"
2. 添加"返回标题"按钮（成功/失败后按 Enter 返回标题）
3. 修改 `main.gd` 支持从结果画面返回标题

**文档同步**：
- 更新 `README.md`（"下一个里程碑"章节）

---

## 六、代码规范

### GDScript 编码规则
1. **类型标注**：函数参数和返回值必须标注类型
   ```gdscript
   func take_damage(amount: int) -> void:
   ```

2. **信号命名**：用动词过去时
   ```gdscript
   signal took_damage(current_health, max_health)
   signal died
   ```

3. **导出变量**：用 `@export` 暴露关键参数
   ```gdscript
   @export var move_speed: float = 6.5
   ```

4. **注释规范**：
   - 核心函数写用途和设计意图
   - 复杂分支写"为什么"而不是"做了什么"
   - 用 `##` 写文档注释（支持 Godot 文档生成）

### 提交规范
- 用中文写提交信息
- 格式：`feat: ...` / `fix: ...` / `docs: ...`
- 一个提交一个清晰目标
- 实现 + 文档 + 验证同批完成

---

## 七、禁止事项

❌ **不要做的事**：
1. 不要引入联网、多人、联机房间或后端服务
2. 不要改为开放世界（保持短流程）
3. 不要大幅重排目录结构（除非确认必要）
4. 不要提交无关的大规模格式化噪声
5. 不要只改代码不更新文档（设计变更必须先改文档）
6. 不要移除 `GameState` Autoload 单例
7. 不要改变核心玩法循环（移动/射击/战斗/撤离）

---

## 八、验证流程

### 每次改动后必须验证：
1. **编辑器加载**：
   ```bash
   godot --headless --path . --quit
   ```
   （无报错即为通过）

2. **游戏可玩性**：
   - 启动游戏 → 显示标题 → 按 Enter → 能玩 → 能结算 → 能重启

3. **信号连接**：
   - 确保 `main.gd` 中所有 `connect()` 调用都有 `has_signal()` 或 `has_method()` 保护

4. **场景切换**：
   - 标题 → 简报 → 游戏 → 结果 → 标题（完整循环无卡死）

---

## 九、文档同步规则

**每次功能改动，必须同步更新**：
1. `CHANGELOG.md`（记录本次改动摘要）
2. `docs/Development_Plan.md`（勾选已完成子任务）
3. `README.md`（如范围/操作/下一个里程碑变化）
4. `docs/Design_Decisions.md`（如设计决策变化）

**禁止**：
- 只在代码里隐含设计决策
- 只改代码不更新文档

---

## 十、推荐开发顺序

```
1. 标题画面（任务 1）          ← 当前最高优先级
   ↓
2. 开场简报（任务 2）
   ↓
3. 多段剧情触发器（任务 3）
   ↓
4. 结果画面增强（任务 4）
   ↓
5. 进入 Phase 3（美术生产）    ← 后续扩展
```

---

## 十一、关键文件快速参考

| 文件 | 作用 | 修改频率 |
|------|------|----------|
| `scripts/main.gd` | 主场景控制器 | 高 |
| `scripts/player.gd` | 玩家逻辑 | 中 |
| `scripts/enemy.gd` | 敌人 AI | 中 |
| `scripts/hud.gd` | HUD + 结算 | 高 |
| `scripts/game_state.gd` | 全局状态 | 低 |
| `scenes/main.tscn` | 主场景 | 中 |
| `docs/Development_Plan.md` | 开发计划 | 每次功能改动 |
| `CHANGELOG.md` | 变更日志 | 每次提交 |

---

## 十二、常见问题处理

### Q1：Godot 启动时崩溃？
- 检查 `project.godot` 中 Autoload 路径是否正确
- 运行 `godot --headless --verbose --path .` 查看详细错误

### Q2：信号连接失败？
- 确保所有 `connect()` 前有 `has_signal()` 检查
- 使用 Godot 编辑器的"信号"面板可视化调试

### Q3：场景切换卡死？
- 检查 `get_tree().change_scene_to_file()` 路径是否正确
- 确保新场景中所有节点都已正确配置

---

## 十三、联系与反馈

- 项目所有者：zhongxingxing
- 项目路径：`/Users/zhongxingxing/2026/code/godot-game-one`
- 遇到问题：先查 `docs/Design_Decisions.md`，再查 `CHANGELOG.md`

---

**祝开发顺利！逐步推进，保持可玩性优先。**
