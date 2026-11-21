extends CanvasLayer

const SafeArea := preload("res://scripts/battle_safe_area.gd")

@onready var _start_label: Label = $StartLabel
@onready var _btn_single: Button = $BtnSingle
@onready var _btn_multi: Button = $BtnMultiplayer
@onready var _btn_first_card: Button = $BtnFirstCard
@onready var _trial_choices: VBoxContainer = $TrialChoices

func _ready() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_blink()
	# 触摸合成的鼠标释放仍会访问触发按钮，等 GUI 处理结束后再切场景。
	_btn_single.pressed.connect(_on_single_pressed, CONNECT_DEFERRED)
	_btn_multi.pressed.connect(_on_multiplayer_pressed)
	_btn_first_card.pressed.connect(_show_trial_choices.bind(true))
	$TrialChoices/A.pressed.connect(_start_game.bind("res://scenes/first_card_trial_a.tscn"), CONNECT_DEFERRED)
	$TrialChoices/B.pressed.connect(_start_game.bind("res://scenes/first_card_trial_b.tscn"), CONNECT_DEFERRED)
	$TrialChoices/Back.pressed.connect(_show_trial_choices.bind(false))
	get_viewport().size_changed.connect(_refresh_trial_layout)
	get_window().focus_entered.connect(_refresh_trial_layout)


func _show_trial_choices(open: bool) -> void:
	for item: Control in [_start_label, _btn_single, _btn_multi, _btn_first_card]:
		item.visible = not open
	_trial_choices.visible = open
	if open:
		_refresh_trial_layout()


func _refresh_trial_layout() -> void:
	if _trial_choices.visible:
		_layout_trial_choices(SafeArea.for_viewport(get_viewport()))


func _layout_trial_choices(safe: Rect2) -> void:
	_trial_choices.size = _trial_choices.get_combined_minimum_size()
	var center := safe.get_center()
	var y := minf(center.y + 64, safe.end.y - _trial_choices.size.y - 12)
	_trial_choices.position = Vector2(center.x - _trial_choices.size.x * 0.5, maxf(safe.position.y + 12, y)).round()


func _start_blink() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_start_label, "modulate:a", 0.3, 0.8)
	tween.tween_property(_start_label, "modulate:a", 1.0, 0.8)


func _input(event: InputEvent) -> void:
	## 仅保留键盘快捷键，避免移动端误触空白区域直接进单机
	if event is InputEventKey and event.pressed and not event.echo:
		if _trial_choices.visible:
			if event.is_action_pressed("ui_cancel"):
				_show_trial_choices(false)
				get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_W or (event.keycode == KEY_ENTER and get_viewport().gui_get_focus_owner() == null):
			_start_game()


func _start_game(scene_path := "res://scenes/main.tscn") -> void:
	if not is_inside_tree():
		return
	## 单机模式入口前先清理可能残留的联机状态，
	## 避免上次联机会话影响单机 authority / 输入链路。
	NetworkDiscovery.stop_all()
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	get_tree().change_scene_to_file(scene_path)


func _on_multiplayer_pressed() -> void:
	## 进入多人大厅前也做一次清理，确保每次都是新会话。
	NetworkDiscovery.stop_all()
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	## 多人模式入口：进入 lobby 选择角色
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _on_single_pressed() -> void:
	_start_game()
