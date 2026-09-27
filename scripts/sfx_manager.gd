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
## 命中确认音按强度分档生成：轻微命中用高频短促"叮"，强度高时降低音高、
## 拉长尾巴，听感上就是"这一下更重"。比播放同一个音再调音量更有质感。
var _hit_streams: Array[AudioStreamWAV] = []
## 擦弹 tick 音：单个高频短音，靠 pitch_scale 变化
var _graze_stream: AudioStreamWAV = null
## 连击计数：连续命中时逐步升调，中断后回落。极低成本却最能放大"我打中了"的感觉。
var _combo: int = 0
var _combo_decay_left: float = 0.0
const COMBO_WINDOW: float = 1.2
const COMBO_MAX_PITCH_STEPS: int = 8
const COMBO_PITCH_RATIO: float = 1.0595  ## 每个半音（2^(1/12)）

func _ready() -> void:
	_stream_shoot = _generate_sweep(1200.0, 400.0, 0.06, 0.15)
	_stream_enemy_death = _generate_sweep(600.0, 100.0, 0.15, 0.3)
	_stream_player_hurt = _generate_tone(200.0, 0.2, 0.4)
	_stream_ui_confirm = _generate_tone(800.0, 0.08, 0.25)
	_stream_ui_select = _generate_tone(500.0, 0.05, 0.15)
	_stream_explosion = _generate_noise(0.3, 0.4)
	## 4 档命中音：强度越高，基频越低、尾巴越长
	var hit_specs: Array = [
		{freq = 1500.0, dur = 0.04, vol = 0.22},
		{freq = 1200.0, dur = 0.06, vol = 0.28},
		{freq = 950.0, dur = 0.09, vol = 0.34},
		{freq = 720.0, dur = 0.13, vol = 0.40},
	]
	for spec in hit_specs:
		_hit_streams.append(_generate_tone(float(spec.freq), float(spec.dur), float(spec.vol)))
	_graze_stream = _generate_tone(2400.0, 0.03, 0.16)
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
	stream.mix_rate = 44100
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
	stream.mix_rate = 44100
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
	stream.mix_rate = 44100
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


## 擦弹 tick：音高随层数上升，形成"越擦越亮"的连续反馈。
## 用短促高频的正弦（不是扫频），因为它要密集触发、需要和射击音区分开。
func play_graze_tick(stacks: int) -> void:
	if _graze_stream == null:
		return
	var pitch: float = pow(COMBO_PITCH_RATIO, float(clampi(stacks, 0, 16)))
	_play_stream(_graze_stream, _players, pitch)


## 命中确认音。intensity 0~1 决定档位，并按连击数整体升调。
##
## 连击升调是性价比最高的一行反馈：玩家不需要看数字，只听音高就能感觉到
## "连着呢"。窗口 1.2 秒，断了就从头再来。
func play_hit_confirm(intensity: float = 0.2) -> void:
	if _hit_streams.is_empty():
		return
	_combo = _combo + 1 if _combo_decay_left > 0.0 else 1
	_combo_decay_left = COMBO_WINDOW
	var idx: int = clampi(int(round(intensity * float(_hit_streams.size() - 1))), 0,
		_hit_streams.size() - 1)
	var stream: AudioStreamWAV = _hit_streams[idx]
	var pitch: float = pow(COMBO_PITCH_RATIO,
		float(mini(_combo - 1, COMBO_MAX_PITCH_STEPS)))
	_play_stream(stream, _players, pitch)


## 带音高倍率播放，pitch > 1 升调。
func _play_stream(stream: AudioStreamWAV, pool: Array[AudioStreamPlayer],
		pitch: float = 1.0) -> void:
	if pool.is_empty() or stream == null:
		return
	var p := _get_available_player(pool)
	p.stream = stream
	p.pitch_scale = pitch
	p.play()


func _process(delta: float) -> void:
	if _combo_decay_left > 0.0:
		_combo_decay_left -= delta
		if _combo_decay_left <= 0.0:
			_combo = 0


## 重置连击（玩家受击 / 死亡时调用，避免"挨打了还在爽"的错觉）
func reset_combo() -> void:
	_combo = 0
	_combo_decay_left = 0.0
