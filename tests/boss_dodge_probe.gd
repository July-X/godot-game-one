extends "res://tests/lan_probe.gd"
## 固定发射坐标，实际子弹碰撞和网络同步由战斗场景处理。
const BossModel := preload("res://scripts/boss.gd")
const CENTER := Vector2(640, 280)
const LEFT_EDGE := Vector2(104, 280)
var mothership: BossModel
var wingmate: Node2D
var begin_pressure := false
var join_finished := false

func _run() -> void:
	await get_tree().process_frame
	seed(20261121)
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_size = Vector2i(1280, 720)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	if _role in ["host", "client"]:
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if not _require("connected", err == OK and await _wait_until(NetworkManager.is_online, 8.0)):
			return
	_enter_main_scene()
	if NetworkManager.is_online() and not _require("two_players", await _wait_until(_cond_both_players, 8.0)):
		return
	_main._player.set_physics_process(false)
	if _role != "client":
		_main._spawn_boss(5)
	if not _require("boss_in_tree", await _wait_until(func(): return is_instance_valid(_main._boss), 5.0)):
		return
	mothership = _main._boss
	match _role:
		"host":
			wingmate = _main._players[NetworkManager.connected_peers[0]]
			await _host_pressure()
		"client": await _join_pressure()
		"entry": await _entry_pressure()
		_: await _solo_pressure()
	get_tree().quit(_summarize())

func _require(label: String, value: bool) -> bool:
	_check(label, value, "")
	if not value:
		get_tree().quit(1)
	return value

func _settle_entry() -> void:
	mothership.set_physics_process(false)
	await _wait_seconds(1.62)
	mothership.set_physics_process(true)

func _pose(origin: Vector2, pilot_position: Vector2) -> void:
	_main._player.global_position = pilot_position
	mothership.global_position = origin
	mothership.reset_physics_interpolation()
	mothership._state = BossModel.State.ATTACK
	mothership._state_timer = 20.0
	mothership._shoot_timer = 20.0
	mothership._strafe_bias = Vector2.ZERO
	mothership._velocity_blend = Vector2.ZERO
	mothership._feint_timer = 20.0

func _fire(point: Vector2, count: int, damage: int = 1) -> void:
	for index in count:
		var origin := point + Vector2((index - 1) * 4, 70)
		_main._player._combat._spawn_bullet(origin, origin.angle_to_point(point), damage, true, 1, 660.0)

func _trace(label: String, ticks: int, fourth_shot: int = -1) -> PackedVector2Array:
	var samples := PackedVector2Array([mothership.global_position])
	for tick in ticks:
		if tick == fourth_shot:
			_fire(mothership.global_position, 1)
		await get_tree().physics_frame
		var point := mothership.global_position
		samples.append(point)
		var pilot_x := wingmate.global_position.x if is_instance_valid(wingmate) else float(_main._player.global_position.x)
		print("[dodge] %s,%d,%f,%f,%f,%f,%d" % [label, tick, point.x, point.y,
			mothership.get_network_health(), pilot_x, mothership.get_attack_window()])
	return samples

func _furthest(samples: PackedVector2Array) -> Vector2:
	var shift := Vector2.ZERO
	for point in samples:
		var displacement := point - samples[0]
		if displacement.length_squared() > shift.length_squared():
			shift = displacement
	return shift

func _check_flight(label: String, samples: PackedVector2Array, side: Vector2) -> void:
	var shift := _furthest(samples)
	var peak := 0.0
	var coast := PackedFloat32Array()
	var reversed := false
	for index in range(1, samples.size()):
		var step := samples[index] - samples[index - 1]
		peak = maxf(peak, step.length())
		var along := step.dot(side)
		if not coast.is_empty() and coast.size() < 30 and along < -0.12:
			reversed = true
		if along > 0.12:
			coast.append(along)
	_check(label + "_side", shift.dot(side) > 98.0 and absf(shift.cross(side)) < 40.0, str(shift))
	_check(label + "_bounded_steps", peak < 9.0 and coast.size() >= 23,
		"peak_px=%.2f moving_ticks=%d" % [peak, coast.size()])
	if label == "center":
		_check("accelerates_and_brakes", coast.size() >= 23 and coast[0] < peak * 0.36
			and coast[coast.size() - 1] < peak * 0.50, "along_steps=%s" % [Array(coast)])
	if label == "p2":
		_check("p2_reversal_keeps_heading", not reversed, "")

func _solo_pressure() -> void:
	await _settle_entry()
	_pose(CENTER, CENTER + Vector2(0, 380))
	var hp := mothership.get_shield_hp()
	_fire(CENTER, 1)
	var light := await _trace("light", 39)
	var movement := _furthest(light)
	_check("one_hit_changes_shield_without_hull_recoil",
		is_equal_approx(mothership.get_shield_hp(), hp - 1.0) and movement.length() < 0.5, str(movement))

	_fire(CENTER, 2)
	var short_burst := await _trace("two", 14)
	_check("two_hits_do_not_move_hull",
		is_equal_approx(mothership.get_shield_hp(), hp - 3.0) and _furthest(short_burst).length() < 0.5, "")
	_fire(CENTER, 1)
	var flight := await _trace("center", 45, 18)
	_check_flight("center", flight, Vector2.LEFT)
	_check("actual_collision_during_dodge", is_equal_approx(mothership.get_shield_hp(), hp - 5.0),
		str(mothership.get_shield_hp()))
	await _trace("settle", 14)

	_pose(LEFT_EDGE, LEFT_EDGE + Vector2(0, 380))
	_fire(LEFT_EDGE, 3)
	_check_flight("edge", await _trace("edge", 42), Vector2.RIGHT)
	await _trace("settle-edge", 17)

	_pose(CENTER, CENTER + Vector2(0, 380))
	_fire(CENTER, 3)
	await _trace("pre-laser", 16)
	await _laser_interrupts()

func _entry_pressure() -> void:
	await _wait_seconds(0.8)
	var origin := mothership.global_position
	_pose(origin, origin + Vector2(0, 380))
	_fire(origin, 3)
	var flight := await _trace("entry", 19)
	_check("pressure_can_interrupt_entry", absf(_furthest(flight).x) > 17.0, str(_furthest(flight)))
	await _laser_interrupts()

func _laser_interrupts() -> void:
	mothership._next_attack = 2
	mothership._shoot_timer = 0.0
	mothership._stop_entry_motion()
	if not _require("scheduled_laser_charge", await _wait_until(
			func(): return mothership.get_attack_window() == BossModel.AttackWindow.CHARGING, 1.5)):
		return
	var laser_start := mothership._ultimate_laser_start
	var charging := await _trace("charging", 22)
	var fixed := true
	for point in charging:
		fixed = fixed and point.distance_to(laser_start) < 0.3
	_check("laser_takes_position_without_drag", fixed, "%s -> %s" % [laser_start, charging[-1]])

func _host_pressure() -> void:
	await _settle_entry()
	_pose(CENTER, CENTER - Vector2(380, 0))
	_check("still_aiming_at_p1", mothership._target == _main._player, "")
	var hp := mothership.get_shield_hp()
	_begin.rpc_id(NetworkManager.connected_peers[0])
	var flight := await _trace("host-p2", 63)
	_check("p2_shots_hit_on_host", is_equal_approx(mothership.get_shield_hp(), hp - 3.0), str(mothership.get_shield_hp()))
	_check_flight("p2", flight, Vector2.RIGHT)
	_check("client_landed_and_observed", await _wait_until(func(): return join_finished, 4.0), "")

func _join_pressure() -> void:
	_main._player.global_position = Vector2(716, 650)
	if not _require("host_released_pressure", await _wait_until(func(): return begin_pressure, 5.0)):
		return
	var hp := mothership.get_shield_hp()
	for tick in 42:
		# 左向趋势决定起步方向，随后掉头检验母舰侧移不会跟着反转。
		_main._player.global_position.x += -4.0 if tick < 25 else 4.0
		if tick == 16:
			_fire(CENTER, 3)
		await get_tree().physics_frame
	_check("host_damage_reached_client", await _wait_until(func(): return mothership.get_shield_hp() <= hp - 3.0, 1.5), "")
	_check("client_observed_host_dodge", await _wait_until(
		func(): return mothership.global_position.x > CENTER.x + 91 and absf(mothership.global_position.y - CENTER.y) < 40,
		1.5), str(mothership.global_position))
	_complete.rpc_id(1)
	await _wait_seconds(0.4)

@rpc("authority", "reliable")
func _begin() -> void:
	begin_pressure = true

@rpc("any_peer", "reliable")
func _complete() -> void:
	if not multiplayer.is_server():
		return
	join_finished = true
