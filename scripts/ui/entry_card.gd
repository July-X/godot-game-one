extends Button

@export var detail := ""

func _ready() -> void:
	if theme_type_variation.is_empty():
		theme_type_variation = &"EntryCard"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text = true
	custom_minimum_size.y = maxf(custom_minimum_size.y, 72.0)
	var note := Label.new()
	note.text = detail
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color("#a2b9cf"))
	add_child(note)
	note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	note.offset_left = 18
	note.offset_right = -16
	note.offset_top = -32
	note.offset_bottom = -9
