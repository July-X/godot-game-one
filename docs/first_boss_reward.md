# 普通首只母舰的本机奖励反馈

首战奖励到账时，两侧机翼短亮并播放一次柔和的两音获得声，已有属性栏只短亮本机实际变化的行。持有额外弹道、火力、移速或冷却奖励后，相应反馈跟随下一次实际生效的玩家操作。

| 实际奖励 | 首次生效时的提示 |
|---|---|
| 额外弹道 | 强化齐射实际发出时，新增弹道的炮口短亮。加入端等房主回送匹配的实弹。弹数达到上限时保留到账和属性行反馈。 |
| 火力 | 伤害提高后的实际主炮齐射带暖色短闪，命中沿用原有接触表现。 |
| 移速 | 第一次由本机有效运动输入产生实际位移时，原尾焰短暂拉长。闪避和位置校正不消费效果。 |
| 激光冷却 | 下一次本机施放得到确认时，现有激光图标短促收放。原冷却、等待及拒绝状态照常显示。 |

房主沿用现有资格、奖池、数值和掉落。实时退场与到账通知和对应属性增量绑定，出现后只消费一次。换线时按权威数值刷新，已播放的反馈不补播。切场和重试随原战斗场景销毁反馈。

## 实际操作对照

Godot 4.7.2 从标题进入普通单人战斗。夹具只固定奖池中实际抽到的奖种并布置射击，两次真实碰撞分别破盾和击毁。以 `cf894c7` 为基线，用相同夹具分别检查实际奖种、六件掉落、一次到账、一次确认及重试。

| 奖种 | 基线与候选的操作结果 |
|---|---|
| 额外弹道 | 单轮实际炮弹从 2 到 3，单发伤害仍为 4。弹数上限夹具的实弹都为 12，仅对应属性行闪亮。 |
| 火力 | 单发 4 到 6，两发实际让靶机损失 8 到 12 生命。 |
| 移速 | 两版同构图录像的摇杆稳态实测均约 259.56 到 285.52 逻辑像素每秒。 |
| 激光冷却 | 三颗实际激光，下一次确认的冷却从 10 到 9 秒。到账时已经在计时的冷却保持原值。 |

两版各用四种奖种录制同帧。候选四类图形探针分别通过 21、21、22、26 项，静音的额外弹道样本通过 21 项。两版均生成原有六件掉落。原始混音为 48 kHz 立体声，探针观测到一次独立的获得音，静音录音的样本为零。当前会话无法直接试听。

双进程夹具建立真实本地 ENet 连接，由房主的实弹破盾及击毁。两人均存活时房主领火力，加入端领额外弹道。房主倒地时只有加入端领移速，加入端倒地时只有房主领激光冷却。三组共通过 92 项。加入端收到已结算的三颗主炮前，炮口强化保持静默。旧到账通知、恢复快照和新局的重试都没有再次触发旧音画。20:9 房主与 4:3 加入端另外录制到账与首次操作，通过 35 项。一次并行图形复跑卡在截图回调，为夹具加入等待上限后，串行复跑通过。

常规联机 40 项，母舰生命周期双端 124 项和单人 42 项，普通双人母舰 108 项，战斗音画单人 14 项和双端 28 项，拇指弧 55 项，裂隙双向牵制 91 项通过。局内输入由脚本和桌面模拟提供。手机、平板真机以及真人辨识度待验证。

## 复跑

```sh
for kind in bullet_count damage speed laser_cd; do
  godot --headless --fixed-fps 60 --path . res://tests/boss_reward_probe.tscn -- "$kind"
done
godot --headless --fixed-fps 60 --path . res://tests/boss_reward_probe.tscn -- bullet_count capped parallel_rows
mkdir -p /tmp/boss-reward/capture
godot --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  --write-movie /tmp/boss-reward/capture/engine.avi res://tests/boss_reward_probe.tscn -- bullet_count capture /tmp/boss-reward/capture
godot --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy --path . \
  res://tests/boss_reward_probe.tscn -- bullet_count capture /tmp/boss-reward/capture mute
```

将同名探针复制到 `cf894c7` 的干净导出目录，追加 `baseline` 运行同一组对照。联机依次替换最后一个参数为 `both`、`host-downed`、`client-downed`，每次分别启动两端。

```sh
godot --headless --path . res://tests/boss_reward_lan_probe.tscn -- host 25421 both &
probe_host=$!
sleep 1
godot --headless --path . res://tests/boss_reward_lan_probe.tscn -- client 25421 both
wait "$probe_host"
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25411 boss
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25412 boss-coop
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 25414 draft-touch-wide-host
```
