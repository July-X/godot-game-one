extends "res://tests/lan_probe.gd"
## 观察实际启动的音频回放。把重发分隔几个混音周期，误播就会独立计数。
const Player = preload("res://scripts/player.gd")
const HIT := "res://scenes/effects/hit_effect.tscn"

var _break_playbacks := {}
var _elite_deaths := {}
var _normal_deaths := {}
var _normal_hits := {}
var _player_hurts := {}
var _shield_hits := {}
var _contact_modes := {}
var _contact_births: Array[Vector2] = []
const MOB_CONTACT := Vector2(250, 200)
const SHIELD_CONTACT := Vector2(430, 180)
const ELITE_CONTACT := Vector2(434, 180)
var _watch := false
var _guest_observing := false

func _process(_delta: float) -> void:
	if not _watch:
		return
	for fx in Pool._active:
		if Pool._active[fx] == "hit_effect" and fx.global_position in [MOB_CONTACT, SHIELD_CONTACT, ELITE_CONTACT]:
			_contact_modes[fx.global_position] = [fx._ordinary_enemy, fx._shield_hit]
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
		# 两名玩家共用受击音，从机体进树起隔离自然碰撞，避免把其他伤害算给 P2。
		get_tree().node_added.connect(func(node: Node) -> void:
			if node is Player:
				node.set_collision_layer_value(1, false))
		_enter_main_scene()
		var ready := await _wait_until(_cond_both_players, 8.0)
		_check("two_players", ready, "")
		if ready:
			if _role == "client":
				_main.position = Vector2(67, 41)
			_main.child_entered_tree.connect(func(node: Node) -> void:
				if node.scene_file_path == HIT:
					_contact_births.append(node.global_position))
			_watch = true
			_main._player.set_physics_process(false)
			if _role == "host":
				# 双端载入与鉴权用时不同。收到观察端确认后再发送第一颗短命火花。
				var observing := await _wait_until(func(): return _guest_observing, 5.0)
				_check("guest_observer_ready", observing, "")
				if observing:
					await _break_twice()
			else:
				_observe_ready.rpc_id(1)
				var spawned := await _wait_until(_cond_elite_alive, 5.0)
				_check("elite_spawned", spawned, "")
				if spawned:
					var destroyed := await _wait_until(_cond_elite_gone, 6.0)
					_check("elite_despawned", destroyed, "")
			await _wait_seconds(0.25)
			_check("two_break_sounds", _break_playbacks.size() == 2,
				"%d（第二次为合成回盾）" % _break_playbacks.size())
			_check("one_elite_death", _elite_deaths.size() == 1, str(_elite_deaths.size()))
			_check("one_normal_death", _normal_deaths.size() == 1, str(_normal_deaths.size()))
			_check("ordinary_impact", not _normal_hits.is_empty(), str(_normal_hits.size()))
			_check("shield_impact", _shield_hits.size() == 1, str(_shield_hits.size()))
			_check("p2_damage_cue", _player_hurts.size() == 1, str(_player_hurts.size()))
			_check("mob_atlas", _contact_modes.get(MOB_CONTACT) == [true, false], str(_contact_modes))
			_check("shield_original", _contact_modes.get(SHIELD_CONTACT) == [false, true], str(_contact_modes))
			_check("exposed_elite_original", _contact_modes.get(ELITE_CONTACT) == [false, false], str(_contact_modes))
			_check("contact_is_anchored_at_birth",
				[MOB_CONTACT, SHIELD_CONTACT, ELITE_CONTACT].all(_contact_births.has), str(_contact_births))
			await _wait_seconds(0.25)
	get_tree().quit(_summarize())

@rpc("any_peer", "reliable", "call_remote")
func _observe_ready() -> void:
	if not multiplayer.is_server():
		return
	_guest_observing = true

func _contact(target: Node2D, point: Vector2, sync_delay := 0.0) -> void:
	var shot := Pool.acquire("bullet", preload("res://scenes/entities/bullet.tscn"))
	_main.add_child(shot)
	shot.setup(point, 0.0, 1, true, 1, 660.0, 1)
	shot.monitoring = false # 该发由下一行交付一次接触。
	shot._on_body_entered(target)
	if sync_delay > 0:
		_main._entity_sync_timer = sync_delay
	else:
		_main._batch_sync_entity_positions()

func _break_twice() -> void:
	await _wait_seconds(0.4)
	var client: int = NetworkManager.connected_peers[0]
	GameState.take_damage(GameState.get_shield_layers(client) + 1, client)
	_main._spawn_enemy_at(0, MOB_CONTACT)
	var mob_id: int = _main._next_entity_id - 1
	var mob: Node2D = _main._entities[mob_id]
	mob.set_physics_process(false)
	mob.health = 5
	await _wait_seconds(0.12)
	_contact(mob, MOB_CONTACT)
	await _wait_seconds(0.16)
	# 让一发足以穿盾的真实敌弹经过 P1，检验受击音计数只来自受控的 P2 扣血。
	var p1: Node2D = _main._players[1]
	var hp_before := GameState.get_current_health(1)
	var stray_damage := GameState.get_shield_layers(1) + 1
	mob._spawn_enemy_bullet(p1.global_position, PI / 2, stray_damage, mob.SPEED_SLOW, Color.WHITE)
	mob.take_damage(100, 1)
	await _wait_seconds(0.14)
	var hp_after := GameState.get_current_health(1)
	_check("p1_ignores_stray_bullet", hp_after == hp_before, "%d -> %d" % [hp_before, hp_after])
	_main._rpc_despawn_entity.rpc(mob_id, true)
	_main._spawn_elite()
	var elite: Node = _main._elite
	elite.set_physics_process(false)
	elite.collision_layer = 0
	elite.get_node("Hitbox").monitorable = false
	var eid: int = elite.entity_id
	var maximum: float = elite.get_network_max_shield()
	await _wait_seconds(0.4)
	_contact(elite, SHIELD_CONTACT)
	await _wait_seconds(0.16)
	elite.take_damage(int(maximum), 1)
	await _wait_seconds(0.24)
	# 同步历史落点时，目标已换位置。加入端仍要在原接触点生成火花。
	_contact(elite, ELITE_CONTACT, 0.10)
	elite.global_position += Vector2(110, 0)
	await _wait_seconds(0.16)
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
