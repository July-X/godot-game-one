extends CanvasLayer
const SafeArea = preload("res://scripts/ui/battle_safe_area.gd")

@export var joystick_radius: float = 112.0
@export var knob_scale: float = 0.38
var _move_vector: Vector2 = Vector2.ZERO
var _joystick_center: Vector2 = Vector2.ZERO
var _move_touch_id: int = -1
var _safe := Rect2()
var _ui_root: Control
var _base_node: Panel
var _knob_node: Panel

signal move_input(vector: Vector2)

func _ready() -> void:
	_build_visual_nodes()
	_recalc_joystick()
	get_viewport().size_changed.connect(_recalc_joystick)
	get_window().focus_entered.connect(_recalc_joystick)
	get_window().focus_exited.connect(cancel_move_touch)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		cancel_move_touch()
	elif what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_recalc_joystick.call_deferred()

func _recalc_joystick() -> void:
	_layout_in_safe_area(SafeArea.for_viewport(get_viewport()))

func _layout_in_safe_area(safe: Rect2) -> void:
	_safe = safe
	if _move_touch_id != -1:
		_update_visual()

func _input(event: InputEvent) -> void:
	# 摇杆手指一旦被认领，就不能把拖动或抬起送给后来出现的按钮。
	if event.device == InputEvent.DEVICE_ID_EMULATION or _move_touch_id == -1:
		return
	if event is InputEventScreenTouch and event.index == _move_touch_id:
		if not event.pressed or event.canceled:
			cancel_move_touch()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _move_touch_id:
		_move_vector = ((event.position - _joystick_center) / joystick_radius).limit_length()
		_update_visual()
		move_input.emit(_move_vector)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# 新触摸先交给 GUI，只有左手区的空白处能起手。
	if (event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION
			and event.pressed and not event.canceled and _move_touch_id == -1
			and _safe.has_point(event.position) and event.position.x < _safe.get_center().x
			and GameState.game_running):
		_move_touch_id = event.index
		_joystick_center = event.position
		_ui_root.show()
		_update_visual()
		get_viewport().set_input_as_handled()

func disable_for_results() -> void:
	cancel_move_touch()
	set_process_input(false)
	set_process_unhandled_input(false)
	hide()

func cancel_move_touch() -> void:
	if _move_touch_id == -1:
		return
	_move_touch_id = -1
	_move_vector = Vector2.ZERO
	_ui_root.hide()
	move_input.emit(Vector2.ZERO)

func _update_visual() -> void:
	var half := _base_node.size * 0.5
	var visual_center := _joystick_center.clamp(_safe.position + half, _safe.end - half)
	_base_node.position = visual_center - half
	var travel := half.x - _knob_node.size.x * 0.5
	_knob_node.position = visual_center + _move_vector * travel - _knob_node.size * 0.5

func _build_visual_nodes() -> void:
	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.hide()
	add_child(_ui_root)
	var visual_radius := joystick_radius * 0.6
	_base_node = _make_disc(visual_radius, Color("#16223550"), Color("#9accff80"))
	_knob_node = _make_disc(visual_radius * knob_scale, Color("#a6c8ff75"), Color("#e4f1ff90"))

func _make_disc(radius: float, fill: Color, outline: Color) -> Panel:
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size = Vector2.ONE * radius * 2.0
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(radius))
	disc.add_theme_stylebox_override("panel", style)
	_ui_root.add_child(disc)
	return disc
