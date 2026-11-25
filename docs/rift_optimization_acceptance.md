# 裂隙航道五轮优化验收

基线 `3ad40d1961b79fe1fdf85bd62084e67adb4cd51f`。每轮的 `rift-optimization-rN` 标签指向对应提交，使用 `git rev-parse rift-optimization-rN` 获取完整 SHA。

## 第 1 轮 · 截断或绕行

首卡后前两波保持 90 物理帧间隔和原有队形。蓄力机用暖色夹角标记，中路用淡色线提示，弹道和触控区域维持现有布局。房主确认蓄力中的真实发射者被击破并取消其三弹发射指令后，两端在击破位置显示一次短反馈。断线恢复只还原当前蓄力状态。

命令与结果：

- 在临时源码副本运行 `godot --headless --path . --editor --import --quit`，另走项目入口与主战场加载，无脚本错误。
- `python3 tests/run_rift_build_probe.py /tmp/rift-optimizations/r1-build` 记录 14 条同种子选卡、实弹、命中和失血轨迹。两种画幅的两波里，中路对照均让聚团后排实发三弹，溅射路线各截断一次。早期断言误将中路自动射击排除在外，修正后用实际记录复核。提前击破单列。
- `PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19811 rift-wide-host`，同端口依次换 `rift-wide-client`、`rift-timeout-host`、`rift-timeout-client`。每次房主 25 项、加入端 22 项通过，覆盖 90 帧排期、触控叠层、截断反馈与重连。
- 两个进程运行 `godot --headless --path . res://tests/lobby_start_probe.tscn -- {host,client} 19812 rift`。首跑加入端提前退出，房主未观察到首个位置报告；回归探针等待双方到场后复跑为房主 7 项、加入端 4 项。

证据为本机脚本操控和环回联机。手机真机与无说明真人试玩留待独立验收。

## 第 2 轮 · 猎手可选奖励

进猎手段时用同一行提示可绕行，以及击破后母舰首次破盾多 1 秒。首次击毁与奖励兑现各显示一次短提示。提示实时由房主发出，重连保留战斗进度和剩余破盾时间，恢复时不补播旧提示。

- 临时源码副本干净导入。运行 `godot --headless --fixed-fps 60 --path . res://tests/rift_route_probe.tscn`，标题入口和后续重试共 32 项通过。绕行、击毁后的首破盾、第二次破盾、重试分别为 270、330、270、270 帧。
- `PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19821 rift-wide-host`，再跑 `rift-wide-client`。每次房主 30 项、加入端 27 项。两端分别用实弹完成最后一击，交换 20:9 和 4:3，并在击毁后重连。提示未重播，首破盾仍为约 330 帧。
- 同端口 `rift-timeout-host` 跑绕行，房主 28 项、加入端 25 项。两次约 270 帧，均无奖励提示。首跑探针脚本有语法和类型错误，修正后结果如上。
