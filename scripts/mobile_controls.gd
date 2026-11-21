extends CanvasLayer
const SafeArea = preload("res://scripts/battle_safe_area.gd")

@export var joystick_radius: float = 112.0
@export var knob_scale: float = 0.38
var _move_vector: Vector2 = Vector2.ZERO
var _joystick_center: Vector2 = Vector2.ZERO
var _move_touch_id: int = -1
var _ui_root: Control
var _base_node: Panel
var _knob_node: Panel
var _base_style: StyleBoxFlat
var _knob_style: StyleBoxFlat

signal move_input(vector: Vector2)

func _ready() -> void:
	_build_visual_nodes()
	_recalc_joystick()
	get_viewport().size_changed.connect(_recalc_joystick)
	get_window().focus_entered.connect(_recalc_joystick)
	get_window().focus_exited.connect(_release_move_touch)

func _recalc_joystick() -> void:
	_layout_in_safe_area(SafeArea.for_viewport(get_viewport()))

func _layout_in_safe_area(safe: Rect2) -> void:
	_joystick_center = Vector2(safe.position.x + joystick_radius + 48, safe.end.y - joystick_radius - 58)
	_base_node.position = _joystick_center - _base_node.size * 0.5
	_update_visual_knob(_joystick_center + _move_vector * joystick_radius)

func _input(event: InputEvent) -> void:
	# 先于 GUI 续接摇杆手指，拖出摇杆区也能收到松手。
	if event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed and _move_touch_id == -1 and _is_in_joystick_area(event.position):
			_move_touch_id = event.index
			_set_active_visual(true)
			_update_move_vector(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _move_touch_id:
			_release_move_touch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _move_touch_id:
			_update_move_vector(event.position)
			get_viewport().set_input_as_handled()

func _release_move_touch() -> void:
	if _move_touch_id == -1:
		return
	_move_touch_id = -1
	_move_vector = Vector2.ZERO
	move_input.emit(Vector2.ZERO)
	_set_active_visual(false)
	_update_visual_knob(_joystick_center)

func _is_in_joystick_area(pos: Vector2) -> bool:
	var dx: float = pos.x - _joystick_center.x
	var dy: float = pos.y - _joystick_center.y
	return dx * dx + dy * dy < joystick_radius * joystick_radius * 1.5

func _update_move_vector(current_pos: Vector2) -> void:
	var delta_v: Vector2 = current_pos - _joystick_center
	if delta_v.length() <= 0.001:
		_move_vector = Vector2.ZERO
		_update_visual_knob(_joystick_center)
	else:
		_move_vector = delta_v / joystick_radius
		_move_vector = _move_vector.limit_length(1.0)
		_update_visual_knob(_joystick_center + _move_vector * joystick_radius)
	move_input.emit(_move_vector)

func _build_visual_nodes() -> void:
	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)
	_base_node = Panel.new()
	_base_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_node.size = Vector2(joystick_radius * 2.0, joystick_radius * 2.0)
	_base_node.position = _joystick_center - _base_node.size * 0.5
	_base_style = StyleBoxFlat.new()
	_base_style.bg_color = Color(0.1, 0.15, 0.25, 0.28)
	_base_style.border_color = Color(0.45, 0.65, 1.0, 0.78)
	_base_style.border_width_left = 3
	_base_style.border_width_top = 3
	_base_style.border_width_right = 3
	_base_style.border_width_bottom = 3
	_base_style.corner_radius_top_left = int(joystick_radius)
	_base_style.corner_radius_top_right = int(joystick_radius)
	_base_style.corner_radius_bottom_left = int(joystick_radius)
	_base_style.corner_radius_bottom_right = int(joystick_radius)
	_base_node.add_theme_stylebox_override("panel", _base_style)
	_ui_root.add_child(_base_node)
	var knob_radius: float = joystick_radius * knob_scale
	_knob_node = Panel.new()
	_knob_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob_node.size = Vector2(knob_radius * 2.0, knob_radius * 2.0)
	_knob_style = StyleBoxFlat.new()
	_knob_style.bg_color = Color(0.65, 0.8, 1.0, 0.88)
	_knob_style.border_color = Color(1.0, 1.0, 1.0, 0.85)
	_knob_style.border_width_left = 2
	_knob_style.border_width_top = 2
	_knob_style.border_width_right = 2
	_knob_style.border_width_bottom = 2
	_knob_style.corner_radius_top_left = int(knob_radius)
	_knob_style.corner_radius_top_right = int(knob_radius)
	_knob_style.corner_radius_bottom_left = int(knob_radius)
	_knob_style.corner_radius_bottom_right = int(knob_radius)
	_knob_node.add_theme_stylebox_override("panel", _knob_style)
	_ui_root.add_child(_knob_node)

func _update_visual_knob(knob_center: Vector2) -> void:
	if _knob_node == null:
		return
	_knob_node.position = knob_center - _knob_node.size * 0.5

func _set_active_visual(active: bool) -> void:
	if _base_style == null or _knob_style == null:
		return
	if active:
		_base_style.bg_color = Color(0.2, 0.3, 0.45, 0.12)
		_base_style.border_color = Color(0.6, 0.8, 1.0, 0.28)
		_knob_style.bg_color = Color(0.8, 0.9, 1.0, 0.25)
		_knob_style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	else:
		_base_style.bg_color = Color(0.1, 0.15, 0.25, 0.28)
		_base_style.border_color = Color(0.45, 0.65, 1.0, 0.78)
		_knob_style.bg_color = Color(0.65, 0.8, 1.0, 0.88)
		_knob_style.border_color = Color(1.0, 1.0, 1.0, 0.85)
