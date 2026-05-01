extends CanvasLayer

@onready var health_label = $Root/TopBar/HealthLabel
@onready var objective_label = $Root/TopBar/ObjectiveLabel
@onready var story_label = $Root/DialogueBox/StoryLabel
@onready var status_label = $Root/StatusLabel
@onready var debug_panel = $Root/DebugPanel
@onready var debug_label = $Root/DebugPanel/DebugLabel

func set_health(current_health: int, max_health: int) -> void:
	health_label.text = "HP %d/%d" % [current_health, max_health]

func set_objective(text: String) -> void:
	objective_label.text = text

func set_story_line(text: String) -> void:
	story_label.text = text

func set_run_state(state: String) -> void:
	if state == "running":
		status_label.text = "Objective active"
	elif state == "finished":
		status_label.text = "Mission complete. Press Enter to restart."
	elif state == "failed":
		status_label.text = "Mission failed. Press Enter to retry."
	else:
		status_label.text = "Booting..."

func toggle_debug(visible_state: bool) -> void:
	debug_panel.visible = visible_state

func set_debug_text(text: String) -> void:
	debug_label.text = text
