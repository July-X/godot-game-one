extends Panel

signal reward_chosen(reward_type: String)

var _rewards: Array[Dictionary] = []

func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -250.0
	offset_top = -120.0
	offset_right = 250.0
	offset_bottom = 120.0
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup() -> void:
	for child in get_children():
		child.queue_free()
	_rewards = _generate_rewards()
	_build_ui()

func _generate_rewards() -> Array[Dictionary]:
	var pool: Array[Dictionary] = [
		{"type": "laser_cd", "name": "激光加速", "desc": "激光冷却 -1s", "icon": "⚡"},
		{"type": "bullet_count", "name": "弹幕扩展", "desc": "子弹 +1", "icon": "✦"},
		{"type": "damage", "name": "火力增强", "desc": "子弹伤害 +2", "icon": "🔥"},
		{"type": "speed", "name": "机动强化", "desc": "移速 +10%", "icon": "➤"},
		{"type": "shield", "name": "护盾充能", "desc": "护盾 +3 层", "icon": "🛡"},
	]
	pool.shuffle()
	return [pool[0], pool[1]]

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = size
	bg.color = Color(0.06, 0.06, 0.15, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.size = Vector2(size.x, 40)
	title.position = Vector2(0, 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1))
	title.add_theme_font_size_override("font_size", 28)
	title.text = "BOSS 击败！选择奖励"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sep := HSeparator.new()
	sep.size = Vector2(size.x - 40, 2)
	sep.position = Vector2(20, 56)
	sep.modulate = Color(0.4, 0.4, 0.6, 0.6)
	add_child(sep)

	for i in range(_rewards.size()):
		var r: Dictionary = _rewards[i]
		var card := Panel.new()
		var card_w: int = 220
		var gap: int = 20
		var total_w: int = card_w * 2 + gap
		var start_x: int = int((size.x - total_w) * 0.5)
		card.size = Vector2(card_w, 90)
		card.position = Vector2(start_x + i * (card_w + gap), 72)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.25, 0.9)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(0.5, 0.3, 0.8, 1.0)
		card.add_theme_stylebox_override("panel", sb)
		card.mouse_filter = Control.MOUSE_FILTER_STOP

		var icon := Label.new()
		icon.size = Vector2(card_w, 40)
		icon.position = Vector2(0, 6)
		icon.add_theme_font_size_override("font_size", 26)
		icon.text = r.icon + "  " + r.name
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0, 1))
		card.add_child(icon)

		var desc := Label.new()
		desc.size = Vector2(card_w, 30)
		desc.position = Vector2(0, 52)
		desc.add_theme_font_size_override("font_size", 15)
		desc.text = r.desc
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0, 0.9))
		card.add_child(desc)

		var btn := Button.new()
		btn.size = card.size
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var transparent := StyleBoxFlat.new()
		transparent.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", transparent)
		btn.add_theme_stylebox_override("pressed", transparent)
		btn.add_theme_stylebox_override("hover", transparent)
		var reward_type: String = r.type
		btn.pressed.connect(func(): _on_reward_clicked(reward_type))
		card.add_child(btn)

		var hover_border := StyleBoxFlat.new()
		hover_border.bg_color = Color(0.2, 0.15, 0.4, 0.95)
		hover_border.border_width_left = 2
		hover_border.border_width_top = 2
		hover_border.border_width_right = 2
		hover_border.border_width_bottom = 2
		hover_border.border_color = Color(0.7, 0.5, 1.0, 1.0)

		var orig_bg: Color = sb.bg_color
		btn.mouse_entered.connect(func():
			card.add_theme_stylebox_override("panel", hover_border)
		)
		btn.mouse_exited.connect(func():
			card.add_theme_stylebox_override("panel", sb)
		)

		add_child(card)

func _on_reward_clicked(reward_type: String) -> void:
	match reward_type:
		"laser_cd":
			GameState.laser_cd_bonus += 1.0
		"bullet_count":
			GameState.extra_bullet_count += 1
		"damage":
			GameState.extra_damage_bonus += 2
		"speed":
			GameState.move_speed_bonus += 0.10
		"shield":
			GameState.shield_layers = min(GameState.shield_layers + 3, 30)
			GameState.shield_changed.emit(GameState.shield_layers)
	reward_chosen.emit(reward_type)
	queue_free()
