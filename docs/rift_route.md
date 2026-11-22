# 裂隙航道试玩

从标题进「裂隙航道 · 试玩」。双人连接后由房主选「开始裂隙航道 · 双人试玩」。普通入口和三种已有试飞仍保留。战斗时钟 35 秒发首卡，90 秒转入精英段，3:30 附近母舰入场。选卡时仅冻结关段排期，不锁移动或技能。只领一轮卡；可绕过精英，击败母舰推进试玩结算，不进普通榜单。桌面按 R 或点重试；联机由房主发起。连接恢复超时后回标题，不把断开的试玩写成一条普通战绩。

## 选敌与保命

母舰的点射、扇弹、终极激光和定向脉冲分别记录最近锁定。选敌使用稳定槽位、近期实结伤害、站位和近期承压；房主身份不加权。终极激光在同一台机上完成蓄力与锁向，已锁方向不跟随切靶。新关精英启用共用账本和受压侧移，旧精英不启用此行为。展开破盾时不能启动该规避。复跑日志保留主动选人方向，而不是只数受击。

## 复跑

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

构筑脚本完整飞过前段，固定触摸输入、敌机真实碰撞；流程探针加速跳过段与段之间的等待，在同一进程检查榜单、局内成长、重试和正常入口隔离。双人用真实 ENet 交换 20:9 与 4:3 画幅；流程探针直接进入共享战场，不计作两台真机或大厅发现验收。真人整关用时、可玩性、手机真机和高射速弹尾优化不在本次技术结论内。没有修改弹幕同步协议。
