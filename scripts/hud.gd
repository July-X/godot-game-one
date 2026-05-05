extends CanvasLayer

@onready var _score_label: Label = $ScoreLabel
@onready var _level_label: Label = $LevelLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _powerup_display: HBoxContainer = $PowerupDisplay
@onready var _controls_label: Label = $ControlsLabel
@onready var _game_over_panel: Panel = $GameOverPanel
@onready var _final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var _final_level_label: Label = $GameOverPanel/VBox/FinalLevelLabel
@onready var _restart_label: Label = $GameOverPanel/VBox/RestartLabel

func _ready() -> void:
	_game_over_panel.visible = false
	_set_control_ignore_input(_game_over_panel)
	_update_platform_hints()
	GameState.score_changed.connect(_on_score_changed)
	GameState.level_changed.connect(_on_level_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.powerup_collected.connect(_on_powerup_collected)
	_update_score(0)
	_update_level(1)
	_update_health(3, 3)

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

func _on_powerup_collected(type: String) -> void:
	_update_powerup_display()

func _update_score(score: int) -> void:
	_score_label.text = "得分: %d" % score

func _update_level(level: int) -> void:
	_level_label.text = "等级 %d" % level

func _update_health(current: int, maximum: int) -> void:
	if _health_bar:
		_health_bar.max_value = maximum
		_health_bar.value = current

func _update_powerup_display() -> void:
	for child in _powerup_display.get_children():
		child.queue_free()
	var labels := {
		"spread": {"color": Color(0.3, 1.0, 0.4, 1.0), "name": "扩散"},
		"speed": {"color": Color(0.4, 0.7, 1.0, 1.0), "name": "速射"},
		"power": {"color": Color(1.0, 0.4, 0.3, 1.0), "name": "威力"},
	}
	for type in labels:
		var level: int = 0
		match type:
			"spread": level = GameState.shoot_level
			"speed": level = GameState.shoot_speed_level
			"power": level = GameState.bullet_power_level
		if level > 0:
			var container := HBoxContainer.new()
			var label := Label.new()
			label.text = labels[type].name + ":"
			label.add_theme_color_override("font_color", labels[type].color)
			label.add_theme_font_size_override("font_size", 13)
			container.add_child(label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(60, 14)
			bar.max_value = 5
			bar.value = level
			bar.modulate = labels[type].color
			container.add_child(bar)
			_powerup_display.add_child(container)

func _set_control_ignore_input(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		if child is Control:
			_set_control_ignore_input(child)

func _update_platform_hints() -> void:
	var is_mobile: bool = OS.has_feature("android") or DisplayServer.is_touchscreen_available()
	if is_mobile:
		_controls_label.text = "左侧轮盘 - 移动/转向\n自动射击\n点击屏幕重新开始"
		_restart_label.text = "点击屏幕重新开始"
	else:
		_controls_label.text = "鼠标 - 移动/瞄准\nESC - 释放鼠标\nR - 重新开始"
		_restart_label.text = "按 R 重新开始"
