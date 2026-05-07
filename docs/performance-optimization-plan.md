# Space Bullet Hell — 性能优化计划

> 版本 v1.0 | 基于 v1.1.0 代码分析

---

## 1. 概述

本文档梳理当前游戏已知的性能瓶颈，按优先级排序并给出具体优化方案。每个方案标注预估工作量（S/M/L）和影响范围，便于按计划逐步实施。

---

## 2. 优先级定义

| 级别 | 说明 | 对帧率影响 |
|------|------|-----------|
| P0 | 必做，显著掉帧根源 | ≥20% |
| P1 | 推荐，累积帧时间明显 | 10-20% |
| P2 | 可做，高频场景下优化 | 5-10% |
| P3 | 锦上添花 | <5% |

---

## 3. 优化项清单

### P0 — 对象池化（Object Pooling）

**问题**：子弹/导弹/爆炸/命中特效/闪电链全部使用 `instantiate()` + `add_child()` + `queue_free()`，无对象池。高等级时每秒创建/销毁数十个对象，GC 停顿导致掉帧。

**涉及文件**：
| 文件 | 问题点 | 创建速率 |
|------|--------|---------|
| `scripts/player.gd` | 子弹 instantiate（_shoot / _fire_ring_shotgun） | 最高 8发/0.08s |
| `scripts/enemy.gd` | 敌方子弹 instantiate | 最高 6发/0.4s |
| `scripts/boss.gd` | Boss 弹幕 instantiate | 最高 18发/次 |
| `scripts/bullet.gd` | hit_effect 每次碰撞创建 | 高频 |
| `scripts/homing_missile.gd` | hit_effect | 高频 |
| `scripts/laser_bolt.gd` | LightningLine + hit_effect | 链式溅射 |
| `scripts/lightning_line.gd` | 每次闪电链 new() + add_child() | 高频 |
| `scripts/explosion.gd` | 每次爆炸 instantiate | 中频 |
| `scripts/powerup.gd` | 掉落物 instantiate | 低频 |

**方案**：为各对象类型建立独立的对象池（`scripts/pool.gd` 单例），用 `acquire()` / `release()` 替代 `instantiate()` / `queue_free()`。保留动态扩容，初始容量按类型预估。

**工作量**：L（1-2 天）  
**预估提升**：GC 停顿减少 80%+

---

### P0 — 屏幕外对象裁剪

**问题**：超出屏幕的子弹/敌人依然参与物理碰撞检测和 `_physics_process`，造成大量无效计算。

**涉及文件**：`scripts/bullet.gd`、`scripts/enemy.gd`、`scripts/asteroid.gd`、`scripts/homing_missile.gd`

**方案**：扩大判定范围后在 `_physics_process` 顶部加 `set_process(false)` / `set_physics_process(false)`，或用 `VisibilityNotifier2D` / `VisibleOnScreenNotifier2D` 自动暂停屏幕外对象。

**工作量**：M（半天）  
**预估提升**：高弹幕密度下 physics 帧时间减少 30%+

---

### P0 — 大量 `_draw()` 调用

**问题**：`homing_missile.gd`、`laser_bolt.gd` 每物理帧调用 `queue_redraw()`，`lightning_line.gd` 每帧调用。每条 trail 都重新 rasterize canvas。

**涉及文件**：
- `scripts/homing_missile.gd:41` — queue_redraw() 每物理帧
- `scripts/laser_bolt.gd:34` — queue_redraw() 每物理帧
- `scripts/lightning_line.gd:23` — queue_redraw() 每帧

**状态**：已实现帧门控（每 2 帧 redraw），但仍有优化空间。

**方案**：
1. 用 `Line2D` 节点替代 `_draw()` 绘制拖尾（Line2D 是 GPU 加速的，不触发 canvas rerasterize）
2. 或进一步降低 redraw 频率到每 3-4 帧（高帧率下 15-20fps 更新拖尾已足够）

**工作量**：M（半天）  
**预估提升**：Canvas redraw 开销减少 60%+

---

### P1 — 组查询缓存

**问题**：多处代码每帧调用 `get_tree().get_nodes_in_group()` 遍历敌人/子弹/道具组，复杂度 O(n) 每次全量遍历。

**涉及文件**：
| 文件 | 行号 | 查询内容 | 执行频率 |
|------|------|----------|---------|
| `scripts/boss.gd:109` | dodge_nearby_bullets | "player_bullets" | 每 6 帧 |
| `scripts/player.gd:263` | _try_pickup_nearby | "powerups" | 每 4 帧 |
| `scripts/homing_missile.gd:56` | _find_target | "enemies" | 每帧 |
| `scripts/laser_bolt.gd:74` | _find_nearest_enemy | "enemies" | 每帧（链式） |

**方案**：
1. 将高频查询缓存到数组变量，在 `add_to_group` / `remove_from_group` 时更新缓存
2. 或用 Area2D `overlaps_area()` / `intersect_shape()` 空间查询替代全量遍历
3. 对 "enemies" 查询增加帧门控（已有部分实现）

**工作量**：M（半天）  
**预估提升**：高敌人数量下每帧 CPU 减少 15%+

---

### P1 — 碰撞检测优化

**问题**：Godot 默认对所有开启碰撞的 Area2D 做 pairwise 检测。大量子弹 × 大量敌人的碰撞对组合数 = O(n²)。

**方案**：
1. 使用碰撞层（collision layers/masks）分离玩家子弹 vs 敌方子弹，减少无效 pair 检测
2. 在 `project.godot` 中配置物理层：

```
玩家子弹 → layer 1, mask 2 (敌人)
敌方子弹 → layer 2, mask 1 (玩家)
敌人     → layer 2, mask 1 (玩家)
玩家     → layer 1, mask 2 (敌人)
```

**工作量**：S（1-2 小时）  
**预估提升**：高密度场景下物理检测时间减少 40%

---

### P1 — 预生成音频流

**问题**：6 种音效每次播放时重新生成 `AudioStreamWAV`，`_generate_sweep` / `_generate_tone` / `_generate_noise` 每调用一次都执行采样循环 + `PackedByteArray` 分配。

**涉及文件**：`scripts/sfx_manager.gd`

**状态**：已实现预生成（`_ready()` 中生成一次并缓存），但可进一步优化。

**方案**：
1. 将预生成的 `AudioStreamWAV` 导出为 `.wav` 资源文件直接 `preload`，消除运行时生成
2. 或保持当前预生成方式，确认无问题

**工作量**：S（1 小时）  
**预估提升**：消除射击时的微小帧时间抖动

---

### P2 — 属性/修饰符动画优化

**问题**：多处使用 `create_tween().tween_property()`，大量 Tween 实例创建。死亡时全屏 20+ 爆炸 + 10+ 掉落物的 tween 同时运行。

**方案**：
1. 用 `AnimationPlayer` 替代大量独立 `create_tween()` 调用
2. 或限制全局并发 Tween 数量

**工作量**：S（2-3 小时）  
**预估提升**：瞬间创建开销减少 30%

---

### P2 — 最小化自动加载

**问题**：当前 5 个 Autoload（GameState / SFX / BGM / SpriteFactory / Leaderboard）全部开机加载。

**方案**：评估是否可将 BGM 和 Leaderboard 改为延迟加载（`ResourceLoader.load_threaded` 或场景内 `@onready`）。

**工作量**：S（1 小时）  
**预估提升**：启动时间减少，中期内存减少

---

### P2 — 光照/阴影检查

**问题**：确认项目未启用不需要的光照和阴影，特别是 CanvasItem 的 `light_mask` 和 `z_index`。

**方案**：检查 `project.godot` 渲染设置，关闭 `rendering/2d/options/use_2d_particle_emitter_feedbacks` 等无用选项。

**工作量**：S（30 分钟）  
**预估提升**：GPU 开销微优化

---

### P3 — 屏幕震动优化

**问题**：`screen_shake.gd` 使用随机位移 + tween 衰减，多震源叠加时可能创建多个同类效果。

**方案**：使用单例震动管理器，合并震源强度，避免叠加创建多个震动节点。

**工作量**：S（1 小时）

---

### P3 — Texture Import 优化

**问题**：22 个 AI 生成 PNG 未设置 VRAM 压缩格式（默认无损），在移动端可能导致纹理内存占用偏高。

**方案**：在 `.godot/import_defaults/` 或导入设置中将像素画类纹理设为 `ETC2 / ASTC` 压缩。

**工作量**：S（30 分钟）

---

## 4. 已完成的优化

| 优化项 | 提交 | 说明 |
|--------|------|------|
| 陨石纹理缓存 | a9849a2 | 首次生成后缓存，避免每颗陨石 6 轮像素循环 |
| 尾迹帧门控 | a9849a2 | queue_redraw 从每帧降为每 2 帧 |
| Boss 闪避帧门控 | a9849a2 | dodge_nearby_bullets 每 6 帧执行 |
| 玩家拾取帧门控 | a9849a2 | _try_pickup_nearby 每 4 帧执行 |
| SFX 音频预生成 | a9849a2 | 6 种音效流 in _ready | 
| 道具脉动优化 | 0db04fe | 移除 Time.get_ticks_msec，改用累加时间 |
| 炸弹连锁间隔 | 0db04fe | 击杀间隔 0.05s → 0.08s |
| 护盾光环改用 draw_arc | 41c0432 | 替代 GradientTexture2D 矩形纹理 |
| 摇杆加速度 | 24ae340 | 移动端 lerp 平滑加速 |

---

## 5. 实施计划

### Phase 1 (P0 — 预计 2-3 天)
1. 创建 `scripts/pool.gd` 通用对象池
2. 子弹池化（player + enemy）
3. 特效池化（hit_effect + explosion + lightning_line）
4. 屏幕外对象裁剪（VisibleOnScreenNotifier2D）

### Phase 2 (P1 — 预计 1-2 天)
1. 碰撞层分离（layer/mask 配置）
2. 组查询缓存（GroupCache 单例）
3. Trail 改用 Line2D 替代 _draw

### Phase 3 (P2 — 预计 1 天)
1. 预生成音频导出为 .wav 资源
2. Tween 管理优化
3. Autoload 延迟加载评估

### Phase 4 (P3 — 按需)
1. 屏幕震动管理器
2. Texture import 压缩设置
3. 渲染设置审计
