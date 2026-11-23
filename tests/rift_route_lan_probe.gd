extends "res://tests/boss_coop_probe.gd"

const Route := preload("res://scenes/rift_route_trial.tscn")
const Trial := preload("res://scripts/rift_route_trial.gd")
const Elite := preload("res://scripts/elite.gd")
const Mobile := preload("res://scenes/ui/mobile_controls.tscn")
var _last_choice_frame := 0
var _last_choice_tick := 0
var _last_choice_source := ""

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mode := OS.get_cmdline_user_args()[2]
	var wide_host := mode.ends_with("-host")
	var use_timeout := mode.begins_with("rift-timeout-")
	var wide := (_role == "host") == wide_host
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1600, 720) if wide else Vector2i(960, 720)
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	if not _require("real_enet", err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)):
		return
	var trial := Route.instantiate() as Trial
	var stick := Mobile.instantiate()
	trial.add_child(stick)
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	_main = trial
	if not _require("stable_player_slots", await _wait_until(func(): return _cond_both_players() and NetworkManager.recovery.is_reserved(), 6)):
		return
	_guest = NetworkManager.recovery.guest_slot
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.emulate_mouse_from_touch = true
	var slot := NetworkManager.local_player_id()
	var host_card := 0 if wide_host else 1
	if use_timeout:
		host_card = 1 - host_card
	var guest_card := 1 - host_card
	var slow := (_role == "host") != wide_host
	var mine := host_card if _role == "host" else guest_card
	var score_rows := Leaderboard.get_entries()
	seed(90220)
	if _role == "host":
		UpgradeDraft.card_chosen.connect(func(pid: int, _card: String, _index: int):
			if not trial._draft_wait:
				_last_choice_frame = Engine.get_physics_frames()
				_last_choice_tick = trial.trial_tick
				_last_choice_source = UpgradeDraft.get_draft(pid).source)
	var touch_origin := Vector2(132, 558)
	_touch(touch_origin, 0, true)
	_drag(touch_origin + Vector2(0, 72))
	await _barrier("rift_ready")
	if _role == "host":
		trial.trial_tick = Trial.CARD_TICK - 1
	var opened := await _wait_until(func(): return UpgradeDraft.has_draft(slot), 3)
	_check("fixed_options_on_both_devices", opened and UpgradeDraft.get_draft(slot).cards == ["pierce", "splash", "power"], "")
	await _verify_draft_controls(trial, stick, touch_origin, slot)
	await _barrier("both_drafts")
	if not slow:
		_tap(trial._hud._draft_card_buttons[mine].get_global_rect().get_center())
	await _wait_seconds(.35)
	_check("wave_waits_for_other_choice", trial._draft_wait and trial.trial_tick == Trial.CARD_TICK
		if _role == "host" else UpgradeDraft.has_draft(slot) == slow, "")
	await _barrier("draft_hold_checked")
	if slow and not use_timeout:
		_tap(trial._hud._draft_card_buttons[mine].get_global_rect().get_center())
	var both := await _wait_until(func():
		return (GameState.get_card_count(Trial.OFFER[host_card], 1) == 1
			and GameState.get_card_count(Trial.OFFER[guest_card], _guest) == 1), 11.5 if use_timeout else 3.0)
	_check("distinct_cards_and_single_grants", both, "")
	var cue := await _wait_until(func(): return not trial._fighters.is_empty(), 4.5)
	_check("host_authored_wave_shared", cue and NetworkManager.battle_size(trial) == Vector2(1280, 720), "")
	if _role == "host":
		var frames := Engine.get_physics_frames() - _last_choice_frame
		_check("wave_schedule_starts_after_last_confirmation_or_timeout", cue and _last_choice_tick == Trial.CARD_TICK
			and trial.trial_tick == Trial.BUILD_WAVES[0] and absi(frames - 90) <= 1
			and _last_choice_source == ("timeout" if use_timeout else "tap"),
			"source=%s last_tick=%d wave_tick=%d elapsed=%d" % [_last_choice_source, _last_choice_tick, trial.trial_tick, frames])
	var wing_present := await _wait_until(func():
		return get_tree().get_nodes_in_group("ordinary_enemies").any(func(ship: Node): return ship.health == Trial.ARMOR_HP), 1.5)
	_check("armored_flank_starts_with_shared_health", wing_present, "")
	await _barrier("wave_observed")
	if _role == "client":
		NetworkManager.recovery.set_background(true)
		await _wait_seconds(.2)
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var wire_at_start := _guest
	var restored := await _wait_until(func():
		return NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != wire_at_start and not get_tree().paused, 13)
	_check("reconnect_does_not_reoffer_or_clear_cards", restored and trial.leg == Trial.Leg.BUILD and GameState.get_card_count(Trial.OFFER[guest_card], _guest) == 1
		and not UpgradeDraft.has_draft(slot), "")
	await _barrier("rewire_complete")
	await _verify_card_impacts(trial, host_card)
	await _verify_elite(trial)
	if _role == "host":
		trial.trial_tick = Trial.SETTLE_TICK - 1
		await get_tree().physics_frame
		await get_tree().physics_frame
		trial.trial_tick = Trial.BOSS_LEG - 1
	var on_boss := await _wait_until(func(): return is_instance_valid(trial._boss) and trial.leg == Trial.Leg.BOSS, 4)
	_check("only_host_advances_boss_leg", on_boss, "")
	await _barrier("boss_observed")
	if _role == "host" and on_boss:
		var boss := trial._boss
		boss.take_damage(boss.get_max_shield_hp(), 1)
		boss.take_damage(boss.get_network_max_health(), 1)
	var complete := await _wait_until(func(): return trial.finished, 3)
	_check("same_terminal_state_without_leaderboard", complete and trial._result.text.begins_with("通关")
		and Leaderboard.get_entries() == score_rows, "")
	await _barrier("rift_complete")
	await _wait_seconds(.25)
	get_tree().quit(_summarize())


func _verify_draft_controls(trial: Trial, stick: Node, origin: Vector2, slot: int) -> void:
	var start: Vector2 = trial._player.global_position
	_drag(origin + Vector2(87, 0))
	var laser: Vector2 = trial._hud._skill_slots[0].button.get_global_rect().get_center()
	_tap(laser)
	var used := await _wait_until(func():
		return (GameState.get_laser_cooldown(slot) > 0.0 and trial._player.global_position.x > start.x + 5.0), 1.4)
	_check("draft_keeps_left_drag_and_second_finger_cast", used and stick._move_touch_id == 0 and UpgradeDraft.has_draft(slot),
		"owner=%d drag=%s laser=%.2f moved=%.1f" % [stick._move_touch_id, trial._player._motion.touch_move,
			GameState.get_laser_cooldown(slot), trial._player.global_position.x - start.x])
	_touch(origin + Vector2(87, 0), 0, false)
	_check("draft_release_clears_move", stick._move_touch_id == -1, "")
	trial._player.set_physics_process(false)


func _tap(at: Vector2) -> void:
	_touch(at, 1, true)
	_touch(at, 1, false)


func _touch(at: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.index = index
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _drag(at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = at
	get_viewport().push_input(event, true)


func _verify_card_impacts(trial: Trial, host_card: int) -> void:
	var targets: Array[Node2D] = []
	if _role == "host":
		for lane in 2:
			var x := 240.0 + lane * 795.0
			var pierce := lane == host_card
			var secondary := Vector2(x, 270) if pierce else Vector2(x + 50.0, 360.0)
			for at in [Vector2(x, 360), secondary]:
				var target := trial._spawn_enemy_at(0, at)
				target.set_physics_process(false)
				target.health = 30
				targets.append(target)
	await _barrier("card_targets")
	var x := 240.0 if _role == "host" else 1035.0
	trial._player._combat._spawn_bullet(Vector2(x, 520), -PI * .5, 4, true, 1, 700.0)
	await _wait_seconds(.65)
	if _role == "host":
		var hp := targets.map(func(target: Node2D): return target.health)
		_check("both_primary_targets_hit_by_real_shots", hp[0] < 30 and hp[2] < 30, str(hp))
		_check("both_cards_damage_secondary_target", hp[1] < 30 and hp[3] < 30, str(hp))
	await _barrier("card_impacts")


func _verify_elite(trial: Trial) -> void:
	if _role == "host":
		trial._clear_non_boss_entities()
		trial.trial_tick = Trial.ELITE_LEG + 154
	if not await _wait_until(func(): return is_instance_valid(trial._elite), 3):
		_check("route_elite_present", false, "")
		return
	var elite: Elite = trial._elite
	await _wait_seconds(1.8)
	await _barrier("elite_in_field")
	if _role == "host":
		for _i in 3:
			elite.take_damage(1, _guest)
	var cue := await _wait_until(func(): return elite.modulate.r < .85, 1.0)
	_check("elite_dodge_cue_visible", cue, str(elite.modulate))
	await _barrier("elite_cue_visible")
	if _role == "host":
		elite.take_damage(int(elite.get_network_shield()), 1)
	var broken := await _wait_until(func(): return elite.get_network_shield() == 0, 1.0)
	_check("shield_break_removes_pending_dodge_cue", broken and elite.modulate.is_equal_approx(Color.WHITE), str(elite.modulate))
	await _barrier("elite_shield_broken")
	if _role == "host":
		elite.take_damage(75, 1)
		elite._phase_c_drone_timer = 0.0
	var drones: Array[Node] = []
	await _wait_until(func():
		drones.assign(get_tree().get_nodes_in_group("ordinary_enemies").filter(func(n: Node): return not n.is_queued_for_deletion()))
		return drones.size() == 2, 1.3)
	var ids := drones.map(func(n: Node): return n.get_entity_id())
	_check("elite_minions_are_registered_on_both_ends", ids.size() == 2 and ids[0] > 0
		and ids[1] > 0 and ids[0] != ids[1]
		and drones.all(func(n: Node): return n.health == 2 and trial._entities.get(n.entity_id) == n), str(ids))
	await _barrier("elite_minions_seen")
