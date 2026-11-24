extends "res://tests/boss_coop_probe.gd"

const Trial := preload("res://scripts/rift_route_trial.gd")
const Route := preload("res://scenes/rift_route_trial.tscn")
const Weapon := preload("res://scripts/rift_hunter_attack.gd")
const LINE := Weapon.Pattern.LINE
const RING := Weapon.Pattern.RING
var _volleys: Array[Dictionary] = []
var _destination := Vector2.INF

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var online := _role != "solo"
	var wide_host := args.size() > 2 and args[2] == "hunter-wide-host"
	if online:
		var wide := (_role == "host") == wide_host
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600, 720) if wide else Vector2i(960, 720)
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if not _require("real_enet", err == OK and await _wait_until(func():
			return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)):
			return
	_evidence = args[3] if args.size() > 3 else ""
	seed(90220)
	var trial := Route.instantiate() as Trial
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	_main = trial
	if online and not _require("both_pilots", await _wait_until(func():
		return _cond_both_players() and NetworkManager.recovery.is_reserved(), 6)):
		return
	var local: Node2D = trial._player
	var near_slot := 1
	if online:
		_guest = NetworkManager.recovery.guest_slot
		near_slot = 1 if wide_host else _guest
	local.set_physics_process(false)
	local._motion.mobile_mode = true
	local.global_position = Vector2(640, 460) if local.peer_id == near_slot else Vector2(935, 486)
	await _pair_barrier("positioned")
	var born := Engine.get_physics_frames()
	if _role != "client":
		GameState.set_shield_layers(1, 0)
		if online:
			GameState.set_shield_layers(_guest, 0)
		trial._set_leg(Trial.Leg.ELITE)
		trial.trial_tick = Trial.ELITE_LEG + 154
	if not _require("route_hunter_entered", await _wait_until(func(): return is_instance_valid(trial._elite), 3)):
		return
	if _role == "host":
		trial._elite.take_damage(29, near_slot)
	get_tree().node_added.connect(_observe_shot)
	var first := await _wait_for_preview(LINE)
	var lead_frames := Engine.get_physics_frames() - born
	if not _require("opening_tracks_stable_slot", not first.is_empty() and first.slot == near_slot):
		return
	if _role != "client":
		_check("quick_entry_immediately_warns", absi(lead_frames - 16) <= 3, str(lead_frames))
	var hp := GameState.get_current_health(near_slot)
	await _capture("pursuit-warning")
	if online:
		await _verify_rewire(first)
		if local.peer_id == near_slot:
			_destination = local.global_position + Vector2.from_angle(first.angle).orthogonal() * 104.0
	var ring := await _wait_for_preview(RING)
	_check("pursuit_two_real_fans_match_lock", _matches_volley(first, 0, 3) and _matches_volley(first, 3, 3),
		str(_volleys.slice(0, 6)))
	if _role != "client" and _volleys.size() >= 6:
		var spacing: int = _volleys[3].frame - _volleys[0].frame
		_check("pursuit_second_fan_timing", spacing == 11, str(spacing))
	var now := GameState.get_current_health(near_slot)
	_check("movement_avoids_pursuit_or_stationary_takes_hit", now == hp if online else now < hp, "%d→%d" % [hp, now])
	if not _require("ring_preview_visible", not ring.is_empty()):
		return
	await _capture("ring-warning")
	if _role != "client":
		var ring_pilot: Node2D = trial._player if not online else trial._players.get(int(ring.slot))
		ring_pilot._invincible_timer = 0.0
	if local.peer_id == ring.slot:
		var radial: Vector2 = local.global_position - ring.origin
		var turn := clampf(wrapf(float(ring.angle) - radial.angle(), -PI, PI), -.33, .33)
		_destination = Vector2(ring.origin) + radial.rotated(turn)
	var before_ring := GameState.get_current_health(int(ring.slot))
	var ring_done := await _wait_until(func(): return _volleys.size() >= 18, 2.5)
	_check("ring_actual_bullets_leave_77_degree_gap", ring_done and _matches_volley(ring, 6, 12), str(ring))
	await _capture("ring-release")
	await _wait_seconds(.96)
	if local.peer_id == ring.slot:
		var radial: Vector2 = local.global_position - ring.origin
		var in_gap := absf(wrapf(radial.angle() - float(ring.angle), -PI, PI)) < Weapon.RING_HALF_GAP
		_check("pilot_moves_into_ring_gap_without_loss", in_gap and GameState.get_current_health(local.peer_id) == before_ring,
			"hp=%d" % GameState.get_current_health(local.peer_id))
	await _pair_barrier("ring_checked")
	await _verify_break_and_cleanup(trial)
	await _pair_barrier("done")
	await _wait_seconds(.22)
	get_tree().quit(_summarize())

func _verify_rewire(first: Dictionary) -> void:
	var old_wire: int = NetworkManager.recovery.guest_wire
	if _role == "client":
		await _wait_seconds(.10)
		NetworkManager.recovery.set_background(true)
		await _wait_seconds(.16)
		_main._entities.erase(_main._elite.entity_id)
		_main._elite.queue_free()
		await get_tree().process_frame
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var restored := await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != old_wire
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13)
	var cue := _preview()
	_check("new_wire_restores_only_remaining_warning", restored and cue.get("stamp") == first.stamp
		and cue.get("origin") == first.origin and cue.get("angle") == first.angle
		and cue.get("left", 0.0) > 0.0 and cue.get("left", 1.0) < Weapon.LINE_WARNING - 0.04
		and _volleys.is_empty(), "wire=%d→%d remaining=%.3f" % [old_wire, NetworkManager.recovery.guest_wire, cue.get("left", 0.0)])

func _verify_break_and_cleanup(trial: Trial) -> void:
	var third := await _wait_for_preview(LINE)
	if not _require("third_preview_visible", not third.is_empty()):
		return
	var first_fan := await _wait_until(func(): return _volleys.size() >= 21, 2.0)
	if _role != "client" and first_fan:
		var elite := trial._elite
		# 开火后用近距离实弹破盾，赶在第二扇之前。
		trial._player._combat._spawn_bullet(elite.global_position + Vector2(0, 33), -PI * .5,
			int(elite.get_network_shield()), true, 1, 720.0)
	var broke := await _wait_until(func(): return trial._elite.get_network_shield() == 0.0, 1.0)
	if _role != "client" and broke:
		var elite := trial._elite
		elite.take_damage(ceili(elite.get_network_max_health() * .58), 1)
	await _wait_seconds(.35)
	var active_fan := get_tree().get_nodes_in_group("enemy_bullets").any(func(shot: Node):
		return shot.modulate.is_equal_approx(Weapon.LINE_COLOR))
	_check("break_cancels_second_fan_but_keeps_first_in_flight", broke and _volleys.size() == 21 and active_fan,
		"fired=%d stored_bullets=%s" % [_volleys.size(), active_fan])
	if _role != "client":
		var exposed_start := Engine.get_physics_frames()
		var exposure_ended := await _wait_until(func(): return trial._elite._phase_b_timer <= 0.0, 5.0)
		var exposure_remaining := Engine.get_physics_frames() - exposed_start
		_check("four_second_exposure_has_no_new_attack", exposure_ended and exposure_remaining >= 210 and _volleys.size() == 21,
			"exposure after first .35s=%d frames" % exposure_remaining)
	var low_ring := await _wait_for_preview(RING, 7.0)
	_check("low_hull_keeps_full_ring_warning", not low_ring.is_empty() and low_ring.left > .59
		and trial._elite.get_network_health() < trial._elite.get_network_max_health() * .35, str(low_ring))
	if low_ring.is_empty():
		return
	var ring_done := await _wait_until(func(): return _volleys.size() >= 33, 1.6)
	var fired_at := int(_volleys[21].frame) if ring_done else 0
	var next := await _wait_for_preview(LINE)
	_check("low_hull_has_shorter_recovery_and_same_warning", not next.is_empty() and next.left > .54
		and absi((Engine.get_physics_frames() - fired_at) - 38) <= 4, str(next))
	await _pair_barrier("clear_prepared")
	if _role == "host":
		trial.trial_tick = Trial.SETTLE_TICK - 1
	elif _role == "solo":
		trial._elite.take_damage(1000, 1)
	var removed := await _wait_until(func(): return not is_instance_valid(trial._elite), 2.0)
	await _wait_seconds(.7)
	_check("death_or_route_clear_cancels_pending_attack", removed and _volleys.size() == 33, str(_volleys.size()))

func _physics_process(delta: float) -> void:
	if _destination == Vector2.INF or get_tree().paused or not is_instance_valid(_main):
		return
	var pilot: Node2D = _main._player
	if not is_instance_valid(pilot):
		return
	var axis := pilot.global_position.direction_to(_destination)
	if pilot.global_position.distance_to(_destination) < 12.0:
		_destination = Vector2.INF
		axis = Vector2.ZERO
	pilot._motion.handle_mobile_move(axis)
	pilot._motion.update(delta, 1.0, NetworkManager.battle_size(pilot))

func _observe_shot(node: Node) -> void:
	if node.scene_file_path == "res://scenes/entities/bullet.tscn":
		_record_shot.call_deferred(node, Engine.get_physics_frames())

func _record_shot(node: Node, frame: int) -> void:
	if not is_instance_valid(node) or not node.is_in_group("enemy_bullets"):
		return
	if node.modulate.is_equal_approx(Weapon.LINE_COLOR) or node.modulate.is_equal_approx(Weapon.RING_COLOR):
		_volleys.append({"frame": frame, "angle": node._direction.angle()})

func _matches_volley(cue: Dictionary, begin: int, count: int) -> bool:
	if cue.is_empty() or _volleys.size() < begin + count:
		return false
	var expected := Weapon.projectile_angles(cue.pattern, cue.angle)
	for i in count:
		if absf(wrapf(float(_volleys[begin + i].angle) - expected[i], -PI, PI)) > .002:
			return false
	return true

func _preview() -> Dictionary:
	if not is_instance_valid(_main._elite) or not _main._elite._route_weapon:
		return {}
	var weapon: Node2D = _main._elite._route_weapon
	if _role != "client":
		return weapon.snapshot()
	return {"stamp": weapon._stamp, "pattern": weapon._shown, "left": weapon._show_left,
		"origin": weapon.global_position, "angle": weapon._angle, "slot": weapon._slot}

func _wait_for_preview(kind: int, seconds := 4.0) -> Dictionary:
	var seen := await _wait_until(func(): return _preview().get("pattern", 0) == kind, seconds)
	return _preview() if seen else {}

func _pair_barrier(label: String) -> void:
	if _role != "solo":
		await _barrier(label)
