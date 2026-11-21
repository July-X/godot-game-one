extends Node
## 固定开火帧及接触帧。目标与危险弹走正式场景，截图只读完成绘制的视口。
const MAIN := preload("res://scenes/main.tscn")
const HIT := preload("res://scenes/effects/hit_effect.tscn")
const BURST := preload("res://scripts/explosion.gd")
const PALETTE := preload("res://scripts/palette.gd")
const CENTERS := [Vector2(640, 300), Vector2(571, 277), Vector2(632, 258), Vector2(696, 283)]
const CONTACTS := [32, 64, 94, 97, 100, 103, 106, 109]
const TARGETS := [0, 0, 1, 2, 3, 1, 2, 3]
const LAST_FRAME := 139
var main
var player
var targets := []
var bolts := {}
var tick := -1
var hits := 0
var deaths := 0
var failed := 0
var checks := 0
var live_fx := []
var capture := ""
var trace: FileAccess
var args := OS.get_cmdline_user_args()

func _ready() -> void:
	set_process(false)
	call_deferred("_start")

func _start() -> void:
	seed(20261121)
	main = MAIN.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	main.set_process(false)
	player = main._player
	player.position = Vector2(640, 494)
	player.set_physics_process(false)
	player.collision_layer = 0
	player.get_node("GrazeArea").monitoring = false
	player.get_node("PickupArea").monitoring = false
	for i in CENTERS.size():
		var target = main._spawn_enemy_at(i % 3, CENTERS[i])
		target.health = 2
		target.drop_chance = 0
		target.set_physics_process(false)
		target.collision_layer = 0
		target.get_node("Hitbox").monitorable = false
		targets.append(target)
	main.child_entered_tree.connect(_track_effect)
	if args.has("capture"):
		capture = args[args.find("capture") + 1]
		trace = FileAccess.open(capture.path_join("frames.jsonl"), FileAccess.WRITE)
		if trace == null:
			push_error("Cannot write capture directory: " + capture)
			get_tree().quit(1)
			return
		RenderingServer.frame_post_draw.connect(_capture_frame)
	set_process(true)

func _track_effect(node: Node) -> void:
	if node.scene_file_path == HIT.resource_path:
		hits += 1
	elif node.get_script() == BURST:
		deaths += 1
	else:
		return
	live_fx.append(node)
	node.tree_exiting.connect(func(): live_fx.erase(node), CONNECT_ONE_SHOT)
	if args.has("off"):
		node.modulate.a = 0

func _contact_point(target: Node2D) -> Vector2:
	var collider: CollisionShape2D = target.get_node("CollisionShape2D")
	return collider.global_position + collider.global_position.direction_to(player.position) * collider.shape.radius

func _fire(i: int) -> void:
	var point := _contact_point(targets[TARGETS[i]])
	var dir: Vector2 = player.position.direction_to(point)
	player.rotation = dir.angle() + PI / 2
	var muzzle: Vector2 = player.position + dir * 24
	var gun = player.get_node("CombatController")
	gun._show_muzzle_flash()
	SFX.play_shoot()
	gun._spawn_bullet(muzzle, dir.angle(), 1, true, 1, muzzle.distance_to(point) * 60 / 15)
	bolts[i] = get_tree().get_nodes_in_group("player_bullets").back()

func _crossing(i: int) -> void:
	var target = targets[TARGETS[i]]
	var through: Vector2 = target.position if i == 1 or i >= 5 else _contact_point(target)
	# 让同一颗危险弹在生效后第二帧穿过火花或机体中心，位置由正式物理帧推进。
	var speed := 240.0
	var step: float = speed * target.bullet_speed_mult / 60.0
	target._spawn_enemy_bullet(through - Vector2(20 * step, 0), 0, 1, speed, PALETTE.ENEMY_BULLET_MID)
	if args.has("hide-bullets"):
		get_tree().get_nodes_in_group("enemy_bullets").back().hide()

func _process(_delta: float) -> void:
	tick += 1
	for i in CONTACTS.size():
		var until: int = CONTACTS[i] - tick
		match until:
			18: _crossing(i)
			15: _fire(i)
			0:
				var target = targets[TARGETS[i]]
				var point := _contact_point(target)
				bolts[i].global_position = point
				bolts[i]._on_body_entered(target)
				var hit = live_fx.back()
				_check("contact_%d" % tick, hit.scene_file_path == HIT.resource_path and hit.global_position.is_equal_approx(point))
				bolts.erase(i)
	if tick == LAST_FRAME + 1:
		_check("eight_contacts_four_kills", hits == 8 and deaths == 4)
		_check("all_released", live_fx.is_empty() and not Pool._active.values().has("hit_effect"))
		var fx = Pool.acquire("hit_effect", HIT)
		main.add_child(fx)
		fx.start()
		fx._process(0.06)
		fx.start_shield_hit()
		_check("restart_shield", fx._shield_hit and not fx._core_pickup and fx._age == 0)
		fx.start_core_pickup()
		_check("restart_core", fx._core_pickup and not fx._shield_hit and fx._duration == 0.30)
		fx.start()
		_check("restart_ordinary", not fx._core_pickup and not fx._shield_hit and fx._duration == 0.10 and fx._age == 0)
		fx._process(0.10)
		_check("expired_unregistered", fx.is_queued_for_deletion() and not Pool._active.has(fx) and not fx.visible)
		set_process(false)
		if DisplayServer.get_name() != "headless":
			await _check_restarted_pixels()
		print("[PixelFX] SUMMARY pass=%d failed=%d" % [checks - failed, failed])
		get_tree().quit(1 if failed else 0)

func _check_restarted_pixels() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(128, 64)
	canvas.world_2d = World2D.new()
	canvas.transparent_bg = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(canvas)
	var reused = HIT.instantiate()
	reused.position = Vector2(32, 32)
	canvas.add_child(reused)
	reused.start()
	reused.set_process(false)
	await RenderingServer.frame_post_draw
	for method in ["start_shield_hit", "start_core_pickup", "start"]:
		var fresh = HIT.instantiate()
		fresh.position = Vector2(96, 32)
		canvas.add_child(fresh)
		for fx in [reused, fresh]:
			fx.call(method)
			fx.set_process(false)
			fx._process(0.035)
		await RenderingServer.frame_post_draw
		var picture := canvas.get_texture().get_image()
		var left := picture.get_region(Rect2i(0, 0, 64, 64))
		var right := picture.get_region(Rect2i(64, 0, 64, 64))
		_check("same_pixels_as_fresh_" + method, left.get_used_rect().has_area() and left.get_data() == right.get_data())
		if not capture.is_empty() and left.save_png(capture.path_join(method + ".png")) != OK:
			_check("write_restart_" + method, false)
		fresh.free()
	canvas.queue_free()

func _capture_frame() -> void:
	if tick < 0 or tick > LAST_FRAME:
		return
	var picture := get_viewport().get_texture().get_image()
	if picture.save_png(capture.path_join("frame_%03d.png" % tick)) != OK:
		push_error("Cannot write frame %d" % tick)
		get_tree().quit(1)
	var shots := []
	for bullet in get_tree().get_nodes_in_group("enemy_bullets"):
		var p: Vector2 = bullet.get_global_transform_with_canvas().origin
		shots.append([p.x, p.y])
	var effects := []
	for fx in live_fx:
		var p: Vector2 = fx.get_global_transform_with_canvas().origin
		effects.append(["hit" if fx.scene_file_path == HIT.resource_path else "death", p.x, p.y])
	trace.store_line(JSON.stringify([tick, shots, effects], "", false, true))

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[PixelFX] " + label)
