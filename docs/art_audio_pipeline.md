# 美术与音频管线

本项目的美术与音频**以程序化生成为主**，外部资产只覆盖少数关键形象。

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
cp tests/pixelfx_probe.{gd,tscn} "$out/baseline/tests/"
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

手机双机、手机屏幕上的辨识度及真人盲测尚未验收。回退时执行 `git revert <本批提交 SHA>`。

## 视觉方向

- **基础参考**：Contra / Metal Slug 时代的街机可读性
- **实现**：2D `Sprite2D` + 低分辨率程序化贴图 + 最近邻过滤（`default_texture_filter=0`）
- **光照**：不用实时光照，用颜色与辉光营造高对比
- **可读性优先**：玩家、弹幕、精英、Boss 必须一眼分得开；任何特效不得遮挡弹幕
- **动画**：靠贴图缩放 / 旋转 / 颜色渐变实现，不引入骨骼动画

## 资产来源

### 程序化生成（`scripts/sprite_factory.gd`）

| 资源 | 函数 |
|------|------|
| 玩家飞机（随等级增大） | `create_player_sprite(level)` |
| 敌人（3 种类型） | `create_enemy_sprite(type)` |
| 精英 | `create_elite_sprite()` |
| 子弹（带缓存） | `create_bullet_sprite(is_player, level)` |
| 道具（5 种形状，带缓存） | `create_powerup_sprite(type)` |
| 小行星纹理 | `apply_asteroid_texture(sprite, size)` |
| 爆炸序列帧 | `create_explosion_frames()` |
| 星空背景 | `create_star_field(width, height, count)` |

### 外部资产（仅此几处）

| 资源 | 路径 | 说明 |
|------|------|------|
| Boss 贴图 | `assets/sprites/enemies/boss/boss_01.png`~`boss_05.png` | 每次出场轮换，避免连续重复 |
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
| 精英/Boss 护盾光晕 | `shield_circle.gd` |
| 破盾碎裂 | `shield_shatter_burst.gd` |
| 激光光束 | `laser_bolt.gd` `_draw()` 三层线叠加 |
| 闪电链 | `lightning_line.gd` 锯齿线 |
| 终局激光 | `boss_ultimate_laser_visual.gd` 36 段渐变切片 |

## 音频

全部程序化合成，无音频文件：

| 模块 | 说明 |
|------|------|
| `sfx_manager.gd` | 8-bit 风格音效：射击 / 玩家受击 / 敌人受击 / 敌人死亡 / 爆炸 / UI 确认 / UI 选择。玩家射击使用独立播放器池，避免 Boss 战音效抢占 |
| `bgm_manager.gd` | 正弦波合成的标题 / 游戏 / 结果主题，Pad + 贝斯 + 旋律 + 底鼓四层，12 秒循环 |
| Boss 阶段 | 进入 Boss 战切换独立背景色与更高音高/音量的 BGM，结束后恢复 |

## 生产顺序

1. 保持程序化管线的完整性（任何新实体优先程序化出图）
2. 联机链路与战斗节奏打磨
3. 只在程序化表现确实不足时，才为关键形象补外部资产
4. 外部资产一旦引入，必须同时提供程序化回退

## 文档交叉引用

- `docs/architecture.md`：代码结构唯一权威
- `docs/Design_Decisions.md`：冻结的范围与设计意图
- `agents.md`：Agent 轮次工作规则
