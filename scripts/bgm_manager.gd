extends Node

## 程序化 BGM 管理器
## 在运行状态时播放 8-bit 风格循环音乐

var _bgm_player: AudioStreamPlayer = null
var _is_playing: bool = false

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	add_child(_bgm_player)
	_bgm_player.finished.connect(_on_bgm_finished)

## 主菜单/标题画面背景音乐
func play_title_music() -> void:
	if _bgm_player == null:
		return
	_bgm_player.stream = _generate_title_theme()
	_bgm_player.play()
	_is_playing = true

## 游戏中背景音乐
func play_game_music() -> void:
	if _bgm_player == null:
		return
	_bgm_player.stream = _generate_game_theme()
	_bgm_player.play()
	_is_playing = true

## 结算画面背景音乐
func play_result_music() -> void:
	if _bgm_player == null:
		return
	_bgm_player.stream = _generate_result_theme()
	_bgm_player.play()
	_is_playing = true

func stop_music() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()
	_is_playing = false

func is_playing() -> bool:
	return _is_playing

## 生成 8-bit 风格主题曲（标题画面）
func _generate_title_theme() -> AudioStreamWAV:
	return _generate_looping_melody(
		[130.81, 138.59, 146.83, 155.56, 174.61, 196.00],  # C, C#, D, E, F, G
		[0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.3, 0.3, 0.3, 0.3, 0.6, 0.6],
		2.2,
		0.15
	)

## 生成 8-bit 风格游戏曲（战斗/紧张）
func _generate_game_theme() -> AudioStreamWAV:
	return _generate_looping_melody(
		[130.81, 138.59, 146.83, 164.81, 174.61, 196.00],  # C, C#, D, E, F#, G
		[0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.2, 0.2, 0.2, 0.2, 0.4, 0.4, 0.6, 0.6, 0.6, 0.6],
		2.8,
		0.2
	)

## 生成 8-bit 风格结果曲（胜利/失败）
func _generate_result_theme() -> AudioStreamWAV:
	return _generate_looping_melody(
		[130.81, 138.59, 146.83, 155.56, 174.61, 196.00],  # C, C#, D, E, F, G
		[0.6, 0.6, 0.3, 0.3, 0.6, 0.6, 0.6, 0.3, 0.3, 0.6, 0.6, 0.6],
		3.0,
		0.12
	)

## 核心：生成循环旋律（音符序列 + 节拍 + 时长 + 音量）
func _generate_looping_melody(freqs: Array, beats: Array, total_duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate: int = 44100
	var samples_per_beat: int = int(float(sample_rate) * 0.5)  # 每拍 0.5s
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	var data := PackedByteArray()

	var num_total_samples: int = int(total_duration * sample_rate)
	for i in num_total_samples:
		var beat_index: int = (i / samples_per_beat) % beats.size()
		var freq: float = freqs[beat_index]
		var amp: float = beats[beat_index] * volume

		var t_in_beat: float = float(i % samples_per_beat) / samples_per_beat
		var decay: float = maxf(1.0 - t_in_beat * 2.0, 0.0)  # 快速衰减

		var sample_value: float = sin(t_in_beat * TAU * freq / sample_rate) * amp * decay
		var sample_int: int = clampi(int(sample_value * 32767), -32768, 32767)

		data.append_array([
			sample_int & 0xFF,
			(sample_int >> 8) & 0xFF
		])

	stream.data = data
	return stream

func _on_bgm_finished() -> void:
	## 自动循环
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.play()