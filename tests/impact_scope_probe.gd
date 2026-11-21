extends Node
## Start the actual combat event first, then isolate its emitted CanvasItem at the same age.
const MAIN := preload("res://scenes/main.tscn")
const BULLET := preload("res://scenes/entities/bullet.tscn")
const LASER := preload("res://scenes/entities/laser_bolt.tscn")
const MISSILE := preload("res://scenes/entities/homing_missile.tscn")
const HIT := "res://scenes/effects/hit_effect.tscn"
const REFS := "res://deliverables/pixelfx/reference/"
const POINT := Vector2(640, 360)
var main
var canvas := SubViewport.new()
var failed := 0
var passed := 0
var args := OS.get_cmdline_user_args()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ImpactScopeProbe requires a graphical renderer")
		get_tree().quit(2)
		return
	if args.has("anchors"):
		await _anchors()
		return
	seed(1121)
	main = MAIN.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	main.set_process(false)
	var player = main._player
	player.set_physics_process(false)
	player.position = POINT
	canvas.size = Vector2i(64, 64)
	canvas.world_2d = World2D.new()
	canvas.transparent_bg = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(canvas)
	var before := GameState.get_current_health(player.peer_id)
	player.take_damage(GameState.get_shield_layers(player.peer_id) + 1)
	var after := GameState.get_current_health(player.peer_id)
	_check("player_damage", before - after == 1)
	print("[scope] HP ", before, " -> ", after)
	await _sample("player", "legacy-0939598")
	# 玩家上一帧已进入无敌窗，只留下敌弹接触本身的第二个调用点。
	var enemy_shot = BULLET.instantiate()
	main.add_child(enemy_shot)
	enemy_shot.setup(POINT, 0.0, 1, false, 1, 660)
	enemy_shot._on_body_entered(player)
	await _sample("enemy_bullet", "legacy-0939598")
	var asteroid = preload("res://scenes/entities/asteroid.tscn").instantiate()
	main.add_child(asteroid)
	asteroid.position = POINT
	asteroid.set_physics_process(false)
	var stone_shot = BULLET.instantiate()
	main.add_child(stone_shot)
	stone_shot.setup(POINT, 0.0, 1, true, 1, 660)
	asteroid._on_area_entered(stone_shot)
	asteroid.queue_free()
	await _sample("asteroid", "legacy-0939598")
	var mob = main._spawn_enemy_at(0, POINT)
	var elite = preload("res://scenes/entities/elite.tscn").instantiate()
	var boss = preload("res://scenes/entities/boss.tscn").instantiate()
	for target in [elite, boss]:
		main.add_child(target)
		target.position = POINT
	boss.setup(5)
	for target in [mob, elite, boss]:
		target.set_physics_process(false)
	mob.health = 100
	await _weapon(BULLET, elite, "shield", "shield-0939598")
	await _weapon(LASER, elite, "laser_shield", "legacy-0939598")
	elite.apply_network_shield(0, elite.get_network_max_shield())
	for row in [[BULLET, mob, "bullet_mob"], [LASER, mob, "laser_mob"], [MISSILE, mob, "missile_mob"],
			[BULLET, elite, "bullet_elite"], [LASER, boss, "laser_boss"], [MISSILE, elite, "missile_elite"],
			[BULLET, boss, "bullet_boss"]]:
		await _weapon(row[0], row[1], row[2], "ordinary-3681e25" if row[1] == mob else "legacy-0939598")
	var splash = BULLET.instantiate()
	main.add_child(splash)
	splash.position = POINT
	splash._splash_radius = 80.0
	splash.set_physics_process(false)
	for target in [mob, boss]:
		splash._splash_damage([target])
		await _sample("splash_mob" if target == mob else "splash_boss",
				"ordinary-3681e25" if target == mob else "legacy-0939598")
	print("[scope] SUMMARY pass=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _anchors() -> void:
	var world := Node2D.new()
	world.position = Vector2(62, 41)
	world.scale = Vector2(1.1, 0.9)
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	canvas.size = Vector2i(512, 288)
	canvas.world_2d = world.get_world_2d()
	canvas.transparent_bg = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(canvas)
	var target := Node2D.new()
	world.add_child(target)
	for entry in [
		["legacy-left", Vector2(154, 128), Pool.Impact.LEGACY],
		["legacy-right", Vector2(413, 200), Pool.Impact.LEGACY],
		["shield", Vector2(206, 151), Pool.Impact.SHIELD],
		["atlas", Vector2(390, 184), Pool.Impact.ORDINARY_ENEMY],
	]:
		var label: String = entry[0]
		var contact: Vector2 = entry[1]
		var lit := 0
		var misplaced := 0
		var expired := true
		target.global_position = contact
		for frame in 16:
			await get_tree().process_frame
			if frame == 0:
				Pool.spawn_hit(target.global_position, entry[2])
			target.global_position += Vector2(3, -2)
			# Move the view without resetting the spawned particle's interpolation.
			canvas.canvas_transform = Transform2D(0, Vector2(-frame * 2, frame))
			await RenderingServer.frame_post_draw
			var picture := canvas.get_texture().get_image()
			var bounds := picture.get_used_rect()
			var point := Vector2i(canvas.canvas_transform * contact)
			if bounds.has_area():
				lit += 1
				var allowed := Rect2i(point - Vector2i(17, 17), Vector2i(35, 35))
				misplaced += int(not allowed.encloses(bounds))
				expired = expired and frame < 13
			print("[anchor] %s,%d,%d,%d,%d,%d,%d,%d" % [
				label, frame, point.x, point.y, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y])
			if args.size() >= 2 and frame in [0, 1, 5, 11, 15]:
				if picture.save_png(args[1].path_join("%s-%02d.png" % [label, frame])) != OK:
					_check(label + "_capture", false)
		_check(label + "_position", lit >= 10 and misplaced == 0)
		_check(label + "_released", expired and not Pool._active.values().has("hit_effect"))
	print("[scope] SUMMARY pass=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _weapon(scene: PackedScene, target: Node2D, label: String, reference: String) -> void:
	var shot = scene.instantiate()
	main.add_child(shot)
	shot.position = POINT
	shot._on_body_entered(target)
	await _sample(label, reference)

func _sample(label: String, reference: String) -> void:
	var hits: Array = main.get_children().filter(func(n): return n.scene_file_path == HIT)
	_check(label + "_origin", hits.size() == 1 and hits[0].global_position == POINT)
	if hits.size() != 1:
		return
	var fx = hits[0]
	fx.reparent(canvas, false)
	fx.position = Vector2(32, 32)
	fx.reset_physics_interpolation()
	fx.set_process(false)
	fx._process(0.035)
	await RenderingServer.frame_post_draw
	var picture := canvas.get_texture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	if args.size() > 1:
		_check(label + "_capture", picture.save_png(args[1].path_join(label + ".png")) == OK)
	print("[scope] ", label, " age=", fx._age, " rect=", picture.get_used_rect())
	if not args.has("record"):
		var golden := Image.load_from_file(REFS + reference + ".png")
		_check(label + "_pixels", golden != null and golden.get_data() == picture.get_data())
	fx.free()

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("[scope] " + label)
