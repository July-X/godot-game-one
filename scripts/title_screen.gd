extends CanvasLayer

@onready var start_hint = $Root/CenterContainer/VBox/StartHint
@onready var record_hint = $Root/CenterContainer/VBox/RecordHint

var _blink_timer: float = 0.0

func _ready() -> void:
	_blink_timer = 0.0
	_update_record_display()

func _process(delta: float) -> void:
	_blink_timer += delta
	start_hint.modulate.a = 0.3 + abs(sin(_blink_timer * 2.5)) * 0.7

func _update_record_display() -> void:
	if record_hint == null:
		return
	if SaveSystem.best_time <= 0.0:
		record_hint.text = "NO RECORD YET"
	else:
		record_hint.text = "BEST: %s  |  KILLS: %d" % [SaveSystem.get_best_time_string(), SaveSystem.total_kills]
