extends Node
## 运行真正的标题、大厅和开局路由。用直连地址隔离发现服务。

const LOBBY := "res://scenes/ui/lobby.tscn"
const RIFT := "res://scenes/rift_route_trial.tscn"
const NORMAL := "res://scenes/main.tscn"
const RouteRules := preload("res://scripts/battle/trials/rift_route_rules.gd")
const Player := preload("res://scripts/player/player.gd")
const Bullet := preload("res://scripts/battle/projectiles/bullet.gd")
var _passed := 0
var _failed := 0
var _battle_at := 0
var _guest_shot_at := 0
var _guest_followup_ms: Array[int] = []
var _guest_move_at := 0
var _guest_position := Vector2.INF

func _ready() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args[0] == "host"
	var port := int(args[1])
	var case_name := args[2] if args.size() > 2 else "normal"
	if args.has("device-a") or args.has("device-b"):
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600 if args.has("device-a") else 960, 720)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("Menu/BtnMultiplayer").pressed.emit()
	await get_tree().scene_changed
	var lobby := get_tree().current_scene
	_check("title_to_lobby", lobby.scene_file_path == LOBBY)
	if host:
		lobby.get_node("VBox/PanelModeSelect").hide()
		lobby.get_node("VBox/PanelHost").show()
		_check("host_listens", NetworkManager.create_host_with_mode(NetworkManager.TRANSPORT_HARMONY, port) == OK)
	else:
		lobby._on_join_mode_selected()
		lobby._deferred_join_host("127.0.0.1", port)
	var connected := await _wait_until(func(): return NetworkManager.is_online() and not NetworkManager.connected_peers.is_empty(), 6.0)
	_check("enet_connected_in_lobby", connected)
	if connected and case_name == "expect-mismatch":
		await _verify_rejection(lobby, host)
	elif connected:
		await _verify_start(lobby, host, case_name)
	await get_tree().create_timer(.25).timeout
	print("[LOBBY] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _verify_start(lobby: Node, host: bool, case_name: String) -> void:
	var remix := case_name == "remix"
	var rift := remix or case_name == "rift"
	get_tree().node_added.connect(_trace_spawn)
	if host:
		var button: Button = lobby.get_node("VBox/PanelHost/BtnRiftRoute" if rift else "VBox/PanelHost/BtnStart")
		var enabled := await _wait_until(func(): return button.is_visible_in_tree() and not button.disabled, 4.0)
		_check("start_available_after_version_check", enabled)
		if enabled and remix:
			lobby._rift_rule.select(1)
			lobby._rift_rule.item_selected.emit(1)
			_check("remix_start_waits_for_joiner_confirmation", button.disabled)
			enabled = await _wait_until(func(): return not button.disabled, 4.0)
			_check("matching_confirmation_enables_remix", enabled)
		if enabled:
			button.pressed.emit()
	elif remix:
		var shown := await _wait_until(func(): return lobby._confirm_rift_rule.is_visible_in_tree(), 4.0)
		_check("joiner_sees_rule_before_start", shown and lobby._lbl_join_status.text == RouteRules.REMIX)
		if shown:
			lobby._confirm_rift_rule.pressed.emit()
	var expected := RIFT if rift else NORMAL
	_check("expected_battle_loaded", await _wait_until(func():
		return (is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == expected), 6.0))
	if is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == expected:
		var battle := get_tree().current_scene
		if not battle.has_method("_get_networked_player_spawn_position"):
			_check("battle_script_loaded", false)
			return
		_battle_at = Time.get_ticks_msec()
		_trace("scene", {"role": "host" if host else "client", "round": GameState.get_sync_round(), "slot": NetworkManager.local_player_id()})
		if remix and OS.get_cmdline_user_args().has("entry-timeout"):
			await _verify_entry_timeout(battle, host)
			return
		if host:
			battle.child_entered_tree.connect(_schedule_bullet_check)
			battle.guest_bullet_batch_spawned.connect(_observe_guest_batch)
			_guest_position = battle._get_networked_player_spawn_position(2)
		# Client position and shots still go through the game's input and ENet paths.
		_drive_pilot_once_bound(battle)
		if rift:
			_check("same_selected_route_on_arrival", get_tree().current_scene.remix == remix)
		_check("both_pilots_synced", await _wait_until(func(): return get_tree().current_scene._players.size() == 2, 4.0))
		if host:
			var active := await _wait_until(func():
				var guest: Node2D = battle._players.get(NetworkManager.recovery.guest_slot)
				if _guest_move_at == 0 and is_instance_valid(guest) and guest.position.distance_to(_guest_position) > 8.0:
					_guest_move_at = Time.get_ticks_msec()
					_trace("authority_move", {"slot": guest.peer_id, "x": guest.position.x, "y": guest.position.y,
						"spawn_x": _guest_position.x, "spawn_y": _guest_position.y})
				return _guest_move_at > 0 and _guest_shot_at > 0, 4.0)
			var ready_ms := Time.get_ticks_msec() - _battle_at
			_trace("active_on_host", {"move_and_shot_ms": ready_ms, "first_shot_ms": _guest_shot_at - _battle_at})
			_check("guest_can_move_and_shoot_within_one_second", active and ready_ms <= 1000)
			if remix:
				_check("authority_has_both_pilots_before_practice_wave", await _wait_until(func():
					return battle._player_entry_ready and battle.trial_tick < 78, .3))
				var continued := await _wait_until(func(): return _guest_followup_ms.size() >= 2, 1.3) if _guest_shot_at > 0 else false
				_trace("followups", {"slot": NetworkManager.recovery.guest_slot, "after_first_ms": _guest_followup_ms})
				_check("two_distinct_followup_batches_within_window", continued and _guest_followup_ms[1] <= 1300)
		else:
			await _verify_entry_replays(battle)
			if remix:
				_check("guest_has_both_pilots_before_practice_wave", battle._player_entry_ready and battle.trial_tick < 78)
			if OS.get_cmdline_user_args().has("recover"):
				var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
				var link := transport.get_peer(1)
				var saved: Vector3i = battle._remix_entry_throttle_settings
				var restored := await _wait_until(func(): return battle._remix_entry_peer == null, 1.8)
				_check("entry_transport_parameters_restore_before_rewire", restored
					and int(link.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_INTERVAL)) == saved.x
					and int(link.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_ACCELERATION)) == saved.y
					and int(link.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION)) == saved.z)
			else:
				# Keep shooting through the host's entire observation window on slow samples.
				await _wait_until(func(): return not NetworkManager.is_online(), 6.0)
		if remix and OS.get_cmdline_user_args().has("recover"):
			await _verify_remix_recovery_and_retry(host)

func _trace_spawn(node: Node) -> void:
	if node is Player:
		_trace("pilot_spawned", {"node": str(node.name), "instance": node.get_instance_id()})

func _schedule_bullet_check(node: Node) -> void:
	if node is Bullet:
		_observe_guest_bullet.call_deferred(node.get_instance_id())

func _observe_guest_bullet(instance: int) -> void:
	var bullet := instance_from_id(instance) as Bullet
	if _guest_shot_at == 0 and is_instance_valid(bullet) and bullet._is_player_bullet \
			and bullet.owner_peer_id == NetworkManager.recovery.guest_slot and not bullet._is_network_ghost:
		_guest_shot_at = Time.get_ticks_msec()
		_trace("authority_bullet", {"slot": bullet.owner_peer_id, "instance": instance})

func _observe_guest_batch(slot: int, count: int, reliable: bool) -> void:
	if slot != NetworkManager.recovery.guest_slot:
		return
	if not reliable and _guest_shot_at > 0:
		_guest_followup_ms.append(Time.get_ticks_msec() - _guest_shot_at)
	_trace("authority_volley", {"slot": slot, "count": count, "reliable": reliable})

func _drive_pilot_once_bound(battle: Node) -> void:
	var slot := NetworkManager.local_player_id()
	var bound := await _wait_until(func():
		var pilot: Player = battle._players.get(slot)
		return (is_instance_valid(pilot) and pilot.is_node_ready() and battle._player == pilot
			and pilot._is_locally_controlled_player()), 3.8)
	_check("local_pilot_input_bound", bound)
	if not bound:
		return
	var pilot: Player = battle._players[slot]
	_trace("input_bound", {"round": GameState.get_sync_round(), "slot": slot, "instance": pilot.get_instance_id()})
	var origin := pilot.position
	var moved := await _wait_until(func():
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(20 if slot == 1 else -20, 0)
		get_viewport().push_input(motion)
		return pilot.position.distance_to(origin) > 8.0, 1.0)
	_trace("pilot_moved", {"slot": slot, "distance": origin.distance_to(pilot.position), "x": pilot.position.x, "y": pilot.position.y})
	_check("local_input_moves_plane_before_first_wave", moved and Time.get_ticks_msec() - _battle_at <= 1000)
	# Exercise successive position reports while the host observes distinct projectile batches.
	if slot != 1 and moved:
		var until := Time.get_ticks_msec() + 2000
		var direction := -1.0
		while Time.get_ticks_msec() < until and is_instance_valid(pilot) and NetworkManager.is_online():
			var x := pilot.position.x - origin.x
			if x < -115.0:
				direction = 1.0
			elif x > 70.0:
				direction = -1.0
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(direction * 16.0, 0)
			get_viewport().push_input(motion)
			await get_tree().process_frame

func _verify_entry_replays(battle: Node) -> void:
	var round_id := GameState.get_sync_round()
	var slot := NetworkManager.local_player_id()
	var pilot: Node = battle._players.get(slot)
	if not is_instance_valid(pilot):
		_check("replay_keeps_current_pilot", false)
		return
	await _wait_until(func(): return battle._player_entry_ready, 1.0)
	NetworkManager.request_battle_players.rpc_id(1, round_id, false)
	battle._rpc_spawn_networked_player(round_id - 1, 99, 300.0, 400.0)
	await get_tree().create_timer(.12).timeout
	_check("replay_keeps_current_pilot", battle._players.get(slot) == pilot and battle._players.size() == 2 and not battle._players.has(99))
	_trace("replayed_roster", {"round": round_id, "slot": slot, "same_instance": pilot.get_instance_id()})

func _verify_entry_timeout(battle: Node, host: bool) -> void:
	if not host:
		battle._next_player_entry_request = battle._player_entry_deadline + 1000
	var timed_out := await _wait_until(func(): return battle._player_entry_deadline < 0, 4.0)
	_check("entry_timeout_explained_and_wave_still_held", timed_out and not battle._player_entry_ready
		and battle.trial_tick == 0 and battle._player_entry_message.text.contains("超时"))
	var battle_id := battle.get_instance_id()
	if host:
		await get_tree().create_timer(.35).timeout
		battle.get_node("TrialUI/Options/Buttons/Retry").pressed.emit()
	var recovered := await _wait_until(func():
		var current := get_tree().current_scene
		return is_instance_valid(current) and current.get_instance_id() != battle_id and current._player_entry_ready, 4.0)
	_check("host_retry_after_timeout_can_enter", recovered)
	_trace("timeout_retry", {"recovered": recovered, "round": GameState.get_sync_round()})
	if not host:
		await get_tree().create_timer(.4).timeout

func _trace(event: String, data: Dictionary) -> void:
	data["ms"] = Time.get_ticks_msec() - _battle_at if _battle_at > 0 else -1
	data["wall_ms"] = int(Time.get_unix_time_from_system() * 1000)
	print("[ENTRY] ", event, " ", JSON.stringify(data))

func _verify_remix_recovery_and_retry(host: bool) -> void:
	var battle := get_tree().current_scene
	var battle_id := battle.get_instance_id()
	var old_round := GameState.get_sync_round()
	var reserved := await _wait_until(func(): return NetworkManager.recovery.is_reserved(), 4.0)
	_check("remix_recovery_reserved", reserved)
	if not reserved:
		return
	var original_wire: int = NetworkManager.recovery.guest_wire
	var slot: int = NetworkManager.recovery.guest_slot
	var old_pilot: Node = battle._players.get(slot)
	if not host:
		NetworkManager.recovery.set_background(true)
		await get_tree().create_timer(.2).timeout
		NetworkManager.drop_lan_transport()
		NetworkManager.recovery.set_background(false)
	var restored := await _wait_until(func():
		return (NetworkManager.recovery.guest_wire > 1 and NetworkManager.recovery.guest_wire != original_wire
			and not get_tree().paused and NetworkManager.recovery.deadline == 0), 13.0)
	_check("remix_reconnect_keeps_agreed_rule", restored and get_tree().current_scene == battle and battle.remix
		and battle._players.get(slot) == old_pilot)
	if not restored:
		return
	if host:
		await get_tree().create_timer(.3).timeout
		battle._restart()
	var restarted := await _wait_until(func():
		var current := get_tree().current_scene
		return (is_instance_valid(current) and current.get_instance_id() != battle_id and current.scene_file_path == RIFT
			and current._player_entry_ready), 4.0)
	_check("remix_host_retry_retains_rule", restarted and get_tree().current_scene.remix and GameState.get_sync_round() > old_round)
	if not host and restarted:
		var current := get_tree().current_scene
		current._rpc_spawn_networked_player(old_round, 99, 300.0, 400.0)
		_check("retry_rejects_old_round_player", current._players.size() == 2 and not current._players.has(99))
		await get_tree().create_timer(.3).timeout

func _verify_rejection(lobby: Node, host: bool) -> void:
	var status: Label = lobby._lbl_host_status if host else lobby._lbl_join_status
	_check("visible_version_warning", await _wait_until(func(): return status.text.contains("联机版本不兼容"), 4.5))
	if host:
		_check("both_start_buttons_disabled", lobby._btn_start.disabled and lobby._btn_rift.disabled)
		lobby._btn_start.pressed.emit()
		lobby._btn_rift.pressed.emit()
	await get_tree().process_frame
	_check("mixed_version_stays_in_lobby", get_tree().current_scene == lobby)

func _wait_until(check: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if check.call():
			return true
		await get_tree().process_frame
	return false

func _check(label: String, ok: bool) -> void:
	print("[LOBBY] ", label, " pass=", ok)
	_passed += int(ok)
	_failed += int(not ok)
