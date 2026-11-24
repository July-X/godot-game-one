extends Node
## 固定同一构图。图形模式加 -- capture /目标目录/前缀 可保存四个时间点的真实渲染。

const MAIN := preload("res://scenes/main.tscn")
const PICKUP := preload("res://scenes/entities/powerup.tscn")
const HIT := preload("res://scenes/effects/hit_effect.tscn")
const GOLD_POS := Vector2(652, 465)
var _failed := 0
var _passed := 0
var _capture := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture":
		_capture = args[1]
	seed(20261120)
	var main = MAIN.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.set_process(false)
	var player: Node2D = main._player
	player.set_physics_process(false)
	player.position = Vector2(640, 440)
	player.reset_physics_interpolation()
	await get_tree().process_frame

	var bg: ColorRect = main._bg_color
	var rect := Rect2(bg.get_global_transform_with_canvas().origin, bg.size)
	_check("background_covers_viewport", rect.encloses(get_viewport().get_visible_rect()), str(rect))
	_check("deep_space_color", bg.color.to_html(false) == "0a1020", bg.color.to_html(false))
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		_check("desktop_no_joystick", main.get_node_or_null("MobileControls") == null)
	var board: Control = main._hud.get_node_or_null("LeaderboardPanel")
	_check("battle_leaderboard_hidden", board == null or not board.is_visible_in_tree())

	# 敌机、弹体和拾取都走生产场景。停住运动，保证两版只比较画面。
	for i in range(4):
		main._spawn_enemy_at(i % 3, Vector2(270 + 232 * i, 144 + 42 * (i % 2)))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		for j in range(9):
			var pos := Vector2(enemy.position.x - 82 + 20 * j, enemy.position.y + 54 + 9 * j)
			enemy._spawn_enemy_bullet(pos, 1.05, 1, 650, Color("#ff5940"))
	# 这枚慢弹与断环右侧相交，录帧能直接看出谁在上层。
	var shooter = get_tree().get_first_node_in_group("enemies")
	shooter._spawn_enemy_bullet(GOLD_POS + Vector2(20, 0), PI / 2, 1,
		shooter.SPEED_SLOW, preload("res://scripts/visuals/palette.gd").ENEMY_BULLET_SLOW)
	var enemy_shots := get_tree().get_nodes_in_group("enemy_bullets")
	for shot in enemy_shots:
		shot.set_physics_process(false)
	var powerup = PICKUP.instantiate()
	main.add_child(powerup)
	powerup.position = GOLD_POS
	powerup.setup("core")
	powerup.collect()
	powerup.collect()
	var hits_before := Pool._active.values().count("hit_effect")
	var hit = Pool.acquire("hit_effect", HIT)
	main.add_child(hit)
	hit.position = Vector2(290, 154)
	hit.start_ordinary_hit()
	_check("one_core_and_toast", Pool._active.values().count("core_pickup") == 1
		and main._hud._active_pickup_toasts.size() == 1)
	var toasts: Array = main._hud._active_pickup_toasts
	var toast: Label = toasts.front() if not toasts.is_empty() else null
	_check("core_text_below_enemy_bullet", toast != null and toast.get_canvas() == enemy_shots[0].get_canvas()
		and toast.z_index < enemy_shots[0].z_index)
	for node in Pool._active:
		if Pool._active[node] == "core_pickup" or node == hit:
			_check("effect_below_enemy_bullet", node.z_index < enemy_shots[0].z_index)

	await _frame("000")
	await get_tree().create_timer(0.075).timeout
	_check("spark_visible_at_75ms", is_instance_valid(hit) and not hit.is_queued_for_deletion())
	await _frame("090")
	await get_tree().create_timer(0.09).timeout
	_check("spark_released", Pool._active.values().count("hit_effect") == hits_before)
	_check("ring_still_visible", Pool._active.values().has("core_pickup"))
	await _frame("190")
	await get_tree().create_timer(0.16).timeout
	_check("ring_released", not Pool._active.values().has("core_pickup"))
	await _frame("end")

	var transient := Node2D.new()
	main.add_child(transient)
	var last_hit = Pool.acquire("hit_effect", HIT)
	transient.add_child(last_hit)
	last_hit.start()
	transient.free()
	_check("scene_exit_unregisters_effect", Pool._active.values().count("hit_effect") == hits_before)
	_check_ship_geometry(player)
	var panorama := main.get_node("Backdrop/Panorama") as TextureRect
	var cruise := panorama.texture
	main._enter_boss_fight_mode()
	var rift := panorama.texture
	main._exit_boss_fight_mode()
	_check("boss_returns_to_base", cruise != rift and panorama.texture == cruise)
	main._rpc_set_boss_bg(true)
	_check("peer_boss_backdrop_matches", panorama.texture == rift)
	main._rpc_set_boss_bg(false)
	_check("peer_returns_to_base", panorama.texture == cruise)
	main._hud._on_game_over(120, 1)
	var entries: Control = main._hud.get_node("GameOverPanel/VBox/LeaderboardEntries")
	_check("result_has_rankings", entries.is_visible_in_tree() and entries.get_child_count() >= 2)
	print("[VISUAL] VERDICT SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _check_ship_geometry(player: Node2D) -> void:
	var collider: CollisionShape2D = player.get_node("CollisionShape2D")
	_check("hull_collision", collider.position == Vector2(0, 8) and collider.shape.radius == 12)
	_check("engine_and_flash", player.get_node("EngineGlow").position == Vector2(0, 32)
		and player.get_node("MuzzleFlash").position == Vector2(0, -40))
	var muzzles_match := true
	for step in 8:
		player.rotation = step * TAU / 8.0
		var before := get_tree().get_nodes_in_group("player_bullets")
		player.get_node("CombatController")._shoot()
		var origins: Array[Vector2] = []
		for bullet in get_tree().get_nodes_in_group("player_bullets"):
			if not before.has(bullet):
				origins.append(player.to_local(bullet.global_position).round())
		muzzles_match = muzzles_match and origins == [Vector2(-12, -24), Vector2(12, -24)]
	_check("eight_opening_volley_angles", muzzles_match)
	GameState.level = 6
	player.get_node("FeedbackController").update_appearance()
	var tier_two: Texture2D = player.get_node("Sprite2D").texture
	var original: Texture2D = load("res://assets/sprites/player/variants/lv02.png")
	_check("second_tier_preserved", tier_two.get_image().get_data() == original.get_image().get_data())
	GameState.level = 1
	player.get_node("FeedbackController").update_appearance()


func _frame(label: String) -> void:
	if _capture.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_check("capture_" + label, img.save_png("%s-%s.png" % [_capture, label]) == OK)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[VISUAL] %s pass=%s %s" % [label, ok, detail])
