extends Node
## 同一份夹具可在基线和候选版本录制。输入、弹体、选卡和激光由游戏处理。
const MAIN = preload("res://scenes/main.tscn")
const BULLET = preload("res://scenes/entities/bullet.tscn")
const PALETTE = preload("res://scripts/palette.gd")
const CARDS := ["pierce", "splash", "power"]

var _main
var _player
var _boss
var _stick
var _out := ""
var _mobile := false
var _verify := false
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
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if _mobile else 1280, 720)
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
	if _mobile:
		_main._spawn_mobile_controls()
		_stick = _main.get_node("MobileControls")
		_stick.move_input.connect(_player._motion.handle_mobile_move)
		_player._motion.mobile_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _main._hud.has_method("_layout_battle_hud"):
			_main._hud._layout_battle_hud()
			_main._hud._update_platform_hints()
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
	_boss = _main._boss
	_boss.global_position = Vector2(_x, 187)
	_boss.reset_physics_interpolation()
	_boss.take_damage(ceilf(_boss.get_network_max_health() * 0.26))
	_fan(4)
	await _at(492)
	await _capture("charge")
	_report("charge")
	# 出光时方向已锁定。马上开始侧移，给触摸摇杆的加速段留下距离。
	while is_instance_valid(_boss) and not _boss._ultimate_laser_firing:
		await get_tree().physics_frame
	_move(Vector2.RIGHT, true)
	await _at(583)
	UpgradeDraft.offer_cards(1, CARDS)
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
	await _at(1430)
	if _verify:
		_check("real_damage_was_observed", _hp_drops > 0)
		_check("laser_has_ended", is_instance_valid(_boss) and not _boss._shield_active)
		_check("open_vulnerability_label", _main._hud._boss_status_phase.text == "可攻击")
	if is_instance_valid(_boss):
		_boss.take_damage(_boss.get_network_health() + 1)
	await _at(1510)
	await _capture("cruise-return")
	_report("cruise_return")
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
		_touch(0, _stick._joystick_center + direction * _stick.joystick_radius * 0.8, pressed)
	elif pressed:
		var motion := InputEventMouseMotion.new()
		motion.position = get_viewport().get_visible_rect().get_center()
		motion.relative = direction * 170
		get_viewport().push_input(motion, true)

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
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
	var boss_rect := bar.get_global_rect() as Rect2 if is_instance_valid(bar) else Rect2()
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
		_check("boss_and_cards_in_separate_rows", hud._draft_panel.visible and row.get_child_count() == 3 and boss_rect.has_area()
			and boss_rect.end.y <= cards.position.y and get_viewport().get_visible_rect().encloses(cards))
		_check("draft_has_no_focus", get_viewport().gui_get_focus_owner() == null and not get_tree().paused)
		_check("countdown_max_10_seconds", hud._draft_time_bar.max_value == 10.0 and hud._draft_time_bar.value > 8.0)
		if _mobile:
			_check_safe_area()
	if _verify and name in ["charge", "laser_and_draft", "laser_hold"]:
		var phase := {"charge": "蓄力", "laser_and_draft": "推进", "laser_hold": "持续"}
		_check("boss_window_" + name, hud._boss_status_phase.text == "护盾中 · 激光" + phase[name])

func _check_safe_area() -> void:
	var viewport := get_viewport()
	var view := viewport.get_visible_rect()
	var unsafe_edges := Rect2(Vector2(60, 14), view.size - Vector2(140, 46))
	var area_script = load("res://scripts/battle_safe_area.gd")
	var safe: Rect2 = area_script.from_display(viewport, viewport.get_screen_transform() * unsafe_edges)
	_check("display_to_canvas_safe_area", safe.is_equal_approx(unsafe_edges))
	var hud = _main._hud
	hud._layout_in_safe_area(safe)
	_stick._layout_in_safe_area(safe)
	var skills: Rect2 = hud._skill_bar.get_global_rect()
	var joystick := Rect2(_stick._joystick_center - Vector2.ONE * _stick.joystick_radius, Vector2.ONE * _stick.joystick_radius * 2.0)
	_check("safe_controls", safe.encloses(hud._draft_panel.get_global_rect()) and safe.encloses(skills)
		and safe.encloses(joystick) and joystick.end.x < skills.position.x)
	# 回到实际视口的安全区，已按住的手指应持续驱动机体。
	hud._layout_battle_hud()
	_stick._recalc_joystick()

func _check(label: String, ok: bool) -> void:
	print("[BATTLE] %s pass=%s" % [label, ok])
	_passed += int(ok)
	_failed += int(not ok)
