extends Node2D

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	_sprite.modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(2, 2), 0.15)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)
