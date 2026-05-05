extends CanvasLayer

var _touch_active: bool = false
var _touch_pos: Vector2 = Vector2.ZERO
var _move_vector: Vector2 = Vector2.ZERO
var _aim_pos: Vector2 = Vector2.ZERO
var _shooting: bool = false
var _move_touch_id: int = -1
var _aim_touch_id: int = -1
var _is_mobile: bool = false

signal move_input(vector: Vector2)
signal aim_pos(pos: Vector2)
signal shoot_pressed
signal shoot_released

func _ready() -> void:
	_is_mobile = OS.has_feature("android") or DisplayServer.is_touchscreen_available()
	if not _is_mobile:
		hide()
		set_process(false)
		set_process_input(false)

func _input(event: InputEvent) -> void:
	if not _is_mobile:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < get_viewport().size.x * 0.4 and _move_touch_id == -1:
				_move_touch_id = event.index
				_touch_active = true
				_touch_pos = event.position
			elif event.position.x >= get_viewport().size.x * 0.4 and _aim_touch_id == -1:
				_aim_touch_id = event.index
				_aim_pos = event.position
				if GameState.game_running:
					_shooting = true
					shoot_pressed.emit()
		else:
			if event.index == _move_touch_id:
				_move_touch_id = -1
				_move_vector = Vector2.ZERO
				move_input.emit(Vector2.ZERO)
			if event.index == _aim_touch_id:
				_aim_touch_id = -1
				_shooting = false
				shoot_released.emit()

	if event is InputEventScreenDrag:
		if event.index == _move_touch_id:
			var screen: Vector2 = get_viewport().size
			var delta_v: Vector2 = (event.position - _touch_pos) / screen
			_move_vector = delta_v.limit_length(1.0)
			move_input.emit(_move_vector)
			_touch_pos = event.position
		if event.index == _aim_touch_id:
			_aim_pos = event.position
			aim_pos.emit(_aim_pos)
			if not _shooting and GameState.game_running:
				_shooting = true
				shoot_pressed.emit()
