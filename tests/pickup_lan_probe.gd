extends "res://tests/lan_probe.gd"
## 真实双端放置飞机，开着生产拾取碰撞区。只停自动射击、移动惯性和刷怪。

const FIELD := Vector2(1280, 720)
const AWAY := Vector2(120, 120)
const RIGHT := Vector2(1256, 690)
const LEFT := Vector2(24, 690)
const STEPS := [
	["guest_power", "power", RIGHT, AWAY, RIGHT - Vector2(105, 0), "guest"],
	["guest_core", "core", RIGHT, AWAY, RIGHT, "guest"],
	["host_core", "core", LEFT, LEFT, Vector2(200, LEFT.y), "host"],
	["shared_race", "speed", Vector2(640, 528), Vector2(568, 528), Vector2(712, 528), "either"],
]
const DELAYED := ["delayed_guest", "core", RIGHT, RIGHT - Vector2(155, 0), RIGHT, "guest"]

var _guest := 0
var _my_id := 0
var _baseline := false
var _step := -1
var _kind := ""
var _site := Vector2.ZERO
var _id := 0
var _item: Node2D
var _magnet_seen := false
var _contacts := {}
var _gone := false
var _stat_seen := false
var _baseline_stats := []
var _plays := {}
var _audio_finishes := 0
var _toast_ids := {}
var _ring_ids := {}
var _peer_ready := {}
var _start_ms := 0.0
var _retired_at := Vector2.ZERO
var _full_toast := true
var _toast_after_stat := true
var _silent_pending := false
var _retired_ms := 0
var _freed_ms := 0
var _animation_only := false


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	_baseline = OS.has_environment("PICKUP_BASELINE")
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1280, 960) if ("pickup-tablet-" + _role) == args[2] else Vector2i(1600, 720)
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var connected := err == OK and await _wait_until(func(): return NetworkManager.is_online() and NetworkManager.connected_peers.size() == 1, 8)
	_check("connected", connected, error_string(err))
	if connected:
		_enter_main_scene()
		var ready := await _wait_until(_cond_both_players, 8)
		_check("pilots", ready, str(_main._players.keys()))
		if ready:
			_my_id = multiplayer.get_unique_id()
			_guest = NetworkManager.connected_peers[0] if _role == "host" else _my_id
			get_tree().node_added.connect(_observe_item)
			for voice: AudioStreamPlayer in SFX.get_children():
				voice.finished.connect(_observe_audio_end.bind(voice))
			_setup_pilots()
			for i in STEPS.size():
				await _exercise(i, STEPS[i])
			if not _baseline:
				await _exercise(STEPS.size(), DELAYED)
				await _probe_restart()
			await _barrier("done")
			await _wait_seconds(0.25)
	get_tree().quit(_summarize())


func _setup_pilots() -> void:
	_main._asteroid_timer = 120.0
	_main._wave_director._cooldown = 120.0
	for pilot in _main._players.values():
		pilot.set_physics_process(false)
		for shape in pilot.get_node("PickupArea").get_children():
			shape.shape = shape.shape.duplicate()
	if _role == "host":
		GameState._state(1).skill_cooldown = 30.0
		GameState._state(_guest).skill_cooldown = 30.0
		GameState.force_sync_to_peer(_guest)


func _exercise(index: int, row: Array) -> void:
	_step = index
	_kind = row[1]
	_site = row[2]
	_retired_at = _site
	_item = null
	_id = 0
	_magnet_seen = false
	_contacts.clear()
	_gone = false
	_stat_seen = false
	_baseline_stats.clear()
	_plays.clear()
	_audio_finishes = 0
	_toast_ids.clear()
	_ring_ids.clear()
	_full_toast = true
	_toast_after_stat = true
	_silent_pending = false
	_retired_ms = 0
	_freed_ms = 0
	_animation_only = false
	_main._players[_my_id].global_position = row[3] if _role == "host" else row[4]
	_main._players[_my_id].reset_physics_interpolation()
	await _barrier("positioned_%s" % index)
	var remote := _guest if _role == "host" else 1
	var remote_at: Vector2 = row[4] if _role == "host" else row[3]
	var aligned := await _wait_until(func(): return _main._players[remote].global_position.distance_to(remote_at) < 1.0, 3)
	_check(str(row[0]) + "_same_positions", aligned, str(_main._players[remote].global_position))
	await _wait_seconds(0.12)
	_baseline_stats = _stats()
	await _barrier("armed_%s" % index)
	if _role == "host":
		if index == STEPS.size():
			GameState._sync_timer = 0.30
		_start_ms = Time.get_unix_time_from_system() * 1000.0
		_mark_spawn.rpc(_start_ms)
		var assigned := _guest if _kind == "core" and row[5] == "guest" else (1 if _kind == "core" else 0)
		_main.spawn_boss_fragment(_kind, _site, assigned)
	var ended := await _wait_until(func(): return _gone and _stat_seen, 4.0)
	var winner := _winner()
	_check(str(row[0]) + "_public_retirement_and_single_reward", ended and winner > 0
		and (row[5] == "either" or winner == (1 if row[5] == "host" else _guest)), str([_baseline_stats, _stats(), winner]))
	if not _baseline and _role == "host" and _kind == "core":
		# 实际 ENet 重发已结束的结果和旧实体快照，既有核心收益不得重放。
		var round_id: int = GameState.call("get_sync_round")
		_main._on_network_powerup_collected(_id, winner)
		_main._rpc_finish_powerup.rpc(round_id, _id, _kind, _retired_at, _guest, _kind, 1)
		_main._rpc_spawn_powerup.rpc(round_id, _id, _kind, _site, winner)
	await _wait_seconds(0.22)
	var own := winner == _my_id
	var count_ok := _toast_ids.size() == int(own) and _ring_ids.size() == int(own and _kind == "core") and _audio_finishes == int(own)
	if _baseline:
		_event("baseline_cues", {"is_owner": own, "toasts": _toast_ids.size(), "rings": _ring_ids.size(), "audio": _plays.size()})
	else:
		_check(str(row[0]) + "_owner_feedback_once", count_ok, str([own, _toast_ids.size(), _ring_ids.size(), _audio_finishes]))
		_check(str(row[0]) + "_full_text_after_applied_state", _full_toast and _toast_after_stat, str([_full_toast, _toast_after_stat]))
		var tail_ms := _freed_ms - _retired_ms
		_check(str(row[0]) + "_shared_shrink_detached_from_pickup", _animation_only and tail_ms >= 92 and tail_ms <= 300, "%d ms" % tail_ms)
		_check(str(row[0]) + "_no_reappeared_item", _main._despawned_entity_ids.has(_id) and not _main._entities.has(_id)
			and not is_instance_valid(_item) and _winner() == winner, str(_id))
		if row[0] == "shared_race" and _role == "host":
			_check("both_overlap_in_same_physics_frame", _contacts.size() == 2 and _contacts[1] == _contacts[_guest], str(_contacts))
		if row[0] == "delayed_guest" and _role == "client":
			_check("remote_retirement_while_reward_snapshot_is_delayed", _silent_pending, "no text or audio while waiting")
	await _barrier("collected_%s" % index)
	_step = -1
	await _wait_seconds(0.75)


func _observe_item(node: Node) -> void:
	if _step < 0 or node.scene_file_path != "res://scenes/entities/powerup.tscn":
		return
	_item = node
	_item.tree_exiting.connect(func():
		_freed_ms = Time.get_ticks_msec()
		_event("visual_freed", {"id": _id}))
	_event("visual_spawn", {"pos": str(_item.global_position)})


func _observe_audio_end(voice: AudioStreamPlayer) -> void:
	if _step < 0 or voice.stream != SFX._stream_ui_confirm:
		return
	_audio_finishes += 1
	_event("audio_finished")


func _process(_delta: float) -> void:
	if _step < 0 or _baseline_stats.is_empty() or not is_instance_valid(_main):
		return
	if is_instance_valid(_item) and _id == 0:
		_id = _item.entity_id
	if is_instance_valid(_item) and not _magnet_seen and (_item._magnet_owner_peer_id > 0 or _item.global_position.distance_to(_site) > 1.0):
		_magnet_seen = true
		_event("magnet_visible", {"at": str(_item.global_position), "magnet_owner": _item._magnet_owner_peer_id})
	if is_instance_valid(_item) and _contacts.size() < 2 and _role == "host":
		for pilot in _main._players.values():
			if _contacts.has(pilot.peer_id) or not pilot.get_node("PickupArea").overlaps_area(_item):
				continue
			_contacts[pilot.peer_id] = Engine.get_physics_frames()
			_event("area_contact", {"peer": pilot.peer_id, "at": str(pilot.global_position)})
	if _id > 0 and not _gone and not _main._entities.has(_id):
		_gone = true
		_retired_ms = Time.get_ticks_msec()
		_animation_only = is_instance_valid(_item) and not _item.is_in_group("powerups")
		_retired_at = _item.global_position if is_instance_valid(_item) else _site
		_event("public_retirement", {"id": _id, "live_visual": is_instance_valid(_item), "at": str(_retired_at)})
	if not _stat_seen and _winner() > 0:
		_stat_seen = true
		_event("reward_visible", {"winner": _winner(), "values": _stats()})
	for voice: AudioStreamPlayer in SFX.get_children():
		if voice.playing and voice.stream == SFX._stream_ui_confirm and voice.get_stream_playback():
			_record("audio_confirm", _plays, voice.get_stream_playback().get_instance_id())
	for node in Pool._active:
		if Pool._active[node] == "core_pickup":
			_record("core_ring", _ring_ids, node.get_instance_id())
	for toast: Label in _main._hud._active_pickup_toasts:
		if _toast_ids.has(toast.get_instance_id()):
			continue
		var rect := Rect2(toast.get_global_transform_with_canvas().origin,
			toast.get_global_transform_with_canvas().basis_xform(toast.size))
		var expected := get_viewport().get_canvas_transform() * _retired_at
		var field := Rect2(get_viewport().get_canvas_transform().origin,
			get_viewport().get_canvas_transform().basis_xform(FIELD))
		var safe: Rect2 = _main._hud._safe_rect
		_full_toast = _full_toast and safe.encloses(rect) and not rect.intersects(_main._hud._skill_bar.get_global_rect())
		if _kind == "core":
			_full_toast = _full_toast and field.encloses(rect) and toast.get_canvas() == _main.get_canvas() and toast.z_index < 0
		else:
			_full_toast = _full_toast and absf(rect.get_center().x - expected.x) <= 90.0 and absf(rect.get_center().y - expected.y) <= 120.0
		_toast_after_stat = _toast_after_stat and _stat_seen
		_record("toast", _toast_ids, toast.get_instance_id(), {"rect": str(rect), "anchor": str(expected),
			"visible_world_width": rect.intersection(field).size.x, "viewport": str(get_viewport().get_visible_rect().size), "text": toast.text})
		_capture_toast.call_deferred(STEPS[_step][0] if _step < STEPS.size() else DELAYED[0])
	if _step == STEPS.size() and _role == "client" and _gone and not _stat_seen and _toast_ids.is_empty() and _plays.is_empty():
		_silent_pending = true


func _capture_toast(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() <= 3 or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var file := args[3].path_join("%s-%s-%s.png" % [args[2], _role, label])
	_check(label + "_window_capture", get_viewport().get_texture().get_image().save_png(file) == OK, file)


func _stats() -> Array:
	match _kind:
		"core":
			return [GameState.get_skill_cooldown(1), GameState.get_skill_cooldown(_guest)]
		"speed":
			return [GameState.get_shoot_speed_level(1), GameState.get_shoot_speed_level(_guest)]
	return [GameState.get_bullet_power_level(1), GameState.get_bullet_power_level(_guest)]


func _winner() -> int:
	var stats := _stats()
	var delta := Vector2(float(stats[0]) - float(_baseline_stats[0]), float(stats[1]) - float(_baseline_stats[1]))
	if _kind == "core":
		delta = -delta / Vector2(float(_baseline_stats[0]), float(_baseline_stats[1])) / 0.30
	if delta.x >= 0.92 and delta.y < 0.92 and delta.x < 1.45:
		return 1
	if delta.y >= 0.92 and delta.x < 0.92 and delta.y < 1.45:
		return _guest
	return 0


func _probe_restart() -> void:
	var old_id := _main.get_instance_id()
	var old_round: int = GameState.call("get_sync_round")
	var old_state := {}
	if _role == "host":
		old_state = GameState._to_dict()
	await _barrier("before_restart")
	if _role == "host":
		_main._restart()
	var restart := await _wait_until(func():
		var scene := get_tree().current_scene
		return (is_instance_valid(scene) and scene.scene_file_path == MAIN_SCENE and scene.get_instance_id() != old_id
			and scene._players.size() == 2 and GameState.call("get_sync_round") > old_round), 6)
	_check("same_connection_enters_next_round", restart, str(GameState.call("get_sync_round")))
	if not restart:
		return
	_main = get_tree().current_scene
	_setup_pilots()
	_main._players[_my_id].global_position = AWAY
	await _wait_seconds(0.35)
	await _barrier("new_round_armed")
	var test_id := 1000
	var at := Vector2(1180, 613)
	if _role == "host":
		_main.spawn_boss_fragment("core", at, _guest)
		_main._rpc_spawn_powerup.rpc(old_round, test_id, "power", RIGHT, 0)
		_main._rpc_spawn_powerup.rpc(old_round, test_id + 42, "power", RIGHT, 0)
		_main._rpc_finish_powerup.rpc(old_round, test_id, "core", at, _guest, "core", 1)
		old_state.sequence = GameState._sync_sequence + 1
		GameState._rpc_sync_game_state.rpc_id(_guest, old_state)
		GameState.force_sync_to_peer(_guest)
	await _wait_seconds(0.22)
	var item: Variant = _main._entities.get(test_id)
	_check("old_round_cannot_replace_collect_or_restore_rewards", is_instance_valid(item) and item.get_powerup_type() == "core"
		and item.global_position.is_equal_approx(at) and not _main._entities.has(test_id + 42)
		and not _main._despawned_entity_ids.has(test_id) and _main._hud._active_pickup_toasts.is_empty()
		and GameState.get_bullet_power_level(_guest) == 1, str(_main._entities.keys()))
	if _role == "client" and is_instance_valid(item):
		# 丢掉显示副本，通过既有真实实体快照补齐。远距离请求仍应无效。
		item.queue_free()
		_main._entities.erase(test_id)
		_main._rpc_request_powerup_magnet.rpc_id(1, GameState.call("get_sync_round"), test_id)
		_main._rpc_request_entity_snapshot.rpc_id(1)
		var resupplied := await _wait_until(func(): return is_instance_valid(_main._entities.get(test_id)), 2)
		_check("live_item_resnapshot_restores_same_position_and_owner", resupplied and _main._entities[test_id].global_position == at
			and int(_main._entities[test_id].get_meta("assigned_peer_id", 0)) == _guest, str(at))
	await _barrier("resnapshot_done")
	if _role == "host":
		_check("distant_magnet_hint_cannot_claim_item", is_instance_valid(item) and item._magnet_owner_peer_id == 0, str(at))


func _event(name: String, detail := {}) -> void:
	print("[PICKUP] ", JSON.stringify({"step": _step, "event": name, "role": _role, "tick": Engine.get_physics_frames(),
		"wall_ms": Time.get_unix_time_from_system() * 1000.0, "spawn_ms": _start_ms, "detail": detail}))


func _record(name: String, seen: Dictionary, instance: int, detail := {}) -> void:
	if seen.has(instance):
		return
	seen[instance] = true
	_event(name, detail)


func _barrier(label: String) -> void:
	if _role == "host":
		_host_ready.rpc(label)
	else:
		_guest_ready.rpc_id(1, label)
	if not await _wait_until(func(): return _peer_ready.has(label), 6.0):
		_check("peer_" + label, false, "sync timeout")


@rpc("authority", "reliable", "call_remote")
func _mark_spawn(stamp: float) -> void:
	_start_ms = stamp


@rpc("authority", "reliable", "call_remote")
func _host_ready(label: String) -> void:
	_peer_ready[label] = true


@rpc("any_peer", "reliable", "call_remote")
func _guest_ready(label: String) -> void:
	if not multiplayer.is_server():
		return
	_peer_ready[label] = true
