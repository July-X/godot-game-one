extends CanvasLayer

signal briefing_finished

@onready var story_label = $Root/Panel/StoryLabel
@onready var skip_hint = $Root/Panel/SkipHint

var _briefing_lines: Array[String] = [
	"Command Log — Priority Alpha",
	"",
	"Operator 07, this is Central Command.",
	"The outpost relay station has been compromised.",
	"",
	"Enemy forces have seized the data terminal.",
	"Your objective: infiltrate the corridor,",
	"neutralize all hostiles, and secure the relay.",
	"",
	"New intel: a forward base lies beyond.",
	"Expect heavy resistance — shooter units",
	"and jump troops are in the area.",
	"",
	"Once the area is clear, extract through",
	"the terminal room immediately.",
	"",
	"There is no backup. There is no extraction.",
	"Move fast, or the relay is lost.",
	"",
	"— Command Out —"
]

var _current_line: int = 0
var _all_shown: bool = false
var _line_timer: float = 0.0
var _typing_phase: bool = true

const LINE_DELAY: float = 1.8

func _ready() -> void:
	story_label.text = ""
	skip_hint.modulate.a = 0.0

func _process(delta: float) -> void:
	if not _typing_phase:
		return
	if _all_shown:
		skip_hint.modulate.a = 0.3 + abs(sin(Time.get_ticks_msec() * 0.004)) * 0.7
		if Input.is_action_just_pressed("ui_accept"):
			briefing_finished.emit()
		return
	_line_timer += delta
	if _line_timer >= LINE_DELAY:
		_line_timer = 0.0
		_show_next_line()

func _show_next_line() -> void:
	if _current_line >= _briefing_lines.size():
		_all_shown = true
		story_label.text += "\n\n[ PRESS ENTER TO BEGIN ]"
		return
	var line = _briefing_lines[_current_line]
	if story_label.text == "":
		story_label.text = line
	else:
		story_label.text += "\n" + line
	_current_line += 1

func skip_to_end() -> void:
	briefing_finished.emit()
