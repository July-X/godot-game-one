extends Node3D

signal player_reached_exit
signal player_reached_story_trigger

@onready var exit_zone = $ExitZone
@onready var player_spawn = $PlayerSpawn
@onready var exit_marker = $ExitZone/ExitMarker
@onready var exit_collision = $ExitZone/CollisionShape3D
@onready var story_trigger = $StoryTrigger

var _exit_locked := true
var _locked_material: StandardMaterial3D
var _unlocked_material: StandardMaterial3D
var _story_trigger_used := false

func _ready() -> void:
	exit_zone.body_entered.connect(_on_exit_body_entered)
	story_trigger.body_entered.connect(_on_story_trigger_body_entered)
	_locked_material = StandardMaterial3D.new()
	_locked_material.albedo_color = Color(0.85, 0.2, 0.2, 0.8)
	_unlocked_material = StandardMaterial3D.new()
	_unlocked_material.albedo_color = Color(0.2, 0.85, 0.35, 0.8)
	_set_exit_visual_state()

func register_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	enemy.defeated.connect(_on_enemy_defeated)

func set_exit_locked(locked: bool) -> void:
	_exit_locked = locked
	_set_exit_visual_state()

func _set_exit_visual_state() -> void:
	if exit_marker != null:
		exit_marker.material_override = _locked_material if _exit_locked else _unlocked_material
	if exit_collision != null:
		exit_collision.disabled = false

func _on_enemy_defeated() -> void:
	var main = get_tree().current_scene
	if main != null and main.has_method("notify_enemy_defeated"):
		main.notify_enemy_defeated()

func _on_exit_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not _exit_locked:
		player_reached_exit.emit()

func _on_story_trigger_body_entered(body: Node) -> void:
	if _story_trigger_used:
		return
	if body.is_in_group("player"):
		_story_trigger_used = true
		player_reached_story_trigger.emit()
