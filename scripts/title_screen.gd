extends CanvasLayer

@onready var _start_label: Label = $StartLabel

func _ready() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_blink()

func _start_blink() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_start_label, "modulate:a", 0.3, 0.8)
	tween.tween_property(_start_label, "modulate:a", 1.0, 0.8)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_start_game()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_start_game()

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
