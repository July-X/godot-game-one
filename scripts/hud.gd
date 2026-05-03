extends CanvasLayer

@onready var health_label = $Root/TopBar/HealthLabel
@onready var objective_label = $Root/TopBar/ObjectiveLabel
@onready var story_label = $Root/DialogueBox/StoryLabel
@onready var debug_panel = $Root/DebugPanel
@onready var debug_label = $Root/DebugPanel/DebugLabel
@onready var result_panel = $Root/ResultPanel
@onready var title_label = $Root/ResultPanel/CenterBox/VBox/TitleLabel
@onready var story_result_label = $Root/ResultPanel/CenterBox/VBox/StoryResultLabel
@onready var stats_label = $Root/ResultPanel/CenterBox/VBox/StatsLabel
@onready var restart_hint = $Root/ResultPanel/CenterBox/VBox/RestartHint
@onready var time_label = $Root/ResultPanel/CenterBox/VBox/TimeLabel
@onready var record_label = $Root/ResultPanel/CenterBox/VBox/RecordLabel

func set_health(current_health: int, max_health: int) -> void:
	health_label.text = "HP %d/%d" % [current_health, max_health]

func set_objective(text: String) -> void:
	objective_label.text = text

func set_story_line(text: String) -> void:
	story_label.text = text

func set_run_state(state: String) -> void:
	if state == "running":
		story_label.text = "Objective active"
	elif state == "finished":
		story_label.text = "Mission complete. Press Enter to restart."
	elif state == "failed":
		story_label.text = "Mission failed. Press Enter to retry."
	else:
		story_label.text = "Booting..."

func toggle_debug(visible_state: bool) -> void:
	debug_panel.visible = visible_state

func set_debug_text(text: String) -> void:
	debug_label.text = text

func show_damage_feed(text: String) -> void:
	## 底部伤害反馈文本，短暂显示后消失
	var feed_label := $Root/DamageFeedLabel
	if feed_label == null:
		return
	feed_label.text = text
	feed_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(feed_label, "modulate:a", 0.0, 1.2)

func show_result_screen(state: String, story: String, kills: int, total_enemies: int, elapsed_time: String = "") -> void:
	var is_success = state == "finished"
	title_label.text = "MISSION COMPLETE" if is_success else "MISSION FAILED"
	title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4, 1) if is_success else Color(0.85, 0.25, 0.2, 1))
	story_result_label.text = story
	stats_label.text = "Enemies eliminated: %d / %d" % [kills, total_enemies]
	if elapsed_time != "":
		time_label.text = "Time: %s" % elapsed_time
	else:
		time_label.text = ""
	## 显示最佳记录
	var best_time_str: String = SaveSystem.get_best_time_string()
	if record_label != null:
		record_label.text = "Best Time: %s  |  Total Kills: %d" % [best_time_str, SaveSystem.total_kills]
	restart_hint.text = "Press ENTER to return to title"
	result_panel.visible = true
