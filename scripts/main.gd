extends Node2D

var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _boss_scene = preload("res://scenes/entities/boss.tscn")
var _asteroid_scene = preload("res://scenes/entities/asteroid.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")

var _player: Node2D = null
var _hud: Node = null
var _boss: Node2D = null
var _enemy_spawn_timer: float = 0.0
var _difficulty_timer: float = 0.0
var _asteroid_timer: float = 0.0
var _bg_layers: Array[Dictionary] = []
var _nebulas: Array[Node2D] = []
var _planets: Array[Node2D] = []

@onready var _bg_color: ColorRect = $BgColor

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_parallax_background()
	_spawn_player()
	_spawn_hud()
	_start_bgm()
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)
	GameState.boss_spawn_requested.connect(_on_boss_spawn_requested)

func _create_parallax_background() -> void:
	if _bg_color:
		_bg_color.color = Color(0.06, 0.06, 0.12, 1.0)
		_bg_color.z_index = -100

	var far_layer := {nodes = [], speed = 5.0}
	for i in range(350):
		var star := Sprite2D.new()
		var b: float = randf_range(0.3, 0.7)
		var blue_tint: float = randf_range(0.8, 1.3)
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(b, b * 0.85, b * blue_tint, randf_range(0.3, 0.8)))
		star.texture = ImageTexture.create_from_image(img)
		star.position = Vector2(randf_range(0, 1500), randf_range(-100, 820))
		star.z_index = -10
		add_child(star)
		far_layer.nodes.append(star)
	_bg_layers.append(far_layer)

	var mid_layer := {nodes = [], speed = 10.0}
	for i in range(180):
		var star := Sprite2D.new()
		var b: float = randf_range(0.5, 0.9)
		var blue_tint: float = randf_range(0.85, 1.2)
		var size: int = randi_range(3, 5)
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in range(size):
			for x in range(size):
				var d: float = sqrt(float(x - size / 2) * float(x - size / 2) + float(y - size / 2) * float(y - size / 2))
				if d < float(size) / 2.0:
					img.set_pixel(x, y, Color(b, b * 0.9, b * blue_tint, 1.0))
		star.texture = ImageTexture.create_from_image(img)
		star.position = Vector2(randf_range(0, 1500), randf_range(-100, 820))
		star.z_index = -9
		add_child(star)
		mid_layer.nodes.append(star)
	_bg_layers.append(mid_layer)

	var near_layer := {nodes = [], speed = 16.0}
	for i in range(70):
		var star := Sprite2D.new()
		var b: float = randf_range(0.7, 1.0)
		var size: int = randi_range(6, 12)
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var col: Color
		match randi() % 5:
			0: col = Color(b, b * 0.9, b, 1.0)
			1: col = Color(b, b * 0.7, b * 0.6, 1.0)
			2: col = Color(b * 0.5, b * 0.8, b, 1.0)
			3: col = Color(b, b * 0.85, b * 0.7, 1.0)
			_: col = Color(b * 0.7, b * 0.8, b, 1.0)
		var cx2: int = size / 2
		for y in range(size):
			for x in range(size):
				var d: float = sqrt(float(x - cx2) * float(x - cx2) + float(y - cx2) * float(y - cx2))
				if d < float(size) / 2.0:
					var t: float = d / (float(size) / 2.0)
					img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0 - t * t))
		star.texture = ImageTexture.create_from_image(img)
		star.position = Vector2(randf_range(0, 1500), randf_range(-100, 820))
		star.z_index = -8
		add_child(star)
		near_layer.nodes.append(star)
	_bg_layers.append(near_layer)

	for i in range(8):
		var nebula := Sprite2D.new()
		var w: int = randi_range(200, 400)
		var h: int = randi_range(120, 280)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var cx: float = w / 2.0
		var cy: float = h / 2.0
		var nc_r: float = randf_range(0.06, 0.25)
		var nc_g: float = randf_range(0.03, 0.15)
		var nc_b: float = randf_range(0.3, 0.7)
		var nc_a: float = randf_range(0.08, 0.18)
		var blob_count: int = randi_range(3, 6)
		for j in range(blob_count):
			var bx: float = randf_range(w * 0.1, w * 0.9)
			var by: float = randf_range(h * 0.1, h * 0.9)
			var rx: float = randf_range(w * 0.1, w * 0.35)
			var ry: float = randf_range(h * 0.1, h * 0.35)
			var rot: float = randf_range(0.0, PI)
			var intensity: float = randf_range(0.5, 1.0)
			for y in range(h):
				for x in range(w):
					var ldx: float = float(x) - bx
					var ldy: float = float(y) - by
					var cos_r: float = cos(-rot)
					var sin_r: float = sin(-rot)
					var local_x: float = ldx * cos_r - ldy * sin_r
					var local_y: float = ldx * sin_r + ldy * cos_r
					var d: float = sqrt(local_x * local_x / (rx * rx) + local_y * local_y / (ry * ry))
					if d < 1.0:
						var a: float = nc_a * (1.0 - d * d) * intensity
						var existing := img.get_pixel(x, y)
						var new_r: float = min(existing.r + nc_r * a, nc_r)
						var new_g: float = min(existing.g + nc_g * a, nc_g)
						var new_b: float = min(existing.b + nc_b * a, nc_b)
						var new_a: float = min(existing.a + a, nc_a)
						img.set_pixel(x, y, Color(new_r, new_g, new_b, new_a))
		nebula.texture = ImageTexture.create_from_image(img)
		nebula.position = Vector2(randf_range(-200, 1500), randf_range(-200, 900))
		nebula.z_index = -6 + randi() % 3
		add_child(nebula)
		_nebulas.append(nebula)

	for i in range(3):
		var planet := Sprite2D.new()
		var p_size: int = randi_range(50, 90)
		var img := Image.create(p_size, p_size, false, Image.FORMAT_RGBA8)
		var pc_r: float = randf_range(0.15, 0.4)
		var pc_g: float = randf_range(0.08, 0.25)
		var pc_b: float = randf_range(0.35, 0.65)
		for y in range(p_size):
			for x in range(p_size):
				var dx: float = float(x - p_size / 2)
				var dy: float = float(y - p_size / 2)
				var d: float = sqrt(dx * dx + dy * dy)
				var mr: float = float(p_size) / 2.0
				if d < mr:
					var t: float = d / mr
					var rr: float = pc_r * (1.0 - t * 0.4)
					var gg: float = pc_g * (1.0 - t * 0.4)
					var bb: float = pc_b * (1.0 - t * 0.4)
					var a: float = 1.0 if t < 0.8 else (1.0 - t) * 5.0
					img.set_pixel(x, y, Color(rr, gg, bb, a))
		if randf() < 0.5:
			var ring_r: float = float(p_size) / 2.0 * 1.4
			for y in range(p_size):
				for x in range(p_size):
					var d2: float = sqrt(float(x - p_size / 2) * float(x - p_size / 2) + float(y - p_size / 2) * float(y - p_size / 2))
					if d2 > ring_r - 2.0 and d2 < ring_r + 2.0:
						var ring_a: float = 0.4 * (1.0 - abs(d2 - ring_r) / 2.0)
						img.set_pixel(x, y, Color(pc_r * 1.2, pc_g * 1.2, pc_b * 1.2, ring_a))
		planet.texture = ImageTexture.create_from_image(img)
		planet.position = Vector2(randf_range(100, 1180), randf_range(100, 620))
		planet.z_index = -4
		add_child(planet)
		_planets.append(planet)

func _start_bgm() -> void:
	BGM.play_bgm()

func _spawn_player() -> void:
	_player = _player_scene.instantiate()
	_player.position = Vector2(640, 500)
	add_child(_player)
	_player.died.connect(_on_player_died)

func _spawn_hud() -> void:
	_hud = _hud_scene.instantiate()
	add_child(_hud)

func _process(delta: float) -> void:
	if not GameState.game_running:
		return

	_scroll_background(delta)

	if _boss != null and is_instance_valid(_boss):
		return

	_asteroid_timer -= delta
	if _asteroid_timer <= 0:
		_spawn_asteroid()
		_asteroid_timer = randf_range(2.0, 5.0)

	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0:
		_spawn_enemy()
		_enemy_spawn_timer = max(1.2 - GameState.level * 0.06, 0.2)

	_difficulty_timer += delta
	if _difficulty_timer > 8.0:
		_difficulty_timer = 0.0
		_spawn_enemy()

func _scroll_background(delta: float) -> void:
	for layer in _bg_layers:
		var spd: float = layer.speed
		for node in layer.nodes:
			node.position.y += delta * spd
			if node.position.y > 800:
				node.position.y = -60
				node.position.x = randf_range(0, 1280)

	for neb in _nebulas:
		neb.position.y += delta * 2.5
		neb.position.x += delta * 0.8
		if neb.position.y > 900:
			neb.position.y = -200
			neb.position.x = randf_range(-200, 1500)

	for pl in _planets:
		pl.position.y += delta * 1.2
		pl.position.x += delta * 0.3
		if pl.position.y > 760:
			pl.position.y = -100
			pl.position.x = randf_range(100, 1180)

func _spawn_enemy() -> void:
	var enemy = _enemy_scene.instantiate()
	var side := randi() % 4
	var pos := Vector2.ZERO
	var screen := get_viewport_rect().size
	match side:
		0: pos = Vector2(randf_range(0, screen.x), -30)
		1: pos = Vector2(randf_range(0, screen.x), screen.y + 30)
		2: pos = Vector2(-30, randf_range(0, screen.y))
		3: pos = Vector2(screen.x + 30, randf_range(0, screen.y))
	enemy.position = pos
	var enemy_type: int = randi() % 3
	enemy.enemy_type = enemy_type
	var mult: float = GameState.post_boss_multiplier
	enemy.health = int((1 + GameState.level / 2 + enemy_type) * mult)
	enemy.move_speed = (40.0 + GameState.level * 6.0 + enemy_type * 10.0) * mult
	enemy.shoot_cooldown = max((2.0 - GameState.level * 0.12) / mult, 0.4)
	enemy.drop_chance = 0.20 + enemy_type * 0.12
	if _player and is_instance_valid(_player):
		enemy.set_target(_player)
	enemy.enemy_died.connect(_on_enemy_died)
	add_child(enemy)

func _on_enemy_died() -> void:
	pass

func _spawn_asteroid() -> void:
	var asteroid = _asteroid_scene.instantiate()
	var side := randi() % 4
	var screen := get_viewport_rect().size
	match side:
		0: asteroid.position = Vector2(randf_range(60, screen.x - 60), -40)
		1: asteroid.position = Vector2(randf_range(60, screen.x - 60), screen.y + 40)
		2: asteroid.position = Vector2(-40, randf_range(60, screen.y - 60))
		3: asteroid.position = Vector2(screen.x + 40, randf_range(60, screen.y - 60))
	add_child(asteroid)

func _on_boss_spawn_requested() -> void:
	if _boss != null and is_instance_valid(_boss):
		return
	_spawn_boss()

func _spawn_boss() -> void:
	_show_boss_warning()
	GameState.boss_encounter_count += 1
	_boss = _boss_scene.instantiate()
	_boss.position = Vector2(640, -60)
	var boss_mult: float = 1.0 + (GameState.boss_encounter_count - 1) * 0.1
	_boss.set_difficulty(boss_mult)
	if _player and is_instance_valid(_player):
		_boss.set_target(_player)
	_boss.boss_died.connect(_on_boss_died)
	add_child(_boss)
	var tween := create_tween()
	tween.tween_property(_boss, "position", Vector2(640, 120), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_boss_died() -> void:
	_boss = null
	GameState.post_boss_multiplier = 1.0 + GameState.boss_encounter_count * 0.05

func _show_boss_warning() -> void:
	var warning := Label.new()
	warning.text = "警告: BOSS 来袭"
	warning.add_theme_font_size_override("font_size", 32)
	warning.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, 1.0))
	warning.horizontal_alignment = 1
	warning.vertical_alignment = 1
	warning.position = Vector2(340, 300)
	warning.z_index = 100
	add_child(warning)
	var tween := create_tween()
	tween.tween_property(warning, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.0)
	tween.tween_property(warning, "modulate:a", 0.0, 0.5)
	tween.tween_callback(warning.queue_free)

func _on_player_died() -> void:
	GameState.game_running = false

func _on_level_up(_new_level: int) -> void:
	if _player and _player.has_method("on_level_up"):
		_player.on_level_up()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and not GameState.game_running:
		_restart()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventKey and event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _restart() -> void:
	get_tree().reload_current_scene()
