extends CanvasLayer

@onready var _score_label: Label = $ScoreLabel
@onready var _level_label: Label = $LevelLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _powerup_display: HBoxContainer = $PowerupDisplay
@onready var _game_over_panel: Panel = $GameOverPanel
@onready var _final_score_label: Label = $GameOverPanel/VBox/FinalScoreLabel
@onready var _final_level_label: Label = $GameOverPanel/VBox/FinalLevelLabel

func _ready() -> void:
	_game_over_panel.visible = false
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
	_final_score_label.text = "SCORE: %d" % final_score
	_final_level_label.text = "LEVEL: %d" % final_level

func _on_powerup_collected(type: String) -> void:
	_update_powerup_display()

func _update_score(score: int) -> void:
	_score_label.text = "SCORE: %d" % score

func _update_level(level: int) -> void:
	_level_label.text = "LEVEL %d" % level

func _update_health(current: int, maximum: int) -> void:
	if _health_bar:
		_health_bar.max_value = maximum
		_health_bar.value = current

func _update_powerup_display() -> void:
	for child in _powerup_display.get_children():
		child.queue_free()
	var labels := {
		"spread": {"color": Color(0.2, 0.8, 0.3), "name": "W"},
		"speed": {"color": Color(0.2, 0.5, 1.0), "name": "F"},
		"power": {"color": Color(1.0, 0.3, 0.2), "name": "P"},
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
			label.add_theme_font_size_override("font_size", 12)
			container.add_child(label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(50, 10)
			bar.max_value = 5
			bar.value = level
			bar.modulate = labels[type].color
			container.add_child(bar)
			_powerup_display.add_child(container)
