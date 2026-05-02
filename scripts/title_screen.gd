extends CanvasLayer

@onready var start_hint = $Root/CenterContainer/VBox/StartHint
@onready var title_label = $Root/CenterContainer/VBox/TitleLabel

var _blink_timer: float = 0.0

func _ready() -> void:
	_blink_timer = 0.0

func _process(delta: float) -> void:
	_blink_timer += delta
	start_hint.modulate.a = 0.3 + abs(sin(_blink_timer * 2.5)) * 0.7
