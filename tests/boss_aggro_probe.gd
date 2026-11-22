extends "res://tests/boss_coop_probe.gd"

const Ledger := preload("res://scripts/boss_aggro.gd")
var _mirror := false
var _targets: Dictionary = {}
var _directions: Dictionary = {}

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	_mirror = args[2] == "boss-aggro-mirror"
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	if not _require("real_enet", err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)):
		return
	_enter_main_scene()
	if not _require("two_slots", await _wait_until(func(): return _cond_both_players() and NetworkManager.recovery.is_reserved(), 6)):
		return
	_guest = NetworkManager.recovery.guest_slot
	_main._asteroid_timer = INF
	_main._wave_director._cooldown = INF
	_main._player.set_physics_process(false)
	var my_slot := NetworkManager.local_player_id()
	var left_slot := _guest if _mirror else 1
	var right_slot := 1 if _mirror else _guest
	_main._player.global_position = P1_AT if my_slot == left_slot else P2_AT
	await _barrier("fixed_geometry")
	if _role == "host":
		_check("guest_matches_location", await _wait_until(func():
			return _main._players[_guest].global_position.distance_to(P1_AT if _mirror else P2_AT) < 1.0, 2.0), "")
		_main._spawn_boss(5)
		var boss: BossModel = _main._boss
		boss._stop_entry_motion()
		boss.set_physics_process(false)
		boss.global_position = AT
		boss.attack_target_selected.connect(_record)
		for _i in 4:
			var previous := get_tree().get_nodes_in_group("enemy_bullets")
			boss._do_aimed_shot()
			_check("emitted_aimed_follows_selected_direction", _new_volley_matches(previous, "aimed"), "")
			previous = get_tree().get_nodes_in_group("enemy_bullets")
			boss._do_fan_spread()
			_check("emitted_fan_center_follows_selected_direction", _new_volley_matches(previous, "fan"), "")
			boss._start_ultimate_laser()
			boss._tick_ultimate_laser(BossModel.BOSS_ULTIMATE_LASER_CHARGE + 0.02)
			var laser: Dictionary = _main._boss_snapshot(boss)
			var actual := Vector2(laser.to - laser.from).normalized()
			var aimed: Vector2 = _directions["laser"].back()
			_check("actual_laser_lock_direction", actual.dot(aimed) > .998, str(actual))
			boss._finish_ultimate_laser()
			boss._pulse_used_this_shield = false
			if boss._try_coop_pulse():
				boss._finish_coop_pulse()
		for kind in ["aimed", "fan", "laser", "pulse"]:
			var slots: Array = _targets.get(kind, [])
			var dirs: Array = _directions.get(kind, [])
			_check(kind + "_targets_each_side", slots.size() == 4 and slots[0] == left_slot
				and slots.has(right_slot) and dirs[0].x < 0.0 and dirs[slots.find(right_slot)].x > 0.0, str(slots))
		boss._aggro = Ledger.new()
		boss.take_damage(30.0, _guest)
		_check("guest_shield_damage_pulls", boss._pick_attack_pilot("aimed").peer_id == _guest, "")
		boss._aggro.advance(15.0)
		boss.take_damage(30.0, 1)
		_check("aged_threat_allows_host_to_take_over", boss._pick_attack_pilot("aimed").peer_id == 1, "")
		var ledger := Ledger.new()
		for _i in 10:
			ledger.record_damage(1, 1.0)
		ledger.record_damage(_guest, 10.0)
		_check("same_applied_damage_same_threat", is_equal_approx(ledger.damage_score(1, 500), ledger.damage_score(_guest, 500)), "")
	else:
		_check("host_snapshot_reaches_joiner", await _wait_until(func(): return is_instance_valid(_main._boss), 4), "")
	await _barrier("checks_complete")
	await _wait_seconds(.25)
	get_tree().quit(_summarize())

func _new_volley_matches(previous: Array, attack: String) -> bool:
	var average := Vector2.ZERO
	var count := 0
	for shot in get_tree().get_nodes_in_group("enemy_bullets"):
		if not previous.has(shot):
			average += shot._direction
			count += 1
	var recorded: Array = _directions.get(attack, [])
	return count > 0 and not recorded.is_empty() and average.normalized().dot(recorded.back()) > .99

func _record(attack: String, slot: int, direction: Vector2) -> void:
	var slots: Array = _targets.get_or_add(attack, [])
	slots.append(slot)
	var dirs: Array = _directions.get_or_add(attack, [])
	dirs.append(direction)
