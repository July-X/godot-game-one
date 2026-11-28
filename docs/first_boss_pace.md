# 普通局首只首领节奏

普通单人和双人战斗在团队第 72 次实际击毁时请求首只首领。已经开始的精英先打完，随后使用已有两秒入场调度。两端顶部显示「首领接近」，伴随短暂的暖色边框和一组下行提示音。同一个时段的乐句提示让位给入场提示。升级仍由实际击毁数推进，第 85 击给第 5 级升级，第 10 级请求下一只首领。

72 次门槛保留了固定路线中的首卡练习及两次精英机会。首领沿用第 5 级配置与现有火力评估，入场时玩家持有的卡和武器可能与旧时点不同。预告通过房主已有快照同步，计时随普通战斗暂停。裂隙航道和固定试飞仍使用各自调度。

## 对照口径

- A 为 `43a52d69ebb653917e1606e0378353cb18dc9273`。D 只把 `0d46ab2` 的 `enemy.gd` 移入 A，隔离普通击毁去重。B 为已验收的 `0d46ab2bc06d1788cc68902861cad4fc698e317d`。C 是本轮候选。
- Godot 4.7.2 从实际标题或大厅进入普通战斗。1121 沿用原地瞄准和超时选卡，前两阵真实交火结束后才启用座机保护。1122、1123 使用交替短距离摇杆移动和数字键选卡。瞄准锁定后可以用实际走位和闪避躲开光束。双人是两个本机 ENet 进程，1122 的两架飞机分别驱动。
- 逐局保留首卡显示与选择、首领请求、被精英阻塞的物理帧、预告可见、实体入场和本体首伤。累计击毁以普通机和精英的实体死亡信号另行核对。空窗累计取首卡显示后至入场，房主或单人本机视野里没有敌机，且场上没有活跃敌弹的采样帧。累计出弹统计房主生成的非表现弹体，受击取采样到的机体生命下降。固定种子和操控方式无法锁定掉落、命中定格和联机处理时机，始终保留逐局数据。

## 计时与归因

1121 原位路线各事件单位为物理帧。双人取房主进程。

| 样本 | 首卡 | 选卡 | 请求 | 精英等待 | 入场 | 本体首伤 |
|---|---:|---:|---:|---:|---:|---:|
| 单人 A | 418 | 1017 | 3470 | 0 | 3590 | 4220 |
| 单人 D | 745 | 1344 | 5184 | 0 | 5304 | 5696 |
| 单人 B | 735 | 1334 | 5089 | 0 | 5209 | 5835 |
| 单人 C | 735 | 1334 | 4173 | 0 | 4293 | 4637 |
| 双人 A | 550 | 1150 | 3168 | 50 | 3342 | 3548 |
| 双人 D | 738 | 1338 | 5009 | 0 | 5129 | 5295 |
| 双人 B | 728 | 1328 | 4903 | 0 | 5022 | 5238 |
| 双人 C | 728 | 1327 | 3995 | 0 | 4114 | 4303 |

D 已复现较长的战前推进，B 的请求比 D 稍早。在 B 的两条 1121 路线中，精英等待都为零，请求到入场约两秒。按第 72 次击毁调度后，1121 单人入场从 86.8 秒到 71.6 秒，双人从 83.7 秒到 68.6 秒。相对 B 分别收回 15.3 和 15.1 秒，两条路线仍晚于各自 A 样本。首伤也提前于 B，单人和双人各收回 20.0 和 15.6 秒。

| 路线 | A 入场／首伤 | D 入场／首伤 | B 入场／首伤 | C 入场／首伤 |
|---|---:|---:|---:|---:|
| 单人 1121 原位 | 3590／4220 | 5304／5696 | 5209／5835 | 4293／4637 |
| 单人 1122 走位 | 2994／3556 | 5627／6120 | 5345／5875 | 4293／4700 |
| 单人 1123 走位 | 2754／3246 | 5375／5863 | 5174／5517 | 4255／4548 |
| 双人 1121 原位 | 3342／3548 | 5129／5295 | 5022／5238 | 4114／4303 |
| 双人 1122 走位 | 3558／3687 | 5188／5424 | 5153／5395 | 3995／4291 |

五条路线的入场中位数与范围由 B 的 86.2 秒（83.7–89.1）变为 C 的 70.9 秒（66.6–71.6）。本体首伤中位数由 92.0 秒（87.3–97.9）变为 75.8 秒（71.5–78.3）。B 的最慢入场及首伤在单人 1122，C 最慢入场为单人 1121 和 1122 并列，首伤最慢为单人 1122。走位样本首跑未横移避开锁定光束，数局在首伤前阵亡。表中走位数据来自加入锁定后横移和闪避的复跑，首跑日志另行保留。

## 发布前复跑

下表用同一组输入再次比较 B 和 C。敌弹列为入场前实弹总数和瞬时在场峰值。失血统计到本体首伤，双人取两架飞机合计。

| 路线 | 入场帧 B→C | 首伤帧 B→C | 敌弹总数 B→C | 在场峰值 B→C | 失血 B→C |
|---|---:|---:|---:|---:|---:|
| 单人 1121 原位 | 5248→4289 | 6053→4640 | 39→30 | 6→6 | 0→0 |
| 单人 1122 走位 | 5353→4468 | 6004→4796 | 49→60 | 6→12 | 3→4 |
| 单人 1123 走位 | 5141→4245 | 5625→4743 | 55→66 | 9→13 | 0→0 |
| 双人 1121 原位 | 5147→4246 | 5379→4463 | 15→17 | 5→6 | 0→0 |
| 双人 1122 走位 | 5178→4170 | 5403→4539 | 53→29 | 8→9 | 6→0 |

两轮的敌弹样本有波动。首轮五条对照的 C 三条单人路线都少发敌弹；复跑两条移动单人路线多发。双人复跑的入场前实际失血均为零，两个新样本的同时在场峰值都比配对基线多一颗。当前方案移动首领调度点，普通敌机的弹速、伤害、出招与波次投放预算沿用原规则。两轮均保留原始弹量。

进一步按第 72 次真实击毁对齐 1122 的移动路线。单人 B/C 到该击时已有敌弹 34／61、峰值 6／13，C 在此后的两秒预告期间没有增加这两个数。双人 B/C 到该击时已有敌弹 46／26、峰值 14／6，采样失血 1／5 点。双人至首伤时是 6／5 点。弹量及受击差异在调度点已经出现，结果有逐局波动。追加复跑中 C 最晚入场为单人 1122 的第 4477 帧（74.6 秒），本体首伤最晚为该局第 5037 帧（84.0 秒）。

发布前双人 C 两局均由房主看到双方实弹接触，1121 各为 78 和 58 次，1122 各为 109 和 74 次。动态走位的房主与加入端实际离开起点最远约 189 和 176 像素。两个加入端均在本机看到首领预告，再收到入场实体。首领入场时没有正在交战的精英；五条复跑的 B、C 都没有清除正在准备或继续释放的普通敌机攻击预警。

规则专项通过 10 项，两种图形画幅各通过 11 项。普通双端通过 40 项，跨画幅交换房主各通过 34 项，换线恢复复跑两次各通过 33 项。移动端 13 项、波次 25 项、曲线 14 项断言通过，曲线探针的退出资源提示可在 B 重现。固定首卡 12 组配对轨迹一致，双线截击中路和双侧通过。

本轮量到首领本体首次受伤。后续首领用请求门槛专项核对。两秒预告冻结由脚本暂停验证，实际换线探针发生在首领入场后。手机和平板实机、真人盲玩及云端独立验收待进行。

## 复跑

```sh
python3 tests/run_first_boss_pace_probe.py /tmp/first-boss-ab
godot --headless --fixed-fps 60 --path . res://tests/first_boss_pace_probe.tscn -- solo rules
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25120 resume-guest "$(mktemp -d)"
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25121
bash tests/run_probe.sh 25126 wide-host
bash tests/run_probe.sh 25127 wide-client
godot --headless --path . res://tests/mobile_check.tscn
godot --headless --path . res://tests/wave_probe.tscn
python3 tests/run_first_card_probe.py /tmp/first-boss-first-card
python3 tests/run_dual_intercept_probe.py /tmp/first-boss-dual --case center --case both
```

Python 驱动输出每个版本和角色的原始日志以及 `samples.json`。可用 `--case lan-anchor` 或 `--case lan-patrol` 选定路线，用 `--variant B --variant C` 专门比较本轮。按需通过环境变量 `GODOT` 指定引擎路径。

```sh
godot --windowed --resolution 1600x720 --path . res://tests/first_boss_pace_probe.tscn -- solo rules wide screenshot=/tmp/first-boss-20x9.png
godot --windowed --resolution 960x720 --path . res://tests/first_boss_pace_probe.tscn -- solo rules screenshot=/tmp/first-boss-4x3.png
```

规则探针先布置在场精英，再驱动击毁门槛、重复请求和冻结。当预告与选卡同屏时检查顶部、安全区和按键矩形。图片来自桌面引擎，安全边距由脚本注入。

音画专项检查屏幕边框透明的中央、触摸穿透、入场前回收，以及重复预告快照只播放一次提示音。房主与加入端可用下面的真实大厅路线分别验证。同一音频声部还负责原有激光蓄力音，战斗反馈探针覆盖其原播放路径。

Godot 4.7.2 单人专项通过 13 项，两种桌面画幅各通过 14 项，真实大厅中房主与加入端各播放一次入场音。常规联机首跑有两条位置断言失败，发生在首领预告前；当前版重跑和修改前的基线对照均通过 40 项。

```sh
python3 tests/run_first_boss_pace_probe.py /tmp/first-boss-warning-lan --variant C --case lan-anchor
godot --headless --fixed-fps 60 --path . res://tests/combat_feedback_probe.tscn
bash tests/run_probe.sh 25184 feedback
```

## 首只母舰的音画提示

普通局首只母舰以闭合盾环、碎开的弧片、持续露出的机芯和聚拢断弧取代上一版 `1c0c06b` 的实时战术字幕。房主的回盾相位抵达后，盾条回升、护盾闭合。激光等原有危险提示继续显示。定向脉冲保持原锁线和伤害宽度，被锁定本机可看到收束角标并听到一次短鸣。恢复原局重建当前盾形和锁线，实时新相位才播放破盾、聚盾或锁定短音。

在 Godot 4.7.2 中从标题选择单人出击。录制夹具隔离母舰的一次真实护盾循环，让实际炮弹触发破盾和本体命中。两端夹具通过本机真实 ENet，交换房主画幅和两名目标槽位。取样在双方看见锁定后才触发取消。击毁清理从实弹碰撞回调计时，飞行时间另外计算。

有声和主音轨静音的引擎录制各通过 16 项。两份录制都在闭环上采到 24/24 个像素采样点。持续露芯与聚盾阶段的闭环采样为 0，聚盾两个时刻的断弧各采到 12/12 点。原始混音为 48 kHz 立体声，在约 4.50 秒处检出与聚盾上扬声匹配的波形。静音导出的 PCM（脉冲编码调制）样本为零。当前会话无法直接试听，录音供人工核对。

20:9 和 4:3 互换房主，两轮各通过 118 项，其中房主 64 项、加入端 54 项。验证包括角标与提示声只在标记端触发、同线发射、横移免伤与队友实弹扣盾、倒地和破盾取消、冻结时撤下锁定提示并停止旧声、开放和聚盾状态换线恢复，以及旧包与死亡清理。图形实拍保留圆环、断片、开放和聚盾关键帧。首跑中，运动插值影响像素采样，断线夹具也会在消息送达前结束原连接。复跑隔离了插值对取样的影响，并留出后台消息到达房主的时间。

首战单人规则 19 项、生命周期单人 42 项与双端 124 项、实弹击毁清理 53 项、战斗反馈单人 14 项与双端 28 项、触屏战斗界面 43 项、拇指弧双端 55 项和裂隙双向牵制 91 项通过。固定种子 1121 走真实标题和大厅，房主在第 4173 物理帧入场并在第 4346 帧打伤本体，房主 11 项、加入端 5 项通过。画面与输入来自桌面引擎、脚本及本机回环。手机和真人辨识度待验。

```sh
mkdir -p /tmp/boss-av/sound /tmp/boss-av/silent /tmp/boss-av/wide-host /tmp/boss-av/wide-client
godot --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  --write-movie /tmp/boss-av/sound/engine.avi res://tests/first_boss_cues_probe.tscn -- capture /tmp/boss-av/sound
godot --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  --write-movie /tmp/boss-av/silent/engine.avi res://tests/first_boss_cues_probe.tscn -- capture /tmp/boss-av/silent mute
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25323 boss-coop-wide-host /tmp/boss-av/wide-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25324 boss-coop-wide-client /tmp/boss-av/wide-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25325 boss
godot --headless --fixed-fps 60 --path . res://tests/boss_lifecycle_probe.tscn -- solo
godot --headless --fixed-fps 60 --path . res://tests/first_boss_pace_probe.tscn -- solo rules
godot --headless --fixed-fps 60 --path . res://tests/battle_presentation_probe.tscn -- verify "" touch inset inset-rounded
python3 tests/run_first_boss_pace_probe.py /tmp/boss-av/lobby --variant C --case lan-anchor --port 25330
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25326 boss-kill
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25327 feedback
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25328 rift-duo-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25329 draft-touch-wide-client
```
