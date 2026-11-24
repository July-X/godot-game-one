extends Node
## ── 波次编排器（Wave Director）────────────────────────────────────
##
## 设计文档：docs/level_design_proposal.md
##
## ## 改造前的关卡长什么样
##
## main.gd 里只有两个定时器：
##   1. 每 `max(1.2 - level*0.06, 0.45)` 秒刷 1 只敌人（main.gd `_process`）
##   2. 每 8 秒再无条件补 1 只（"难度脉冲"）
## 而 `_spawn_enemy()` 里敌人类型是 `randi() % 3`、出生点是四条边各 1/4 概率。
##
## 这套做法能跑，但有三条结构性缺陷：
##   - **没有形状**：同屏压力是一条恒定直线。张弛没了，玩十分钟和玩一分钟手感相同。
##   - **没有构图**：敌人永远是随机散点。屏幕上从来不出现"一条横线压过来"
##     或"两侧同时夹击"这种可读的图案，弹幕也就谈不上美感。
##   - **没有主题**：第 30 分钟和第 1 分钟是同一种游戏，只是血厚了一点。
##
## ## 改造后的关卡是什么
##
## 一关 = 一段 **4 拍乐句**：起拍 → 涨潮 → 浪峰 → 退潮，各 16 秒，合计 64 秒。
## 每一拍有自己的敌人配比、阵型词表、投放间隔。强度不是"更大"，而是"更有形状"：
##   - 涨潮把屏幕填满，浪峰压到章节平均的 1.49 倍，退潮回落到 0.35 倍，
##     玩家终于能把屏幕清干净、喘口气、把弹道读明白。
##     没有退潮就没有浪峰的压迫感——这是整套设计唯一真正的新东西。
##
## ## 一条硬约束
##
## `PHASE_SHAPE` 的四个数之和**恰好等于 4**，于是
## 「一章的平均投放速率 ≡ 旧版随机刷怪的速率」。
## 这次改造只重新分配强度在时间轴上的分布，**不允许偷偷把难度拉高**。
## tests/wave_probe.gd 会把这条当门禁守住，任何人日后改数值都会被立刻抓住。

signal phase_changed(phase_index: int, phase_name: String)

# ── 乐句结构 ────────────────────────────────────────────────────

const PHASE_SETUP: int = 0
const PHASE_SURGE: int = 1
const PHASE_CREST: int = 2
const PHASE_LULL: int = 3

const PHASE_COUNT: int = 4
## 每拍时长（秒）。四拍等长是刻意的：只有等长，"四拍形状的均值 = 1"
## 这条换算才不需要再乘一层时长权重，改数值时也不会算错。
const PHASE_SECONDS: float = 16.0
## 一章 = 4 拍 = 64 秒。
const CHAPTER_SECONDS: float = PHASE_SECONDS * float(PHASE_COUNT)

const PHASE_NAMES: Array[String] = ["起拍", "涨潮", "浪峰", "退潮"]
const PHASE_COLORS: Array[Color] = [
	Color(0.55, 0.85, 1.0), Color(1.0, 0.84, 0.32),
	Color(1.0, 0.42, 0.28), Color(0.50, 1.0, 0.70),
]

## 每一拍相对"旧版平均速率"的倍率。
## 和必须**恰好为 PHASE_COUNT**，否则章节平均强度就偏离旧版曲线（难度墙就是这么长回来的）。
## 对照关系：起拍 0.910（−9%）、涨潮 1.254（+25%）、浪峰 1.486（+49%）、退潮 0.350（−65%）。
## 浪峰/退潮 ≈ 4.25 倍，这就是整套设计的支点：没有低谷就没有峰值。
##
## 退潮为什么**不取 0**：最初写成"退潮一只不刷"，实测高等级会出现
## 连续 16 秒的空屏——那不叫喘息，叫掉线。弹幕射击的空屏本来就该用
## 少量低威胁敌人填着，所以退潮改成 1 只一批的涓流：
## 压力掉到浪峰的四分之一，但屏幕上永远有事可做。
const PHASE_SHAPE: Array[float] = [0.910, 1.254, 1.486, 0.350]

## 每拍两次阵型投放之间的最短间隔（秒）。
## 它只是"闸门"，真正的投放速率由 `threat_rate()` 累加出来的威胁预算决定——
## 闸门只用来防止预算攒够后一次性倒出一大坨。
## 上限由 tests/wave_probe.gd 的 `throughput_supports_rate` 反推：
## 闸门必须撑得住设计速率，否则预算被饿死、实际强度低于设计。
const FORMATION_INTERVAL: Array[float] = [2.6, 1.9, 1.6, 1.2]
## 同一阵型内部的错峰间隔（秒）。阵型要有"列队进场"的节奏感，
## 同时错峰又保证预警线（enemy.gd 的 WARN_DURATION）不会全部叠在一起变成噪音。
const FORMATION_STAGGER: float = 0.12
## 威胁预算上限。限制的是"预算积压"，不是"同屏数量"——后者由 ENEMY_SCREEN_CAP 管。
const BUDGET_CAP: float = 16.0
## 开局预置预算（只给一次，不影响长期速率）。
## 没有它，第一波阵型要等 budget 攒满 3 点才出现——按起拍速率约 3.4 秒，
## 玩家开局会盯着空屏发呆。1.6 点 ≈ 1.6 秒后第一波进场，手感上"一上来就有事"。
const OPENING_BUDGET: float = 1.6

# ── 旧版刷怪节奏（校准基准，只读）────────────────────────────
#
# 复制自 main.gd 改造前的刷怪参数。这里刻意不做成引用 main.gd 的常量：
# main.gd 反过来 preload 本脚本，互相 preload 会成环。
# 两者一旦不一致，tests/wave_probe.gd 的 `rhythm_baseline_matches_main`
# 断言会立刻报错。

const LEGACY_BASE_INTERVAL: float = 1.2
const LEGACY_PER_LEVEL: float = 0.06
const LEGACY_MIN_INTERVAL: float = 0.45
const LEGACY_PULSE_SECONDS: float = 8.0

# ── 阵型词表 ───────────────────────────────────────────────────

const FORMATION_LINE: String = "line"
const FORMATION_COLUMN: String = "column"
const FORMATION_VEE: String = "vee"
const FORMATION_PINCER: String = "pincer"
const FORMATION_RING: String = "ring"
const FORMATION_SWARM: String = "swarm"

const ALL_FORMATIONS: Array[String] = [
	FORMATION_LINE, FORMATION_COLUMN, FORMATION_VEE,
	FORMATION_PINCER, FORMATION_RING, FORMATION_SWARM,
]

## 每拍允许使用的阵型。限词表是为了让每一拍有自己的性格，
## 而不是把 6 个阵型随机撒到 4 拍上——那等于没编排。
## 退潮只留最轻的两个：涓流要的是"清得掉"，不是"清得累"。
const PHASE_FORMATIONS: Array = [
	[FORMATION_LINE, FORMATION_COLUMN],
	[FORMATION_VEE, FORMATION_PINCER, FORMATION_SWARM],
	[FORMATION_RING, FORMATION_LINE, FORMATION_PINCER],
	[FORMATION_SWARM, FORMATION_COLUMN],
]

## 阵型 → 敌人类型。0=狙击手(高速单发) 1=散射者(中速三连) 2=环绕者(慢速六连环)。
## 配对的原则是**让阵型看起来像它在做的事**：
## 一字横排的狙击手 = 一排同时点名的针；V 字散射者 = 合围的交叉弹幕；
## 环形环绕者 = 一圈合拢的弹幕环。玩家看到形状就该知道要往哪躲。
const FORMATION_TYPE: Dictionary = {
	FORMATION_LINE: 0,
	FORMATION_COLUMN: 2,
	FORMATION_VEE: 1,
	FORMATION_PINCER: 1,
	FORMATION_RING: 2,
	FORMATION_SWARM: 0,
}

## 出生点在屏幕外的距离。阵型必须"从画外进来"，
## 否则玩家会在毫无预警的情况下被贴脸，这是弹幕射击最忌讳的事。
const SPAWN_MARGIN: float = 44.0

# ── 章节主题 ───────────────────────────────────────────────────
#
# 每 5 级（= 一章，与 Boss 节奏对齐）换一个主题。
# 主题改的是**怎么躲**，不是"躲不躲得过"：弹速变快的同时敌人变脆，
# 玩家的应对方式从"站桩输出"换成"贴脸抢输出窗口"，手感就换了一种。

const CHAPTER_THEMES: Array = [
	{"id": "strike", "name": "压制", "bullet_speed": 1.00, "enemy_health": 1.00, "fire_rate": 1.00},
	{"id": "overdrive", "name": "超载", "bullet_speed": 1.10, "enemy_health": 0.92, "fire_rate": 1.15},
	{"id": "swarm", "name": "蜂群", "bullet_speed": 0.94, "enemy_health": 1.08, "fire_rate": 0.90},
	{"id": "ionstorm", "name": "离子风暴", "bullet_speed": 1.16, "enemy_health": 0.96, "fire_rate": 1.05},
]

# ── 运行态 ─────────────────────────────────────────────────────

var _phase_index: int = PHASE_SETUP
var _phase_left: float = PHASE_SECONDS
var _budget: float = 0.0
var _cooldown: float = 0.0
var _last_formation: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 已排期但尚未出场的敌人（阵型错峰用）
var _pending: Array[Dictionary] = []
## 最近一次**排期**的阵型 id。
## 它记录的是"编排决策"而不是"出场瞬间"：一个阵型的敌人会跨若干帧陆续出场，
## 用出场事件统计重复率会把错峰误判成连续重复。tests/wave_probe.gd 依赖这个区分。
var last_formation_id: String = ""


func _ready() -> void:
	_rng.randomize()


func reset(start_phase: int = PHASE_SETUP) -> void:
	_phase_index = clampi(start_phase, 0, PHASE_COUNT - 1)
	_phase_left = PHASE_SECONDS
	_budget = OPENING_BUDGET
	_cooldown = 0.0
	_last_formation = ""
	last_formation_id = ""
	_pending.clear()


# ── 静态设计曲线（tests/wave_probe.gd 直接验证这一层）──────────

## 旧版随机刷怪的节奏（只/秒）。这是本次改造的校准基准。
static func legacy_rate(level: int) -> float:
	var interval: float = maxf(LEGACY_BASE_INTERVAL - float(level) * LEGACY_PER_LEVEL,
		LEGACY_MIN_INTERVAL)
	return 1.0 / interval + 1.0 / LEGACY_PULSE_SECONDS


## 第 `phase` 拍的威胁投放速率（只/秒）。
## 定义为 `旧版速率 × 本拍形状倍率`，这样四拍的均值恒等于旧版速率。
static func threat_rate(level: int, phase: int) -> float:
	return legacy_rate(level) * PHASE_SHAPE[clampi(phase, 0, PHASE_COUNT - 1)]


## 一章（4 拍）的平均投放速率。恒等于 `legacy_rate(level)`。
static func chapter_mean_rate(level: int) -> float:
	var total: float = 0.0
	for p in range(PHASE_COUNT):
		total += threat_rate(level, p)
	return total / float(PHASE_COUNT)


## 本拍一次阵型投放的规模。随等级变大，但封顶 8——
## 再大就变成一坨糊屏，不是阵型了。
## 退潮恒定 1 只：它是涓流，作用是让屏幕不空，而不是给压力。
static func formation_size(level: int, phase: int) -> int:
	if phase == PHASE_LULL:
		return 1
	return clampi(3 + int(float(level) / 3.0), 3, 8)


## 本拍的主题。章节号 = (等级 + 4) / 5，与 Boss 每 5 级一场对齐。
static func theme_for_chapter(chapter: int) -> Dictionary:
	var idx: int = posmod(chapter - 1, CHAPTER_THEMES.size())
	return CHAPTER_THEMES[idx]


## 等级 → 章节号
static func chapter_for_level(level: int) -> int:
	return maxi(1, int((level + 4) / 5))


## 某等级、某拍的阵型规模 vs 闸门上限必须撑得住设计速率，
## 否则预算会被闸门饿死，实际强度就会低于设计值。
static func formation_throughput(level: int, phase: int) -> float:
	var size: int = formation_size(level, phase)
	if size <= 0:
		return 0.0
	return float(size) / FORMATION_INTERVAL[phase]


# ── 阵型生成 ───────────────────────────────────────────────────

## 生成一个阵型的出怪计划。
##
## 返回 [{type:int, pos:Vector2, delay:float}]，`delay` 是相对现在的错峰时间。
## 全部出生点都保证在屏幕之外（见 SPAWN_MARGIN）。
static func plan_formation(formation_id: String, screen: Vector2, count: int,
		rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var n: int = maxi(count, 1)
	var plan: Array[Dictionary] = []
	var top: float = -SPAWN_MARGIN
	var bottom: float = screen.y + SPAWN_MARGIN
	var left: float = -SPAWN_MARGIN
	var right: float = screen.x + SPAWN_MARGIN
	match formation_id:
		FORMATION_LINE:
			## 上方一字横排：逼迫玩家横向找空档，整排同时点名。
			for i in range(n):
				var t: float = (float(i) + 0.5) / float(n)
				plan.append({
					"type": FORMATION_TYPE[FORMATION_LINE],
					"pos": Vector2(lerpf(screen.x * 0.08, screen.x * 0.92, t),
						top - float(i % 2) * 18.0),
					"delay": float(i) * FORMATION_STAGGER,
				})
		FORMATION_COLUMN:
			## 上方纵列，前后拉开距离：形成纵深，玩家看到的是"一列压过来"。
			for i in range(n):
				plan.append({
					"type": FORMATION_TYPE[FORMATION_COLUMN],
					"pos": Vector2(screen.x * 0.5 + r.randf_range(-110.0, 110.0),
						top - float(i) * 46.0),
					"delay": float(i) * FORMATION_STAGGER * 2.0,
				})
		FORMATION_VEE:
			## 下方 V 字合围：两翼先到、尖端最后，把玩家的活动空间压成口袋。
			var apex: Vector2 = Vector2(screen.x * 0.5, bottom)
			var wing: Vector2 = Vector2(screen.x * 0.5, bottom + 150.0)
			for i in range(n):
				var t: float = float(i) / maxf(float(n - 1), 1.0)
				plan.append({
					"type": FORMATION_TYPE[FORMATION_VEE],
					"pos": Vector2(lerpf(apex.x, wing.x, t * 2.0 - 1.0),
						lerpf(apex.y, wing.y, absf(t * 2.0 - 1.0))),
					"delay": absf(t * 2.0 - 1.0) * 0.5,
				})
		FORMATION_PINCER:
			## 左右同时对进：制造"往哪边都是枪"的中段压迫，只能往上/下逃。
			var half: int = int(ceil(float(n) * 0.5))
			for i in range(n):
				var from_left: bool = i < half
				var slot: int = i if from_left else i - half
				var t: float = (float(slot) + 0.5) / float(maxi(half, 1))
				plan.append({
					"type": FORMATION_TYPE[FORMATION_PINCER],
					"pos": Vector2(left if from_left else right,
						screen.y * 0.25 + t * screen.y * 0.5),
					"delay": float(i) * FORMATION_STAGGER,
				})
		FORMATION_RING:
			## 上方弧线排开的环绕者：六连慢弹会合成一道会呼吸的弹幕环。
			## 弧线用"抛物线 + 恒在屏外"而不是真正的圆弧——真正的圆弧两端会绕回
			## 屏幕内侧（半径大于半屏宽时必然如此），玩家会毫无预警地被贴脸。
			## 这条由 tests/wave_probe.gd 的 `spawn_points_offscreen` 逐点钉死。
			for i in range(n):
				var t: float = (float(i) + 0.5) / float(n)
				var bow: float = 1.0 - 4.0 * pow(t - 0.5, 2.0)
				plan.append({
					"type": FORMATION_TYPE[FORMATION_RING],
					"pos": Vector2(lerpf(screen.x * 0.12, screen.x * 0.88, t),
						top - bow * 70.0),
					"delay": bow * 0.35,
				})
		_:
			## 蜂群：四边随机散点的小型群。强度不高但持续压缩活动空间，
			## 是涨潮段最好的"背景压力"填充物。
			for i in range(n):
				var edge: int = i % 4
				var p: Vector2 = Vector2.ZERO
				match edge:
					0: p = Vector2(r.randf_range(0.0, screen.x), top)
					1: p = Vector2(r.randf_range(0.0, screen.x), bottom)
					2: p = Vector2(left, r.randf_range(0.0, screen.y))
					_: p = Vector2(right, r.randf_range(0.0, screen.y))
				plan.append({"type": FORMATION_TYPE[FORMATION_SWARM], "pos": p,
					"delay": float(i) * FORMATION_STAGGER * 1.5})
	return plan


# ── 每帧推进 ───────────────────────────────────────────────────

## 推进编排器。返回"此刻应当出场"的敌人列表。
##
## `alive` 是当前同屏敌人数（含精英与 Boss 判定交由调用方在调用前过滤）。
## Host 权威运行，客户端不调用——出怪点仍然走既有的 `_rpc_spawn_enemy` 广播，
## 所以联机两端看到的波次天然一致，不新增同步负担。
func advance(delta: float, level: int, alive: int, screen: Vector2,
		screen_cap: int) -> Array[Dictionary]:
	_phase_left -= delta
	if _phase_left <= 0.0:
		_phase_left += PHASE_SECONDS
		_phase_index = (_phase_index + 1) % PHASE_COUNT
		phase_changed.emit(_phase_index, PHASE_NAMES[_phase_index])

	var phase: int = _phase_index
	_budget = minf(_budget + threat_rate(level, phase) * delta, BUDGET_CAP)
	_cooldown = maxf(_cooldown - delta, 0.0)

	var ready: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		entry["delay"] = float(entry["delay"]) - delta
	for i in range(_pending.size() - 1, -1, -1):
		var e: Dictionary = _pending[i]
		if float(e["delay"]) <= 0.0:
			ready.append(e)
			_pending.remove_at(i)
	ready.reverse()

	var cost: int = formation_size(level, phase)
	if cost <= 0 or _cooldown > 0.0:
		return ready
	if alive + _pending.size() + ready.size() + cost > screen_cap:
		return ready
	if _budget < float(cost):
		return ready

	_budget -= float(cost)
	var fid: String = _pick_formation(phase)
	var plan: Array[Dictionary] = plan_formation(fid, screen, cost, _rng)
	_budget = minf(_budget, BUDGET_CAP)
	for e: Dictionary in plan:
		_pending.append({
			"type": int(e["type"]),
			"pos": e["pos"],
			"delay": float(e["delay"]) + FORMATION_STAGGER,
			"formation": fid,
		})
	_cooldown = FORMATION_INTERVAL[phase]
	return ready


## 选阵型：只在本拍词表里取，并且不与上一次重复（词表只有 1 个时除外）。
func _pick_formation(phase: int) -> String:
	var vocab: Array = PHASE_FORMATIONS[clampi(phase, 0, PHASE_COUNT - 1)]
	if vocab.is_empty():
		return FORMATION_SWARM
	var candidates: Array[String] = []
	for fid: String in vocab:
		if fid != _last_formation:
			candidates.append(fid)
	if candidates.is_empty():
		return vocab[0]
	var picked: String = candidates[_rng.randi_range(0, candidates.size() - 1)]
	_last_formation = picked
	last_formation_id = picked
	return picked


# ── 只读查询（HUD / 探针用）─────────────────────────────────────

func current_phase() -> int:
	return _phase_index


func current_phase_name() -> String:
	return PHASE_NAMES[_phase_index]


func current_phase_color() -> Color:
	return PHASE_COLORS[_phase_index]


## 本拍剩余秒数
func phase_left() -> float:
	return maxf(_phase_left, 0.0)


## 本拍进度 0~1（HUD 画节奏条用）
func phase_progress() -> float:
	return clampf(1.0 - _phase_left / PHASE_SECONDS, 0.0, 1.0)


## 本拍名称 + 进度，合并成一个字符串方便直接塞进 HUD 文本
func phase_readout(level: int) -> String:
	var pct: int = int(phase_progress() * 100.0)
	return "%s · 第 %d 章 · %d%%" % [current_phase_name(),
		chapter_for_level(level), pct]
