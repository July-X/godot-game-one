extends Node

const Scene := preload("res://scenes/opening_trial.tscn")
const Rift := preload("res://scripts/rift_route_trial.gd")
const RiftScene := preload("res://scenes/rift_route_trial.tscn")
const Opening := preload("res://scripts/opening_trial.gd")
const Mobile := preload("res://scenes/ui/mobile_controls.tscn")
const Bullet := preload("res://scripts/bullet.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Elite := preload("res://scripts/elite.gd")
const CloseTrial := preload("res://scripts/elite_close_trial.gd")
const SafeArea := preload("res://scripts/battle_safe_area.gd")
const Title := "res://scenes/ui/title_screen.tscn"
const OpeningChoices := "res://scenes/ui/opening_trial_choices.tscn"
const Solo := "res://scenes/main.tscn"
const SEED := 90220

var trial: Opening
var stick: Node
var origin := Vector2.ZERO
var births: Array = []
var deaths: Dictionary = {}
var fans: Dictionary = {}
var charges: Dictionary = {}
var interruptions: Array = []
var hits: Dictionary = {}
var health_loss: Array = []
var enemy_contacts: Array = []
var elite_hits: Array = []
var elite_spawn_count := 0
var elite_alive_at_end := false
var nearest_elite := INF
var path := PackedVector2Array()
var _shot_serial := 0
var _body_alive := 50
var _shield_alive := 0
var _chosen_at := -1
var _choice := ""
var _chosen_card := ""
var _push_finale := false
var _capture_dir := ""
var _capture_from := Opening.FINALE_TICK + 130
var _capture_to := Opening.FINALE_TICK + 310
var _last_capture := -1
var _captured := 0
var _fail := 0
var _rift_build := false
var _draft_at := Opening.DRAFT_TICK
var _build_at := int(Opening.BUILD_STARTS[0])

func _ready() -> void:
	process_priority = 100
	_run.call_deferred()

func _process(_delta: float) -> void:
	if is_instance_valid(trial):
		# 定格由墙钟结束。固定航线对照只去掉定格，保留实际伤害与运动。
		trial._hitstop_left = 0.0
		Engine.time_scale = 1.0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if "--wide" in args else 1280, 720)
	seed(SEED)
	if "--entry" in args:
		await _check_title()
		_report()
		return
	var card := args[0] if args.size() > 0 else "pierce"
	var route := args[1] if args.size() > 1 else "column"
	_push_finale = "--press-finale" in args
	_rift_build = "--rift-build" in args
	if _rift_build:
		_draft_at = Rift.CARD_TICK
		_build_at = Rift.CARD_TICK + 90
	trial = RiftScene.instantiate() if _rift_build else Scene.instantiate()
	stick = Mobile.instantiate()
	trial.add_child(stick)
	get_tree().root.add_child(trial)
	get_tree().current_scene = trial
	origin = Vector2(156, trial.field.y - 171)
	trial.child_entered_tree.connect(_observe_node)
	trial.volley_interrupted.connect(_record_interruption)
	UpgradeDraft.card_chosen.connect(_record_choice)
	GameState.health_changed.connect(_record_health)
	GameState.shield_changed.connect(_record_shield)
	_touch(origin, true)
	var finish := Opening.END_TICK
	if "--intro" in args:
		finish = 408
		_capture_from = 132
		_capture_to = 332
	elif "--first-build" in args or _rift_build:
		finish = _build_at + 360
		_capture_from = _build_at + 65
		_capture_to = _build_at + 288
	elif "--finale-clip" in args:
		finish = Opening.FINALE_TICK + 380
	for arg in args:
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	if not _capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_capture_frame)
	var deadline := Engine.get_physics_frames() + finish - trial.trial_tick + 720
	var waited := 0
	while trial.trial_tick < finish and not trial.finished and Engine.get_physics_frames() < deadline:
		await get_tree().physics_frame
		if not is_instance_valid(trial._player):
			break
		if UpgradeDraft.has_draft(1):
			waited += 1
			if waited == 2:
				_check("centered_three_cards", _centered_cards())
				_touch(origin, false)
				_touch(origin, true)
			if waited == 5 and "--timeout" not in args:
				var button: Button = trial._hud._draft_card_buttons[Opening.OFFER.find(card)]
				_touch(button.get_global_rect().get_center(), true, 1)
				_touch(button.get_global_rect().get_center(), false, 1)
				_check("second_finger_selects_and_keeps_move", stick._move_touch_id == 0
					and GameState.get_card_stacks(1) == {card: 1})
		_steer(route)
		_sample_charge()
		if is_instance_valid(trial._elite) and trial.trial_tick <= Opening.FINALE_TICK + 310:
			nearest_elite = minf(nearest_elite, trial._player.global_position.distance_to(trial._elite.global_position))
		if trial.trial_tick == Opening.END_TICK - 1:
			elite_alive_at_end = is_instance_valid(trial._elite) and trial._elite.get_network_health() > 0
		if waited == 0 or _chosen_at >= 0:
			path.append(trial._player.position.snapped(Vector2.ONE * .01))
	_check("reached_requested_frame", trial.trial_tick == finish and trial.finished == (finish == Opening.END_TICK))
	_check("no_normal_spawns_or_levels", not is_instance_valid(trial._boss) and GameState.level == 1)
	_check("all_fans_have_visible_warning_and_three_real_bullets", _check_fans())
	_check("only_pending_volley_interrupted", _check_interruptions())
	if finish > _draft_at:
		var timeout := "--timeout" in args
		_check("actual_upgrade_source", _choice == ("timeout" if timeout else "tap")
			and _chosen_card == (Opening.OFFER[0] if timeout else card))
	if finish > Opening.ELITE_TICK:
		_check("one_real_elite", elite_spawn_count == 1 and GameState.elite_encounter_count == 1)
	if finish == Opening.END_TICK:
		await get_tree().process_frame
		_check("clears_entities_and_joystick_at_result", trial._result.visible and stick._move_touch_id == -1
			and not UpgradeDraft.has_draft(1) and get_tree().get_nodes_in_group("enemies").is_empty()
			and get_tree().get_nodes_in_group("enemy_bullets").is_empty()
			and get_tree().get_nodes_in_group("player_bullets").is_empty())
	if not _capture_dir.is_empty():
		_check("all_capture_frames_saved", _captured == _capture_to - _capture_from + 1)
	print("[OPENING_DATA] ", JSON.stringify({
		"seed": SEED, "view": str(trial.field), "card": card, "route": route,
		"births": births, "fans": fans, "charges": charges, "hits": hits, "deaths": deaths,
		"interruptions": interruptions, "losses": health_loss, "enemy_contacts": enemy_contacts, "choice": _choice,
		"elite_spawn_count": elite_spawn_count, "elite_hits": elite_hits, "elite_alive_at_end": elite_alive_at_end,
		"nearest_elite": nearest_elite if is_finite(nearest_elite) else -1,
		"press_finale": _push_finale,
		"position_hash": var_to_bytes(path).hex_encode().sha256_text(), "samples": path.size(),
		"end": trial.trial_tick,
	}))
	get_tree().current_scene = null
	trial.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_report()

func _report() -> void:
	print("[OPENING] SUMMARY failed=", _fail)
	get_tree().quit(int(_fail != 0))

func _check_title() -> void:
	get_tree().node_added.connect(func(node: Node):
		if (node is Opening or node.scene_file_path == Solo) and not (OS.has_feature("android") or OS.has_feature("ios")):
			node._spawn_mobile_controls())
	get_tree().current_scene = null
	get_tree().change_scene_to_file(Title)
	await get_tree().scene_changed
	await get_tree().process_frame
	var title := get_tree().current_scene
	var menu := title.get_node("Menu") as Control
	var choices := title.get_node("OpeningChoices") as Control
	_check("title_fits_safety_margin", SafeArea.for_viewport(get_viewport()).encloses(menu.get_global_rect())
		and menu.is_visible_in_tree() and not choices.is_visible_in_tree())
	await _tap_button(menu.get_node("BtnOpeningTrial"))
	_check("opens_secondary_choices", get_tree().current_scene == title and not menu.is_visible_in_tree()
		and choices.is_visible_in_tree() and choices.get_node("Start").text == "开始 90 秒试飞"
		and choices.get_node("A").text == "近身试飞 A" and choices.get_node("B").text == "近身试飞 B")
	await _check_choice_insets(title, choices)
	await _tap_button(choices.get_node("Back"))
	_check("chooser_back_restores_title", get_tree().current_scene == title and menu.is_visible_in_tree()
		and not choices.is_visible_in_tree())
	await _tap_button(menu.get_node("BtnOpeningTrial"))
	for variant in ["B", "A"]:
		if not await _check_close_choice(choices, variant):
			return
		choices = get_tree().current_scene.get_node("OpeningChoices")
	await _tap_button(choices.get_node("Start"))
	trial = get_tree().current_scene as Opening
	_check("opens_trial_with_base_fire_and_mobile_controls", is_instance_valid(trial)
		and trial.scene_file_path == Scene.resource_path
		and not UpgradeDraft.has_draft(1) and GameState.get_card_stacks(1).is_empty() and trial._player._motion.mobile_mode)
	if not is_instance_valid(trial):
		return
	var previous := trial.get_instance_id()
	trial.trial_tick = Opening.DRAFT_TICK - 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("draft_can_open_in_trial", UpgradeDraft.has_draft(1))
	await _tap_button(trial.get_node("TrialUI/Options/Buttons/Retry"))
	trial = get_tree().current_scene as Opening
	_check("retry_clears_previous_trial", is_instance_valid(trial) and trial.get_instance_id() != previous
		and trial.trial_tick < 12 and not UpgradeDraft.has_draft(1) and GameState.get_card_stacks(1).is_empty())
	if not is_instance_valid(trial):
		return
	await _tap_button(trial.get_node("TrialUI/Options/Buttons/Back"))
	title = get_tree().current_scene
	var at_title := is_instance_valid(title) and title.scene_file_path == Title
	_check("returns_to_title", at_title and title.get_node("Menu").is_visible_in_tree())
	if not at_title:
		return
	await _tap_button(title.get_node("Menu/BtnSingle"))
	var solo := get_tree().current_scene
	_check("opens_normal_solo", is_instance_valid(solo) and solo.scene_file_path == Solo
		and not NetworkManager.is_online() and not UpgradeDraft.has_draft(1)
		and GameState.get_card_stacks(1).is_empty() and solo._player._motion.mobile_mode)

func _check_choice_insets(title: Node, choices: Control) -> void:
	var viewport := get_viewport()
	var view := viewport.get_visible_rect()
	var safe := view.grow_individual(-132, -28, -36, -78)
	var display_rect := viewport.get_screen_transform() * safe
	title._layout_in_safe_area(SafeArea.from_display(viewport, display_rect))
	await get_tree().process_frame
	var usable := safe.grow(-SafeArea.MENU_MARGIN)
	var last_bottom := usable.position.y
	var fits := absf(choices.get_global_rect().get_center().x - usable.get_center().x) <= 1.0
	for control: Control in choices.get_children():
		var rect := control.get_global_rect()
		fits = fits and usable.encloses(rect) and rect.position.y >= last_bottom
		if control is Button:
			fits = fits and rect.size.y >= 48.0
		last_bottom = rect.end.y
	_check("chooser_fits_asymmetric_safe_area", fits)
	print("[OPENING] entry viewport=", view.size, " safe_area=", safe)

func _check_close_choice(choices: Control, variant: String) -> bool:
	await _tap_button(choices.get_node(variant))
	var close_trial := get_tree().current_scene as CloseTrial
	var scene_path := "res://scenes/elite_close_trial_%s.tscn" % variant.to_lower()
	var entered := is_instance_valid(close_trial) and close_trial.scene_file_path == scene_path
	_check(variant + "_touch_enters_close_trial", entered and close_trial.variant_b == (variant == "B")
		and close_trial.trial_tick < CloseTrial.START_TICK + 12 and close_trial._player._motion.mobile_mode
		and GameState.get_card_stacks(1) == {CloseTrial.TRIAL_CARD: 1})
	if not entered:
		return false
	var previous := close_trial.get_instance_id()
	for i in 14:
		await get_tree().physics_frame
	await _tap_button(close_trial.get_node("TrialUI/Options/Buttons/Retry"))
	close_trial = get_tree().current_scene as CloseTrial
	var retried := is_instance_valid(close_trial) and close_trial.get_instance_id() != previous
	_check(variant + "_retry_keeps_variant", retried and close_trial.scene_file_path == scene_path
		and close_trial.variant_b == (variant == "B") and close_trial.trial_tick < CloseTrial.START_TICK + 12
		and GameState.get_card_stacks(1) == {CloseTrial.TRIAL_CARD: 1})
	if not retried:
		return false
	await _tap_button(close_trial.get_node("TrialUI/Options/Buttons/Back"))
	var chooser := get_tree().current_scene
	var returned := is_instance_valid(chooser) and chooser.scene_file_path == OpeningChoices
	_check(variant + "_back_to_opening_choices", returned and chooser.get_node("OpeningChoices").is_visible_in_tree()
		and not chooser.get_node("Menu").is_visible_in_tree())
	return returned

func _tap_button(button: Button) -> void:
	var point := get_viewport().get_final_transform() * button.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await get_tree().process_frame

func _capture_frame() -> void:
	if not is_instance_valid(trial):
		return
	var tick := trial.trial_tick
	if tick < _capture_from or tick > _capture_to or tick == _last_capture:
		return
	_last_capture = tick
	var filename := _capture_dir.path_join("frame-%05d.jpg" % tick)
	if get_viewport().get_texture().get_image().save_jpg(filename, .96) == OK:
		_captured += 1

func _touch(at: Vector2, pressed: bool, index := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.index = index
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _steer(route: String) -> void:
	var now := trial.trial_tick
	var target := trial.field * Vector2(.5, .78)
	var final_age := now - Opening.FINALE_TICK
	if _push_finale and final_age >= -108 and final_age <= 302:
		var axis := 1.0 - Opening.CLUSTER_X + Opening.FINALE_SHIFT
		target.x = trial.field.x * axis - clampf((final_age - 202) * 3.2, 0, 38)
		target.y -= clampf((final_age - 148) * 1.73, 0, 235)
	elif final_age >= -108:
		var width := trial.field.x
		var sweep_step := 4.0 if route == "dodge" and width > 1280.0 else 3.45
		target.x = width * .11 + pingpong(width * .54 + maxi(final_age, 0) * sweep_step, width * .78)
		var returning := final_age < 0 or (_push_finale and final_age <= 435)
		target.y = trial.field.y * .82 if returning else trial._player.position.y
		if route == "dodge":
			target.y = maxf(target.y, trial.field.y * .78)
	elif now < 400:
		if route != "dodge" and now >= 80 and now < 290:
			target.x = trial.field.x * .28
			target.y -= clampf((now - 174) * 1.7, 0, 142)
		elif route == "dodge":
			target.x = trial.field.x * .54
			target.y -= clampf((now - 100) * 1.4, 0, 145)
	elif now < _draft_at:
		if now >= 850:
			target.x = trial.field.x * (.46 if now < 990 else .5)
			target.y = trial._player.position.y
	elif now >= _build_at:
		var age := now - _build_at
		target.x = trial.field.x * .67
		if age < (44 if route in ["cluster", "dodge"] else 30):
			target.x = trial.field.x * .5
		elif age <= 232 and route in ["column", "cluster", "wing"]:
			var x: float = {
				"column": Opening.COLUMN_X, "cluster": Opening.CLUSTER_X, "wing": Opening.WING_X,
			}[route]
			target.x = trial.field.x * x - (22 if route == "wing" else 0)
			var turn := 153 if route == "column" else 147
			if route in ["column", "wing"] and age >= turn:
				target.x = trial._player.position.x
			target.y -= clampf((age - turn) * 1.6, 0, 135)
		elif age > 232:
			target.y -= clampf((age - 260) * 1.6, 0, 145)
	else:
		target.y = trial._player.position.y
	var desired: Vector2 = ((target - trial._player.position) * 7).limit_length(trial._player.move_speed)
	if route == "dodge" and final_age >= 0:
		desired = _avoid_visible_bullets(desired)
	var drag := InputEventScreenDrag.new()
	drag.position = origin + desired / trial._player.move_speed * stick.joystick_radius
	get_viewport().push_input(drag, true)

func _avoid_visible_bullets(preferred: Vector2) -> Vector2:
	# 只在验证航迹里看屏内实弹。移动仍通过摇杆、惯性和正常碰撞。
	var at: Vector2 = trial._player.position
	var nearby: Array = []
	for bullet in get_tree().get_nodes_in_group("enemy_bullets"):
		if Rect2(Vector2.ZERO, trial.field).has_point(bullet.position) and bullet.position.distance_to(at) < 620:
			nearby.append(bullet)
	if nearby.is_empty() or _projected_clearance(preferred, nearby) >= 52.0:
		return preferred
	var best := preferred
	var best_score := -INF
	var speed: float = trial._player.move_speed
	for i in 12:
		var direction := Vector2.from_angle(i * TAU / 12.0)
		var proposal := direction * speed
		var score := minf(_projected_clearance(proposal, nearby), 82.0)
		score += direction.dot(preferred / speed) * 9.0 + direction.dot(trial._player.velocity / speed) * 3.0
		score -= maxf(0.0, trial.field.y * .76 - (at + proposal * .45).y) * .14
		if score > best_score:
			best_score = score
			best = proposal
	return best

func _projected_clearance(desired: Vector2, bullets: Array) -> float:
	var at: Vector2 = trial._player.position
	var inertia: Vector2 = trial._player.velocity - desired
	var nearest := INF
	for i in range(1, 13):
		var seconds := i * .05
		var pilot := at + desired * seconds + inertia * (.09 * (1.0 - exp(-seconds / .09)))
		pilot = pilot.clamp(Vector2.ONE * 24.0, trial.field - Vector2.ONE * 24.0)
		for bullet in bullets:
			var projectile: Vector2 = bullet.position + bullet._direction * bullet._speed * seconds
			nearest = minf(nearest, pilot.distance_squared_to(projectile))
	return sqrt(nearest)

func _centered_cards() -> bool:
	var panel: Control = trial._hud._draft_panel
	var safe := SafeArea.for_viewport(get_viewport())
	return panel.visible and safe.encloses(panel.get_global_rect()) and trial._hud._draft_card_buttons.size() == 3 \
		and absf(panel.get_global_rect().get_center().y - safe.get_center().y) < 2.0

func _observe_node(node: Node) -> void:
	if node is Enemy and node.get_parent() == trial:
		_observe_fighter.call_deferred(node.get_instance_id())
	elif node is Elite:
		elite_spawn_count += 1
	elif node is Bullet:
		_observe_bullet.call_deferred(node.get_instance_id(), trial.trial_tick)

func _observe_fighter(id: int) -> void:
	var fighter = instance_from_id(id)
	if not is_instance_valid(fighter):
		return
	var key := str(fighter.name)
	births.append([key, trial.trial_tick, fighter.enemy_type, fighter.health, fighter.position.x, fighter.position.y])
	fighter.enemy_died.connect(func(): deaths[key] = trial.trial_tick, CONNECT_ONE_SHOT)

func _observe_bullet(id: int, tick: int) -> void:
	var shot = instance_from_id(id)
	if not is_instance_valid(shot):
		return
	if shot.is_in_group("enemy_bullets"):
		var source := "other"
		for order: Dictionary in trial._fighters.values():
			var fighter = order.ship
			if int(order.fire) != tick or not is_instance_valid(fighter):
				continue
			if absf(shot.position.distance_to(fighter.position) - 20.0) < .08 and shot._speed == Enemy.SPEED_SLOW:
				source = str(fighter.name)
				var fan: Array = fans.get_or_add(source, [])
				fan.append([tick, shot.position.x, shot.position.y, shot._direction.x, shot._direction.y])
				break
		shot.body_entered.connect(func(body):
			if body == trial._player:
				enemy_contacts.append([trial.trial_tick, source]))
		return
	if not shot.is_in_group("player_bullets"):
		return
	_shot_serial += 1
	var serial := _shot_serial
	shot.body_entered.connect(func(target): _record_hit(shot, target, serial, tick))
	shot.card_effect.connect(func(card, target):
		if target is Enemy:
			_record_contact(target, serial, tick, card, shot._damage))

func _record_hit(shot, target: Node2D, serial: int, born: int) -> void:
	if target is Enemy and shot._pierced.has(target):
		_record_contact(target, serial, born, "direct", shot._damage)
	elif target is Elite and shot._pierced.has(target):
		elite_hits.append([trial.trial_tick, serial, born, target.get_network_shield(),
			target.get_network_health(), trial._player.position.distance_to(target.position)])

func _record_contact(target: Node2D, serial: int, born: int, kind: String, damage: float) -> void:
	var contacts: Array = hits.get_or_add(str(target.name), [])
	contacts.append([trial.trial_tick, serial, born, kind, damage, target.health])

func _sample_charge() -> void:
	var visible := get_viewport().get_visible_rect().grow(-38.0)
	for order: Dictionary in trial._fighters.values():
		var fighter = order.ship
		if is_instance_valid(fighter) and fighter.health > 0 and trial._is_charging(order) \
				and visible.has_point(get_viewport().get_canvas_transform() * fighter.global_position):
			charges.get_or_add(str(fighter.name), [trial.trial_tick, int(order.fire)])

func _record_interruption(role: String, at: Vector2, fire: int) -> void:
	interruptions.append([str(trial._fighters[role].ship.name), trial.trial_tick, fire, at.x, at.y])

func _record_choice(_pid: int, card: String, _idx: int) -> void:
	_chosen_at = trial.trial_tick
	_choice = UpgradeDraft.get_draft(1).source
	_chosen_card = card

func _record_health(hp: int, _max_hp: int) -> void:
	if hp < _body_alive:
		health_loss.append([trial.trial_tick, "hull", _body_alive - hp])
	_body_alive = hp

func _record_shield(pid: int, shields: int) -> void:
	if pid == 1:
		if shields < _shield_alive:
			health_loss.append([trial.trial_tick, "shield", _shield_alive - shields])
		_shield_alive = shields

func _check_fans() -> bool:
	for role: String in fans:
		if not charges.has(role) or fans[role].size() != 3 or charges[role][0] >= fans[role][0][0]:
			return false
	return not fans.is_empty() or not interruptions.is_empty()

func _check_interruptions() -> bool:
	var canceled := {}
	for event in interruptions:
		var role: String = event[0]
		if canceled.has(role) or fans.has(role) or not charges.has(role) or deaths.get(role) != event[1] or event[1] >= event[2]:
			return false
		canceled[role] = true
	return canceled.size() == trial.interruptions

func _check(label: String, ok: bool) -> void:
	print("[OPENING] ", label, " pass=", ok)
	_fail += int(not ok)
