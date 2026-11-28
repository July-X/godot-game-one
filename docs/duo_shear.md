# 普通双人剪翼的诱敌与侧切

首只母舰请求前，两名机师均可行动时，房主能把涨潮中的第一支钳形或 V 形剪翼小队改为从上方集中入场。沿用原导演选择的机型、数量、出生顺序、错峰和预算。横向间隔为 53 逻辑像素。每局至多替换这一支，其他阵列从原排期生成。

剪翼准备时按与可行动机师的实际距离选人。距离完全相同的机师从同一个候选池抽取。两架的蓄力相重叠时，后开始的沿用仍有效的已有目标。实际发射点和扇形角度随后冻结，各走原来的蓄力、实弹和恢复。玩家可根据机头、展开的双炮和警戒射线横移，队友可以从另一侧实弹接近。目标倒地时，原取消规则撤下待发扇射，后续再从可以行动的飞机里选。重连清掉旧预警，原实体按原攻击序号重新蓄力。

初版沿用剪翼每轮三发、原伤害、弹速、血量、掉落与普通联机协议 10。实际预警时间仍走两端绘制回执。普通单人、已有试飞、裂隙和首战后运输机继续各自的原有入口。

## 实拍与验证口径

Godot 4.7.2 从标题点进普通大厅，两端用真实 ENet（局域网传输）连接。本机环回由脚本生成发现回调。以种子 `47681` 布置同一个二级涨潮排期，导演实际生成三架剪翼。固定机位，双方从预警后按各自路线注入有效走位，首个敌弹确认后使用现有主炮。侧切时由侧翼先打，诱敌机在 1.25 秒后补射。初始护盾由原上限给出，并从房主的权威结算记录实际减少量。清场从本端第一架实体入树计到最后一架被实际主炮击毁。测试中的倒地由房主触发，单列在比较之外。

| 图形双端对照 | 首个锁定对象 | 房主清场 | 房主 / 加入端实扣护盾 |
| --- | --- | ---: | ---: |
| 基线并排 | 房主 | 3.974 秒 | 1 / 1 |
| 基线侧切 | 房主 | 4.451 秒 | 1 / 1 |
| 候选并排 | 加入端 | 2.513 秒 | 1 / 1 |
| 候选侧切 | 房主 | 3.259 秒 | 0 / 0 |
| 候选镜像侧切，4:3 房主 | 加入端 | 3.144 秒 | 0 / 1 |

候选的正向和镜像各由侧翼主炮清阵，分别从加入端和房主打出四次房主权威实体接触。五个候选图形场景共通过 101 项。倒地样本的剩余机师实际清场用时 2.958 秒，无敌弹接触。真实换线前后仍是 `1001`、`1002`、`1003`，旧预警撤下，恢复从新序号绘制。房主在恢复样本实测 3.567 秒清场，其中含换线等待。两端已观测的弹体与警戒线起点、方向一致。

单人从正常入口复跑仍从两侧生成原钳形。波次门禁 28 项、普通敌机单人 44 项、普通联机 40 项、普通母舰双人 108 项、裂隙双人 91 项、运输机截击 13 项、固定首卡 27 项通过。干净导入后标题与战斗可加载。并排首跑固定了预期目标，实测另一架更近，复跑用明确分开的近侧与远侧站位验目标。两次图形复拍中，房主先清完，客机侧翼没有记录到命中。让侧翼先打后重新对照，照常要求房主确认侧翼的实际命中。实拍和计时均由脚本操控，真机、真人盲玩与实体局域网待验。

## 复跑

将可执行文件路径导出为 `GODOT`。核心夹具从生产大厅进入，使用大厅默认端口 7777。基线对照把 `tests/duo_shear_probe.gd` 和同名场景复制到 `05eea55` 的干净导出目录并导入，两端追加 `baseline`。

```sh
probe=res://tests/duo_shear_probe.tscn
mkdir -p /tmp/duo-shear-frames
"$GODOT" --windowed --resolution 1600x720 --audio-driver Dummy --path . "$probe" -- \
  host 7777 flank frames=/tmp/duo-shear-frames > /tmp/duo-shear-host.log 2>&1 &
probe_host=$!
sleep 2
"$GODOT" --windowed --resolution 960x720 --audio-driver Dummy --path . "$probe" -- \
  client 7777 flank frames=/tmp/duo-shear-frames > /tmp/duo-shear-client.log 2>&1
wait "$probe_host"
```

并排时两端把 `flank` 换为 `parallel`。镜像交换时互换分辨率，两端追加 `mirror guest-bait`。倒地和换线分别使用 `downed guest-bait` 与 `rewire mirror guest-bait`。

```sh
"$GODOT" --headless --path . res://tests/wave_probe.tscn
"$GODOT" --headless --fixed-fps 60 --path . res://tests/duo_shear_probe.tscn -- solo 7777 scope
"$GODOT" --headless --fixed-fps 60 --path . res://tests/transport_intercept_probe.tscn -- solo 7777 hit
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25570
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25571 boss-coop
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25572 rift-duo-client
```
