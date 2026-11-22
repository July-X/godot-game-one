extends "res://tests/lan_probe.gd"

const ROUND_RADIUS := 92.0
const P1_SCORE := 1234567890123456789
const P2_SCORE := 2345678901234567890

func _process(_delta: float) -> void:
	pass

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(1600 if args.has("wide") else 1280, 720)
	get_window().content_scale_size = size
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var desktop := args.has("desktop")
	if _role in ["host", "client"]:
		var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
		if err != OK or not await _wait_until(NetworkManager.is_online, 7):
			_finish_after_error("peers_connected")
			return
	_enter_main_scene()
	_main._wave_director._cooldown = INF
	_main._asteroid_timer = INF
	if not desktop:
		_main._spawn_mobile_controls()
		_main._hud._update_platform_hints()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var online := NetworkManager.is_online()
	if online and not await _wait_until(_cond_both_players, 5):
		_finish_after_error("two_pilots")
		return
	var viewport := get_viewport().get_visible_rect()
	var hud = _main._hud
	hud._layout_in_safe_area(viewport)
	if _role != "client":
		GameState.add_score(1000 if desktop else P1_SCORE, 1)
		if online:
			GameState.add_score(P2_SCORE, NetworkManager.connected_peers[0])
		_main._spawn_boss(5)
	var expected_total := P1_SCORE + P2_SCORE if online else 1000 if desktop else P1_SCORE
	var synced := await _wait_until(func():
		return (GameState.score == expected_total and is_instance_valid(hud._boss_status_root)
			and hud._boss_status_root.visible), 4)
	if not synced:
		_finish_after_error("boss_and_authoritative_scores_visible")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_check_profile("live_score_change", viewport, viewport, desktop)
	var profiles := {
		"round": viewport,
		"cutout_left": viewport.grow_individual(-76, -8, -6, -8),
		"cutout_right": viewport.grow_individual(-6, -8, -76, -8),
		"cutout_top": viewport.grow_individual(-12, -43, -12, -8),
	}
	var capture := args.find("capture")
	if capture >= 0 and capture + 1 < args.size() and DisplayServer.get_name() != "headless":
		_add_corner_mask(viewport)
	for name: String in profiles:
		var safe: Rect2 = profiles[name]
		hud._layout_in_safe_area(safe)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_profile(name, safe, viewport, desktop)
		if capture >= 0 and capture + 1 < args.size() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			_check("capture_" + name, image.save_png(args[capture + 1].path_join(name + ".png")) == OK, "")
	if online:
		await _wait_seconds(0.65)
	get_tree().quit(_summarize())

func _check_profile(profile: String, safe: Rect2, viewport: Rect2, desktop: bool) -> void:
	var hud = _main._hud
	var local_right := _role != "client"
	var score: Rect2 = hud._score_label.get_global_rect()
	var old_edge := safe.end.x - 18.0 if local_right else safe.position.x + 18.0
	var old_y := safe.position.y + (75.0 if NetworkManager.is_online() else 12.0)
	var edge := score.end.x if local_right else score.position.x
	var detail := "%s rect=%s edge=%.1f y=%.1f" % [profile, score, edge, score.position.y]
	if desktop:
		_check(profile + "_desktop_original_score_anchor", is_equal_approx(edge, old_edge)
			and is_equal_approx(score.position.y, old_y) and score.size.x == 198.0, detail)
		return
	var ideal_edge := minf(old_edge, viewport.end.x - 40.0) if local_right else maxf(old_edge, viewport.position.x + 40.0)
	var ideal_y := maxf(old_y, viewport.position.y + 32.0)
	_check(profile + "_edge_and_safe_area_use_stricter_bound", is_equal_approx(edge, ideal_edge)
		and is_equal_approx(score.position.y, ideal_y), detail)
	var corner := Vector2(viewport.end.x if local_right else viewport.position.x, viewport.position.y)
	var dx := maxf(0.0, ROUND_RADIUS - absf(corner.x - edge))
	var dy := maxf(0.0, ROUND_RADIUS - (score.position.y - corner.y))
	_check(profile + "_full_text_rect_inside_simulated_round_corner",
		Vector2(dx, dy).length() <= ROUND_RADIUS, "radius=%.1f distance=%.1f" % [ROUND_RADIUS, Vector2(dx, dy).length()])
	var boss: Rect2 = hud._boss_status_root.get_global_rect()
	var labels: Array[Label] = [hud._score_label, hud._level_label, hud._phase_label, hud._player_scores_label]
	var fits := true
	for label: Label in labels:
		if not label.visible:
			continue
		var box := label.get_global_rect()
		var font_width := label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		var bound := box.end.x if local_right else box.position.x
		fits = fits and safe.encloses(box) and is_equal_approx(bound, ideal_edge)
		fits = fits and not boss.intersects(box) and font_width <= box.size.x + 1.0
	_check(profile + "_long_score_lines_fit_and_clear_boss_bar", fits, hud._score_label.text + " / " + hud._player_scores_label.text)
	if NetworkManager.is_online():
		_check(profile + "_both_19_digit_peer_scores_visible", hud._player_scores_label.visible
			and hud._player_scores_label.text.contains(str(P1_SCORE))
			and hud._player_scores_label.text.contains(str(P2_SCORE)), str(hud._player_scores_label.size))

func _add_corner_mask(viewport: Rect2) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	for right in [false, true]:
		var corner := Vector2(viewport.end.x if right else viewport.position.x, viewport.position.y)
		var center := corner + Vector2(-ROUND_RADIUS if right else ROUND_RADIUS, ROUND_RADIUS)
		var from := -PI * 0.5 if right else PI
		var points := PackedVector2Array([corner])
		for i in 25:
			points.append(center + Vector2.from_angle(from + float(i) * PI / 48.0) * ROUND_RADIUS)
		var clip := Polygon2D.new()
		clip.color = Color.BLACK
		clip.polygon = points
		layer.add_child(clip)

func _finish_after_error(label: String) -> void:
	_check(label, false, "")
	get_tree().quit(_summarize())
