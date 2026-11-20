extends "res://tests/lan_probe.gd"
## 观察实际启动的音频回放。把重发分隔几个混音周期，误播就会独立计数。
var _break_playbacks := {}
var _elite_deaths := {}
var _normal_deaths := {}
var _normal_hits := {}
var _player_hurts := {}
var _shield_hits := {}
var _watch := false

func _process(_delta: float) -> void:
	if not _watch:
		return
	for voice in SFX.get_children():
		if not voice.playing:
			continue
		var seen: Dictionary
		if voice.stream == SFX._stream_shield_break:
			seen = _break_playbacks
		elif voice.stream == SFX._stream_elite_death:
			seen = _elite_deaths
		elif voice.stream == SFX._stream_enemy_death:
			seen = _normal_deaths
		elif voice.stream == SFX._hit_streams[0]:
			seen = _normal_hits
		elif voice.stream == SFX._stream_shield_hit:
			seen = _shield_hits
		elif voice.stream == SFX._stream_player_hurt:
			seen = _player_hurts
		else:
			continue
		var playback: AudioStreamPlayback = voice.get_stream_playback()
		if playback:
			seen[playback.get_instance_id()] = true

func _run() -> void:
	await get_tree().process_frame
	var err: Error
	if _role == "host":
		err = NetworkManager.create_host(_port)
	else:
		err = NetworkManager.join_host("127.0.0.1", _port)
	var online := err == OK and await _wait_until(NetworkManager.is_online, 8.0)
	_check("online", online, error_string(err))
	if online:
		_enter_main_scene()
		var ready := await _wait_until(_cond_both_players, 8.0)
		_check("two_players", ready, "")
		if ready:
			_watch = true
			_main._player.set_physics_process(false)
			if _role == "host":
				await _break_twice()
			else:
				var spawned := await _wait_until(_cond_elite_alive, 5.0)
				_check("elite_spawned", spawned, "")
				if spawned:
					var destroyed := await _wait_until(_cond_elite_gone, 6.0)
					_check("elite_despawned", destroyed, "")
			await _wait_seconds(0.25)
			_check("two_break_sounds", _break_playbacks.size() == 2, str(_break_playbacks.size()))
			_check("one_elite_death", _elite_deaths.size() == 1, str(_elite_deaths.size()))
			_check("one_normal_death", _normal_deaths.size() == 1, str(_normal_deaths.size()))
			_check("ordinary_impact", not _normal_hits.is_empty(), str(_normal_hits.size()))
			_check("shield_impact", _shield_hits.size() == 1, str(_shield_hits.size()))
			_check("p2_damage_cue", _player_hurts.size() == 1, str(_player_hurts.size()))
			await _wait_seconds(0.25)
	get_tree().quit(_summarize())

func _break_twice() -> void:
	await _wait_seconds(0.4)
	var client: int = NetworkManager.connected_peers[0]
	GameState.take_damage(GameState.get_shield_layers(client) + 1, client)
	_main._spawn_enemy_at(0, Vector2(250, 200))
	var mob_id: int = _main._next_entity_id - 1
	var mob: Node2D = _main._entities[mob_id]
	mob.set_physics_process(false)
	mob.health = 5
	await _wait_seconds(0.12)
	var shot := Pool.acquire("bullet", preload("res://scenes/entities/bullet.tscn"))
	_main.add_child(shot)
	shot.setup(mob.position, 0.0, 1, true, 1, 660.0, 1)
	shot._on_body_entered(mob)
	_main._batch_sync_entity_positions()
	await _wait_seconds(0.16)
	mob.take_damage(100, 1)
	await _wait_seconds(0.14)
	_main._rpc_despawn_entity.rpc(mob_id, true)
	_main._spawn_elite()
	var elite: Node = _main._elite
	elite.set_physics_process(false)
	var eid: int = elite.entity_id
	var maximum: float = elite.get_network_max_shield()
	await _wait_seconds(0.4)
	elite.take_damage(1, 1)
	_main._batch_sync_entity_positions()
	await _wait_seconds(0.16)
	elite.take_damage(int(maximum), 1)
	await _wait_seconds(0.24)
	_main._rpc_spawn_elite.rpc(eid, 1.0)
	_main._rpc_elite_shield_destroyed.rpc(eid)
	await _wait_seconds(0.18)
	# 用已有快照入口注入回盾，同时覆盖“显式消息先到”和“零值快照先到”。
	elite.apply_network_shield(maximum, maximum)
	_main._batch_sync_entity_positions()
	await _wait_seconds(0.24)
	_main._rpc_sync_entity_shields.rpc(PackedFloat32Array([eid, 0, maximum]))
	elite.take_damage(int(maximum), 1)
	await _wait_seconds(0.24)
	elite.take_damage(1000000, 1)
	await _wait_seconds(0.15)
	_main._rpc_despawn_entity.rpc(eid, true)
