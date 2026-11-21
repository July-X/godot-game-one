extends Node
## 一条音乐声部。换段先淡出再切流，预警衰减与换段的音量分别计算。

const FADE_OUT := 0.16
const FADE_IN := 0.34
const DUCK_DB := -6.0
const DUCK_ATTACK := 0.025
const DUCK_RELEASE := 0.32

var _cruise: AudioStreamWAV
var _boss: AudioStreamWAV
var _bgm_player: AudioStreamPlayer
var _target_stream: AudioStreamWAV
var _transition: Tween
var _duck: Tween
var _track_gain := 0.0
var _duck_db := 0.0
var _duck_hold := 0.0

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.max_polyphony = 1
	add_child(_bgm_player)
	_update_volume()
	_cruise = _load_loop("res://assets/audio/cruise-softlead-loop.wav")
	_boss = _load_loop("res://assets/audio/boss-softlead-loop.wav")
	SFX.priority_cue.connect(_duck_for)

func _load_loop(path: String) -> AudioStreamWAV:
	# 循环标记只属于战斗音乐播放器，避免修改同一资源的共享状态。
	var stream := ResourceLoader.load(path, "AudioStreamWAV", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream

func play_bgm() -> void:
	_select(_cruise)

func play_boss_bgm() -> void:
	_select(_boss)

func _select(stream: AudioStreamWAV) -> void:
	if _target_stream == stream:
		return
	_target_stream = stream
	if _transition:
		_transition.kill()
	_transition = create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _bgm_player.playing and _bgm_player.stream != stream:
		_transition.tween_method(_set_track_gain, _track_gain, 0.0, FADE_OUT)
		_transition.tween_callback(_play_stream.bind(stream))
		_transition.tween_method(_set_track_gain, 0.0, 1.0, FADE_IN)
	else:
		if not _bgm_player.playing:
			_play_stream(stream)
		_transition.tween_method(_set_track_gain, _track_gain, 1.0, FADE_IN)

func _play_stream(stream: AudioStreamWAV) -> void:
	_bgm_player.stop()
	_bgm_player.stream = stream
	_bgm_player.play()

func _duck_for(duration: float) -> void:
	if _target_stream == null:
		return
	var remaining := 0.0
	if _duck and _duck.is_running():
		remaining = _duck_hold + DUCK_ATTACK - _duck.get_total_elapsed_time()
		_duck.kill()
	_duck_hold = maxf(duration, remaining)
	_duck = create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_duck.tween_method(_set_duck, _duck_db, DUCK_DB, DUCK_ATTACK)
	_duck.tween_interval(_duck_hold)
	_duck.tween_method(_set_duck, DUCK_DB, 0.0, DUCK_RELEASE)

func _set_track_gain(gain: float) -> void:
	_track_gain = gain
	_update_volume()

func _set_duck(db: float) -> void:
	_duck_db = db
	_update_volume()

func _update_volume() -> void:
	_bgm_player.volume_db = linear_to_db(maxf(_track_gain, 0.0001)) + _duck_db

func stop_bgm() -> void:
	if _transition:
		_transition.kill()
	if _duck:
		_duck.kill()
	_bgm_player.stop()
	_bgm_player.stream = null
	_target_stream = null
	_track_gain = 0.0
	_duck_db = 0.0
	_duck_hold = 0.0
	_update_volume()
