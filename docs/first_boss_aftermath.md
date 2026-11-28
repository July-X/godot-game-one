# 普通首只母舰的收场间隔

决定性击毁到下一批普通敌机或陨石之间，至少留出约两秒的游戏时间。原排期的空档计入其中。若一个出生点提前到期，房主暂缓推进波次和陨石计时，保留已排期的敌机、预算和错峰顺序。旧弹照常飞行，玩家可以移动、开火和吸取掉落。暂停与联机换线冻结收场计时，重试从新场景的原定排期开始。

## 击毁后的实际生成时间

同一台机器用 Godot 4.7.2 和种子 `47681` 对照 `cd05a62`。单人从标题进入普通局，双端用实际 ENet（局域网传输）接入普通战斗。脚本准备同一波次状态，实弹碰撞破盾并击毁母舰，随后注入移动，保留原自动主炮、拾取和联机结算。时间从真实退场到引擎创建实体，以有效游戏秒计。双端同时记录墙钟和物理帧，换线冻结时的墙钟等待不计入两秒。

| 单人场景 | 基线首架杂兵 / 首颗陨石 | 候选首架杂兵 / 首颗陨石 |
| --- | ---: | ---: |
| 已排期的四机纵列 | 0.13 / 0.10 秒 | 2.05 / 2.02 秒 |
| 典型退潮，导演还未排期 | 0.52 / 0.75 秒 | 2.02 / 2.25 秒 |
| 已有自然空档 | 2.70 / 3.32 秒 | 2.70 / 3.32 秒 |
| 第 10 级母舰 | 0.13 / 0.10 秒 | 0.13 / 0.10 秒 |

待发纵列在 60 帧固定步进中，两版前三段出生间隔均为 0.23、0.23、0.25 秒。单人并排实拍在相同第 20 帧击毁，之后约 0.42 秒内移动约 87 像素、发射实弹并拾取掉落。两版中，击毁前就在飞的红弹都继续移动。原声和静音片段均为 4.55 秒。

待发纵列的双端基线在房主退场后 0.09 秒生成陨石、0.12 秒生成杂兵。交换 20:9 和 4:3 桌面房主后，候选的对应时间约为 2.00–2.02 秒和 2.03–2.06 秒。两端确认相同的四架杂兵及陨石实体编号。两个槽位都产生房主权威实弹，房主实际吸到专属核心，加入端拾取后射速升到第 2 级。一次 0.50 秒的 LAN（局域网）冻结中三个计时值保留，恢复同一局时更换传输编号；随后两端只见到一份原编队。收场未结束时触发的房主重试，双方进入新局并按开局排期看到新陨石。

典型退潮的无头双端对照中，房主的首架杂兵与首颗陨石分别从 0.50 / 0.74 秒变为 2.00 / 2.24 秒，加入端收到相同实体编号。

独立图形复测中，房主有效时钟为 2.009 / 2.045 秒，加入端独立累计渲染步长为 1.817 / 1.878 秒。收场时长和编队错峰用房主时钟判定。加入端继续比对同一批实体编号、顺序和唯一性，保留本地时钟供诊断。

候选单人六组 48 项、原声绘制 11 项、图形双端 59 项、典型退潮双端 25 项、双端重试 22 项通过。常规双端 40、母舰单人 42 和双端 124、普通双人母舰 108、波次 25、原版裂隙 57、双人变奏牵制 91、双线截击 93 项通过。难度门禁 14 项通过，Godot 4.7.2 的退出资源诊断在基线和候选都出现。

早期探针误用敌机节点名做两端匹配，共享治疗碎片也可能先被另一架飞机吸走。改用实体编号和实际入账属性后复跑。录像用游戏步进等待操作，避免用编码耗时截断移动。短片由脚本操控，手机和平板真机、实体局域网与真人对收场长度的评价待验收。

## 复跑

将 Godot 4.7.2 的可执行文件路径导出为 `GODOT`，以下命令在仓库根目录运行。对照基线时把同名 `.gd`、`.tscn` 探针复制到 `cd05a62` 的干净导出目录，导入后追加 `baseline`。

```sh
probe=res://tests/first_boss_aftermath_probe.tscn
for sample in pending typical quiet later rift retry; do
  "$GODOT" --headless --fixed-fps 60 --path . "$probe" -- solo 25521 "$sample"
done
"$GODOT" --headless --fixed-fps 60 --path . "$probe" -- solo 25528 pending hold
"$GODOT" --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  --write-movie /tmp/aftermath.avi "$probe" -- solo 25523 pending record
```

两端分别保留标准输出。交换房主画幅时用房主 `960x720`、加入端 `1600x720`，去掉两边的 `hold`。双端重试时用 `--headless`，把双方最后的 `pending hold` 改为 `retry`。

```sh
probe=res://tests/first_boss_aftermath_probe.tscn
"$GODOT" --windowed --resolution 1600x720 --audio-driver Dummy --path . \
  "$probe" -- host 25518 pending hold > /tmp/aftermath-host.log 2>&1 &
probe_host=$!
sleep 1
"$GODOT" --windowed --resolution 960x720 --audio-driver Dummy --path . \
  "$probe" -- client 25518 pending hold > /tmp/aftermath-client.log 2>&1
wait "$probe_host"
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25510 boss
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25511
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25512 rift-duo-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25524 rift-wide-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25525 boss-coop
"$GODOT" --headless --path . res://tests/wave_probe.tscn
python3 tests/run_dual_intercept_probe.py /tmp/aftermath-dual-intercept --case both
```
