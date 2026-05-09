extends CanvasLayer

@onready var _start_label: Label = $StartLabel
@onready var _btn_multi: Button = $BtnMultiplayer

func _ready() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_blink()
	_btn_multi.pressed.connect(_on_multiplayer_pressed)


func _start_blink() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_start_label, "modulate:a", 0.3, 0.8)
	tween.tween_property(_start_label, "modulate:a", 1.0, 0.8)


func _input(event: InputEvent) -> void:
	## 点击空白区域或按 W 开始单机游戏
	## 注意：点击"多人联机"按钮时会触发按钮的 pressed 信号，不走这里
	if event is InputEventMouseButton and event.pressed:
		## 检查点击是否在按钮范围内（用全局坐标）
		var btn_rect := _btn_multi.get_global_rect()
		if not btn_rect.has_point(event.position):
			_start_game()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W or event.keycode == KEY_ENTER:
			_start_game()


func _start_game() -> void:
	## 单机模式入口：直接进入 main.tscn
	## NetworkManager.is_online() 在 main.gd 中会返回 false，走原有单人逻辑
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_multiplayer_pressed() -> void:
	## 多人模式入口：进入 lobby 选择角色
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
