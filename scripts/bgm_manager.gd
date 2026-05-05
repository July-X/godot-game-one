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
	_bgm_player.volume_db = -3.0
	_bgm_player.play()
	_is_playing = true
	_bgm_player.finished.connect(_on_bgm_finished)

func stop_bgm() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()
	_is_playing = false

func _on_bgm_finished() -> void:
	if _bgm_player != null:
		_bgm_player.stream = _generate_bgm()
		_bgm_player.play()

func _generate_bgm() -> AudioStreamWAV:
	var sample_rate: int = 44100
	var duration: float = 8.0
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 4)
	## 贝斯线
	var bass_notes := [65.41, 82.41, 73.42, 87.31]
	## 和弦
	var chord_notes := [[130.81, 164.81, 196.0], [164.81, 196.0, 246.94], [146.83, 174.61, 220.0], [174.61, 220.0, 261.63]]
	## 旋律
	var melody_notes := [261.63, 293.66, 329.63, 349.23, 392.0, 349.23, 329.63, 293.66]
	var note_duration: float = duration / float(melody_notes.size())
	for i in num_samples:
		var t: float = float(i) / sample_rate
		var sample_value: float = 0.0
		## 贝斯（方波，更响亮）
		var bass_idx: int = int(t / (duration / bass_notes.size())) % bass_notes.size()
		var bass_freq: float = bass_notes[bass_idx]
		var bass_phase: float = fmod(t * bass_freq, 1.0)
		var bass_wave: float = 1.0 if bass_phase < 0.5 else -1.0
		sample_value += bass_wave * 0.25
		## 和弦（锯齿波）
		var chord_idx: int = int(t / (duration / chord_notes.size())) % chord_notes.size()
		for chord_note in chord_notes[chord_idx]:
			var ch_phase: float = fmod(t * chord_note, 1.0)
			var ch_wave: float = 2.0 * ch_phase - 1.0
			sample_value += ch_wave * 0.1
		## 旋律（三角波，带颤音）
		var melody_idx: int = int(t / note_duration) % melody_notes.size()
		var mel_freq: float = melody_notes[melody_idx]
		var vibrato: float = sin(t * TAU * 5.0) * 3.0
		var mel_phase: float = fmod(t * (mel_freq + vibrato), 1.0)
		var mel_wave: float = 2.0 * abs(2.0 * mel_phase - 1.0) - 1.0
		var mel_t: float = fmod(t, note_duration) / note_duration
		var mel_env: float = max(1.0 - mel_t * 1.5, 0.0)
		sample_value += mel_wave * 0.2 * mel_env
		## 鼓点
		var beat_t: float = fmod(t, 0.5)
		if beat_t < 0.06:
			var kick_env: float = 1.0 - beat_t / 0.06
			sample_value += sin(beat_t * TAU * 60.0) * 0.4 * kick_env
		elif beat_t > 0.25 and beat_t < 0.3:
			var hihat_env: float = 1.0 - (beat_t - 0.25) / 0.05
			sample_value += (randf() - 0.5) * 0.25 * hihat_env
		## 限制
		sample_value = clamp(sample_value, -0.9, 0.9)
		var si: int = clampi(int(sample_value * 32767), -32768, 32767)
		data[i * 4] = si & 0xFF
		data[i * 4 + 1] = (si >> 8) & 0xFF
		data[i * 4 + 2] = si & 0xFF
		data[i * 4 + 3] = (si >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = sample_rate
	stream.data = data
	return stream
