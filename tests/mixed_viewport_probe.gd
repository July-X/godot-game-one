extends "res://tests/lan_probe.gd"
## 真实大厅开局，P1/P2 通过视口输入飞到四边。可选图形模式见 run_probe.sh。

const FIELD := Vector2(1280, 720)
const Director = preload("res://scripts/battle/wave_director.gd")
const BossModel = preload("res://scripts/battle/enemies/boss/boss.gd")
const SafeArea = preload("res://scripts/ui/battle_safe_area.gd")
const SHOT_SPEED := 240.0
const DROP_AT := Vector2(924, 380)
const RESCUE_AT := Vector2(264, 414)
var _peer_steps: Array[String] = []
var _expected_size: Vector2i
var _direction := Vector2.ZERO
var _stick: Node
var _teammate: Node2D
var _line_spawns: Array[Vector2] = []
var _watch_line := false
var _watch_bullets := false
var _turn := Vector2.INF
var _exit_x := INF
var _boss_entry := Vector2.INF
var _tablet_pair := false
var _safe := Rect2()


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args[2] not in ["wide-host", "wide-client", "wide-tablet-host", "wide-tablet-client"] or (args.size() > 3 and DisplayServer.get_name() == "headless"):
		_check("arguments", false, "使用 tests/run_probe.sh 端口 wide-{host,client}|wide-tablet-{host,client} [截图目录]")
		get_tree().quit(_summarize())
		return
	_tablet_pair = args[2].begins_with("wide-tablet-")
	if _tablet_pair:
		_expected_size = Vector2i(1280, 960) if args[2] == "wide-tablet-" + _role else Vector2i(1600, 720)
	else:
		_expected_size = Vector2i(1600 if args[2] == "wide-" + _role else 1280, 720)
	if DisplayServer.get_name() == "headless":
		# 无窗口时只合成逻辑画布。截图模式走项目的 canvas_items + expand。
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = _expected_size
	var lobby := preload("res://scenes/ui/lobby.tscn").instantiate()
	get_tree().root.add_child(lobby)
	get_tree().current_scene = lobby
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var joined := err == OK and await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 8.0)
	_check("connected", joined, error_string(err))
	if joined:
		await _barrier("lobby")
		if _role == "host":
			lobby._on_start_pressed()
		var started := await _wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == MAIN_SCENE, 10.0)
		_check("host_started_battle", started, "lobby -> main")
		if started:
			_main = get_tree().current_scene
			var ready := await _wait_until(func(): return _cond_both_players() and is_instance_valid(_main._player), 8.0)
			_check("two_players", ready, str(_main._players.keys()))
			if ready:
				await _exercise_arena()
	get_tree().quit(_summarize())


func _exercise_arena() -> void:
	_teammate = _main._players[NetworkManager.connected_peers[0]]
	_main._player.get_node("CombatController")._shoot_timer = 120.0
	_main._asteroid_timer = 120.0
	_main._wave_director._cooldown = 120.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().node_added.connect(_observe_spawn)
	var view := get_viewport().get_visible_rect()
	var offset := (Vector2(_expected_size) - FIELD) * 0.5
	var canvas := get_viewport().get_canvas_transform()
	_check("full_field", view.size.is_equal_approx(Vector2(_expected_size))
		and (canvas * Vector2.ZERO).is_equal_approx(offset) and (canvas * FIELD).is_equal_approx(offset + FIELD),
		"viewport=%s world_on_canvas=%s..%s" % [view.size, canvas * Vector2.ZERO, canvas * FIELD])
	var bg: ColorRect = _main.get_node("Backdrop/BgColor")
	_check("display_canvas", bg.get_global_rect().is_equal_approx(view) and _main._hud._get_design_canvas_size().is_equal_approx(view.size)
		and _main._hud.transform == Transform2D.IDENTITY, "bg=%s HUD=%s" % [bg.size, _main._hud.transform])
	await _check_projection(view)
	if _tablet_pair:
		_bind_test_stick()
	var left := Vector2(24, 504)
	var right := Vector2(1256, 504)
	await _fly_to("opposite_edges", left, right, Vector2.LEFT, Vector2.RIGHT)
	await _check_spawns_and_bullets()
	if _role == "host":
		_main._on_boss_spawn_requested(5)
	var arrived := await _wait_until(func(): return is_instance_valid(_main._boss) and _main._boss.position.distance_to(Vector2(640, 160)) < 0.5, 8.0)
	_check("boss_entry", _boss_entry == Vector2(640, -80) and arrived, "entry=%s arrived=%s" % [_boss_entry, arrived])
	await _barrier("boss_at_center")
	if arrived and OS.get_cmdline_user_args().size() > 3:
		await _capture(OS.get_cmdline_user_args()[3])
	await _barrier("frame_done")
	if _role == "client" and not _stick:
		# 桌面注入真实摇杆与本机绑定。mobile_check 另测移动端入场自动绑定。
		_main._spawn_mobile_controls()
		_stick = _main.get_node("MobileControls")
		var motion: Node = _main._player.get_node("MotionController")
		motion.mobile_mode = true
		_stick.move_input.connect(motion.handle_mobile_move)
		var touch := InputEventScreenTouch.new()
		touch.pressed = true
		touch.position = Vector2(160, get_viewport().get_visible_rect().end.y - 170)
		get_viewport().push_input(touch, true)
	var top := Vector2(1256, 24)
	var bottom := Vector2(24, 696)
	await _fly_to("opposite_corners", top, bottom, Vector2(1, -1), Vector2(-1, 1))
	await _fly_to("vertical_edges", Vector2(1256, 696), Vector2(24, 24), Vector2.DOWN, Vector2.UP)
	if _tablet_pair:
		await _fly_to("other_bottom_and_top_corners", bottom, top, Vector2.LEFT, Vector2.RIGHT)
		await _fly_to("last_top_and_bottom_corners", Vector2(24, 24), Vector2(1256, 696), Vector2.UP, Vector2.DOWN)
		await _fly_to("return_along_horizontal_edges", Vector2(1256, 24), Vector2(24, 696), Vector2.RIGHT, Vector2.LEFT)
		await _fly_to("corners_before_resize", Vector2(1256, 696), Vector2(24, 24), Vector2.DOWN, Vector2.UP)
	if _stick:
		_touch(0, _stick._joystick_center, false)
		_check("touch_released", _main._player.get_node("MotionController").touch_move == Vector2.ZERO, "screen touch up")
	var native_window := get_window().size
	await _check_resize()
	await _barrier("resized")
	if _role == "client":
		# 模拟旧宽端上报越界。停一小段常规上报，给房主观察同一条消息的时间。
		_main._player_report_timer = 4.0
		_main._rpc_report_player_state.rpc_id(1, multiplayer.get_unique_id(), 1576, -40, 0)
	else:
		var clamped := await _wait_until(func(): return _main._player_target_positions.get(_teammate.peer_id) == Vector2(1256, 24), 3.0)
		_check("host_bounds_report", clamped, str(_main._player_target_positions.get(_teammate.peer_id)))
	await _barrier("done")
	if _tablet_pair:
		await _restore_native_view(native_window)
		_main._player_report_timer = 0.0
		await _check_touch_hud()
		await _check_world_anchors()
		await _check_resize(false)
	await _barrier("before_disconnect")
	if _role == "client":
		_check("host_ready_for_disconnect", await _wait_until(func(): return _peer_steps.has("disconnect_now"), 4.0), "")
		NetworkManager.disconnect_network()
	else:
		var previous_id := _main.get_instance_id()
		_host_at.rpc("disconnect_now")
		var solo_view := await _wait_until(func():
			var scene := get_tree().current_scene
			if not is_instance_valid(scene) or scene.get_instance_id() == previous_id or scene.scene_file_path != MAIN_SCENE:
				return false
			var camera := scene.get_node("Camera2D") as Camera2D
			return (not NetworkManager.is_online() and NetworkManager.battle_size(scene) == Vector2(1280, 800)
				and camera.position == Vector2(640, 400) and camera.zoom == Vector2.ONE), 6.0)
		_check("disconnect_restores_solo_field", solo_view, "1280×800 at one-to-one zoom")


func _check_resize(check_corner := true) -> void:
	var size := Vector2i(1280, 800)
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_size = size
	else:
		get_window().size = Vector2i(960, 600)  # 0.75 倍逻辑画布
	var resized := func() -> bool:
		return get_viewport().get_visible_rect().size.is_equal_approx(Vector2(size)) \
			and get_viewport().get_canvas_transform().origin.is_equal_approx(Vector2(0, 40))
	var mapped := await _wait_until(resized, 4.0)
	var origin := get_viewport().get_canvas_transform().origin
	var corner := Vector2(1256, 696) if _role == "host" else Vector2(24, 24)
	var own: Vector2 = _main._player.position if is_instance_valid(_main._player) else Vector2.INF
	_check("resize_preserves_field", mapped and (not check_corner or own.distance_to(corner) < 0.1)
		and NetworkManager.battle_size(_main) == FIELD, "view=%s origin=%s own=%s" % [get_viewport().get_visible_rect().size, origin, own])
	if _stick and check_corner and DisplayServer.get_name() != "headless":
		var tap := InputEventScreenTouch.new()
		var at := Vector2(160, size.y - 170)
		var transform := get_viewport().get_final_transform()
		tap.position = transform * at
		tap.pressed = true
		get_viewport().push_input(tap)
		var drag := InputEventScreenDrag.new()
		drag.position = transform * (at + Vector2(84, 0))
		get_viewport().push_input(drag)
		var motion: Node = _main._player.get_node("MotionController")
		_check("scaled_touch", motion.touch_move.is_equal_approx(Vector2(0.75, 0)), "physical=%s stick=%s move=%s" % [tap.position, _stick._joystick_center, motion.touch_move])
		tap = tap.duplicate()
		tap.pressed = false
		get_viewport().push_input(tap)
	if _tablet_pair and check_corner:
		var prior_size := get_window().content_scale_size
		# 改的是测试根画布基准，物理窗口尺寸没变。直接跑同一个取景入口。
		get_window().content_scale_size = Vector2i(1024, 576)
		await get_tree().process_frame
		_main._center_camera_on_viewport()
		var zoomed := await _wait_until(func():
			return get_viewport().get_canvas_transform().get_scale().is_equal_approx(Vector2(0.8, 0.8)), 2.0)
		var transform := get_viewport().get_canvas_transform()
		var projected := Rect2(transform * Vector2.ZERO, transform.basis_xform(FIELD))
		_check("smaller_logical_view_uses_uniform_fit", zoomed and _view_contains(projected)
			and projected.get_center().distance_to(get_viewport().get_visible_rect().get_center()) < 0.05,
			"view=%s world=%s" % [get_viewport().get_visible_rect(), projected])
		get_window().content_scale_size = prior_size
		await get_tree().process_frame
		_main._center_camera_on_viewport()
		await _wait_until(resized, 3.0)

func _view_contains(rect: Rect2) -> bool:
	return get_viewport().get_visible_rect().grow(0.05).encloses(rect)

func _check_projection(view: Rect2) -> void:
	var hud := _main._hud as CanvasLayer
	var camera := _main.get_node("Camera2D") as Camera2D
	_main.add_shake(1.0)
	var fits := true
	var invertible := true
	var moved := false
	for i in 6:
		await get_tree().process_frame
		camera.force_update_scroll()
		var canvas := get_viewport().get_canvas_transform()
		var projected := Rect2(canvas * Vector2.ZERO, canvas.basis_xform(FIELD))
		fits = fits and _view_contains(projected)
		moved = moved or not camera.offset.is_zero_approx()
		for world in [Vector2.ZERO, Vector2(24, 696), FIELD]:
			var screen: Vector2 = _main.world_to_screen(world)
			invertible = invertible and screen.is_equal_approx(get_viewport().get_screen_transform() * (canvas * world))
			invertible = invertible and _main.screen_to_world(screen).distance_to(world) < 0.002
	var extra := not view.size.is_equal_approx(FIELD)
	_check("shake_keeps_full_field", fits and moved == extra, "extra=%s offset=%s" % [extra, camera.offset])
	_check("screen_world_inverse_with_shake_and_fixed_hud", invertible and hud.transform == Transform2D.IDENTITY, str(view))
	_main._camera_shake.reset()
	camera.force_update_scroll()

func _restore_native_view(native_window: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_size = _expected_size
	else:
		get_window().size = native_window
	await _wait_until(func(): return get_viewport().get_visible_rect().size.is_equal_approx(Vector2(_expected_size)), 3.0)
	_layout_test_safe_area()

func _bind_test_stick() -> void:
	_main._spawn_mobile_controls()
	_stick = _main.get_node("MobileControls")
	var motion: Node = _main._player.get_node("MotionController")
	motion.mobile_mode = true
	_stick.move_input.connect(motion.handle_mobile_move)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main._hud._update_platform_hints()
	_layout_test_safe_area()
	_touch(0, _move_origin(), true)

func _layout_test_safe_area() -> void:
	var view := get_viewport().get_visible_rect()
	var inset := view.grow_individual(-73, -16, -14, -26) if view.size.x > FIELD.x else view.grow_individual(-14, -25, -64, -18)
	_safe = SafeArea.from_display(get_viewport(), get_viewport().get_screen_transform() * inset)
	_main._hud._layout_in_safe_area(_safe)
	_stick._layout_in_safe_area(_safe)

func _move_origin() -> Vector2:
	return Vector2(_safe.position.x + 92.0, _safe.end.y - 135.0)

func _touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	get_viewport().push_input(event)

func _drag(point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = get_viewport().get_final_transform() * point
	get_viewport().push_input(event)

func _tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	_touch(1, point, true)
	_touch(1, point, false)

func _check_touch_hud() -> void:
	var pilot: Node2D = _main._player
	var hud = _main._hud
	var peer_id: int = pilot.peer_id
	var anchor := _move_origin()
	_touch(0, anchor, true)
	var direction := Vector2.LEFT if pilot.position.x > FIELD.x * 0.5 else Vector2.RIGHT
	_drag(anchor + direction * 84.0)
	_check("safe_area_touch_uses_canvas_direction", _stick._move_touch_id == 0
		and _stick._move_vector.is_equal_approx(direction * 0.75) and hud._safe_rect.is_equal_approx(_safe), str(_safe))
	await _barrier("holding_before_draft")
	if _role == "host":
		GameState.level_up()
	var offered := await _wait_until(func(): return UpgradeDraft.has_draft(peer_id) and hud._draft_panel.visible, 3.0)
	await get_tree().process_frame
	var dash: Button = hud._skill_slots[2].button
	var from := pilot.position
	_tap(dash)
	var dashed := await _wait_until(func(): return pilot.get_dash_cooldown_ratio() > 0.0, 0.5)
	await _wait_seconds(0.12)
	_check("skill_uses_safe_area_and_actual_world_dash", offered and _safe.encloses(dash.get_global_rect())
		and dashed and pilot.position.distance_to(from) > 35.0 and _stick._move_touch_id == 0 and UpgradeDraft.has_draft(peer_id),
		"%s → %s" % [from, pilot.position])
	if offered:
		_tap(hud._draft_card_buttons[1])
	var confirmed := await _wait_until(func(): return bool(UpgradeDraft.get_draft(peer_id).get("chosen", false)), 2.0)
	_check("card_and_score_stay_in_safe_canvas", confirmed and UpgradeDraft.get_draft(peer_id).get("index") == 1
		and _stick._move_touch_id == 0 and _safe.encloses(hud._score_label.get_global_rect()), str(hud._score_label.get_global_rect()))
	_touch(0, anchor, false)
	_check("held_touch_releases_cleanly", _stick._move_touch_id == -1 and _stick._move_vector == Vector2.ZERO, "")
	await _barrier("controls_checked")

func _check_world_anchors() -> void:
	if _role == "host":
		_main.spawn_boss_fragment("core", DROP_AT)
		var boss: BossModel = _main._boss
		_main._player.global_position = Vector2(640, 560)
		boss._start_ultimate_laser()
		boss._tick_ultimate_laser(BossModel.BOSS_ULTIMATE_LASER_CHARGE + 0.01)
		boss._ultimate_laser_fire_timer = 8.0
		boss._publish_attack_window()
		_main._player.global_position = RESCUE_AT
		_main._player.force_kill()
	var arrived := await _wait_until(func():
		return (_find_anchor_drop() != null and GameState.rescue_peer_id == 1
			and is_instance_valid(_main._boss_laser_visual)
			and _main._boss_laser_visual._beam_start.is_equal_approx(Vector2(640, 160))), 3.0)
	var drop := _find_anchor_drop()
	_check("same_world_anchors_for_drop_rescue_and_laser", arrived and _main._players[1].global_position.is_equal_approx(RESCUE_AT)
		and GameState.rescue_position.is_equal_approx(RESCUE_AT) and _node_aligns(drop, DROP_AT)
		and _node_aligns(_main._boss_laser_visual, Vector2(640, 160)), "drop=%s rescue=%s" % [drop, GameState.rescue_position])
	await _barrier("world_anchors")
	var args := OS.get_cmdline_user_args()
	if arrived and args.size() > 3:
		# 加入端刚收到状态时，HUD 的 _process 和 Main 的重绘还没提交到视口。
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := args[3].path_join("%s-%s-anchors.png" % [args[2], _role])
		var ring_samples := _count_rescue_ring_pixels(image)
		_check("rendered_world_anchors", image.save_png(path) == OK and ring_samples >= 8
			and _main._hud._downed_label.text.contains("P1 倒地"), "%s ring_samples=%d/12" % [path, ring_samples])
	await _barrier("anchor_frame_done")

func _count_rescue_ring_pixels(image: Image) -> int:
	var scale_px := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var canvas := get_viewport().get_canvas_transform()
	var count := 0
	for i in 12:
		var world := RESCUE_AT + Vector2.from_angle(i * TAU / 12) * GameState.RESCUE_RADIUS
		var pixel := Vector2i((canvas * world) * scale_px)
		var found := false
		for x in range(-1, 2):
			for y in range(-1, 2):
				var color := image.get_pixelv(pixel + Vector2i(x, y))
				found = found or (color.g > 0.45 and color.b > 0.5 and color.g > color.r + 0.1)
		count += int(found)
	return count

func _find_anchor_drop() -> Node2D:
	for item: Node2D in get_tree().get_nodes_in_group("powerups"):
		if item.global_position.distance_to(DROP_AT) < 0.1:
			return item
	return null

func _node_aligns(node: Node2D, point: Vector2) -> bool:
	var drawn := get_viewport().get_screen_transform() * node.get_global_transform_with_canvas().origin
	return _main.world_to_screen(point).distance_to(drawn) < 0.05 and _main.screen_to_world(drawn).distance_to(point) < 0.05


func _check_spawns_and_bullets() -> void:
	_watch_line = true
	_watch_bullets = true
	await _barrier("armed")
	var size: int = Director.formation_size(GameState.level, Director.PHASE_SETUP)
	var expected: Array[Vector2] = []
	for order in Director.plan_formation(Director.FORMATION_LINE, FIELD, size):
		expected.append(order.pos)
	if _role == "host":
		# 起拍只有横排和纵列。固定上一个阵型，让真实导演排出可核对的横排。
		var director: Node = _main._wave_director
		director.reset()
		director._last_formation = Director.FORMATION_COLUMN
		director._budget = size
		_main._tick_wave_director(0)
		director._cooldown = 120.0
	var spawned := await _wait_until(func(): return _line_spawns.size() >= size, 4.0)
	_watch_line = false
	_check("director_spawns", spawned and _line_spawns == expected, str(_line_spawns))
	if _role == "host":
		# 大厅载入时的长帧会让 ENet 暂时节流。等链路恢复后才发唯一一组不可靠有序弹包。
		var link: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(NetworkManager.connected_peers[0])
		await _wait_until(func(): return link.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE) >= link.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT), 8.0)
	await _barrier("line_spawned")
	if _role == "host":
		var gun: Node = _main._player.get_node("CombatController")
		gun._spawn_bullet(Vector2(1190, 296), 0, 1, true, 7, SHOT_SPEED)
		gun._spawn_bullet(Vector2(1200, 332), 0, 1, false, 1, SHOT_SPEED)
	await _wait_until(func(): return _turn.is_finite() and is_finite(_exit_x), 4.0)
	_watch_bullets = false
	_check("same_shot_bounce", _turn == Vector2(1270, -1), "turn_x/direction_x=%s" % _turn)
	_check("enemy_bullet_recycled", _exit_x > 1340 and _exit_x <= 1344.1, "exit_x=%.1f" % _exit_x)


func _observe_spawn(node: Node) -> void:
	if _watch_line and node.scene_file_path == "res://scenes/entities/enemy.tscn":
		_line_spawns.append(node.position)
	if node.scene_file_path == "res://scenes/entities/boss.tscn":
		_boss_entry = node.position
		# 保留房主入场 tween 和网络插值，将随后的 AI 停在入场终点供两端取同一帧。
		node.set_physics_process.call_deferred(false)


func _physics_process(_delta: float) -> void:
	# 两个桌面窗口可能互相切焦点。系统取消后模拟手指重新落下，走同一输入链路。
	if _direction != Vector2.ZERO and _tablet_pair and is_instance_valid(_stick) and _stick._move_touch_id == -1:
		_touch(0, _move_origin(), true)
		_drag(_stick._joystick_center + _direction * _stick.joystick_radius)
	if _direction != Vector2.ZERO and not _stick:
		var mouse := InputEventMouseMotion.new()
		mouse.position = get_viewport().get_visible_rect().get_center()
		mouse.relative = _direction * 64.0
		get_viewport().push_input(mouse, true)
	if not _watch_bullets:
		return
	for bullet in get_tree().get_nodes_in_group("player_bullets"):
		if _turn == Vector2.INF and bullet._level == 7 and bullet._has_bounced and is_equal_approx(bullet.position.y, 296):
			_turn = Vector2(bullet.position.x, bullet._direction.x)
	for bullet in get_tree().get_nodes_in_group("enemy_bullets"):
		if bullet._speed == SHOT_SPEED and is_equal_approx(bullet.position.y, 332) and not bullet.tree_exiting.is_connected(_record_exit.bind(bullet)):
			bullet.tree_exiting.connect(_record_exit.bind(bullet), CONNECT_ONE_SHOT)


func _record_exit(bullet: Node2D) -> void:
	_exit_x = bullet.position.x


func _fly_to(step: String, p1: Vector2, p2: Vector2, dir1: Vector2, dir2: Vector2) -> void:
	var own := p1 if _role == "host" else p2
	var other := p2 if _role == "host" else p1
	_direction = (dir1 if _role == "host" else dir2).normalized()
	if _stick:
		_drag(_stick._joystick_center + _direction * _stick.joystick_radius)
	var reached := await _wait_until(func(): return _main._player.position.distance_to(own) < 0.1 and _teammate.position.distance_to(other) < 0.8, 12.0)
	var projected := _teammate.get_global_transform_with_canvas().origin
	var normal := Vector2(_main.screen_to_world(get_viewport().get_screen_transform() * projected)) / FIELD
	_check(step, reached and get_viewport().get_visible_rect().has_point(projected) and normal.distance_to(other / FIELD) < 0.002,
		"own=%s peer=%s peer_on_canvas=%s normalized=%s" % [_main._player.position, _teammate.position, projected, normal])
	await _barrier(step)
	_direction = Vector2.ZERO


func _capture(directory: String) -> void:
	# P2 的独立选卡可能盖住 Boss。等正常倒计时收起后，两端再拍停驻的同一幕。
	var panel: Control = _main._hud.get_node("DraftPanel")
	var clear_view := await _wait_until(func(): return not panel.is_visible_in_tree(), 12.0)
	_check("boss_visible_for_capture", clear_view, "draft_visible=%s" % panel.is_visible_in_tree())
	await _barrier("clear_view")
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	var path := directory.path_join("%s-%s.png" % [args[2], _role])
	_check("rendered_frame", img.save_png(path) == OK, "%s pixels=%s boss_id=%s P1/P2=%s/%s" %
		[path, img.get_size(), _main._boss.entity_id, _main._players[1].position, _main._players[_main._players.keys().max()].position])
	_check_background_edge(img)
	# 用跨过右边缘的色块验证真实渲染裁切，两张交付截图已经在上方保存。
	var mark := ColorRect.new()
	mark.color = Color.MAGENTA
	mark.z_index = 3000
	mark.position = Vector2(1270, 246)
	mark.size = Vector2(20, 8)
	_main.add_child(mark)
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	img = get_viewport().get_texture().get_image()
	var scale_px := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var canvas := get_viewport().get_canvas_transform()
	var inside := Vector2i((canvas * Vector2(1275, 250)) * scale_px)
	var outside := Vector2i((canvas * Vector2(1285, 250)) * scale_px)
	var clipped := not Rect2i(Vector2i.ZERO, img.get_size()).has_point(outside) or img.get_pixelv(outside) != Color.MAGENTA
	_check("world_clip", img.get_pixelv(inside) == Color.MAGENTA and clipped, "inside=%s outside=%s" % [inside, outside])
	mark.queue_free()

func _check_background_edge(img: Image) -> void:
	var view := get_viewport().get_visible_rect()
	var ratio := view.size / FIELD
	if is_equal_approx(ratio.x, ratio.y):
		return
	var x_extra := ratio.x > ratio.y
	var scale_px := Vector2(img.get_size()) / view.size
	var canvas := get_viewport().get_canvas_transform()
	var normal := Vector2i(1, 0) if x_extra else Vector2i(0, 1)
	var bright := 0
	var samples := 64
	for i in samples:
		var world := Vector2(FIELD.x - 0.5, 182.0 + 3.0 * i) if x_extra else Vector2(360.0 + 9.0 * i, FIELD.y - 0.5)
		var pixel := Vector2i((canvas * world) * scale_px)
		var surround_a := img.get_pixelv(pixel - normal * 3).get_luminance()
		var surround_b := img.get_pixelv(pixel + normal * 3).get_luminance()
		for offset in [-1, 0, 1]:
			if img.get_pixelv(pixel + normal * offset).get_luminance() > maxf(surround_a, surround_b) + 0.07:
				bright += 1
				break
	_check("no_drawn_arena_edge", bright < samples / 8, "continuous_line_pixels=%d/%d" % [bright, samples])


func _barrier(step: String) -> void:
	if multiplayer.is_server():
		_host_at.rpc(step)
	else:
		_client_at.rpc_id(1, step)
	if not await _wait_until(func(): return _peer_steps.has(step), 12.0):
		_check("peer_" + step, false, "联机同步点超时")


@rpc("any_peer", "reliable")
func _client_at(step: String) -> void:
	if not multiplayer.is_server():
		return
	_peer_steps.append(step)


@rpc("authority", "reliable")
func _host_at(step: String) -> void:
	_peer_steps.append(step)
