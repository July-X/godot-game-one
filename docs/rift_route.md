# 裂隙航道试玩

从标题进「裂隙航道 · 试玩」。双人连接后由房主选「开始裂隙航道 · 双人试玩」。普通入口和三种已有试飞仍保留。战斗时钟 35 秒发首卡，90 秒转入精英段，3:30 附近母舰入场。选卡时仅冻结关段排期，不锁移动或技能。只领一轮卡；可绕过精英，击败母舰推进试玩结算，不进普通榜单。桌面按 R 或点重试；联机由房主发起。连接恢复超时后回标题，不把断开的试玩写成一条普通战绩。

## 选敌与保命

母舰的点射、扇弹、终极激光和定向脉冲分别记录最近锁定。选敌使用稳定槽位、近期实结伤害、站位和近期承压；房主身份不加权。终极激光在同一台机上完成蓄力与锁向，已锁方向不跟随切靶。新关精英启用共用账本和受压侧移，旧精英不启用此行为。展开破盾时不能启动该规避。复跑日志保留主动选人方向，而不是只数受击。

## 复跑

### 裂隙猎手的预警与反打

裂隙猎手以快速俯冲进场，着位即开始首招，不再留一段可白打的额外等待。着位后沿横向滑向首招的起射点，橙色预警从这个终点画出，机体抵达才开火；预警仍完整，已经对准入场线的子弹不会跟着猎手转弯。首发每弹 6 点，后续窄扇每弹 2 点。破盾和反打规则不变。持盾遭到连续命中时，青闪后横移约 100 像素，能实际离开原先的直射线；开火预警或连射中不横移，破盾后不续移，不增加血量或免伤。追身断线按最近实际受伤来源和玩家站位选人，锁定带短提前量的方向。两次窄扇共用该方向。缺口扫环按最近机师的可达空间选择让位侧，环形刻线中留出与实际弹路相同的缺口。

出招后留出约 0.8 秒攻防转换。破盾立即中断待发攻击，仍可躲避已经发出的弹；原 4 秒暴露期不发强化招。召唤保留原血线、数量和计时，避开预警与连射。低血只缩短下一招前的间歇。原局恢复仅补剩余预警。普通模式精英和母舰独立于本规则。

预警顺序为 0.60 秒窄扇和 0.65 秒扫环。窄扇提前量 0.23 秒，两次各三发，间隔 11 个物理帧。扫环在 14 格中留两格，实际相邻弹路间有 77.14° 缺口。常态和低血间歇分别为 0.82 和 0.62 秒。警告画在锁定的世界坐标上，避免首帧插值使路径偏离实际弹路。

Godot 4.6.2、种子 90220。以猎手出生为第 0 帧，单人和联机房主记录一致。旧版 `067b6f2` 在第 80 帧直接发五发窄扇。上一版 `3556637` 第 123 帧开始预警，第 159 和 170 帧分别发窄扇，第 220 帧开始扫环预警，第 259 帧发 12 弹，均使用实际弹体。单人基础配装固定对准主炮在第 130 帧破盾，第 154 帧打到本体，首招因此取消。高射速配装第 76 帧即破盾。脚本走位躲过窄扇、进入缺口，站定在窄扇上实扣 2 点。低血路径验证了破盾当发、剩余弹体、4 秒空窗及预警时长。把召唤计时推进到扫环预警时，实际等到预警结束才生成两机，下一轮计时为 6 秒。

本轮以同一脚本对照 `3556637`（60 Hz，种子 90220，玩家无盾；基础射速 0.252 秒、高射速 0.090 秒）。追瞄站桩在中心及侧方旧版均为 0 次首发、0 掉血；新版第 15 帧预警、第 51 帧发射，两处均实扣 6 点，按预警横移的脚本四种组合均无伤并完成击杀。中心持续追瞄的击杀时间为基础约 5.5→5.8 秒、高射速约 2.2→3.1 秒；侧方为约 5.5→6.5 秒和 2.3→2.6 秒。中心高射速只打固定入场点，旧版约 2.2 秒击杀，新版 10 秒内未破盾。没有加血，也不是最低击杀时间锁。

```bash
for rate in basic fast; do
  for position in "" side; do
    for response in "" dodge; do
      godot --headless --fixed-fps 60 --path . res://tests/rift_hunter_pressure_probe.tscn -- "$rate" ${position:+$position} ${response:+$response} || exit
    done
  done
  godot --headless --fixed-fps 60 --path . res://tests/rift_hunter_pressure_probe.tscn -- "$rate" fixed-aim || exit
done
```

在旧版使用同一测试场景和脚本，参数追加 `measure` 仅记录读数，不套新版门槛。

双人专项使用真实 ENet 回环和交换房主的 20:9、4:3。机师倒地后，下一招从存活机师中选择。换传输身份时只补剩余预警，房主照原计划发弹一次。猎手的短齐射复用现有可靠散射队列。桌面同版本大厅及协议版本不同时的阻断均已复跑。触控、画幅和走位数据来自模拟，手机和平板真机仍待验。

```bash
godot --headless --path . res://tests/rift_hunter_probe.tscn -- solo
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21073 hunter-wide-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21074 hunter-wide-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21123 hunter-wide-host "$(mktemp -d)"
```

### MR 复核后的联机修复

双人首卡需要在实际碰撞上对等。房主和加入端分别选贯穿与溅射，交换配装后重跑，同一发实弹必须打到对应的次目标。房主生成加入端的实弹时按已确认的机师槽位读取构筑，远端弹体只负责显示。

裂隙猎手第三阶段的召唤机使用已有敌机同步，双方应看到同样的实体编号、血量和退场。精英侧移仍由房主决定，两端显示相同的短青闪。破盾时撤下未完成的预警，原局恢复只补当前剩余预警。

大厅连接后先校验双方联机协议版本，通过后才开放普通局和航道试玩。旧版本缺少确认时，新版大厅显示更新提示。协议标记用可靠字节消息传递，早于开局远程调用。[Godot SceneMultiplayer](https://docs.godotengine.org/en/4.6/classes/class_scenemultiplayer.html)

```bash
export PROBE_KEEP_LOGS=1
godot --headless --path . --editor --import
godot --headless --fixed-fps 60 --path . res://tests/rift_route_probe.tscn -- --rift-log
python3 tests/run_rift_build_probe.py "$(mktemp -d)"
bash tests/run_probe.sh 20671 rift-wide-host
bash tests/run_probe.sh 20672 rift-wide-client
bash tests/run_probe.sh 20673 boss-aggro
bash tests/run_probe.sh 20674 boss-aggro-mirror
bash tests/run_probe.sh 20675 boss-coop
bash tests/run_probe.sh 20676 boss-kill
bash tests/run_probe.sh 20677 resume-host "$(mktemp -d)"
bash tests/run_probe.sh 20678 resume-guest "$(mktemp -d)"
```

大厅直连测试在两个终端运行以下命令，先启动房主。将末参数都改为 `normal` 可复跑普通局。混版测试时，把探针复制到旧版目录，用该目录运行一端，另一端在新版将末参数改为 `expect-mismatch`。旧版没有版本提示，新版应停在大厅显示更新提示。

```bash
godot --headless --path . res://tests/lobby_start_probe.tscn -- host 20902 rift
godot --headless --path . res://tests/lobby_start_probe.tscn -- client 20902 rift
```

构筑脚本完整飞过前段，固定触摸输入、敌机真实碰撞；流程探针加速跳过段与段之间的等待，在同一进程检查榜单、局内成长、重试和正常入口隔离。双人用真实 ENet 交换 20:9 与 4:3 画幅；流程探针直接进入共享战场，不计作两台真机或大厅发现验收。真人整关用时、可玩性、手机真机和高射速弹尾优化不在本次技术结论内。没有修改弹幕同步协议。

修复后，航道交换房主的两组探针各通过 26 项。相同 30 HP 次目标受到贯穿 4 点或溅射 2 点，双方都看到两架相同编号的召唤机。破盾时青闪收起，另用换传输身份重连验证了精英副本补齐剩余青闪。大厅同版本普通局和航道各通过 11 项，混版两种角色组合均在新版侧显示更新提示。
