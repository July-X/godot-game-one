extends "res://tests/lan_probe.gd"
## 真实大厅开局，P1/P2 通过视口输入飞到四边。可选图形模式见 run_probe.sh。

const FIELD := Vector2(1280, 720)
const Director = preload("res://scripts/wave_director.gd")
const SHOT_SPEED := 240.0
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


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args[2] not in ["wide-host", "wide-client"] or (args.size() > 3 and DisplayServer.get_name() == "headless"):
		_check("arguments", false, "使用 tests/run_probe.sh 端口 wide-host|wide-client [截图目录]")
		get_tree().quit(_summarize())
		return
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
	if _role == "client":
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
	if _stick:
		var release := InputEventScreenTouch.new()
		release.position = _stick._joystick_center
		get_viewport().push_input(release, true)
		_check("touch_released", _main._player.get_node("MotionController").touch_move == Vector2.ZERO, "screen touch up")
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
	if _role == "client":
		NetworkManager.disconnect_network()
	else:
		var solo_view := await _wait_until(func(): return _main._fallback_in_progress and _main.get_node("Camera2D").position == Vector2(640, 400), 4.0)
		_check("disconnect_restores_solo_field", solo_view and NetworkManager.battle_size(_main) == Vector2(1280, 800), str(_main.get_node("Camera2D").position))


func _check_resize() -> void:
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
	_check("resize_preserves_field", mapped and _main._player.position.distance_to(corner) < 0.1
		and NetworkManager.battle_size(_main) == FIELD, "view=%s origin=%s own=%s" % [get_viewport().get_visible_rect().size, origin, _main._player.position])
	if _stick and DisplayServer.get_name() != "headless":
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
		var drag := InputEventScreenDrag.new()
		drag.position = _stick._joystick_center + _direction * _stick.joystick_radius
		get_viewport().push_input(drag, true)
	var reached := await _wait_until(func(): return _main._player.position.distance_to(own) < 0.1 and _teammate.position.distance_to(other) < 0.8, 12.0)
	var projected := _teammate.get_global_transform_with_canvas().origin
	_check(step, reached and get_viewport().get_visible_rect().has_point(projected),
		"own=%s peer=%s peer_on_canvas=%s" % [_main._player.position, _teammate.position, projected])
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
