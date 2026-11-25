extends "res://tests/boss_coop_probe.gd"

const Route := preload("res://scenes/rift_route_trial.tscn")
const Trial := preload("res://scripts/battle/trials/rift_route_trial.gd")
const Elite := preload("res://scripts/battle/enemies/elite.gd")
const Mobile := preload("res://scenes/ui/mobile_controls.tscn")
var _last_choice_frame := 0
var _last_choice_tick := 0
var _last_choice_source := ""

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var mode := args[2]
	_evidence = args[3] if args.size() > 3 else ""
	var review := mode == "rift-review"
	var wide_host := mode.ends_with("-host")
	var use_timeout := mode.begins_with("rift-timeout-")
	var wide := (_role == "host") == wide_host
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var viewport_width: int = (1600 if _role == "host" else 960) if review else (1600 if wide else 960)
	get_window().content_scale_size = Vector2i(viewport_width, 720)
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	if not _require("real_enet", err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8)):
		return
	GameState.rift_remix = review
	var trial := Route.instantiate() as Trial
	var stick := Mobile.instantiate()
	trial.add_child(stick)
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	_main = trial
	if not _require("stable_player_slots", await _wait_until(func(): return _cond_both_players() and NetworkManager.recovery.is_reserved(), 6)):
		return
	_guest = NetworkManager.recovery.guest_slot
	if review:
		await _verify_route_reviews(trial)
		get_tree().quit(_summarize())
		return
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
	var stage_seen := await _wait_until(func(): return trial.leg == Trial.Leg.BUILD, .4)
	_check("build_hint_waits_for_local_card_and_leaves_draft_clear", stage_seen and trial._build_hint_pending
		and trial._route_hint_left == 0.0 and trial._hud._draft_panel.visible, trial._hud._phase_label.text)
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
	var expect_hint := not use_timeout or slow
	var hinted := await _wait_until(func(): return trial._hud._phase_label.text == Trial.LEG_HINTS[Trial.Leg.BUILD], .3) if expect_hint else false
	var cue_left := trial._route_hint_left
	trial._rpc_route_leg(Trial.Leg.BUILD, false)
	_check("build_hint_once_after_card_confirmation", (hinted and _hint_fits(trial) if expect_hint else cue_left == 0.0)
		and trial._route_hint_left == cue_left, "%s remaining=%.2f" % [trial._hud._phase_label.text, cue_left])
	await _capture("build-hint")
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
	if _role == "host":
		var order: Dictionary = trial._fighters.wing
		await _wait_until(func(): return trial._is_charging(order), 2.5)
		var ship: Node2D = order.ship
		trial._player._combat._spawn_bullet(ship.global_position + Vector2(0, 38), -PI * .5, 9, true, 1, 760.0)
	_check("real_bullet_interrupt_shows_one_local_cue", await _wait_until(func():
		return trial._cut_cues.size() == 1, 3.1), "")
	await _barrier("cut_observed")
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
	_check("recovery_restores_title_without_replaying_hint", restored and trial._route_hint_left == 0.0
		and trial._hud._phase_label.text.ends_with(Trial.LEG_NAMES[Trial.Leg.BUILD]), trial._hud._phase_label.text)
	_check("recovery_does_not_replay_cut_feedback", trial._cut_cues.is_empty(), "")
	await _barrier("rewire_complete")
	await _verify_card_impacts(trial, host_card)
	await _verify_elite(trial)
	var earned := not use_timeout
	if earned:
		await _finish_hunter_with_shot(trial, 1 if wide_host else _guest)
		await _barrier("hunter_reward_observed")
		var reward_wire: int = NetworkManager.recovery.guest_wire
		if _role == "client":
			NetworkManager.recovery.set_background(true)
			await _wait_seconds(.2)
			NetworkManager.drop_lan_transport()
			NetworkManager.recovery.set_background(false)
		_check("hunter_notice_not_replayed_after_recovery", await _wait_until(func():
			return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != reward_wire
				and not get_tree().paused and trial._route_notice.is_empty()), 13), "")
		await _barrier("hunter_reward_recovered")
	if _role == "host":
		trial.trial_tick = Trial.SETTLE_TICK - 1
		await get_tree().physics_frame
		await get_tree().physics_frame
		trial.trial_tick = Trial.BOSS_LEG - 1
	var on_boss := await _wait_until(func(): return is_instance_valid(trial._boss) and trial.leg == Trial.Leg.BOSS, 4)
	_check("only_host_advances_boss_leg", on_boss, "")
	await _barrier("boss_observed")
	if on_boss:
		if _role == "host":
			trial._boss._start_ultimate_laser()
		var charging := await _wait_until(func(): return trial._boss.get_attack_window() == BossModel.AttackWindow.CHARGING, .9)
		_check("boss_hint_keeps_charge_and_buttons_clear", charging and trial._hud._phase_label.text == Trial.LEG_HINTS[Trial.Leg.BOSS]
			and _hint_fits(trial), str(trial._hud._phase_label.get_global_rect()))
		await _capture("boss-hint")
		await _barrier("boss_hint_checked")
		await _verify_exposure(trial._boss, 5.5 if earned else 4.5, trial)
		await _barrier("boss_first_exposure_observed")
		await _verify_exposure(trial._boss, 4.5, trial)
		await _barrier("boss_second_exposure_observed")
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

func _verify_route_reviews(trial: Trial) -> void:
	var cases := [
		{"name": "zero", "leg": Trial.Leg.INTERCEPT, "cuts": 0, "hunter": false, "outcome": "被击落",
			"facts": "猎手未击破 · 盾沿命中 0 次", "tip": "下局试着先切掉一股齐射"},
		{"name": "early", "leg": Trial.Leg.BUILD, "cuts": 1, "hunter": false, "outcome": "被击落",
			"facts": "猎手未击破 · 盾沿命中 0 次", "tip": "下局试着换一条拦截路线"},
		{"name": "earned", "leg": Trial.Leg.ELITE, "cuts": 1, "hunter": true, "outcome": "被击落",
			"facts": "猎手击破 · 奖励未用 · 盾沿命中 0 次", "tip": "下局试着换一条拦截路线"},
		{"name": "boss", "leg": Trial.Leg.BOSS, "cuts": 2, "hunter": false, "outcome": "被击落",
			"facts": "猎手未击破 · 盾沿命中 0 次", "tip": "下局试着横移，再从侧翼打盾"},
		{"name": "win", "leg": Trial.Leg.BOSS, "cuts": 3, "hunter": true, "outcome": "通关",
			"facts": "猎手击破 · 奖励已兑现 · 盾沿命中 1 次", "tip": "下局试试另一张首卡或另一条拦截路线"},
	]
	var scores := Leaderboard.get_entries().duplicate(true)
	for sample: Dictionary in cases:
		var label: String = sample.name
		if not trial.has_node("MobileControls"):
			trial._spawn_mobile_controls()
		trial._player.set_physics_process(false)
		await _barrier("review_ready_" + label)
		if _role == "host":
			trial.trial_tick = 4500
			trial._set_leg(Trial.Leg.ELITE if sample.hunter else sample.leg)
			await _review_intercept_shots(trial, int(sample.cuts))
			if sample.hunter:
				trial.trial_tick = Trial.ELITE_LEG + 154
		if sample.hunter:
			if not _require(label + "_hunter_present", await _wait_until(func(): return is_instance_valid(trial._elite), 2.0)):
				return
			await _finish_hunter_with_shot(trial, 1)
			await _barrier(label + "_hunter_complete")
		if _role == "host":
			if sample.leg == Trial.Leg.BOSS:
				trial._set_leg(Trial.Leg.BOSS)
				trial._start_route_boss()
		if label == "win":
			await _review_flank_shot(trial)
		if _role == "host":
			if sample.outcome == "通关" and is_instance_valid(trial._boss):
				var boss := trial._boss
				boss.take_damage(boss.get_shield_hp(), 1)
				boss.take_damage(boss.get_network_max_health(), 1)
			elif sample.outcome != "通关":
				for pilot in trial._players.values():
					pilot.force_kill()
				GameState.force_sync_to_peer(-1)
		var settled := await _wait_until(func(): return trial.finished, 3.0)
		if sample.outcome == "被击落":
			_check(label + "_defeat_is_authoritative", await _wait_until(func():
				return not GameState.is_player_alive(1) and not GameState.is_player_alive(_guest), .8), "")
		var expected := "%s · 截断 %d 次\n%s\n%s" % [sample.outcome, sample.cuts, sample.facts, sample.tip]
		_check(label + "_same_review_and_actual_intercepts", settled and trial.leg == sample.leg
			and trial.interruptions == sample.cuts and trial._result.text == expected,
			"leg=%d %s" % [trial.leg, trial._result.text.replace("\n", " | ")])
		_check(label + "_review_fits_and_clears_stage_hint", Trial.SafeArea.for_viewport(get_viewport()).encloses(trial._options.get_global_rect())
			and trial._route_hint_left == 0.0 and not trial._build_hint_pending and not trial._hud._game_over_panel.visible, "")
		_check(label + "_review_stays_off_skill_buttons", trial._hud._skill_slots.all(func(slot: Dictionary):
			return not trial._options.get_global_rect().intersects(slot.button.get_global_rect())), "")
		var settled_round := GameState.get_sync_round()
		trial._rpc_route_result(settled_round, "被击落", 99, Trial.Leg.BOSS, {})
		_check(label + "_old_result_cannot_rewrite_review", trial.interruptions == sample.cuts and trial._result.text == expected, "")
		var retry: Button = trial.get_node("TrialUI/Options/Buttons/Retry")
		var back: Button = trial.get_node("TrialUI/Options/Buttons/Back")
		_check(label + "_existing_buttons_respect_authority", retry.is_visible_in_tree() == (_role == "host")
			and back.is_visible_in_tree(), "")
		if label == "win":
			await _review_recovery(trial, expected)
		if _role == "host" and label == "boss":
			await _capture("review-phone")
		elif _role == "client" and label == "win":
			await _capture("review-tablet")
		if _role == "client":
			trial._restart()
			await get_tree().process_frame
			_check(label + "_guest_retry_cannot_reload", get_tree().current_scene == trial and trial.finished, "")
		await _barrier("review_read_" + label)
		var previous := trial.get_instance_id()
		if _role == "host":
			retry.pressed.emit()
		var reset := await _wait_until(func():
			var current := get_tree().current_scene
			return current is Trial and current.get_instance_id() != previous, 4.0)
		if not _require(label + "_host_retry_reloads_both", reset):
			return
		trial = get_tree().current_scene as Trial
		_main = trial
		if not _require(label + "_pilots_ready_after_retry", await _wait_until(_cond_both_players, 5.0)):
			return
		trial._rpc_route_result(settled_round, "被击落", 99, Trial.Leg.BOSS, {"hunter": true, "reward_used": true, "flank_hits": 99})
		_check(label + "_remix_retry_rejects_old_round_review", trial.remix and not trial.finished and trial.interruptions == 0
			and trial._route_review.is_empty() and not trial._result.visible and trial.leg == Trial.Leg.INTERCEPT
			and trial._route_hint_left == 0.0, "")
	_check("all_reviews_leave_ordinary_leaderboard_unchanged", Leaderboard.get_entries() == scores, "")
	await _barrier("all_reviews_checked")
	await _wait_seconds(.22)

func _review_intercept_shots(trial: Trial, count: int) -> void:
	for index in count:
		var role := "review-emitter-%d" % index
		trial._add_fighter(role, 1, Vector2(.27 + index * .22, .39), 90, 1)
		var order: Dictionary = trial._fighters[role]
		var ship: Node2D = order.ship
		order.origin = order.target
		ship.position = order.target
		trial._player._combat._spawn_bullet(ship.global_position + Vector2(0, 50), -PI * .5, 4, true, 1, 760.0)
	_check("host_count_comes_from_bullet_collisions_%d" % count, await _wait_until(func(): return trial.interruptions == count, .8),
		"actual=%d" % trial.interruptions)

func _review_flank_shot(trial: Trial) -> void:
	if not _require("review_boss_present", await _wait_until(func(): return is_instance_valid(trial._boss), 2.0)):
		return
	var boss := trial._boss
	await _arrange("review_flank")
	if _role == "host":
		boss._stop_entry_motion()
		boss.global_position = AT
		boss._shoot_timer = 60.0
		boss._try_coop_pulse()
	var open := await _wait_until(boss.has_flank_window, 1.7)
	_check("review_flank_opened_by_real_pulse", open, "")
	if _role == "host" and open:
		var aim: Vector2 = AT + boss._flank_side * 24.0 + Vector2(0, 22)
		trial._player._combat._spawn_bullet(aim + Vector2(0, 58), -PI * .5, 4, true, 1, 760.0)
	_check("review_counts_actual_flank_shot_once", await _wait_until(func():
		return not trial._flank_sparks.is_empty() and (_role == "client" or trial._flank_hits == 1), .6), "")
	await _barrier("review_flank_observed")

func _review_recovery(trial: Trial, expected: String) -> void:
	var wire: int = NetworkManager.recovery.guest_wire
	await _barrier("review_result_before_recovery")
	if _role == "client":
		NetworkManager.recovery.set_background(true)
		await _wait_seconds(.2)
		# Drop only the displayed replica to exercise the terminal snapshot path.
		trial.finished = false
		trial._route_review.clear()
		trial._result.hide()
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var restored := await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != wire
			and NetworkManager.recovery.deadline == 0 and trial.finished), 13.0)
	_check("real_recovery_restores_same_terminal_review", restored and trial._result.text == expected, trial._result.text)
	await _barrier("review_result_restored")

func _hint_fits(trial: Trial) -> bool:
	var hud := trial._hud
	var hint: Rect2 = hud._phase_label.get_global_rect()
	if not trial.get_viewport().get_visible_rect().encloses(hint) or hud._phase_label.get_minimum_size().x > hint.size.x:
		return false
	var reserved: Array[Control] = [hud._score_label, hud._player_scores_label, hud._draft_panel,
		hud._alert_label, hud._boss_status_root, trial._options]
	for slot: Dictionary in hud._skill_slots:
		reserved.append(slot.button)
	for control: Control in reserved:
		if is_instance_valid(control) and control.is_visible_in_tree() and hint.intersects(control.get_global_rect()):
			_log("hint rect %s intersects %s %s" % [hint, control.name, control.get_global_rect()])
			return false
	return true

func _verify_exposure(boss: Node, expected: float, trial: Trial) -> void:
	if _role == "host":
		boss._shoot_timer = 60.0
		boss.take_damage(boss.get_max_shield_hp(), 1)
	var exposed := await _wait_until(func(): return not boss.has_impact_shield(), 2)
	var start := Engine.get_physics_frames()
	var noticed := await _wait_until(func(): return trial._route_notice == Trial.HUNTER_NOTICE.spent, .2)
	_check("reward_cue_matches_actual_exposure", noticed == (expected == 5.5), trial._route_notice)
	var recharged := await _wait_until(func(): return boss.has_impact_shield(), 6.5)
	var frames := Engine.get_physics_frames() - start
	_check("first_exposure_matches_hunter_outcome_on_both_ends",
		exposed and recharged and absf(frames - expected * 60.0) <= 5.0, "frames=%d expected=%.1fs" % [frames, expected])

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
		trial._clear_non_boss_entities()
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
		trial.trial_tick = Trial.ELITE_LEG - 1
		await get_tree().physics_frame
		await get_tree().physics_frame
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

func _finish_hunter_with_shot(trial: Trial, killer: int) -> void:
	var target := Vector2(640, 320)
	if _role == "host":
		var hunter: Elite = trial._elite
		hunter.set_physics_process(false)
		hunter.global_position = target
		if hunter.get_network_shield() > 0:
			hunter.take_damage(int(hunter.get_network_shield()), 1)
		hunter.take_damage(floori((hunter.get_network_health() - 1.0) / 1.25), 1)
	await _barrier("hunter_final_shot_ready")
	if NetworkManager.local_player_id() == killer:
		trial._player._combat._spawn_bullet(target + Vector2(0, 58), -PI * .5, 7, true, 1, 700.0)
	_check("hunter_final_shot_confirms_reward_on_both_ends", await _wait_until(func():
		return not is_instance_valid(trial._elite) and trial._route_notice == Trial.HUNTER_NOTICE.earned, 2.0),
		"killer_slot=%d notice=%s" % [killer, trial._route_notice])
