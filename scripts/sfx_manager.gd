extends Node

var _players: Array[AudioStreamPlayer] = []
var _shoot_players: Array[AudioStreamPlayer] = []
var _pool_size: int = 16
var _shoot_pool_size: int = 8
var _shoot_index: int = 0

var _stream_shoot: AudioStreamWAV
var _stream_enemy_death: AudioStreamWAV
var _stream_player_hurt: AudioStreamWAV
var _stream_ui_confirm: AudioStreamWAV
var _stream_ui_select: AudioStreamWAV
var _stream_explosion: AudioStreamWAV

func _ready() -> void:
	_stream_shoot = _generate_sweep(1200.0, 400.0, 0.06, 0.15)
	_stream_enemy_death = _generate_sweep(600.0, 100.0, 0.15, 0.3)
	_stream_player_hurt = _generate_tone(200.0, 0.2, 0.4)
	_stream_ui_confirm = _generate_tone(800.0, 0.08, 0.25)
	_stream_ui_select = _generate_tone(500.0, 0.05, 0.15)
	_stream_explosion = _generate_noise(0.3, 0.4)
	for i in _pool_size:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	for i in _shoot_pool_size:
		var player := AudioStreamPlayer.new()
		player.volume_db = 1.5
		add_child(player)
		_shoot_players.append(player)

func _get_available_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for player in pool:
		if not player.playing:
			return player
	return pool[0]

func _play_stream(stream: AudioStreamWAV, pool: Array[AudioStreamPlayer]) -> void:
	if pool.is_empty():
		return
	var p := _get_available_player(pool)
	p.stream = stream
	p.play()

func _generate_tone(freq: float, duration: float, volume: float = 0.3, sample_rate: int = 44100) -> AudioStreamWAV:
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0
	var phase_step: float = freq / sample_rate
	var decay: float = 1.0
	var decay_step: float = 1.0 / num_samples
	for i in num_samples:
		decay = maxf(decay - decay_step * 1.2, 0.0)
		var sv: float = sin(phase * TAU) * volume * decay
		var si: int = clampi(int(sv * 32767), -32768, 32767)
		data[i * 2] = si & 0xFF
		data[i * 2 + 1] = (si >> 8) & 0xFF
		phase = fmod(phase + phase_step, 1.0)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func _generate_sweep(start_f: float, end_f: float, duration: float, volume: float = 0.3) -> AudioStreamWAV:
	var sample_rate := 44100
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0
	for i in num_samples:
		var t: float = float(i) / num_samples
		var freq: float = lerp(start_f, end_f, t)
		var decay: float = 1.0 - t * 0.7
		phase = fmod(phase + freq / sample_rate, 1.0)
		var sv: float = sin(phase * TAU) * volume * decay
		var si: int = clampi(int(sv * 32767), -32768, 32767)
		data[i * 2] = si & 0xFF
		data[i * 2 + 1] = (si >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func _generate_noise(duration: float, volume: float = 0.3) -> AudioStreamWAV:
	var sample_rate := 44100
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var decay: float = 1.0
	var decay_step: float = 1.0 / num_samples
	for i in num_samples:
		decay = maxf(decay - decay_step * 1.5, 0.0)
		var sv: float = randf_range(-1.0, 1.0) * volume * decay
		var si: int = clampi(int(sv * 32767), -32768, 32767)
		data[i * 2] = si & 0xFF
		data[i * 2 + 1] = (si >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func play_shoot() -> void:
	if _shoot_players.is_empty():
		_play_stream(_stream_shoot, _players)
		return
	var p := _shoot_players[_shoot_index % _shoot_players.size()]
	_shoot_index += 1
	p.stop()
	p.stream = _stream_shoot
	p.play()

func play_enemy_death() -> void:
	_play_stream(_stream_enemy_death, _players)

func play_player_hurt() -> void:
	_play_stream(_stream_player_hurt, _players)

func play_ui_confirm() -> void:
	_play_stream(_stream_ui_confirm, _players)

func play_ui_select() -> void:
	_play_stream(_stream_ui_select, _players)

func play_explosion() -> void:
	_play_stream(_stream_explosion, _players)
