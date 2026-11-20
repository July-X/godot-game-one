extends Node
## 60 帧/秒固定事件，同时用于无窗口回归和 Godot Movie Maker 有声对照。
const MAIN := preload("res://scenes/main.tscn")
const ELITE := preload("res://scenes/entities/elite.tscn")
const PALETTE := preload("res://scripts/palette.gd")
var main
var player
var normal
var elite
var gun
var bolt
var tick := 0
var failed := 0
var passed := 0
var hurt_finished := false
var wall_clock := OS.get_cmdline_user_args().has("realtime")
var next_tick_usec := 0

func _ready() -> void:
	Engine.max_fps = 60
	set_process(false)
	call_deferred("_start")

func _start() -> void:
	seed(20261120)
	main = MAIN.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	main.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player = main._player
	player.position = Vector2(620, 500)
	player.set_physics_process(false)
	player.collision_layer = 0
	player.get_node("GrazeArea").monitoring = false
	player.get_node("PickupArea").monitoring = false
	gun = player.get_node("CombatController")
	main._spawn_enemy_at(1, Vector2(560, 260))
	normal = get_tree().get_first_node_in_group("enemies")
	var damage := GameState.get_bullet_damage(player.peer_id)
	normal.health = damage * 2
	normal.drop_chance = 0.0
	normal.set_physics_process(false)
	elite = ELITE.instantiate()
	main.add_child(elite)
	elite.position = Vector2(787, 230)
	elite.set_physics_process(false)
	elite.apply_network_shield(damage * 2, damage * 2)
	for target in [normal, elite]:
		target.collision_layer = 0
		target.get_node("Hitbox").monitorable = false
	set_process(true)

func _fire(target: Vector2) -> void:
	player.rotation = player.position.angle_to_point(target) + PI / 2.0
	gun._shoot()
	bolt = get_tree().get_nodes_in_group("player_bullets").back()
	# 所有接触都在指定帧走正式子弹回调，消除录制速度和物理步进的影响。
	bolt.monitoring = false

func _hit(target: Node2D) -> void:
	var collider: CollisionShape2D = target.get_node("CollisionShape2D")
	var radius: float = collider.shape.radius
	bolt.global_position = collider.global_position + collider.global_position.direction_to(player.position) * radius
	bolt._on_body_entered(target)

func _voices(stream: AudioStream) -> Array:
	var active := []
	if stream:
		for voice in SFX.get_children():
			if voice.playing and voice.stream == stream:
				active.append(voice)
	return active

func _explosions() -> Array:
	return main.get_children().filter(func(node): return node.get_script() == preload("res://scripts/explosion.gd"))

func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[feedback] ", label, " pass=", ok, " ", detail)

func _stress() -> void:
	# 先填满共享池，再把受击和预警夹在两批同帧命中之间。
	for i in 24:
		main.emit_hit_feedback(main.SHAKE_HIT, 0.0, true)
	player.take_damage(GameState.get_shield_layers(player.peer_id) + 1)
	var hurt := _voices(SFX._stream_player_hurt)
	var first: AudioStreamPlayback = hurt[0].get_stream_playback() if hurt else null
	if first:
		var voice: AudioStreamPlayer = hurt[0]
		voice.finished.connect(func(): hurt_finished = voice.stream == SFX._stream_player_hurt, CONNECT_ONE_SHOT)
	main.broadcast_boss_ultimate_laser_charge(Vector2(940, 132), 1.2)
	for i in 24:
		main.emit_hit_feedback(main.SHAKE_HIT, 0.0, true)
	var still_playing := _voices(SFX._stream_player_hurt)
	var intact: bool = first != null and not still_playing.is_empty() and still_playing[0].get_stream_playback() == first
	_check("hurt_survives_24_hits", intact, "hurt voices=%d" % still_playing.size())
	var hits := 0
	for stream in SFX._hit_streams:
		hits += _voices(stream).size()
	_check("coalesced_hits", hits == 1, "hit voices=%d" % hits)
	var warnings := _voices(SFX.get("_stream_boss_warning"))
	_check("charge_warning", warnings.size() == 1, "warning voices=%d" % warnings.size())

func _process(_delta: float) -> void:
	# 无窗口模式可能远超过 60 FPS。实时时钟试听须给混音线程留下播放时间。
	if wall_clock:
		var now := Time.get_ticks_usec()
		if now < next_tick_usec:
			return
		next_tick_usec = now + 16667
	# 正式定格用墙钟计时，离线录像每个输出帧推进同样的 1/60 秒。
	main._hitstop_last_usec = Time.get_ticks_usec() - 16667
	main._tick_hitstop()
	if tick % 15 == 0 and tick < 285 and is_instance_valid(elite):
		for lane in range(-4, 5):
			var angle := PI / 2 + 0.18 * sin(tick * 0.05 + lane)
			elite._spawn_enemy_bullet(Vector2(655 + lane * 64, 122), angle, 1, 240, PALETTE.ENEMY_BULLET_MID)
	if tick > 238 and tick <= 272 and tick % 4 == 0:
		main.emit_hit_feedback(main.SHAKE_HIT, 0.0, true)
	match tick:
		12, 46:
			_fire(normal.position)
			if tick == 46:
				_check("second_muzzle_flash", player.get_node("MuzzleFlash").modulate.a > 0.1)
		32, 66:
			_hit(normal)
			if tick == 32:
				_check("ordinary_hit", _voices(SFX._hit_streams[0]).size() == 1)
		68:
			var bursts := _explosions()
			_check("normal_kill_behind_bullets", bursts.size() == 1 and bursts[0].z_index < 0)
		90:
			_check("normal_kill_expired", _explosions().is_empty())
		84, 116, 174, 258:
			_fire(elite.position)
		108, 140, 198, 284:
			if tick == 284:
				bolt._damage = elite.get_network_health()
			_hit(elite)
			if tick == 108:
				_check("shield_hit_timbre", _voices(SFX.get("_stream_shield_hit")).size() == 1)
			if tick == 140 or tick == 198:
				_check("shield_break_%d" % tick, _voices(SFX.get("_stream_shield_break")).size() == 1)
		167:
			elite.apply_network_shield(1, 2)
			_check("restored_shield_visible", is_instance_valid(elite._shield_circle) and elite._shield_circle.visible)
		211:
			BGM.play_boss_bgm()
			main._rpc_set_boss_bg(true)
		218, 224, 230, 236, 242, 248:
			_fire(Vector2(922, 110))
		238:
			_stress()
		287:
			_check("elite_death", _voices(SFX.get("_stream_elite_death")).size() == 1)
			var bursts := _explosions()
			_check("elite_kill_behind_bullets", not bursts.is_empty() and bursts.all(func(fx): return fx.z_index < 0))
		310:
			_check("elite_kill_expired", _explosions().is_empty())
		320:
			if OS.get_cmdline_user_args().has("audio-tail"):
				_check("hurt_finished_under_fire", hurt_finished)
			print("[feedback] SUMMARY pass=%d failed=%d" % [passed, failed])
			get_tree().quit(1 if failed else 0)
	tick += 1
