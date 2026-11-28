# 普通敌机出招

普通主战场的三型杂兵用准备、释放、恢复表现出招。准备时锁定发射点与射线，预告与实际生成的弹体使用同一组角度。预告线固定在世界画布，只在攻击阶段或视口尺寸变化时重绘。锁定期间停止移动，恢复时重新使用原运动模式。手工试飞保留原来的机体、移动和发射时序。

| 敌机 | 前期 | 进阶 |
| --- | --- | --- |
| 针锋 | 窄翼收束，单炮口聚光，沿一条固定方向射出原速单针 | 同一规则 |
| 剪翼 | 横翼展开，双炮口预告三向齐射 | 第二章起在浪峰使用先二后一的三发扫射，两段在准备时画全 |
| 环卫 | 三瓣打开，六发慢弹让出以初始瞄准为中心的 80° 扇区 | 第三章起在涨潮、场内有穿行余量时分为两批，每批三发，沿用同一个安全扇区 |

首次预告从本机准备帧绘制完成起留满 0.45 秒，分段间隔 0.34 秒。联机由房主锁定攻击。加入端准备帧完成绘制后回执，房主同时保证本机与回执后的可读时间。准备最迟 0.95 秒仍不足以发射则跳过该轮，等待绘制和回执不会挤掉后续射击间隔。双方断线等待期间清掉原来的普通敌机预告及本轮普通敌弹。恢复沿用实体快照及当前局号，重新准备的攻击用新序号。其他攻击的弹体恢复规则照旧。

联机协议为 10。大厅在战斗场景加载前双向检查版本，协议 9 显示更新提示。普通敌机只在阶段变化时使用可靠消息，实弹使用已有可靠弹批。敌人数量、血量、掉落、碰撞和弹体伤害保持原值。

## 复跑

在仓库根目录运行，使用 Godot 4.7.2，可用 `GODOT` 指定引擎。专项从游戏标题和大厅进入，固定种子并用脚本操控玩家。两端分别渲染 20:9 和 4:3。`--stabilize-render` 只在桌面窗口停止出帧时由探针请求真实视口帧。延迟样本经过本机 UDP 转发器，双向各加 100 毫秒。混版样本从 `188fb02` 导入真实协议 9，走 UDP 房间列表和真实 ENet 握手。

```bash
godot --headless --path . --editor --import
python3 tests/run_ordinary_enemy_probe.py /tmp/ordinary-enemy-check \
  --case solo --case solo-swap --case lan --case lan-swap \
  --case delayed --case cancellation --case versions --render-peer both --stabilize-render
python3 tests/run_ordinary_enemy_probe.py /tmp/ordinary-enemy-frame-time --case solo --no-capture
bash tests/run_probe.sh 23430
bash tests/run_probe.sh 23431 wide-tablet-host
bash tests/run_probe.sh 23432 wide-tablet-client
python3 tests/run_lobby_entry_probe.py /tmp/ordinary-enemy-entry --normal-runs 2 --remix-runs 2 --start-port 23460
python3 tests/run_dual_intercept_probe.py /tmp/ordinary-enemy-dual --case both-no-pulse --case mismatch
godot --headless --fixed-fps 60 --path . res://tests/first_card_wave_probe.tscn -- graze_focus edge --trial-hint --trial-log --wide
godot --headless --fixed-fps 60 --path . res://tests/opening_trial_probe.tscn -- pierce column --wide
godot --headless --fixed-fps 60 --path . res://tests/offense_window_probe.tscn -- pierce rush --first-wave
```

计时取首次绘出预告的视口帧到本机首次采到实弹的时间。无窗口回归用场景帧代替绘制回执。手感和设备链路仍需真人与真机验证。

## 验收记录

- 单机两种画幅各 64 项通过，双端交换画幅各 151 项通过。两种房主画幅的针锋都锁向正右，玩家向下移动后，权威弹速仍为 `(950, 0)`，两端截图中的预告线也朝右。每轮一发、三发、六发的上限与基线一致。环卫分段样本同一安全扇区内实际移动约 230–238 像素，生命值均为 50。靠场地侧边的样本使用单环。
- 单机预告到首弹为 451.7–469.1 毫秒，正常环回的客机为 468.1–519.2 毫秒，双向各加 100 毫秒时的客机针锋样本为 681.6 毫秒。未绘制预告的样本在约 966 毫秒采到取消，双方没有旧弹补发。陈旧回执、死亡、换目标和真实换线覆盖 58 项。任意延迟下的发射时长无统一保证。
- 真实 9/10 两个房主方向共 22 项，四份日志均在大厅显示更新提示。普通联机 40 项，宽屏交换房主各 57 项，换线探针复跑 26 项。七组正式大厅开局通过。首卡 27 项且逐帧轨迹与基线一致，开场、进攻窗口和双线截击专项通过。
- 同机交错运行两轮 20:9 单机样本并关闭取帧。前期三型的帧间隔 P95，基线为 12.8–18.7 毫秒，改版为 12.8–19.2 毫秒。环卫贴边用例两轮为 31.3 和 32.4 毫秒，基线暂无同位置、同阶段样本。以上为隔离桌面场景的帧间隔，真机和满屏波次性能待测。
