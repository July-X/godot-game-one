extends Node
## 统一动作路由
##
## 接收来自键盘、HUD 按钮、移动端控件的动作请求，
## 在下一帧由 CombatController 消费。
##
## 新增动作来源时只需调用 request_action()，不需直接调用私有战斗方法。

var _queued_actions: Array[String] = []


func request_action(action: String) -> void:
	_queued_actions.append(action)


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
