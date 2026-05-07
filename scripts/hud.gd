extends CanvasLayer
## HUD 控制器 — 动态技能条 + 像素风 UI

@onready var _score_label: Label = $ScoreLabel
@onready var _level_label: Label = $LevelLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _hp_num: Label = $HealthBar/HPNum
@onready var _powerup_display: HBoxContainer = $PowerupDisplay
@onready var _controls_label: Label = $ControlsLabel
@onready var _game_over_panel: Panel = $GameOverPanel
@onready var _final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var _final_level_label: Label = $GameOverPanel/VBox/FinalLevelLabel
@onready var _restart_label: Label = $GameOverPanel/VBox/RestartLabel
@onready var _perm_leaderboard_entries: VBoxContainer = $LeaderboardPanel/LeaderboardEntries
@onready var _skill_bar: HBoxContainer = $SkillBar

var _damage_flash: ColorRect

## 技能槽数据（新增技能只需在这里加一条）
## {name, icon, action, key, overlay_style, bar_color}
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
			"name": "激光", "icon": "◎",
			"action": "laser", "key": KEY_Q,
			"overlay": 1,  # CIRCLE
			"bar_color": Color(0.25, 0.12, 0.85),
		},
		{
			"name": "散射", "icon": "△",
			"action": "skill", "key": KEY_SPACE,
			"overlay": 0,  # TRIANGLE
			"bar_color": Color(0.15, 0.72, 0.28),
		},
	]

	for data in _skill_data:
		_create_skill_slot(data)

## 动态创建单个技能按钮
func _create_skill_slot(data: Dictionary) -> void:
	var slot_size := Vector2(72, 72)

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
	overlay.overlay_style = data.overlay as int
	btn.add_child(overlay)

	# 图标标签
	var lbl := Label.new()
	lbl.size = slot_size
	lbl.text = data.icon
	lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.horizontal_alignment = 1
	lbl.vertical_alignment = 1
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	_skill_bar.add_child(btn)
	_skill_slots.append({
		"data": data,
		"button": btn,
		"overlay": overlay,
		"label": lbl,
	})

## 技能按钮被点击 / 触屏触发
func _on_skill_slot_pressed(data: Dictionary) -> void:
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
			slot.label.text = str(int(ceil(cd)))
			slot.label.add_theme_font_size_override("font_size", 26)
		else:
			slot.label.text = slot.data.icon
			slot.label.add_theme_font_size_override("font_size", 28)

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
		_hp_num.text = "%d/%d" % [current, maximum]

func _update_powerup_display() -> void:
	for child in _powerup_display.get_children():
		child.queue_free()
	var labels := {
		"spread": {"color": Color(0.3, 1.0, 0.4, 1.0), "name": "SPR", "bar": Color(0.2, 0.8, 0.3, 1)},
		"speed": {"color": Color(0.4, 0.7, 1.0, 1.0), "name": "SPD", "bar": Color(0.3, 0.6, 1.0, 1)},
		"power": {"color": Color(1.0, 0.4, 0.3, 1.0), "name": "POW", "bar": Color(0.9, 0.3, 0.2, 1)},
	}
	for type in labels:
		var level: int = 0
		match type:
			"spread": level = GameState.shoot_level
			"speed": level = GameState.shoot_speed_level
			"power": level = GameState.bullet_power_level
		if level > 0:
			var block := ColorRect.new()
			block.custom_minimum_size = Vector2(80, 18)
			block.size = Vector2(80, 18)
			block.color = labels[type].bar
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lbl := Label.new()
			lbl.text = "%s %d/15" % [labels[type].name, level]
			lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.horizontal_alignment = 1
			lbl.vertical_alignment = 1
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.add_child(lbl)
			_powerup_display.add_child(block)

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
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0, 0.9))
		label.horizontal_alignment = 1
		label.text = "#%d  %s  —  %s  (等级%d)" % [entries.find(entry) + 1, entry.time, entry.score, entry.level]
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
