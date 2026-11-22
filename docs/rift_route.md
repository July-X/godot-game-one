# 裂隙航道试玩

从标题进「裂隙航道 · 试玩」。双人连接后由房主选「开始裂隙航道 · 双人试玩」。普通入口和三种已有试飞仍保留。战斗时钟 35 秒发首卡，90 秒转入精英段，3:30 附近母舰入场。选卡时仅冻结关段排期，不锁移动或技能。只领一轮卡；可绕过精英，击败母舰推进试玩结算，不进普通榜单。桌面按 R 或点重试；联机由房主发起。连接恢复超时后回标题，不把断开的试玩写成一条普通战绩。

## 选敌与保命

母舰的点射、扇弹、终极激光和定向脉冲分别记录最近锁定。选敌使用稳定槽位、近期实结伤害、站位和近期承压；房主身份不加权。终极激光在同一台机上完成蓄力与锁向，已锁方向不跟随切靶。新关精英启用共用账本和受压侧移，旧精英不启用此行为。展开破盾时不能启动该规避。复跑日志保留主动选人方向，而不是只数受击。

## 复跑

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
