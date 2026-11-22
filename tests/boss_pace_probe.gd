extends "res://tests/first_card_timing.gd"
## Observes the normal director, random draft, weapons and death signals through the first Boss.
var pilot := ""
var first_card := ""
var offers := 0
var base_cooldown := 0.0
var first_wave_at := -1
var wave_members := {}
var last_volley := -1
var fast_volley := false
var evidence := {}
var boss_requested := false
var boss_seen := false
var elite_number := 0
var elite_requests := 0
var finished := false
var start_pos: Vector2
var furthest := 0.0
var boss_wait_elite := 0
var boss_wait_other := 0
var boss_open := 0
var boss_shield := 0
var boss_outside := 0
var boss_initial_hp := 0.0
var boss_last_hp := 0.0
var damage_ticks := 0
var last_damage_tick := -1
var evasion := Vector2.ZERO
var laser_lock := -1

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4 or not args[2].is_valid_int() or args[3] not in ["anchor", "evade", "assisted"]:
		push_error("Pass -- input|timeout /absolute/births.csv seed anchor|evade|assisted")
		get_tree().quit(2)
		return
	run_seed = args[2].to_int()
	pilot = args[3]
	protect_pilot = pilot == "assisted"
	stop_at_first_hit = false
	super._start()
	start_pos = game._player.position
	game._player.died.connect(func(): _finish("player_dead"))
	GameState.powerup_collected.connect(func(kind):
		if kind == "bomb":
			_record("bomb_pickup"))

func _event(kind: String, details := "") -> void:
	super._event(kind, details)
	if kind == "elite_entry":
		elite_number += 1
	elif kind == "elite_request":
		elite_requests += 1
	elif kind == "boss_request":
		boss_requested = true
	elif kind == "boss_entry":
		boss_seen = true
	var data := {"detail": details}
	if kind == "elite_request":
		data.request = elite_requests
		data.blocked_by_existing = game._is_elite_blocking_boss_spawn()
	elif kind.begins_with("elite_"):
		data.encounter = elite_number
	_record(kind, data)

func _record(kind: String, data := {}) -> void:
	print("[PACE] ", JSON.stringify({"event": kind, "tick": _tick(), "kills": GameState.total_kills,
			"level": GameState.level, "data": data}))

func _opened(pid: int, cards: Array) -> void:
	offers += 1
	choice_key = KEY_2
	if offers == 1:
		base_cooldown = GameState.get_shoot_cooldown(pid)
		var index := cards.find("pierce")
		if index == -1:
			index = cards.find("homing")
		if index >= 0:
			choice_key = [KEY_1, KEY_2, KEY_3][index]
	super._opened(pid, cards)

func _chosen(pid: int, card: String, index: int) -> void:
	if not first_choice:
		first_card = card
	super._chosen(pid, card, index)

func _build_window() -> bool:
	return first_choice and offers == 1 and _tick() - first_choice_tick < 600 and not finished

func _once(kind: String, data: Dictionary) -> void:
	if not evidence.has(kind):
		evidence[kind] = _tick()
		_record(kind, data)

func _birth(node: Node) -> void:
	var path := node.scene_file_path
	if path == ELITE:
		node.elite_died.connect(func(): _event("elite_defeat"))
	elif path == BOSS:
		boss_initial_hp = node.get_network_health()
		boss_last_hp = boss_initial_hp
		node.boss_died.connect(_boss_defeated.bind(node))
	elif _build_window():
		if path == ENEMY:
			for row in pending:
				if row.at >= first_choice_tick and row.entry.pos == node.position and row.entry.type == node.enemy_type:
					if first_wave_at < 0:
						first_wave_at = row.at
						_record("next_wave", {"formation": row.entry.formation, "scheduled": row.at})
					if row.at == first_wave_at:
						wave_members[node.get_instance_id()] = true
					break
		elif path == "res://scenes/entities/bullet.tscn":
			# setup() and apply_owner_cards() run immediately after the bullet enters the tree.
			call_deferred("_observe_launch", node.get_instance_id(), _tick())
	super._birth(node)

func _observe_launch(id: int, launched: int) -> void:
	var shot = instance_from_id(id)
	if not _build_window() or not is_instance_valid(shot) or not shot._is_player_bullet:
		return
	var cooldown := GameState.get_shoot_cooldown(game._player.peer_id)
	if launched != last_volley:
		fast_volley = last_volley >= 0 and cooldown < base_cooldown and launched - last_volley < ceili(60 * base_cooldown)
		if first_card == "firerate" and fast_volley:
			_once("build_used", {"volley_interval_ticks": launched - last_volley, "old_cd": base_cooldown, "new_cd": cooldown})
		last_volley = launched
	var flight := {"direction": shot._direction, "targets": 0, "wave": false, "fast": fast_volley}
	_once("shot_equipped", {"card": first_card, "pierce": shot._pierce_left, "homing": shot._homing_strength, "cooldown": cooldown})
	shot.body_entered.connect(func(body): _contact(shot, body, flight))
	shot.area_entered.connect(func(area): _contact(shot, area.get_parent(), flight))

func _contact(shot, target: Node, flight: Dictionary) -> void:
	if not _build_window() or shot._pierced.size() <= flight.targets or not shot._pierced.has(target):
		return
	flight.targets = shot._pierced.size()
	var in_wave := wave_members.has(target.get_instance_id())
	flight.wave = flight.wave or in_wave
	if in_wave:
		_once("next_wave_contact", {"card": first_card})
	var data := {}
	match first_card:
		"pierce":
			if flight.targets >= 2:
				data = {"distinct_targets_one_bullet": flight.targets}
		"homing":
			var angle := absf(Vector2(flight.direction).angle_to(shot._direction))
			if shot._homing_strength > 0 and not shot._has_bounced and angle > 0.002:
				data = {"turn_degrees_at_contact": rad_to_deg(angle)}
		"firerate":
			if flight.fast:
				data = {"shorter_volley_hit": true}
	if not data.is_empty():
		_once("build_used", data)
		if flight.wave:
			_once("next_wave_build_used", data)

func _physics_process(delta: float) -> void:
	if trace == null or finished:
		return
	if _tick() >= 36000:
		_finish("observation_limit")
		return
	if boss_requested and not boss_seen:
		if game._is_elite_blocking_boss_spawn():
			boss_wait_elite += 1
		else:
			boss_wait_other += 1
	if boss_seen and is_instance_valid(game._boss):
		_observe_boss_hp(game._boss)
		if game._boss.has_impact_shield():
			boss_shield += 1
		elif _can_hit_in_view(game._boss, "boss"):
			boss_open += 1
		else:
			boss_outside += 1
	if is_instance_valid(game._player):
		furthest = maxf(furthest, start_pos.distance_to(game._player.position))
		if pilot != "anchor" and is_instance_valid(game._boss):
			_evade_beam(game._player, game._boss)
	super._physics_process(delta)

func _evade_beam(player, boss) -> void:
	if not boss._ultimate_laser_firing:
		laser_lock = -1
		return
	var origin: Vector2 = boss._ultimate_laser_start
	var beam: Vector2 = origin.direction_to(boss._ultimate_laser_end)
	if laser_lock == -1:
		laser_lock = _tick()
		evasion = beam.orthogonal()
		var center := get_viewport().get_visible_rect().get_center()
		if evasion.dot(center - player.position) < 0:
			evasion = -evasion
		_record("laser_lock", {"player_x": player.position.x, "player_y": player.position.y})
	var offset: float = absf((player.position - origin).cross(beam))
	var desired := evasion * 250.0 if offset < 110.0 else Vector2.ZERO
	var mouse := InputEventMouseMotion.new()
	mouse.relative = (desired - player._motion.mouse_vel) / (player.mouse_sensitivity * player.move_speed)
	if mouse.relative.length_squared() > 0.001:
		get_viewport().push_input(mouse, true)
	if _tick() == laser_lock + 1:
		player.request_action("dash")

func _process(delta: float) -> void:
	if not finished:
		super._process(delta)

func _observe_boss_hp(boss) -> void:
	var hp := maxf(0, boss.get_network_health())
	if hp < boss_last_hp and _tick() != last_damage_tick:
		damage_ticks += 1
		last_damage_tick = _tick()
	boss_last_hp = hp

func _boss_defeated(boss) -> void:
	_observe_boss_hp(boss)
	var cause := "hp_zero"
	if boss_last_hp > 0:
		cause = "unattributed"
		# 清屏炸弹直接调用 die()，信号发出时队列游标仍指向这次击毁。
		for pickup in get_tree().get_nodes_in_group("powerups"):
			var i: int = pickup._kill_idx - 1
			if i >= 0 and i < pickup._kill_queue.size() and is_same(pickup._kill_queue[i], boss):
				cause = "screen_bomb"
				break
	_finish("boss_defeat", {"cause": cause})

func _finish(outcome: String, details := {}) -> void:
	if finished:
		return
	finished = true
	if outcome == "player_dead" and is_instance_valid(game._boss):
		_observe_boss_hp(game._boss)
		if game._boss._ultimate_laser_firing:
			details.beam_distance_px = game._boss._distance_to_beam_center(game._player.position)
			details.beam_core_radius_px = game._boss.BOSS_ULTIMATE_LASER_WIDTH * 0.5 * game._boss.ULTIMATE_LASER_INNER_RATIO
	_record(outcome, details)
	var hp := GameState.get_current_health(game._player.peer_id)
	_record("end", {"outcome": outcome, "hp": hp, "card": first_card, "assisted": protect_pilot,
			"pilot": pilot, "max_displacement": snappedf(furthest, 0.1), "wave_members": wave_members.size(),
			"wait_elite": boss_wait_elite, "wait_other": boss_wait_other, "open": boss_open,
			"shield": boss_shield, "outside": boss_outside, "boss_start_hp": boss_initial_hp,
			"boss_remaining_hp": boss_last_hp, "damage_ticks": damage_ticks})
	var ok := not failed and ((outcome == "boss_defeat" and boss_seen and elite_hit and first_choice)
			or (outcome == "player_dead" and hp == 0)
			or (outcome == "observation_limit" and hp > 0))
	_event("verdict", "pass=%s" % ok)
	trace.flush()
	# 死亡信号在生产代码排队退场之前发出；先让同帧的清理和特效挂载走完。
	_shutdown.call_deferred(0 if ok else 1)

func _shutdown(code: int) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().quit(code)
