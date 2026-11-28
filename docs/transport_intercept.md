# 普通局运输机截击

首只母舰真正击毁并结束收场后，普通单人或双人局有一次运输机机会。正常波次先排期。待发队列为空、场上至多一架普通敌机，导演和陨石都有至少 1.1 秒的自然空档时，才允许进入。已有的选卡、精英和首领优先。如果它们在运输机飞行中到来，运输机提前离场。最迟到下一只首领请求时结束待触发的机会。

首版从左向右飞过战场上方 26% 高度，速度每秒 300 逻辑像素，初始 12 点生命。两节方货舱和并列尾迹标出航向，入场有一声约 180 毫秒的低鸣。运输机单独飞行，中央保持可通行。击毁掉一份既有治疗，命中和退场复用普通敌机表现。放行或提前退出时结算一次退场。普通导演的投放、击杀进度、分数和掉落流程继续使用原来的规则。

房主保存尚未触发或已消费的局内机会。运输机复用已有实体编号、真实弹体、位置同步和血量载体。协议 10 的现有敌机字典传递机型标记，恢复时只补当前实体与血量。已退出的编号沿用现有拒收逻辑。重试从新场景开始。

## 对照复跑

使用 Godot 4.7.2。固定种子 `47681`，从实际标题进入，脚本准备首战末段并用真实弹体完成破盾和击毁。之后仅布置相同的退潮导演状态，运输机由生产入口自行触发。放行与截击都注入真实横移，截击再使用原主炮发实弹。双端从普通大厅开局，本机环回注入房间发现回调，实际握手、战斗和换线均走生产 ENet（局域网传输）。

| 固定步进样本 | 运输机 | 下一架普通敌机 |
| --- | --- | --- |
| 基线 `e9de6c3` | 原普通局 | 击毁后第 209 帧，种类 2，`(726.85, -44)` |
| 放行 | 2.02 秒进入，6.57 秒飞离，0 份掉落 | 同一帧、同种类与坐标 |
| 截击 | 2.02 秒进入，主炮扣减 12→8→4→0，4.13 秒击毁，1 份治疗 | 同一帧、同种类与坐标 |
| 选卡占用 | 未入场 | 同一帧、同种类与坐标 |

放行和截击的普通击杀均为 0→0，分数 1000→1000，飞机生命值 50。飞离与击毁的回调交叉重放，各自仍只有一次结算。浪峰待发队列在第 120 帧先出普通机。运输机途中遇精英请求则退场一次，无掉落。五组单人专项共通过 48 项。

两种画幅交换房主，图形双端通过 45 和 29 项。在 20:9 房主和 4:3 加入端一组，加入端真实开火后，双方在同一局换线恢复编号 `1008` 的运输机和当时的 7 点生命，只观测到一次入场声音播放。击毁后由房主重试，双方都回到未完成首战的状态。4:3 房主在另一组实际击毁运输机。

补做三条由标题入局、从开场打到首战结束的受保护脚本路线。种子 `1121`、`2257`、`9217` 都在第 72 击触发首战，生产波次原样推进，运输机分别在实际击毁后第 120、120、273 帧自然出现。补充观察脚本与三份出生记录随本轮日志保存。

常规联机 40 项、母舰 124 项、普通敌机出招 111 项、敌机死亡去重 12 项、波次 25 项、裂隙双人 91 项、收场与单人裂隙 23 项、固定首卡 27 项、联机退出 5 项通过。干净导入后，标题和战斗场景均可运行，首战后截击通过 13 项。

## 命令

将 Godot 4.7.2 的可执行文件路径导出为 `GODOT`，在仓库根目录运行。取基线对照时，把两个 `transport_intercept_probe` 文件复制到 `e9de6c3` 的干净导出目录，导入后在 `pass` 后追加 `baseline`。

```sh
probe=res://tests/transport_intercept_probe.tscn
for case in pass hit blocked busy withdraw; do
  "$GODOT" --headless --fixed-fps 60 --path . "$probe" -- solo 7777 "$case"
done
"$GODOT" --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  --write-movie /tmp/transport-pass.avi "$probe" -- solo 7777 pass record
"$GODOT" --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  --write-movie /tmp/transport-hit.avi "$probe" -- solo 7777 hit record
```

交换房主画幅时，将两端分辨率互换，并把两端的 `recover guest-shoots` 换成 `hit`，由房主截击。

```sh
probe=res://tests/transport_intercept_probe.tscn
"$GODOT" --windowed --resolution 1600x720 --audio-driver Dummy --path . \
  "$probe" -- host 7777 recover guest-shoots > /tmp/transport-host.log 2>&1 &
probe_host=$!
sleep 2
"$GODOT" --windowed --resolution 960x720 --audio-driver Dummy --path . \
  "$probe" -- client 7777 recover guest-shoots > /tmp/transport-client.log 2>&1
wait "$probe_host"
"$GODOT" --headless --path . res://tests/wave_probe.tscn
"$GODOT" --headless --path . res://tests/ordinary_enemy_death_probe.tscn
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25550
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25551 boss
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25552 rift-duo-client
```

轨迹、录屏和音轨来自脚本操控的实际引擎。手机和平板真机以及新人对截击机会的辨识度待验收。
