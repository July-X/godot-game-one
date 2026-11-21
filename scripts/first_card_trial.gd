extends "res://scripts/main.gd"
## 单人首卡试飞。出生和扇弹只读游戏时钟，与选卡、击杀数及随机导演无关。
const Enemy := preload("res://scripts/enemy.gd")
const TrialPalette := preload("res://scripts/palette.gd")
const FIRST_OFFER := ["pierce", "splash", "graze_focus"]
# 出生和停靠点按视口比例排列。右队先分开进入，再收拢到溅射半径内。
const ORDERS := [
	{"at": 12, "lane": "column", "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .43)},
	{"at": 34, "lane": "column", "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .34)},
	{"at": 56, "lane": "column", "kind": 0, "from": Vector2(.30, -.05), "to": Vector2(.30, .25)},
	{"at": 72, "lane": "cluster", "kind": 0, "from": Vector2(.59, -.05), "to": Vector2(.71, .30)},
	{"at": 84, "lane": "cluster", "kind": 1, "from": Vector2(.74, -.05), "to": Vector2(.74, .25)},
	{"at": 96, "lane": "cluster", "kind": 0, "from": Vector2(.89, -.05), "to": Vector2(.77, .30)},
]
const ARRIVAL_TICKS := 100
const RETREAT_TICK := 278
const VOLLEYS := [338, 368, 398]
const END_TICK := 550
const FAN_EXITS := [.59, .73, .87]

@export var from_draft := false
var trial_tick := -1
var next_order := 0
var squad: Array[CharacterBody2D] = []
var field: Vector2
var asteroid_resume := 0.0
var regular_draft_hint := ""

func _ready() -> void:
	super._ready()
	UpgradeDraft.clear_drafts()
	from_draft = from_draft or "--from-draft" in OS.get_cmdline_user_args()
	$TrialUI/Options.hide()
	$TrialUI/Options/Power.pressed.connect(_choose_power)
	$TrialUI/Options/Retry.pressed.connect(_restart)
	$TrialUI/Options/Back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn"))
	UpgradeDraft.card_chosen.connect(_start_trial)
	if from_draft:
		_player.position = get_viewport_rect().size * Vector2(.50, .78)
		GameState.level_up()

func _exit_tree() -> void:
	UpgradeDraft.clear_drafts()

func _on_level_up(new_level: int) -> void:
	if new_level != 2 or trial_tick >= 0:
		super._on_level_up(new_level)
		return
	asteroid_resume = _asteroid_timer
	_asteroid_timer = INF
	# 旧弹和残敌退出本次换波，保留分数、掉落和玩家当前位置。
	for group in ["enemies", "asteroids", "enemy_bullets", "player_bullets"]:
		for unit in get_tree().get_nodes_in_group(group):
			unit.queue_free()
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.on_level_up()
	$TrialUI/Options.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hint: Label = _hud.get_node("DraftPanel/DraftHint")
	regular_draft_hint = hint.text
	hint.text = "首卡选定后进场 · 超时取第一张"
	UpgradeDraft.offer_cards(1, FIRST_OFFER)

func _choose_power() -> void:
	if GameState.level == 2 and trial_tick < 0 and UpgradeDraft.has_draft(1):
		UpgradeDraft.offer_cards(1, ["power"])
		UpgradeDraft.choose_card(1, 0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_4, KEY_KP_4]:
		_choose_power()
	else:
		super._input(event)

func _start_trial(_pid: int, _card: String, _index: int) -> void:
	if trial_tick >= 0:
		return
	trial_tick = 0
	field = get_viewport_rect().size
	$TrialUI/Options.hide()
	_player.set_physics_process(true)
	_player.set_process_unhandled_input(true)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.set_wave_phase("首卡试飞 · 中路可通行", Color.LIGHT_CYAN)

func _tick_wave_director(delta: float) -> void:
	if GameState.level < 2 or (trial_tick >= END_TICK and not from_draft):
		super._tick_wave_director(delta)

func _physics_process(_delta: float) -> void:
	if trial_tick < 0 or trial_tick >= END_TICK or not GameState.game_running:
		return
	trial_tick += 1
	while next_order < ORDERS.size() and ORDERS[next_order].at == trial_tick:
		var order: Dictionary = ORDERS[next_order]
		var ship = _spawn_enemy_at(order.kind, field * order.from)
		ship.set_physics_process(false)
		ship.rotation = PI
		ship.drop_chance = 0.0
		# 同一物理帧的后续炮弹和溅射不能再次给这架已击毁的靶机计分。
		ship.enemy_died.connect(ship.remove_from_group.bind("enemies"), CONNECT_ONE_SHOT)
		squad.append(ship)
		next_order += 1
	for i in squad.size():
		var ship = squad[i]
		if not is_instance_valid(ship):
			continue
		var order: Dictionary = ORDERS[i]
		var travel := clampf(float(trial_tick - int(order.at)) / ARRIVAL_TICKS, 0.0, 1.0)
		var retreat := clampf(float(trial_tick - RETREAT_TICK) / 50.0, 0.0, 1.0)
		ship.position = field * (order.from as Vector2).lerp(order.to, travel)
		ship.position.y = lerpf(ship.position.y, -40.0, retreat)
		ship.get_node("HealthBar").value = ship.health
		if retreat >= 1.0:
			ship.queue_free()
	if trial_tick == RETREAT_TICK:
		_hud.set_wave_phase("右侧扇弹 · 中路可通行", Color.LIGHT_CYAN)
		queue_redraw()
	if trial_tick in VOLLEYS:
		for end_x: float in FAN_EXITS:
			var bullet = Pool.acquire("bullet", _bullet_scene)
			add_child(bullet)
			var start := _fan_origin()
			var direction := start.direction_to(field * Vector2(end_x, 1.0))
			bullet.setup(start, direction.angle(), 0.3, false, 1, Enemy.SPEED_SLOW)
			bullet.modulate = TrialPalette.ENEMY_BULLET_SLOW
		if trial_tick == VOLLEYS[0]:
			queue_redraw()
	if trial_tick == END_TICK:
		if not from_draft:
			_asteroid_timer = asteroid_resume
			_hud.get_node("DraftPanel/DraftHint").text = regular_draft_hint
			_last_wave_phase_text = ""
			_refresh_wave_phase_hud()
			return
		_player.set_physics_process(false)
		_player.set_process_unhandled_input(false)
		_hud.set_wave_phase("试飞结束", Color.LIGHT_CYAN)
		$TrialUI/Options/Power.hide()
		$TrialUI/Options/Retry.show()
		$TrialUI/Options.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _fan_origin() -> Vector2:
	return Vector2(field.x * .75, 0)

func _draw() -> void:
	if trial_tick >= RETREAT_TICK and trial_tick < VOLLEYS[0]:
		var color := Color(TrialPalette.WARN_LINE, .46)
		for end_x: float in FAN_EXITS:
			draw_line(_fan_origin(), field * Vector2(end_x, 1.0), color, 2.0)
