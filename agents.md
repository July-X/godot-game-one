# Codex Agent 指南（godot-game-one）

本文件用于约束 Codex/AI Agent 在本仓库的工作方式，目标是把项目目标、设计决策、实现边界、测试门槛和文档更新要求固定下来，避免后续工作偏离当前项目方向。

## 0. Skill 自动调用规则

- 默认由 Agent 自行判断是否需要调用 skill，不要求用户手动指定。
- 遇到库、框架、SDK、API、CLI、云服务文档问题时，优先使用 `context7-mcp`，再回答实现细节。
- 遇到 bug、崩溃、异常行为、回归、性能退化时，优先使用 `diagnose` 或 `systematic-debugging`。
- 遇到 Godot 相关任务时，优先使用最贴合的 Godot skill：
  - 代码、场景、脚本、架构：`godot-development` / `godot-gdscript-patterns` / `godot-best-practices`
  - UI：`godot-ui`
  - 导出、构建、平台设置：`godot-export-builds`
- 遇到创建或改造 skill 的任务时，使用 `skill-creator` 或 `write-a-skill`。
- 如果多个 skill 都适用，选最小、最具体、最贴合当前任务的那一个或那一组。
- 只有在任务边界不清、且继续推进会有明显风险时，才向用户追问 skill 选择。
- 每次实际调用了 skill，要在回复里简短说明使用了哪个 skill，以及原因。

## 1. 项目基线

- **引擎与语言**：Godot 4.6，GDScript。
- **游戏类型**：`Space Bullet Hell` —— 2D 俯视角 Roguelike 弹幕射击。
- **视觉方向**：像素风 / 街机高对比，2D 精灵，美术与音频**全部程序化生成**。
- **联机**：2 人本地合作（P1 房主 / P2 加入），Wi-Fi LAN + 鸿蒙近场发现 + ENet 战斗同步。
- **主场景**：`scenes/ui/title_screen.tscn`（入口分流），战斗场景 `scenes/main.tscn`。
- **代码结构权威**：`docs/architecture.md`。该文档与代码冲突时以代码为准，并回头修文档。
- **固定项目目录**：`/Users/zhongxingxing/2026/code/godot-game-one`。
- **历史包袱**：`backup_3d/` 是已废弃的旧 3D 版本存档，**不是**设计依据，不要参考。

## 2. 开发优先级

1. 先保证联机链路稳定（发现 → 连接 → 权威同步 → 死亡/断线分离）。
2. 再保证弹幕射击手感与精英 / Boss 战斗节奏。
3. 最后做外部美术资产替换与性能优化。

## 3. 代码改动规则

- 只做与当前任务直接相关的最小改动，避免无关重构。
- 优先保留当前的项目结构，不在未确认的情况下大幅重排目录。
- 玩法、镜头、UI、美术、音频的设计决策必须同步写入文档，不允许只留在对话里。
- 任何会影响玩家体验的变更，优先更新：
  - `README.md`
  - `docs/architecture.md`（代码结构变更时）
  - `docs/Development_Plan.md`
  - `docs/Design_Decisions.md`
  - `docs/art_audio_pipeline.md`
  - `CHANGELOG.md`
  - 本文件 `agents.md`
- 核心脚本要保持可读，复杂逻辑要写清楚用途和设计意图。
- 如需调整范围，优先保持"一个完整短流程"而不是扩大为开放式大工程。

## 4. 内容边界

- 当前项目是 **2 人**联机合作 + 单机，不引入互联网服务器、云后端、matchmaking、账号系统。
- 不追求开放世界，不做大型系统堆叠。
- 核心是**弹幕射击手感**与**联机同步稳定性**，新增系统必须先证明不破坏这两者。
- 当前阶段已完成：
  - 玩家移动 / 自动射击 / 受击 / 死亡 / 护盾充能
  - 三种敌人 + 小行星
  - 精英四阶段、Boss 三阶段 + 终局究极激光炮
  - 属性成长、掉落物、Boss 持久强化
  - HUD、标题画面、联机大厅
  - 2 人 Wi-Fi LAN / 鸿蒙近场联机（Host 权威）
  - 双进程 headless 联机回归探针

## 5. 文档与设计固定要求

- 每次新增或改变关键设计，必须同步更新设计文档，不能只在代码里隐含。
- 设计决策优先落在以下文件：
  - `docs/Design_Decisions.md`
  - `docs/art_audio_pipeline.md`
  - `README.md`
- 如果玩法、镜头、关卡结构、目标时长、艺术方向发生变化，必须先改文档，再改实现。
- 任何未来的"继续做"都应先读取这些文档，确认当前版本约束，再开始编码。

## 6. 测试与验证门槛

- 至少执行受影响模块的可用性检查。
- Godot 相关改动优先做编辑器或命令行载入验证。
- 若未能验证，必须在结果说明中明确标注原因与风险。
- 任何引擎版本、资源格式或场景结构变化，必须重新检查项目是否可加载。

**联机改动必须跑回归门禁**（不允许只做静态检查）：

```bash
# 推荐：一条命令，自动起双进程 + 收口退出码 + 扫描引擎报错，全绿才 exit 0
tests/run_probe.sh 7788
```

手工跑（需要实时看日志时）：

```bash
godot --headless --path . res://tests/lan_probe.tscn -- host 7788   &
godot --headless --path . res://tests/lan_probe.tscn -- client 7788
```

判定标准：**`[PROBE] ... VERDICT SUMMARY pass=N failed=0` 且两个进程退出码都是 0**，
`run_probe.sh` 还会额外把 `SCRIPT ERROR` 和运行期 `ERROR:` 计入失败。
当前共 36 项断言（host 22 + client 14）。

涉及 `hud.gd` / 场景结构的改动，还必须额外跑主场景运行验证
（`--quit` 不覆盖 `_ready` / `_process` 链路）：

```bash
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20
```

## 7. 工作约束

- 默认优先使用 `rg` 搜索代码和文档。
- 除非 `rg` 不可用，否则不要用 `grep` / `find` 作为首选检索方式。
- 修改文件时默认使用 `apply_patch`，不要用 `cat` / `echo` 之类的方式直接写文件。
- 修改前先读相关文件，再动手改，避免盲改。
- 修改前先阅读相关文件，不要直接大改。
- 新增内容时，优先补文档，再补实现。
- 保持仓库内文档入口清晰，README 必须能引导到核心设计文档。
- 如果后续扩展到模型、动画、音效，必须遵守已有美术方向，不要引入风格冲突。

## 8. 提交规范

- 提交信息使用中文，建议格式：
  - `feat: ...`
  - `fix: ...`
  - `docs: ...`
- 一个提交只表达一个清晰目标，尽量实现 + 文档 + 验证同批闭环。
- 禁止提交无关的大规模格式化噪声。

## 9. 常用命令

```bash
godot --headless --path . --quit
```

## 10. 注释与设计意图要求

- 核心脚本、导出字段、关卡控制函数要写清楚用途和设计意图。
- 复杂分支要补充"为什么"而不是只写"做了什么"。
- 设计文档优先覆盖：
  1. 游戏定位与范围
  2. 关卡与玩法闭环
  3. 美术、动画、音频管线
  4. 验证与发布路径

## 11. AI Agent 接力开发方向（2026-09-27 校准）

### 11.1 当前阶段定位

项目已从「3D 微剧情动作游戏」转型为 **2D 俯视角 Roguelike 弹幕射击**，
单机 + 2 人 LAN 联机两条链路均已闭环。当前阶段是**打磨与防回归**，不是铺新系统。

### 11.2 工作顺序

1. 联机稳定性：双机帧率、掉线自愈、同步包体积
2. 弹幕手感与精英 / Boss 战斗节奏
3. 关卡节奏与敌人构成扩充
4. 外部美术资产替换（最后做，且必须保留程序化回退）

### 11.3 文档同步规则

- 每次功能改动的实现与文档更新必须同批完成。
- `CHANGELOG.md` 记录每次改动摘要。
- `docs/architecture.md` 是代码结构权威，新增/重命名文件必须同步。
- `docs/Development_Plan.md` 反映当前阶段进展。
- 所有新功能必须先过设计文档，再过代码。

### 11.4 验证流程

- 每完成一项任务，用 `godot --headless --path . --quit` 验证项目可加载。
- **联机相关改动必须跑 `tests/lan_probe.gd` 双进程回归探针**（见 §6）。
- 出现加载错误立即修复，不累积。
- 无法验证时在结果中明确标注原因。

## 12. 项目现状（2026-09-27 校准）

- **单机闭环 ✅**：标题 → 战斗 → 精英 / Boss 波次 → 结算
- **联机闭环 ✅**：2 人 Wi-Fi LAN / 鸿蒙近场发现 + ENet 战斗同步，Host 权威
- **程序化管线 ✅**：贴图、音效、BGM 全部程序化，零外部资源依赖
- **联机回归门禁 ✅**：`tests/run_probe.sh` + `tests/lan_probe.gd`，**36 项断言**（host 22 + client 14），一条命令收口退出码

**下一步可选扩展**：
1. 双机联机性能压测（加入端 ≥ 60 FPS 的量化结论）
2. 鸿蒙真机双端联调与稳定性压测
3. 关卡节奏扩充
4. 清理 `backup_3d/` 历史存档
5. 子弹/命中特效的真对象池（需先补齐归还时的节点状态重置）

**禁止事项**：
- ✅ ~~不引入联网、多人、后端服务~~ → **已解除**：2026-05-09 引入 2 人 Wi-Fi LAN 合作模式（无互联网、无云后端）
- ❌ 不引入云服务器、matchmaking、后端账号系统
- ❌ 不引入互联网联机
- ❌ 不改为开放世界
- ❌ 不大幅重排目录结构
- ❌ 不提交无关格式化噪声

## 13. 多人模式工作约束（2026-05-09）

- 通讯方案固定为 **Wi-Fi 热点 LAN + Godot ENet**，不再讨论蓝牙/星闪方案。
- 多人模式新增文件：
  - `scripts/network_manager.gd`（Autoload）
  - `scenes/ui/lobby.tscn` + `scripts/lobby.gd`
- 多人模式改动文件：
  - `scripts/player.gd`（authority 守卫；权威必须 `set_multiplayer_authority(peer_id, true)` 递归设置）
  - `scripts/main.gd`（多玩家生成 + 玩家位置显式同步，**不使用 MultiplayerSynchronizer**）
  - `project.godot`（注册 NetworkManager autoload）
- 敌人逻辑服务器权威，不在客户端重复执行；客户端只做渲染和输入。
- 任何 `@rpc("any_peer")` 函数体内必须有 `if not multiplayer.is_server(): return` 守卫。
- **玩家位置同步走 `main.gd` 的手工管线**（`_batch_sync_players` / `_rpc_sync_player_states` /
  `_rpc_report_player_state`），不要在 `player.tscn` 挂 `MultiplayerSynchronizer`：
  引擎场景复制会因客户端晚挂载 `main.tscn` 而持续丢包，原因见
  `docs/architecture.md` §11.7。
