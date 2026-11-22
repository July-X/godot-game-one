extends Node
## 固定相同配装，程序瞄准并用实弹测 Boss；旧版也可运行同一夹具。
const MAIN := preload("res://scenes/main.tscn")
const CENTER := Vector2(640.0, 360.0)
const STEP := 1.0 / 60.0
const MAX_TICKS := 60 * 240
var _releases: Array[int] = []
var _tick := 0
var _defeated := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pilot := args[0] if not args.is_empty() else "evade"
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var main = MAIN.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	seed(14813)
	var player = main._player
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.position = Vector2(640.0, 625.0)
	player._motion.mobile_mode = true
	GameState.set_shield_layers(1, 0)
	if pilot == "assisted":
		player._rescue_protected_until = Engine.get_physics_frames() + MAX_TICKS + 60
	main._spawn_boss(5)
	var boss = main._boss
	boss.shield_released.connect(func(): _releases.append(_tick))
	boss.boss_died.connect(func(): _defeated = true)
	var initial_hull: float = boss.get_network_health()
	var initial_hp := GameState.get_current_health()
	var base_cooldown := GameState.get_shoot_cooldown()
	var shoot_left := 0.0
	print("[RHYTHM] start ", JSON.stringify({"mode": pilot, "pilot_hp": initial_hp,
		"shot_damage": GameState.get_bullet_damage(), "shot_count": GameState.get_bullet_count(),
		"cooldown": base_cooldown, "hull": initial_hull,
		"shield": boss.get_max_shield_hp() if boss.has_method("get_max_shield_hp") else 0.0}))
	var escaped_locks := 0
	var charges := 0
	var beams := 0
	var charge_prev := false
	var beam_prev := false
	var evade_left := 0
	var evade_side := Vector2.ZERO
	var dodging_this_beam := false
	var last_active := 0
	var max_quiet := 0
	var volleys := 0
	var seen := {}
	while _tick < MAX_TICKS and not _defeated and is_instance_valid(player) and GameState.game_running:
		await get_tree().physics_frame
		if not is_instance_valid(boss) or not is_instance_valid(player):
			break
		_tick += 1
		# 固定物理时钟，避免旧版的墙钟定格让两个样本的计时速率不同。
		main._hitstop_left = 0.0
		Engine.time_scale = 1.0
		var charging: bool = boss._ultimate_laser_charging
		var firing: bool = boss._ultimate_laser_firing
		if charging and not charge_prev:
			charges += 1
			dodging_this_beam = false
		if firing and not beam_prev:
			beams += 1
			if dodging_this_beam and absf(boss._ultimate_laser_start.direction_to(boss._ultimate_laser_end).cross(
					player.global_position - boss._ultimate_laser_start)) > boss.BOSS_ULTIMATE_LASER_WIDTH * 0.5:
				escaped_locks += 1
		charge_prev = charging
		beam_prev = firing
		var volley := false
		for shot in get_tree().get_nodes_in_group("enemy_bullets"):
			var id := shot.get_instance_id()
			if not seen.has(id):
				seen[id] = true
				volley = true
		if volley:
			volleys += 1
		if volley or charging or firing:
			max_quiet = maxi(max_quiet, _tick - last_active)
			last_active = _tick
		var locked: Variant = boss.get("_laser_locked_direction")
		var axis := Vector2.ZERO
		if charging and locked is Vector2:
			axis = locked
		elif firing:
			axis = boss._ultimate_laser_start.direction_to(boss._ultimate_laser_end)
		if pilot != "anchor" and not dodging_this_beam and not axis.is_zero_approx():
			dodging_this_beam = true
			evade_left = 40
			evade_side = axis.orthogonal()
			if evade_side.dot(CENTER - player.global_position) < 0.0:
				evade_side = -evade_side
		player._invincible_timer = maxf(player._invincible_timer - STEP, 0.0)
		player._motion.handle_mobile_move(evade_side if evade_left > 0 else Vector2.ZERO)
		player._motion.update(STEP, 1.0, Vector2(1280.0, 720.0))
		evade_left -= 1
		shoot_left -= STEP
		if shoot_left <= 0.0:
			player.rotation = player.global_position.angle_to_point(boss.global_position) + PI * 0.5
			player._combat._shoot()
			shoot_left += base_cooldown
	max_quiet = maxi(max_quiet, _tick - last_active)
	print("[RHYTHM] end ", JSON.stringify({"outcome": "defeated" if _defeated else "timed_out" if GameState.game_running else "pilot_died",
		"ticks": _tick, "quiet_max_ticks": max_quiet, "volleys": volleys, "charges": charges,
		"beams": beams, "clear_before_fire": escaped_locks, "shield_releases": _releases,
		"pilot_hp": GameState.get_current_health(), "hull_remaining": boss.get_network_health() if is_instance_valid(boss) else 0.0}))
	get_tree().quit()
