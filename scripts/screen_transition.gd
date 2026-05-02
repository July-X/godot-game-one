extends CanvasLayer

signal transition_finished

@onready var overlay: ColorRect = $Overlay

func _ready() -> void:
	overlay.visible = false
	overlay.color = Color(0, 0, 0, 0)

func fade_out(duration: float = 0.4) -> void:
	overlay.visible = true
	var tween := create_tween()
	tween.tween_property(overlay, "color", Color(0, 0, 0, 1), duration)
	tween.tween_signal(self, "transition_finished")

func fade_in(duration: float = 0.3) -> void:
	overlay.visible = true
	overlay.color = Color(0, 0, 0, 1)
	var tween := create_tween()
	tween.tween_property(overlay, "color", Color(0, 0, 0, 0), duration)
	tween.tween_callback(func():
		overlay.visible = false
	)
	tween.tween_signal(self, "transition_finished")
