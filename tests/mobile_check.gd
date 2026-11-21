extends Node
## 移动端交互回归探针（headless 单进程）
##
## 用法：
##   godot --headless --path . res://tests/mobile_check.tscn
##
## 它守的是**只在触摸端暴露**的问题——单机与联机门禁都测不到：
##   1. 升级卡必须是可点控件。原来的卡片是 PanelContainer + Label，
##      Control 默认 mouse_filter=STOP，点击被吃掉却没人处理，
##      手机上表现为"点了没反应"；桌面端靠 1/2/3 键所以完全测不出来。
##   2. 闪避必须有按钮入口。闪避原本只有 Shift 键（action_router.gd），
##      手机上根本触发不了。
##   3. 相机 / 出怪中心必须跟着视口走。视口不再是固定 1280×720 之后，
##      写死的 (640, 360) 会让画面偏出可视区，看起来就是"不是全屏"。

const TAG := "[MOBILE]"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var hud: Node = main.get_node_or_null("HUD")
	_check("hud_present", hud != null, "HUD=%s" % str(hud))
	if hud == null:
		_report()
		return

	_check_skill_slots(hud)
	await _check_touch_card_select(hud)
	await _check_dash_button(hud)
	_check_camera_centered(main)
	await _check_joystick(main)
	_report()


# ── 1. 技能槽（含闪避）─────────────────────────────────────

func _check_skill_slots(hud: Node) -> void:
	var bar: Node = hud.get_node_or_null("SkillBar")
	if bar == null:
		_check("skill_slots_built", false, "找不到 SkillBar")
		return
	var count: int = bar.get_child_count()
	var labels: Array = []
	for c in bar.get_children():
		labels.append(_collect_label_texts(c))
	var flat: Array = []
	for entry: Array in labels:
		flat.append_array(entry)
	_check("skill_slots_built", count == 3,
		"技能槽数=%d（期望 3）槽内文本=%s" % [count, str(labels)])
	## 必须收集**所有** Label 而不是第一个：图标缺失时槽里会先出现
	## 字形兜底 Label，取第一个会永远拿到兜底字符，测不到真正的动作名。
	_check("dash_slot_present", flat.has("闪避"),
		"技能槽文本=%s（必须含 闪避）" % str(flat))
	_check_skill_icon_loaded(bar)


## 技能槽必须真的加载到图标贴图，而不是退回字形占位。
##
## hud.gd 的 `_create_skill_slot` 在贴图缺失时会塞一个字形 Label 兜底
## （HUD 上不能出现"看得见、点得动、却不知道是什么"的空按钮）。
## 但这个兜底是**静默**的：图标文件被误删或改错路径，游戏照样跑，
## 只是图标悄悄变成了一个字母。所以必须由门禁守住。
func _check_skill_icon_loaded(bar: Node) -> void:
	var missing: Array = []
	for c in bar.get_children():
		var tex: TextureRect = _find_texture_rect(c)
		var name_lbl := _find_label_text(c)
		if tex == null or tex.texture == null:
			missing.append(name_lbl)
	_check("skill_icons_loaded", missing.is_empty(),
		"没有加载到贴图的槽位=%s（会退回字形占位）" % str(missing))


func _find_texture_rect(node: Node) -> TextureRect:
	if node is TextureRect:
		return node as TextureRect
	for c in node.get_children():
		var t := _find_texture_rect(c)
		if t != null:
			return t
	return null


func _find_label_text(node: Node) -> String:
	for c in node.get_children():
		if c is Label:
			var t := (c as Label).text
			if not t.is_empty():
				return t
	return "?"


func _collect_label_texts(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out.append_array(_collect_label_texts(c))
	return out


# ── 2. 触摸选卡 ───────────────────────────────────────────

func _check_touch_card_select(hud: Node) -> void:
	GameState.reset_game()
	GameState.level_up()
	var pid: int = 1
	UpgradeDraft.open_draft(pid)
	for i in range(4):
		await get_tree().process_frame
	var row: Node = hud.get_node_or_null("DraftPanel/CardRow")
	if row == null:
		_check("cards_are_buttons", false, "找不到 DraftPanel/CardRow")
		return
	var count: int = row.get_child_count()
	var all_buttons: bool = count > 0
	for c in row.get_children():
		if not (c is Button):
			all_buttons = false
	_check("cards_are_buttons", all_buttons and count == 3,
		"卡片数=%d 全是可点 Button=%s" % [count, str(all_buttons)])
	if not all_buttons or count < 3:
		GameState.reset_game()
		return

	## 从视口分发第 2 根手指，覆盖无需模拟鼠标的真实触摸输入路径。
	## 必须 deep 拷贝：`get_card_stacks()` 返回的是 GameState 内部的同一个
	## Dictionary 对象（GDScript 的 Dictionary 是引用类型），
	## 直接拿它当"操作前快照"，前后指向同一份数据，比较永远相等。
	var before: Dictionary = GameState.get_card_stacks(pid).duplicate(true)
	var card := row.get_child(2) as Button
	var tap := InputEventScreenTouch.new()
	tap.index = 1
	tap.position = card.get_global_rect().get_center()
	tap.pressed = true
	get_viewport().push_input(tap, true)
	tap = tap.duplicate()
	tap.pressed = false
	get_viewport().push_input(tap, true)
	await get_tree().process_frame
	var after: Dictionary = GameState.get_card_stacks(pid)
	var gained: String = ""
	for k: String in after.keys():
		if int(after[k]) > int(before.get(k, 0)):
			gained = k

	_check("touch_card_selects", not gained.is_empty() and not UpgradeDraft.has_draft(pid),
		"点第 3 张后拿到卡=%s 抽卡已结束=%s" % [gained, str(not UpgradeDraft.has_draft(pid))])
	GameState.reset_game()


# ── 3. 闪避按钮 ───────────────────────────────────────────

func _check_dash_button(hud: Node) -> void:
	var player: Node = null
	for n in get_tree().get_nodes_in_group("player"):
		player = n
		break
	_check("player_found", player != null and player.has_method("can_dash"),
		"本地玩家节点=%s" % str(player))
	if player == null:
		return
	var router: Node = player.get_node_or_null("ActionRouter")
	if router != null:
		router.consume_actions()
	var can_before: bool = player.can_dash()
	var button: Button = hud.get_node("SkillBar").get_child(2)
	var tap := InputEventScreenTouch.new()
	tap.position = button.get_global_rect().get_center()
	tap.pressed = true
	get_viewport().push_input(tap, true)
	# 玩家在物理帧消费按键。无窗口时多个渲染帧可能落在同一个物理帧内。
	await get_tree().physics_frame
	await get_tree().physics_frame
	tap = tap.duplicate()
	tap.pressed = false
	get_viewport().push_input(tap, true)
	var can_after: bool = player.can_dash()
	_check("dash_button_triggers", can_before and not can_after,
		"触发前可闪=%s 触发后=%s（false = 确实闪出去了）" % [str(can_before), str(can_after)])


# ── 4. 相机 / 视口自适应 ──────────────────────────────────

func _check_camera_centered(main: Node) -> void:
	var cam: Camera2D = main.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		_check("camera_centered", false, "找不到 Camera2D")
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_check("camera_centered",
		absf(cam.position.x - vs.x * 0.5) < 1.0 and absf(cam.position.y - vs.y * 0.5) < 1.0,
		"相机=(%.1f, %.1f) 视口中心=(%.1f, %.1f)" % [
			cam.position.x, cam.position.y, vs.x * 0.5, vs.y * 0.5])
	## 出怪中心必须跟着视口走，不能再写死 640
	var center_x: float = main.call("_screen_center_x")
	_check("spawn_center_follows_viewport", absf(center_x - vs.x * 0.5) < 0.01,
		"_screen_center_x()=%.1f 视口宽=%.1f" % [center_x, vs.x])


func _check_joystick(main: Node) -> void:
	var stick = main.get_node_or_null("MobileControls")
	var player: Node = main._player
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		_check("desktop_no_joystick", stick == null, "desktop")
		# 在桌面模拟手机入场次序，使用生产摇杆、玩家绑定和视口事件分发。
		main._spawn_mobile_controls()
		stick = main.get_node("MobileControls")
		player = preload("res://scenes/entities/player.tscn").instantiate()
		main.add_child(player)
		player.position = Vector2(320, 360)
	if stick == null:
		_check("joystick_present", false, "missing MobileControls")
		return
	var motion = player.get_node("MotionController")
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.position = Vector2(160, get_viewport().get_visible_rect().end.y - 164)
	touch.pressed = true
	var start_x: float = player.position.x
	get_viewport().push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = touch.index
	drag.position = touch.position + Vector2.RIGHT * 84
	get_viewport().push_input(drag, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("touch_drives_own_ship", motion.mobile_mode and motion.touch_move.x > 0.65
		and player.position.x > start_x,
		"move=%s radius=%s" % [motion.touch_move, stick.joystick_radius])
	touch = touch.duplicate()
	touch.pressed = false
	get_viewport().push_input(touch, true)
	_check("touch_release_stops_stick", motion.touch_move == Vector2.ZERO, str(motion.touch_move))


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("%s VERDICT %s pass=%s | %s" % [TAG, name, str(ok).to_lower(), detail])


func _report() -> void:
	print("%s VERDICT SUMMARY pass=%d failed=%d total=%d" % [
		TAG, _passed, _failed, _passed + _failed])
	get_tree().quit(1 if _failed > 0 else 0)
