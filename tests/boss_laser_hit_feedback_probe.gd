extends Node
## Exercise production collision feedback at 60 Hz, 60 hits/s in three-hit bursts.
## Contacts are replayed deterministically through the actual bullet callback.
const MAIN := preload("res://scenes/main.tscn")
const BULLET := preload("res://scenes/entities/bullet.tscn")
const Boss := preload("res://scripts/boss.gd")
const DURATION := 60
const HIT_COUNT := 60
const CONTACT_DAMAGE := 0.25

var _main: Node
var _boss: Boss
var _failed := 0

func _ready() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func _run() -> void:
	seed(2417)
	_main = MAIN.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_main.set_process(false)
	_main._player.set_physics_process(false)
	_main._player.get_node("GrazeArea").monitoring = false
	_main._spawn_boss(5)
	_boss = _main._boss
	_boss._stop_entry_motion()
	_boss.set_physics_process(false)
	_boss.position = Vector2(640, 175)
	_boss._shield_hp = 0.0
	_boss._max_health = 1000.0
	_boss._health = 1000.0
	_boss._start_ultimate_laser()
	_check("charge_cue_kept", is_equal_approx(_main._camera_shake._trauma, _main.SHAKE_LASER_CHARGE))
	_boss._lock_ultimate_laser()
	_boss._fire_ultimate_laser()
	_boss._ultimate_laser_fire_timer -= 1.8
	_main._camera_shake.reset()
	var camera := _main.get_viewport().get_camera_2d()
	var peak := 0.0
	var peak_offset := 0.0
	var rest_frames := 0
	var bump_count := 0
	var last_moving := false
	var scaled_frames := 0
	var max_flash := 1.0
	var contact_fx_seen := false
	var end_hp := _boss._health - CONTACT_DAMAGE * Boss.BOSS_EXPOSED_DAMAGE_MULTIPLIER * HIT_COUNT
	for frame in range(DURATION):
		await get_tree().process_frame
		if frame == DURATION / 2:
			_boss._ultimate_laser_fire_timer = Boss.BOSS_ULTIMATE_LASER_HOLD_SECONDS - 0.05
			_boss._publish_attack_window()
		if frame % 3 == 0:
			for _burst in range(3):
				_strike()
		peak = maxf(peak, _main._camera_shake._trauma)
		peak_offset = maxf(peak_offset, camera.offset.length())
		var moving := camera.offset.length() > 0.05
		bump_count += int(moving and not last_moving)
		rest_frames += int(not moving)
		last_moving = moving
		scaled_frames += int(not _boss._sprite.scale.is_equal_approx(Vector2.ONE * Boss.BOSS_VISUAL_SCALE))
		max_flash = maxf(max_flash, _boss._sprite.modulate.r)
		contact_fx_seen = contact_fx_seen or Pool._active.values().has("hit_effect")
	print("[BOSS-HIT] fire peak_trauma=%.3f peak_offset=%.3f scaled_frames=%d rest_frames=%d bumps=%d max_flash=%.2f damage=%.3f" % [
		peak, peak_offset, scaled_frames, rest_frames, bump_count, max_flash, 1000.0 - _boss._health])
	_check("firing_light_camera_bump_without_trauma", is_zero_approx(peak) and peak_offset >= 0.8 and peak_offset <= 1.201)
	_check("hit_bumps_do_not_stack_or_fill_the_window", rest_frames >= 20 and bump_count >= 3 and bump_count <= 5)
	_check("firing_no_recoil", scaled_frames == 0)
	_check("firing_subtle_local_flash", max_flash > 1.0 and max_flash <= 1.20)
	_check("damage_unchanged", absf(end_hp - _boss._health) < 0.01)
	_check("localized_hit_particles_and_audio_kept", contact_fx_seen and SFX._combo > 0)
	_check("beam_visual_active", is_instance_valid(_main._boss_laser_visual) and _boss.get_attack_window() == Boss.AttackWindow.HOLD)
	_boss._finish_ultimate_laser()
	for i in range(12):
		await get_tree().process_frame
	_check("camera_returns_to_rest", camera.offset.is_zero_approx())
	_check("flash_returns_to_normal", _boss._sprite.modulate.is_equal_approx(Color.WHITE))
	_main._camera_shake.reset()
	_strike()
	_check("open_window_hit_shake_kept", is_equal_approx(_main._camera_shake._trauma, _main.SHAKE_HIT))
	_check("open_window_flash_and_recoil_kept", _boss._sprite.modulate.r > 1.5 and _boss._hit_recoil_tween != null)
	_boss._start_ultimate_laser()
	_check("charge_clears_active_recoil", _boss._hit_recoil_tween == null and _boss._sprite.scale.is_equal_approx(Vector2.ONE * Boss.BOSS_VISUAL_SCALE))
	_boss._shield_hp = 1.0
	_main._camera_shake.reset()
	_strike()
	_check("charging_shield_damage_without_stacked_shake", is_equal_approx(_boss._shield_hp, 0.75) and is_zero_approx(_main._camera_shake._trauma))
	_main._camera_shake.set_offset_limit(Vector2(0.0, 0.4))
	var margin_peak := 0.0
	var horizontal_peak := 0.0
	for i in range(8):
		await get_tree().process_frame
		margin_peak = maxf(margin_peak, absf(camera.offset.y))
		horizontal_peak = maxf(horizontal_peak, absf(camera.offset.x))
	_check("camera_stays_within_arena_margin", is_equal_approx(margin_peak, 0.4) and is_zero_approx(horizontal_peak))
	_main._camera_shake.reset()
	_main._camera_shake.add_trauma(_main.SHAKE_PLAYER_HURT)
	_main.add_boss_laser_hit_bump()
	_check("soft_hit_does_not_override_player_hurt", _main._camera_shake._soft_hit_left == 0.0 and _main._camera_shake._trauma > 0.0)
	_main._camera_shake.reset()
	_boss._is_network_ghost = true
	_boss.apply_network_attack_window(Boss.AttackWindow.HOLD - Boss.AttackWindow.OPEN)
	var impact := PackedFloat32Array([640.0, 175.0, Pool.Impact.BOSS_HULL])
	_main._rpc_sync_entity_positions(PackedFloat32Array(), impact)
	_check("replicated_laser_impact_uses_same_bump", _main._camera_shake._soft_hit_left > 0.0 and _main._camera_shake._trauma == 0.0)
	_main._camera_shake.reset()
	_boss.apply_network_attack_window(Boss.WINDOWS_PER_CYCLE)
	_main._rpc_sync_entity_positions(PackedFloat32Array(), impact)
	_check("replicated_open_window_does_not_add_bump", _main._camera_shake._soft_hit_left == 0.0)
	print("[BOSS-HIT] SUMMARY failed=%d" % _failed)
	get_tree().quit(1 if _failed else 0)

func _strike() -> void:
	var bullet := BULLET.instantiate()
	_main.add_child(bullet)
	bullet.setup(_boss.global_position, 0.0, CONTACT_DAMAGE, true, 1, 0.0)
	bullet.monitoring = false
	bullet._on_body_entered(_boss)

func _check(label: String, ok: bool) -> void:
	_failed += int(not ok)
	print("[BOSS-HIT] %s=%s" % [label, ok])
