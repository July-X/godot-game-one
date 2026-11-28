# 裂隙变奏：双线截击

两端从标题的「试飞任务 → 裂隙航道」进入「裂隙变奏：双线截击 · 仅双人」。一端创建房间，另一端加入同名房间并确认，随后由房主开始。试飞复用双人变奏大厅、原生摇杆、技能按钮和重试。普通大厅继续提供原版和变奏。协议仍为 9，开局参数、实体、预警、脉冲和结算沿用原格式。独立房间用已有的大厅校验消息核对双方入口身份，旧版或从普通入口误连的玩家会留在大厅。

第 1.5 秒，两架各有 8 点耐久的干扰机分别从左右入场，同时预告三发扇弹。房主在第 198 个战斗帧实际发射仍存活一侧的三发。提前击毁只撤下本侧预告，给出断弧和短音。晚到的击毁保留在飞弹体的原轨迹。两股弹之间的中路可通行。

第 9 秒进母舰，两次定向脉冲的尝试从第 12 和 19 秒开始。已有的瞄准、公用攻击路线和安全筛选保持有效，队友倒地或没有安全锁向时可跳过该次攻击。两侧都截断后，第一轮实际发射的脉冲从距舰心 152 单位处开始，普通起点是 48。危险半径均为 34，故近端危险边界从舰心前 14 推至 118。预警、发射和扣血共用锁定端点。未发出的脉冲保留奖励，后续实际发射回到 48 单位起点。

在第 1500 个战斗帧显示结算，保留真实截断数；全员被击落时走已有失败流程。断线暂停期间不额外推进时钟，回到原局继续。房主重试重新生成两架干扰机和母舰，从 0 次截断开始。试飞独立于正式关卡的选卡、成长奖励和榜单。

结算沿用原位置和按钮，两行内交代本局截断，并给出下一局行动或本局解锁。房主只在真实取消一侧齐射后记录侧别。单侧结果用复盘字典的可选 `cut_side` 字段随结算和终局快照发送。缺字段或侧别无效时显示「截断 1 侧」。双侧提示「解锁母舰首轮宽缺口」，即使全员倒地在首发之前，这句话仍只表示条件达成。

## 复跑

```bash
godot --headless --path . --editor --import
python3 tests/run_dual_intercept_probe.py /tmp/dual-intercept-matrix
python3 tests/run_dual_intercept_probe.py /tmp/dual-intercept-frames --capture --case center --case both
python3 tests/run_dual_intercept_probe.py /tmp/dual-intercept-mismatch --case mismatch
python3 tests/run_lobby_entry_probe.py /tmp/dual-intercept-lobby-regression --normal-runs 4 --remix-runs 4 --start-port 21290
bash tests/run_probe.sh 21270
bash tests/run_probe.sh 21272 wide-host
bash tests/run_probe.sh 21273 wide-client
bash tests/run_probe.sh 21274 rift-duo-host
bash tests/run_probe.sh 21275 rift-duo-client
bash tests/run_probe.sh 21276 feedback
godot --headless --path . res://tests/mobile_check.tscn
```

使用 Godot 4.7.2。探针经真实标题按钮、创建房间、房间列表、规则确认和开始按钮进入。单机双进程环回时用现有发现回调填入房间，局内走真实 ENet（Godot 联机传输）链路。试飞生成实际弹体，脚本注入模拟触摸走位，到达测试航线后固定机头，开火和击毁仍由原主炮与房主碰撞执行。倒地和换线由探针触发。房主的几何采样点调用实际脉冲扣血路径，和真实驾驶样本分别记录。图形模式使用桌面模拟画幅，不代表物理手机或平板测试。

### 结算反馈复跑

```bash
python3 tests/run_dual_intercept_probe.py /tmp/dual-review-frames --capture --case left --case right --case both-no-pulse --case sequence
python3 tests/run_dual_intercept_probe.py /tmp/dual-review-extra --case late --case downed --case mismatch
old_project=$(mktemp -d)
git archive 9837d14f5d0eb2b6942835434b72ba5eb6539fbd | tar -x -C "$old_project"
cp tests/dual_intercept_probe.gd "$old_project/tests/"
godot --headless --path "$old_project" --editor --import
python3 tests/run_dual_intercept_probe.py /tmp/dual-review-old-host --legacy-host "$old_project" --case left
python3 tests/run_dual_intercept_probe.py /tmp/dual-review-old-client --legacy-client "$old_project" --tablet-first --case right
bash tests/run_probe.sh 21900
bash tests/run_probe.sh 21901 rift-review
bash tests/run_probe.sh 21902 rift-wide-host
bash tests/run_probe.sh 21903 rift-duo-client
godot --headless --path . res://tests/mobile_check.tscn
```

`sequence` 在同一房间依次结算 0、2、0 次，实际点击房主重试。`left` 在结算后让加入端清掉本地结算副本并更换 ENet 连接，再由房主终局快照恢复。`both` 在结算前换线。探针通过现有接收入口直接重放旧局和重复回执。`both-no-pulse` 先由实际主炮截断两侧，再由探针在母舰首发前触发双机被击落。旧版混联沿用同一探针，生产脚本来自基线提交。

| 样本 | 房主画幅 | 房主／加入端断言 | 双端结果 |
| --- | --- | ---: | --- |
| 仅左侧 | 20:9 | 34／31 | 显示「已截断左侧」，结算换线后恢复原文 |
| 仅右侧 | 4:3 | 31／28 | 显示「已截断右侧」 |
| 双侧、首发前被击落 | 20:9 | 17／15 | 房主战斗帧 560 结算，首轮尝试在帧 720。双端只提示解锁 |
| 同房间 0 → 2 → 0 | 4:3 | 91／84 | 每局双端一致，结算前换线、旧局回执与重试检查通过 |

两种画幅的结算文字和按钮位于模拟非对称安全区内。加入端保留返回标题，房主同时可重试。正式航道结算 121 项、原版航道 57 项、正式变奏母舰牵制 91 项、普通联机 40 项及移动交互 13 项通过。

以 `9837d14` 作实际旧房主时，新版加入端结算和换线恢复都显示「截断 1 侧」，共 53 项断言通过。以该版作旧加入端时，旧界面保留「截断 1 次」，新版房主显示「已截断右侧」，共 47 项通过。

补跑迟到击毁 49 项、倒地推进 26 项、错误大厅 8 项。本轮结算矩阵共 514 项断言通过，含取帧与双向混联。手机、平板真机和无讲解真人试玩尚未执行。

上一轮独立验收曾遇到一次重试的第二轮脉冲在双端均未锁定，原基线与候选各两次复跑均通过。本轮未重现，保留正常样本的锁定、实际发射和伤害断言，失败时记录计划发射帧的护盾、存活机师和房主安全槽位。首发前双机被击落是单独验证的终局。

## 验收记录

| 大厅样本 | 双端最终截断 | 左／右发弹 | 验证点 |
| --- | ---: | ---: | --- |
| 两人走中路 | 0 | 3／3 | 通过齐射而且机体健康值不变，完整推进到结算 |
| 仅抢左路 | 1 | 0／3 | 主炮击毁左侧，重复回调不重复计数 |
| 仅抢右路 | 1 | 3／0 | 主炮击毁右侧，重复回调不重复计数 |
| 左右分飞 | 2 | 0／0 | 更换 ENet 连接后恢复相同槽位、局次和计数 |
| 左侧发射后再击毁 | 0 | 3／3 | 已发弹体保持同一运动方向 |
| 加入端倒地 | 0 | 3／3 | 双端认出倒地状态，仍可结算 |
| 双截断后房主重试 | 0 | 3／3 | 重走中路，旧局结果不覆盖新局 |

双截断首轮在舰心前 105 单位处实测扣血 0，外侧采样点扣血 10。第二轮、零截断首轮和重试首轮都是 10／10。20:9 和 4:3 交换房主，两端看见相同锁向端点。图形探针留有两侧预告、齐射和母舰锁向／发射关键帧，积分、摇杆和技能按钮之间留有空间。

首轮双截断探针错把新连接号当作旧号，导致房主漏采首轮。首轮图形重试中，探针的自动主炮提前破盾，按游戏规则取消了一轮脉冲，重叠窗口也漏取了房主图像。复跑记录入局时连接号，让采样机避开母舰护盾，并分别露出两个窗口。

最终试飞矩阵共 358 项断言通过，含图形取帧与普通大厅误入。另用基线 `b6e089a` 作为实际旧版加入端，10 项断言均通过，两端提示后留在大厅。复跑该组时，让新版以 `res://tests/dual_intercept_probe.tscn -- host mismatch wide` 开房，旧版在基线目录以 `res://tests/lobby_start_probe.tscn -- client 7777 expect-mismatch device-b` 加入。

普通联机 40 项，贴边双端每种房主画幅 34 项，正式变奏双向牵制每种房主画幅 91 项，移动交互 13 项，均通过。另从标题回归普通大厅 4 局、正式变奏 4 局、原版裂隙、换线、超时和重试。物理设备的发现、触感和音效听感，以及两位玩家无讲解首局与第二局的决策，留待真人试玩。
