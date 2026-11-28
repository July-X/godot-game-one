extends Node

signal priority_cue(duration: float)

var _players: Array[AudioStreamPlayer] = []
var _shoot_players: Array[AudioStreamPlayer] = []
# 总预算 24 声部；密集命中只能占用共享池。
const SHARED_VOICES := 12
const SHOOT_VOICES := 8
var _hurt_voice: AudioStreamPlayer
var _warning_voice: AudioStreamPlayer
var _break_voice: AudioStreamPlayer
var _elite_voice: AudioStreamPlayer
var _mix_time := 0.0
var _next_play := {}
var _shoot_index: int = 0

var _stream_shoot: AudioStreamWAV
var _stream_enemy_death: AudioStreamWAV
var _stream_elite_death: AudioStreamWAV
var _stream_shield_hit: AudioStreamWAV
var _stream_shield_break: AudioStreamWAV
var _stream_boss_warning: AudioStreamWAV
var _stream_boss_approach: AudioStreamWAV
var _stream_volley: AudioStreamWAV
var _stream_laser: AudioStreamWAV
var _stream_player_hurt: AudioStreamWAV
var _stream_ui_confirm: AudioStreamWAV
var _stream_ui_select: AudioStreamWAV
var _stream_explosion: AudioStreamWAV
## 命中确认音按强度分档生成：轻微命中用高频短促"叮"，强度高时降低音高、
## 拉长尾巴，听感上就是"这一下更重"。比播放同一个音再调音量更有质感。
var _hit_streams: Array[AudioStreamWAV] = []
## 擦弹 tick 音：单个高频短音，靠 pitch_scale 变化
var _graze_stream: AudioStreamWAV = null
## 闪避音效：下行扫频，听感上是一声呼
var _stream_dash: AudioStreamWAV
## 连击计数：连续命中时逐步升调，中断后回落。极低成本却最能放大"我打中了"的感觉。
var _combo: int = 0
var _combo_decay_left: float = 0.0
const COMBO_WINDOW: float = 1.2
const COMBO_MAX_PITCH_STEPS: int = 8
const COMBO_PITCH_RATIO: float = 1.0595  ## 每个半音（2^(1/12)）

func _ready() -> void:
	_stream_shoot = _percussion(830, 285, 0.055, 0.24, 0.16)
	_stream_laser = _generate_sweep(1200, 400, 0.06, 0.15)
	_stream_enemy_death = _percussion(445, 90, 0.13, 0.44, 0.36)
	_stream_elite_death = _percussion(235, 48, 0.27, 0.68, 0.32, 0.088)
	_stream_shield_hit = _percussion(1950, 830, 0.075, 0.34, 0.23)
	_stream_shield_break = _percussion(1450, 165, 0.18, 0.57, 0.66, 0.050)
	_stream_volley = _percussion(470, 250, 0.085, 0.20, 0.12)
	_stream_boss_warning = _generate_tone(880, 0.16, 0.42)
	var gap := PackedByteArray()
	gap.resize(roundi(0.065 * _stream_boss_warning.mix_rate) * 2)
	_stream_boss_warning.data += gap + _generate_tone(1245, 0.23, 0.45).data
	_stream_boss_approach = _generate_tone(523.25, 0.12, 0.35)
	_stream_boss_approach.data += gap + _generate_tone(349.23, 0.22, 0.39).data
	_stream_player_hurt = _generate_tone(200.0, 0.2, 0.4)
	_stream_ui_confirm = _generate_tone(800.0, 0.08, 0.25)
	_stream_ui_select = _generate_tone(500.0, 0.05, 0.15)
	_stream_explosion = _generate_noise(0.3, 0.4)
	## 4 档命中音：强度越高，基频越低、尾巴越长
	var hit_specs: Array = [
		{freq = 990.0, dur = 0.045, vol = 0.17},
		{freq = 840.0, dur = 0.055, vol = 0.20},
		{freq = 700.0, dur = 0.07, vol = 0.24},
		{freq = 590.0, dur = 0.09, vol = 0.28},
	]
	for spec in hit_specs:
		_hit_streams.append(_generate_tone(float(spec.freq), float(spec.dur), float(spec.vol)))
	_graze_stream = _generate_tone(2400.0, 0.03, 0.16)
	_stream_dash = _generate_sweep(900.0, 260.0, 0.14, 0.28)
	_hurt_voice = _new_voice(_stream_player_hurt)
	_warning_voice = _new_voice(_stream_boss_warning)
	_break_voice = _new_voice(_stream_shield_break)
	_elite_voice = _new_voice(_stream_elite_death)
	for i in SHARED_VOICES:
		_players.append(_new_voice())
	for i in SHOOT_VOICES:
		var player := _new_voice()
		player.volume_db = 1.5
		_shoot_players.append(player)

func _new_voice(stream: AudioStream = null) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	add_child(voice)
	return voice

func _get_available_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for player in pool:
		if not player.playing:
			return player
	return null

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

## 仅在初始化时合成。噪声使用独立种子，不消耗战斗的随机序列。
func _percussion(start_hz: float, end_hz: float, duration: float, gain: float,
		grit: float, second_strike: float = 0.0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	var samples := roundi(duration * wav.mix_rate)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 20261120
	var phase := 0.0
	for i in samples:
		var time := float(i) / wav.mix_rate
		var tail := second_strike > 0 and time >= second_strike
		var age := time - second_strike if tail else time
		var span := duration - second_strike if tail else duration
		var t := age / span
		var pitch := lerpf(start_hz * (0.52 if tail else 1.0), end_hz, 1.0 - pow(1.0 - t, 3))
		phase += TAU * pitch / wav.mix_rate
		var body := 0.78 * sin(phase) + 0.22 * sin(2.37 * phase)
		var sample_value := lerpf(body, noise.randf_range(-1, 1), grit * exp(-3.0 * t))
		var envelope := minf(age / 0.0015, 1.0) * exp(-4.8 * t) * (1.0 - t)
		pcm.encode_s16(i * 2, roundi(32767 * gain * sample_value * envelope * (0.55 if tail else 1.0)))
	wav.data = pcm
	return wav

func _admit(stream: AudioStream, interval: float) -> bool:
	if _mix_time < float(_next_play.get(stream, 0.0)):
		return false
	_next_play[stream] = _mix_time + interval
	return true

func play_shoot() -> void:
	if _admit(_stream_shoot, 0.035):
		_play_shot(_stream_shoot)

func play_laser() -> void:
	_play_shot(_stream_laser)

func _play_shot(stream: AudioStreamWAV) -> void:
	var p := _shoot_players[_shoot_index % _shoot_players.size()]
	_shoot_index += 1
	p.stop()
	p.stream = stream
	p.play()

func play_enemy_death() -> void:
	if _admit(_stream_enemy_death, 0.055):
		_play_stream(_stream_enemy_death, _players)

func play_shield_hit() -> void:
	if _admit(_stream_shield_hit, 0.055):
		_play_stream(_stream_shield_hit, _players)

func play_enemy_volley() -> void:
	_play_stream(_stream_volley, _players)

func play_shield_break() -> void:
	_break_voice.play()

func play_elite_death() -> void:
	_elite_voice.play()

func play_boss_warning() -> void:
	_play_priority_warning(_stream_boss_warning)

func play_boss_approach() -> void:
	_play_priority_warning(_stream_boss_approach)

func _play_priority_warning(stream: AudioStreamWAV) -> void:
	_warning_voice.stream = stream
	_warning_voice.play()
	priority_cue.emit(stream.get_length())

func play_player_hurt() -> void:
	_hurt_voice.play()
	priority_cue.emit(_stream_player_hurt.get_length())

func play_ui_confirm() -> void:
	_play_stream(_stream_ui_confirm, _players)

func play_ui_select() -> void:
	_play_stream(_stream_ui_select, _players)

func play_explosion() -> void:
	_play_stream(_stream_explosion, _players)


## 擦弹 tick：音高随层数上升，形成"越擦越亮"的连续反馈。
## 用短促高频的正弦（不是扫频），因为它要密集触发、需要和射击音区分开。
## 闪避音效
func play_dash() -> void:
	_play_stream(_stream_dash, _players)


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
	if _hit_streams.is_empty() or not _admit(_hit_streams[0], 0.055):
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
	if p == null:
		return
	p.stream = stream
	p.pitch_scale = pitch
	p.play()


func _process(delta: float) -> void:
	_mix_time += delta
	if _combo_decay_left > 0.0:
		_combo_decay_left -= delta
		if _combo_decay_left <= 0.0:
			_combo = 0


## 重置连击（玩家受击 / 死亡时调用，避免"挨打了还在爽"的错觉）
func reset_combo() -> void:
	_combo = 0
	_combo_decay_left = 0.0
