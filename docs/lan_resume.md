# 双人局后台恢复

战斗中的后台通知会清空摇杆、鼠标惯性和待执行技能，并暂停游戏树。队友收到通知或在约 3 秒内收不到心跳时也暂停，界面显示等待或同步。控制层每半秒发送心跳并检查墙钟，因此玩法冷却、在场弹幕和三选一计时冻结时，恢复流程仍可推进。没有回包约 6 秒时清理故障传输。20 秒宽限从本机冻结开始计时，超时后在前台提示并沿用单人回退。正常退出通过可靠通知跳过宽限。

房主给当前局的加入槽位发放仅驻留内存的随机凭证。重新握手用 Godot `SceneMultiplayer` 的认证通道互验新随机挑战的消息认证码。挑战只消费一次，校验通过且握手完成后才把新 ENet 编号映射到原玩家槽位。房间只给原队友留位，凭证随局刷新。首次凭证走既有 LAN 信道，面向可信局域网；系统终止进程、地址变化和房主迁移超出恢复范围。[Godot 4.6 认证通道](https://docs.godotengine.org/en/4.6/classes/class_scenemultiplayer.html#signals)

在两个应用都回前台后，房主先从可靠同序通道发送带序号的局状态和实体生成，再发送当前玩家、可见实体、弹幕与 Boss 阶段的权威快照。加入端确认属性序号和必要实体齐全，再应答。房主收到应答后才放行双方输入。恢复不会重放掉落奖励，旧局快照和已经消费的拾取及选卡事件沿用各自的局号、序号与去重规则。双方需使用同一版本。

## 复跑

以下使用 Godot 4.6.2。每次为恢复探针传入新的空目录。

```bash
export PROBE_KEEP_LOGS=1
bash tests/run_probe.sh 7788 resume-host "$(mktemp -d)"
RESUME_WIRE_WHILE_BACKGROUND=1 bash tests/run_probe.sh 7787 resume-host "$(mktemp -d)"
bash tests/run_probe.sh 7789 resume-guest "$(mktemp -d)"
bash tests/run_probe.sh 7790 resume-timeout "$(mktemp -d)"
bash tests/run_probe.sh 7791 resume-exit "$(mktemp -d)"
RESUME_EXIT_ACTOR=host bash tests/run_probe.sh 7792 resume-exit "$(mktemp -d)"
bash tests/run_probe.sh 7793
bash tests/run_probe.sh 7794 draft
bash tests/run_probe.sh 7795 rescue
bash tests/run_probe.sh 7796 boss
bash tests/run_probe.sh 7797 pickup-tablet-host
```

使用真实 ENet 传输，桌面手动投递系统后台和前台通知。`resume-host` 和 `resume-guest` 分别检查保留连接与关闭旧套接字后重新握手，故意移去加入端的 Boss 副本，检查权威数据补齐之后才放行。打开 `RESUME_WIRE_WHILE_BACKGROUND` 时，探针在房主仍处后台时先放通套接字，确认认证成功也继续冻结。

第三进程用于验证无关加入请求。在前台探针刚启用 `RESUME_WITH_OUTSIDER=1` 时用同一端口和标记目录运行 `godot --headless --path . res://tests/lan_resume_probe.tscn -- intruder 7789 resume-guest "$markers"`。探针等候原连接释放后抵达认证阶段，房主须保留原槽位。`resume-quiet` 用独立的桌面进程停止信号测试没有系统通知的静默。测试器写出 `host-pid`，控制脚本核对进程归属后挂起 3.7 秒再恢复，并在同一目录创建 `host-continued`。

Android 真机切应用、锁屏、系统对 Wi-Fi 的暂停策略和移动路由延迟仍待验。桌面回环恢复耗时不作为设备承诺。

## 本机结果

基线 `c807397` 在房主、加入端两种方向都复现后台通知后未冻结。关闭真实 ENet 连接后双方走旧的清场回退，联机玩家表归零。

macOS 同机双进程上，房主与加入端两组恢复专项各 26 项通过。房主保持后台时先完成新连接的专项通过 28 项，加入端继续冻结直到收到放行。静默用例暂停房主进程 3.7 秒，加入端由心跳判定等待，继续时沿用原连接。无凭证的第三个进程进入认证阶段后被拒，原 P2 重新握手后仍使用原节点。测试中的权威补齐包含血量、位置、卡牌层数、待选卡批次、冷却、已花救援次数、已拾取属性、在场弹幕和 Boss 激光阶段。重放旧局快照和重复拾取通知未再发奖。

正常样本从主动回前台到放行的墙钟如下。房主断链样本计入原端口监听恢复和另一端重新发起连接。另测双方断链后在 20.24 秒回退，主动退出通知约 16–19 毫秒后进入回退流程。

| 场景 | 恢复耗时 |
|---|---:|
| 保留连接，双端无窗口 | 4–8 毫秒 |
| 保留连接，加入端图形窗口 | 56–66 毫秒 |
| 加入端关闭套接字并重新握手 | 10 毫秒，无窗口 |
| 房主关闭监听并重新开端口 | 143 毫秒，无窗口 |
| 加入端关闭套接字并重新握手，双端图形窗口 | 143–160 毫秒 |

常规联机探针在第一道激光验收结束后停掉 Boss 后续主动攻击，单独观察 P1 死亡后 P2 会话是否保持。反馈探针等加入端装好观察器后再打出首颗短命火花。两处调整限于夹具。

常规联机 40 项、选卡 25 项、救援 79 项、Boss 124 项、拾取 72 项、跨画幅 57 项及反馈 28 项通过。项目导入、主场景启动和 13 项移动检查通过。
