# 裂隙航道试玩

从标题进「裂隙航道 · 试玩」。双人连接后由房主选「开始裂隙航道 · 双人试玩」。普通入口和三种已有试飞仍保留。战斗时钟 35 秒发首卡，90 秒转入精英段，3:30 附近母舰入场。选卡时仅冻结关段排期，不锁移动或技能。只领一轮卡；可绕过精英，击败母舰推进试玩结算，不进普通榜单。桌面按 R 或点重试；联机由房主发起。连接恢复超时后回标题，不把断开的试玩写成一条普通战绩。

进入构筑、猎手和母舰段时，关段标题短暂改为一条行动提示，约 2 秒后恢复关段名。构筑提示等本机选卡确认后再显示，给三选一留出完整操作区。沿用现有标题位置和关段消息。整备、结算和重连恢复显示当前关段，不补播行动提示。

结算保留通关或被击落、实际截断次数和原有按钮。结果下方给一条下局建议。零截断可先切掉一股齐射；已截断但在母舰段被击落可试横移后从侧翼打盾；其他失败可更换拦截路线；通关可换一张首卡或一条航线。双端用现有的房主结果、截断数和关段显示同一复盘。

运行 `PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 22546 rift-review` 复跑零截断、早段失败、母舰段失败和通关。探针用实弹分别截断 0、1、2、3 股齐射，检查双端结论、旧结果重放、房主重试和普通榜单。追加一个已有目录，可用 16:9 手机模拟和 4:3 平板模拟保存两端结算截图。行动提示另由 `rift-wide-host`、`rift-wide-client` 和双方超时模式验证。

## 选敌与保命

母舰的点射、扇弹、终极激光和定向脉冲分别记录最近锁定。选敌使用稳定槽位、近期实结伤害、站位和近期承压；房主身份不加权。终极激光在同一台机上完成蓄力与锁向，已锁方向不跟随切靶。新关精英启用共用账本和受压侧移，旧精英不启用此行为。展开破盾时不能启动该规避。复跑日志保留主动选人方向，而不是只数受击。

## 首卡后的两波截击

首卡后的前两波把纵列、聚团、装甲侧翼拉开，第二波左右镜像并调整三股火力的发射顺序。中路留给绕行。沿原本的机身蓄力环提前画出三条短线，线和该机随后发出的三颗弹使用同一个方向计算。所有路线都可以由机师主动切换，队形和发射排期独立于抽到的卡。

验收以具体发射者是否真的少发三颗弹为准，并记录动作来源和损失。双人等待最后一次确认或原有超时，选卡期间可继续走位和使用技能。确认到第一波的排期恒为 90 个关卡物理帧。

同种子同路线对比 `3556637`：溅射沿聚团、贯穿沿装甲翼两条路线在旧版常让目标发出整股三弹，新版两个画幅的两波都能截断相应发射者。贯穿沿纵列的一发实弹穿过前段机体击中后排，溅射沿聚团击中间接目标，威力沿装甲翼一发击毁 7 HP 的发射机。溅射和威力也可以沿纵列截击，贯穿可以沿翼截击但需要再次命中。中路样本每波仍有至少两股真实弹流通过。双进程轮换最后选卡者，并各跑一次由房主或加入者超时的情形，确认所用的是同一排期。

```bash
python3 tests/run_rift_build_probe.py "$(mktemp -d)"
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21201 rift-wide-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21202 rift-wide-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21203 rift-timeout-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21204 rift-timeout-client
```

复跑旧版时，从 `4c1d0d6` 取目录迁移前的 `tests/run_rift_build_probe.py` 和 `tests/opening_trial_probe.gd`，复制到 `3556637` 的临时副本，导入后在该副本执行 Python 命令并附加 `--baseline`。逐机出生、逐弹发射、实际命中和失血记录在输出目录。脚本沿固定手势操作，是否能主动换线留给不提示打法的真人试玩。

## 猎手击破奖励

房主在猎手实际击毁时记录当局奖励。母舰按原排期在 3:30 入场。击毁猎手时，第一次破盾的暴露期为 5.5 秒，之后每次为 4.5 秒；绕行和重试回到 4.5 秒。奖励在开盾时交给当前母舰，第一次破盾时消耗。联机沿用房主盾状态、回盾预警和恢复快照。

单人用真实主炮完成猎手最后一击，母舰在第 12600 帧入场。绕行、首次奖励、第二次破盾、重试的暴露期分别为 270、330、270、270 帧。双端实测分别观察到约 330 帧（房主击毁猎手）和 270 帧（绕行），已把等待运输的帧差计入容差。PR #3 的猎手开场仍待独立集成，奖励以现有击毁信号验收。

```bash
godot --headless --fixed-fps 60 --path . res://tests/rift_route_probe.tscn -- --rift-log
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21215 rift-wide-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21216 rift-wide-client
```

## 母舰诱敌

裂隙航道的母舰在护盾期选定一名机师。先用机体边缘的短标记告知目标，前 0.30 秒根据目标位置决定锁向，随后画出实际定向脉冲的有伤害轮廓。锁向后仍有 0.60 秒横移时间，已锁定的轨迹和端点保持固定。队友可利用侧面交火。如果锁定时同航线会挤掉队友的安全空间，母舰撤销这一发。单人按同一节奏走位反打。

双人仍用房主记录的实结伤害与站位选稳定槽位。跟踪、锁定和发射复用现有按阶段更新与恢复快照，机体标记在本地绘制。普通局沿用原脉冲。大厅协议升级，避免不识别跟踪阶段的旧版混局。终极激光的外焰判定保留独立验收。

Godot 4.6.2 用实际主炮命中提供施压样本，再用真实位移和主炮验证反打。单人和双人的目标均可横移无伤。双人侧翼样本再削去 16–24 点护盾，锁定方向随早期横移偏转 3.61°–6.41°。20:9 与 4:3 交换房主，P1 或 P2 都能连续成为目标，另一机打出更高实际压力后目标切换。更换传输连接后恢复同一个机体标记，破盾可以清掉这次未发射的脉冲。

```bash
godot --headless --path . res://tests/rift_inducement_probe.tscn -- solo 0 solo
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21243 rift-induce-host "$(mktemp -d)"
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21244 rift-induce-client "$(mktemp -d)"
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21224 boss-coop
```

手机和平板互换房主、真人能否自己理解锁向和主动配合仍待验。

### 侧翼反击窗

航道母舰真正打出定向脉冲时，脉冲偏向另一侧的盾沿亮起一段薄荷绿弧和菱形。亮处维持 1.2 秒，机师可横移到该侧，以主炮或散射实弹命中亮边，按原伤害的 1.5 倍扣盾。被标记者和单人同样能利用这个位置。打中其余部位或以技能溅射、连锁结算时按原规则扣盾，破盾当发仍无伤害溢出。

跟踪、锁向和脉冲危险区沿用诱敌规则。提前取消或锁向时没有安全空间均不开窗。破盾、击毁和离场收窗，下一轮重新等到脉冲发射。动态余时和侧翼随现有脉冲更新与母舰快照传输，以房主事件号判断先后。同一次事件的补发只校短余时。联机需要协议 5。

```bash
godot --headless --path . res://tests/rift_inducement_probe.tscn -- solo 0 rift-flank-solo
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 22503 rift-flank-host
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 22502 rift-flank-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 22504 boss-coop
```

固定种子 90220，以脚本控机和近距离生成的实弹隔离落点。一发面值 4 的实弹打中普通区域仍扣 4，打中亮边扣 6，同脚本在 `a5e8536` 都扣 4。两组双人各 55 项，互换目标、主炮归属和 20:9／4:3；站在锁线上的目标实扣 10，读标横移的目标无伤。重连恢复约 1.05–1.08 秒余时，过期重连和旧包重放保持关闭。护盾剩 5 时，亮边一发破盾，本体血量维持不变。普通局的脉冲仍无弱点，协议 4 和 5 互换房主均明确阻断开局。

复跑基线时，在 `a5e8536` 的临时副本中替换为 `4c1d0d6` 的 `tests/rift_inducement_probe.gd`，使用同一场景，角色参数之后追加 `baseline`。双端直接按 `-- host 端口 rift-flank-host baseline` 和 `-- client 端口 rift-flank-host baseline` 运行。

### 终极激光外焰

外焰由房主按稳定机师槽位累加，每束独立结算。暂时脱离外焰可保留本束自己的小数余额，倒地或离场的机师停止累加，新光束清零。单人、内圈、外沿和光束画面沿用原规则。

```bash
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21228 rift-outer-burn
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 21229 rift-outer-burn-mirror
godot --headless --path . res://tests/rift_inducement_probe.tscn -- solo 0 rift-outer-burn-solo
```

`9395d701` 基线旧探针复现 P1 50→49、P2 50→50。新探针以固定 60 Hz 步进房主的实际激光结算，两机经真实联机上报位置。核对 59 单位安全、39 单位同时各扣 1 点，并换边、交换画幅和先入焰机师。第二束先入焰 5 帧无扣血，累计 8 帧才扣 1 点；晚进入的机师按自己的入焰帧数扣血。单人同脚本保留逐阶段血量作对照。

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

在旧版使用 `4c1d0d6` 的测试场景和脚本，参数追加 `measure` 仅记录读数，不套新版门槛。

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
