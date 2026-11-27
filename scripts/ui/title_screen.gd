extends CanvasLayer

const SafeArea := preload("res://scripts/ui/battle_safe_area.gd")
const RouteRules := preload("res://scripts/battle/trials/rift_route_rules.gd")

@export var show_opening_choices_on_entry := false

@onready var _menu: VBoxContainer = $Menu
@onready var _hero: VBoxContainer = $Hero
@onready var _trial_hub: VBoxContainer = $TrialHub
@onready var _trial_choices: VBoxContainer = $TrialChoices
@onready var _opening_choices: VBoxContainer = $OpeningChoices
@onready var _rift_choices: VBoxContainer = $RiftChoices
var _active_menu: VBoxContainer

func _ready() -> void:
	GameState.rift_remix = false
	GameState.rift_dual_intercept = false
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 让触摸合成的鼠标事件全部处理完毕，再切换场景。
	$Menu/BtnSingle.pressed.connect(_start_game, CONNECT_DEFERRED)
	$Menu/BtnMultiplayer.pressed.connect(_on_multiplayer_pressed, CONNECT_DEFERRED)
	$Menu/BtnTrials.pressed.connect(_show_menu.bind(_trial_hub))
	$TrialHub/BtnFirstCard.pressed.connect(_show_menu.bind(_trial_choices))
	$TrialHub/BtnOffenseWindow.pressed.connect(_start_game.bind("res://scenes/offense_window_trial.tscn"), CONNECT_DEFERRED)
	$TrialHub/BtnOpeningTrial.pressed.connect(_show_menu.bind(_opening_choices))
	$TrialHub/BtnRiftRoute.pressed.connect(_show_menu.bind(_rift_choices))
	$RiftChoices/Original.text = RouteRules.ORIGINAL
	$RiftChoices/Remix.text = RouteRules.REMIX
	$RiftChoices/DualIntercept.text = RouteRules.DUAL_INTERCEPT + " · 仅双人"
	$RiftChoices/Original.pressed.connect(_start_rift.bind(false), CONNECT_DEFERRED)
	$RiftChoices/Remix.pressed.connect(_start_rift.bind(true), CONNECT_DEFERRED)
	$RiftChoices/DualIntercept.pressed.connect(_on_multiplayer_pressed.bind(true), CONNECT_DEFERRED)
	$TrialChoices/A.pressed.connect(_start_game.bind("res://scenes/first_card_trial_a.tscn"), CONNECT_DEFERRED)
	$TrialChoices/B.pressed.connect(_start_game.bind("res://scenes/first_card_trial_b.tscn"), CONNECT_DEFERRED)
	$OpeningChoices/Start.pressed.connect(_start_game.bind("res://scenes/opening_trial.tscn"), CONNECT_DEFERRED)
	$OpeningChoices/A.pressed.connect(_start_game.bind("res://scenes/elite_close_trial_a.tscn"), CONNECT_DEFERRED)
	$OpeningChoices/B.pressed.connect(_start_game.bind("res://scenes/elite_close_trial_b.tscn"), CONNECT_DEFERRED)
	for panel: VBoxContainer in [_trial_hub, _trial_choices, _opening_choices, _rift_choices]:
		panel.get_node("Back").pressed.connect(_back)
	get_viewport().size_changed.connect(_layout_title)
	get_window().focus_entered.connect(_layout_title)
	_show_menu(_opening_choices if show_opening_choices_on_entry else _menu)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_layout_title.call_deferred()

func _show_menu(active: VBoxContainer, focus: Button = null) -> void:
	_active_menu = active
	for menu: VBoxContainer in [_menu, _trial_hub, _trial_choices, _opening_choices, _rift_choices]:
		menu.visible = menu == active
	_layout_title()
	if focus == null:
		for child in active.get_children():
			if child is Button:
				focus = child
				break
	if focus:
		focus.grab_focus()

func _back() -> void:
	if _active_menu == _trial_hub:
		_show_menu(_menu, $Menu/BtnTrials)
	elif _active_menu == _trial_choices:
		_show_menu(_trial_hub, $TrialHub/BtnFirstCard)
	elif _active_menu == _opening_choices:
		_show_menu(_trial_hub, $TrialHub/BtnOpeningTrial)
	elif _active_menu == _rift_choices:
		_show_menu(_trial_hub, $TrialHub/BtnRiftRoute)

func _layout_title() -> void:
	_layout_in_safe_area(SafeArea.for_viewport(get_viewport()))

func _layout_in_safe_area(safe: Rect2) -> void:
	if not is_instance_valid(_active_menu):
		return
	var content := safe.grow(-SafeArea.MENU_MARGIN)
	var side_by_side := content.size.x >= 790.0 and _active_menu in [_menu, _trial_hub]
	var menu_width := minf(408.0, content.size.x * 0.46) if side_by_side else minf(430.0, content.size.x)
	_active_menu.size = Vector2(menu_width, 0)
	var center := content.get_center()
	if side_by_side:
		var logo_width := minf(570.0, content.size.x * 0.48)
		var gap := clampf(content.size.x * 0.045, 26.0, 76.0)
		var start := center.x - (logo_width + gap + menu_width) * 0.5
		_hero.size = Vector2(logo_width, logo_width * 0.3125 + 34.0)
		_hero.position = Vector2(start, center.y - _hero.size.y * 0.5).round()
		_active_menu.position = Vector2(start + logo_width + gap, center.y - _active_menu.size.y * 0.5).round()
		_hero.show()
	else:
		var space := content.size.y - _active_menu.size.y - 18.0
		_hero.visible = space >= 66.0
		_hero.size = Vector2(menu_width, clampf(space, 66.0, 170.0))
		var hero_height := _hero.size.y + 18.0 if _hero.visible else 0.0
		var top := center.y - (_active_menu.size.y + hero_height) * 0.5
		_hero.position = Vector2(center.x - menu_width * 0.5, top).round()
		_active_menu.position = Vector2(center.x - menu_width * 0.5, top + hero_height).round()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _menu.visible:
		_back()
		get_viewport().set_input_as_handled()
		return
	if _menu.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W or (event.keycode == KEY_ENTER and get_viewport().gui_get_focus_owner() == null):
			_start_game()

func _start_game(scene_path := "res://scenes/main.tscn") -> void:
	if not is_inside_tree():
		return
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	get_tree().change_scene_to_file(scene_path)

func _start_rift(remix: bool) -> void:
	GameState.rift_remix = remix
	_start_game("res://scenes/rift_route_trial.tscn")

func _on_multiplayer_pressed(dual_intercept := false) -> void:
	if not is_inside_tree():
		return
	HarmonyBridge.stop_all()
	NetworkManager.disconnect_network()
	GameState.rift_dual_intercept = dual_intercept
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
