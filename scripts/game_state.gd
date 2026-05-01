extends Node

signal health_changed(current_health, max_health)
signal objective_changed(text)
signal story_line_changed(text)
signal run_state_changed(state)

var max_health: int = 5
var current_health: int = 5
var objective_text: String = "Reach the relay terminal"
var story_line: String = "Command: hold the line and retrieve the data core."
var run_state: String = "boot"

func reset_run() -> void:
	current_health = max_health
	objective_text = "Reach the relay terminal"
	story_line = "Command: hold the line and retrieve the data core."
	run_state = "running"
	health_changed.emit(current_health, max_health)
	objective_changed.emit(objective_text)
	story_line_changed.emit(story_line)
	run_state_changed.emit(run_state)

func set_run_state(state: String) -> void:
	run_state = state
	run_state_changed.emit(run_state)

func set_objective(text: String) -> void:
	objective_text = text
	objective_changed.emit(objective_text)

func set_story_line(text: String) -> void:
	story_line = text
	story_line_changed.emit(story_line)

func damage_player(amount: int = 1) -> void:
	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		run_state = "failed"
		run_state_changed.emit(run_state)

func heal_player(amount: int = 1) -> void:
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)
