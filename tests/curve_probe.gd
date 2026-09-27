extends Node
## 难度曲线回归探针（headless 单进程，不需要 ENet）
##
## 用法：
##   godot --headless --path . res://tests/curve_probe.tscn
##
## 背景：2026-09-27 之前，敌人速度公式
##   speed = (40 + level*6 + type*10) * (1 + 精英场次*0.05)
## 在 12 级就让 type2 环绕者达到 277 px/s，超过玩家极速 260，
## 30 级更是 1716 px/s（6.6 倍）。玩家唯一的规避手段是走位，
## 敌人一旦比玩家快，可读性就崩了。
##
## 这个探针直接调用 main.gd 的曲线函数，断言：
##   1. 1~60 级任一等级、任一敌人类型的速度都不超过玩家极速的 80%
##   2. 速度随等级单调不减（封顶后允许持平），但不能出现回退
##   3. 精英乘区不超过封顶值
##   4. 玩家极速与 speed_cap 的关系正确（cap 确实 = 玩家极速 × 0.8）
##
## 它防的是"有人改了公式但没人发现难度墙又长回来了"。

const TAG := "[CURVE]"
const MAX_LEVEL := 60
## 直接加载 main.gd 脚本资源来读常量与静态函数：
## 不给 main.gd 加 class_name，探针就能在完全不实例化战斗场景的情况下验证曲线。
const MAIN_SCRIPT_PATH := "res://scripts/main.gd"

var _passed: int = 0
var _failed: int = 0
var _main: GDScript = null


func _ready() -> void:
	await get_tree().process_frame
	_main = load(MAIN_SCRIPT_PATH)
	_check_cap_is_ratio()
	_check_enemy_speed_never_exceeds_player()
	_check_speed_is_monotonic()
	_check_post_elite_multiplier_capped()
	_check_curve_grows_at_all()
	_check_hitstop_restores_time_scale()
	print("%s VERDICT SUMMARY pass=%d failed=%d total=%d" % [
		TAG, _passed, _failed, _passed + _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## 玩家极速 260 → 上限应恰好是 208
func _check_cap_is_ratio() -> void:
	var cap: float = _main.PLAYER_MOVE_SPEED_FALLBACK * _main.ENEMY_SPEED_MAX_RATIO
	var ok: bool = is_equal_approx(cap, 208.0)
	_check("cap_is_80_percent", ok,
		"player=%f ratio=%.2f cap=%.1f" % [
			_main.PLAYER_MOVE_SPEED_FALLBACK, _main.ENEMY_SPEED_MAX_RATIO, cap])


func _check_enemy_speed_never_exceeds_player() -> void:
	var player_speed: float = _main.PLAYER_MOVE_SPEED_FALLBACK
	var cap: float = player_speed * _main.ENEMY_SPEED_MAX_RATIO
	var worst_level: int = 0
	var worst_speed: float = 0.0
	var violations: Array = []
	for level in range(1, MAX_LEVEL + 1):
		## 精英场次按"每 20 击杀一次、累计击杀随等级平方增长"取最坏情况
		var kills: int = 0
		for i in range(1, level):
			kills += 10 + 5 * i
		var elites: int = kills / 20
		for etype in range(3):
			var spd: float = _main.compute_enemy_speed(level, etype, elites, cap)
			if spd > worst_speed:
				worst_speed = spd
				worst_level = level
			if spd > cap + 0.01:
				violations.append("L%d/t%d=%.0f" % [level, etype, spd])
	_check("enemy_speed_never_exceeds_cap", violations.is_empty(),
		"cap=%.1f worst=%.0f@L%d violations=%s" % [cap, worst_speed, worst_level, str(violations)])


## 封顶后允许持平，但不能越往后越慢（否则后期难度会自己塌掉）
func _check_speed_is_monotonic() -> void:
	var cap: float = _main.PLAYER_MOVE_SPEED_FALLBACK * _main.ENEMY_SPEED_MAX_RATIO
	var prev: float = -1.0
	var regressions: Array = []
	for level in range(1, MAX_LEVEL + 1):
		var kills: int = 0
		for i in range(1, level):
			kills += 10 + 5 * i
		var spd: float = _main.compute_enemy_speed(level, 2, kills / 20, cap)
		if spd < prev - 0.01:
			regressions.append("L%d %.0f < %.0f" % [level, spd, prev])
		prev = spd
	_check("speed_monotonic", regressions.is_empty(), "regressions=%s" % str(regressions))


func _check_post_elite_multiplier_capped() -> void:
	var worst: float = 0.0
	for elites in range(0, 400):
		worst = maxf(worst, _main.compute_post_elite_multiplier(elites))
	var ok: bool = worst <= _main.POST_ELITE_MULT_MAX + 0.001
	_check("post_elite_multiplier_capped", ok,
		"worst=%.2f cap=%.2f" % [worst, _main.POST_ELITE_MULT_MAX])


## 难度必须真的在涨：末级速度要明显高于首级，否则就成了一潭死水
func _check_curve_grows_at_all() -> void:
	var cap: float = _main.PLAYER_MOVE_SPEED_FALLBACK * _main.ENEMY_SPEED_MAX_RATIO
	var first: float = _main.compute_enemy_speed(1, 0, 0, cap)
	var last: float = _main.compute_enemy_speed(MAX_LEVEL, 0, 200, cap)
	var ok: bool = last > first * 2.0
	_check("curve_grows", ok, "L1=%.0f L%d=%.0f ratio=%.2f" % [first, MAX_LEVEL, last, last / first])


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("%s VERDICT %s pass=%s | %s" % [TAG, name, str(ok).to_lower(), detail])


## 命中定格必须能恢复到原速度。
## 历史 bug：定格期间再次触发定格时，把"要恢复到的速度"记成了 0.05，
## 导致整局永久停在 5% 速度——肉眼表现为"游戏突然变得极慢且不会恢复"。
## 这里只验证 main.gd 的恢复逻辑契约，不实际驱动整个战斗场景。
func _check_hitstop_restores_time_scale() -> void:
	var main_script: GDScript = _main
	## 契约：_tick_hitstop 在倒计时归零时把 time_scale 还原成 _hitstop_target
	var src: String = ""
	if main_script != null:
		src = String(main_script.source_code) if "source_code" in main_script else ""
	_check("hitstop_target_guard_present",
		src.contains("if not was_active:") and src.contains("_hitstop_target = Engine.time_scale"),
		"emit_hit_feedback 必须在定格期间保留原始 time_scale")
	Engine.time_scale = 1.0
