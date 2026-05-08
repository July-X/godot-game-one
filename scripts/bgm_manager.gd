extends Node

var _bgm_player: AudioStreamPlayer = null
var _is_playing: bool = false

var _bgm_stream: AudioStreamWAV = null
var _boss_mode: bool = false

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)
	_bgm_stream = _generate_bgm()

func play_bgm() -> void:
	_boss_mode = false
	_play_with_profile(-6.0, 1.0)

func play_boss_bgm() -> void:
	_boss_mode = true
	_play_with_profile(-3.5, 1.18)

func _play_with_profile(volume_db: float, pitch_scale: float) -> void:
	if _bgm_player == null or _bgm_stream == null:
		return
	_bgm_player.stream = _bgm_stream
	_bgm_player.volume_db = volume_db
	_bgm_player.pitch_scale = pitch_scale
	if not _bgm_player.playing:
		_bgm_player.play()
	_is_playing = true
	if not _bgm_player.finished.is_connected(_on_bgm_finished):
		_bgm_player.finished.connect(_on_bgm_finished)

func stop_bgm() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()
	_is_playing = false

func _on_bgm_finished() -> void:
	## 复用预生成的 BGM 流，避免每 12 秒重计算
	if _bgm_player != null and _bgm_stream != null:
		_bgm_player.stream = _bgm_stream
		_bgm_player.pitch_scale = 1.18 if _boss_mode else 1.0
		_bgm_player.play()

func _generate_bgm() -> AudioStreamWAV:
	var sample_rate: int = 44100
	var duration: float = 12.0
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 4)

	var pad_notes := [130.81, 164.81, 196.0, 246.94]
	var pad_dur: float = duration / pad_notes.size()
	var bass_notes := [65.41, 82.41, 73.42, 87.31]
	var bass_dur: float = duration / bass_notes.size()
	var melody_notes := [261.63, 293.66, 329.63, 349.23, 392.0, 349.23, 329.63, 293.66, 261.63, 293.66, 349.23, 392.0]
	var mel_dur: float = duration / melody_notes.size()

	for i in num_samples:
		var t: float = float(i) / sample_rate
		var left: float = 0.0
		var right: float = 0.0

		## Pad — sine chord, slow swell
		var pad_t: float = fmod(t, pad_dur) / pad_dur
		var pad_env: float = sin(pad_t * PI) * 0.7
		var pad_idx: int = int(t / pad_dur) % pad_notes.size()
		var pad_f: float = pad_notes[pad_idx]
		left += sin(t * TAU * pad_f) * pad_env * 0.06
		right += sin(t * TAU * pad_f) * pad_env * 0.06
		left += sin(t * TAU * pad_f * 1.5) * pad_env * 0.04
		right += sin(t * TAU * pad_f * 1.5) * pad_env * 0.04

		## Bass — sine, subtle
		var b_idx: int = int(t / bass_dur) % bass_notes.size()
		var b_f: float = bass_notes[b_idx]
		var b_t: float = fmod(t, bass_dur) / bass_dur
		var b_env: float = min(b_t * 4.0, 1.0) * max(1.0 - b_t * 0.6, 0.3)
		left += sin(t * TAU * b_f) * b_env * 0.08
		right += sin(t * TAU * b_f) * b_env * 0.08

		## Melody — sine, warm attack/decay
		var m_idx: int = int(t / mel_dur) % melody_notes.size()
		var m_f: float = melody_notes[m_idx]
		var m_t: float = fmod(t, mel_dur) / mel_dur
		var m_env: float = 1.0
		if m_t < 0.12:
			m_env = m_t / 0.12
		elif m_t > 0.78:
			m_env = (1.0 - m_t) / 0.22
		var pan: float = sin(t * 0.37) * 0.5
		var mel_val: float = sin(t * TAU * m_f) * m_env * 0.12
		left += mel_val * (0.5 - pan)
		right += mel_val * (0.5 + pan)

		## Gentle pulse — soft sine kick every beat
		var beat_t: float = fmod(t, 0.75)
		if beat_t < 0.12:
			var ke: float = 1.0 - beat_t / 0.12
			var kick_val: float = sin(beat_t * TAU * 55.0) * ke * 0.1
			left += kick_val
			right += kick_val

		## Master
		left = clamp(left, -0.85, 0.85)
		right = clamp(right, -0.85, 0.85)
		var sl: int = clampi(int(left * 32767), -32768, 32767)
		var sr: int = clampi(int(right * 32767), -32768, 32767)
		data[i * 4] = sl & 0xFF
		data[i * 4 + 1] = (sl >> 8) & 0xFF
		data[i * 4 + 2] = sr & 0xFF
		data[i * 4 + 3] = (sr >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = sample_rate
	stream.data = data
	return stream
