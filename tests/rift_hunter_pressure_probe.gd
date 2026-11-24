extends Node
## 固定种子的实弹回归；用 -- measure 在旧版只报读数。
const Trial := preload("res://scripts/battle/trials/rift_route_trial.gd")
const Weapon := preload("res://scripts/battle/enemies/rift_hunter_attack.gd")
const Route := preload("res://scenes/rift_route_trial.tscn")
var trial: Trial
var first_enemy_frame := -1
var born := -1
var broken := -1
var first_warning := -1
var hp_at_spawn := 0
var dodge_target := Vector2.INF
func _ready() -> void:
	_run.call_deferred()
func _watch(node: Node) -> void:
	if node.scene_file_path == "res://scenes/entities/bullet.tscn":
		_track.call_deferred(node, Engine.get_physics_frames() - born)
func _track(node: Node, frame: int) -> void:
	if first_enemy_frame < 0 and is_instance_valid(node) and node.is_in_group("enemy_bullets") and node.modulate.is_equal_approx(Weapon.LINE_COLOR):
		first_enemy_frame = frame
func _run() -> void:
	seed(90220)
	trial = Route.instantiate() as Trial
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	var pilot: Node2D = trial._player
	pilot.set_physics_process(false)
	var args := OS.get_cmdline_user_args()
	pilot.global_position = Vector2(815, 450) if args.has("side") else Vector2(640, 460)
	pilot._motion.mobile_mode = true
	GameState.set_shield_layers(1, 0)
	hp_at_spawn = GameState.get_current_health(1)
	var sharp := args.has("fast")
	var dodge := args.has("dodge")
	if sharp:
		GameState._state(1).shoot_speed_level = 10
	trial._set_leg(Trial.Leg.ELITE)
	trial.trial_tick = Trial.ELITE_LEG + 154
	for _attempt in 30:
		if is_instance_valid(trial._elite):
			break
		await get_tree().physics_frame
	if not is_instance_valid(trial._elite):
		push_error("Rift Hunter did not spawn.")
		get_tree().quit(1)
		return
	born = Engine.get_physics_frames()
	get_tree().node_added.connect(_watch)
	var next_shot := 0
	var killed := -1
	var fixed_aim := args.has("fixed-aim")
	var fixed_target := Vector2(640, 120)
	var opening_start := Vector2.INF
	var opening_muzzle := Vector2.INF
	var opening_shift := 0.0
	var arrival_error := -1.0
	var sidestep_start := Vector2.INF
	var max_sidestep := 0.0
	trial._elite.route_evaded.connect(func(): trial._elite.set_meta("pressure_probe_evade_start", trial._elite.global_position))
	var damage_after_first_break := -1
	for tick in range(600):
		await get_tree().physics_frame
		var hunter: Node2D = trial._elite
		if not is_instance_valid(hunter):
			killed = tick
			break
		if hunter._route_dodge_left > 0.0 and hunter.has_meta("pressure_probe_evade_start"):
			sidestep_start = hunter.get_meta("pressure_probe_evade_start")
			max_sidestep = maxf(max_sidestep, hunter.global_position.distance_to(sidestep_start))
		var cue: Dictionary = hunter.route_attack_preview()
		if first_warning < 0 and cue.get("pattern") == Weapon.Pattern.LINE:
			first_warning = tick
			opening_start = hunter.global_position
			opening_muzzle = cue.origin
			if dodge:
				dodge_target = pilot.global_position + Vector2.from_angle(cue.angle).orthogonal() * 120.0
		if first_enemy_frame >= 0 and arrival_error < 0.0 and opening_start != Vector2.INF:
			opening_shift = hunter.global_position.distance_to(opening_start)
			arrival_error = hunter.global_position.distance_to(opening_muzzle)
		if dodge_target != Vector2.INF:
			var axis := pilot.global_position.direction_to(dodge_target)
			if pilot.global_position.distance_to(dodge_target) < 12.0:
				dodge_target = Vector2.INF
				axis = Vector2.ZERO
			pilot._motion.handle_mobile_move(axis)
			pilot._motion.update(1.0 / 60.0, 1.0, NetworkManager.battle_size(pilot))
		if broken < 0 and hunter.get_network_shield() <= 0.0:
			broken = tick
		if broken >= 0 and damage_after_first_break < 0 and hunter.get_network_health() < hunter.get_network_max_health():
			damage_after_first_break = tick
		if tick >= next_shot:
			var toward: Vector2 = fixed_target if fixed_aim else hunter.global_position
			pilot.rotation = pilot.global_position.angle_to_point(toward) + PI / 2
			pilot._combat._shoot()
			next_shot += ceili(GameState.get_shoot_cooldown(1) * 60.0)
	var hp_lost := hp_at_spawn - GameState.get_current_health(1)
	print("HUNTER_PRESSURE fast=%s side=%s dodge=%s cooldown=%.3f warn=%d break=%d hull_hit=%d kill=%d first_hunter_shot=%d hp_lost=%d bank=%.1f alignment=%.2f sidestep=%.1f fixed_aim=%s" %
		[sharp, args.has("side"), dodge, GameState.get_base_shoot_cooldown(1), first_warning, broken,
		damage_after_first_break, killed, first_enemy_frame, hp_lost, opening_shift, arrival_error, max_sidestep, fixed_aim])
	var ok := (killed >= 0 and broken >= 0) or fixed_aim
	if not args.has("measure"):
		ok = ok and first_warning >= 0 and first_enemy_frame - first_warning >= 35
		ok = ok and opening_shift >= 105.0 and arrival_error < 2.0 and arrival_error >= 0.0
		ok = ok and (broken < 0 and killed < 0 if fixed_aim else first_enemy_frame < broken)
		if not fixed_aim and not sharp:
			ok = ok and max_sidestep >= 90.0
		ok = ok and (hp_lost == 0 if dodge else hp_lost >= 6)
	if not ok:
		push_error("Rift Hunter pressure fixture did not meet the expected result.")
	get_tree().quit(0 if ok else 1)
