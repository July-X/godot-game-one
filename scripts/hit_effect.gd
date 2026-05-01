extends Node3D

func _ready() -> void:
	var timer = $Timer
	timer.timeout.connect(queue_free)
