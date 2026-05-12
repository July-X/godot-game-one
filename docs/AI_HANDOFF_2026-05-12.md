# AI 接力开发记录（2026-05-12）

## 当前版本方向

- 当前主线是 `v1.3.1` 后的联机 Boss 战修复与打磨。
- 项目已经从单机垂直切片扩展到 2 人 Wi-Fi LAN/Harmony 发现 + ENet 战斗同步。
- 联机角色命名固定为 `P1/P2`：
  - `P1`：Host / 房主 / ENet server peer `1`。
  - `P2`：唯一 Client。不要直接把 Godot 的真实 client peer_id 显示到 UI 上。

## 本轮已完成但未提交的重点改动

- 移除 Boss 战旧代码：
  - 删除旧 Boss Buff 顶部卡片 UI。
  - 删除无消费者的 `boss_active`、`boss_defeated`、`boss_reward_applied` 等旧信号/状态。
- Boss 终局技：
  - Boss 血量首次低于或等于 10% 时触发 `究极激光炮`。
  - 2 秒蓄力，0.8 秒宽束推进逃离窗口。
  - 0.8 秒结束后仍在激光束内的玩家被秒杀。
  - Host 权威触发和结算，Client 只显示同步视觉。
- 联机死亡判定：
  - P1/P2 单方死亡只移除该玩家并切换敌人目标。
  - 只有 P1/P2 全灭才 Game Over。
  - P1 被 Boss 激光秒杀时不能断网、不能切回单机。
- 联机 UI：
  - HUD 记分牌、实时排行榜、历史排行榜统一显示 `P1/P2`。
  - 注意：ENet client 的真实 peer_id 不一定是 `2`，HUD 必须把非 `1` 的唯一 client 显示为 `P2`。
- Boss 生成兜底：
  - Boss 触发时如果精英仍在场，`main.gd` 只记录 `_pending_boss_level`。
  - 精英死亡后通过 `_consume_pending_boss_spawn()` 消费 pending，避免旧精英引用或 queued-for-deletion 节点继续阻塞 Boss 生成。
  - `_is_elite_blocking_boss_spawn()` 会清理无效/已排队删除的 `_elite` 引用。
  - `_has_active_boss()` 会清理无效/已排队删除的 `_boss` 引用，避免旧 Boss 引用阻塞下一次生成。

## 关键文件

- `scripts/main.gd`
  - 联机玩家生成、死亡、despawn、Game Over 判定。
  - Boss 终局激光视觉 RPC 广播。
- `scripts/game_state.gd`
  - 玩家独立状态、分数、伤害结算。
  - 联机模式下不应由单个本地死亡直接发全局 `game_over`。
- `scripts/hud.gd`
  - 记分牌和排行榜显示。
  - `_peer_label()` 必须按 P1/P2 槽位显示，不要直接显示真实 peer_id。
- `scripts/boss.gd`
  - Boss 三阶段、10% 终局激光炮触发与 Host 伤害结算。
- `scripts/boss_ultimate_laser_visual.gd`
  - 程序化蓄力光圈和宽束激光视觉。
- `scripts/player.gd`
  - `force_kill()` 用于 Boss 终局激光秒杀。

## 验证命令

```bash
git diff --check
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20
godot --headless --path . --export-debug Android "android/Space Bullet Hell.apk"
```

主场景 headless 退出时仍会出现 RID/CanvasItem 泄漏提示，目前不是本轮改动引入的阻塞错误。

## 当前工作区注意事项

- `.claude/settings.local.json` 只有本地格式化变化，不应混入玩法提交。
- 当前 APK 路径固定为 `android/Space Bullet Hell.apk`。
- 修改联机逻辑时不要把“玩家死亡”和“玩家断线”混为一条流程：
  - 死亡：保留联机会话，切换目标，等待队友。
  - 断线：才允许 `_fallback_to_single_player()`。

## 下一轮优先检查

- 真机双端验证 P1 被 Boss 终局激光击杀后，P2 是否继续游戏且不会切单机。
- 真机双端验证 P2 记分牌和排行榜是否显示为 `P2`，不要出现 `P3` 或真实 ENet peer_id。
- 如继续做 Boss 终局激光，需要确认 2 秒蓄力提示和 0.8 秒宽束推进在 Android 小屏上足够明显。
- 验证 Level 5 Boss 触发：如果 Boss 触发时精英仍在场，杀死精英后必须补发 Boss；不要再被旧 `_elite` 引用卡住。
