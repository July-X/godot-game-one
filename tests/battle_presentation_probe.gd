extends Node
## 同一份夹具可在基线和候选版本录制。输入、弹体、选卡和激光由游戏处理。
const MAIN = preload("res://scenes/main.tscn")
const BULLET = preload("res://scenes/entities/bullet.tscn")
const PALETTE = preload("res://scripts/palette.gd")
const SafeArea = preload("res://scripts/battle_safe_area.gd")
const CARDS := ["pierce", "splash", "power"]

var _main
var _player
var _boss
var _stick
var _out := ""
var _mobile := false
var _verify := false
var _safe_profile := "right"
var _passed := 0
var _failed := 0
var _start := 0
var _shot_count := 0
var _hp_drops := 0
var _last_hp := 0
var _x := 640.0

func _ready() -> void:
	process_priority = 100
	call_deferred("_run")

func _process(_delta: float) -> void:
	# 命中定格使用墙钟。录片统一物理帧时钟，避免不同编码速度改变事件帧。
	if is_instance_valid(_main):
		_main._hitstop_left = 0.0
		Engine.time_scale = 1.0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[1] if args.size() > 1 else ""
	_mobile = args.has("touch")
	_verify = args.has("verify")
	if args.has("inset-left"):
		_safe_profile = "left"
	elif args.has("inset-rounded"):
		_safe_profile = "rounded"
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if _mobile and not args.has("narrow") else 1280, 720)
	seed(1121)
	_main = MAIN.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	seed(1121)
	_start = Engine.get_physics_frames()
	_main._wave_director._cooldown = 90
	_main._asteroid_timer = 90
	_player = _main._player
	_x = _main._screen_center_x()
	_place_player(Vector2(_x - 156, 535))
	# 实拍窗口中的系统鼠标移动会干扰固定航线，只从夹具注入本文的移动。
	_player.set_process_unhandled_input(false)
	if _mobile:
		_main._spawn_mobile_controls()
		_stick = _main.get_node("MobileControls")
		_stick.move_input.connect(_player._motion.handle_mobile_move)
		_player._motion.mobile_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _main._hud.has_method("_layout_battle_hud"):
			_main._hud._layout_battle_hud()
			_main._hud._update_platform_hints()
		if args.has("inset"):
			_apply_safe_area(_asymmetric_safe())
	GameState.health_changed.connect(_health_changed)
	_last_hp = GameState.get_current_health()
	GameState.set_shield_layers(1, 0)
	get_tree().node_added.connect(_observe_bullet)
	for i in 6:
		var enemy_x := _x - 156 if i == 2 else _x - 420 + i * 105
		var enemy = _main._spawn_enemy_at(i % 3, Vector2(enemy_x, 168 + 30 * (i % 2)))
		enemy.set_physics_process(false)
	await _at(68)
	_fan(3)
	await _at(110)
	await _capture("cruise")
	_report("cruise")
	_hurt_bullet()
	await _at(190)
	_main._on_boss_spawn_requested(5)
	_report("boss_request")
	await _at(440)
	if _mobile and args.has("inset"):
		_apply_safe_area(_asymmetric_safe())
	_boss = _main._boss
	_boss.global_position = Vector2(_x, 187)
	_boss.reset_physics_interpolation()
	_boss.take_damage(ceilf(_boss.get_network_max_health() * 0.26))
	_fan(4)
	await _at(472)
	UpgradeDraft.offer_cards(1, CARDS)
	await _at(492)
	await _capture("charge")
	_report("charge")
	# 出光时方向已锁定。马上开始侧移，给触摸摇杆的加速段留下距离。
	while is_instance_valid(_boss) and not _boss._ultimate_laser_firing:
		await get_tree().physics_frame
	_move(Vector2.RIGHT, true)
	await _at(586)
	await _capture("laser-tip")
	_report("laser_tip")
	await _at(598)
	_fan(4)
	await _at(622)
	await _capture("laser-and-draft")
	_report("laser_and_draft")
	if not is_instance_valid(_player):
		_check("pilot_survived_to_choice", false)
		get_tree().quit(1)
		return
	var card := _main._hud._draft_row.get_child(1) as Button
	var before: Vector2 = _player.global_position
	var shots := _shot_count
	if _mobile:
		_touch(1, card.get_global_rect().get_center(), true)
		_touch(1, card.get_global_rect().get_center(), false)
	else:
		_key(KEY_2)
	await _at(645)
	if not is_instance_valid(_player):
		_check("pilot_survived_choice", false)
		get_tree().quit(1)
		return
	if _verify:
		_check("selected_second_card", GameState.get_card_stacks(1).get("splash", 0) == 1 and not UpgradeDraft.has_draft(1))
		_check("movement_and_auto_fire_during_choice", _player.global_position.x > before.x + 20.0 and _shot_count > shots)
		if _mobile:
			_check("only_move_finger_owns_stick", _stick._move_touch_id == 0 and _player._motion.touch_move.x > 0.7)
	if _mobile and _verify:
		var skill := _main._hud._skill_bar.get_child(0) as Button
		_touch(0, skill.get_global_rect().get_center(), false)
	else:
		_move(Vector2.ZERO, false)
	if _mobile and _verify:
		_check("held_touch_released", _player._motion.touch_move == Vector2.ZERO)
	# 下一段录固定束下的扣血。把机体设到光束另一侧，避免片段提前结算。
	_player._motion.mouse_vel = Vector2.ZERO
	_player._motion.mobile_vel = Vector2.ZERO
	_place_player(Vector2(_x + 330, 535))
	_hurt_bullet()
	await _at(805)
	await _capture("laser-hold")
	_report("laser_hold")
	await _at(1310)
	UpgradeDraft.offer_cards(1, CARDS)
	while is_instance_valid(_boss) and _boss._shield_active and Engine.get_physics_frames() - _start < 1420:
		await get_tree().physics_frame
	await _at(Engine.get_physics_frames() - _start + 4)
	await _capture("shield-release")
	_report("shield_release")
	await _at(1430)
	await _capture("vulnerable")
	_report("vulnerable")
	if _verify:
		_check("real_damage_was_observed", _hp_drops > 0)
		_check("laser_has_ended", is_instance_valid(_boss) and not _boss._shield_active)
		_check("open_vulnerability_label", _main._hud._boss_status_phase.text == "可攻击")
		_check("vulnerable_uses_same_hp_bar", not _main._hud._boss_status_hatch.visible and _main._hud._boss_status_fill.color == Color("#e1827f"))
	if is_instance_valid(_boss):
		_boss.take_damage(_boss.get_network_health() + 1)
	await _at(1510)
	await _capture("cruise-return")
	_report("cruise_return")
	if _mobile and _verify:
		await _exercise_touch_lifecycle()
	print("[BATTLE] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)

func _at(tick: int) -> void:
	while Engine.get_physics_frames() - _start < tick:
		await get_tree().physics_frame

func _place_player(at: Vector2) -> void:
	_player.global_position = at
	_player.rotation = 0.0
	_player.reset_physics_interpolation()

func _move(direction: Vector2, pressed: bool) -> void:
	if _mobile:
		var origin := _asymmetric_safe().position + Vector2(138, 470)
		_touch(0, origin, pressed)
		if pressed:
			_drag(0, origin + direction * _stick.joystick_radius * 0.8)
	elif pressed:
		var motion := InputEventMouseMotion.new()
		motion.position = get_viewport().get_visible_rect().get_center()
		motion.relative = direction * 170
		_player._unhandled_input(motion)

func _touch(index: int, pos: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	event.canceled = canceled
	get_viewport().push_input(event, true)

func _drag(index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	get_viewport().push_input(event, true)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func _fan(rows: int) -> void:
	for line in rows:
		for i in 26:
			var pos := Vector2(_x + (i - 12.5) * 31.0, 135 + line * 39.0 + absf(i - 12.5) * 3.0)
			var angle := PI * 0.5 + (i - 12.5) * 0.021
			var tint := PALETTE.ENEMY_BULLET_MID if (line + i) % 3 else PALETTE.ENEMY_BULLET_SLOW
			_spawn_hazard(pos, angle, 165.0 + line * 12.0, tint)

func _hurt_bullet() -> void:
	_spawn_hazard(_player.global_position - Vector2(0, 42), PI * 0.5, 520, PALETTE.ENEMY_BULLET_FAST)

func _spawn_hazard(pos: Vector2, angle: float, speed: float, tint: Color) -> void:
	var shot = Pool.acquire("bullet", BULLET)
	_main.add_child(shot)
	shot.setup(pos, angle, 1, false, 1, speed)
	shot.modulate = tint

func _observe_bullet(node: Node) -> void:
	if node.scene_file_path == BULLET.resource_path:
		_count_shot.call_deferred(node.get_instance_id())

func _count_shot(id: int) -> void:
	var shot := instance_from_id(id) as Node
	if shot and shot.is_in_group("player_bullets"):
		_shot_count += 1

func _health_changed(hp: int, _capacity: int) -> void:
	if hp < _last_hp:
		_hp_drops += 1
	_last_hp = hp

func _capture(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check("capture_" + name, image.save_png(_out.path_join(name + ".png")) == OK)

func _report(name: String) -> void:
	var hud = _main._hud
	var bar = hud._boss_status_root
	var cards: Rect2 = hud._draft_panel.get_global_rect()
	var boss_rect := bar.get_global_rect() as Rect2 if is_instance_valid(bar) and bar.visible else Rect2()
	var laser := "off"
	if is_instance_valid(_boss):
		laser = "%s / %s / %.2f" % [_boss._ultimate_laser_charging, _boss._ultimate_laser_firing, _boss._ultimate_laser_fire_timer]
	var player_pos: Vector2 = _player.global_position if is_instance_valid(_player) else Vector2.INF
	print("[BATTLE] %s tick=%d view=%s shots=%d hp=%d kills=%d pos=%s boss=%s draft=%s overlap=%s laser=%s" % [
		name, Engine.get_physics_frames() - _start, get_viewport().get_visible_rect().size,
		_shot_count, GameState.get_current_health(), GameState.total_kills, player_pos, boss_rect,
		cards if hud._draft_panel.visible else Rect2(), hud._draft_panel.visible and boss_rect.intersects(cards), laser])
	if name == "laser_and_draft" and _verify:
		var row := hud._draft_row as HBoxContainer
		var skills: Rect2 = hud._skill_bar.get_global_rect()
		var safe: Rect2 = hud._safe_rect
		var slot := hud._skill_slots[0].button as Button
		print("[SKILL_RECT] profile=%s mobile=%s safe=%s rect=%s margin=%s slot=%s gap=%d" %
			[_safe_profile, _mobile, safe, skills, safe.end - skills.end, slot.size,
				hud._skill_bar.get_theme_constant("separation")])
		var margin := safe.end - skills.end
		var expected_slot := Vector2(94, 94) if _mobile else Vector2(80, 80)
		_check("skill_slots_keep_their_hitbox_and_gap", slot.size == expected_slot
			and skills.size == Vector2(expected_slot.x * 3 + 16, expected_slot.y)
			and hud._skill_bar.get_theme_constant("separation") == 8)
		if _mobile:
			var center_combat := Rect2(safe.position + safe.size * Vector2(.25, .17), safe.size * Vector2(.43, .55))
			_check("thumb_clearance_leaves_center_and_cards_clear", margin.x > 18 and margin.y > 18
				and safe.encloses(skills) and not skills.intersects(center_combat) and not skills.intersects(cards))
		else:
			_check("desktop_skill_margin_stays_at_18", margin == Vector2(18, 18))
		_check("boss_and_cards_in_separate_rows", hud._draft_panel.visible and row.get_child_count() == 3 and boss_rect.has_area()
			and boss_rect.end.y <= cards.position.y and get_viewport().get_visible_rect().encloses(cards))
		_check("draft_centered_and_enlarged", cards.get_center().distance_to(hud._safe_rect.get_center()) < 1
			and row.get_child(0).size.y >= 120 and row.get_child(0).get_node("CardName").get_theme_font_size("font_size") >= 19)
		_check("draft_has_no_focus", get_viewport().gui_get_focus_owner() == null and not get_tree().paused)
		_check("countdown_max_10_seconds", hud._draft_time_bar.max_value == 10.0 and absf(hud._draft_time_bar.value - 7.5) < 0.2)
		if _mobile:
			_check_safe_area()
	if _verify and name in ["charge", "laser_and_draft", "laser_hold"]:
		if not is_instance_valid(_boss):
			_check("boss_alive_at_" + name, false)
			return
		var phase := {"charge": "蓄力", "laser_and_draft": "推进", "laser_hold": "持续"}
		_check("boss_window_" + name, hud._boss_status_phase.text == "有盾 · 不掉血 · 激光" + phase[name])
		_check("same_hp_fill_width_" + name, hud._boss_status_hatch.visible
			and is_equal_approx(hud._boss_status_hatch.size.x, hud._boss_status_fill.size.x)
			and is_equal_approx(hud._boss_status_fill.size.x, 500.0 * _boss.get_network_health() / _boss.get_network_max_health()))
	if _verify and name == "charge":
		var hit_circle := _boss.get_node("CollisionShape2D") as CollisionShape2D
		var boss_sprite: Sprite2D = _boss._sprite
		var player_sprite: Sprite2D = _player.get_node("Sprite2D")
		var hull := Vector2(boss_sprite.texture.get_image().get_used_rect().size) * boss_sprite.scale
		var swift := Vector2(player_sprite.texture.get_image().get_used_rect().size) * player_sprite.scale
		_check("single_hp_bar_original_collision", not _boss.has_node("HealthBar") and not _boss.has_node("Label")
			and hit_circle.shape.radius == 33.0 and hit_circle.global_scale.is_equal_approx(Vector2.ONE))
		_check("enlarged_hull_at_muzzle", hull.x > swift.x * 1.5 and hull.y > swift.y * 1.2
			and boss_sprite.global_position == _boss._ultimate_laser_start)
		print("[BATTLE] opaque_hull=", hull, " player=", swift, " hit_radius=", hit_circle.shape.radius)
	if _verify and name == "shield_release":
		_check("one_release_in_boss_row", hud._boss_status_phase.text == "护盾解除 · 可攻击"
			and not hud._boss_status_hatch.visible and hud._draft_panel.visible and boss_rect.end.y <= cards.position.y)

func _check_safe_area() -> void:
	var viewport := get_viewport()
	var inset := _asymmetric_safe()
	var safe: Rect2 = SafeArea.from_display(viewport, viewport.get_screen_transform() * inset)
	_check("display_to_canvas_safe_area", safe.is_equal_approx(inset))
	var hud = _main._hud
	var original: Rect2 = hud._safe_rect
	_apply_safe_area(safe)
	var skills: Rect2 = hud._skill_bar.get_global_rect()
	var joystick: Rect2 = _stick._base_node.get_global_rect()
	_check("safe_controls", safe.encloses(hud._draft_panel.get_global_rect()) and safe.grow(-16).encloses(skills)
		and safe.encloses(joystick) and joystick.end.x < skills.position.x
		and _stick._move_touch_id == 0 and _player._motion.touch_move.x > 0.7)
	_apply_safe_area(original)

func _asymmetric_safe() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	match _safe_profile:
		"left":
			return Rect2(Vector2(116, 34), size - Vector2(188, 102))
		"rounded":
			return Rect2(Vector2(32, 26), size - Vector2(64, 78))
	return Rect2(Vector2(72, 34), size - Vector2(188, 102))

func _apply_safe_area(safe: Rect2) -> void:
	_main._hud._layout_in_safe_area(safe)
	_stick._layout_in_safe_area(safe)

func _exercise_touch_lifecycle() -> void:
	var hud = _main._hud
	var motion = _player._motion
	UpgradeDraft.clear_drafts()
	await get_tree().process_frame
	await get_tree().process_frame
	var safe := _asymmetric_safe()
	_apply_safe_area(safe)
	var outside := Vector2(safe.position.x - 1, safe.end.y - 12)
	_touch(0, outside, true)
	_check("outside_safe_does_not_start", _stick._move_touch_id == -1 and not _stick._ui_root.visible)
	_touch(0, outside, false)
	var edge := outside + Vector2(4, 0)
	_touch(0, edge, true)
	_check("fresh_touch_is_neutral_at_actual_origin", _stick._joystick_center.is_equal_approx(edge)
		and _stick._move_vector == Vector2.ZERO and safe.encloses(_stick._base_node.get_global_rect()))
	_drag(0, edge + Vector2(84, 0))
	_check("clamped_visual_does_not_change_direction", motion.touch_move.is_equal_approx(Vector2(0.75, 0))
		and safe.encloses(_stick._knob_node.get_global_rect()))
	_drag(0, Vector2(safe.get_center().x + 30, edge.y))
	_check("owned_touch_survives_crossing_half", _stick._move_touch_id == 0 and motion.touch_move == Vector2.RIGHT)
	UpgradeDraft.offer_cards(1, ["splash", "graze_focus", "pierce"])
	_check("reward_open_releases_owned_finger", _stick._move_touch_id == -1 and motion.touch_move == Vector2.ZERO)
	await get_tree().process_frame
	var card: Button = hud._draft_card_buttons[0]
	var card_point := card.get_global_rect().get_center()
	_drag(0, card_point)
	_touch(0, card_point, false)
	_check("old_finger_cannot_choose_reward", UpgradeDraft.has_draft(1) and _stick._move_touch_id == -1)
	_touch(0, edge, true)
	_drag(0, edge + Vector2(84, 0))
	var old_corner := safe.end - Vector2(22, 22)
	_touch(1, old_corner, true)
	_touch(1, old_corner, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("old_skill_corner_has_no_touch_target", _player.can_dash() and GameState.get_laser_cooldown() == 0
		and UpgradeDraft.has_draft(1) and _stick._move_touch_id == 0)
	var skill: Button = hud._skill_slots[0].button
	var skill_corner := skill.get_global_rect().end - Vector2(4, 4)
	_touch(1, skill_corner, true)
	_touch(1, skill_corner, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("second_finger_uses_shifted_skill_without_selecting_card", GameState.get_laser_cooldown() > 0
		and UpgradeDraft.has_draft(1) and _stick._move_touch_id == 0
		and motion.touch_move.is_equal_approx(Vector2(.75, 0)))
	_touch(0, edge, false)
	var narrow := Rect2(safe.position + Vector2(84, 0), Vector2(544, safe.size.y))
	_apply_safe_area(narrow)
	for i in 3:
		await get_tree().process_frame
	var fits: bool = narrow.encloses(hud._draft_panel.get_global_rect())
	for button: Button in hud._draft_card_buttons:
		var label := button.get_node("Description") as Label
		fits = fits and button.get_global_rect().encloses(label.get_global_rect())
		fits = fits and label.get_line_count() == label.get_visible_line_count()
	_check("narrow_reward_wraps_full_description", fits and card.size.x < 188)
	await _capture("narrow-reward")
	card_point = card.get_global_rect().position + Vector2(8, card.size.y - 8)
	_touch(1, card_point, true)
	_touch(1, card_point, false)
	_check("whole_card_taps_without_starting_stick", not UpgradeDraft.has_draft(1)
		and _stick._move_touch_id == -1 and UpgradeDraft.get_draft(1).source == "tap")
	_apply_safe_area(safe)
	var next := edge + Vector2(120, -106)
	_touch(0, next, true)
	_drag(0, next - Vector2(0, 84))
	_check("next_touch_relocates_center", _stick._joystick_center.is_equal_approx(next) and motion.touch_move.y < -0.7)
	_touch(0, next, true, true)
	_check("os_canceled_touch_clears_move", _stick._move_touch_id == -1 and motion.touch_move == Vector2.ZERO)
	_touch(0, next, true)
	_drag(0, next + Vector2(0, 84))
	_stick.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check("background_clears_move", _stick._move_touch_id == -1 and motion.touch_move == Vector2.ZERO)
	_touch(0, next, true)
	_drag(0, next + Vector2(0, 84))
	get_tree().paused = true
	_check("pause_clears_move", _stick._move_touch_id == -1 and motion.touch_move == Vector2.ZERO)
	_touch(1, edge, true)
	get_tree().paused = false
	_drag(1, edge + Vector2(84, 0))
	_touch(1, edge, false)
	_check("paused_touch_cannot_resume_movement", motion.touch_move == Vector2.ZERO and not _stick._ui_root.visible)
	_touch(0, next, true)
	_drag(0, next + Vector2(84, 0))
	_main._on_player_died()
	await get_tree().process_frame
	_check("gameover_releases_stick_and_has_safe_button", not _stick.visible and _stick._move_touch_id == -1
		and motion.touch_move == Vector2.ZERO and safe.grow(-16).encloses(hud._restart_button.get_global_rect()))
	var result_button: Vector2 = hud._restart_button.get_global_rect().get_center()
	var finished_id: int = _main.get_instance_id()
	_touch(0, result_button, false)
	_touch(1, edge, true)
	_touch(1, edge, false)
	await get_tree().process_frame
	_check("result_ignores_old_release_and_blank_press", is_instance_valid(_main) and not GameState.game_running)
	_touch(1, result_button, true)
	_touch(1, result_button, false)
	for i in 8:
		await get_tree().process_frame
	var restarted := get_tree().current_scene
	_check("result_button_restarts", is_instance_valid(restarted) and restarted.get_instance_id() != finished_id
		and GameState.game_running)

func _check(label: String, ok: bool) -> void:
	print("[BATTLE] %s pass=%s" % [label, ok])
	_passed += int(ok)
	_failed += int(not ok)
