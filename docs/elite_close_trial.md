# 精英近身抢攻 A/B

直接运行 `res://scenes/elite_close_trial.tscn` 进入 A。启动参数加 `--close-b` 进入 B。桌面按 R 或释放鼠标后点底部「重试」。触摸沿用同一个按钮，重开自动保留版本。该入口用于开发对照。

## 规则和画面

18 秒包括镜像护航的完整前情。两版都在第 1 秒生成原来的镜像编队，第 215 个物理帧入场一架裂隙猎手，生命 125、护盾 50。入场使用种子 90220。双方都使用正式溅射弹头，护航机还活着就实际发射。精英被击毁后，已发出的弹沿用原规则，倒计时仍到 18 秒。

A 沿用现有伤害。B 在原破盾阶段的第 0.22 到 1.30 秒内检查本机和精英的中心距离，208 个画布单位内实际命中的主炮弹额外造成 5 点伤害。近身圈淡线表示将开启，亮线表示已开启，收益出现时抬头显示短暂写出实际数值。关窗后继续按现有破盾阶段结算。两版的暖色弧出现在血条外侧，在现有开火前约 0.28 秒提示回击。暖色弹、冷色近身圈和数值反馈分别落在弹道、范围和抬头显示。

最初每颗弹加 10 点时，贪留对照在回击前已能击毁精英。调为 5 点后，无伤抢攻仍能缩短击杀，贪留则会在收窗后吃到回击。

## 固定输入结果

A 生成摇杆指令，B 逐帧重播。同一画幅和航线的 1,080 帧玩家位置一致，第一笔加成前，精英状态、护航出生与实际弹道一致。下表时间均从 18 秒试飞入场算起。

| 操作 | 16:9 | 20:9 |
| --- | --- | --- |
| 贴近后撤 | A 到时剩 7 点，B 8.58 秒击毁 | A 14.05 秒击毁，B 12.85 秒击毁 |
| 全程绕开 | 两版零敌弹接触和损失，精英保有 125 生命与 50 护盾 | 同左 |
| 提前进入 | 实际近身命中发生在开窗前，A/B 同为 81 点剩余生命，无伤拉开 | A/B 同为 85 点剩余生命，无伤拉开 |
| 关窗后进入 | 正常伤害，实弹命中后拉开时精英仍可回击，A/B 均无伤 | 同左 |
| 贪攻不撤 | A 8.22 秒、B 7.38 秒击毁，两版均被回击扣 3 点机体生命 | 同左 |

贴近后撤的 B 都触发六颗主炮弹的额外伤害。窗口关闭时精英 20 点，对应的 A 为 50 点，两段都实际截断护航且没有敌弹接触。贪留航线的回击在第 429 帧发出，第 442 帧碰到玩家。B 依然能早击毁，额外输出与受击代价都保留。

## 本地复跑

```bash
godot --headless --path . --editor --import
godot --path . res://scenes/elite_close_trial.tscn
godot --path . res://scenes/elite_close_trial.tscn -- --close-b

out=$(mktemp -d)
python3 tests/run_elite_close_trial_probe.py "$out"
python3 tests/run_opening_trial_probe.py /tmp/opening-90-regression
godot --headless --path . res://tests/mobile_check.tscn
bash tests/run_probe.sh 19572
```

同一目录保存 `summary.csv`、逐帧 `replays.json` 和各条航线的摇杆文件。以下命令在临时项目副本中录制完整的 20:9 贴近后撤 B。Godot 4.6.2 的影片尺寸由录制用窗口设置决定，`--resolution` 负责运行窗口尺寸。[Godot 录制器源码](https://github.com/godotengine/godot/blob/4.6.2-stable/main/main.cpp#L4374-L4389)

```bash
capture=$(mktemp -d)
git archive HEAD | tar -xf - -C "$capture"
printf '%s\n' '[application]' 'config/name="Space Bullet Hell - Elite Close Recording"' \
  '[display]' 'window/size/window_width_override.movie=1600' \
  'window/size/window_height_override.movie=720' > "$capture/override.cfg"
godot --headless --path "$capture" --editor --import
godot --path "$capture" --windowed --resolution 1600x720 --fixed-fps 60 --disable-vsync \
  --audio-driver Dummy --write-movie "$out/close-b.avi" --quit-after 1210 \
  res://tests/elite_close_trial_probe.tscn \
  -- press "--flight=$out/1600-press-flight.json" --close-b --hold-result
```

删除 `--close-b` 并换输出名可录 A。录 16:9 时，把配置和命令中的宽度改为 1280，使用对应的 1280 路线文件。录贪攻使用 `hold` 和对应的贪攻路线文件。

记录来自 Mac 实际渲染和模拟摇杆。脚本清除了由墙钟恢复的命中定格，保留真实伤害、投射物、惯性与碰撞。绕行指令由脚本读取可见弹体生成，再在 B 重播。手机真机以及玩家能否读懂窗口、愿不愿意冒险或重试，仍待试玩验证。
