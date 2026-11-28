extends "res://tests/lan_probe.gd"
## 真 ENet、正式敌机死亡与选卡入口。固定靶机隔离自然击杀，便于归因。

const BULLET := preload("res://scenes/entities/bullet.tscn")
const HOST_TARGET := Vector2(290, 240)
const GUEST_TARGET := Vector2(985, 240)

var _opens: Array[Dictionary] = []
var _choices: Array[Dictionary] = []
var _panel_changes: Array[Dictionary] = []
var _guest_tapped := false

func _process(_delta: float) -> void:
	pass

func _run() -> void:
	await get_tree().process_frame
	var err := NetworkManager.create_host(_port) if _role == "host" else NetworkManager.join_host("127.0.0.1", _port)
	var online := err == OK and await _wait_until(NetworkManager.is_online, 8.0)
	_check("draft_online", online, error_string(err))
	if online:
		UpgradeDraft.draft_opened.connect(_record_open)
		UpgradeDraft.card_chosen.connect(_record_choice)
		_enter_main_scene()
		_main._asteroid_timer = INF
		_main._wave_director._cooldown = INF
		_main._hud._draft_panel.visibility_changed.connect(_record_panel)
		var ready := await _wait_until(_cond_both_players, 8.0)
		_check("draft_two_players", ready, "")
		if ready:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_main._player.set_physics_process(false)
			for plane: CharacterBody2D in _main._players.values():
				plane.set_collision_layer_value(1, false)
				plane.set_collision_mask_value(3, false)
			if _role == "host":
				await _host_drafts()
			else:
				await _guest_drafts()
	get_tree().quit(_summarize())

func _host_drafts() -> void:
	await _wait_seconds(0.35)
	var guest := int(NetworkManager.connected_peers[0])
	if not await _host_kills(GameState.kills_for_next_level - 1):
		return
	_spawn_target(GUEST_TARGET)
	var leveled := await _wait_until(func(): return GameState.level == 2, 5.0)
	_check("guest_real_kill_levels_both", leveled and GameState.total_kills == 10,
		"level=%d kills=%d" % [GameState.level, GameState.total_kills])
	if not leveled:
		return
	var host_card := str(UpgradeDraft.get_draft(1).cards[1])
	_press_key(KEY_2)
	_check("host_key_applies_once", GameState.get_card_stacks(1) == {host_card: 1}, str(_choices))
	_check("guest_tap_seen", await _wait_until(func(): return _guest_tapped, 5.0), "")
	await _refresh_same_level()
	var confirmed := _events(_choices, guest, 2)
	_check("guest_tap_settles_on_host", confirmed.size() == 1 and confirmed[0].source == "tap"
		and GameState.get_card_stacks(guest) == {confirmed[0].card: 1}, str(confirmed))
	_check("host_one_open_per_peer", _events(_opens, 1, 2).size() == 1 and _events(_opens, guest, 2).size() == 1, str(_opens))
	if not await _host_kills(GameState.kills_for_next_level):
		return
	_check("host_real_kills_level_again", GameState.level == 3 and GameState.total_kills == 30,
		"level=%d kills=%d" % [GameState.level, GameState.total_kills])
	_press_key(KEY_1)
	await _refresh_same_level()
	var timed := await _wait_until(func(): return not _events(_choices, guest, 3).is_empty(), 12.0)
	await _refresh_same_level()
	var guest_round3 := _events(_choices, guest, 3)
	var guest_stacks := GameState.get_card_stacks(guest)
	_check("guest_timeout_settles_once_on_host", timed and guest_round3.size() == 1
		and guest_round3[0].source == "timeout" and guest_round3[0].index == 0
		and _stack_count(guest_stacks) == 2, "%s stacks=%s" % [guest_round3, guest_stacks])
	_check("host_choice_not_timed_out_twice", _events(_choices, 1, 3).size() == 1
		and _stack_count(GameState.get_card_stacks(1)) == 2, str(_choices))
	await _wait_seconds(0.8)
	if timed:
		await _host_overlapping_drafts(guest)

func _guest_drafts() -> void:
	var pid := multiplayer.get_unique_id()
	var target := await _wait_until(func(): return is_instance_valid(_find_guest_target()), 8.0)
	_check("guest_sees_synced_target", target, "")
	if not target:
		return
	_shoot_target(_find_guest_target(), pid)
	var offered := await _wait_until(func(): return GameState.level == 2 and _visible(), 5.0)
	_check("guest_level_two_panel_visible", offered, "")
	if not offered:
		return
	_check("guest_no_offer_before_first_level_up", _events(_opens, pid, 1).is_empty() and _shows(1) == 0, str(_opens))
	var card := str(UpgradeDraft.get_draft(pid).cards[1])
	await _tap_card(1)
	_guest_tap_sent.rpc_id(1)
	await _wait_seconds(0.75)
	var level_two := _events(_choices, pid, 2)
	_check("guest_single_touch_no_reopen_or_rollback", not _visible()
		and _events(_opens, pid, 2).size() == 1 and _shows(2) == 1 and level_two.size() == 1
		and level_two[0].source == "tap" and level_two[0].card == card
		and GameState.get_card_stacks(pid) == {card: 1},
		"panel=%s opens=%d shows=%d confirmed=%s stacks=%s" % [
			_visible(), _events(_opens, pid, 2).size(), _shows(2), level_two, GameState.get_card_stacks(pid)])
	var next_offer := await _wait_until(func(): return GameState.level == 3 and _visible(), 8.0)
	_check("guest_new_level_reopens", next_offer and _events(_opens, pid, 3).size() == 1, str(_opens))
	if not next_offer:
		return
	var draft := UpgradeDraft.get_draft(pid)
	var first := str(draft.cards[0])
	await _wait_seconds(0.35)
	var remaining := float(draft.left)
	_request_probe_state_snapshot.rpc_id(1)
	await _wait_seconds(0.20)
	_check("guest_resync_preserves_offer_and_timer", UpgradeDraft.get_draft(pid).id == draft.id
		and UpgradeDraft.get_draft(pid).cards == draft.cards and _events(_opens, pid, 3).size() == 1
		and float(UpgradeDraft.get_draft(pid).left) < remaining, str(UpgradeDraft.get_draft(pid)))
	var timed := await _wait_until(func(): return not _events(_choices, pid, 3).is_empty(), 12.5)
	await _wait_seconds(0.45)
	var round_three := _events(_choices, pid, 3)
	var stacks := GameState.get_card_stacks(pid)
	_check("guest_timeout_once_with_first_card", timed and round_three.size() == 1
		and round_three[0].source == "timeout" and round_three[0].card == first and _stack_count(stacks) == 2
		and not _visible() and _events(_opens, pid, 3).size() == 1 and _shows(3) == 1,
		"panel=%s confirmed=%s stacks=%s" % [_visible(), round_three, stacks])
	if timed:
		await _guest_overlapping_drafts(pid, int(draft.id))

func _host_overlapping_drafts(guest: int) -> void:
	if not await _host_kills(GameState.kills_for_next_level):
		return
	var first := UpgradeDraft.get_draft(guest)
	if not await _host_kills(GameState.kills_for_next_level):
		return
	var queued := UpgradeDraft.get_draft(guest)
	_check("overlapping_level_does_not_replace_active_offer", GameState.level == 5 and GameState.total_kills == 85
		and queued.id == first.id and UpgradeDraft.has_draft(guest), str(queued))
	var advanced := await _wait_until(func(): return UpgradeDraft.get_draft(guest).get("id", 0) > first.id, 5.0)
	_check("host_issues_queued_offer_after_one_confirmation", advanced and UpgradeDraft.has_draft(guest)
		and _stack_count(GameState.get_card_stacks(guest)) == 3 and _events(_choices, guest, 5).size() == 1,
		str(_events(_choices, guest, 5)))
	var disconnected := await _wait_until(func(): return not NetworkManager.is_online(), 5.0)
	await get_tree().process_frame
	_check("disconnect_clears_pending_drafts", disconnected and UpgradeDraft.get_draft(guest).is_empty()
		and UpgradeDraft.get_draft(1).is_empty() and not _visible(), "")
	var old_scene := _main.get_instance_id()
	var solo := await _wait_until(func():
		var scene := get_tree().current_scene
		return is_instance_valid(scene) and scene.get_instance_id() != old_scene and GameState.level == 1, 7.0)
	_check("fallback_solo_has_no_previous_draft_or_cards", solo and UpgradeDraft.get_draft(1).is_empty()
		and GameState.get_card_stacks(1).is_empty(), "")

func _guest_overlapping_drafts(pid: int, timed_out_id: int) -> void:
	var next := await _wait_until(func():
		return _visible() and int(UpgradeDraft.get_draft(pid).get("id", 0)) > timed_out_id, 6.0)
	if not next:
		_check("guest_has_overlap_fixture", false, "")
		return
	var first := UpgradeDraft.get_draft(pid)
	var upgraded := await _wait_until(func(): return GameState.level == 5, 5.0)
	# 重交已结算的批次，验证迟到的选择不能选中新一轮。
	UpgradeDraft.rpc_id(1, "_rpc_request_card", timed_out_id, 1, "tap")
	await _wait_seconds(0.25)
	_check("guest_stale_request_does_not_choose_active_offer", upgraded and _visible()
		and UpgradeDraft.get_draft(pid).id == first.id and _stack_count(GameState.get_card_stacks(pid)) == 2,
		str(UpgradeDraft.get_draft(pid)))
	await _tap_card(1)
	var queued := await _wait_until(func():
		return _visible() and int(UpgradeDraft.get_draft(pid).get("id", 0)) > first.id, 5.0)
	_check("guest_sees_queued_offer_after_confirmed_card", queued and _stack_count(GameState.get_card_stacks(pid)) == 3
		and _events(_choices, pid, 5).size() == 1
		and _events(_choices, pid, 5)[0].card == str(first.cards[1]), str(_events(_choices, pid, 5)))
	NetworkManager.disconnect_network()

func _host_kills(count: int) -> bool:
	for i in count:
		var before := GameState.total_kills
		_shoot_target(_spawn_target(HOST_TARGET), 1)
		if not await _wait_until(func(): return GameState.total_kills > before, 1.0):
			_check("fixture_hit", false, "target=%d kills=%d" % [i, before])
			return false
	return true

func _spawn_target(at: Vector2) -> Node2D:
	var enemy: Node2D = _main._spawn_enemy_at(0, at)
	enemy.set_physics_process(false)
	enemy.drop_chance = 0.0
	return enemy

func _find_guest_target() -> Node2D:
	for enemy: Node2D in get_tree().get_nodes_in_group("ordinary_enemies"):
		if enemy.position.distance_to(GUEST_TARGET) < 2.0:
			return enemy
	return null

func _shoot_target(target: Node2D, pid: int) -> void:
	var bullet := Pool.acquire("bullet", BULLET)
	_main.add_child(bullet)
	bullet.setup(target.global_position + Vector2(0, 34), -PI * 0.5, 10, true, 1, 660, pid)
	# 敌机死亡仍走物理接触。此处只固定射程和伤害，避免卡牌改变下一轮试验。

func _refresh_same_level() -> void:
	for i in 4:
		GameState.add_score(1, 1)
		await _wait_seconds(0.16)

func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	get_viewport().push_input(event, true)

func _tap_card(index: int) -> void:
	# 容器在显示后的布局阶段才确定按钮位置。
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = _main._hud._draft_card_buttons[index]
	var point := get_viewport().get_final_transform() * button.get_global_rect().get_center()
	for down in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = point
		touch.pressed = down
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		await get_tree().process_frame

@rpc("any_peer", "reliable")
func _guest_tap_sent() -> void:
	if not multiplayer.is_server():
		return
	_guest_tapped = true

func _visible() -> bool:
	return is_instance_valid(_main) and _main._hud._draft_panel.is_visible_in_tree()

func _record_open(pid: int, cards: Array) -> void:
	var row := {"level": GameState.level, "pid": pid, "batch": UpgradeDraft.get_draft(pid).get("id", 0),
		"cards": cards, "kills": GameState.total_kills, "left": UpgradeDraft.get_draft(pid).left}
	_opens.append(row)
	_log("draft_open " + str(row))

func _record_choice(pid: int, card: String, index: int) -> void:
	var draft := UpgradeDraft.get_draft(pid)
	var row := {"level": GameState.level, "pid": pid, "batch": draft.get("id", 0),
		"card": card, "index": index, "source": draft.source, "stacks": GameState.get_card_stacks(pid).duplicate()}
	_choices.append(row)
	_log("draft_choice " + str(row))

func _record_panel() -> void:
	var row := {"level": GameState.level, "visible": _visible()}
	_panel_changes.append(row)
	_log("draft_panel " + str(row))

func _events(rows: Array[Dictionary], pid: int, level: int) -> Array[Dictionary]:
	return rows.filter(func(row: Dictionary): return row.pid == pid and row.level == level)

func _shows(level: int) -> int:
	return _panel_changes.filter(func(row: Dictionary): return row.level == level and row.visible).size()

func _stack_count(stacks: Dictionary) -> int:
	var count := 0
	for value: int in stacks.values():
		count += value
	return count
