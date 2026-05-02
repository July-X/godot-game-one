extends Node3D

signal player_reached_exit
signal player_reached_story_trigger(trigger_index)

@onready var exit_zone = $ExitZone
@onready var exit_marker = $ExitZone/ExitMarker
@onready var exit_collision = $ExitZone/CollisionShape3D

var _exit_locked := true
var _locked_material: StandardMaterial3D
var _unlocked_material: StandardMaterial3D

## 多段剧情触发器：每个触发器只触发一次
var _story_triggers: Array[Dictionary] = []

func _ready() -> void:
	exit_zone.body_entered.connect(_on_exit_body_entered)
	_locked_material = StandardMaterial3D.new()
	_locked_material.albedo_color = Color(0.85, 0.2, 0.2, 0.8)
	_unlocked_material = StandardMaterial3D.new()
	_unlocked_material.albedo_color = Color(0.2, 0.85, 0.35, 0.8)
	_set_exit_visual_state()
	_discover_story_triggers()

## 自动发现所有 StoryTrigger* 节点并注册
func _discover_story_triggers() -> void:
	_story_triggers.clear()
	var index := 1
	while true:
		var trigger_name := "StoryTrigger%d" % index
		if not has_node(trigger_name):
			break
		var trigger: Area3D = get_node(trigger_name)
		trigger.body_entered.connect(_on_story_trigger_body_entered.bind(index))
		_story_triggers.append({"node": trigger, "used": false})
		index += 1

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

func _on_story_trigger_body_entered(body: Node, index: int) -> void:
	if not body.is_in_group("player"):
		return
	var entry_index := index - 1
	if entry_index >= 0 and entry_index < _story_triggers.size():
		if not _story_triggers[entry_index]["used"]:
			_story_triggers[entry_index]["used"] = true
			player_reached_story_trigger.emit(index)
