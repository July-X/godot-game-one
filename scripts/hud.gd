extends CanvasLayer
const Palette = preload("res://scripts/palette.gd")
## HUD 控制器 — 动态技能条 + 像素风 UI

@onready var _score_label: Label = $ScoreLabel
@onready var _level_label: Label = $LevelLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _hp_num: Label = $HealthBar/HPNum
@onready var _player_scores_label: Label = $PlayerScoresLabel
@onready var _powerup_display: VBoxContainer = $PowerupDisplay
@onready var _graze_label: Label = $GrazeLabel
@onready var _draft_panel: VBoxContainer = $DraftPanel
@onready var _draft_title: Label = $DraftPanel/DraftTitle
@onready var _draft_row: HBoxContainer = $DraftPanel/CardRow
@onready var _evolution_label: Label = $EvolutionLabel
@onready var _dash_label: Label = $DashLabel
@onready var _downed_label: Label = $DownedLabel
@onready var _revive_bar: ProgressBar = $ReviveBar
@onready var _controls_label: Label = $ControlsLabel
@onready var _fps_label: Label = $FpsLabel
@onready var _game_over_panel: Panel = $GameOverPanel
@onready var _final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var _final_level_label: Label = $GameOverPanel/VBox/FinalLevelLabel
@onready var _restart_label: Label = $GameOverPanel/VBox/RestartLabel
@onready var _perm_leaderboard_entries: VBoxContainer = $LeaderboardPanel/LeaderboardEntries
@onready var _skill_bar: HBoxContainer = $SkillBar

var _damage_flash: ColorRect

## 技能槽数据（新增技能只需在这里加一条）
## {name, action, key, bar_color}
var _skill_data: Array[Dictionary] = []
## 运行时生成的技能槽节点列表
var _skill_slots: Array[Dictionary] = []
var _cached_spread_level: int = -1
var _cached_speed_level: int = -1
var _cached_power_level: int = -1
var _cached_extra_bullet_count: int = -1
var _cached_extra_damage_bonus: int = -1
var _cached_laser_cd_bonus: float = -1.0
var _cached_move_speed_bonus: float = -1.0
var _cached_shield_cur: int = -1
var _cached_shield_max: int = -1
var _cached_score: int = -1
var _cached_player_scores_signature: String = ""
var _fps_accum: float = 0.0
var _active_pickup_toasts: Array = []
var _boss_status_root: Control = null
var _boss_status_fill: ColorRect = null
var _boss_status_label: Label = null
var _boss_status_phase: Label = null
const POWERUP_BAR_WIDTH: int = 120
const POWERUP_BAR_HEIGHT: int = 14
const BOSS_BONUS_LASER_CD_MAX: float = 5.0
const BOSS_BONUS_BULLET_COUNT_MAX: float = 4.0
const BOSS_BONUS_DAMAGE_MAX: float = 20.0
const BOSS_BONUS_MOVE_SPEED_MAX: float = 0.5
const SKILL_SLOT_DESKTOP: Vector2 = Vector2(144, 144)
const SKILL_SLOT_MOBILE: Vector2 = Vector2(116, 116)
const SKILL_BAR_MOBILE_MARGIN: Vector2 = Vector2(30, 38)
const SKILL_BAR_DESKTOP_MARGIN: Vector2 = Vector2(20, 18)

func _ready() -> void:
	set_process(true)
	layer = 20
	_game_over_panel.visible = false
	_set_control_ignore_input(_game_over_panel)
	_set_control_ignore_input($LeaderboardPanel)
	_score_label.z_index = 30
	_level_label.z_index = 30
	_player_scores_label.z_index = 30
	_health_bar.z_index = 30
	_powerup_display.z_index = 30
	_controls_label.z_index = 30
	_fps_label.z_index = 30
	_skill_bar.z_index = 30
	_skill_bar.visible = true
	_skill_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_setup_damage_flash()
	_update_platform_hints()
	_setup_skill_bar()
	_layout_skill_bar()
	if get_viewport() and not get_viewport().size_changed.is_connected(_layout_skill_bar):
		get_viewport().size_changed.connect(_layout_skill_bar)

	GameState.score_changed.connect(_on_score_changed)
	GameState.level_changed.connect(_on_level_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.powerup_collected.connect(_on_powerup_collected)
	GameState.player_scores_changed.connect(_on_player_scores_changed)
	_update_score(0)
	_update_level(1)
	_update_health(GameState.get_current_health(), GameState.get_max_health())
	_update_player_scores(GameState.get_all_player_scores(), GameState.score)
	_update_powerup_display()
	_refresh_leaderboard()

func _process(_delta: float) -> void:
	_refresh_score_if_needed()
	_update_cooldowns()
	_refresh_powerup_display_if_needed()
	_update_graze_display()
	_update_draft_panel()
	_update_evolution_display()
	_update_downed_display()
	_update_dash_display()
	_update_fps(_delta)


## 闪避冷却提示
##
## 闪避有 1.1 秒 CD，玩家很容易在冷却里还去按。必须把"能不能闪"直接显示出来，
## 否则失败反馈是"按了没反应"，会被理解成游戏卡了。
func _update_dash_display() -> void:
	if _dash_label == null:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("_player"):
		_dash_label.visible = false
		return
	var pl: Node = scene.get("_player")
	if pl == null or not is_instance_valid(pl) or not pl.has_method("can_dash"):
		_dash_label.visible = false
		return
	var ready: bool = pl.can_dash()
	_dash_label.visible = true
	if ready:
		_dash_label.text = "闪避就绪（Shift）"
		_dash_label.add_theme_color_override("font_color", Palette.DASH_READY)
	else:
		_dash_label.text = "闪避冷却 %.1fs" % (1.1 - pl.get_dash_cooldown_ratio() * 1.1)
		_dash_label.add_theme_color_override("font_color", Palette.DASH_COOLDOWN)


## 倒地 / 救援 HUD
##
## 救援的时间压力必须可视化：倒地者只剩 20 秒，队友必须知道还剩多少时间、
## 自己的按住进度到哪了。没有这个反馈，1.2 秒的按住会显得像"没反应"。
func _update_downed_display() -> void:
	if _downed_label == null or _revive_bar == null:
		return
	var downed_node: Node = _nearest_downed_node()
	if downed_node == null:
		_downed_label.visible = false
		_revive_bar.visible = false
		return
	var left: float = float(downed_node.get_downed_time_left())
	_downed_label.visible = true
	_revive_bar.visible = true
	var warn: bool = left <= 5.0
	_downed_label.text = "队友倒地！按住 E 救援  剩余 %.0f 秒" % left
	_downed_label.add_theme_color_override("font_color",
		Palette.DOWNED_CRITICAL if warn else Palette.DOWNED_SAFE)
	_revive_bar.value = float(downed_node.get_revive_ratio()) * 100.0


## 场景里最近的倒地队友
func _nearest_downed_node() -> Node:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("_players"):
		return null
	var players: Dictionary = scene.get("_players")
	var me: Node = scene.get("_player")
	var best: Node = null
	var best_d: float = INF
	for pid: Variant in players.keys().duplicate():
		## 同 _tick_downed_rescue：先取 Variant 判有效性再强转，
		## 否则节点已 queue_free 时会抛 "assign invalid previously freed instance"
		var raw: Variant = players.get(pid)
		if not is_instance_valid(raw):
			continue
		var node := raw as Node
		if node == null or not node.has_method("go_downed") or not node.is_downed:
			continue
		if node == me:
			continue
		var d: float = 0.0
		if me != null and is_instance_valid(me) and node is Node2D:
			d = (me as Node2D).global_position.distance_to((node as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## ── 升级三选一面板 ──────────────────────────────────────
##
## 面板不暂停游戏、不锁定鼠标：玩家在选卡时仍然可以走位。
## 这是本作的设计要求（"全自动射击 + 只用鼠标走位"），
## 所以选卡用 1/2/3 键而不是点击。
##
## 排版原则：**图标是主要信息通道，文字只是补充**。
## 弹幕战斗中玩家只有零点几秒扫一眼，字号小的说明文字根本读不完；
## 图标（贯穿的箭头、爆开的星芒、弯曲的追踪线）能在 0.2 秒内传达效果。
var _card_icon_script = preload("res://scripts/card_icon.gd")
var _draft_card_icons: Array = []
## 每张卡是一对 [名字 Label, 说明 Label]
var _draft_card_labels: Array = []

func _update_draft_panel() -> void:
	if _draft_panel == null:
		return
	var my_pid: int = _local_peer_id()
	if not UpgradeDraft.has_draft(my_pid):
		_draft_panel.visible = false
		return
	var draft: Dictionary = UpgradeDraft.get_draft(my_pid)
	var cards: Array = draft.get("cards", [])
	_draft_panel.visible = true
	## 首次出现时才建卡片，之后只更新内容（避免每帧重建节点）
	while _draft_card_labels.size() < cards.size():
		var panel := PanelContainer.new()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		## 卡片放大到 210 宽：图标 40px + 名字 16px + 一行说明 13px，
		## 在 1280×720 的视口里占据约 1/6 宽度，远处也能看清图标
		panel.custom_minimum_size = Vector2(210, 132)
		var icon := Control.new()
		icon.set_script(_card_icon_script)
		icon.custom_minimum_size = Vector2(0, 44)
		var l := Label.new()
		l.custom_minimum_size = Vector2(200, 22)
		l.add_theme_font_size_override("font_size", 16)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l2 := Label.new()
		l2.custom_minimum_size = Vector2(200, 20)
		l2.add_theme_font_size_override("font_size", 13)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(icon)
		box.add_child(l)
		box.add_child(l2)
		panel.add_child(box)
		_draft_row.add_child(panel)
		_draft_card_icons.append(icon)
		_draft_card_labels.append([l, l2])
	for i in range(_draft_card_labels.size()):
		var pair: Array = _draft_card_labels[i]
		var name_label: Label = pair[0]
		var desc_label: Label = pair[1]
		var icon: Control = _draft_card_icons[i]
		if i < cards.size():
			var card: Dictionary = UpgradeDraft.card_by_id(str(cards[i]))
			name_label.visible = true
			desc_label.visible = true
			icon.visible = true
			## 风格卡（青）与数值卡（白）用颜色区分：改变操作方式的卡
			## 才是构筑主体，要一眼能挑出来
			var tint: Color = Palette.CARD_STYLE if str(card.get("kind", "stat")) == "style" \
				else Palette.CARD_STAT
			name_label.add_theme_color_override("font_color", tint)
			desc_label.add_theme_color_override("font_color",
				Color(0.72, 0.72, 0.8, 1.0))
			## 名字带 [1]/[2]/[3] 前缀，按键和卡片位置一一对应
			name_label.text = "[%d] %s" % [i + 1, str(card.get("name", ""))]
			desc_label.text = str(card.get("desc", ""))
			icon.setup(str(card.get("icon", card.get("id", ""))), tint)
		else:
			name_label.visible = false
			desc_label.visible = false
			icon.visible = false
	_draft_title.text = "升级！按 1 / 2 / 3 选择  (%.0f 秒)" % float(draft.get("left", 0.0))


## 已激活的组合进化提示。玩家看不到自己解锁了什么，
## 组合进化就只是"数值莫名变强"，构筑感建立不起来。
func _update_evolution_display() -> void:
	if _evolution_label == null:
		return
	var evos: Array = GameState.get_active_evolutions(_local_peer_id())
	if evos.is_empty():
		_evolution_label.visible = false
		return
	_evolution_label.visible = true
	var names: Array = []
	for evo: Dictionary in evos:
		names.append(str(evo.get("name", "")))
	_evolution_label.text = "进化：%s" % " · ".join(PackedStringArray(names))


func _local_peer_id() -> int:
	if NetworkManager.is_online() and multiplayer != null \
			and multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


## 擦弹层数指示。**必须有这个提示**：擦弹是"主动贴着子弹飞"的机制，
## 玩家不知道它存在、也看不到收益，就永远不会去尝试。
## 层数归零时隐藏而不是显示 0，避免常驻一行没用的字。
func _update_graze_display() -> void:
	if _graze_label == null:
		return
	var stacks: int = GameState.get_graze_stacks()
	if stacks <= 0:
		_graze_label.visible = false
		return
	_graze_label.visible = true
	var bonus: int = int(round(GameState.get_graze_fire_rate_bonus() * 100.0))
	_graze_label.text = "擦弹 ×%d  射速 +%d%%" % [stacks, bonus]


## ── 动态技能条 ──────────────────────────────────────────────
## 定义技能、动态创建按钮、按 action 触发技能
func _setup_skill_bar() -> void:
	_skill_data = [
		{
			"name": "激光",
			"action": "laser", "key": KEY_Q,
			"bar_color": Color(0.25, 0.12, 0.85),
		},
		{
			"name": "散射",
			"action": "skill", "key": KEY_W,
			"bar_color": Color(0.15, 0.72, 0.28),
		},
	]

	for data in _skill_data:
		_create_skill_slot(data)

## 动态创建单个技能按钮
func _create_skill_slot(data: Dictionary) -> void:
	var slot_size := _get_skill_slot_size() * 0.8

	# Button 容器
	var btn := Button.new()
	btn.custom_minimum_size = slot_size
	btn.size = slot_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty_sb := StyleBoxFlat.new()
	empty_sb.bg_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	btn.focus_mode = Control.FOCUS_NONE
	btn.z_index = 30
	btn.pressed.connect(_on_skill_slot_pressed.bind(data))
	btn.gui_input.connect(_on_skill_slot_gui_input.bind(data))

	# 半透明背景框
	var bg := ColorRect.new()
	bg.size = slot_size
	bg.color = Color(0, 0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = 1
	btn.add_child(bg)

	# 冷却覆盖层
	var overlay := ColorRect.new()
	overlay.size = slot_size - Vector2(4, 4)
	overlay.position = Vector2(2, 2)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(1, 1, 1, 0)
	overlay.set_script(preload("res://scripts/cooldown_overlay.gd"))
	overlay.z_index = 2
	btn.add_child(overlay)

	# 技能图标（AI 生成像素图）
	var icon_tex := TextureRect.new()
	icon_tex.size = slot_size
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_tex.z_index = 3
	var tex_path: String = "res://assets/sprites/ui/skill_%s.png" % data.action
	if ResourceLoader.exists(tex_path):
		icon_tex.texture = load(tex_path)
	btn.add_child(icon_tex)

	_skill_bar.add_child(btn)
	# 冷却数字标签（覆盖在图标上方）
	var cd_label := Label.new()
	cd_label.size = slot_size
	cd_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1))
	cd_label.add_theme_font_size_override("font_size", 44)
	cd_label.horizontal_alignment = 1
	cd_label.vertical_alignment = 1
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_label.z_index = 4
	btn.add_child(cd_label)

	var name_lbl := Label.new()
	name_lbl.position = Vector2(0, slot_size.y - 36.0)
	name_lbl.size = Vector2(slot_size.x, 22)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.95))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	name_lbl.add_theme_constant_override("shadow_outline_size", 1)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.z_index = 5
	name_lbl.text = data.name
	btn.add_child(name_lbl)

	_skill_slots.append({
		"data": data,
		"button": btn,
		"bg": bg,
		"icon": icon_tex,
		"name": name_lbl,
		"overlay": overlay,
		"cd_label": cd_label,
	})
	_layout_skill_slot(_skill_slots[_skill_slots.size() - 1], slot_size)

func _get_skill_slot_size() -> Vector2:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return SKILL_SLOT_MOBILE
	return SKILL_SLOT_DESKTOP

func _layout_skill_bar() -> void:
	if _skill_bar == null:
		return
	var slot_size := _get_skill_slot_size() * 0.8
	var gap: float = 8.0
	var count: int = max(_skill_slots.size(), 2)
	var bar_size := Vector2(slot_size.x * float(count) + gap * float(count - 1), slot_size.y)
	_skill_bar.size = bar_size
	_skill_bar.custom_minimum_size = bar_size
	_skill_bar.add_theme_constant_override("separation", int(gap))
	_skill_bar.anchor_left = 1.0
	_skill_bar.anchor_top = 1.0
	_skill_bar.anchor_right = 1.0
	_skill_bar.anchor_bottom = 1.0
	if OS.has_feature("android") or OS.has_feature("ios"):
		_skill_bar.offset_left = -bar_size.x - SKILL_BAR_MOBILE_MARGIN.x
		_skill_bar.offset_top = -bar_size.y - SKILL_BAR_MOBILE_MARGIN.y
		_skill_bar.offset_right = -SKILL_BAR_MOBILE_MARGIN.x
		_skill_bar.offset_bottom = -SKILL_BAR_MOBILE_MARGIN.y
	else:
		_skill_bar.offset_left = -bar_size.x - SKILL_BAR_DESKTOP_MARGIN.x
		_skill_bar.offset_top = -bar_size.y - SKILL_BAR_DESKTOP_MARGIN.y
		_skill_bar.offset_right = -SKILL_BAR_DESKTOP_MARGIN.x
		_skill_bar.offset_bottom = -SKILL_BAR_DESKTOP_MARGIN.y
	for slot in _skill_slots:
		_layout_skill_slot(slot, slot_size)
	if _boss_status_root:
		var canvas_size := _get_design_canvas_size()
		_boss_status_root.position = Vector2(maxf((canvas_size.x - 560.0) * 0.5, 16.0), 16.0)
	call_deferred("_verify_skill_bar_layout")

func _layout_skill_slot(slot: Dictionary, slot_size: Vector2) -> void:
	if slot.is_empty():
		return
	var btn: Button = slot.button
	btn.custom_minimum_size = slot_size
	btn.size = slot_size
	var bg: ColorRect = slot.bg
	bg.size = slot_size
	var overlay: Control = slot.overlay
	overlay.size = slot_size - Vector2(4, 4)
	var icon_tex: TextureRect = slot.icon
	icon_tex.size = slot_size
	var cd_label: Label = slot.cd_label
	cd_label.size = slot_size
	cd_label.add_theme_font_size_override("font_size", 34 if slot_size.x < 130.0 else 44)
	var name_lbl: Label = slot.name
	name_lbl.position = Vector2(0, slot_size.y - 34.0)
	name_lbl.size = Vector2(slot_size.x, 22.0)

func _get_design_canvas_size() -> Vector2:
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var height := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	return Vector2(width, height)

func _verify_skill_bar_layout() -> void:
	if _skill_bar == null:
		return
	var rect := _skill_bar.get_global_rect()
	var canvas_size := _get_design_canvas_size()
	var outside := rect.position.x > canvas_size.x \
		or rect.position.y > canvas_size.y \
		or rect.end.x < 0.0 \
		or rect.end.y < 0.0
	if outside:
		push_error("[HUD] SkillBar outside design canvas: rect=%s canvas=%s. Resetting to bottom-right anchors." % [str(rect), str(canvas_size)])
		var slot_size := _get_skill_slot_size() * 0.8
		var bar_size := Vector2(slot_size.x * 2.0 + 8.0, slot_size.y)
		_skill_bar.anchor_left = 1.0
		_skill_bar.anchor_top = 1.0
		_skill_bar.anchor_right = 1.0
		_skill_bar.anchor_bottom = 1.0
		_skill_bar.offset_left = -bar_size.x - 20.0
		_skill_bar.offset_top = -bar_size.y - 18.0
		_skill_bar.offset_right = -20.0
		_skill_bar.offset_bottom = -18.0
	if _skill_slots.size() < 2:
		push_error("[HUD] SkillBar expected 2 skill slots, got %d." % _skill_slots.size())

## 技能按钮被点击 / 触屏触发
func _on_skill_slot_pressed(data: Dictionary) -> void:
	match data.action:
		"skill": _trigger_skill()
		"laser": _trigger_laser()

## 移动端触屏技能按钮
func _on_skill_slot_gui_input(event: InputEvent, data: Dictionary) -> void:
	if event is InputEventScreenTouch and event.pressed:
		match data.action:
			"skill": _trigger_skill()
			"laser": _trigger_laser()

func _update_cooldowns() -> void:
	for slot in _skill_slots:
		var action: String = slot.data.action
		var cd: float = 0.0
		var cd_max: float = 0.0
		match action:
			"skill":
				cd = GameState.get_skill_cooldown()
				cd_max = GameState.SKILL_COOLDOWN_MAX
			"laser":
				cd = GameState.get_laser_cooldown()
				cd_max = GameState.get_laser_cooldown_max()
		var progress: float = 1.0 - cd / cd_max if cd_max > 0 else 1.0
		slot.overlay.set_ready_progress(progress)
		if cd > 0:
			slot.cd_label.visible = true
			slot.cd_label.text = str(int(ceil(cd)))
			slot.cd_label.add_theme_font_size_override("font_size", 40)
		else:
			slot.cd_label.visible = false

## ── 技能触发 ────────────────────────────────────────────────

func _trigger_skill() -> void:
	var player := _resolve_local_player()
	if player and player.has_method("request_action"):
		player.request_action("skill")
	elif player and player.has_node("ActionRouter"):
		var router := player.get_node("ActionRouter")
		if router and router.has_method("request_action"):
			router.request_action("skill")
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _trigger_laser() -> void:
	var player := _resolve_local_player()
	if player and player.has_method("request_action"):
		player.request_action("laser")
	elif player and player.has_node("ActionRouter"):
		var router := player.get_node("ActionRouter")
		if router and router.has_method("request_action"):
			router.request_action("laser")
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _resolve_local_player() -> Node:
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if not NetworkManager.is_online():
			return p
		if p.has_method("get") and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
			var maybe_peer: Variant = p.get("peer_id")
			if typeof(maybe_peer) == TYPE_INT and int(maybe_peer) == multiplayer.get_unique_id():
				return p
		if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
			return p
	return null

## ── 信号响应 ────────────────────────────────────────────────

func _on_score_changed(new_score: int) -> void:
	_update_score(new_score)

func _on_level_changed(new_level: int) -> void:
	_update_level(new_level)

func _on_player_scores_changed(scores: Dictionary, total_score: int) -> void:
	_update_player_scores(scores, total_score)
	_refresh_leaderboard()

func _on_health_changed(current: int, maximum: int) -> void:
	_update_health(current, maximum)

func _on_game_over(final_score: int, final_level: int) -> void:
	_game_over_panel.visible = true
	_final_score_label.text = "得分: %d" % final_score
	_final_level_label.text = "等级: %d" % final_level
	Leaderboard.add_entry(final_score, final_level, GameState.get_all_player_scores())
	_refresh_leaderboard()

func _on_powerup_collected(type: String) -> void:
	_update_powerup_display()

func _refresh_powerup_display_if_needed() -> void:
	var spread_level := GameState.get_shoot_level()
	var speed_level := GameState.get_shoot_speed_level()
	var power_level := GameState.get_bullet_power_level()
	var extra_bullet_count := GameState.get_extra_bullet_count()
	var extra_damage_bonus := GameState.get_extra_damage_bonus()
	var laser_cd_bonus := GameState.get_laser_cd_bonus()
	var move_speed_bonus := GameState.get_move_speed_bonus()
	var shield_cur := GameState.get_shield_layers()
	var shield_max := GameState.get_shield_max_hp()
	if spread_level == _cached_spread_level \
	and speed_level == _cached_speed_level \
	and power_level == _cached_power_level \
	and extra_bullet_count == _cached_extra_bullet_count \
	and extra_damage_bonus == _cached_extra_damage_bonus \
	and is_equal_approx(laser_cd_bonus, _cached_laser_cd_bonus) \
	and is_equal_approx(move_speed_bonus, _cached_move_speed_bonus) \
	and _cached_shield_cur == shield_cur \
	and _cached_shield_max == shield_max:
		return
	_update_powerup_display()

## ── 显示更新 ────────────────────────────────────────────────

func _update_score(score: int) -> void:
	_score_label.text = "总分: %d" % score
	_cached_score = score

func _refresh_score_if_needed() -> void:
	var current_score: int = GameState.score
	var current_scores_signature: String = str(GameState.get_all_player_scores())
	if current_score != _cached_score:
		_update_score(current_score)
	if current_scores_signature != _cached_player_scores_signature:
		_cached_player_scores_signature = current_scores_signature
		_update_player_scores(GameState.get_all_player_scores(), current_score)

func _update_level(level: int) -> void:
	_level_label.text = "等级 %d" % level

func _update_player_scores(scores: Dictionary, total_score: int) -> void:
	if _player_scores_label == null:
		return
	var rows: Array[String] = []
	var keys: Array = scores.keys()
	keys.sort()
	for key in keys:
		if not String(key).is_valid_int():
			continue
		var pid: int = int(String(key))
		rows.append("%s: %d" % [_peer_label(pid), int(scores[key])])
	if rows.is_empty():
		_player_scores_label.text = "P1: 0  |  P2: 0"
	else:
		_player_scores_label.text = "  |  ".join(rows)
	_score_label.text = "总分: %d" % total_score
	_cached_score = total_score
	_cached_player_scores_signature = str(scores)

func _peer_label(peer_id: int) -> String:
	## ENet 的 Client peer_id 不保证固定为 2；本项目限制 1 个 Client，
	## 因此 UI 层按角色槽位显示：Host=P1，唯一 Client=P2。
	if peer_id == 1:
		return "P1"
	return "P2"

func _update_health(current: int, maximum: int) -> void:
	if _health_bar:
		_health_bar.max_value = maximum
		_health_bar.value = current
	if _hp_num:
		_hp_num.text = "%d/%d" % [current, maximum]

func _update_powerup_display() -> void:
	var prev_spread_level := _cached_spread_level
	var prev_speed_level := _cached_speed_level
	var prev_power_level := _cached_power_level
	var prev_extra_bullet_count := _cached_extra_bullet_count
	var prev_extra_damage_bonus := _cached_extra_damage_bonus
	var prev_laser_cd_bonus := _cached_laser_cd_bonus
	var prev_move_speed_bonus := _cached_move_speed_bonus

	_cached_spread_level = GameState.get_shoot_level()
	_cached_speed_level = GameState.get_shoot_speed_level()
	_cached_power_level = GameState.get_bullet_power_level()
	_cached_extra_bullet_count = GameState.get_extra_bullet_count()
	_cached_extra_damage_bonus = GameState.get_extra_damage_bonus()
	_cached_laser_cd_bonus = GameState.get_laser_cd_bonus()
	_cached_move_speed_bonus = GameState.get_move_speed_bonus()
	for child in _powerup_display.get_children():
		child.queue_free()

	var labels := {
		"spread": {"name": "扩散", "color": Color(0.3, 1.0, 0.4), "bar": Color(0.2, 0.8, 0.3)},
		"speed": {"name": "速射", "color": Color(0.4, 0.7, 1.0), "bar": Color(0.3, 0.6, 1.0)},
		"power": {"name": "威力", "color": Color(1.0, 0.4, 0.3), "bar": Color(0.9, 0.3, 0.2)},
	}
	## 护盾值进度条
	var shield_cur: int = GameState.get_shield_layers()
	var shield_max: int = GameState.get_shield_max_hp()
	_cached_shield_cur = shield_cur
	_cached_shield_max = shield_max
	if shield_max > 0:
		var shield_fill_w: int = int(POWERUP_BAR_WIDTH * float(min(shield_cur, shield_max)) / float(shield_max))
		_add_powerup_bar(
			"护盾",
			Color(0.35, 0.65, 1.0, 0.95),
			Color(0.3, 0.55, 0.95, 1.0),
			shield_fill_w,
			"%d/%d" % [shield_cur, shield_max]
		)

	var ordered_types: Array[String] = ["spread", "speed", "power"]
	for type in ordered_types:
		var level: int = 0
		var max_level: int = 15
		match type:
			"spread":
				level = GameState.get_shoot_level()
				max_level = 10
			"speed":
				level = GameState.get_shoot_speed_level()
				max_level = 10
			"power":
				level = GameState.get_bullet_power_level()
				max_level = 50
		if level <= 0:
			continue

		var prev_level: int = -1
		match type:
			"spread":
				prev_level = prev_spread_level
			"speed":
				prev_level = prev_speed_level
			"power":
				prev_level = prev_power_level
		var bar_w: int = POWERUP_BAR_WIDTH
		var bar_h: int = POWERUP_BAR_HEIGHT
		var fill_w: int = int(bar_w * float(level) / float(max_level))
		var prev_fill_w: int = 0
		if prev_level > 0:
			prev_fill_w = int(bar_w * float(prev_level) / float(max_level))

		_add_powerup_bar(
			labels[type].name,
			labels[type].color,
			labels[type].bar,
			fill_w,
			"%d/%d" % [level, max_level],
			prev_fill_w,
			prev_level >= 0 and prev_level != level
		)

	_render_boss_bonus_section()

	if prev_extra_bullet_count != _cached_extra_bullet_count \
	or prev_extra_damage_bonus != _cached_extra_damage_bonus \
	or not is_equal_approx(prev_laser_cd_bonus, _cached_laser_cd_bonus) \
	or not is_equal_approx(prev_move_speed_bonus, _cached_move_speed_bonus):
		_pulse_powerup_bonus_lines()


func _render_boss_bonus_section() -> void:
	var has_bullet := _cached_extra_bullet_count > 0
	var has_damage := _cached_extra_damage_bonus > 0
	var has_laser := _cached_laser_cd_bonus > 0.0
	var has_speed := _cached_move_speed_bonus > 0.0
	if not has_bullet and not has_damage and not has_laser and not has_speed:
		return
	_add_boss_bonus_group_header()
	if has_bullet:
		_add_boss_bonus_bar("弹幕", float(_cached_extra_bullet_count), BOSS_BONUS_BULLET_COUNT_MAX, "+%d/%d" % [_cached_extra_bullet_count, int(BOSS_BONUS_BULLET_COUNT_MAX)], Color(1.0, 0.78, 0.28), Color(1.0, 0.58, 0.16))
	if has_damage:
		_add_boss_bonus_bar("火力", float(_cached_extra_damage_bonus), BOSS_BONUS_DAMAGE_MAX, "+%d/%d" % [_cached_extra_damage_bonus, int(BOSS_BONUS_DAMAGE_MAX)], Color(1.0, 0.58, 0.32), Color(1.0, 0.35, 0.18))
	if has_laser:
		_add_boss_bonus_bar("激光", _cached_laser_cd_bonus, BOSS_BONUS_LASER_CD_MAX, "-%.1f/%.1fs" % [_cached_laser_cd_bonus, BOSS_BONUS_LASER_CD_MAX], Color(0.58, 0.86, 1.0), Color(0.25, 0.72, 1.0))
	if has_speed:
		_add_boss_bonus_bar("移速", _cached_move_speed_bonus, BOSS_BONUS_MOVE_SPEED_MAX, "+%d/%d%%" % [int(round(_cached_move_speed_bonus * 100.0)), int(BOSS_BONUS_MOVE_SPEED_MAX * 100.0)], Color(0.7, 1.0, 0.58), Color(0.32, 0.88, 0.38))

func _add_boss_bonus_bar(name: String, value: float, max_value: float, value_text: String, name_color: Color, bar_color: Color) -> void:
	var fill_w := int(POWERUP_BAR_WIDTH * clampf(value / max(max_value, 0.001), 0.0, 1.0))
	_add_powerup_bar(name, name_color, bar_color, fill_w, value_text, 0, false, true)

func _add_boss_bonus_group_header() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 3)
	spacer.set_meta("boss_bonus_row", true)
	_powerup_display.add_child(spacer)
	var title := Label.new()
	title.text = "Boss强化"
	title.add_theme_color_override("font_color", Color(1.0, 0.74, 0.28, 0.98))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	title.add_theme_constant_override("shadow_outline_size", 1)
	title.add_theme_font_size_override("font_size", 11)
	title.set_meta("boss_bonus_label", true)
	_powerup_display.add_child(title)

func _add_powerup_bar(name: String, name_color: Color, bar_color: Color, fill_w: int, value_text: String, prev_fill_w: int = 0, animate: bool = false, is_boss_bonus: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if is_boss_bonus:
		row.set_meta("boss_bonus_row", true)
	_powerup_display.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = name + "  "
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_boss_bonus:
		name_lbl.set_meta("boss_bonus_label", true)
	row.add_child(name_lbl)

	var bg := ColorRect.new()
	bg.custom_minimum_size = Vector2(POWERUP_BAR_WIDTH, POWERUP_BAR_HEIGHT)
	bg.size = Vector2(POWERUP_BAR_WIDTH, POWERUP_BAR_HEIGHT)
	bg.color = Color(0.08, 0.08, 0.15, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

	var fill := ColorRect.new()
	fill.size = Vector2(clampi(fill_w, 0, POWERUP_BAR_WIDTH), POWERUP_BAR_HEIGHT)
	fill.color = bar_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_boss_bonus:
		fill.set_meta("boss_bonus_fill", true)
	bg.add_child(fill)

	var val_lbl := Label.new()
	val_lbl.size = Vector2(POWERUP_BAR_WIDTH, POWERUP_BAR_HEIGHT)
	val_lbl.text = value_text
	val_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	val_lbl.add_theme_font_size_override("font_size", 10)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_boss_bonus:
		val_lbl.set_meta("boss_bonus_label", true)
	bg.add_child(val_lbl)

	if animate:
		_animate_powerup_row(row, bg, fill, val_lbl, prev_fill_w, fill_w, POWERUP_BAR_HEIGHT, bar_color)

func _animate_powerup_row(row: Control, bg: ColorRect, fill: ColorRect, val_lbl: Label, prev_fill_w: int, fill_w: int, bar_h: int, bar_color: Color) -> void:
	row.scale = Vector2(0.98, 0.98)
	row.modulate = Color(1, 1, 1, 0.85)
	fill.modulate = Color(1.35, 1.35, 1.35, 1.0)
	val_lbl.modulate = Color(1, 1, 1, 0.75)
	var row_tween := create_tween().set_parallel(true)
	row_tween.tween_property(row, "scale", Vector2(1, 1), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	row_tween.tween_property(row, "modulate", Color(1, 1, 1, 1), 0.18)
	var fill_tween := create_tween().set_parallel(true)
	fill_tween.tween_property(fill, "modulate", Color(1, 1, 1, 1), 0.20)
	fill_tween.tween_property(val_lbl, "modulate", Color(1, 1, 1, 1), 0.20)
	if fill_w > prev_fill_w:
		var trail := ColorRect.new()
		trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		trail.z_index = 3
		trail.color = Color(1.0, 1.0, 1.0, 0.9)
		trail.position = Vector2(max(prev_fill_w - 4, 0), 0)
		trail.size = Vector2(14.0, float(bar_h))
		bg.add_child(trail)
		var trail_tween := create_tween().set_parallel(true)
		trail_tween.tween_property(trail, "position:x", max(fill_w - 10, 0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		trail_tween.tween_property(trail, "modulate:a", 0.0, 0.22)
		trail_tween.tween_callback(trail.queue_free)
	else:
		var edge_flash := ColorRect.new()
		edge_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge_flash.z_index = 3
		edge_flash.color = Color(bar_color.r, bar_color.g, bar_color.b, 0.55)
		edge_flash.position = Vector2(max(fill_w - 12, 0), 0)
		edge_flash.size = Vector2(12.0, float(bar_h))
		bg.add_child(edge_flash)
		var flash_tween := create_tween()
		flash_tween.tween_property(edge_flash, "modulate:a", 0.0, 0.16)
		flash_tween.tween_callback(edge_flash.queue_free)

func _pulse_powerup_bonus_lines() -> void:
	for child in _powerup_display.get_children():
		_pulse_boss_bonus_node(child)

func _pulse_boss_bonus_node(node: Node) -> void:
	if node is Label and bool(node.get_meta("boss_bonus_label", false)):
		var lbl := node as Label
		lbl.scale = Vector2(0.98, 0.98)
		lbl.modulate = Color(1.0, 0.95, 0.65, 0.75)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(lbl, "scale", Vector2(1, 1), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(lbl, "modulate", Color(1.0, 0.85, 0.4, 0.98), 0.18)
	if node is ColorRect and bool(node.get_meta("boss_bonus_fill", false)):
		var rect := node as ColorRect
		rect.modulate = Color(1.35, 1.35, 1.15, 1.0)
		var fill_tween := create_tween()
		fill_tween.tween_property(rect, "modulate", Color(1, 1, 1, 1), 0.22)
	for child in node.get_children():
		_pulse_boss_bonus_node(child)

func _setup_damage_flash() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.z_index = 200
	add_child(_damage_flash)
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if NetworkManager.is_online():
		## 多人下 GameState.health 是全局共享；避免队友受击触发本地红屏误闪。
		return
	var old_health: int = GameState.get_current_health()
	GameState.health_changed.connect(func(_cur: int, _max: int):
		var new_health: int = GameState.get_current_health()
		if new_health < old_health:
			if _damage_flash and is_instance_valid(_damage_flash):
				var tween := create_tween()
				tween.tween_property(_damage_flash, "color", Color(1.0, 0.0, 0.0, 0.18), 0.05)
				tween.tween_property(_damage_flash, "color", Color(1.0, 0.0, 0.0, 0.0), 0.25)
				tween.tween_callback(func(): _damage_flash.color = Color(1.0, 0.0, 0.0, 0.0))
		old_health = new_health
	)

func _set_control_ignore_input(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		_set_control_ignore_input(child)

func _refresh_leaderboard() -> void:
	for child in _perm_leaderboard_entries.get_children():
		child.queue_free()
	var score_rows: Array[Dictionary] = []
	var live_scores: Dictionary = GameState.get_all_player_scores()
	var live_keys: Array = live_scores.keys()
	live_keys.sort()
	for key in live_keys:
		var key_str := str(key)
		if not key_str.is_valid_int():
			continue
		var pid: int = int(key_str)
		score_rows.append({
			"peer_id": pid,
			"score": int(live_scores[key]),
		})
	score_rows.sort_custom(func(a, b): return int(a.score) > int(b.score))
	if score_rows.is_empty():
		score_rows.append({"peer_id": 1, "score": 0})
		score_rows.append({"peer_id": 2, "score": 0})
	for i in range(score_rows.size()):
		var row: Dictionary = score_rows[i]
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0, 0.9))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "#%d  %s : %d" % [i + 1, _peer_label(int(row.peer_id)), int(row.score)]
		_perm_leaderboard_entries.add_child(label)

	var entries := Leaderboard.get_entries()
	for entry in entries:
		var history := Label.new()
		history.add_theme_font_size_override("font_size", 10)
		history.add_theme_color_override("font_color", Color(0.52, 0.66, 0.9, 0.72))
		history.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		history.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var players_text := _format_leaderboard_players(entry)
		history.text = "历史 %s  总分:%d  %s  Lv.%d" % [str(entry.time), int(entry.score), players_text, int(entry.level)]
		_perm_leaderboard_entries.add_child(history)

func _format_leaderboard_players(entry: Dictionary) -> String:
	var players: Dictionary = entry.get("players", {})
	if players.is_empty():
		return "P1:0 P2:0"
	var keys: Array = players.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		var key_str := str(key)
		if not key_str.is_valid_int():
			continue
		parts.append("%s:%d" % [_peer_label(int(key_str)), int(players[key])])
	if parts.is_empty():
		return "P1:0 P2:0"
	return " ".join(parts)

func _update_platform_hints() -> void:
	var is_mobile: bool = OS.has_feature("android") or OS.has_feature("ios")
	var can_restart: bool = true
	if NetworkManager.is_online():
		can_restart = multiplayer.is_server()
	if is_mobile:
		if can_restart:
			_controls_label.text = "左侧轮盘 - 移动/转向\n自动射击\n点击屏幕重新开始"
			_restart_label.text = "点击屏幕重新开始"
		else:
			_controls_label.text = "左侧轮盘 - 移动/转向\n自动射击\n等待房主重新开始"
			_restart_label.text = "等待房主重新开始"
	else:
		if can_restart:
			_controls_label.text = "鼠标 - 移动/瞄准\nESC - 释放鼠标\nQ - 激光  W - 散射\nR - 重新开始"
			_restart_label.text = "按 R 重新开始"
		else:
			_controls_label.text = "鼠标 - 移动/瞄准\nESC - 释放鼠标\nQ - 激光  W - 散射\n等待房主重新开始"
			_restart_label.text = "等待房主重新开始"

func _update_fps(delta: float) -> void:
	if _fps_label == null:
		return
	_fps_accum += delta
	if _fps_accum < 0.2:
		return
	_fps_accum = 0.0
	var fps: int = int(Engine.get_frames_per_second())
	if fps <= 0 and delta > 0.0:
		fps = int(round(1.0 / max(delta, 0.0001)))
	_fps_label.text = "FPS: %d" % fps

## 新增技能：追加到 _skill_data 并重建技能条
func add_skill(data: Dictionary) -> void:
	_skill_data.append(data)
	_create_skill_slot(data)

func show_boss_bonus_attribute_feedback() -> void:
	_update_powerup_display()
	_pulse_powerup_bonus_lines()

func show_center_banner(text: String, hold: float = 2.0, color: Color = Color(1.0, 0.3, 0.2, 1.0)) -> void:
	var banner := Label.new()
	banner.text = text
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	banner.add_theme_constant_override("shadow_outline_size", 2)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var canvas_size := _get_design_canvas_size()
	banner.position = Vector2(0, canvas_size.y * 0.28)
	banner.size = Vector2(canvas_size.x, 56)
	banner.modulate.a = 0.0
	add_child(banner)
	var tween := create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.18)
	tween.tween_interval(maxf(hold, 0.2))
	tween.tween_property(banner, "modulate:a", 0.0, 0.28)
	tween.tween_callback(banner.queue_free)

func show_boss_status(current: float, maximum: float, phase_name: String) -> void:
	_ensure_boss_status_ui()
	if _boss_status_root == null:
		return
	_boss_status_root.visible = true
	var ratio: float = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	_boss_status_fill.size.x = 520.0 * ratio
	_boss_status_label.text = "裂隙母舰  %d%%" % int(round(ratio * 100.0))
	_boss_status_phase.text = phase_name

func hide_boss_status() -> void:
	if _boss_status_root:
		_boss_status_root.visible = false

func _ensure_boss_status_ui() -> void:
	if _boss_status_root != null:
		return
	var viewport_size := _get_design_canvas_size()
	_boss_status_root = Control.new()
	_boss_status_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_status_root.position = Vector2(maxf((viewport_size.x - 560.0) * 0.5, 16.0), 16.0)
	_boss_status_root.size = Vector2(560.0, 48.0)
	_boss_status_root.z_index = 45
	add_child(_boss_status_root)
	var bg := ColorRect.new()
	bg.position = Vector2(20.0, 22.0)
	bg.size = Vector2(520.0, 14.0)
	bg.color = Color(0.06, 0.04, 0.08, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_status_root.add_child(bg)
	_boss_status_fill = ColorRect.new()
	_boss_status_fill.size = Vector2(520.0, 14.0)
	_boss_status_fill.color = Color(0.92, 0.12, 0.20, 0.96)
	_boss_status_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_boss_status_fill)
	_boss_status_label = Label.new()
	_boss_status_label.position = Vector2(0.0, 0.0)
	_boss_status_label.size = Vector2(560.0, 22.0)
	_boss_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_status_label.add_theme_font_size_override("font_size", 16)
	_boss_status_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.78, 1.0))
	_boss_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_boss_status_label.add_theme_constant_override("shadow_outline_size", 1)
	_boss_status_root.add_child(_boss_status_label)
	_boss_status_phase = Label.new()
	_boss_status_phase.position = Vector2(0.0, 36.0)
	_boss_status_phase.size = Vector2(560.0, 20.0)
	_boss_status_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_status_phase.add_theme_font_size_override("font_size", 12)
	_boss_status_phase.add_theme_color_override("font_color", Color(0.95, 0.72, 1.0, 0.95))
	_boss_status_root.add_child(_boss_status_phase)

func show_pickup_toast(powerup_type: String, world_pos: Vector2) -> void:
	var text := _pickup_text(powerup_type)
	if text.is_empty():
		return
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	toast.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	toast.add_theme_constant_override("shadow_outline_size", 2)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.position = world_pos + Vector2(-60.0, -36.0)
	toast.size = Vector2(120.0, 24.0)
	add_child(toast)
	_active_pickup_toasts.append(toast)
	var tween := create_tween()
	tween.tween_property(toast, "position:y", toast.position.y - 20.0, 0.8)
	tween.parallel().tween_property(toast, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func():
		_active_pickup_toasts.erase(toast)
		toast.queue_free()
	)

func _pickup_text(powerup_type: String) -> String:
	match powerup_type:
		"heal":
			return "治疗 +5"
		"power":
			return "威力 +1"
		"speed":
			return "速射 +1"
		"spread":
			return "扩散 +1"
		"bomb":
			return "炸弹清场"
		"core":
			return "核心奖励"
	return ""
