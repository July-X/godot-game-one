extends Node

## 程序化 8-bit 风格音效管理器
## 使用 AudioStreamGenerator 实时合成短促音效，无需外部音频文件

var _players: Array[AudioStreamPlayer] = []
var _pool_size: int = 8

func _ready() -> void:
	## 预创建 AudioStreamPlayer 池，避免运行时频繁实例化
	for i in _pool_size:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)

func _get_available_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	## 全部占用时，取第一个强制复用
	return _players[0]

func _generate_tone(frequency: float, duration: float, volume: float = 0.4, sample_rate: int = 44100) -> AudioStreamWAV:
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0
	var phase_step: float = frequency / sample_rate
	var decay: float = 1.0
	var decay_step: float = 1.0 / num_samples

	for i in num_samples:
		decay = maxf(decay - decay_step, 0.0)
		var sample_value: float = sin(phase * TAU) * volume * decay
		var sample_int: int = clampi(int(sample_value * 32767), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
		phase = fmod(phase + phase_step, 1.0)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func _generate_noise(duration: float, volume: float = 0.3, sample_rate: int = 44100) -> AudioStreamWAV:
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var decay: float = 1.0
	var decay_step: float = 1.0 / num_samples

	for i in num_samples:
		decay = maxf(decay - decay_step * 1.5, 0.0)
		var sample_value: float = randf_range(-1.0, 1.0) * volume * decay
		var sample_int: int = clampi(int(sample_value * 32767), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func _generate_sweep(start_freq: float, end_freq: float, duration: float, volume: float = 0.4, sample_rate: int = 44100) -> AudioStreamWAV:
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0

	for i in num_samples:
		var t: float = float(i) / num_samples
		var freq: float = lerp(start_freq, end_freq, t)
		var decay: float = 1.0 - t * 0.8
		phase = fmod(phase + freq / sample_rate, 1.0)
		var sample_value: float = sin(phase * TAU) * volume * decay
		var sample_int: int = clampi(int(sample_value * 32767), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func play_shoot() -> void:
	var player := _get_available_player()
	player.stream = _generate_sweep(800.0, 200.0, 0.08, 0.35)
	player.play()

func play_hit() -> void:
	var player := _get_available_player()
	player.stream = _generate_noise(0.06, 0.3)
	player.play()

func play_enemy_hurt() -> void:
	var player := _get_available_player()
	player.stream = _generate_tone(300.0, 0.1, 0.3)
	player.play()

func play_enemy_death() -> void:
	var player := _get_available_player()
	player.stream = _generate_sweep(400.0, 80.0, 0.25, 0.4)
	player.play()

func play_player_hurt() -> void:
	var player := _get_available_player()
	player.stream = _generate_tone(150.0, 0.15, 0.45)
	player.play()

func play_ui_confirm() -> void:
	var player := _get_available_player()
	player.stream = _generate_tone(600.0, 0.06, 0.2)
	player.play()

func play_ui_select() -> void:
	var player := _get_available_player()
	player.stream = _generate_tone(440.0, 0.04, 0.15)
	player.play()

func play_explosion() -> void:
	var player := _get_available_player()
	player.stream = _generate_noise(0.3, 0.5)
	player.play()
