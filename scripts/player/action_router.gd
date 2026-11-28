extends Node
## 统一动作路由
##
## 接收键盘和 HUD 的动作请求，下一个物理帧由 Player 和 CombatController 消费。

var _queued_actions: Array[String] = []
var touch_dash_direction := Vector2.ZERO


func request_action(action: String) -> void:
	_queued_actions.append(action)


func request_touch_dash(direction: Vector2) -> void:
	if _queued_actions.has("touch_dash"):
		return
	touch_dash_direction = direction
	request_action("touch_dash")


func consume_actions() -> Array[String]:
	var actions := _queued_actions.duplicate()
	_queued_actions.clear()
	return actions


func handle_keyboard_event(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_W:
			request_action("skill")
		KEY_Q:
			request_action("laser")
		KEY_SHIFT:
			request_action("dash")
