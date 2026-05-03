extends Node3D

signal boss_defeated

@onready var boss_node = $Boss


func _ready() -> void:
	if boss_node and boss_node.has_signal("defeated"):
		boss_node.defeated.connect(_on_boss_defeated, CONNECT_ONE_SHOT)


func _on_boss_defeated() -> void:
	boss_defeated.emit()
	# 通知 main.gd
	var main = get_tree().current_scene
	if main != null and main.has_method("notify_boss_defeated"):
		main.notify_boss_defeated()
