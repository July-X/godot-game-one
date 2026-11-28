extends "res://tests/transport_intercept_probe.gd"
## -- host|client 7777 parallel|flank|downed|rewire [mirror] [guest-bait] [baseline] [frames=DIR]

const BAIT_SUPPORT_DELAY_MS := 1250

var _route := ""
var _bait_slot := 0
var _local_slot := 0
var _reflected := false
var _frame_dir := ""
var _wing: Array[Node2D] = []
var _birth_positions: Array[Vector2] = []
var _warnings := {}
var _seen_bullets := {}
var _releases := 0
var _bad_rays := 0
var _seen_at := -1
var _launch_at := -1
var _wave_at := 0
var _first_direction := Vector2.ZERO
var _first_actor := 0
var _last_health := {}
var _lost_health := {}
var _last_shield := {}
var _lost_shield := {}
var _contacts := {}
var _cannon_contacts := {}
var _cannon_seen := {}


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	_route = args[2]
	_baseline = args.has("baseline")
	_reflected = args.has("mirror")
	for arg: String in args:
		if arg.begins_with("frames="):
			_frame_dir = arg.trim_prefix("frames=")
	if not await _require("ready_from_real_ordinary_lobby", await _open_battle()):
		return
	_main = get_tree().current_scene
	if _role == "solo":
		_main._player._combat._shoot_timer = 99.0
		_main._asteroid_timer = 99.0
		_main.child_entered_tree.connect(_track_wing_birth)
		_stage_wave()
		var spawned := await _wait_until(func(): return _wing.size() == 3, 6)
		_check("solo_keeps_the_original_two_sided_formation", spawned
			and _wing.all(func(ship): return not ship.get("duo_shear"))
			and _birth_positions[0].x < 0 and _birth_positions[2].x > NetworkManager.battle_size(_main).x,
			str(_birth_positions))
		await _finish()
		return
	if not await _require("real_enet_and_two_slots", await _wait_until(func():
			return _cond_both_players() and _main._player_entry_ready and NetworkManager.recovery.is_reserved(), 9)):
		return
	_local_slot = NetworkManager.local_player_id()
	_bait_slot = NetworkManager.recovery.guest_slot if args.has("guest-bait") else 1
	for slot: int in [1, NetworkManager.recovery.guest_slot]:
		_last_health[slot] = GameState.get_current_health(slot)
		_lost_health[slot] = 0
		_last_shield[slot] = GameState.get_shield_max_hp(slot)
		_lost_shield[slot] = 0
	_pilot = _main._players[_local_slot]
	var field := NetworkManager.battle_size(_main)
	var other_offset := 23.0 if _route == "parallel" else 260.0
	var direction := -1.0 if _reflected else 1.0
	var at := Vector2(field.x * 0.5 + direction * (-18.0 if _local_slot == _bait_slot else other_offset), field.y * 0.45)
	_pilot.position = at
	_pilot.reset_physics_interpolation()
	_pilot.set_process_unhandled_input(false)
	_pilot._motion.mobile_mode = true
	_pilot._combat._shoot_timer = 99.0
	_pilot._shield_recharge_timer = 99.0
	_pilot._invincible_timer = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_main.child_entered_tree.connect(_track_wing_birth)
	if _role == "host":
		_main.guest_bullet_batch_spawned.connect(func(slot, count, reliable):
			_log("guest_cannon_authority slot=%d count=%d reliable=%s" % [slot, count, reliable]))
		_main._asteroid_timer = 99.0
		_main._wave_director._cooldown = 99.0
		for slot: int in _last_shield:
			GameState.set_shield_layers(slot, _last_shield[slot])
		GameState.force_sync_to_peer(NetworkManager.recovery.guest_wire)
	await _wait_seconds(0.20)
	for slot: int in _last_shield:
		_last_shield[slot] = GameState.get_shield_layers(slot)
	await _barrier("ready")
	if _role == "host":
		_stage_wave()
	if not await _require("three_budgeted_shears", await _wait_until(func(): return _wing.size() == 3, 6)):
		return
	if _role == "host":
		# Isolate the chosen wave after the production director has created all three.
		_main._wave_director._cooldown = 99.0
		if not _baseline:
			_check("one_ordinary_wave_replaced", _birth_positions.all(func(pos): return pos.y < 0.0)
				and _wing.all(func(ship): return ship.get("duo_shear")), str(_birth_positions))
	var remote: int = NetworkManager.recovery.guest_slot
	_log("case=%s bait=%d slot=%d window=%s birth=%s" % [_route, _bait_slot, _local_slot, get_window().size, _birth_positions])
	if not await _require("first_visible_warning", await _wait_until(func(): return _seen_at >= 0, 4)):
		return
	if _role == "host" and not _baseline and _route != "parallel":
		_check("acquisition_matches_geometry_instead_of_host", _first_actor == _bait_slot, "selected=%d expected=%d" % [_first_actor, _bait_slot])
	if _route == "downed":
		if _role == "host":
			_main._players[_bait_slot].force_kill()
		var other := remote if _bait_slot == 1 else 1
		_check("downed_target_retires_and_other_gets_fresh_warning", await _wait_until(func():
			return not GameState.is_player_alive(_bait_slot) and _warnings.values().any(func(row):
				return row.actor == other if _role == "host" else Vector2(row.direction).dot(_first_direction) < 0.88), 6), "")
	elif _route == "rewire":
		await _check_rewire()
	var first_warning := _seen_at
	var movement: Vector2
	if _route == "parallel":
		movement = -_first_direction
	elif _local_slot == _bait_slot:
		movement = Vector2(-direction, 0.0)
	else:
		movement = Vector2.UP
	if not _pilot.is_downed:
		_pilot._motion.handle_mobile_move(movement)
	var fired_at := -1
	var next_shot := 0
	while Time.get_ticks_msec() - first_warning < 5200:
		var now := Time.get_ticks_msec()
		if now - first_warning >= 570:
			_pilot._motion.handle_mobile_move(Vector2.ZERO)
		# Let the flanker take the first exchange before the bait pilot adds support.
		var ready_to_shoot := _launch_at >= 0 and (
			_route != "flank" or _local_slot != _bait_slot or now - _launch_at >= BAIT_SUPPORT_DELAY_MS)
		if ready_to_shoot and now >= next_shot and not _pilot.is_downed:
			var enemy: Node2D = _closest_wing()
			if is_instance_valid(enemy):
				_pilot.rotation = _pilot.global_position.angle_to_point(enemy.global_position) + PI * 0.5
				_pilot._combat._shoot()
				_log("cannon slot=%d ship=%d from=%s at=%s far_side=%s" % [_local_slot, enemy.entity_id,
					_pilot.position, enemy.position, _local_slot != _bait_slot])
				next_shot = now + 330
				if fired_at < 0:
					fired_at = now
		if not is_instance_valid(_closest_wing()):
			break
		await get_tree().process_frame
	var end_at := Time.get_ticks_msec()
	_check("real_cannons_clear_the_wave", not is_instance_valid(_closest_wing()), "ms=%d" % (end_at - _wave_at))
	if _role == "host" and _route == "flank":
		var flanker := remote if _bait_slot == 1 else 1
		_check("flanking_cannon_really_hits_the_wing", int(_cannon_contacts.get(flanker, 0)) > 0,
			str(_cannon_contacts))
	await _wait_seconds(0.55)
	if not _frame_dir.is_empty():
		await _save_frame("clear")
	_check("real_fans_match_visible_locked_rays", _releases >= 3 and _releases % 3 == 0 and _bad_rays == 0,
		"bullets=%d mismatches=%d" % [_releases, _bad_rays])
	var result := {"case": _route, "first_actor": _first_actor, "bait": _bait_slot, "first_warning_ms": first_warning - _wave_at,
		"first_shot_ms": fired_at - _wave_at if fired_at >= 0 else -1, "clear_ms": end_at - _wave_at, "hp1": GameState.get_current_health(1),
		"hp2": GameState.get_current_health(remote), "lost1": _lost_health[1], "lost2": _lost_health[remote],
		"shield_lost1": _lost_shield[1], "shield_lost2": _lost_shield[remote], "real_contacts": _contacts,
		"cannon_contacts": _cannon_contacts, "moved": snappedf(at.distance_to(_pilot.global_position), 0.1), "rays": _releases}
	_log("RESULT " + JSON.stringify(result))
	await _barrier("done")
	await _finish()


func _stage_wave() -> void:
	GameState.level = 2
	seed(SEED)
	var director: Node = _main._wave_director
	director.reset(director.PHASE_SURGE)
	director._last_formation = director.FORMATION_SWARM
	director._rng.seed = SEED
	director._budget = 3.0


func _track_wing_birth(node: Node) -> void:
	if node is Enemy and node.enemy_type == 1:
		if _wave_at == 0:
			_wave_at = Time.get_ticks_msec()
		_wing.append(node)
		_birth_positions.append(node.position)


func _closest_wing() -> Node2D:
	var result: Node2D = null
	var distance := INF
	for ship in _wing:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			var candidate := _pilot.global_position.distance_squared_to(ship.global_position)
			if candidate < distance:
				distance = candidate
				result = ship
	return result


func _process(_delta: float) -> void:
	if _wing.is_empty() or get_tree().paused:
		return
	for slot: int in _last_health:
		var hp := GameState.get_current_health(slot)
		_lost_health[slot] += maxi(int(_last_health[slot]) - hp, 0)
		_last_health[slot] = hp
		var shield := GameState.get_shield_layers(slot)
		_lost_shield[slot] += maxi(int(_last_shield[slot]) - shield, 0)
		_last_shield[slot] = shield
	if _role == "host":
		for shot in get_tree().get_nodes_in_group("player_bullets"):
			if not _cannon_seen.has(shot.get_instance_id()):
				_cannon_seen[shot.get_instance_id()] = true
				shot.body_entered.connect(_real_cannon_contact.bind(shot.owner_peer_id))
	for ship in _wing:
		if not is_instance_valid(ship) or ship.attack_phase != Enemy.AttackPhase.PREPARE:
			continue
		var key := Vector2i(ship.entity_id, ship.attack_stamp)
		if _warnings.has(key):
			continue
		var headless := DisplayServer.get_name() == "headless"
		if not headless and ship._ordinary_visual.drawn_warning_stamp != ship.attack_stamp:
			continue
		var actor: int = ship._attack_target.peer_id if is_instance_valid(ship._attack_target) else 0
		var rays: Array[Dictionary] = []
		for index in ship.attack_angles.size():
			rays.append({"dir": Vector2.from_angle(ship.attack_angles[index]), "origin": ship.attack_muzzle(index)})
		_warnings[key] = {"direction": Vector2.from_angle(ship.attack_heading), "rays": rays, "actor": actor}
		if _seen_at < 0:
			_seen_at = Time.get_ticks_msec()
			_first_actor = actor
			_first_direction = _warnings[key].direction
			if not _frame_dir.is_empty():
				_save_frame.call_deferred("warning")
	for shot in get_tree().get_nodes_in_group("enemy_bullets"):
		if shot.ordinary_enemy_round <= 0 or _seen_bullets.has(shot.get_instance_id()):
			continue
		_seen_bullets[shot.get_instance_id()] = true
		if _role == "host":
			shot.body_entered.connect(_enemy_projectile_contact)
		_releases += 1
		var ray: Vector2 = shot._direction
		var at: Vector2 = shot.global_position
		var matched := _warnings.values().any(func(row):
			for announced: Dictionary in row.rays:
				if ray.is_equal_approx(announced.dir) and absf((at - Vector2(announced.origin)).cross(ray)) < 0.8:
					return true
			return false)
		_bad_rays += int(not matched)
		if _launch_at < 0:
			_launch_at = Time.get_ticks_msec()
			if not _frame_dir.is_empty():
				_save_frame.call_deferred("release")


func _enemy_projectile_contact(body: Node2D) -> void:
	if body.is_in_group("player"):
		var slot: int = body.peer_id
		_contacts[slot] = int(_contacts.get(slot, 0)) + 1
		_log("enemy_real_contact slot=%d at=%s" % [slot, body.position])


func _real_cannon_contact(body: Node2D, slot: int) -> void:
	if _wing.has(body):
		_cannon_contacts[slot] = int(_cannon_contacts.get(slot, 0)) + 1


func _save_frame(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# The draw stamp can arrive before the new pixels are available to read back.
	var rendered := [false]
	var mark := func(): rendered[0] = true
	RenderingServer.frame_post_draw.connect(mark, CONNECT_ONE_SHOT)
	if not await _wait_until(func(): return rendered[0], 1.5):
		if RenderingServer.frame_post_draw.is_connected(mark):
			RenderingServer.frame_post_draw.disconnect(mark)
		_log("capture unavailable label=" + label)
		return
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png(_frame_dir.path_join("%s-%s-%s.png" % [_route, _role, label]))


func _check_rewire() -> void:
	await _barrier("hold_wing")
	var previous: int = NetworkManager.recovery.guest_wire
	var ids := _wing.map(func(ship): return ship.entity_id)
	var old_warnings := _warnings.keys()
	if _role == "client":
		NetworkManager.recovery.set_background(true)
	var held := await _wait_until(func(): return get_tree().paused, 3)
	_check("holds_clear_warnings_without_offscreen_fire", held and _wing.all(func(ship):
		return is_instance_valid(ship) and ship.attack_phase == Enemy.AttackPhase.FLIGHT), "")
	if _role == "client":
		await _wait_seconds(0.2)
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var joined := await _wait_until(func():
		return (not get_tree().paused and NetworkManager.recovery.guest_wire != previous
			and NetworkManager.recovery.guest_wire > 1), 13)
	_check("same_wing_and_no_replayed_warning_on_new_wire", joined and _wing.size() == ids.size()
		and _wing.map(func(ship): return ship.entity_id) == ids, str(ids))
	_seen_at = -1
	_launch_at = -1
	_check("restored_wing_has_a_fresh_visible_warning", await _wait_until(func():
		return _seen_at >= 0 and _warnings.keys().any(func(key): return not old_warnings.has(key)), 5), "")
