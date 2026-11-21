extends Node
## 每个进程只选一张首卡。鼠标输入走原惯性和转向，伤害、擦弹与死亡走真实碰撞。
const KEYS := {"pierce": KEY_1, "splash": KEY_2, "graze_focus": KEY_3, "power": KEY_4}
const ROUTES := {"pierce": "column", "splash": "cluster", "graze_focus": "edge", "power": "center"}
@onready var trial = get_parent()
var card := ""
var route := ""
var start := 0
var orders := 0
var fans := 0
var passed := 0
var failed := 0
var kills := {}
var grazes := 0
var max_stacks := 0
var pierce_flights := 0
var cluster_splash := 0
var first_up_tick := -1
var min_x := INF
var max_x := -INF
var min_bullet_gap := INF
var path := PackedVector2Array()
var health := 0
var low_health := 0
var hint_ticks := 0
var hint_clear := true
var capture_dir := ""

func _ready() -> void:
	# Headless 的默认窗口是方形，固定逻辑视口才能与录屏逐帧对照。
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1600 if "--wide" in OS.get_cmdline_user_args() else 1280, 720)
	process_physics_priority = -20
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not KEYS.has(args[0]):
		push_error("Pass -- pierce|splash|graze_focus|power [column|cluster|edge|center]")
		get_tree().quit(2)
		return
	card = args[0]
	route = args[1] if args.size() > 1 and not args[1].begins_with("--") else ROUTES[card]
	if route not in ROUTES.values():
		get_tree().quit(2)
		return
	seed(1121)
	for arg in args:
		if arg.begins_with("--capture="):
			capture_dir = arg.trim_prefix("--capture=")
	start = Engine.get_physics_frames()
	health = GameState.get_current_health(1)
	low_health = health
	_check("fixed_offer", UpgradeDraft.get_draft(1).get("cards") == ["pierce", "splash", "graze_focus"])
	get_tree().node_added.connect(_observe_birth)
	trial._player.get_node("GrazeArea").area_entered.connect(func(area):
		if area.is_in_group("enemy_bullets"):
			grazes += 1
	)

func _physics_process(_delta: float) -> void:
	if card.is_empty():
		return
	if Engine.get_physics_frames() - start > 1300:
		push_error("First-card trial did not finish")
		get_tree().quit(1)
		return
	var tick: int = trial.trial_tick
	if tick < 0:
		if Engine.get_physics_frames() - start == 60:
			var key := InputEventKey.new()
			key.keycode = KEYS[card]
			key.pressed = true
			get_viewport().push_input(key)
			trial._player.set_process_unhandled_input(false)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_trace_frame(tick)
	if tick < trial.END_TICK:
		_observe_hint()
		if tick == (300 if card == "graze_focus" else 120):
			_capture_action()
		_steer(tick)
		path.append(trial._player.position.snapped(Vector2(.01, .01)))
		min_x = minf(min_x, trial._player.position.x)
		max_x = maxf(max_x, trial._player.position.x)
		low_health = mini(low_health, GameState.get_current_health(1))
		max_stacks = maxi(max_stacks, GameState.get_graze_stacks())
		for b: Node2D in get_tree().get_nodes_in_group("enemy_bullets"):
			min_bullet_gap = minf(min_bullet_gap, b.position.distance_to(trial._player.position))
	else:
		_finish()

func _trace_frame(tick: int) -> void:
	var p = trial._player
	var state: Array = [p.position, p.rotation, p.velocity, GameState.get_current_health(1), GameState.get_shield_layers(1), GameState.total_kills]
	for ship in trial.squad:
		state.append([ship.position, ship.health] if is_instance_valid(ship) else null)
	for group in ["player_bullets", "enemy_bullets"]:
		var shots: Array = []
		for shot in get_tree().get_nodes_in_group(group):
			shots.append([shot.position, shot._direction, shot._speed, shot._damage, shot._pierced.size()])
		state.append(shots)
	print("[FRAME] ", tick, " ", var_to_bytes(state).hex_encode().sha256_text())

func _observe_hint() -> void:
	var hint: Label = trial._action_hint
	if not hint.visible:
		return
	hint_ticks += 1
	var ink := hint.get_global_rect().grow(2.0)
	hint_clear = hint_clear and get_viewport().get_visible_rect().encloses(ink)
	var draft: Control = trial._hud._draft_panel
	hint_clear = hint_clear and (not draft.visible or not ink.intersects(draft.get_global_rect()))
	for group in ["player", "enemies", "enemy_bullets"]:
		for unit in get_tree().get_nodes_in_group(group):
			var sprite := unit.get_node("Sprite2D") as Sprite2D
			hint_clear = hint_clear and not ink.intersects(sprite.get_global_transform_with_canvas() * sprite.get_rect())
	# 中央文字在试飞右侧扇弹起点以及左路出口之间。
	hint_clear = hint_clear and ink.position.x > trial.field.x * .38 and ink.end.x < trial.field.x * .59

func _capture_action() -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	_check("captured_action", frame.save_png(capture_dir.path_join(card + ".png")) == OK)

func _steer(tick: int) -> void:
	var p = trial._player
	var size: Vector2 = trial.field
	var target := size * Vector2(.5, .78)
	match route:
		"column":
			target.x = size.x * .30
			if tick > 100:
				target.y -= minf((tick - 100) * 1.4, 130)
		"cluster":
			target.x = size.x * .74
			if tick > 185:
				target.y -= minf((tick - 185) * 1.6, 120)
			if tick >= trial.RETREAT_TICK:
				target.x = size.x * .5
		"edge":
			var origin: Vector2 = trial._fan_origin()
			var dir := origin.direction_to(size * Vector2(trial.FAN_EXITS[0], 1.0))
			# 轨迹到最近一束弹的垂距 40 px，落在单层卡新增的感应区内。
			target.x = origin.x + (target.y - origin.y) * dir.x / dir.y - 40.0 / dir.y
		"center":
			target.y -= minf(tick * .55, 150)
	var motion = p._motion
	var desired: Vector2 = ((target - p.position) * 7.0).limit_length(p.move_speed)
	if desired.y < -10 and absf(desired.x) < 5 and first_up_tick < 0:
		first_up_tick = tick
	var ev := InputEventMouseMotion.new()
	ev.relative = (desired - motion.mouse_vel) / (p.mouse_sensitivity * p.move_speed)
	p._unhandled_input(ev)

func _observe_birth(node: Node) -> void:
	if node.scene_file_path == "res://scenes/entities/enemy.tscn":
		var i := orders
		orders += 1
		if i >= trial.ORDERS.size():
			_check("extra_enemy", false)
			return
		var order: Dictionary = trial.ORDERS[i]
		_check("spawn_%d" % i, trial.trial_tick == order.at and node.enemy_type == order.kind and node.position.is_equal_approx(trial.field * order.from))
		print("[TRACE] order=", i, " scheduled=", order.at, " born=", trial.trial_tick, " formation=", order.lane, " type=", node.enemy_type, " pos=", node.position)
		node.enemy_died.connect(_on_kill.bind(node, i))
	elif node.scene_file_path == "res://scenes/entities/bullet.tscn":
		# setup 在 add_child 之后。离树时 _pierced 仍保有本次飞行打中过的不同目标。
		node.tree_exiting.connect(func():
			if node._is_player_bullet and node._pierced.size() > 1:
				pierce_flights += 1
		, CONNECT_ONE_SHOT)
		call_deferred("_record_fan", node.get_instance_id(), trial.trial_tick)

func _record_fan(id: int, tick: int) -> void:
	var b = instance_from_id(id)
	if is_instance_valid(b) and not b._is_player_bullet:
		var i := fans
		fans += 1
		var end_x: float = trial.FAN_EXITS[i % 3]
		var expected: Vector2 = trial._fan_origin().direction_to(trial.field * Vector2(end_x, 1.0))
		_check("fan_%d" % i, i < 9 and tick == trial.VOLLEYS[i / 3] and b.position.is_equal_approx(trial._fan_origin()) and b._direction.is_equal_approx(expected) and b._speed == 430.0)
		print("[TRACE] fan=", i, " tick=", tick, " origin=", b.position, " dir=", b._direction)

func _on_kill(ship: Node2D, i: int) -> void:
	if kills.has(i):
		return
	kills[i] = trial.trial_tick
	# 溅射发生在直接命中登记之后。要求邻机与弹体不相交，排除同弹直接命中。
	if i >= 3 and card == "splash":
		for b in get_tree().get_nodes_in_group("player_bullets"):
			var gap: float = b.position.distance_to(ship.position)
			if b._pierced.size() > 0 and not b._pierced.has(ship) and gap > 25 and gap <= b._splash_radius:
				cluster_splash += 1
				break

func _finish() -> void:
	set_physics_process(false)
	_check("choice_from_key", UpgradeDraft.get_draft(1).get("source") == "key")
	_check("one_card", GameState.get_card_stacks(1) == {card: 1})
	_check("fixed_wave", orders == 6 and fans == 9)
	_check("one_credit_per_kill", GameState.total_kills == kills.size())
	_check("end_menu", trial.get_node("TrialUI/Options/Retry").is_visible_in_tree())
	_check("survived_without_hit", low_health == health)
	var window: Dictionary = trial.ACTION_HINTS.get(card, {}) if "--trial-hint" in OS.get_cmdline_user_args() else {}
	var expected_ticks := int(window.end) - int(window.start) if not window.is_empty() else 0
	_check("action_hint_window", hint_ticks == expected_ticks and not trial._action_hint.visible)
	_check("action_hint_clear_of_targets_and_draft", hint_clear)
	var radius: float = trial._player.get_node("GrazeArea/CollisionShape2D").shape.radius
	_check("graze_geometry", radius == (42.0 if card == "graze_focus" else 34.0))
	if route == "column" and card == "pierce":
		_check("two_targets_one_shot", pierce_flights > 0)
	if route == "cluster" and card == "splash":
		_check("cluster_collateral", cluster_splash > 0 and first_up_tick >= 185)
	if card == "power" and route in ["cluster", "column"]:
		_check("stat_card_no_secondary", pierce_flights == 0 and cluster_splash == 0)
		if route == "cluster":
			_check("only_direct_target", kills.size() == 1 and kills.has(4))
	if route == "center" or (route == "edge" and card != "graze_focus"):
		_check("optional_graze", grazes == 0 and max_stacks == 0)
	if route == "edge" and card == "graze_focus":
		_check("graze_reward", grazes == 3 and max_stacks == 1 and GameState.get_graze_window_msec(1) == 3000)
		var now := Time.get_ticks_msec()
		GameState._graze_last_msec = now - 2500
		var boosted := GameState.get_shoot_cooldown(1)
		GameState._graze_last_msec = now - 3001
		_check("card_window_and_cooldown", is_equal_approx(boosted, .96 * GameState.get_shoot_cooldown(1)))
	print("[PATH] ", hash(path))
	print("[TRIAL] card=", card, " route=", route, " x=", Vector2(min_x, max_x), " first_up_tick=", first_up_tick, " kills=", kills, " two_target_flights=", pierce_flights, " splash_neighbours=", cluster_splash, " nearest_bullet_px=", snappedf(min_bullet_gap, .1), " grazes=", grazes, " stacks=", max_stacks, " hp=", low_health, "/", health)
	print("[TRIAL] VERDICT pass=", passed, " failed=", failed)
	get_tree().quit(0 if failed == 0 else 1)

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("[TRIAL] FAIL ", label)
