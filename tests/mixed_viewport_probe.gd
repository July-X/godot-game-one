extends "res://tests/lan_probe.gd"
## 独立的已知失败用例。验收目标是窄屏也能看见边界上的队友。
## bash tests/run_probe.sh 7790 wide-host 或 wide-client

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var wide := args.size() >= 3 and args[2] == "wide-" + _role
	var size := Vector2i(1600 if wide else 1280, 720)
	# 无屏幕时显式给出两端的逻辑视口。后续移动、夹取和传输均走生产代码。
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = size
	var err: Error
	if _role == "host":
		err = NetworkManager.create_host(_port)
	else:
		err = NetworkManager.join_host("127.0.0.1", _port)
	var online := err == OK and await _wait_until(NetworkManager.is_online, 8.0)
	_check("online", online, error_string(err))
	if online:
		_enter_main_scene()
		var ready := await _wait_until(func(): return _main._players.size() == 2 and is_instance_valid(_main._player), 8.0)
		_check("two_players", ready, str(_main._players.keys()))
		if ready:
			await _check_edge(size)
	# 给对端留出接收最后一帧位置的时间。
	await _wait_seconds(0.6)
	get_tree().quit(_summarize())


func _check_edge(size: Vector2i) -> void:
	var viewport_size: Vector2 = _main.get_viewport_rect().size
	_check("logical_viewport", viewport_size == Vector2(size), str(viewport_size))
	var own: Node2D = _main._player
	own.global_position = Vector2(size.x + 50, 220)
	own.get_node("MotionController")._clamp_to_bounds(viewport_size)
	var other_pid: int = NetworkManager.connected_peers[0] if _role == "host" else 1
	var remote: Node2D = _main._players[other_pid]
	var arrived := await _wait_until(func(): return remote.position.x > 1200 and absf(remote.position.y - 220) < 1, 6.0)
	_check("edge_arrived", arrived, str(remote.position))
	if arrived:
		# 等插值收敛到实际边界，再与本端可视范围比较。
		await _wait_seconds(0.35)
		_check("teammate_visible_at_edge", remote.position.x <= viewport_size.x - 24.0 + 1.0,
			"viewport=%s local_x=%.0f remote_x=%.0f" % [viewport_size, own.position.x, remote.position.x])
