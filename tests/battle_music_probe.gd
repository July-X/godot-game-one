extends Node

var _passed := 0
var _failed := 0

func _ready() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	BGM.play_bgm()
	var settled := await _wait_for_full_gain()
	var player: AudioStreamPlayer = BGM._bgm_player
	_check("one_cruise_voice", BGM.get_child_count() == 1 and player.max_polyphony == 1
		and player.playing and player.stream == BGM._cruise and settled,
		"players=%d playing=%s cruise=%s gain=%.3f" % [BGM.get_child_count(), player.playing, player.stream == BGM._cruise, BGM._track_gain])
	var playback := player.get_stream_playback()
	BGM.play_bgm()
	_check("duplicate_phase_keeps_cursor", player.get_stream_playback() == playback)

	BGM.play_boss_bgm()
	# 固定推进淡出的一部分，避免宿主一帧抖动跨过真正切流的边界。
	BGM._transition.pause()
	BGM._transition.custom_step(BGM.FADE_OUT * 0.5)
	var partial_fade: bool = BGM._track_gain > 0.0 and BGM._track_gain < 1.0
	BGM.play_bgm()
	settled = await _wait_for_full_gain()
	_check("interrupted_switch_recovers_without_restart", partial_fade and player.get_stream_playback() == playback
		and player.stream == BGM._cruise and settled,
		"same_voice=%s gain=%.3f" % [player.get_stream_playback() == playback, BGM._track_gain])
	BGM.play_boss_bgm()
	settled = await _wait_for_full_gain()
	_check("boss_has_its_own_loop", player.stream == BGM._boss and player.playing and settled)
	for loop: AudioStreamWAV in [BGM._cruise, BGM._boss]:
		var stage := "cruise" if loop == BGM._cruise else "boss"
		_check(stage + "_whole_loop", loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_begin == 0
			and loop.loop_end == 641455 and loop.mix_rate == 44100 and loop.stereo)

	player.seek(player.stream.get_length() - 0.28)
	await _wait(0.07)
	playback = player.get_stream_playback()
	await _wait(0.46)
	var position := player.get_playback_position()
	_check("engine_loops_without_new_voice", player.playing and player.get_stream_playback() == playback
		and position > 0.0 and position < 0.75, "position=%.3f" % position)

	var warning_gain: float = SFX._warning_voice.volume_db
	var hurt_gain: float = SFX._hurt_voice.volume_db
	SFX.play_boss_warning()
	await _wait(0.09)
	_check("laser_warning_ducks_music", SFX._warning_voice.playing and player.volume_db < -5.8)
	SFX.play_player_hurt()
	_check("priority_sfx_stays_at_original_gain", SFX._hurt_voice.playing
		and SFX._warning_voice.volume_db == warning_gain and SFX._hurt_voice.volume_db == hurt_gain)
	await _wait(0.27)
	_check("overlap_does_not_end_duck_early", player.volume_db < -5.8)
	await _wait(0.55)
	_check("full_music_level_restored", absf(player.volume_db) < 0.01)
	SFX.play_player_hurt()
	await _wait(0.07)
	_check("player_damage_also_ducks_music", player.volume_db < -5.8)
	BGM.play_bgm()
	BGM.stop_bgm()
	await _wait(0.62)
	_check("stop_cancels_both_pending_fades", not player.playing and BGM._target_stream == null and BGM._duck_db == 0.0)
	print("[MUSIC] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _wait_for_full_gain() -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while BGM._transition.is_running() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return is_equal_approx(BGM._track_gain, 1.0)

func _check(name: String, ok: bool, detail := "") -> void:
	print("[MUSIC] %s pass=%s %s" % [name, ok, detail])
	_passed += int(ok)
	_failed += int(not ok)
