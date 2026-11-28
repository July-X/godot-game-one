extends "res://tests/player_growth_probe.gd"
## Real title/lobby entry. The driver only aims, moves and chooses cards.

const ELITE := "res://scenes/entities/elite.tscn"
const Boss := preload("res://scripts/battle/enemies/boss/boss.gd")
var _patrol := false
var _choose := false
var _seed := SEED
var _first_request := -1
var _entry := -1
var _elite_wait := 0
var _elite_deaths := 0
var _offers := {}
var _choices := {}
var _enemy_shots := 0
var _player_shots := 0
var _shots_by_slot := {}
var _contacts_by_slot := {}
var _interrupted_previews := 0
var _hull_loss_before_entry := {}
var _enemy_peak := 0
var _health_min := {}
var _health_last := {}
var _hull_loss := {}
var _motion_origins := {}
var _motion_max := {}
var _empty_ticks := 0
var _longest_empty := 0
var _empty_run := 0
var _dodges := 0
var _warning := -1
var _warning_outline_seen := false
var _approach_cues := 0
var _entry_elite := false
var _requests := 0
var _first_damage := -1
var _correct_first_offer := false

func _measure(battle: Node, authority: bool) -> void:
	_battle = battle
	SFX.priority_cue.connect(_observe_approach_cue)
	if OS.get_cmdline_user_args().has("rules"):
		await _exercise_schedule()
		return
	_authority = authority
	_patrol = OS.get_cmdline_user_args().has("patrol")
	_choose = OS.get_cmdline_user_args().has("choose")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			_seed = int(arg.get_slice("=", 1))
	seed(_seed)
	battle._wave_director._rng.seed = _seed
	UpgradeDraft._rng.seed = _seed
	_start_tick = Engine.get_physics_frames()
	get_tree().node_added.connect(_observe)
	UpgradeDraft.draft_opened.connect(_observe_draft)
	UpgradeDraft.card_chosen.connect(_chosen)
	GameState.boss_spawn_requested.connect(_requested)
	if GameState.has_signal("cannon_calibrated"):
		GameState.connect("cannon_calibrated", _observe_calibration)
	_event("start", {"seed": _seed, "patrol": _patrol, "choose": _choose, "host": authority})
	if authority:
		var hit := await _wait_until(func(): return _boss_hit or not GameState.game_running, 145)
		_check("real_first_hull_damage", hit and _boss_hit)
		_check("one_request_and_no_elite_at_entry", _requests == 1 and not _entry_elite)
		_check("real_local_route", not _patrol or float(_motion_max.get(1, 0)) > 80)
		if NetworkManager.is_online():
			_check("real_guest_route", not _patrol or float(_motion_max.get(_guest_slot(), 0)) > 80)
			_check("both_slots_have_authoritative_projectile_contacts",
				int(_contacts_by_slot.get(1, 0)) > 0 and int(_contacts_by_slot.get(_guest_slot(), 0)) > 0)
	else:
		_check("guest_sees_first_boss", await _wait_until(func(): return _entry >= 0 or not GameState.game_running, 143)
			and _entry >= 0)
		await _wait_until(func(): return not NetworkManager.is_online() or not GameState.game_running, 52)
	if _candidate:
		_check("visible_warning_before_boss_entry", _warning >= 0 and _warning < _entry)
		_check("approach_outline_and_one_local_cue", _warning_outline_seen and _approach_cues == 1)
		if authority:
			_check("first_offer_at_ten_actual_kills_and_one_calibration", _correct_first_offer and _calibrations == 1)
	_event("end", {"request": _first_request, "entry": _entry, "hull_hit": _first_damage,
		"warning": _warning, "elite_wait": _elite_wait, "kills": GameState.total_kills, "unique": _unique_count(),
		"calibrations": _calibrations, "offers": _offers, "choices": _choices, "enemy_shots": _enemy_shots,
		"player_shots": _player_shots, "enemy_peak": _enemy_peak, "hull_loss": _hull_loss, "min_hull": _health_min,
		"travel": _motion_max, "idle_ticks": _empty_ticks, "longest_idle": _longest_empty, "dodges": _dodges,
		"shots_by_slot": _shots_by_slot, "contacts_by_slot": _contacts_by_slot,
		"interrupted_previews": _interrupted_previews, "preboss_hull_loss": _hull_loss_before_entry})
	_summary = true

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_battle) or _summary or not GameState.game_running:
		return
	var pilot: Node2D = _battle._player
	if is_instance_valid(pilot):
		_drive(pilot)
	_select_local_card()
	_observe_hud()
	if not _authority:
		return
	if not _patrol:
		_sample_opening()
	_sample_combat()
	for boss: Node in get_tree().get_nodes_in_group("boss"):
		if not _boss_hit and boss.has_meta("pace_initial_hull") and boss.get_network_health() < boss.get_meta("pace_initial_hull"):
			_first_damage = _tick()
			_boss_hit = true
			_event("boss_hull_hit", {"hp": boss.get_network_health(), "kills": GameState.total_kills})

func _drive(pilot: Node2D) -> void:
	if _patrol:
		var phase := _tick() % 220
		var slot: int = pilot.peer_id
		if not _motion_origins.has(slot):
			_motion_origins[slot] = pilot.global_position
		var origin: Vector2 = _motion_origins[slot]
		var direction := 1.0 if _tick() / 220 % 2 == 0 else -1.0
		if slot != 1:
			direction *= -1.0
		var offset := Vector2(direction * 178, -54 if slot == 1 else 48)
		var target := NetworkManager.battle_size(_battle) * Vector2(0.5, 0.68) if not NetworkManager.is_online() else origin
		target += offset
		pilot._motion.mobile_mode = true
		if _evade_locked_beam(pilot):
			return
		pilot._motion.touch_move = (target - pilot.global_position).limit_length(48.0) / 48.0 if phase < 65 else Vector2.ZERO
		if phase < 65:
			return
	var target: Node2D
	var best := INF
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		var distance := pilot.global_position.distance_squared_to(enemy.global_position)
		if not enemy.is_queued_for_deletion() and distance < best:
			target = enemy
			best = distance
	if target:
		pilot.rotation = pilot.global_position.angle_to_point(target.global_position) + PI / 2

func _evade_locked_beam(pilot: Node2D) -> bool:
	var boss = _battle._boss
	if not is_instance_valid(boss) or boss.get_attack_window() < 2 or boss._laser_locked_direction.is_zero_approx():
		return false
	var normal: Vector2 = boss._laser_locked_direction.orthogonal()
	var distance: float = (pilot.global_position - boss.global_position).dot(normal)
	if absf(distance) >= 98.0:
		return false
	var direction := normal if distance >= 0.0 else -normal
	pilot._motion.touch_move = direction
	if pilot.can_dash() and pilot.velocity.dot(direction) > 36.0 and absf(distance) < 65.0:
		pilot.request_action("dash")
		_dodges += 1
		_event("dash_away_from_locked_beam", {"slot": pilot.peer_id, "distance": distance})
	return true

func _select_local_card() -> void:
	if not _choose:
		return
	var pid := NetworkManager.local_player_id()
	if not UpgradeDraft.has_draft(pid):
		return
	var draft := UpgradeDraft.get_draft(pid)
	if float(draft.left) <= UpgradeDraft.DRAFT_TIMEOUT_SECONDS - 0.75:
		var key := InputEventKey.new()
		key.keycode = KEY_1 if not _choices.has(pid) else KEY_2
		key.pressed = true
		get_viewport().push_input(key)

func _sample_combat() -> void:
	if _first_request >= 0 and _entry < 0 and _elite_active():
		_elite_wait += 1
	var enemy_peak := get_tree().get_node_count_in_group("enemy_bullets")
	if _entry < 0:
		_enemy_peak = maxi(_enemy_peak, enemy_peak)
		if _offers.has(1):
			var targetable := false
			for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
				if get_viewport().get_visible_rect().has_point(enemy.global_position):
					targetable = true
					break
			_empty_run = 0 if targetable or enemy_peak > 0 else _empty_run + 1
			_empty_ticks += int(_empty_run > 0)
			_longest_empty = maxi(_longest_empty, _empty_run)
	for slot: int in ([1, _guest_slot()] if _guest_slot() > 1 else [1]):
		var pilot: Node2D = _battle._players.get(slot, _battle._player if slot == 1 else null)
		if is_instance_valid(pilot):
			if not _motion_origins.has(slot):
				_motion_origins[slot] = pilot.global_position
			_motion_max[slot] = maxf(float(_motion_max.get(slot, 0.0)), pilot.global_position.distance_to(_motion_origins[slot]))
		var hp := GameState.get_current_health(slot)
		_health_min[slot] = mini(int(_health_min.get(slot, 50)), hp)
		_hull_loss[slot] = int(_hull_loss.get(slot, 0)) + maxi(int(_health_last.get(slot, 50)) - hp, 0)
		_health_last[slot] = hp

func _elite_active() -> bool:
	return is_instance_valid(_battle._elite) and not _battle._elite.is_queued_for_deletion()

func _observe_hud() -> void:
	var frame := _battle._hud.get_node_or_null("BossWarningFrame") as Panel
	if frame and frame.modulate.a > 0.05:
		_warning_outline_seen = true
	var alert: Label = _battle._hud._alert_label
	if (_warning < 0 and is_instance_valid(alert) and alert.visible and alert.modulate.a > 0.1
			and ("母舰展开" in alert.text or "首领接近" in alert.text)):
		_warning = _tick()
		_event("boss_warning_visible", {"text": alert.text, "safe": _battle._hud._safe_rect.encloses(alert.get_rect())})

func _observe_approach_cue(duration: float) -> void:
	var cue := SFX.get("_stream_boss_approach") as AudioStreamWAV
	if cue and SFX._warning_voice.stream == cue and is_equal_approx(duration, cue.get_length()):
		_approach_cues += 1

func _requested(level: int) -> void:
	if not _authority:
		return
	_requests += 1
	if _first_request < 0:
		_first_request = _tick()
		_event("boss_requested", {"level": level, "pilot_level": GameState.level, "kills": GameState.total_kills,
			"elite_blocks": _elite_active(), "unique_before_death_signal": _unique_count()})

func _observe(node: Node) -> void:
	var path := node.scene_file_path
	if path == BOSS and _entry < 0:
		_entry = _tick()
		_entry_elite = _elite_active()
		if _authority:
			_hull_loss_before_entry = _hull_loss.duplicate()
			for enemy in get_tree().get_nodes_in_group("ordinary_enemies"):
				if enemy.is_queued_for_deletion() and int(enemy.get("attack_phase")) in [1, 2]:
					_interrupted_previews += 1
		node.set_meta("pace_initial_hull", node.get_network_health())
		_event("boss_entry", {"hp": node.get_network_health(), "elite_blocks": _entry_elite,
			"kills": GameState.total_kills, "enemy_shots": _enemy_shots, "player_shots": _player_shots})
	elif _authority and path == ELITE:
		_event("elite_entry", {"kills": GameState.total_kills})
		node.elite_died.connect(func():
			_elite_deaths += 1
			_event("elite_death", {"kills": GameState.total_kills}))
	elif _authority and path == ENEMY:
		super(node)
	elif _authority and node is Bullet:
		_count_shot.call_deferred(node)

func _count_shot(bullet: Bullet) -> void:
	if _entry >= 0 or not is_instance_valid(bullet) or bullet._is_network_ghost:
		return
	if bullet._is_player_bullet:
		_player_shots += 1
		var slot := bullet.owner_peer_id
		_shots_by_slot[slot] = int(_shots_by_slot.get(slot, 0)) + 1
		bullet.body_entered.connect(func(body):
			if body.is_in_group("enemies"):
				_contacts_by_slot[slot] = int(_contacts_by_slot.get(slot, 0)) + 1)
	else:
		_enemy_shots += 1

func _observe_death(id: int, wave: int) -> void:
	var seen := _enemy_deaths.has(id)
	super(id, wave)
	if not seen:
		_event("unique_death", {"kills": GameState.total_kills, "unique": _unique_count()})
		if _unique_count() == 72:
			_event("kill_72_exposure", {"enemy_shots": _enemy_shots, "enemy_peak": _enemy_peak,
				"hull_loss": _hull_loss.duplicate()})

func _unique_count() -> int:
	return _enemy_deaths.size() + _elite_deaths

func _observe_draft(pid: int, cards: Array) -> void:
	if not _offers.has(pid):
		_offers[pid] = _tick()
		if _authority and pid == 1:
			_correct_first_offer = GameState.total_kills == 10 and _unique_count() == 9
		_event("first_draft", {"slot": pid, "kills": GameState.total_kills, "cards": cards,
			"unique_before_death_signal": _unique_count()})

func _chosen(pid: int, card: String, _index: int) -> void:
	if not _choices.has(pid):
		_choices[pid] = _tick()
		_event("first_choice", {"slot": pid, "card": card, "source": UpgradeDraft.get_draft(pid).source})

func _exercise_schedule() -> void:
	var shot := ""
	var wide := OS.get_cmdline_user_args().has("wide")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("screenshot="):
			shot = arg.trim_prefix("screenshot=")
	var size := Vector2i(1600 if wide else 960, 720)
	get_window().content_scale_size = size
	await get_tree().process_frame
	await get_tree().process_frame
	_battle._spawn_mobile_controls()
	_battle._player.set_physics_process(false)
	var safe := Rect2(Vector2(74 if wide else 24, 24), Vector2(size) - Vector2(104 if wide else 44, 48))
	_battle._hud._layout_in_safe_area(safe)
	_battle.get_node("MobileControls")._layout_in_safe_area(safe)
	_battle._wave_director._cooldown = INF
	_battle._asteroid_timer = INF
	var steps: Array[Vector2i] = []
	var offers: Array[int] = []
	var calibration := [0]
	GameState.boss_spawn_requested.connect(func(level): steps.append(Vector2i(GameState.total_kills, level)))
	UpgradeDraft.draft_opened.connect(func(_pid, _cards): offers.append(GameState.total_kills))
	GameState.connect("cannon_calibrated", func(): calibration[0] += 1)
	GameState.elite_spawn_requested.disconnect(_battle._on_elite_spawn_requested)
	for i in 71:
		GameState.add_kill(1)
	_battle._spawn_elite()
	GameState.elite_spawn_requested.connect(_battle._on_elite_spawn_requested)
	_check("growth_and_first_card_keep_kill_thresholds", calibration[0] == 1 and offers[0] == 10)
	_check("no_request_before_72", steps.is_empty())
	GameState.add_kill(1)
	_check("request_waits_behind_live_elite", steps == [Vector2i(72, 5)] and GameState.level == 4
		and _battle._pending_boss_level == 5 and _elite_active() and not GameState.get("first_boss_warning_active"))
	while GameState.level < 5:
		GameState.add_kill(1)
	_check("level_five_keeps_upgrade_without_another_boss", offers.back() == 85 and steps.size() == 1
		and _elite_active() and not is_instance_valid(_battle._boss))
	_battle._elite._die(1)
	await get_tree().create_timer(.35).timeout
	var hud = _battle._hud
	hud._update_platform_hints()
	hud._layout_in_safe_area(safe)
	_battle.get_node("MobileControls")._layout_in_safe_area(safe)
	var alert: Label = hud._alert_label
	var clear: bool = is_instance_valid(alert) and alert.visible and alert.text == "首领接近"
	if clear:
		var box := alert.get_global_rect()
		clear = safe.encloses(box) and not box.intersects(hud._skill_bar.get_global_rect())
		clear = clear and (not hud._draft_panel.visible or not box.intersects(hud._draft_panel.get_global_rect()))
		for score: Label in hud._score_rows:
			clear = clear and not box.intersects(score.get_global_rect())
	_check("warning_uses_safe_top_row_without_overlap", clear)
	var frame := hud.get_node_or_null("BossWarningFrame") as Panel
	var outline := frame.get_theme_stylebox("panel") as StyleBoxFlat if frame else null
	_check("warning_outline_is_visible_clear_and_ignores_touches", frame != null and frame.modulate.a > 0.05
		and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE and outline != null and not outline.draw_center)
	GameState.set_first_boss_warning(true)
	_check("approach_cue_is_distinct_and_plays_once", _approach_cues == 1
		and SFX._warning_voice.stream == SFX.get("_stream_boss_approach")
		and SFX._warning_voice.stream != SFX.get("_stream_boss_warning"))
	if not shot.is_empty():
		RenderingServer.force_draw(false)
		_check("warning_screenshot", get_viewport().get_texture().get_image().save_png(shot) == OK)
	_battle._on_wave_phase_changed(2, "浪峰")
	_check("wave_phase_does_not_replace_active_warning", alert.text == "首领接近")
	GameState.elite_spawn_requested.emit()
	await get_tree().process_frame
	_check("warning_does_not_insert_another_elite", not _elite_active())
	get_tree().paused = true
	await get_tree().create_timer(2.15).timeout
	_check("warning_timer_respects_battle_freeze", GameState.get("first_boss_warning_active")
		and not is_instance_valid(_battle._boss))
	get_tree().paused = false
	# 图形录制可能慢于实时，入场倒计时仍用游戏时钟。
	await get_tree().create_timer(1.85).timeout
	_check("one_boss_enters_after_warning", is_instance_valid(_battle._boss)
		and not _elite_active() and not GameState.get("first_boss_warning_active"))
	_check("warning_outline_clears_before_entry", not is_instance_valid(frame))
	GameState.elite_spawn_requested.disconnect(_battle._on_elite_spawn_requested)
	while GameState.level < 10:
		GameState.add_kill(1)
	_check("next_boss_remains_level_ten", steps == [Vector2i(72, 5), Vector2i(310, 10)])
	var first: Boss = _battle._boss
	first.set_physics_process(false)
	first.take_damage(first.get_shield_hp())
	await get_tree().create_timer(0.80).timeout
	_check("solo_first_boss_uses_core_phase_without_caption_or_coop_marker", hud._boss_status_phase.text.is_empty()
		and not hud._boss_attack_label.is_visible_in_tree() and first.is_shield_exposed()
		and first.uses_first_boss_cues() and not first.first_boss_lock_visible())
	first._tick_shield_cycle(Boss.BOSS_EXPOSURE_SECONDS - Boss.BOSS_RECHARGE_WARNING + 0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("solo_recharge_keeps_shield_bar_empty_without_caption", hud._boss_status_phase.text.is_empty()
		and first.is_shield_recharging() and hud._boss_shield_fill.size.x == 0.0)
	first.die()
	await get_tree().process_frame
	_battle._spawn_boss(10)
	await _check_legacy_boss_hud(_battle, "later_ordinary_boss")
	get_tree().change_scene_to_file("res://scenes/first_card_trial.tscn")
	await get_tree().scene_changed
	var trial := get_tree().current_scene
	trial._spawn_boss(5)
	await _check_legacy_boss_hud(trial, "fixed_trial_boss_at_same_level")

func _check_legacy_boss_hud(battle: Node, label: String) -> void:
	var boss: Boss = battle._boss
	boss.set_physics_process(false)
	boss._start_ultimate_laser()
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = battle._hud
	_check(label + "_keeps_combined_laser_status", hud._boss_status_phase.text.ends_with(" · 激光蓄力")
		and not hud._boss_attack_label.is_visible_in_tree() and not boss.uses_first_boss_cues())
	boss.take_damage(boss.get_shield_hp())
	await get_tree().create_timer(0.80).timeout
	_check(label + "_keeps_legacy_exposure_status", hud._boss_status_phase.text == "可攻击")
