extends "res://tests/lobby_start_probe.gd"
## Same route on both revisions, through the normal title/lobby/battle flow.

const SEED := 1121
const ENEMY := "res://scenes/entities/enemy.tscn"
const BOSS := "res://scenes/entities/boss.tscn"
var _battle: Node
var _authority := false
var _candidate := false
var _start_tick := 0
var _formations: Array[String] = []
var _orders: Array[Dictionary] = []
var _wave_deaths := [0, 0]
var _lowest_hull := {}
var _peak := Vector2i.ZERO
var _volleys := {}
var _first_kills := {}
var _first_fast_hits := {}
var _enemy_deaths := {}
var _boss_hit := false
var _calibrations := 0
var _first_draft := false
var _drafts_seen := {}
var _summary := false
var _opening_done_at := 0
var _fourth_actual_kill := 0

func _ready() -> void:
	process_physics_priority = -10
	var args := OS.get_cmdline_user_args()
	_candidate = args.has("candidate")
	if args[0] != "solo":
		super()
		return
	_run_solo.call_deferred()

func _run_solo() -> void:
	await get_tree().process_frame
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1280, 720)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("Menu/BtnSingle").pressed.emit()
	await get_tree().scene_changed
	var args := OS.get_cmdline_user_args()
	if args.has("capture"):
		await _capture_skills(get_tree().current_scene, args[2], args.has("wide"))
	else:
		await _measure(get_tree().current_scene, true)
	print("[GROWTH] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _capture_skills(battle: Node, prefix: String, wide: bool) -> void:
	var size := Vector2i(1600 if wide else 960, 720)
	get_window().content_scale_size = size
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	battle._spawn_mobile_controls()
	battle._player.get_node("MotionController").mobile_mode = true
	battle._hud._update_platform_hints()
	var safe := Rect2(Vector2(72 if wide else 27, 23), Vector2(size) - Vector2(96 if wide else 46, 51))
	battle.get_node("MobileControls")._layout_in_safe_area(safe)
	battle._hud._layout_in_safe_area(safe)
	battle._hud._update_cooldowns()
	await _save_frame(prefix + "-ready.png")
	for action: String in ["laser", "skill", "dash"]:
		battle._player.request_action(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	battle._hud._layout_in_safe_area(safe)
	battle._hud._update_cooldowns()
	await _save_frame(prefix + "-cooling.png")

func _save_frame(path: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	_check("capture_" + path.get_file(), image != null and image.save_png(path) == OK)

func _verify_start(_lobby: Node, host: bool, _case_name: String) -> void:
	if host:
		var button: Button = _lobby.get_node("VBox/PanelHost/BtnStart")
		if not await _wait_until(func(): return not button.disabled, 4.0):
			_check("lobby_start_available", false)
			return
		button.pressed.emit()
	if not await _wait_until(func():
		return is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == NORMAL, 6.0):
		_check("normal_battle_loaded", false)
		return
	await _measure(get_tree().current_scene, host)

func _measure(battle: Node, authority: bool) -> void:
	_check("normal_battle_loaded", battle.scene_file_path == NORMAL)
	_authority = authority
	_start_tick = Engine.get_physics_frames()
	seed(SEED)
	battle._wave_director._rng.seed = SEED
	UpgradeDraft._rng.seed = SEED
	_battle = battle
	get_tree().node_added.connect(_observe)
	UpgradeDraft.draft_opened.connect(_observe_draft)
	if _candidate:
		GameState.connect("cannon_calibrated", _observe_calibration)
	if authority:
		_check("boss_reached_and_hull_hit_by_real_fire", await _wait_until(func(): return _boss_hit, 130))
		_check("first_two_natural_formations_cleared", _wave_deaths == [3, 3])
		_check("fourth_kill_captured", _first_kills.has(4))
		_check("first_draft_at_ten", _first_draft and (_guest_slot() <= 1 or bool(_drafts_seen.get(_guest_slot(), false))))
		if _candidate:
			_check("automatic_once_on_fourth_distinct_kill", _first_kills.get(4, -1) == _fourth_actual_kill and _calibrations == 1)
			_check("real_early_cannon_hit", _first_fast_hits.values().any(func(tick): return tick <= _opening_done_at))
			_check("authority_spawns_calibrated_main_cannon_for_both_slots", not NetworkManager.is_online()
				or (_first_fast_hits.has(1) and _first_fast_hits.has(_guest_slot())))
	else:
		_check("guest_first_draft_at_ten", await _wait_until(func(): return _first_draft, 24))
		if _candidate:
			_check("guest_receives_one_calibration", _calibrations == 1 and bool(GameState.get("main_cannon_calibrated")))
		# Keep the actual ENet peer active through the shared Boss comparison.
		await _wait_until(func(): return not NetworkManager.is_online() or not NetworkManager.multiplayer.has_multiplayer_peer(), 132)
	_summary = true

func _tick() -> int:
	return Engine.get_physics_frames() - _start_tick

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_battle) or _summary:
		return
	var pilot: Node2D = _battle._player
	if is_instance_valid(pilot):
		var target: Node2D
		var best := INF
		for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
			var distance := pilot.global_position.distance_squared_to(enemy.global_position)
			if not enemy.is_queued_for_deletion() and distance < best:
				target = enemy
				best = distance
		if target:
			pilot.rotation = pilot.global_position.angle_to_point(target.global_position) + PI / 2
	if not _authority:
		return
	_sample_opening()
	for boss: Node in get_tree().get_nodes_in_group("boss"):
		if boss.has_meta("growth_start_hull") and boss.get_network_health() < boss.get_meta("growth_start_hull"):
			if not _boss_hit:
				_event("boss_hull_hit", {"hp": boss.get_network_health(), "kills": GameState.total_kills})
			_boss_hit = true

func _sample_opening() -> void:
	if _wave_deaths == [3, 3]:
		# After both real waves, protect the scripted stationary pilots for the Boss timing comparison.
		var pilots: Array = _battle._players.values() if NetworkManager.is_online() else [_battle._player]
		for pilot in pilots:
			if is_instance_valid(pilot):
				pilot.extend_rescue_protection(1)
		return
	var director: Node = _battle._wave_director
	var formation: String = director.last_formation_id
	if _formations.size() < 2 and not formation.is_empty() and not _formations.has(formation):
		_formations.append(formation)
		for entry: Dictionary in director._pending:
			if entry.formation == formation:
				_orders.append({"wave": _formations.size() - 1, "pos": entry.pos, "kind": entry.type})
		_event("plan", {"wave": _formations.size(), "formation": formation, "orders": _orders.size()})
	_peak = _peak.max(Vector2i(get_tree().get_node_count_in_group("player_bullets"), get_tree().get_node_count_in_group("enemy_bullets")))
	for pid: int in [1, _guest_slot()] if _guest_slot() > 1 else [1]:
		_lowest_hull[pid] = mini(int(_lowest_hull.get(pid, 50)), GameState.get_current_health(pid))

func _observe(node: Node) -> void:
	if not _authority:
		return
	if node.scene_file_path == ENEMY:
		var index := _orders.find_custom(func(order): return order.pos == node.position and order.kind == node.enemy_type)
		var wave := -1
		if index >= 0:
			wave = int(_orders.pop_at(index).wave)
		node.enemy_died.connect(_observe_death.bind(node.get_instance_id(), wave))
	elif node.scene_file_path == BOSS:
		node.set_meta("growth_start_hull", node.get_network_health())
		_event("boss_entry", {"hp": node.get_network_health(), "kills": GameState.total_kills})
	elif node is Bullet:
		_watch_bullet.call_deferred(node)

func _observe_death(id: int, wave: int) -> void:
	if _enemy_deaths.has(id):
		return
	_enemy_deaths[id] = true
	if _enemy_deaths.size() == 4:
		_fourth_actual_kill = _tick()
	if _enemy_deaths.size() <= 6:
		_first_kills[GameState.total_kills] = _tick()
		_event("kill", {"count": GameState.total_kills, "unique_enemy_deaths": _enemy_deaths.size(), "wave": wave + 1})
	if wave >= 0:
		_wave_deaths[wave] += 1
		if _wave_deaths[wave] == 3:
			_event("wave_clear", {"wave": wave + 1, "min_hull": _lowest_hull, "peak_player": _peak.x,
				"peak_enemy": _peak.y, "shot_batches": {"host": _batch_count(1), "guest": _batch_count(_guest_slot())}})
		if _wave_deaths == [3, 3]:
			_opening_done_at = _tick()
			var pilots: Array = _battle._players.values() if NetworkManager.is_online() else [_battle._player]
			for pilot in pilots:
				if is_instance_valid(pilot):
					pilot._rescue_protected_until = Engine.get_physics_frames() + 10
			_event("protection_started", {})

func _batch_count(slot: int) -> int:
	var ticks: Dictionary = _volleys.get(slot, {})
	return ticks.size()

func _guest_slot() -> int:
	return NetworkManager.recovery.guest_slot if NetworkManager.is_online() else 0

func _watch_bullet(bullet: Bullet) -> void:
	if not is_instance_valid(bullet) or not bullet._is_player_bullet or bullet._is_network_ghost:
		return
	var slot := bullet.owner_peer_id
	var born := _tick()
	if not _volleys.has(slot):
		_volleys[slot] = {}
	_volleys[slot][born] = true
	if _enemy_deaths.size() >= 4 and not _first_fast_hits.has(slot):
		var origin := bullet.global_position
		var speed := bullet._speed
		bullet.body_entered.connect(func(body):
			if (body.is_in_group("ordinary_enemies") and body.health <= 0
					and not _first_fast_hits.has(slot) and (not _candidate or speed == 900.0)):
				_first_fast_hits[slot] = _tick()
				_event("main_cannon_first_real_hit", {"slot": slot, "speed": speed,
					"flight_frames": _tick() - born, "distance": origin.distance_to(bullet.global_position),
					"damage": bullet._damage, "type": body.enemy_type}))

func _observe_calibration() -> void:
	_calibrations += 1
	_event("calibrated", {"kills": GameState.total_kills, "count": _calibrations})

func _observe_draft(pid: int, cards: Array) -> void:
	if _drafts_seen.has(pid):
		return
	var draft := UpgradeDraft.get_draft(pid)
	var correct_kills := GameState.total_kills == 10 if _authority else GameState.total_kills >= 10
	var correct: bool = correct_kills and (not _candidate
		or (cards[0] == "firerate" and bool(draft.get("recommends_first", false))))
	_drafts_seen[pid] = correct
	_event("first_draft", {"slot": pid, "kills": GameState.total_kills, "cards": cards})
	if pid == NetworkManager.local_player_id():
		_first_draft = correct
	if _authority and pid == 1:
		UpgradeDraft.card_chosen.connect(func(slot, card, index):
			if GameState.level == 2:
				_event("first_card_effect", {"slot": slot, "card": card, "index": index,
					"source": UpgradeDraft.get_draft(slot).source, "shot_interval": GameState.get_shoot_cooldown(slot),
					"base_interval": GameState.get_base_shoot_cooldown(slot)}))

func _event(event: String, data: Dictionary) -> void:
	data.tick = _tick()
	print("[GROWTH] ", event, " ", JSON.stringify(data))
