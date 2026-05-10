extends CanvasLayer

@onready var _start_label: Label = $StartLabel
@onready var _btn_single: Button = $BtnSingle
@onready var _btn_multi: Button = $BtnMultiplayer

func _ready() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_blink()
	_btn_single.pressed.connect(_on_single_pressed)
	_btn_multi.pressed.connect(_on_multiplayer_pressed)


func _start_blink() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_start_label, "modulate:a", 0.3, 0.8)
	tween.tween_property(_start_label, "modulate:a", 1.0, 0.8)


func _input(event: InputEvent) -> void:
	## 仅保留键盘快捷键，避免移动端误触空白区域直接进单机
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W or event.keycode == KEY_ENTER:
			_start_game()


func _start_game() -> void:
	## 单机模式入口前先清理可能残留的联机状态，
	## 避免上次联机会话影响单机 authority / 输入链路。
	NetworkDiscovery.stop_all()
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_multiplayer_pressed() -> void:
	## 进入多人大厅前也做一次清理，确保每次都是新会话。
	NetworkDiscovery.stop_all()
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	## 多人模式入口：进入 lobby 选择角色
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _on_single_pressed() -> void:
	_start_game()
