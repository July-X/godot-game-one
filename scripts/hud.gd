extends CanvasLayer
## HUD 控制器 — 动态技能条 + 像素风 UI

@onready var _score_label: Label = $ScoreLabel
@onready var _level_label: Label = $LevelLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _hp_num: Label = $HealthBar/HPNum
@onready var _powerup_display: VBoxContainer = $PowerupDisplay
@onready var _controls_label: Label = $ControlsLabel
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

func _ready() -> void:
	_game_over_panel.visible = false
	_set_control_ignore_input(_game_over_panel)
	_set_control_ignore_input($LeaderboardPanel)
	_setup_damage_flash()
	_update_platform_hints()
	_setup_skill_bar()

	GameState.score_changed.connect(_on_score_changed)
	GameState.level_changed.connect(_on_level_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.powerup_collected.connect(_on_powerup_collected)
	_update_score(0)
	_update_level(1)
	_update_health(3, 3)
	_refresh_leaderboard()

func _process(_delta: float) -> void:
	_update_cooldowns()

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
			"action": "skill", "key": KEY_SPACE,
			"bar_color": Color(0.15, 0.72, 0.28),
		},
	]

	for data in _skill_data:
		_create_skill_slot(data)

## 动态创建单个技能按钮
func _create_skill_slot(data: Dictionary) -> void:
	var slot_size := Vector2(144, 144)

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
	btn.pressed.connect(_on_skill_slot_pressed.bind(data))
	btn.gui_input.connect(_on_skill_slot_gui_input.bind(data))

	# 半透明背景框
	var bg := ColorRect.new()
	bg.size = slot_size
	bg.color = Color(0.1, 0.12, 0.2, 0.45)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bg)

	# 冷却覆盖层
	var overlay := ColorRect.new()
	overlay.size = slot_size - Vector2(4, 4)
	overlay.position = Vector2(2, 2)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(1, 1, 1, 0)
	overlay.set_script(preload("res://scripts/cooldown_overlay.gd"))
	btn.add_child(overlay)

	# 技能图标（AI 生成像素图）
	var icon_tex := TextureRect.new()
	icon_tex.size = slot_size
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	btn.add_child(cd_label)

	_skill_slots.append({
		"data": data,
		"button": btn,
		"overlay": overlay,
		"cd_label": cd_label,
	})

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
				cd = GameState.skill_cooldown
				cd_max = GameState.SKILL_COOLDOWN_MAX
			"laser":
				cd = GameState.laser_cooldown
				cd_max = GameState.LASER_COOLDOWN_MAX
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
	if not GameState.use_skill():
		return
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player and player.has_method("_fire_ring_shotgun"):
		player._fire_ring_shotgun()
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _trigger_laser() -> void:
	if not GameState.use_laser():
		return
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player and player.has_method("_fire_laser"):
		player._fire_laser()
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _trigger_skill()
			KEY_Q: _trigger_laser()

## ── 信号响应 ────────────────────────────────────────────────

func _on_score_changed(new_score: int) -> void:
	_update_score(new_score)

func _on_level_changed(new_level: int) -> void:
	_update_level(new_level)

func _on_health_changed(current: int, maximum: int) -> void:
	_update_health(current, maximum)

func _on_game_over(final_score: int, final_level: int) -> void:
	_game_over_panel.visible = true
	_final_score_label.text = "得分: %d" % final_score
	_final_level_label.text = "等级: %d" % final_level
	Leaderboard.add_entry(final_score, final_level)
	_refresh_leaderboard()

func _on_powerup_collected(type: String) -> void:
	_update_powerup_display()

## ── 显示更新 ────────────────────────────────────────────────

func _update_score(score: int) -> void:
	_score_label.text = "得分: %d" % score

func _update_level(level: int) -> void:
	_level_label.text = "等级 %d" % level

func _update_health(current: int, maximum: int) -> void:
	if _health_bar:
		_health_bar.max_value = maximum
		_health_bar.value = current
	if _hp_num:
		_hp_num.text = "HP %d/%d" % [current, maximum]

func _update_powerup_display() -> void:
	for child in _powerup_display.get_children():
		child.queue_free()
	var labels := {
		"spread": {"name": "扩散", "color": Color(0.3, 1.0, 0.4), "bar": Color(0.2, 0.8, 0.3)},
		"speed": {"name": "速射", "color": Color(0.4, 0.7, 1.0), "bar": Color(0.3, 0.6, 1.0)},
		"power": {"name": "威力", "color": Color(1.0, 0.4, 0.3), "bar": Color(0.9, 0.3, 0.2)},
	}
	for type in labels:
		var level: int = 0
		var max_level: int = 15
		match type:
			"spread":
				level = GameState.shoot_level
				max_level = 20
			"speed":
				level = GameState.shoot_speed_level
				max_level = 20
			"power":
				level = GameState.bullet_power_level
				max_level = 50
		if level <= 0:
			continue

		var bar_w: int = 120
		var bar_h: int = 14
		var fill_w: int = int(bar_w * float(level) / float(max_level))

		# 行容器: SPR ████░░  8/15
		var row := HBoxContainer.new()
		_powerup_display.add_child(row)

		# 名称标签
		var name_lbl := Label.new()
		name_lbl.text = labels[type].name + "  "
		name_lbl.add_theme_color_override("font_color", labels[type].color)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.vertical_alignment = 1
		row.add_child(name_lbl)

		# 进度条背景
		var bg := ColorRect.new()
		bg.custom_minimum_size = Vector2(bar_w, bar_h)
		bg.size = Vector2(bar_w, bar_h)
		bg.color = Color(0.08, 0.08, 0.15, 0.7)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bg)

		# 进度条填充
		var fill := ColorRect.new()
		fill.size = Vector2(fill_w, bar_h)
		fill.color = labels[type].bar
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)

		# 数值标签（覆盖在进度条上）
		var val_lbl := Label.new()
		val_lbl.size = Vector2(bar_w, bar_h)
		val_lbl.text = "%d/%d" % [level, max_level]
		val_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		val_lbl.add_theme_font_size_override("font_size", 10)
		val_lbl.horizontal_alignment = 1
		val_lbl.vertical_alignment = 1
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(val_lbl)

func _setup_damage_flash() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.z_index = 200
	add_child(_damage_flash)
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var old_health: int = GameState.current_health
	GameState.health_changed.connect(func(_cur: int, _max: int):
		if GameState.current_health < old_health:
			if _damage_flash and is_instance_valid(_damage_flash):
				var tween := create_tween()
				tween.tween_property(_damage_flash, "color", Color(1.0, 0.0, 0.0, 0.18), 0.05)
				tween.tween_property(_damage_flash, "color", Color(1.0, 0.0, 0.0, 0.0), 0.25)
				tween.tween_callback(func(): _damage_flash.color = Color(1.0, 0.0, 0.0, 0.0))
		old_health = GameState.current_health
	)

func _set_control_ignore_input(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		_set_control_ignore_input(child)

func _refresh_leaderboard() -> void:
	for child in _perm_leaderboard_entries.get_children():
		child.queue_free()
	var entries := Leaderboard.get_entries()
	for entry in entries:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
		label.horizontal_alignment = 1
		label.vertical_alignment = 1
		label.text = "#%d  %s\n%s  (Lv.%d)" % [entries.find(entry) + 1, entry.time, entry.score, entry.level]
		_perm_leaderboard_entries.add_child(label)

func _update_platform_hints() -> void:
	var is_mobile: bool = OS.has_feature("android") or OS.has_feature("ios")
	if is_mobile:
		_controls_label.text = "左侧轮盘 - 移动/转向\n自动射击\n点击屏幕重新开始"
		_restart_label.text = "点击屏幕重新开始"
	else:
		_controls_label.text = "鼠标 - 移动/瞄准\nESC - 释放鼠标\nQ - 激光  Space - 散射\nR - 重新开始"
		_restart_label.text = "按 R 重新开始"

## 新增技能：追加到 _skill_data 并重建技能条
func add_skill(data: Dictionary) -> void:
	_skill_data.append(data)
	_create_skill_slot(data)
