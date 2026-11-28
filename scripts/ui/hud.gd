extends CanvasLayer
const Palette = preload("res://scripts/visuals/palette.gd")
const SafeArea = preload("res://scripts/ui/battle_safe_area.gd")
## HUD 控制器 — 动态技能条 + 像素风 UI

@onready var _score_label: Label = $ScoreLabel
@onready var _level_label: Label = $LevelLabel
@onready var _phase_label: Label = $PhaseLabel
@onready var _local_pilot: Control = $LocalPilot
@onready var _wingman: Control = $Wingman
@onready var _player_scores_label: Label = $PlayerScoresLabel
@onready var _powerup_display: VBoxContainer = $PowerupDisplay
@onready var _graze_label: Label = $GrazeLabel
@onready var _draft_panel: VBoxContainer = $DraftPanel
@onready var _draft_title: Label = $DraftPanel/Heading/DraftTitle
@onready var _draft_clock: Label = $DraftPanel/Heading/Countdown
@onready var _draft_time_bar: ProgressBar = $DraftPanel/TimeBar
@onready var _draft_row: HBoxContainer = $DraftPanel/CardRow
@onready var _evolution_label: Label = $EvolutionLabel
@onready var _downed_label: Label = $DownedLabel
@onready var _controls_label: Label = $ControlsLabel
@onready var _fps_label: Label = $FpsLabel
@onready var _score_rows: Array[Label] = [_score_label, _level_label, _phase_label, _player_scores_label, _fps_label]
@onready var _game_over_panel: Panel = $GameOverPanel
@onready var _final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var _final_level_label: Label = $GameOverPanel/VBox/FinalLevelLabel
@onready var _restart_button: Button = $GameOverPanel/VBox/Restart
@onready var _perm_leaderboard_entries: VBoxContainer = $GameOverPanel/VBox/LeaderboardEntries
@onready var _skill_bar: Control = $SkillBar

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
var _cached_score: int = -1
var _cached_player_scores_signature: String = ""
var _fps_accum: float = 0.0
var _active_pickup_toasts: Array = []
var _boss_status_root: Control = null
var _boss_status_fill: ColorRect = null
var _boss_shield_fill: ColorRect = null
var _boss_status_label: Label = null
var _boss_status_phase: Label = null
var _boss_shield_release_left := 0.0
var _alert_label: Label
var _alert_tween: Tween
var _safe_rect := Rect2()
var _draft_cards: Array = []
var _draft_prompt := ""
var _recommends_first := false
var _rejected_action := ""
var _rejected_until := 0
const BOSS_BAR_SIZE := Vector2(520, 39)
const EDGE_MARGIN := 18.0
const SIDE_WIDTH := 198.0
const SCORE_CORNER_INSET := Vector2(40.0, 32.0)
const POWERUP_BAR_WIDTH: int = 110
const POWERUP_BAR_HEIGHT: int = 12
const BOSS_BONUS_LASER_CD_MAX: float = 5.0
const BOSS_BONUS_BULLET_COUNT_MAX: float = 4.0
const BOSS_BONUS_DAMAGE_MAX: float = 20.0
const BOSS_BONUS_MOVE_SPEED_MAX: float = 0.5
const SKILL_SLOT_DESKTOP: Vector2 = Vector2(80, 80)
const TOUCH_SKILL_SIZE := 74.0
const TOUCH_DASH_SIZE := 108.0
const TOUCH_SKILL_INSET := Vector2(36, 35)

## 图标资源缺失时的字形兜底（见 _create_skill_slot）
const SKILL_GLYPH: Dictionary = {
	"laser": "L", "skill": "S", "dash": "»",
}

func _ready() -> void:
	layer = 20
	_game_over_panel.visible = false
	_fps_label.visible = OS.get_cmdline_user_args().has("--fps")
	for child in get_children():
		_set_control_ignore_input(child)
	for label in _score_rows:
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.minimum_size_changed.connect(_on_score_size_changed)
	_draft_panel.minimum_size_changed.connect(_position_draft_panel)
	_restart_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_restart_button.pressed.connect(Callable(get_parent(), "_restart"), CONNECT_DEFERRED)
	_restart_button.gui_input.connect(_on_restart_touch)
	_setup_damage_flash()
	_update_platform_hints()
	_draft_time_bar.max_value = UpgradeDraft.DRAFT_TIMEOUT_SECONDS
	_draft_time_bar.add_theme_stylebox_override("background", _surface(Color("#243244")))
	_draft_time_bar.add_theme_stylebox_override("fill", _surface(Color("#79afc6")))
	_setup_skill_bar()
	_layout_battle_hud()
	get_viewport().size_changed.connect(_layout_battle_hud)
	get_window().focus_entered.connect(_layout_battle_hud)

	GameState.score_changed.connect(_on_score_changed)
	GameState.level_changed.connect(_on_level_changed)
	GameState.powerup_collected.connect(_on_powerup_collected)
	GameState.player_scores_changed.connect(_on_player_scores_changed)
	UpgradeDraft.draft_opened.connect(_on_draft_opened)
	_update_score(0)
	_update_level(1)
	_update_pilots()
	_update_player_scores(GameState.get_all_player_scores(), GameState.score)
	_update_powerup_display()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_layout_battle_hud.call_deferred()

func _process(_delta: float) -> void:
	_boss_shield_release_left = maxf(_boss_shield_release_left - _delta, 0.0)
	_update_pilots()
	_refresh_score_if_needed()
	_update_level(GameState.level)
	_update_cooldowns()
	_refresh_powerup_display_if_needed()
	_update_graze_display()
	_update_draft_panel()
	_update_evolution_display()
	_update_downed_display()
	_update_fps(_delta)


func _update_downed_display() -> void:
	var visible := NetworkManager.is_online() and GameState.game_running
	if visible != _downed_label.visible:
		_downed_label.visible = visible
		_position_draft_panel()
	if not visible:
		return
	var text := "救援 %d/%d" % [GameState.rescues_left, GameState.RESCUE_LIMIT]
	var downed := GameState.rescue_peer_id
	if downed > 0:
		text = "%s 倒地 · %d 秒 · 入圈%s" % [_peer_label(downed), GameState.rescue_seconds, text]
	if _downed_label.text != text:
		_downed_label.text = text
		var warn := downed > 0 and GameState.rescue_seconds <= GameState.RESCUE_WARNING_SECONDS
		_downed_label.add_theme_color_override("font_color", Palette.DOWNED_CRITICAL if warn else Palette.DOWNED_SAFE)


## 同一排 Button 显示常规三选一和试飞的四张卡，确认仍由 UpgradeDraft 处理。
var _draft_card_buttons: Array[Button] = []

func _on_draft_opened(pid: int, _cards: Array) -> void:
	if pid != _local_peer_id():
		return
	_update_draft_panel()

func _update_draft_panel() -> void:
	var my_pid := _local_peer_id()
	if not GameState.game_running or not UpgradeDraft.has_draft(my_pid):
		_draft_panel.visible = false
		return
	var draft := UpgradeDraft.get_draft(my_pid)
	var cards: Array = draft.cards
	_draft_panel.visible = true
	var recommends_first := bool(draft.get("recommends_first", false))
	if cards != _draft_cards or _recommends_first != recommends_first:
		_draft_cards = cards.duplicate()
		_recommends_first = recommends_first
		_populate_draft(cards)
		_layout_draft_cards()
	var left := float(draft.left)
	_draft_time_bar.value = left
	_draft_clock.text = "%02d 秒" % ceili(left)

func _populate_draft(cards: Array) -> void:
	while _draft_card_buttons.size() < cards.size():
		var icon := Control.new()
		icon.name = "Icon"
		icon.set_script(preload("res://scripts/ui/card_icon.gd"))
		var card_name := _label(22, Vector2.ZERO, Vector2.ZERO)
		card_name.name = "CardName"
		var description := _label(18, Vector2.ZERO, Vector2.ZERO)
		description.name = "Description"
		description.add_theme_color_override("font_color", Color("#b0c4d6"))
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.add_child(icon)
		button.add_child(card_name)
		button.add_child(description)
		var index := _draft_card_buttons.size()
		button.pressed.connect(_on_draft_card_pressed.bind(index))
		button.gui_input.connect(_on_draft_card_touch.bind(button, index))
		_draft_row.add_child(button)
		_set_control_ignore_input(icon)
		_draft_card_buttons.append(button)
	for i in _draft_card_buttons.size():
		var button := _draft_card_buttons[i]
		button.visible = i < cards.size()
		if not button.visible:
			continue
		var card := UpgradeDraft.card_by_id(str(cards[i]))
		var tint := Palette.CARD_STYLE if card.kind == "style" else Palette.CARD_STAT
		var card_name: Label = button.get_node("CardName")
		card_name.text = "%d  %s" % [i + 1, card.name]
		card_name.add_theme_color_override("font_color", tint)
		var description: String = "推荐 · 缩短主炮开火间隔" if i == 0 and _recommends_first else card.desc
		button.get_node("Description").text = description
		button.get_node("Icon").setup(card.icon, tint)
		button.tooltip_text = description
	_update_draft_title()

func set_draft_prompt(text: String) -> void:
	_draft_prompt = text
	# 教学保留紧凑面板的热区。普通局只有真正的卡片按钮接收新触摸。
	_draft_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE if text.is_empty() else Control.MOUSE_FILTER_STOP
	_update_draft_title()
	if not _draft_cards.is_empty():
		_layout_draft_cards()

func _update_draft_title() -> void:
	var action := "点选卡片" if _is_touch_platform() else "按 1 / 2" if _draft_cards.size() == 2 else "按 1 / 2 / 3"
	var fallback := "超时选推荐" if _recommends_first else "超时取第一张"
	_draft_title.text = "本机升级 · %s · %s" % [action, fallback] if _draft_prompt.is_empty() else _draft_prompt

func _on_draft_card_pressed(index: int) -> void:
	UpgradeDraft.choose_card(_local_peer_id(), index, "tap")

func _on_draft_card_touch(event: InputEvent, button: Button, index: int) -> void:
	if _accept_touch_press(event, button):
		_on_draft_card_pressed(index)

func _accept_touch_press(event: InputEvent, button: Button) -> bool:
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		button.accept_event()
	if event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION and event.pressed and not event.canceled:
		button.accept_event()
		return true
	return false

func _is_touch_platform() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or get_parent().has_node("MobileControls")


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
		return NetworkManager.local_player_id()
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
##
## 闪避（dash）也放在这里，而不是另做一个按钮：
## 三个动作共用一套冷却遮罩、图标与按下反馈，玩家一眼就能看出
## "右下角这一排都是消耗资源的动作"。若把闪避做成独立控件，
## 它就会在视觉上脱离这一排，而闪避恰恰是最需要被看到的那个（1.1s CD）。
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
		{
			"name": "闪避",
			"action": "dash", "key": KEY_SHIFT,
			"bar_color": Color(0.15, 0.62, 0.78),
		},
	]

	for data in _skill_data:
		_create_skill_slot(data)
	GameState.cast_rejected.connect(_on_cast_rejected)

func _create_skill_slot(data: Dictionary) -> void:
	var btn := Button.new()
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", _surface(Color("#112034d4"), Color("#43677e")))
	btn.add_theme_stylebox_override("hover", _surface(Color("#20374bdc"), Palette.CARD_STYLE))
	btn.add_theme_stylebox_override("pressed", _surface(Color("#2a455de8"), Palette.CARD_STYLE))
	btn.pressed.connect(_on_skill_slot_pressed.bind(data))
	btn.gui_input.connect(_on_skill_slot_touch.bind(btn, data))
	_skill_bar.add_child(btn)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_path: String = "res://assets/sprites/ui/skill_%s.png" % data.action
	if ResourceLoader.exists(tex_path):
		icon.texture = load(tex_path)
	else:
		var fallback := _label(23, Vector2.ZERO, Vector2(36, 32), HORIZONTAL_ALIGNMENT_CENTER)
		fallback.text = SKILL_GLYPH.get(str(data.action), "?")
		icon.add_child(fallback)
	btn.add_child(icon)

	var key_label := _label(10, Vector2(6, 3), Vector2(36, 14))
	key_label.text = OS.get_keycode_string(data.key)
	key_label.add_theme_color_override("font_color", Color("#9bb1c7"))
	btn.add_child(key_label)
	var action_label := _label(13, Vector2.ZERO, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	action_label.text = data.name
	btn.add_child(action_label)
	var cooldown := _label(11, Vector2.ZERO, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	btn.add_child(cooldown)
	var progress := ColorRect.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.color = data.bar_color
	btn.add_child(progress)

	_skill_slots.append({
		"data": data, "button": btn, "icon": icon, "key": key_label,
		"name": action_label, "progress": progress, "cd_label": cooldown,
		"ready_surface": _surface(Color("#182b3fda"), Color("#95c6d6")),
		"cooling_surface": _surface(Color("#101b2bdc"), Color("#435166")),
		"rejected_surface": _surface(Color("#2e1a24dc"), Color("#f59583")),
		"visual": "",
	})

func _layout_battle_hud() -> void:
	_layout_in_safe_area(SafeArea.for_viewport(get_viewport()))

func _layout_in_safe_area(safe: Rect2) -> void:
	_safe_rect = safe
	var left := safe.position.x + EDGE_MARGIN
	var right := safe.end.x - EDGE_MARGIN - SIDE_WIDTH
	var top := safe.position.y + 12.0
	var local_left := _local_peer_id() == 1
	var local_x := left if local_left else right
	var other_x := right if local_left else left
	_local_pilot.position = Vector2(local_x, top)
	_wingman.position = Vector2(other_x, top)
	_graze_label.position = Vector2(local_x, top + 63)
	_evolution_label.position = Vector2(local_x, top + 81)
	_evolution_label.size = Vector2(SIDE_WIDTH, 34)
	_powerup_display.position = Vector2(local_x, top + 119)
	_layout_score_rows()
	_controls_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_controls_label.position = Vector2(left, safe.end.y - 32)
	_controls_label.size = Vector2(310, 17)
	_layout_skill_bar()
	_game_over_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_game_over_panel.position = safe.get_center() - _game_over_panel.size * 0.5
	if not _draft_cards.is_empty():
		_layout_draft_cards()
	_layout_top_rows()

func _on_score_size_changed() -> void:
	if _is_touch_platform() and _safe_rect.has_area():
		_layout_score_rows()

func _layout_score_rows() -> void:
	var on_right := _local_peer_id() == 1
	var touch := _is_touch_platform()
	var y := _safe_rect.position.y + (75.0 if NetworkManager.is_online() else 12.0)
	var edge := _safe_rect.end.x - EDGE_MARGIN if on_right else _safe_rect.position.x + EDGE_MARGIN
	if touch:
		# 有切口时与矩形安全区取交集，圆角余量不会重复叠加。
		var canvas := get_viewport().get_visible_rect()
		y = maxf(y, canvas.position.y + SCORE_CORNER_INSET.y)
		edge = minf(edge, canvas.end.x - SCORE_CORNER_INSET.x) if on_right else maxf(edge, canvas.position.x + SCORE_CORNER_INSET.x)
	for i in _score_rows.size():
		var label := _score_rows[i]
		var width := maxf(SIDE_WIDTH, label.get_combined_minimum_size().x) if touch else SIDE_WIDTH
		label.size = Vector2(width, 18.0)
		label.position = Vector2(edge - width if on_right else edge, y + 18.0 * i)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if on_right else HORIZONTAL_ALIGNMENT_LEFT

func _layout_top_rows() -> void:
	var center := _safe_rect.get_center().x
	var top := _safe_rect.position.y + 12.0
	var rescue_width := minf(360.0, _safe_rect.size.x - EDGE_MARGIN * 2.0)
	_downed_label.position = Vector2(center - rescue_width * 0.5, top + 42.0)
	_downed_label.size = Vector2(rescue_width, 24)
	if is_instance_valid(_boss_status_root):
		_boss_status_root.position = Vector2(center - BOSS_BAR_SIZE.x * 0.5, top)
	if is_instance_valid(_alert_label):
		_alert_label.position = Vector2(center - BOSS_BAR_SIZE.x * 0.5, top)
	_position_draft_panel()

func _layout_draft_cards() -> void:
	var compact := not _draft_prompt.is_empty()
	var short_view := not compact and _is_touch_platform() and _safe_rect.size.y < 420.0
	var columns := _draft_cards.size()
	var gap := 8.0 if compact else 12.0
	var width := floorf(minf(204.0 if compact else 272.0,
		(_safe_rect.size.x - EDGE_MARGIN * 2.0 - gap * (columns - 1)) / columns))
	var height := 50.0 if compact else 144.0 if width < 148.0 else 120.0
	if short_view:
		height = 80.0
	var narrow := width < 188.0
	_draft_row.add_theme_constant_override("separation", int(gap))
	_draft_panel.add_theme_constant_override("separation", 3 if compact else 4 if short_view else 8)
	_draft_title.add_theme_font_size_override("font_size", 13 if compact else 16 if short_view else 18)
	_draft_clock.add_theme_font_size_override("font_size", 14 if compact else 15 if short_view else 18)
	_draft_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_draft_title.add_theme_color_override("font_outline_color", Color("#0b1324"))
	_draft_title.add_theme_constant_override("outline_size", 4)
	for i in columns:
		var button := _draft_card_buttons[i]
		button.custom_minimum_size = Vector2(width, height)
		button.add_theme_stylebox_override("normal", _surface(Color("#132238d9" if compact else "#1322387a"), Color("#426480")))
		button.add_theme_stylebox_override("hover", _surface(Color("#233b52e8" if compact else "#233b5290"), Palette.CARD_STYLE))
		button.add_theme_stylebox_override("pressed", _surface(Color("#2c455de8" if compact else "#2c455d9c"), Palette.CARD_STYLE))
		var icon := button.get_node("Icon") as Control
		var title := button.get_node("CardName") as Label
		var desc := button.get_node("Description") as Label
		for label in [title, desc]:
			label.add_theme_color_override("font_outline_color", Color("#0b1324"))
			label.add_theme_constant_override("outline_size", 0 if compact else 4)
		icon.position = Vector2(8, 6) if compact else Vector2(12, 5 if short_view else 12)
		icon.size = Vector2(37, 38) if compact else Vector2.ONE * (28 if short_view else 34)
		icon.visible = not narrow
		var title_x := 12.0 if narrow else 48.0 if compact else 56.0
		title.position = Vector2(title_x, 5 if compact or short_view else 14)
		title.add_theme_font_size_override("font_size", 15 if compact or width < 128.0 else 19 if narrow else 22)
		title.size = Vector2(width - title_x - 10.0, 22 if compact else 32)
		var desc_x := title_x if compact else 14.0
		var description_top := 27.0 if compact else 35.0 if short_view else 55.0
		desc.position = Vector2(desc_x, description_top)
		desc.autowrap_mode = TextServer.AUTOWRAP_OFF if compact else TextServer.AUTOWRAP_WORD_SMART
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if compact else TextServer.OVERRUN_NO_TRIMMING
		desc.add_theme_font_size_override("font_size", 12 if compact else 16 if narrow else 18)
		desc.size = Vector2(width - desc_x - 12.0, 18 if compact else height - description_top - 7.0)
	_draft_panel.size = Vector2(width * columns + gap * (columns - 1), 0)
	_position_draft_panel()

func _position_draft_panel() -> void:
	if not _draft_panel.visible:
		return
	_draft_panel.size.y = _draft_panel.get_combined_minimum_size().y
	var top := _safe_rect.position.y + 12.0
	var boss_visible := is_instance_valid(_boss_status_root) and _boss_status_root.visible
	var alert_visible := is_instance_valid(_alert_label) and _alert_label.visible
	if boss_visible or alert_visible:
		top += 42.0
	if _downed_label.visible:
		top = maxf(top, _downed_label.position.y + _downed_label.size.y + 6.0)
	var y := top if not _draft_prompt.is_empty() else maxf(top, _safe_rect.get_center().y - _draft_panel.size.y * 0.5)
	if _is_touch_platform() and _draft_prompt.is_empty():
		y = maxf(top, minf(y, _skill_bar.position.y - _draft_panel.size.y - 8.0))
	_draft_panel.position = Vector2(_safe_rect.get_center().x - _draft_panel.size.x * 0.5, y)

func _layout_skill_bar() -> void:
	var touch := _is_touch_platform()
	var dock_scale := clampf(minf(_safe_rect.size.x / 850.0, _safe_rect.size.y / 540.0), 0.74, 1.0)
	var bounds := Vector2.ZERO
	for i in _skill_slots.size():
		var slot := _skill_slots[i]
		var btn: Button = slot.button
		var dash: bool = slot.data.action == "dash"
		var slot_size := Vector2.ONE * (TOUCH_DASH_SIZE if dash else TOUCH_SKILL_SIZE) * dock_scale if touch else SKILL_SLOT_DESKTOP
		btn.position = Vector2(88, 86) * dock_scale if touch and dash else Vector2(i * 84, 0) * dock_scale if touch else Vector2(i * (slot_size.x + 8), 0)
		btn.custom_minimum_size = slot_size
		btn.size = slot_size
		bounds = bounds.max(btn.position + slot_size)
		slot.key.visible = not touch
		slot.name.visible = not touch
		slot.cd_label.visible = not (touch and dash)
		var icon_size := (62.0 if dash else 44.0) * dock_scale if touch else 42.0
		slot.icon.size = Vector2.ONE * icon_size
		slot.icon.position = Vector2((slot_size.x - icon_size) * 0.5, (slot_size.y - icon_size) * 0.5 - (0.0 if dash else 5.0) if touch else 5.0)
		slot.name.position = Vector2(0, slot_size.y - 36)
		slot.name.size = Vector2(slot_size.x, 18)
		slot.cd_label.position = Vector2(0, slot_size.y - 21)
		slot.cd_label.size = Vector2(slot_size.x, 15)
		slot.progress.position = Vector2(4, slot_size.y - (6 if touch else 3))
	_skill_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_skill_bar.size = bounds
	var inset := TOUCH_SKILL_INSET if touch else Vector2.ONE * EDGE_MARGIN
	_skill_bar.position = _safe_rect.end - _skill_bar.size - inset

func _get_design_canvas_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _on_skill_slot_pressed(data: Dictionary) -> void:
	_request_player_action(data.action)

func _on_skill_slot_touch(event: InputEvent, button: Button, data: Dictionary) -> void:
	if _accept_touch_press(event, button):
		_on_skill_slot_pressed(data)

func _on_cast_rejected(action: String) -> void:
	_rejected_action = action
	_rejected_until = Time.get_ticks_msec() + 550

func _update_cooldowns() -> void:
	var touch := _is_touch_platform()
	for slot in _skill_slots:
		var cd := 0.0
		var cd_max := 0.0
		var action: String = slot.data.action
		match action:
			"skill":
				cd = GameState.get_skill_cooldown()
				cd_max = GameState.SKILL_COOLDOWN_MAX
			"laser":
				cd = GameState.get_laser_cooldown()
				cd_max = GameState.get_laser_cooldown_max()
			"dash":
				var pl := _resolve_local_player()
				if pl and pl.has_method("get_dash_cooldown_ratio"):
					cd_max = preload("res://scripts/player/motion_controller.gd").DASH_COOLDOWN
					cd = float(pl.get_dash_cooldown_ratio()) * cd_max
		var progress: float = clampf(1.0 - cd / cd_max, 0.0, 1.0) if cd_max > 0.0 else 1.0
		var pending := GameState.is_cast_pending(action)
		var rejected := _rejected_action == action and Time.get_ticks_msec() < _rejected_until
		var ready := cd <= 0.0 and not pending and not rejected
		slot.progress.size = Vector2((slot.button.size.x - 8.0) * progress, 2.0)
		slot.progress.visible = not touch or ready
		slot.icon.modulate = Color.WHITE if ready else Color("#8794a6")
		if touch:
			var visual := "rejected_surface" if rejected else "ready_surface" if ready else "cooling_surface"
			if slot.visual != visual:
				slot.button.add_theme_stylebox_override("normal", slot[visual])
				slot.visual = visual
			slot.cd_label.text = "×" if rejected else "…" if pending else str(ceili(cd)) if cd > 0.0 else ""
		else:
			slot.cd_label.text = "未释放" if rejected else "确认中" if pending else "就绪" if ready else "%.1fs" % (ceilf(cd * 10.0) / 10.0)
			slot.cd_label.add_theme_color_override("font_color", Palette.DASH_READY if ready else Color("#abb7c5"))

func _request_player_action(action: String) -> void:
	var player := _resolve_local_player()
	if player and player.has_method("request_action"):
		player.request_action(action)
	elif player and player.has_node("ActionRouter"):
		var router := player.get_node("ActionRouter")
		if router and router.has_method("request_action"):
			router.request_action(action)
	if not _is_touch_platform():
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
			if typeof(maybe_peer) == TYPE_INT and int(maybe_peer) == NetworkManager.local_player_id():
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

func _on_game_over(final_score: int, final_level: int) -> void:
	if _game_over_panel.visible:
		return
	_game_over_panel.visible = true
	hide_boss_status()
	if is_instance_valid(_alert_label):
		_alert_label.hide()
	_draft_panel.hide()
	_update_platform_hints()
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
	if spread_level == _cached_spread_level \
	and speed_level == _cached_speed_level \
	and power_level == _cached_power_level \
	and extra_bullet_count == _cached_extra_bullet_count \
	and extra_damage_bonus == _cached_extra_damage_bonus \
	and is_equal_approx(laser_cd_bonus, _cached_laser_cd_bonus) \
	and is_equal_approx(move_speed_bonus, _cached_move_speed_bonus):
		return
	_update_powerup_display()

## ── 显示更新 ────────────────────────────────────────────────

func _update_score(score: int) -> void:
	_score_label.text = "总分 %d" % score
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
	_level_label.text = "等级 %d · 击杀 %d/%d" % [level, GameState.kills, GameState.kills_for_next_level]


## 关卡乐句读数：当前拍名 + 章节号 + 本拍进度。
##
## 这行字存在的唯一理由是**让玩家知道自己在哪一拍**——
## 弹幕射击的乐趣来自"熬过浪峰、等来退潮"的预期感，
## 而预期感需要一个可见的进度来源。它是纯显示，不参与任何战斗逻辑。
func set_wave_phase(text: String, color: Color) -> void:
	if _phase_label == null:
		return
	_phase_label.text = text
	_phase_label.add_theme_color_override("font_color", color)

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
	_player_scores_label.visible = NetworkManager.is_online()
	_score_label.text = "总分 %d" % total_score
	_cached_score = total_score
	_cached_player_scores_signature = str(scores)

func _peer_label(peer_id: int) -> String:
	## ENet 的 Client peer_id 不保证固定为 2；本项目限制 1 个 Client，
	## 因此 UI 层按角色槽位显示：Host=P1，唯一 Client=P2。
	if peer_id == 1:
		return "P1"
	return "P2"

func _update_pilots() -> void:
	_update_pilot(_local_pilot, _local_peer_id(), "本机")
	var peers := NetworkManager.connected_peers
	_wingman.visible = NetworkManager.is_online() and not peers.is_empty()
	if _wingman.visible:
		_update_pilot(_wingman, NetworkManager.slot_for_peer(peers[0]), "队友")

func _update_pilot(panel: Control, peer_id: int, role: String) -> void:
	var tint := Palette.CARD_STYLE if peer_id == 1 else Color("#cfb7ff")
	var callsign: Label = panel.get_node("Rows/Callsign")
	callsign.text = ("P1 ━ " if peer_id == 1 else "P2 ═ ") + role
	callsign.modulate = tint
	var readout: Label = panel.get_node("Rows/Readout")
	var hull: ProgressBar = panel.get_node("Rows/Hull")
	var shield: ProgressBar = panel.get_node("Rows/Shield")
	hull.max_value = GameState.get_max_health(peer_id)
	hull.value = GameState.get_current_health(peer_id)
	shield.max_value = GameState.get_shield_max_hp(peer_id)
	shield.value = GameState.get_shield_layers(peer_id)
	shield.modulate = tint
	readout.text = "机体 %d/%d   护盾 %d/%d" % [hull.value, hull.max_value, shield.value, shield.max_value]

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
		"speed": {"name": "射速", "color": Color(0.4, 0.7, 1.0), "bar": Color(0.3, 0.6, 1.0)},
		"power": {"name": "威力", "color": Color(1.0, 0.4, 0.3), "bar": Color(0.9, 0.3, 0.2)},
	}
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
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var can_restart := not NetworkManager.is_online() or multiplayer.is_server()
	_restart_button.disabled = not can_restart
	if _is_touch_platform():
		_controls_label.hide()
		_restart_button.text = "重新开始" if can_restart else "等待房主重新开始"
	else:
		_restart_button.text = "重新开始 · R" if can_restart else "等待房主重新开始"
		_controls_label.show()
		_controls_label.text = "Esc 释放鼠标"

func _on_restart_touch(event: InputEvent) -> void:
	if _accept_touch_press(event, _restart_button) and not _restart_button.disabled:
		get_parent().call_deferred("_restart")

func _update_fps(delta: float) -> void:
	if not _fps_label.visible:
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
	_layout_skill_bar()

func show_boss_bonus_attribute_feedback() -> void:
	_update_powerup_display()
	_pulse_powerup_bonus_lines()

func show_center_banner(text: String, hold: float = 2.0, color: Color = Color(1.0, 0.3, 0.2, 1.0)) -> void:
	if is_instance_valid(_boss_status_root) and _boss_status_root.visible:
		return
	if not is_instance_valid(_alert_label):
		_alert_label = _label(19, Vector2.ZERO, BOSS_BAR_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		_alert_label.add_theme_color_override("font_shadow_color", Color("#050b18"))
		_alert_label.add_theme_constant_override("shadow_outline_size", 2)
		add_child(_alert_label)
	if _alert_tween:
		_alert_tween.kill()
	_alert_label.text = text
	_alert_label.add_theme_color_override("font_color", color)
	_alert_label.modulate.a = 0.0
	_alert_label.show()
	_layout_top_rows()
	_alert_tween = create_tween()
	_alert_tween.tween_property(_alert_label, "modulate:a", 1.0, 0.18)
	_alert_tween.tween_interval(maxf(hold, 0.2))
	_alert_tween.tween_property(_alert_label, "modulate:a", 0.0, 0.28)
	_alert_tween.tween_callback(func():
		_alert_label.hide()
		_layout_top_rows())

func show_boss_status(current: float, maximum: float, shield: float, max_shield: float,
		phase_name: String, attack_window: String, recharging: bool) -> void:
	_ensure_boss_status_ui()
	if not _boss_status_root.visible:
		_boss_status_root.show()
		if is_instance_valid(_alert_label):
			_alert_label.hide()
		_layout_top_rows()
	var ratio := clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	_boss_status_fill.size.x = (BOSS_BAR_SIZE.x - 20.0) * ratio
	var shield_ratio := clampf(shield / maxf(max_shield, 1.0), 0.0, 1.0)
	_boss_shield_fill.size.x = (BOSS_BAR_SIZE.x - 20.0) * shield_ratio
	_boss_status_label.text = "裂隙母舰  %d%%  ·  %s" % [roundi(ratio * 100), phase_name]
	var status := "可攻击"
	if current <= 0.0:
		status = "本体已击毁"
	elif shield > 0.0:
		_boss_shield_release_left = 0.0
		status = "护盾 %d%%" % maxi(1, roundi(shield_ratio * 100))
	elif recharging:
		status = "即将回盾"
	elif _boss_shield_release_left > 0.0:
		status = "破盾 · 可攻击"
	_boss_status_phase.text = status if attack_window.is_empty() else status + " · " + attack_window
	_boss_status_phase.add_theme_color_override("font_color", Color("#c3d6e2") if shield > 0.0 or recharging else Palette.CARD_STYLE)

func show_boss_shield_released() -> void:
	_boss_shield_release_left = 0.55

func hide_boss_status() -> void:
	_boss_shield_release_left = 0.0
	if is_instance_valid(_boss_status_root) and _boss_status_root.visible:
		_boss_status_root.hide()
		_layout_top_rows()

func _ensure_boss_status_ui() -> void:
	if is_instance_valid(_boss_status_root):
		return
	var panel := Panel.new()
	panel.size = BOSS_BAR_SIZE
	panel.add_theme_stylebox_override("panel", _surface(Color("#131c2bdc"), Color("#795763")))
	add_child(panel)
	_boss_status_root = panel
	panel.hide()
	_boss_status_fill = _add_boss_track(panel, 26.0, Color("#e1827f"))
	_boss_shield_fill = _add_boss_track(panel, 32.0, Color("#73bbdd"))
	_boss_status_label = _label(15, Vector2(10, 2), Vector2(265, 24))
	panel.add_child(_boss_status_label)
	_boss_status_phase = _label(14, Vector2(273, 2), Vector2(237, 24), HORIZONTAL_ALIGNMENT_RIGHT)
	panel.add_child(_boss_status_phase)
	_set_control_ignore_input(panel)

func _add_boss_track(panel: Control, y: float, color: Color) -> ColorRect:
	var track := ColorRect.new()
	track.position = Vector2(10.0, y)
	track.size = Vector2(BOSS_BAR_SIZE.x - 20.0, 4.0)
	track.color = Color("#313747")
	panel.add_child(track)
	var fill := ColorRect.new()
	fill.size = track.size
	fill.color = color
	track.add_child(fill)
	return fill

func _surface(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var surface := StyleBoxFlat.new()
	surface.bg_color = color
	surface.border_color = border
	if border.a > 0.0:
		surface.set_border_width_all(1)
		surface.corner_radius_top_right = 6
		surface.corner_radius_bottom_left = 6
	return surface

func _label(font_size: int, at: Vector2, extent: Vector2, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = at
	label.size = extent
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label

func show_lan_wait() -> Label:
	var banner := _label(22, Vector2.ZERO, Vector2(420, 56), HORIZONTAL_ALIGNMENT_CENTER)
	banner.process_mode = Node.PROCESS_MODE_ALWAYS
	banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	banner.add_theme_constant_override("shadow_outline_size", 8)
	add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	return banner

func show_pickup_toast(powerup_type: String, world_pos: Vector2, reward: String) -> void:
	var toast := Label.new()
	toast.text = _pickup_text(reward) if not reward.is_empty() else ("核心已拾取" if powerup_type == "core" else "已拾取")
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	toast.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	toast.add_theme_constant_override("shadow_outline_size", 2)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.size = Vector2(120.0, 24.0)
	var field_parent := get_parent() as Node2D
	var camera := get_viewport().get_canvas_transform()
	var anchor := camera * world_pos
	var area := _safe_rect.grow(-14.0)
	var at := anchor + Vector2(-toast.size.x * 0.5, -36.0)
	var basis := get_final_transform()
	var parent: Node = self
	if powerup_type == "core":
		# 世界标签需要同时框在安全区和渲染裁剪区内，文字字号按本地画布。
		if NetworkManager.is_online():
			var field := Rect2(camera.origin, camera.basis_xform(NetworkManager.battle_size(field_parent)))
			area = area.intersection(field.grow(-4.0))
		var gap := 34.0
		var room_right := anchor.x + gap + toast.size.x <= area.end.x
		at = anchor + Vector2(gap if room_right else -gap - toast.size.x,
			-22.0 if anchor.y >= area.position.y + 42.0 else 22.0)
		toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if room_right else HORIZONTAL_ALIGNMENT_RIGHT
		toast.z_index = -1
		basis = field_parent.get_global_transform_with_canvas()
		parent = field_parent
	var rise := 20.0
	at = at.clamp(area.position + Vector2(0.0, rise), (area.end - toast.size).max(area.position + Vector2(0.0, rise)))
	# 右下角靠边拾取时，技能按钮处于文字前面。把整段上浮轨迹放到按钮上方。
	var skills := _skill_bar.get_global_rect().grow(14.0)
	var toast_path := Rect2(at - Vector2(0.0, rise), toast.size + Vector2(0.0, rise))
	if _skill_bar.is_visible_in_tree() and toast_path.intersects(skills):
		at.y = maxf(area.position.y + rise, skills.position.y - toast.size.y)
	toast.position = basis.affine_inverse() * at
	toast.scale = Vector2.ONE / basis.get_scale()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(toast)
	_active_pickup_toasts.append(toast)
	var tween := create_tween()
	tween.tween_property(toast, "position:y", toast.position.y - rise * toast.scale.y, 0.8)
	tween.parallel().tween_property(toast, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func():
		_active_pickup_toasts.erase(toast)
		toast.queue_free()
	)

func _pickup_text(powerup_type: String) -> String:
	match powerup_type:
		"heal":
			return "治疗 +1"
		"power":
			return "威力 +1"
		"speed":
			return "射速 +1"
		"spread":
			return "扩散 +1"
		"bomb":
			return "炸弹已拾取" if NetworkManager.is_online() else "炸弹清场"
		"core":
			return "核心 · 冷却缩短"
	return ""
