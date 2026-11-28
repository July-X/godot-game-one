extends Node
## 走标题单人入口。隔离一轮真实护盾，录下原混音和静音状态的引擎像素。

const Boss := preload("res://scripts/battle/enemies/boss/boss.gd")
var _battle: Node
var _boss: Boss
var _out := ""
var _first_tick := 0
var _passed := 0
var _failed := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("capture"):
		_out = args[args.find("capture") + 1]
	if args.has("mute"):
		AudioServer.set_bus_mute(0, true)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("Menu/BtnSingle").pressed.emit()
	await get_tree().scene_changed
	_battle = get_tree().current_scene
	_check("ordinary_title_entry", _battle.scene_file_path == "res://scenes/main.tscn")
	_battle._wave_director._cooldown = 90.0
	_battle._asteroid_timer = 90.0
	_battle._player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	seed(14813)
	_battle._spawn_boss(GameState.FIRST_BOSS_LEVEL)
	_boss = _battle._boss
	_boss._stop_entry_motion()
	_boss.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_boss.global_position = Vector2(640, 235)
	_boss.reset_physics_interpolation()
	_boss._shoot_timer = 90.0
	_boss._rush_cooldown = 90.0
	_boss._dodge_cooldown = 90.0
	_battle._player.global_position = Vector2(640, 550)
	_battle._player.reset_physics_interpolation()
	_first_tick = Engine.get_physics_frames()
	await _ticks(45)
	var shielded := await _sample("shielded")
	var hull := _boss.get_network_health()
	_shoot(_boss.get_shield_hp())
	var opened := await _until(_boss.is_shield_exposed, 60)
	_check("real_shot_breaks_only_shield", opened and _boss.get_network_health() == hull)
	await _ticks(3)
	var shattered := await _sample("shattered")
	await _ticks(60)
	var exposed := await _sample("exposed")
	_check("sustained_exposure_has_no_caption_or_marker", _boss.is_shield_exposed()
		and _battle._hud._boss_status_phase.text.is_empty() and not _boss.first_boss_lock_visible())
	_shoot(4.0)
	_check("real_exposed_hit_consumes_hull", await _until(func(): return _boss.get_network_health() < hull, 45))
	_check("authoritative_recharge_phase", await _until(_boss.is_shield_recharging, 300))
	await _ticks(5)
	var recharge := await _sample("recharge")
	_check("charging_keeps_shield_bar_empty_without_caption", _boss.is_shield_recharging()
		and _battle._hud._boss_shield_fill.size.x == 0.0 and _battle._hud._boss_status_phase.text.is_empty())
	await _ticks(18)
	var drawing_changed := await _sample("recharge-later")
	_check("returns_to_actual_shield", await _until(_boss.has_impact_shield, 75))
	var restored := await _sample("restored")
	if DisplayServer.get_name() != "headless":
		_check("visible_closed_ring_at_both_raised_samples", shielded.ring >= 21 and restored.ring >= 21)
		_check("visible_outward_break_then_open_core", shattered.shards > 6 and exposed.ring <= 3 and exposed.core > 4)
		_check("visible_recharge_arcs_move_without_closing", recharge.ring <= 3 and drawing_changed.ring <= 3
			and recharge.arc >= 10 and drawing_changed.arc >= 10 and recharge.art != drawing_changed.art)
	await _ticks(52)
	print("[FIRST BOSS AV] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _shoot(amount: float) -> void:
	_battle._player._combat._spawn_bullet(_boss.global_position + Vector2(0, 61), -PI * 0.5,
		ceili(amount), true, 1, 900.0)

func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _until(condition: Callable, count: int) -> bool:
	for i in count:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false

func _sample(label: String) -> Dictionary:
	await get_tree().process_frame
	var stamp := _boss.get_shield_stamp()
	var tick := Engine.get_physics_frames()
	print("[FIRST BOSS AV] %s tick=%d elapsed=%d stamp=%d shield=%.1f hull=%.1f art=%.3f mute=%s" % [
		label, tick, tick - _first_tick, stamp, _boss.get_shield_hp(), _boss.get_network_health(),
		_boss._recharge_art_age, AudioServer.is_bus_mute(0)])
	if DisplayServer.get_name() == "headless":
		return {}
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	if not _out.is_empty():
		_check("saved_" + label, frame.save_png(_out.path_join(label + ".png")) == OK)
	var transform := _boss.get_global_transform_with_canvas()
	print("[FIRST BOSS AV] center %s x=%.2f y=%.2f" % [label, transform.origin.x, transform.origin.y])
	var ring := _cold_samples(frame, transform, 72.0, 0, 24)
	var shards := _cold_samples(frame, transform, 79.0, 0, 32) + _cold_samples(frame, transform, 82.0, 0, 32)
	var arc := 0
	for side in 4:
		var travel := fposmod(_boss._recharge_art_age / 0.52 + float(side % 2) * 0.48, 1.0)
		var radius := lerpf(91.0, 75.0, travel)
		var center := side * TAU * 0.25 + PI * 0.25
		for offset in [-0.14, 0.0, 0.14]:
			arc += int(_cold_near(frame, transform * (Vector2.from_angle(center + offset) * radius)))
	var core := 0
	for y in range(-8, 3, 2):
		var tone := frame.get_pixelv(Vector2i((transform * Vector2(0, y)).round()))
		core += int(tone.r > 0.64 and tone.r - tone.b > 0.23 and tone.g > 0.42)
	print("[FIRST BOSS AV] pixels %s ring=%d shards=%d arcs=%d core=%d" % [label, ring, shards, arc, core])
	return {"ring": ring, "shards": shards, "arc": arc, "core": core, "art": _boss._recharge_art_age}

func _cold_samples(frame: Image, transform: Transform2D, radius: float, offset: float, count: int) -> int:
	var colored := 0
	for i in count:
		var at := transform * (Vector2.from_angle(offset + float(i) * TAU / count) * radius)
		colored += int(_cold_near(frame, at))
	return colored

func _cold_near(frame: Image, at: Vector2) -> bool:
	for dx in [-2, 0, 2]:
		for dy in [-2, 0, 2]:
			var pixel := frame.get_pixelv(Vector2i(at.round()) + Vector2i(dx, dy))
			if pixel.b > 0.33 and pixel.g > 0.24 and pixel.b - pixel.r > 0.10:
				return true
	return false

func _check(label: String, passed: bool) -> void:
	_passed += int(passed)
	_failed += int(not passed)
	print("[FIRST BOSS AV] %s pass=%s" % [label, passed])
