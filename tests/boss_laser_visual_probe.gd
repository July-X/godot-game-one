extends Node

const Boss = preload("res://scripts/boss.gd")
const Laser = preload("res://scripts/boss_ultimate_laser_visual.gd")
const BULLET := preload("res://scenes/entities/bullet.tscn")
const START := Vector2(123, 134)
const END := Vector2(471, 254)
const AGE := 0.89
const MID_TAPER_LEFT := 0.70
const DURATION := Boss.BOSS_ULTIMATE_LASER_TRAVEL + Boss.BOSS_ULTIMATE_LASER_HOLD_SECONDS
const OUTER := Boss.BOSS_ULTIMATE_LASER_WIDTH * 0.5
const INNER := OUTER * Boss.ULTIMATE_LASER_INNER_RATIO

class Pilot extends Node2D:
	var hp := 50
	func force_kill() -> void:
		hp = 0
	func take_damage(amount: int) -> void:
		hp -= amount

var _view := SubViewport.new()
var _world := Node2D.new()
var _boss: Boss
var _laser: Laser
var _passed := 0
var _failed := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BossLaserVisualProbe requires a graphical renderer")
		get_tree().quit(2)
		return
	_view.size = Vector2i(624, 368)
	_view.world_2d = World2D.new()
	_view.transparent_bg = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_world.position = Vector2(71, 33)
	_view.add_child(_world)
	_boss = preload("res://scenes/entities/boss.tscn").instantiate()
	_world.add_child(_boss)
	_boss.hide()
	_boss.set_physics_process(false)
	_boss._ultimate_laser_start = START
	_boss._ultimate_laser_end = END
	_boss._ultimate_laser_firing = true
	_laser = Laser.new()
	_world.add_child(_laser)
	_laser.setup_beam(START, END, Boss.BOSS_ULTIMATE_LASER_TRAVEL, Boss.BOSS_ULTIMATE_LASER_WIDTH, Boss.BOSS_ULTIMATE_LASER_HOLD_SECONDS)
	_laser.authority_boss = _boss

	_set_age(0.0)
	_check("zero_length_has_no_pixels", not (await _frame()).get_used_rect().has_area())
	_set_age(AGE)
	var advancing := await _frame()
	_check("advancing_uses_authority_age", is_equal_approx(_laser._age, _boss.get_laser_visual_age()))
	var tip := START.lerp(END, AGE / Boss.BOSS_ULTIMATE_LASER_TRAVEL)
	_check_capsule("advancing", advancing, tip)
	_check_damage(tip)
	await _check_foreground(tip)
	_set_age(DURATION - 2.1)
	var full := await _frame()
	_set_age(DURATION - 2.28)
	_check_plasma(full, await _frame())
	_set_age(DURATION - 1.40)
	var first_taper := await _frame()
	_set_age(DURATION - MID_TAPER_LEFT)
	var taper := await _frame()
	_set_age(DURATION - 0.04)
	var residual := await _frame()
	_check_capsule("late_hold", residual, END, true)
	await _check_shutdown(full, first_taper, taper, residual)
	_set_age(DURATION)
	var expired := await _frame()
	_capture("05-expired", expired)
	_check("expired_age_has_no_danger", not expired.get_used_rect().has_area())
	_check("finish_once", _laser.finish_beam() and not _laser.finish_beam())
	var ember := await _frame()
	_capture("06-tip-afterglow", ember)
	var ember_rect := ember.get_used_rect()
	_check("cooling_only_at_tip", ember_rect.has_area() and Rect2i(Vector2i(END) - Vector2i(6, 6),
		Vector2i(13, 13)).encloses(ember_rect))
	await get_tree().create_timer(0.30).timeout
	_check("cooling_releases_visual", not is_instance_valid(_laser) and not (await _frame()).get_used_rect().has_area())
	print("[LASER-VISUAL] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)

func _set_age(age: float) -> void:
	_boss._ultimate_laser_fire_timer = DURATION - age

func _frame() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return _view.get_texture().get_image()

func _check_shutdown(full: Image, first_taper: Image, taper: Image, residual: Image) -> void:
	var source := START.lerp(END, 0.14)
	var mid := START.lerp(END, 0.50)
	var tip := END
	var source_early := _opacity_at(first_taper, source) / _opacity_at(full, source)
	var mid_early := _opacity_at(first_taper, mid) / _opacity_at(full, mid)
	var mid_late := _opacity_at(taper, mid) / _opacity_at(full, mid)
	var tip_early := _opacity_at(first_taper, tip) / _opacity_at(full, tip)
	var tip_late := _opacity_at(taper, tip) / _opacity_at(full, tip)
	var tip_final := _opacity_at(residual, tip) / _opacity_at(full, tip)
	print("[LASER-VISUAL] source %.3f; middle %.3f -> %.3f; tip %.3f -> %.3f -> %.3f" %
		[source_early, mid_early, mid_late, tip_early, tip_late, tip_final])
	_check("source_fades_before_middle_and_tip", source_early < 0.25 and mid_early > 0.90 and tip_early > 0.90)
	_check("middle_fades_before_tip", mid_late < 0.25 and tip_late > 0.90)
	_check("tip_fades_last_before_cutoff", tip_final < 0.22)
	_check_capsule("mid_taper", taper, END, true)
	_check_damage(END)
	# The guest restores a mid-taper frame using the existing age, not a new
	# wind-down event. Compare actual emitted pixels, not just local age.
	_laser.authority_boss = null
	_laser.set_process(false)
	_laser.setup_beam(START, END, Boss.BOSS_ULTIMATE_LASER_TRAVEL, Boss.BOSS_ULTIMATE_LASER_WIDTH,
		Boss.BOSS_ULTIMATE_LASER_HOLD_SECONDS, DURATION - MID_TAPER_LEFT)
	_laser.queue_redraw()
	_check("remote_age_reconstructs_same_taper", (await _frame()).get_data() == taper.get_data())
	_laser.set_process(true)
	_laser.authority_boss = _boss
	_capture("01-full", full)
	_capture("02-early-taper", first_taper)
	_capture("03-mid-taper", taper)
	_capture("04-residual", residual)

func _opacity_at(frame: Image, point: Vector2) -> float:
	var total := 0.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := frame.get_pixelv(Vector2i(point) + Vector2i(dx, dy))
			total += c.a
	return total / 49.0

func _capture(label: String, frame: Image) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture":
		_check(label + "_saved", frame.save_png(args[1].path_join(label + ".png")) == OK)

func _check_plasma(full: Image, earlier: Image) -> void:
	var across := START.direction_to(END).orthogonal()
	var min_fringe := 1.0
	var max_fringe := 0.0
	var changed := 0
	var readable := true
	for i in range(1, 19):
		var center := START.lerp(END, float(i) / 20.0)
		for side in [-1.0, 1.0]:
			var fringe := Vector2i(center + across * (INNER + 12.0) * side)
			var rgb := full.get_pixelv(fringe)
			min_fringe = minf(min_fringe, rgb.a)
			max_fringe = maxf(max_fringe, rgb.a)
			changed += int(absf(earlier.get_pixelv(fringe).a - rgb.a) > 0.055)
			var hot := full.get_pixelv(Vector2i(center))
			readable = readable and hot.a > rgb.a + 0.20 and hot.g > rgb.g
	print("[LASER-VISUAL] fringe alpha %.3f..%.3f, changing pixels %d/36" % [min_fringe, max_fringe, changed])
	_check("plasma_varies_along_beam", max_fringe - min_fringe > 0.12)
	_check("plasma_flows_at_a_fixed_position", changed >= 9)
	_check("continuous_gold_core_outshines_fringe", readable)

func _check_capsule(label: String, frame: Image, tip: Vector2, fading := false) -> void:
	var axis := START.direction_to(END)
	var across := axis.orthogonal()
	for landmark in [[START, -axis, "source_cap"], [tip, axis, "tip_cap"],
			[START.lerp(tip, 0.5), across, "right_side"], [START.lerp(tip, 0.5), -across, "left_side"]]:
		var inner := frame.get_pixelv(Vector2i(landmark[0] + landmark[1] * (INNER - 6.0))).a
		var outer := frame.get_pixelv(Vector2i(landmark[0] + landmark[1] * (OUTER - 1.6))).a
		var beyond := frame.get_pixelv(Vector2i(landmark[0] + landmark[1] * (OUTER + 2.0))).a
		_check(label + "_" + landmark[2], inner > (0.14 if fading else 0.80)
			and outer >= 0.065 and outer <= 0.24 and inner > outer + 0.03 and beyond <= 0.01)
	var rect := frame.get_used_rect()
	var outside := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if frame.get_pixel(x, y).a > 0.05 and _boss._distance_to_beam_center(Vector2(x + 0.5, y + 0.5)) < 0.0:
				outside += 1
	_check(label + "_no_pixels_in_safe_area", outside == 0)

func _check_damage(tip: Vector2) -> void:
	var pilot := Pilot.new()
	_world.add_child(pilot)
	pilot.add_to_group("player")
	for row in [[INNER - 0.5, 0], [INNER + 0.5, 40], [OUTER - 0.5, 40], [OUTER + 0.5, 50]]:
		pilot.hp = 50
		pilot.global_position = tip + START.direction_to(END) * row[0]
		_boss._laser_dot_accumulator = 0
		_boss._apply_continuous_laser_damage(1.0)
		_check("tip_at_%.1f_receives_%d_damage" % [row[0], 50 - row[1]], pilot.hp == row[1])
	pilot.free()

func _check_foreground(tip: Vector2) -> void:
	var bullets: Array[Node2D] = []
	for center in [START.lerp(tip, 0.45), tip + START.direction_to(END) * 33.0]:
		var bullet := BULLET.instantiate() as Node2D
		_world.add_child(bullet)
		bullet.setup(center, PI * 0.5, 1.0, false, 1, 0.0)
		bullet.set_physics_process(false)
		bullets.append(bullet)
	var ship := Sprite2D.new()
	ship.texture = preload("res://assets/sprites/player/swift_p1.png")
	_world.add_child(ship)
	ship.global_position = START.lerp(tip, 0.65) + START.direction_to(tip).orthogonal() * 28.0
	ship.hide()
	_laser.hide()
	var bullets_only := await _frame()
	_laser.show()
	_check_opaque_pixels("opaque_enemy_bullets_stay_in_front", bullets_only, await _frame())
	for bullet in bullets:
		bullet.free()

	ship.show()
	_laser.hide()
	var ship_only := await _frame()
	_laser.show()
	_check_opaque_pixels("opaque_pilot_stays_in_front", ship_only, await _frame())
	ship.free()

func _check_opaque_pixels(label: String, before: Image, during: Image) -> void:
	var rect := before.get_used_rect()
	var count := 0
	var unchanged := true
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pixel := before.get_pixel(x, y)
			if pixel.a >= 0.999:
				count += 1
				unchanged = unchanged and pixel == during.get_pixel(x, y)
	_check(label, count > 20 and unchanged)

func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[LASER-VISUAL] %s pass=%s" % [label, ok])
