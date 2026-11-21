extends Node
## 普通导演实播。观察排期与场景出生分别记账，不给游戏加击杀或伤害。
const RUN_SEED := 1121
const ENEMY := "res://scenes/entities/enemy.tscn"
const ELITE := "res://scenes/entities/elite.tscn"
const BOSS := "res://scenes/entities/boss.tscn"

@onready var game = get_parent()
var trace: FileAccess
var pending: Array[Dictionary] = []
var watched: Dictionary = {}
var start_tick := 0
var next_order := 0
var director_births := 0
var opened_tick := -1
var timeout_mode := false
var first_choice := false
var elite_seen := false
var failed := false
var observed_trial := false
var first_choice_tick := -1
var fixed_births := 0
var director_resumed := false
var elite_hit := false
var slice_end_kills := -1
var run_seed := RUN_SEED
var protect_pilot := true
var stop_at_first_hit := true
var choice_key := KEY_2

func _ready() -> void:
	# Headless 的默认窗口是方形，固定逻辑视口才能与录屏逐帧对照。
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1280, 720)
	process_priority = 100
	process_physics_priority = -10
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["input", "timeout"]:
		push_error("Pass -- input|timeout /absolute/path/to/trace.csv")
		get_tree().quit(2)
		return
	trace = FileAccess.open(args[1], FileAccess.WRITE)
	if trace == null:
		push_error("Cannot write trace: " + args[1])
		get_tree().quit(2)
		return
	timeout_mode = args[0] == "timeout"
	observed_trial = game.has_method("_start_trial")
	trace.store_csv_line(["event", "tick", "order", "formation", "enemy_type", "x", "y", "scheduled_tick", "nominal_due_tick"])
	seed(run_seed)
	game._wave_director._rng.seed = run_seed
	UpgradeDraft._rng.seed = run_seed
	start_tick = Engine.get_physics_frames()
	if protect_pilot:
		game._player._invincible_timer = 10000.0
	get_tree().node_added.connect(_birth)
	GameState.elite_spawn_requested.connect(func(): _event("elite_request"))
	GameState.boss_spawn_requested.connect(func(_level): _event("boss_request"))
	UpgradeDraft.draft_opened.connect(_opened)
	UpgradeDraft.card_chosen.connect(_chosen)
	_event("start", "seed=%d director_seed=%d draft_seed=%d viewport=%s" % [run_seed, run_seed, run_seed, game.get_viewport_rect().size])

func _tick() -> int:
	return Engine.get_physics_frames() - start_tick

func _event(kind: String, details := "") -> void:
	print("[TIMING] ", kind, " tick=", _tick(), " kills=", GameState.total_kills, " level=", GameState.level, " ", details)

func _opened(_pid: int, cards: Array) -> void:
	opened_tick = _tick()
	_event("offer", ",".join(cards))
	if observed_trial and GameState.level == 2:
		failed = failed or GameState.total_kills != 10 or cards != ["pierce", "splash", "graze_focus"]

func _chosen(pid: int, card: String, index: int) -> void:
	var source: String = UpgradeDraft.get_draft(pid).source
	var reason := "script_key" if source == "key" else source
	var expected := "timeout" if timeout_mode else "key"
	if source != expected or (timeout_mode and _tick() - opened_tick < 599):
		failed = true
	if not first_choice:
		first_choice_tick = _tick()
		first_choice = true
	_event("choice", "%s index=%d reason=%s" % [card, index, reason])
	opened_tick = -1

func _physics_process(_delta: float) -> void:
	if trace == null or not is_instance_valid(game._player):
		return
	# 标定射手固定位置，只转向最近目标。留住普通子弹、击杀、掉落和同屏上限。
	var player = game._player
	var target: Node2D
	var best := INF
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion():
			continue
		var distance: float = player.global_position.distance_squared_to(enemy.global_position)
		if distance < best:
			best = distance
			target = enemy
	if target != null:
		player.rotation = player.global_position.angle_to_point(target.global_position) + PI / 2
	if not timeout_mode and opened_tick >= 0 and _tick() - opened_tick >= 45:
		var key := InputEventKey.new()
		key.keycode = choice_key
		key.pressed = true
		get_viewport().push_input(key)

func _process(_delta: float) -> void:
	if trace == null:
		return
	if observed_trial and game.trial_tick == game.END_TICK and slice_end_kills < 0:
		slice_end_kills = GameState.total_kills
		failed = failed or slice_end_kills > 10 + game.ORDERS.size() or GameState.level != 2
		_event("slice_end")
	for entry: Dictionary in game._wave_director._pending:
		if not pending.any(func(row): return is_same(row.entry, entry)):
			next_order += 1
			var row := {"entry": entry, "id": next_order, "at": _tick(), "due": _tick() + ceili(float(entry.delay) * 60.0)}
			pending.append(row)
			_write("schedule", row, entry.pos, entry.type)
	for id: int in watched.keys():
		var unit = instance_from_id(id)
		if not is_instance_valid(unit):
			watched.erase(id)
			continue
		var info: Dictionary = watched[id]
		if not info.in_view and _can_hit_in_view(unit, info.kind):
			info.in_view = true
			_event(info.kind + "_attackable_in_view")
		var hp: float = unit.get_network_health()
		if info.kind == "elite":
			hp += unit.get_network_shield()
		if not info.hit and hp < info.initial:
			info.hit = true
			_event(info.kind + "_first_damage")
			if info.kind == "elite":
				elite_hit = true
			if info.kind == "boss" and stop_at_first_hit:
				var ok: bool = first_choice and elite_seen and elite_hit and info.in_view and director_births > 0 and not failed
				if observed_trial:
					ok = ok and fixed_births == game.ORDERS.size() and slice_end_kills >= 10 and director_resumed
				_event("verdict", "pass=%s schedules=%d births=%d pending=%d fixed=%d resumed=%s" % [ok, next_order, director_births, pending.size(), fixed_births, director_resumed])
				trace.flush()
				get_tree().quit(0 if ok else 1)
	if _tick() > 60 * 600 or (stop_at_first_hit and not GameState.game_running):
		_event("deadline")
		get_tree().quit(1)

func _can_hit_in_view(unit: Node2D, kind: String) -> bool:
	var collider: CollisionShape2D = unit.get_node("CollisionShape2D")
	var bounds: Rect2 = collider.global_transform * collider.shape.get_rect()
	return (kind == "elite" or not unit._shield_active) and not collider.disabled and get_viewport().get_visible_rect().intersects(bounds)

func _birth(node: Node) -> void:
	var path := node.scene_file_path
	if path == ELITE or path == BOSS:
		var kind := "elite" if path == ELITE else "boss"
		var hp: float = node.get_network_health()
		if path == ELITE:
			hp += node.get_network_shield()
			elite_seen = true
		watched[node.get_instance_id()] = {"kind": kind, "initial": hp, "in_view": false, "hit": false}
		_event(kind + "_entry")
	elif path == ENEMY:
		if observed_trial and game.trial_tick > 0 and game.trial_tick < game.END_TICK:
			if fixed_births >= game.ORDERS.size():
				failed = true
				return
			var order: Dictionary = game.ORDERS[fixed_births]
			fixed_births += 1
			if game.trial_tick != order.at or node.enemy_type != order.kind or not node.position.is_equal_approx(game.field * order.from):
				failed = true
			_write("fixed_birth", {"id": fixed_births, "entry": {"formation": order.lane}, "at": first_choice_tick, "due": first_choice_tick + int(order.at)}, node.position, node.enemy_type)
			return
		for i in pending.size():
			var row := pending[i]
			if row.entry.pos == node.position and row.entry.type == node.enemy_type:
				_write("birth", row, node.position, node.enemy_type)
				pending.remove_at(i)
				director_births += 1
				if observed_trial and game.trial_tick == game.END_TICK and not director_resumed:
					director_resumed = true
					_event("director_resumed")
				return
		# 精英／Boss 自己召唤的杂兵没有导演订单，也必须留在出生流水里。
		_write("other_birth", {"id": 0, "entry": {"formation": "outside_director"}, "at": -1, "due": -1}, node.position, node.enemy_type)

func _write(kind: String, row: Dictionary, pos: Vector2, enemy_type: int) -> void:
	trace.store_csv_line([kind, str(_tick()), str(row.id), str(row.entry.formation), str(enemy_type), str(pos.x), str(pos.y), str(row.at), str(row.due)])
