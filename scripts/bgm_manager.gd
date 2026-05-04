extends Node

var _bgm_player: AudioStreamPlayer = null
var _is_playing: bool = false

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)

func play_bgm() -> void:
	if _bgm_player == null:
		return
	_bgm_player.stream = _generate_bgm()
	## 使用默认 bus
	_bgm_player.volume_db = -12.0
	_bgm_player.play()
	_is_playing = true
	_bgm_player.finished.connect(_on_bgm_finished)

func stop_bgm() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()
	_is_playing = false

func _on_bgm_finished() -> void:
	## 循环播放
	if _bgm_player != null:
		_bgm_player.stream = _generate_bgm()
		_bgm_player.play()

func _generate_bgm() -> AudioStreamWAV:
	## 生成 8-bit 风格循环背景音乐
	var sample_rate: int = 44100
	var duration: float = 8.0
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	## 低音贝斯线
	var bass_notes := [65.41, 82.41, 73.42, 87.31]
	## 和弦
	var chord_notes := [[130.81, 164.81, 196.0], [164.81, 196.0, 246.94], [146.83, 174.61, 220.0], [174.61, 220.0, 261.63]]
	## 旋律
	var melody_notes := [261.63, 293.66, 329.63, 349.23, 392.0, 349.23, 329.63, 293.66]
	var note_duration: float = duration / float(melody_notes.size())
	for i in num_samples:
		var t: float = float(i) / sample_rate
		var sample_value: float = 0.0
		## 贝斯
		var bass_idx: int = int(t / (duration / bass_notes.size())) % bass_notes.size()
		var bass_freq: float = bass_notes[bass_idx]
		sample_value += sin(t * TAU * bass_freq) * 0.15
		## 和弦（每 2 秒换一个）
		var chord_idx: int = int(t / (duration / chord_notes.size())) % chord_notes.size()
		for chord_note in chord_notes[chord_idx]:
			sample_value += sin(t * TAU * chord_note) * 0.06
		## 旋律
		var melody_idx: int = int(t / note_duration) % melody_notes.size()
		var mel_freq: float = melody_notes[melody_idx]
		var mel_t: float = fmod(t, note_duration) / note_duration
		var mel_env: float = max(1.0 - mel_t * 2.0, 0.0)
		sample_value += sin(t * TAU * mel_freq) * 0.1 * mel_env
		## 鼓点（每 0.5 秒）
		var beat_t: float = fmod(t, 0.5)
		if beat_t < 0.05:
			var kick: float = sin(beat_t * TAU * 80.0) * 0.3 * (1.0 - beat_t / 0.05)
			sample_value += kick
		elif beat_t > 0.25 and beat_t < 0.28:
			var hihat: float = (randf() - 0.5) * 0.15 * (1.0 - (beat_t - 0.25) / 0.03)
			sample_value += hihat
		## 限制
		sample_value = clamp(sample_value, -0.8, 0.8)
		var si: int = clampi(int(sample_value * 32767), -32768, 32767)
		data[i * 2] = si & 0xFF
		data[i * 2 + 1] = (si >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = sample_rate
	stream.data = data
	return stream
