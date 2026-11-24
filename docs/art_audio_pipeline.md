# 美术与音频管线

本项目的美术与音频**以程序化生成为主**，外部资产只覆盖少数关键形象。

## 航道母舰的侧翼盾沿

橙色虚线仍表示脉冲危险区。实际发射后，舰体另一侧用薄荷绿盾弧和空心菱形标出可击中的边缘。提示贴着碰撞轮廓，随母舰平移；脉冲锁定和 HUD（抬头显示）安全区保持原样。

## 终局激光的像素表现

参考固定版本的 PixelFX `arcane/arcane-beam` 明暗分层及 `lightning/charge-up` 向内收束。制作以 Godot 中的一倍画面为准，确认蓄力收向母舰、推进尖端轮廓、持续束的低亮边带，以及从炮口推进至束尖的淡出。[PixelFX 固定版本](https://github.com/patch-gg/pixelfx/tree/5294518ce7c72e48b6100a744596e0acf57f2826)

游戏使用单个 CanvasItem 着色器；没有新增粒子节点、贴图或联机数据。按到束段最近点的距离区分核心秒杀（半径 16.5）与边缘灼伤（最大半径 55）。连续金橙亮芯融入流动暗红焰边；定向像素噪声形成沿束流动的火舌，外侧逐渐变暗，不用固定描边，也不越出真实判定。房主及单人逐帧读取伤害时钟，加入端用现有消息和快照时间恢复。同一对束段坐标锁定舰首，忽略迟到的常规朝向。最后 2 秒从炮口向尖端淡出；淡出的区域保留一层暗红热痕（中心略亮），直至原定伤害结束，随后只在束尖留 0.22 秒无伤害余光。

Godot 4.6.2 以 `b451652` 作基线。同一脚本、种子和视口按第 492、586、805、1345 物理帧对照蓄力、推进尖端、持续和收束。16:9 为 1280×720，20:9 为 1600×720。两版样本的激光时序、机体位置和生命值匹配。收束后的部分蓝色主炮数量受擦弹增益的墙钟衰减影响。三轮制作先对齐形状，再降低外带亮度并加分段流光，最后校准蓄力、出光与短余烬的明暗。

图形探针 22/22。斜向束在推进和接近持续结束时逐点检查内外圈、两端帽及安全区，敌弹和雨燕的不透明像素保持原色。实际伤害函数在尖端验证了 16.0 单位秒杀、17.0 和 54.5 单位各每秒扣 10 点、55.5 单位无伤。单人生命周期 32/32。双进程本机 ENet 回环的 Boss 门禁为房主 52/52、加入端 52/52，包含蓄力、推进与持续的实体快照恢复，以及开火后玩家移开、旧朝向更新不能转动舰首。炸弹击败、结算与换场时，激光节点随原生命周期清理。

本轮 Godot 4.6.2 图形探针 44/44；同一探针在几何描边版为 30/44。在外焰 36 个采样点中，24 个像素随时间变化，核心始终比外焰更亮。淡出起算 0.60 秒，炮口附近不透明度约为初始 20%，中段和束尖仍接近满值；1.30 秒时中段约 19%，束尖仍约 100%；1.96 秒时束尖约 21%。同时验证范围外无危险像素、原伤害未变、快照按同龄恢复逐像素匹配。用图形探针命令追加 `-- capture /已有目录` 可存六张 PNG。

真实图形双进程中，房主 1280×720 和加入端 1600×720 各 53/53。双方都录到推进光束、对齐的舰首和选卡叠层。常规联机 40/40，反馈联机 27/27。

基线可以用 `git archive b451652` 解到临时目录，使用 `git show 4c1d0d6:tests/battle_presentation_probe.gd` 取目录迁移前的探针后导入。当前项目使用工作树里的探针。截图和录像写入各自的已有输出目录。

```bash
godot --windowed --resolution 1280x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- capture /已有目录/16x9 verify
godot --windowed --resolution 1600x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- capture /已有目录/20x9 touch verify
godot --windowed --resolution 800x480 --fixed-fps 60 --audio-driver Dummy res://tests/boss_laser_visual_probe.tscn
godot --headless --path . res://tests/boss_lifecycle_probe.tscn -- solo
bash tests/run_probe.sh 18826 boss
bash tests/run_probe.sh 18827
bash tests/run_probe.sh 18823 feedback
```

单人中断用同一生命周期场景的 `bomb`、`game-over` 和 `scene-exit` 参数复跑。实拍由脚本驱动，20:9 的触摸是桌面模拟。手机与真实网络抖动下的显示待验。

## 裂隙母舰可读性

以 `SBH-Rift-Mothership-Design.png` 为造型参考。`python3 scripts/generate_assets/make_rift_mothership.py` 用 Pillow 重画肩甲、钢灰色层次和中央炮口。输出仍为 128×96 像素，33 单位碰撞圆沿用原尺寸。首版使用 2/3 倍精灵缩放，后续提高到 0.90 倍，细节见下节。

### 手机战斗界面与母舰尺度

普通奖励组移到安全区中心，单卡从 204×50 扩至最多 272×120，普通描述支持换行。半透明卡面让重叠的激光和敌弹仍可辨认。窄可用区缩窄卡片并让说明换行。首卡 A/B 保留顶部选卡和额外入口。Android 全屏的引擎安全区提供挖孔边距，原生桥从 `WindowInsets` 补充手势和圆角。桌面模拟采用同一画布换算。Android 10 起读取手势边距，Android 12 起读取圆角。 [Godot 4.6.2 Android 实现](https://github.com/godotengine/godot/blob/4.6.2-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/GodotIO.java#L203-L237) · [Android WindowInsets](https://developer.android.com/reference/android/view/WindowInsets)

第 492 物理帧取同一艘母舰与第一档雨燕。母舰精灵的不透明像素外框由约 83×59 扩至 112×79，雨燕为约 67×62。淡出亮度的翼片延伸到碰撞圆之外，亮装甲和中央炮口标示交火目标。盾弧包住舰身，光束从同一世界坐标发出。单人和双端使用同一套精灵及受击缩放。

```bash
out=$(mktemp -d)
mkdir -p "$out"/{desktop,16x9,20x9}
godot --headless --path . --import
godot --path . --windowed --resolution 1280x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- verify "$out/desktop"
godot --path . --windowed --resolution 1280x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- verify "$out/16x9" touch inset
godot --path . --windowed --resolution 1600x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- verify "$out/20x9" touch inset
godot --path . --windowed --fixed-fps 60 --audio-driver Dummy res://tests/boss_laser_visual_probe.tscn
godot --headless --path . res://tests/mobile_check.tscn
python3 tests/run_first_card_probe.py "$out/first-card"
bash tests/run_probe.sh 19301
bash tests/run_probe.sh 19302 boss
bash tests/run_probe.sh 19303 feedback
```

同帧旧图由 `3280d59` 的原探针用相同窗口和时钟参数取得。图形探针模拟两指、旧触摸跨奖励、暂停、后台通知和重试。两台实体手机的系统边距、物理手柄和触屏手感待验。

#### 技能栏的拇指留白

手机端由技能栏自己的留白控制右下位置。三个按钮和完整热区同时向左、向上移。验收用相同战斗帧比对两种画幅、左右镜像缺口和无缺口的圆角模型，并通过两指确认移位后的技能仍能点中。普通选卡、移动和技能各走自己的输入。

在六种模拟布局的第 622 帧，技能栏距安全区右边和底边从 18／18 实测为 48／56 个画布单位。单个热区仍为 94×94，间距 8，桌面保持 18／18。左手继续推摇杆时，右手按移位后按钮的边缘能发动技能，三选一仍待确认。旧右下角的触点不会发动技能。实拍中技能组留在战斗画面的右侧下方，和中央交火区及卡组有间隔。实体手机的拇指触达待验。

```bash
out=$(mktemp -d)
godot --path . --windowed --resolution 1600x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- verify "$out" touch inset inset-left
```

也可换成 1280×720。分别使用 `inset-left`、`inset-right`、`inset-rounded`，日志 `[SKILL_RECT]` 会输出实际热区与边距。

#### 积分区的圆角留白

移动端积分区距画布横边至少 40 单位、距上边至少 32 单位。系统安全区给出更严格的边界时沿用系统位置和原边距。P1 积分在右侧，P2 积分在左侧，字号沿用原值。长分数以实际文字最小宽度向内扩展，桌面保留原锚点。

在 `5b991de` 上叠半径 92 单位的圆角遮罩，19 位总分最外侧只剩 5 单位边距，比分末位被裁。修复后边距为 40，首行距顶 32。用 16:9 和 20:9 核对无切口、左右横屏切口和上切口。两个画幅的实拍各通过 19 项，两个画幅交换房主的双进程各通过 40 项，桌面通过 5 项。双人比分分别用 19 位数字，比分保持完整且与母舰血盾条无交叠。遮罩由探针绘制，手机实测待复核。

```bash
godot --headless --path . res://tests/score_safe_area_probe.tscn -- solo 0 desktop
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19931 score-safe-wide-client
PROBE_KEEP_LOGS=1 bash tests/run_probe.sh 19932 score-safe-wide-host
godot --audio-driver Dummy --windowed --resolution 1280x720 --path . \
  res://tests/score_safe_area_probe.tscn -- solo 0 capture /已有目录
```

20:9 图形复跑使用 `--resolution 1600x720`，在 `capture` 前加 `wide`。

### 首版复跑

用 Godot 4.6.2 在同机截取两版。这组历史命令使用当时版本的探针。复现基线时，将母舰首版的 `tests/battle_presentation_probe.gd` 复制到 `c26defe` 临时副本。候选版用 `verify` 校验顶部血条、选卡、输入和真实扣血。两版分别把输出写入已存在的目录。

```bash
godot --windowed --resolution 1280x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- capture /已有目录/16x9 verify
godot --windowed --resolution 1600x720 --fixed-fps 60 --disable-vsync --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- capture /已有目录/20x9 touch verify
tests/run_probe.sh 18599 boss
tests/run_probe.sh 18600
tests/run_probe.sh 18601 feedback
godot --headless res://tests/mobile_check.tscn
godot --headless --fixed-fps 60 res://tests/combat_visual_probe.tscn
```

基线命令省去 `verify`。实拍的蓄力、推进、解除和可攻击分别取第 492、622、1345 和 1430 物理帧。测试脚本提交键盘或触屏事件，保留引擎的走位、碰撞和激光绘制。擦弹加速按墙钟衰减，后段计入的蓝色主炮弹数可不同。

联机专项用真实 ENet 双进程，跑完一次完整激光。加入端先通过现有实体快照保留正在画的光束，再模拟光束绘制节点缺失并恢复当前进度。解除后重发一次解除、上一阶段、旧快照和其他实体编号，验证碎片和顶部提示只出现一次。受保护与可攻击阶段各用一次真实主炮碰撞，随后再击毁并拾取六件掉落。图形模式可分别用 `-- host <端口> capture <已有目录>` 与 `-- client <同端口> capture <已有目录>` 抓取两端画面。并排验收时，让两个窗口各有一部分可见。

### 本机验收

- `c26defe` 的双进程复现里，实体快照替换了同一艘母舰。顶部仍显示蓄力和护盾，舰体护盾却已消失。
- 16:9 实拍通过 24/24，20:9 实拍通过 28/28。第 622 帧，两种画幅各抽样 3,734 个暖色弹幕像素和 25,871 个光束区域暖色像素。对应像素的坐标和颜色均与基线一致。母舰肩甲在光束外仍可辨认，顶部生命条和选卡互不重叠。
- Boss 专项无窗口房主 47/47、加入端 43/43。双窗渲染房主 48/48、加入端 44/44。主炮碰撞时，有盾保持 936.67 生命值，解除后降为 928.67，加入端收到相同的扣血。每端只显示一次碎裂和解除，六件掉落的坐标、顺序、归属及奖励次数通过核对。
- 常规联机 40/40，反馈联机 25/25，宽窄端轮换房主各 29/29。单人渲染专项 32/32，覆盖盾片与前景敌弹的同帧像素、碎片释放与击毁。桌面模拟触屏 13/13，战斗画面 21/21，导入及主场景启动通过。常规联机仍有已知的入场寻址消息，立即退出时仍可见引擎对象清理提示。
- 桌面模拟触屏与键鼠输入、同机双进程联机均已覆盖。真人辨识与手机双机未验。

## 固定的生产假设

- 游戏类型：2D 俯视角 Roguelike 弹幕射击
- 视觉：像素风 / 街机高对比，2D 精灵
- 范围规则：先保证联机与战斗节奏稳定，再谈资产替换
- 主原则：**零外部依赖**——引擎刚装好、仓库刚 clone 下来就能跑出完整画面与音效

## 战斗反馈试听

同一场景可运行 `godot --headless --fixed-fps 60 res://tests/combat_feedback_probe.tscn` 验证，图形模式用 `--write-movie /已有目录/frame.png` 导出逐帧画面和立体声 WAV。录制包含主炮、两次破盾、精英击毁，以及夹在密集命中间的玩家受击和 Boss 激光蓄力。对照时用同一背景音乐、事件帧和播放电平，静音时检查火花、击毁轮廓及敌弹遮挡。

双进程运行 `bash tests/run_probe.sh 7855 feedback` 可核对房主及加入端的命中、两次破盾、击毁和 P2 受击。精英当前的回盾计时器只重置计时，用例通过既有护盾快照注入正值，以覆盖第二次破盾。无窗口实时时钟检查可运行 `godot --headless res://tests/combat_feedback_probe.tscn -- realtime audio-tail`，等待受击声在连续开火中自然播完。

## 战斗界面、远行与裂隙

设计来自本项目的三张 HUD 稿与《远行与裂隙》合成对照。战斗层用正式机体、弹体、激光与命中效果实拍。用 `70f2ad1` 和新版本分别录制 1280×720、1600×720。检查蓄力、推进和开盾结束时的状态读数，三选一与激光同画时的遮挡，以及移动、选卡和自动开火是否可同时操作。

配乐采用原创草案的 `cruise-softlead-loop.wav` 与 `boss-softlead-loop.wav`。两段都是 132 BPM（每分钟拍数）、八小节，柔起音的制作逻辑由 `compose.py` 与 `lead-ab.py` 保存。验收在相同输出电平下听巡航、激光报警、命中和玩家受伤，检查循环跨接、重试及离开场景时的播放实例数。

太空底图由 `scripts/generate_assets/make_backdrops.py` 离线生成，源自本项目的 `SBH-Space-Background-AB.png` 与 `space.py`。巡航的冰蓝行星斜切右缘，裂隙的冷紫尘带环绕外侧。生产场景用两张 800×450 底图和两层平铺星野，各自按本机画布显示。每块星野合计 36 个星点。图像生成需 NumPy 和 Pillow，Godot 运行时读取 PNG。

两段 WAV 均为 44.1 kHz 双声道，641455 个采样帧（约 14.545 秒）。在 Godot 中整段循环，换段由同一个音乐播放器先淡出 160 毫秒、切流、再淡入 340 毫秒。激光预警与玩家受击沿用原有声部，并让音乐短暂降 6 dB。连续受击会延长衰减窗口。房主与加入端收到相同的阶段值，各自淡入淡出。重试回到巡航，从战斗退回标题时停播。

### 实拍与混音

MacBook 用 Godot 4.6.2 录制了两版的 1280×720 与 1600×720。第 622 物理帧一边是旧版重叠的血条与卡面，一边是新版独立两行。两版同帧的机体位置一致，两种画幅都能看见光束起点和穿过中场的暖色弹幕。宽屏触摸用脚本把两根独立的屏幕触点交给视口，左指持续移动，右指确认第二张卡，期间自动射击继续。斜向光束来自 Boss 的原推进入口。录制脚本固定出场和选卡帧，收口墙钟驱动的命中定格并安排走位，保留真实弹体碰撞、扣血、激光、命中和击毁。

原始混音由引擎以 48 kHz 输出。每版 1512 帧、25.2 秒，连续拼接且保持同一主输出电平。Boss 在约 5.2 秒切入，7.3 秒鸣响激光预警，10.4 秒出现激光与选卡同帧，23.8 秒击败并切回巡航。基线峰值 −5.73 dBFS，候选峰值 −5.38 dBFS，均无满幅削波。候选的两段报警音、实际扣血和早段命中均能在原始混音中定位。音轨边界的相邻样本差不超过满幅的 0.055%，引擎循环没有更换播放实例。手机扬声器和真人听辨尚未验收。

背景显示与隐藏各通过 5 项，种子 1121 的出场轨迹、抽卡与扣血日志逐行一致。图形回放在 16:9 通过 16 项，在 20:9 通过 20 项。移动端交互门禁 13/13，首卡固定轨迹 194/194，按键与超时的四条完整流程全部通过。房主和加入端从巡航打到 Boss 击败，再结算、重试和退回标题。无窗口 Boss 专项 70/70，分别用 1280×720 和 1600×720 实拍再通过 72/72。常规联机 40/40、反馈联机 25/25，宽窄端分别当房主的真实渲染各 36/36。音乐单场景 13/13，覆盖循环、切换中断、叠加预警和停播。普通局域网单次复跑仍可见既有入场寻址消息，立即退出时还可能出现 Godot 音频对象清理警告。

### 复跑

在仓库根目录运行。先确保 Git LFS 素材已下载。图形命令使用 [Godot Movie Maker](https://docs.godotengine.org/en/4.6/tutorials/animation/creating_movies.html) 导出引擎画面和原始混音。16:9 两版各写一段有声录屏，20:9 两版各留五张原尺寸帧。对照的图片文件名为 `cruise.png`、`charge.png`、`laser-and-draft.png`、`laser-hold.png`、`cruise-return.png`。

```bash
out=$(mktemp -d)
mkdir -p "$out"/{baseline,A16,A20,B16,B20,wide-host,wide-client}
git archive 70f2ad1 | tar -x -C "$out/baseline"
for ext in gd tscn; do
    git show "4c1d0d6:tests/battle_presentation_probe.$ext" > "$out/baseline/tests/battle_presentation_probe.$ext"
done
godot --headless --path "$out/baseline" --import
godot --headless --path . --import
godot --path "$out/baseline" --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy \
  --write-movie "$out/A16/engine.avi" res://tests/battle_presentation_probe.tscn -- capture "$out/A16"
godot --path . --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy \
  --write-movie "$out/B16/engine.avi" res://tests/battle_presentation_probe.tscn -- verify "$out/B16"
godot --path "$out/baseline" --windowed --resolution 1600x720 --fixed-fps 60 --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- capture "$out/A20" touch
godot --path . --windowed --resolution 1600x720 --fixed-fps 60 --audio-driver Dummy \
  res://tests/battle_presentation_probe.tscn -- verify "$out/B20" touch

godot --headless --path . --quit
godot --headless --path . --scene res://scenes/main.tscn --quit-after 20
godot --headless --path . res://tests/mobile_check.tscn
godot --headless --path . res://tests/battle_music_probe.tscn
python3 tests/run_first_card_probe.py "$out/first-card"
for state in visible hidden; do
  godot --headless --path . --fixed-fps 60 res://tests/battle_backdrop_probe.tscn -- "$state" > "$out/$state.log" || exit 1
done
diff -u <(rg '^\[TRACE\]' "$out/visible.log") <(rg '^\[TRACE\]' "$out/hidden.log")
bash tests/run_probe.sh 19119
bash tests/run_probe.sh 19113 feedback
bash tests/run_probe.sh 19118 boss
bash tests/run_probe.sh 19116 wide-host "$out/wide-host"
bash tests/run_probe.sh 19117 wide-client "$out/wide-client"
```

用安装了 NumPy 的 Python 运行 `python3 scripts/generate_assets/music/lead-ab.py "$out/loop-rebuild"`，可从同目录的 `compose.py` 复原 `assets/audio/` 内两段最新版 WAV。原始文件与重新生成的文件逐字节一致。

## 普通命中与普通敌机击毁的 PixelFX 对照

图集只用于玩家弹体击中普通敌机，以及普通敌机击毁。玩家受伤、陨石、精英和 Boss 的接触沿用原画，主炮击盾和核心拾取各走原有的专用画法。武器在扣血前确定目标类别，加入端按房主确认的类别绘制。验收以 `0939598` 的真实玩家扣血画面为参照，在同视口、同落点、同为 35 毫秒时比对像素；普通命中和击毁继续对照已通过的 B。

两版的玩家都从 50 血降到 49。受击火花在 `0939598` 占 11×11 像素，`3681e25` 扩成 15×16，修复后的整张透明帧与 `0939598` 相同。主炮、激光、导弹和溅射命中普通敌机时仍与 B 相同。回归使用从两个历史提交实际渲染出的参考帧。运行 `godot --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy res://tests/impact_scope_probe.tscn` 可检查像素与落点；追加 `-- verify /已有目录` 可留图，本轮含保存检查共 43/43。普通特效六组实拍的逐帧测量与原报告一致。修复后的反馈联机为房主 12/12、加入端 13/13，新增检查覆盖普通、带盾和破盾后的三种接触。[玩家受击的三版同帧图](../deliverables/pixelfx/player-hurt-35ms.png)

采用 B。左侧 A 是 `09395981e6d8ea47e28e3824f9b376170ca9b2d6`。在同一轮三机交火中，B 的冰蓝火花标在弹体接触处，敌机消失时，暖色亮闪从机体中心散成几块碎片。横穿两处的橙红敌弹都能沿原轨迹追踪。视频前 2.33 秒按原速和原倍率播放，后半段把单次反馈放慢到四分之一速，并另取隐藏敌弹图像的两次渲染展示火花和碎片本身。[同屏视频](../deliverables/pixelfx/ordinary-feedback-ab.mp4) · [前景敌弹与关闭特效的同帧对照](../deliverables/pixelfx/projectile-overlap.png)

| 原倍率检查 | Godot 4.6.2 桌面实拍，每秒 60 帧 |
| --- | --- |
| 接触与退场 | F032 命中 `(640,320)`，B 当帧在接触处亮起，F037 为末帧。F064 普通敌机在 `(640,300)` 击毁，B 的碎片在 F072 后消失。对应 100、150 毫秒。A 的两次起帧都曾画在屏幕左上角。B 为这两种静止特效关闭出生位置插值。 |
| 连续交火 | 固定 8 次开火及接触，击毁 4 架。A、B、关闭特效及各自隐藏敌弹图像的 6 组录像，每组 140 帧。逐帧的敌弹和特效坐标相同。100 个没有特效节点的时刻，A、B 和关闭特效的全屏像素相同。 |
| 前景遮挡 | F034 敌弹中心与接触点重合，F066 与击毁中心重合。用隐藏敌弹的同帧找出弹体下方确有特效的位置。A 的 4,096 个、B 的 2,611 个重叠像素样本，各自都与关闭特效时的前景颜色完全相同。 |
| 释放与重启 | 8 次命中、4 次击毁均退场。当前 `Pool.release` 会注销并释放节点。另将同一节点依次切换为普通、护盾、核心、普通，与新节点同帧逐像素比对。护盾和核心也分别与 A 比对。 |

**素材与运行时**　命中取自 `bullet-impact` 的开头。以实际火花 `(116,60)` 为中心裁切、旋转四分之一圈，落在 31×31 小格的 `(15,15)`。上游的默认锚点 `(116,84)` 在接触点下方 24 像素。击毁取自 `big-explosion` 的初闪和受光碎块，按俯视角向四周散开。游戏只读取六帧和九帧的透明图集，缺少图集时沿用原先的程序绘制。图集可用 Node.js、Python 和 Pillow 在仓库根目录离线重建，命令为 `node scripts/generate_assets/make_pixelfx.mjs /path/to/pixelfx`。Android 资源包随图集附带授权与署名。[上游固定版本](https://github.com/patch-gg/pixelfx/tree/5294518ce7c72e48b6100a744596e0acf57f2826) · [MIT 授权与原始 NOTICE](../assets/sprites/explosion/PixelFX-LICENSE.txt)

**复跑**　下列命令在本仓库根目录运行，需要 Git LFS（大文件存储）中的素材已下载。A 导出到临时目录，两版使用同一份夹具。夹具在指定帧调用正式子弹接触回调，危险弹按正常物理步进飞行。六组图像只切换绘制，碰撞回调和时间线相同。

```bash
out=$(mktemp -d)
mkdir -p "$out"/{baseline,A,B,OFF,A-clear,B-clear,OFF-clear}
git archive 0939598 | tar -x -C "$out/baseline"
for ext in gd tscn; do
    git show "4c1d0d6:tests/pixelfx_probe.$ext" > "$out/baseline/tests/pixelfx_probe.$ext"
done
godot --headless --path "$out/baseline" --import
godot --headless --path . --import
take() {
    local project=$1 name=$2
    shift 2
    godot --path "$project" --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy \
        res://tests/pixelfx_probe.tscn -- capture "$out/$name" "$@"
}
take "$out/baseline" A
take . B
take . OFF off
take "$out/baseline" A-clear hide-bullets
take . B-clear hide-bullets
take . OFF-clear off hide-bullets
python3 tests/compare_pixelfx.py "$out"
```

回归在配有 Radeon Pro 5300M 的 MacBook 上完成。无窗口检查通过战斗画面 21/21、战斗反馈 14/14、PixelFX 事件与释放 14/14。每组实拍另做 3 项同节点重启的像素断言，共 17/17。移去两张图集的独立副本里，程序绘制的普通火花和击毁也与 A 的对应像素吻合。[逐帧测量结果](../deliverables/pixelfx/measurements.json)

双进程局域网回归中，常规房主 24/24、加入端 16/16，反馈房主 9/9、加入端 10/10，四个进程均退出 0。一次建房遇到本机 7897 端口占用，换到空闲端口后完成复跑。

```bash
godot --headless --fixed-fps 60 --path . res://tests/combat_visual_probe.tscn
godot --headless --fixed-fps 60 --path . res://tests/combat_feedback_probe.tscn
godot --headless --fixed-fps 60 --path . res://tests/pixelfx_probe.tscn
bash tests/run_probe.sh 17943 feedback
bash tests/run_probe.sh 17944
```

### 静止命中特效的出生坐标

静止命中效果以调用方提供的世界坐标为准。主炮接触点、溅射目标当时的位置和房主确认的历史接触点，在效果入树前换算成场景局部坐标。该节点关闭物理插值。火花留在原位，随镜头取景。冰白、护盾、普通敌机图集和核心金环沿用各自的图样、时长与层级。

Godot 4.6.2 在同一平移和缩放的父节点下，以每秒 120 帧渲染两次远隔接触、盾面火花和普通敌机图集。目标与取景均逐帧移动。基线 `0acdea8` 的两处冰白火花和盾面火花都在首帧出现在父节点原点，第二次冰白火花的首帧中心约为 `(62,42)`，该帧接触点为 `(413,200)`。修复后的首帧中心约为 `(413,201)`，四组全程落点与释放为 8/8。同龄像素与武器接触检查为 29/29，包含玩家扣血、直击、激光、导弹和溅射。真实双进程反馈门禁，房主 13/13、加入端 14/14。加入端的场景有偏移，房主将精英的历史接触包延后 100 毫秒发送，期间目标移位。两端在同一世界落点创建火花。

```bash
out=$(mktemp -d)
godot --windowed --resolution 1280x720 --fixed-fps 120 --audio-driver Dummy \
    res://tests/impact_scope_probe.tscn -- anchors "$out"
godot --windowed --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy res://tests/impact_scope_probe.tscn
bash tests/run_probe.sh 18753 feedback
```

这组桌面样本复现了偏位机制。玩家反馈中的当时画面与手机上的表现待验。

手机双机、手机屏幕上的辨识度及真人盲测尚未验收。回退时执行 `git revert <本批提交 SHA>`。

## 视觉方向

- **基础参考**：Contra / Metal Slug 时代的街机可读性
- **实现**：2D `Sprite2D` + 低分辨率程序化贴图 + 最近邻过滤（`default_texture_filter=0`）
- **光照**：不用实时光照，用颜色与辉光营造高对比
- **可读性优先**：玩家、弹幕、精英、Boss 必须一眼分得开；任何特效不得遮挡弹幕
- **动画**：靠贴图缩放 / 旋转 / 颜色渐变实现，不引入骨骼动画

## 资产来源

### 程序化生成（`scripts/visuals/sprite_factory.gd`）

| 资源 | 函数 |
|------|------|
| 玩家飞机（随等级增大） | `create_player_sprite(level)` |
| 敌人（3 种类型） | `create_enemy_sprite(type)` |
| 精英 | `create_elite_sprite()` |
| 子弹（带缓存） | `create_bullet_sprite(is_player, level)` |
| 道具（5 种形状，带缓存） | `create_powerup_sprite(type)` |
| 小行星纹理 | `apply_asteroid_texture(sprite, size)` |
| 爆炸序列帧 | `create_explosion_frames()` |
| 战斗背景 | `make_backdrops.py` 生成全幅图，`battle_backdrop.gd` 生成两层星野 |

### 外部资产（仅此几处）

| 资源 | 路径 | 说明 |
|------|------|------|
| Boss 贴图 | `assets/sprites/enemies/boss/boss_01.png`~`boss_05.png` | 项目脚本生成，沿用出场轮换与阶段换型 |
| 玩家等级外形 | `assets/sprites/player/variants/lv01.png`~`lv05.png` | 每 5 级一档 |
| 技能图标 | `assets/sprites/ui/skill_{laser,skill,dash}.png` | HUD 技能槽，**规格见下节** |
| 图标 | `assets/sprites/ui/icon.png` | 项目图标 |

以上路径固定，新增外形必须沿用命名规则，缺失时才回退程序化占位图。

### 第一档雨燕

第一档雨燕用 `python3 scripts/generate_assets/make_swift.py` 离线生成。两架 48×48 机体采用同一透明轮廓，色阶与机腹标记分别绘制，短尾焰共用一张贴图。双炮口对应机身局部坐标 (±12, −24)，尾焰节点在 (0, 32)。关闭 `feedback_controller.gd` 的 `USE_SWIFT_HULL` 即可恢复首档旧外形。旧等级贴图和缺图时的程序化机体继续可用。

八个朝向都用游戏里的慢速敌弹做了对照。本机渲染时，品红色与原有红色弹体贴图相乘，弹芯实际偏红（取样 `#DC1118`）。P2 靠机腹的两个亮点与 P1 区分。以后调整慢弹贴图时，应把两架雨燕一起放回弹幕里复看。

P1 精修以 `3d960c3` 为对照，只在既有剪影内调整像素。用连续亮边勾出机头与掠翼，座舱受光面和机腹暗面分开，两个喷口各有暗槽。机腹保留一条中线，最亮的一段落在真实碰撞圆的圆心。验收用同一段密集弹幕，以 1280×720 原倍率看 P1 机头、圆心和旁边的 P2 双标记。

本机固定走位回放共 180 帧，同屏有 136 至 153 枚敌弹。173 帧能看到中线最亮的一段，位置距圆心最多 1.4 像素。另 7 帧是前景敌弹经过圆心。短尾焰距碰撞圆外缘至少 4.3 像素。首次看到机体的玩家能多快认出朝向和受击位置，留给试玩判断。

### 抬头显示（HUD）技能图标的像素画规格

`assets/sprites/ui/skill_*.png` 三张必须规格一致，规格是**实测反推**出来的：

| 项 | 值 | 怎么测出来的 |
|---|---|---|
| 画布 | 128×128 RGBA | 直接读 |
| 网格 | 在 32×32 上作画，最近邻放大 **4 倍** | 统计同色连续像素块长度，恒为 4 |
| 色彩 | 深色描边 + 3~5 级明度阶梯，色数 ≤11 | 统计不同 RGB 值个数 |
| 导入 | `compress/mode=0`（无损）、`mipmaps/generate=false` | 读 `.png.import` |

**为什么不用图像模型直接出图标**（2026-09-28 实测，出过 3 轮共 12 张候选）：
模型输出是大面积近乎同色的平滑渐变，512 → 32 的面积平均会把细描边冲掉、
把镂空填满，落到 32×32 上只剩两三个亮色档，形状糊成一坨圆饼。
**像素画能用是因为形状由少量、刻意的大色块构成，平滑渲染缩小只会变饼。**

所以定下这条规矩：**造型可以来自模型，工艺必须由代码保证**。
新增 HUD 图标走 `scripts/generate_assets/make_skill_icon.py`——
直接在 32×32 网格上按块画，明暗分层由到描边的距离决定，天然就是像素画。
该脚本也保留了 `ai` 子命令（抠底 + 裁剪 + 量化 + 补描边）供其他题材复用。

**方向语义要在出图前就定死**：闪避试过朝左的构图（更好看），
但闪避是"向前突进"语义，朝左会被玩家读成"向左移动"，否掉了。
最终造型是朝右的双人字箭头（`»`，快进/冲刺的通用符号）+ 左侧速度残影。

### 动态绘制（不占贴图）

| 效果 | 实现 |
|------|------|
| 玩家护盾环 | `shield_ring.gd` `draw_arc()` |
| 普通命中 / 核心确认 | `hit_effect.gd` 在世界层级 −1 绘制 0.10 秒冰色火花或 0.30 秒金色断环。沿用 `Pool` 取用与释放，每次效果共用一个绘制节点。 |
| 精英护盾光晕 | `shield_circle.gd` |
| 母舰护盾细弧 | `boss.gd` 按房主盾相位绘制。冷青为打盾触点，暖白为打本体，破盾用原位短碎片。[验证](boss_shield_rhythm.md) |
| 破盾碎裂 | `shield_shatter_burst.gd` |
| 激光光束 | `laser_bolt.gd` `_draw()` 三层线叠加 |
| 闪电链 | `lightning_line.gd` 锯齿线 |
| 终局激光 | `boss_ultimate_laser_visual.gd` 绘制蓄力和余烬，`boss_laser_beam.gdshader` 绘制圆端帽与两圈危险边界 |

## 音频

音效在运行时合成，主题音乐由仓库内的原创脚本离线合成。

| 模块 | 说明 |
|------|------|
| `sfx_manager.gd` | 8-bit 风格音效：射击 / 玩家受击 / 敌人受击 / 敌人死亡 / 爆炸 / UI 确认 / UI 选择。玩家射击使用独立播放器池，避免 Boss 战音效抢占 |
| `bgm_manager.gd` | 战斗巡航与 Boss 变奏共用四音动机，分别整段循环 |
| Boss 阶段 | 房主的阶段通知同时切换底图与配乐，两端各自淡入淡出 |

## 生产顺序

1. 保持程序化管线的完整性（任何新实体优先程序化出图）
2. 联机链路与战斗节奏打磨
3. 只在程序化表现确实不足时，才为关键形象补外部资产
4. 外部资产一旦引入，必须同时提供程序化回退

## 文档交叉引用

- `docs/architecture.md`：代码结构唯一权威
- `docs/Design_Decisions.md`：冻结的范围与设计意图
- `agents.md`：Agent 轮次工作规则
