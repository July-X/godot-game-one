extends "res://scripts/battle/main.gd"
## Exercise real paths. --capture=PATH renders a fixed crossing stress fixture; no change to game data.

class Target extends CharacterBody2D:
	var hits: Array[float] = []

	func take_damage(damage: float, _owner: int) -> void:
		hits.append(damage)


var _passed := 0
var _failed := 0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_run_probe.call_deferred()


func _make_shot(laser: bool, pos: Vector2, angle: float, friendly := true) -> Node2D:
	var shot: Node2D = _laser_scene.instantiate() if laser else Pool.acquire("bullet", _bullet_scene)
	add_child(shot)
	if laser:
		shot.setup(pos, angle, 5.0, 1)
	else:
		shot.setup(pos, angle, 5.0, friendly, 1, 600.0, 1)
	shot.set_physics_process(false)
	return shot


func _run_probe() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await _capture_fixture(arg.trim_prefix("--capture="))
			return
	var pos := Vector2(9, 120)
	var bullet := _make_shot(false, pos, PI)
	var enemy := _make_shot(false, pos + Vector2(0, 120), PI, false)
	var bolt := _make_shot(true, pos + Vector2(0, 240), PI)
	var direct := _make_shot(false, Vector2(320, 120), -PI / 2)
	var enemy_tint: Color = enemy._sprite.modulate
	var direct_texture: Texture2D = direct._sprite.texture
	bolt._line_points = PackedVector2Array([Vector2(90, 360), Vector2(45, 360)])
	bullet._physics_process(1.0 / 60.0)
	enemy._physics_process(1.0 / 60.0)
	bolt._physics_process(1.0 / 60.0)
	_check("ordinary bounces with unchanged position/direction/speed/lifetime",
		bullet._has_bounced and is_equal_approx(bullet.global_position.x, 10.0)
		and bullet._direction.is_equal_approx(Vector2.RIGHT) and is_equal_approx(bullet._speed, 780.0)
		and is_equal_approx(bullet._lifetime, 4.0 - 1.0 / 60.0))
	_check("bolt bounces with unchanged position/direction/speed/lifetime",
		bolt._has_bounced and is_equal_approx(bolt.global_position.x, -11.0)
		and bolt._direction.is_equal_approx(Vector2.RIGHT) and is_equal_approx(bolt._speed, 1200.0)
		and is_equal_approx(bolt._lifetime, 0.6 - 1.0 / 60.0))
	_check("only reflected friendly projectiles move behind enemy and Boss visual",
		bullet.z_index < -2 and bolt.z_index == bullet.z_index and enemy.z_index == 0 and direct.z_index == 0)
	_check("ordinary reflected core is short, cool and translucent",
		bullet._sprite.texture.get_size() == Vector2(3, 9) and bullet._sprite.modulate == Palette.FRIENDLY_RICOCHET
		and bullet._sprite.modulate.a < 0.65 and bullet._sprite.modulate.b > bullet._sprite.modulate.r)
	_check("enemy appearance untouched",
		not enemy._has_bounced and enemy._sprite.modulate == enemy_tint and enemy._sprite.texture != bullet._sprite.texture)
	_check("reflected bolt drops previous trail and stops recording",
		bolt._line_points.is_empty())
	bolt._physics_process(1.0 / 60.0)
	_check("no new reflected trail history", bolt._line_points.is_empty())
	_check("collision geometry and damage unchanged",
		bullet.get_node("CollisionShape2D").shape.radius == 3.0 and bullet._damage == 5.0
		and bolt.get_node("CollisionShape2D").shape.radius == 8.0 and bolt._damage == 5.0)
	var snapshot := _resume_bullets()
	_check("resume uses existing 11-field rows", snapshot.size() == 4 and snapshot[0].size() == 11)
	_restore_resume_bullets(snapshot)
	for shot: Node in get_tree().get_nodes_in_group("player_bullets"):
		if shot.is_queued_for_deletion():
			continue
		var is_bolt: bool = shot.scene_file_path == _laser_scene.resource_path
		if shot._has_bounced:
			_check("resume restores muted bolt" if is_bolt else "resume restores muted ordinary",
				shot._is_network_ghost and shot.z_index == Palette.FRIENDLY_RICOCHET_Z
				and is_equal_approx(shot._speed, 1200.0 if is_bolt else 780.0)
				and (shot._line_points.is_empty() if is_bolt else shot._sprite.modulate == Palette.FRIENDLY_RICOCHET))
		elif not is_bolt:
			_check("resume keeps unreflected appearance", shot.z_index == 0 and shot._sprite.texture == direct_texture)
	bullet.reset()
	_check("reset clears reflected style", not bullet._has_bounced and bullet.z_index == 0
		and bullet._sprite.texture == direct_texture and bullet._sprite.modulate == Palette.PLAYER_BULLET)
	_check("fresh spawn retains original style", direct._sprite.texture == direct_texture
		and direct._sprite.modulate == Palette.PLAYER_BULLET)
	await _verify_reflected_hit(false, 165.0)
	await _verify_reflected_hit(true, 445.0)
	await get_tree().create_timer(0.45).timeout
	print("[RICOCHET] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0 or _passed != 16))


func _verify_reflected_hit(laser: bool, y: float) -> void:
	GameState.game_running = true
	var shot := _make_shot(laser, Vector2(8, y), PI)
	shot._physics_process(1.0 / 60.0)
	var target := Target.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	target.add_child(shape)
	target.collision_layer = 4
	target.collision_mask = 0
	target.position = Vector2(50, y)
	target.add_to_group("enemies")
	add_child(target)
	shot.set_physics_process(true)
	for i in range(12):
		await get_tree().physics_frame
		if not target.hits.is_empty():
			break
	_check("original damage through live collision after bolt reflection" if laser
		else "original damage through live collision after ordinary reflection",
		target.hits == [5.0])
	target.queue_free()
	GameState.game_running = false


func _capture_fixture(path: String) -> void:
	# A seeded stress fixture, not a recording of live play. Use real projectile scenes/draw code.
	RenderingServer.set_default_clear_color(Color("#0a1223"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7823
	for i in range(18):
		var x := 234.0 + float(i) * 43.0
		for j in range(3):
			var enemy := _make_shot(false, Vector2(x + j * 9.0, 248.0 + j * 45.0 + sin(i * 0.53) * 52.0), PI / 2 - 0.22, false)
			enemy.modulate = Palette.ENEMY_BULLET_FAST if j < 2 else Palette.ENEMY_BULLET_MID
	for i in range(164):
		var is_bolt := i % 14 == 0
		var shot := _make_shot(is_bolt, Vector2(8 if i % 2 == 0 else 1274, 50), PI if i % 2 == 0 else 0.0)
		shot._physics_process(1.0 / 60.0)
		var angle := (0.64 if i % 2 == 0 else 2.5) + rng.randf_range(-0.48, 0.48)
		shot.global_position = Vector2(rng.randf_range(226, 1050), rng.randf_range(165, 499))
		shot.rotation = angle if is_bolt else angle + PI / 2
		if is_bolt:
			# Simulate the trail samples that would have accumulated during the flight.
			for j in range(12, 0, -1):
				if not shot.has_method("set_bounced"):
					shot._line_points.append(shot.global_position - Vector2.from_angle(angle) * j * 8)
			shot.queue_redraw()
	for i in range(42):
		_make_shot(false, Vector2(395.0 + (i % 2) * 486.0 + rng.randf_range(-18, 18),
			rng.randf_range(170, 506)), -PI / 2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[RICOCHET] capture=%s err=%d" % [path, err])
	get_tree().quit(int(err != OK))


func _check(label: String, ok: bool) -> void:
	print("[RICOCHET] ", label, " pass=", ok)
	_passed += int(ok)
	_failed += int(not ok)
