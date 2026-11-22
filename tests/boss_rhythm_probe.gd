extends Node
## 固定相同配装，程序瞄准并用实弹测 Boss；旧版也可运行同一夹具。
const MAIN := preload("res://scenes/main.tscn")
const Boss := preload("res://scripts/boss.gd")
const CENTER := Vector2(640.0, 360.0)
const STEP := 1.0 / 60.0
const MAX_TICKS := 60 * 240
var _releases: Array[int] = []
var _tick := 0
var _defeated := false
var _partner_ready := false
var _window_start_hp := -1.0
var _window_damage: Array[float] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pilot := args[0] if not args.is_empty() else "evade"
	var loadout := args[1] if args.size() > 1 else "basic"
	var side := args[2] if args.size() > 2 else "solo"
	if side != "solo":
		if args.size() < 4 or side not in ["host", "client"] or not args[3].is_valid_int():
			push_error("Use -- assisted|aligned basic|growth|mixed|mixed-host host|client PORT")
			get_tree().quit(2)
			return
		Engine.max_fps = 60
		var port := int(args[3])
		var error := NetworkManager.create_host(port) if side == "host" else NetworkManager.join_host("127.0.0.1", port)
		if error != OK or not await _wait_ready(NetworkManager.is_online):
			push_error("Paired rhythm probe could not connect")
			get_tree().quit(1)
			return
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var main = MAIN.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	seed(14813)
	if pilot == "aligned":
		main._wave_director._cooldown = 240.0
		main._asteroid_timer = 240.0
	if side != "solo" and not await _wait_ready(func(): return main._players.size() == 2 and is_instance_valid(main._player)):
		push_error("Paired rhythm probe could not find both pilots")
		get_tree().quit(1)
		return
	var player = main._player
	var local_id: int = player.peer_id
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.position = Vector2(780.0 if side == "client" else (500.0 if pilot == "aligned" and side == "host" else 640.0), 625.0)
	player._motion.mobile_mode = true
	if side == "client":
		_ready_to_fight.rpc_id(1)
	elif side == "host" and not await _wait_ready(func(): return _partner_ready):
		push_error("Paired rhythm probe waited for pilot input setup")
		get_tree().quit(1)
		return
	if side != "client":
		for id: int in GameState.get_alive_player_ids():
			var actor = main._players.get(id, player)
			if pilot == "assisted" or pilot == "aligned":
				actor._rescue_protected_until = Engine.get_physics_frames() + MAX_TICKS + 60
			if loadout == "growth" or (loadout == "mixed" and id != 1) or (loadout == "mixed-host" and id == 1):
				var stats := GameState._state(id)
				stats.shoot_level = 6
				stats.shoot_speed_level = 7
				stats.bullet_power_level = 9
				stats.extra_bullet_count = 1
				stats.extra_damage_bonus = 2
			GameState.set_shield_layers(id, 0)
		if side == "host":
			GameState.force_sync_to_peer(NetworkManager.connected_peers[0])
		main._spawn_boss(5)
	if not await _wait_ready(func(): return is_instance_valid(main._boss)):
		push_error("Paired rhythm probe could not start Boss")
		get_tree().quit(1)
		return
	var boss = main._boss
	boss.shield_released.connect(func():
		_releases.append(_tick)
		_window_start_hp = boss.get_network_health())
	boss.boss_died.connect(func():
		_defeated = true
		_close_damage_window(boss.get_network_health()))
	var initial_hull: float = boss.get_network_health()
	var initial_hp := GameState.get_current_health()
	var base_cooldown := GameState.get_shoot_cooldown()
	var shoot_left := 0.0
	print("[RHYTHM] start ", JSON.stringify({"mode": pilot, "loadout": loadout, "side": side, "pilot_hp": initial_hp,
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
	var pulse_targets: Array[String] = []
	var pulse_fires := 0
	var pulse_stamp := 0
	while _tick < MAX_TICKS and not _defeated and is_instance_valid(player) and GameState.game_running:
		await get_tree().physics_frame
		if side == "client" and not is_instance_valid(main._boss):
			_defeated = true
			break
		if not is_instance_valid(boss) or not is_instance_valid(player):
			break
		_tick += 1
		# 固定物理时钟，避免旧版的墙钟定格让两个样本的计时速率不同。
		main._hitstop_left = 0.0
		Engine.time_scale = 1.0
		var ghost := side == "client"
		var charging: bool = boss.get_attack_window() == Boss.AttackWindow.CHARGING if ghost else boss._ultimate_laser_charging
		var firing: bool = boss.get_attack_window() >= Boss.AttackWindow.SWEEP if ghost else boss._ultimate_laser_firing
		var pulse: Dictionary = boss.coop_pulse_snapshot() if boss.has_method("coop_pulse_snapshot") else {}
		if int(pulse.get("stamp", 0)) > pulse_stamp:
			pulse_stamp = pulse.stamp
			if int(pulse.phase) == 1:
				pulse_targets.append("P1" if pulse.slot == 1 else "P2")
			elif int(pulse.phase) == 2:
				pulse_fires += 1
		var beam_from: Vector2 = boss._ultimate_laser_start
		var beam_to: Vector2 = boss._ultimate_laser_end
		if ghost and firing and is_instance_valid(main._boss_laser_visual):
			beam_from = main._boss_laser_visual._beam_start
			beam_to = main._boss_laser_visual._beam_end
		if not ghost and _window_start_hp >= 0.0 and boss.has_method("has_impact_shield") and boss.has_impact_shield():
			_close_damage_window(boss.get_network_health())
		if charging and not charge_prev:
			charges += 1
			dodging_this_beam = false
		if firing and not beam_prev:
			beams += 1
			if dodging_this_beam and absf(beam_from.direction_to(beam_to).cross(
					player.global_position - beam_from)) > boss.BOSS_ULTIMATE_LASER_WIDTH * 0.5:
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
		if volley or charging or firing or int(pulse.get("phase", 0)) != 0:
			max_quiet = maxi(max_quiet, _tick - last_active)
			last_active = _tick
		var locked: Variant = boss.get("_laser_locked_direction")
		var axis := Vector2.ZERO
		if charging and locked is Vector2:
			axis = locked
		elif firing:
			axis = beam_from.direction_to(beam_to)
		if pilot not in ["anchor", "aligned"] and not dodging_this_beam and not axis.is_zero_approx():
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
		"pulse_targets": pulse_targets, "pulse_fires": pulse_fires,
		"window_damage": _window_damage, "pilot_hp": GameState.get_current_health(),
		"hull_remaining": boss.get_network_health() if is_instance_valid(boss) else 0.0}))
	if side == "host":
		await get_tree().create_timer(0.65).timeout
	get_tree().quit(0 if _defeated else 1)

func _close_damage_window(hp: float) -> void:
	if _window_start_hp >= 0.0:
		_window_damage.append(snappedf(_window_start_hp - hp, 0.01))
		_window_start_hp = -1.0

func _wait_ready(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false

@rpc("any_peer", "reliable", "call_remote")
func _ready_to_fight() -> void:
	if not multiplayer.is_server():
		return
	_partner_ready = true
