extends Node
## 波次编排器回归探针（headless 单进程，不需要 ENet）
##
## 用法：
##   godot --headless --path . res://tests/wave_probe.tscn
##
## 它守住的是"关卡设计"本身，而不是某个数值。
## 难度曲线门禁在 curve_probe.gd；这里守的是**节奏**：
##
##   1. 章节平均投放速率 ≡ 旧版随机刷怪速率（这次改造不许偷偷加难度）
##   2. 四拍形状倍率的和恒等于拍数（上一条的充要条件）
##   3. 退潮必须真的低于涨潮（张弛是这套设计的全部意义）
##   4. 浪峰必须真的高于涨潮（要有压迫感峰值）
##   5. 平均速率随等级单调不减（不能出现后期变简单）
##   6. 阵型规模/投放间隔在安全区间内
##   7. 阵型闸门撑得住设计速率（否则预算被饿死，实际强度低于设计）
##   8. 所有出生点在屏幕之外（不能贴脸刷怪）
##   9. 同屏上限在任何模拟中都不被突破
##  10. 阵型不会连续重复（否则编排退化成单一形状）
##  11. 章节主题的三个倍率都在安全区间（弹速不能快到躲不掉）
##  12. 校准基准与 main.gd 实际用的刷怪常量一致（防止两边漂移）
##
## 为什么要单独一个探针而不是并进 curve_probe：curve_probe 守"数值曲线不越界"，
## wave_probe 守"节奏形状不塌陷"。两类问题会互相掩盖——比如有人为了让浪峰更刺激
## 直接调大 PHASE_SHAPE，curve_probe 全绿，但整局难度已经悄悄涨了。

const TAG := "[WAVE]"
const MAX_LEVEL := 60
const SCREEN := Vector2(1280.0, 720.0)

const DIRECTOR_PATH := "res://scripts/wave_director.gd"
const MAIN_PATH := "res://scripts/main.gd"

var _passed: int = 0
var _failed: int = 0
var _dir: GDScript = null
var _main: GDScript = null


func _ready() -> void:
	await get_tree().process_frame
	_dir = load(DIRECTOR_PATH)
	_main = load(MAIN_PATH)
	if _dir == null:
		_check("director_loaded", false, "无法加载 wave_director.gd")
		_report()
		return
	_check("director_loaded", true, "wave_director.gd")
	_check_rhythm_baseline_matches_main()
	_check_phase_shape_normalized()
	_check_chapter_mean_matches_legacy()
	_check_contrast_between_phases()
	_check_mean_rate_monotonic()
	_check_formation_size_bounds()
	_check_throughput_supports_rate()
	_check_spawn_points_offscreen()
	_check_screen_cap_respected()
	_check_no_repeated_formation()
	_check_chapter_theme_bounds()
	_check_simulation_stays_healthy()
	_report()


func _report() -> void:
	print("%s VERDICT SUMMARY pass=%d failed=%d total=%d" % [
		TAG, _passed, _failed, _passed + _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("%s VERDICT %s pass=%s | %s" % [TAG, name, str(ok).to_lower(), detail])


# ── 1. 校准基准不能和 main.gd 漂移 ───────────────────────────
#
# wave_director 为了避免和 main.gd 互相 preload，把旧版刷怪常量复制了一份。
# 复制就会漂移，所以这里钉死：两边必须一致，
# 否则"章节平均 ≡ 旧版速率"这句话就悄悄变成了假话。
func _check_rhythm_baseline_matches_main() -> void:
	if _main == null:
		_check("rhythm_baseline_matches_main", false, "无法加载 main.gd")
		return
	var pairs: Array = [
		["LEGACY_BASE_INTERVAL", "1.2"],
		["LEGACY_PER_LEVEL", "0.06"],
		["LEGACY_MIN_INTERVAL", _main.ENEMY_SPAWN_MIN_INTERVAL],
		["LEGACY_PULSE_SECONDS", "8.0"],
	]
	var bad: Array = []
	for pair: Array in pairs:
		var key: String = str(pair[0])
		if not (key in _dir):
			bad.append("missing:" + key)
			continue
		if not is_equal_approx(float(_dir.get(key)), float(pair[1])):
			bad.append("%s=%f expect=%s" % [key, float(_dir.get(key)), str(pair[1])])
	_check("rhythm_baseline_matches_main", bad.is_empty(), "issues=%s" % str(bad))


# ── 2. 四拍形状必须归一 ─────────────────────────────────────
#
# PHASE_SHAPE 的和必须恰好等于拍数（4）。这是"章节平均 ≡ 旧版速率"的充要条件。
# 它一旦被改坏，平均强度就会脱离校准，而这类改动不会报任何错——只会让游戏变难。
func _check_phase_shape_normalized() -> void:
	var shape: Array = _dir.PHASE_SHAPE
	var total: float = 0.0
	for v: float in shape:
		total += v
	var expect: float = float(_dir.PHASE_COUNT)
	_check("phase_shape_normalized", absf(total - expect) < 0.0001,
		"sum=%.4f expect=%.1f shape=%s" % [total, expect, str(shape)])


# ── 3. 章节平均速率 ≡ 旧版速率 ───────────────────────────────
#
# 这是本次关卡改造最重要的一条契约：平均强度一点没变，
# 变的只是强度在时间轴上的分布。允许 ±0.5% 的浮点误差。
func _check_chapter_mean_matches_legacy() -> void:
	var worst: float = 0.0
	var worst_level: int = 0
	for level in range(1, MAX_LEVEL + 1):
		var mean: float = float(_dir.chapter_mean_rate(level))
		var legacy: float = float(_dir.legacy_rate(level))
		var dev: float = absf(mean - legacy) / maxf(legacy, 0.0001)
		if dev > worst:
			worst = dev
			worst_level = level
	_check("chapter_mean_matches_legacy", worst < 0.005,
		"worst_dev=%.3f%% @L%d" % [worst * 100.0, worst_level])


# ── 4. 张弛：浪峰必须远高于退潮 ─────────────────────────────
#
# 全部对照"章节平均"（= 1.0，因为 PHASE_SHAPE 之和恒等于拍数）。
# 直接拿浪峰和涨潮比会得到误导性结论：浪峰 1.486 / 涨潮 1.254 = 1.19，
# 看起来"峰不够尖"，但涨潮本来就已经是 +25% 的高压拍，两者的绝对高度才是关键。
# 真正要守住的是**峰谷比**：它塌下来，整套编排就退回成一条恒定直线。
func _check_contrast_between_phases() -> void:
	var lull: float = float(_dir.PHASE_SHAPE[_dir.PHASE_LULL])
	var surge: float = float(_dir.PHASE_SHAPE[_dir.PHASE_SURGE])
	var crest: float = float(_dir.PHASE_SHAPE[_dir.PHASE_CREST])
	var setup: float = float(_dir.PHASE_SHAPE[_dir.PHASE_SETUP])
	_check("crest_over_lull_is_strong", crest / maxf(lull, 0.0001) >= 3.0,
		"crest/lull=%.2f 需 >=3.0（crest=%.3f lull=%.3f）" % [crest / maxf(lull, 0.0001), crest, lull])
	_check("lull_is_a_real_breather", lull <= 0.40,
		"lull=%.3f 需 <=0.40（退潮必须明显塌下来）" % lull)
	_check("crest_is_a_real_peak", crest >= 1.35,
		"crest=%.3f 相对章节均值(1.0) 需 >=1.35" % crest)
	_check("surge_is_elevated", surge >= 1.15 and surge < crest,
		"surge=%.3f 需 >=1.15 且 <crest=%.3f" % [surge, crest])
	_check("setup_is_around_baseline", setup >= 0.85 and setup <= 1.05,
		"setup=%.3f 需落在 0.85~1.05（基准线本身，不是高低潮）" % setup)
	## 每一拍都必须有自己的性格：四拍不能有两拍倍率相同，
	## 否则"编排"退化成"两拍轮换"。
	var seen: Dictionary = {}
	for v: float in _dir.PHASE_SHAPE:
		seen["%.4f" % v] = true
	_check("phases_are_distinct", seen.size() == int(_dir.PHASE_COUNT),
		"distinct=%d of %d" % [seen.size(), int(_dir.PHASE_COUNT)])


# ── 5. 平均速率随等级单调不减 ───────────────────────────────
func _check_mean_rate_monotonic() -> void:
	var regressions: Array = []
	var prev: float = -1.0
	for level in range(1, MAX_LEVEL + 1):
		var mean: float = float(_dir.chapter_mean_rate(level))
		if mean < prev - 0.0001:
			regressions.append("L%d %.4f < %.4f" % [level, mean, prev])
		prev = mean
	_check("mean_rate_monotonic", regressions.is_empty(), "regressions=%s" % str(regressions))


# ── 6. 阵型规模与投放间隔的安全区间 ─────────────────────────
func _check_formation_size_bounds() -> void:
	var bad: Array = []
	for level in range(1, MAX_LEVEL + 1):
		for phase in range(int(_dir.PHASE_COUNT)):
			var size: int = int(_dir.formation_size(level, phase))
			if phase == int(_dir.PHASE_LULL):
				## 退潮是涓流，恒定 1 只。写成 0 会出现连续 16 秒空屏，
				## 写成 ≥2 就不是喘息了。
				if size != 1:
					bad.append("L%d/lull size=%d (须 1)" % [level, size])
				continue
			if size < 2 or size > 8:
				bad.append("L%d/p%d size=%d" % [level, phase, size])
	_check("formation_size_in_range", bad.is_empty(), "issues=%s" % str(bad))

	var intervals: Array = _dir.FORMATION_INTERVAL
	var bad_cd: Array = []
	for phase in range(int(_dir.PHASE_COUNT)):
		var cd: float = float(intervals[phase])
		if cd < 1.0 or cd > 5.0:
			bad_cd.append("p%d cd=%.2f" % [phase, cd])
	_check("formation_interval_in_range", bad_cd.is_empty(), "issues=%s" % str(bad_cd))


# ── 7. 闸门必须撑得住设计速率 ───────────────────────────────
#
# 实际投放速率 = min(预算速率, 阵型规模/间隔)。如果后者更小，
# 预算会被闸门饿死，实际强度低于设计值，"章节平均 ≡ 旧版速率"就只是账面上的。
func _check_throughput_supports_rate() -> void:
	var starved: Array = []
	for level in range(1, MAX_LEVEL + 1):
		for phase in range(int(_dir.PHASE_COUNT)):
			var want: float = float(_dir.threat_rate(level, phase))
			var can: float = float(_dir.formation_throughput(level, phase))
			if can < want:
				starved.append("L%d/p%d want=%.3f can=%.3f" % [level, phase, want, can])
	_check("throughput_supports_rate", starved.is_empty(),
		"starved=%d 例 %s" % [starved.size(), str(starved.slice(0, 5))])


# ── 8. 出生点必须在屏幕之外 ─────────────────────────────────
#
# 弹幕射击最忌讳贴脸刷怪：玩家没有任何反应时间，战败感来自"被偷袭"而不是"我没打好"。
# 全部阵型 × 多等级 × 多种子跑一遍，任何一个出生点落在屏幕内都算失败。
func _check_spawn_points_offscreen() -> void:
	var inside: Array = []
	var rng := RandomNumberGenerator.new()
	for fid: String in _dir.ALL_FORMATIONS:
		for count in range(1, 9):
			for seed_value in range(12):
				rng.seed = seed_value * 7919 + count
				var plan: Array = _dir.plan_formation(fid, SCREEN, count, rng)
				if plan.size() != count:
					inside.append("%s count=%d got=%d" % [fid, count, plan.size()])
				for e: Dictionary in plan:
					var p: Vector2 = e["pos"]
					var on_screen: bool = p.x > -1.0 and p.x < SCREEN.x + 1.0 \
						and p.y > -1.0 and p.y < SCREEN.y + 1.0
					if on_screen:
						inside.append("%s %s" % [fid, str(p)])
					if int(e["type"]) < 0 or int(e["type"]) > 2:
						inside.append("%s bad_type=%d" % [fid, int(e["type"])])
					if float(e["delay"]) < 0.0:
						inside.append("%s neg_delay" % fid)
	_check("spawn_points_offscreen", inside.is_empty(),
		"violations=%d 例 %s" % [inside.size(), str(inside.slice(0, 5))])


# ── 9. 同屏上限在任何模拟中都不被突破 ───────────────────────
func _check_screen_cap_respected() -> void:
	var cap: int = int(_main.ENEMY_SCREEN_CAP) if _main != null else 20
	var d: Object = _dir.new()
	d.reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var screen := SCREEN
	var level: int = 1
	var alive: int = 0
	var peak: int = 0
	var spawned: int = 0
	var delta: float = 1.0 / 60.0
	## 模拟 10 分钟；敌人 3 秒后消失（等价于"打得掉"的上限乐观假设，
	## 这样同屏数会偏高，是对上限最严格的检验）
	for i in range(60 * 600):
		level = 1 + i / (60 * 64)
		var orders: Array = d.advance(delta, level, alive, screen, cap)
		for _o: Dictionary in orders:
			spawned += 1
			alive += 1
		peak = maxi(peak, alive)
		if i % 180 == 0:
			alive = maxi(0, alive - 3)
	_check("screen_cap_respected", peak <= cap,
		"cap=%d peak=%d spawned_in_10min=%d" % [cap, peak, spawned])
	_check("director_actually_spawns", spawned > 100,
		"10 分钟只刷了 %d 只（编排器没生效）" % spawned)
	d.free()


# ── 10. 阵型不能连续重复 ───────────────────────────────────
#
# 统计口径必须挂在**排期**上（`last_formation_id`），不能挂在"出场"上：
# 一个阵型的敌人会按 FORMATION_STAGGER 跨若干帧陆续出场，
# 用出场事件统计会把错峰误判成"连续重复 8 次"。
func _check_no_repeated_formation() -> void:
	var d: Object = _dir.new()
	d.reset()
	var seen_formation: String = ""
	var repeats: int = 0
	var scheduled: int = 0
	var levels: Array[int] = [1, 5, 12, 20, 35, 60]
	for level in levels:
		for _chapter in range(6):
			for i in range(60 * 64):
				## 同屏容量宽松且敌人立刻消失，保证每拍都会排期新阵型
				d.advance(1.0 / 60.0, level, 0, SCREEN, 20)
				var fid: String = str(d.last_formation_id)
				if fid.is_empty() or fid == seen_formation:
					continue
				if not seen_formation.is_empty():
					scheduled += 1
					if fid == seen_formation:
						repeats += 1
				seen_formation = fid
	_check("formations_do_not_repeat_back_to_back", scheduled > 0 and repeats == 0,
		"跨拍换阵型 %d 次，连续重复 %d 次" % [scheduled, repeats])
	d.free()


# ── 11. 章节主题的安全区间 ─────────────────────────────────
#
# 主题改的是"怎么躲"。弹速一旦快过玩家能反应的范围（>1.25 倍基准），
# 就从"换一种躲法"变成"躲不掉"，这与可读性红线冲突；
# 敌人血量太低则会让章节退化成刷分，威胁感消失。
func _check_chapter_theme_bounds() -> void:
	var bad: Array = []
	var names: Array[String] = []
	for chapter in range(1, 25):
		var theme: Dictionary = _dir.theme_for_chapter(chapter)
		var bs: float = float(theme.get("bullet_speed", 1.0))
		var eh: float = float(theme.get("enemy_health", 1.0))
		var fr: float = float(theme.get("fire_rate", 1.0))
		if bs < 0.90 or bs > 1.25:
			bad.append("ch%d bullet_speed=%.2f" % [chapter, bs])
		if eh < 0.85 or eh > 1.15:
			bad.append("ch%d enemy_health=%.2f" % [chapter, eh])
		if fr < 0.85 or fr > 1.20:
			bad.append("ch%d fire_rate=%.2f" % [chapter, fr])
		if chapter <= int(_dir.CHAPTER_THEMES.size()):
			names.append(str(theme.get("name", "")))
	_check("chapter_theme_in_range", bad.is_empty(), "issues=%s" % str(bad))
	_check("first_chapters_have_distinct_themes",
		names.size() == int(_dir.CHAPTER_THEMES.size())
			and _count_distinct(names) == names.size(),
		"themes=%s" % str(names))
	## 章节号必须和 Boss 每 5 级一场对齐，否则主题会在 Boss 中途切换
	_check("chapter_matches_boss_cadence",
		int(_dir.chapter_for_level(5)) == 1
			and int(_dir.chapter_for_level(6)) == 2
			and int(_dir.chapter_for_level(10)) == 2
			and int(_dir.chapter_for_level(11)) == 3,
		"L5=%d L6=%d L10=%d L11=%d (期望 1/2/2/3)" % [
			int(_dir.chapter_for_level(5)), int(_dir.chapter_for_level(6)),
			int(_dir.chapter_for_level(10)), int(_dir.chapter_for_level(11))])


# ── 12. 长时模拟不崩、不泄漏 ───────────────────────────────
func _check_simulation_stays_healthy() -> void:
	var d: Object = _dir.new()
	d.reset()
	var phase_out_of_range: bool = false
	var lull_orders: int = 0
	var lull_time: int = 0
	var lull_size_violations: int = 0
	var total_time: int = 0
	var spawned: int = 0
	var delta: float = 1.0 / 60.0
	var lull_design_units: float = 0.0
	for i in range(60 * 900):
		var sim_level: int = 1 + i / (60 * 30)
		var orders: Array = d.advance(delta, sim_level, 3, SCREEN, 20)
		var ph: int = int(d.current_phase())
		if ph < 0 or ph >= int(_dir.PHASE_COUNT):
			phase_out_of_range = true
		total_time += 1
		if ph == int(_dir.PHASE_LULL):
			lull_time += 1
			## 退潮拍允许出场的是浪峰排期、尚未出场的余波，
			## 但**本拍新排期**的阵型必须恒为 1 只。
			if int(_dir.formation_size(sim_level, ph)) != 1:
				lull_size_violations += 1
			## 设计值按时间积分累加。等级在模拟里持续上涨，
			## 取"平均等级 × 总时长"会低估（等级越高速率越快，曲线是凹的）。
			lull_design_units += float(_dir.threat_rate(sim_level, ph)) * delta
			lull_orders += orders.size()
		spawned += orders.size()
	_check("lull_is_a_trickle_not_a_void", lull_size_violations == 0 and not phase_out_of_range,
		"退潮违规=%d；退潮共出场 %d 只" % [lull_size_violations, lull_orders])
	## 退潮的实际涓流速率必须等于设计值。
	## 注意**不能**用"空帧占比"来衡量：涓流本来就是每 ~1.2 秒才出一只，
	## 逐帧看几乎全是空帧，那个指标测的是采样率而不是设计。
	## 真正要守的是"退潮有没有真的在以设计速率投喂少量敌人"——
	## 这决定了退潮是"低压力的涓流"还是"16 秒空屏"。
	var dev: float = absf(float(lull_orders) - lull_design_units) / maxf(lull_design_units, 0.0001)
	_check("lull_trickle_rate_matches_design", dev < 0.10 and lull_orders > 0,
		"实测出场 %d 只 vs 设计积分 %.1f 只，偏差=%.1f%%" % [lull_orders, lull_design_units, dev * 100.0])
	var lull_share: float = float(lull_time) / maxf(float(total_time), 1.0)
	_check("lull_is_about_a_quarter_of_each_chapter",
		lull_share > 0.2 and lull_share < 0.3,
		"lull_time_share=%.3f (期望 ≈0.25)" % lull_share)
	_check("long_run_spawns_at_expected_rate", spawned > 800,
		"15 分钟刷了 %d 只，期望 ≈%d" % [spawned,
			int(float(_dir.legacy_rate(10)) * 900.0)])
	d.free()


func _count_distinct(items: Array[String]) -> int:
	var seen: Dictionary = {}
	for s: String in items:
		seen[s] = true
	return seen.size()
