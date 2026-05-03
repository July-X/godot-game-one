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
	## 显示成就进度
	var unlocked: int = Achievements.get_unlocked_count()
	var total: int = Achievements.get_all_achievements().size()
	if record_hint.text != "NO RECORD YET":
		record_hint.text += " | ACH: %d/%d" % [unlocked, total]
