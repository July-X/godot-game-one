extends "res://scripts/battle/trials/opening_trial.gd"
## 从镜像护航前一秒开始，沿用原型的生成、移动、选卡加成和清理。
const START_TICK := FINALE_TICK - 60
const LAST_TICK := START_TICK + 18 * 60
const ELITE_SEED := 90220
const TRIAL_CARD := "splash"
const EliteRules := preload("res://scripts/battle/enemies/elite.gd")
const CannonShot := preload("res://scripts/battle/projectiles/bullet.gd")
const CLOSE_RANGE := 208.0
const OPENS_AT := .22
const CLOSES_AT := 1.30
const BONUS_DAMAGE := 4

signal bonus_hit(shot_id: int, extra_damage: int)

enum TrialVariant { COMMAND_LINE, A, B }

@export var playtest_variant := TrialVariant.COMMAND_LINE

var defeat_tick := -1
var remaining_hp := 0
var variant_b := false
var bonus_count := 0
var _last_extra := 0
var _gain_until := -1
var _status := ""

func _ready() -> void:
	trial_tick = START_TICK
	var from_menu := playtest_variant != TrialVariant.COMMAND_LINE
	variant_b = playtest_variant == TrialVariant.B if from_menu else "--close-b" in OS.get_cmdline_user_args()
	super._ready()
	if from_menu:
		$TrialUI/Options/Buttons/Back.text = "返回试飞选择"
	GameState.apply_card(1, TRIAL_CARD)
	if variant_b:
		child_entered_tree.connect(_watch_cannon_shot)

func _return_to_title() -> void:
	if playtest_variant == TrialVariant.COMMAND_LINE:
		super._return_to_title()
	elif is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/ui/opening_trial_choices.tscn")

func _spawn_elite() -> void:
	# 护航的击毁也会消耗随机数，在精英入场时重新固定两版的初始状态。
	seed(ELITE_SEED)
	super._spawn_elite()

func _exit_tree() -> void:
	randomize()
	super._exit_tree()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if finished:
		return
	if trial_tick == LAST_TICK:
		_finish("完成")
		return
	if is_instance_valid(_elite):
		_cues.queue_redraw()
	_update_countdown()

func _update_countdown() -> void:
	var seconds := ceili(float(LAST_TICK - trial_tick) / 60.0)
	var label := "近身试飞 B" if variant_b else "近身试飞 A"
	if defeat_tick >= 0:
		label = "精英已击毁"
	elif variant_b and is_instance_valid(_elite) and not _elite.has_impact_shield():
		var age := exposure_age()
		if trial_tick < _gain_until:
			label = "近身命中 +%d" % _last_extra
		elif age >= 0.0 and age < OPENS_AT:
			label = "弱点将开"
		elif _close_window_open():
			label = "近身弱点"
		else:
			label = "窗口关闭"
	var status := "%s · %d 秒" % [label, seconds]
	if status != _status:
		_status = status
		_hud.set_wave_phase(status, Color.LIGHT_CYAN)

func exposure_age() -> float:
	if not is_instance_valid(_elite) or _elite._phase_b_timer <= 0.0:
		return -1.0
	return EliteRules.PHASE_B_EXPOSE_DURATION - _elite._phase_b_timer

func _close_window_open() -> bool:
	var age := exposure_age()
	return age >= OPENS_AT and age < CLOSES_AT

func _return_fire_soon() -> bool:
	return is_instance_valid(_elite) and not _elite._dead and _elite._shoot_timer <= .28

func _watch_cannon_shot(node: Node) -> void:
	if node is CannonShot:
		_bind_cannon_hit.call_deferred(node.get_instance_id())

func _bind_cannon_hit(id: int) -> void:
	var shot := instance_from_id(id) as CannonShot
	if is_instance_valid(shot) and shot.is_in_group("player_bullets") and shot.owner_peer_id == 1 and shot._level == 1:
		shot.body_entered.connect(_on_cannon_contact.bind(shot))

func _on_cannon_contact(body: Node2D, shot: CannonShot) -> void:
	# 生产碰撞先结算普通伤害并登记 _pierced，再检查同一颗主炮弹是否获得收益。
	if finished or not GameState.game_running or not is_instance_valid(_elite) or body != _elite \
			or not shot._pierced.has(body) or _elite._dead or not _close_window_open():
		return
	if not is_instance_valid(_player) or _player.global_position.distance_squared_to(body.global_position) > CLOSE_RANGE * CLOSE_RANGE:
		return
	var before: float = _elite.get_network_health()
	_elite.take_damage(BONUS_DAMAGE, shot.owner_peer_id)
	_last_extra = int(before - maxf(0.0, body.get_network_health()))
	bonus_count += 1
	_gain_until = trial_tick + 15
	bonus_hit.emit(shot.get_instance_id(), _last_extra)

func _draw_cues() -> void:
	super._draw_cues()
	if finished or not is_instance_valid(_elite) or _elite._dead:
		return
	var center := _cues.to_local(_elite.global_position)
	var age := exposure_age()
	if variant_b and age >= 0.0 and age < CLOSES_AT:
		var ink := Color("#75d5e4") if _close_window_open() else Color(0.45, 0.83, 0.89, .36)
		for i in 12:
			var angle := i * TAU / 12.0
			_cues.draw_arc(center, CLOSE_RANGE, angle + .07, angle + .44, 9, ink, 1.6, true)
	if _return_fire_soon():
		var forward: float = _elite.rotation - PI * .5
		_cues.draw_arc(center, 92.0, forward - .44, forward + .44, 20, Color("#f6a06f"), 3.0, true)

func _on_elite_died() -> void:
	defeat_tick = trial_tick
	_cues.queue_redraw()
	super._on_elite_died()

func _finish(outcome: String) -> void:
	if finished:
		return
	if is_instance_valid(_elite):
		remaining_hp = maxi(0, int(_elite.get_network_health()))
	super._finish(outcome)
	_result.text = "%s · %s" % [outcome,
		"精英 %.2f 秒击毁" % ((defeat_tick - START_TICK) / 60.0) if defeat_tick >= 0
		else "精英剩余 %d" % remaining_hp]
	if variant_b:
		_result.text += " · 近身命中 %d" % bonus_count
	_layout_options()
