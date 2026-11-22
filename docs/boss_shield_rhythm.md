# 裂隙母舰周期护盾

母舰开场持盾。打盾只消耗冷青护盾条，破盾一击的剩余伤害作废。随后本体开放 4.5 秒，最后 0.8 秒以短弧和「即将回盾」预告。回盾保留本体当前血量。初始本体与每轮盾量分别为旧版同配装最大生命的 70% 和 10%。

每盾轮轮换预判点射、中央留空的扇弹和一次激光。常规齐射由独立计时安排，正常巡航阶段间隔约 1.0–1.4 秒，调度上限为 2 秒。破盾后仍会齐射，母舰减慢巡航，停止突进与受压侧移。激光锁向在蓄力最后 0.55 秒开始，炮口朝向与引线使用同一方向。蓄力中破盾会撤下预警，已经发出的束保持原轨迹、推进尖端和伤害。束在播时不会增加齐射，护盾仍可回满。若主炮在光束期间打空本体，收束后才结算和掉落；炸弹沿用原来的直接击杀。

护盾打击用冷青短线和偏硬的短音，打本体用暖白火花和普通命中音。每次实际破盾各端只播一次冷色碎片和断裂声。补快照时，护盾相位和激光进度分别恢复，已发生的破盾不补播。局域网两端须使用同一版本。

## 同配装对照

以 `abb0d0af962294d8bb038b30bdb697962d7d78b0` 为旧版，在本机 Godot 4.6.2 用同一夹具、同一个种子 14813 对照。初始生命 50，每次 2 发、每发 4 点、间隔 0.252 秒。脚本转向后调用真实主炮，锁向可见后用游戏移动控制器侧移。旧版没有蓄力锁向信号，夹具在刚发射时响应。最长无攻击时段包含入场，正在蓄力、推进或持续的帧不算空档；这是截断在退场或死亡时的观测值。受保护样本在夹具中屏蔽玩家伤害，用于跑完整场，时间均从母舰创建计起。

| 航线 | 旧版 | 周期护盾 |
|---|---|---|
| 侧移，承受实际伤害 | 23.92 秒玩家阵亡，未出激光；最长空档 3.17 秒 | 74.87 秒击败，剩 31 生命，4 次在发射前移出 55 像素危险半宽；最长空档 1.37 秒，7 次破盾 |
| 同类侧移，脚本保命 | 158.65 秒击败，最长空档 10.03 秒，3 次自动解盾 | 73.82 秒击败，最长空档 1.37 秒，7 次破盾 |

两组实弹样本都超过约 2–3 次破盾的目标。初始参数下，主炮即使持续满额命中也需要约 27.9 秒有效本体输出，三个开放窗合计 13.5 秒。能否靠主动技能、构筑或双人集火缩到目标需要另取样本。本轮按初始比例与时长交付，样本时间不代表真人难度。

另在普通导演和随机三选一流程用种子 1121、脚本保命跑完首只 Boss。两版实际成长配装不同，旧版从入场到击败约 159.6 秒，新版两次约 56.4 和 84.6 秒。这组样本用于验证生产路径能打完。

Boss 双进程专项通过 124 项，图形双进程通过 128 项。房主逐物理帧实测开放 270 帧，回盾预告 48 帧。两端各观察到两种接触颜色、三种音色与每轮一次实际破盾回放。常规联机 40 项、救援 79 项、三选一 25 项、战斗反馈 27 项、Boss 侧移 15 项均通过。首卡 12 组 A/B 共 6,600 帧一致，六条完整路径均到达首只 Boss 的实际本体受伤。图形 16:9 和 20:9 分别通过 30 和 53 项，光束像素与判定通过 22 项。

## 复跑

```bash
godot --headless --editor --import --path .
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19846 boss
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19855 boss-dodge
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19851
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19852 draft
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19853 rescue
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19854 feedback
godot --headless --path . res://tests/boss_lifecycle_probe.tscn -- finishing-beam
godot --headless --path . res://tests/curve_probe.tscn
godot --headless --path . res://tests/mobile_check.tscn
python3 tests/run_first_card_probe.py "$(mktemp -d)"
```

在基线的临时副本中只复制 `tests/boss_rhythm_probe.gd` 和 `tests/boss_rhythm_probe.tscn`。两版分别导入后运行以下命令。将最后一个参数换成 `assisted` 可复跑脚本保命对照。

```bash
godot --headless --fixed-fps 60 --path . res://tests/boss_rhythm_probe.tscn -- evade
```

双进程 Boss 门禁走主炮碰撞、可靠阶段包、实际音效回放和实体补发。专项依次覆盖蓄力前打盾、蓄力中击破、光束推进中击破、空盾时光束恢复、迟到或重复通知、原位碎片、回盾、击败和掉落。`finishing-beam` 用短尾段夹具单测光束期间的致命实弹。抓两端同场画面时，在已有输出目录中分别启动两个窗口。两个窗口各保留一部分可见区域。

```bash
godot --audio-driver Dummy --windowed --resolution 1280x720 --position 5,35 --path . res://tests/boss_lifecycle_probe.tscn -- host 19845 capture /已有目录
godot --audio-driver Dummy --windowed --resolution 1600x720 --position 240,114 --path . res://tests/boss_lifecycle_probe.tscn -- client 19845 capture /已有目录
```

桌面图形复跑以 `godot --audio-driver Dummy --max-fps 60 --fixed-fps 60 --windowed --resolution 1280x720 --path . res://tests/battle_presentation_probe.tscn -- capture /已有目录 verify` 进入。20:9 将分辨率改为 `1600x720`，在 `verify` 前加 `touch inset` 会模拟触控与单侧安全区。手机双机、手机喇叭和真人对预警的理解仍待验证。
