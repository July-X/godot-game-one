extends Button
## 触屏热区与技能按钮使用同一圆形。

var circular := false
var accent := Color.WHITE
var _progress := 1.0
var _ready_to_cast := true
var _rejected := false
var _press := 0.0
var _press_tween: Tween


func set_circular(enabled: bool) -> void:
	if circular == enabled:
		return
	circular = enabled
	var empty := StyleBoxEmpty.new()
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		if circular:
			add_theme_stylebox_override(style, empty)
		else:
			remove_theme_stylebox_override(style)
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	if not circular:
		return Rect2(Vector2.ZERO, size).has_point(point)
	var center := size * 0.5
	return point.distance_squared_to(center) <= center.x * center.x


func update_touch_state(progress: float, ready_to_cast: bool, rejected: bool) -> void:
	if _progress == progress and _ready_to_cast == ready_to_cast and _rejected == rejected:
		return
	_progress = progress
	_ready_to_cast = ready_to_cast
	_rejected = rejected
	queue_redraw()


func flash_press() -> void:
	if not circular:
		return
	if _press_tween:
		_press_tween.kill()
	_set_press(1.0)
	_press_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_press_tween.tween_method(_set_press, 1.0, 0.0, 0.16)


func _set_press(amount: float) -> void:
	_press = amount
	queue_redraw()


func _draw() -> void:
	if not circular:
		return
	var center := size * 0.5
	var radius := center.x
	var rim := Color("#f59583") if _rejected else accent
	var fill := Color("#172a3deb") if _ready_to_cast else Color("#0d1928e6")
	draw_circle(center, radius, fill.lerp(rim, _press * 0.27), true, -1.0, true)
	draw_circle(center, radius - 1.5, Color("#526377"), false, 2.0, true)
	draw_circle(center, radius - 6.0, Color("#2a4158"), false, 1.0, true)
	if _ready_to_cast or _rejected:
		draw_circle(center, radius - 1.5, rim, false, 3.0, true)
	elif _progress > 0.0:
		draw_arc(center, radius - 1.5, -PI * 0.5, -PI * 0.5 + TAU * _progress,
			40, Color("#8ca7ba"), 3.0, true)
