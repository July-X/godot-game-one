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
var _stars: Array[Node2D] = []

@onready var _bg_color: ColorRect = $BgColor

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_starfield()
	_spawn_player()
	_spawn_hud()
	_start_bgm()
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)
	GameState.boss_spawn_requested.connect(_on_boss_spawn_requested)

func _create_starfield() -> void:
	if _bg_color:
		_bg_color.color = Color(0.06, 0.08, 0.18, 1.0)
		_bg_color.z_index = -100
	## 大星星（6-12像素，非常亮）
	for i in range(80):
		var star := Sprite2D.new()
		var brightness: float = randf_range(0.8, 1.0)
		var pix_size: int = randi_range(6, 12)
		var img := Image.create(pix_size, pix_size, false, Image.FORMAT_RGBA8)
		var star_type: int = randi() % 5
		var col: Color
		match star_type:
			0: col = Color(brightness, brightness, brightness, 1.0)
			1: col = Color(brightness, brightness * 0.7, brightness * 0.5, 1.0)
			2: col = Color(brightness * 0.6, brightness * 0.8, brightness, 1.0)
			3: col = Color(brightness, brightness * 0.9, brightness * 0.6, 1.0)
			_: col = Color(brightness * 0.8, brightness, brightness * 0.9, 1.0)
		## 画带光晕的星星
		var cx2: int = pix_size / 2
		var cy2: int = pix_size / 2
		for y in range(pix_size):
			for x in range(pix_size):
				var d: float = sqrt(float(x - cx2) * float(x - cx2) + float(y - cy2) * float(y - cy2))
				var max_r: float = float(pix_size) / 2.0
				if d < max_r:
					var t: float = d / max_r
					var a: float = 1.0 - t * t
					img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
		var tex := ImageTexture.create_from_image(img)
		star.texture = tex
		star.position = Vector2(randf_range(0, 1280), randf_range(0, 720))
		star.z_index = -10
		add_child(star)
		_stars.append(star)
	## 中等星星（3-5像素）
	for i in range(200):
		var star := Sprite2D.new()
		var brightness: float = randf_range(0.6, 1.0)
		var pix_size: int = randi_range(3, 5)
		var img := Image.create(pix_size, pix_size, false, Image.FORMAT_RGBA8)
		for y in range(pix_size):
			for x in range(pix_size):
				var d: float = sqrt(float(x - pix_size / 2) * float(x - pix_size / 2) + float(y - pix_size / 2) * float(y - pix_size / 2))
				if d < float(pix_size) / 2.0:
					img.set_pixel(x, y, Color(brightness, brightness, brightness, 1.0))
		var tex := ImageTexture.create_from_image(img)
		star.texture = tex
		star.position = Vector2(randf_range(0, 1280), randf_range(0, 720))
		star.z_index = -9
		add_child(star)
		_stars.append(star)
	## 小星星（1-2像素，密密麻麻）
	for i in range(500):
		var star := Sprite2D.new()
		var brightness: float = randf_range(0.4, 0.9)
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(brightness, brightness, brightness * 1.1, randf_range(0.5, 1.0)))
		var tex := ImageTexture.create_from_image(img)
		star.texture = tex
		star.position = Vector2(randf_range(0, 1280), randf_range(0, 720))
		star.z_index = -8
		add_child(star)
		_stars.append(star)
	## 大型彩色星云（100-250px，高透明度）
	for i in range(15):
		var nebula := Sprite2D.new()
		var neb_size: int = randi_range(100, 250)
		var neb_img := Image.create(neb_size, neb_size, false, Image.FORMAT_RGBA8)
		var nc_r: float = randf_range(0.2, 0.5)
		var nc_g: float = randf_range(0.1, 0.3)
		var nc_b: float = randf_range(0.3, 0.6)
		var nc_a: float = randf_range(0.08, 0.18)
		for y in range(neb_size):
			for x in range(neb_size):
				var dx: float = float(x - neb_size / 2) / (neb_size / 2.0)
				var dy: float = float(y - neb_size / 2) / (neb_size / 2.0)
				var d: float = sqrt(dx * dx + dy * dy)
				if d < 1.0:
					var a: float = nc_a * (1.0 - d * d)
					neb_img.set_pixel(x, y, Color(nc_r, nc_g, nc_b, a))
		var neb_tex := ImageTexture.create_from_image(neb_img)
		nebula.texture = neb_tex
		nebula.position = Vector2(randf_range(-100, 1380), randf_range(-100, 820))
		nebula.z_index = -5
		add_child(nebula)
	## 行星/大球体（40-80px，带环）
	for i in range(4):
		var planet := Sprite2D.new()
		var p_size: int = randi_range(40, 80)
		var p_img := Image.create(p_size, p_size, false, Image.FORMAT_RGBA8)
		var pc_r: float = randf_range(0.25, 0.55)
		var pc_g: float = randf_range(0.15, 0.35)
		var pc_b: float = randf_range(0.35, 0.65)
		var p_cx: int = p_size / 2
		var p_cy: int = p_size / 2
		for y in range(p_size):
			for x in range(p_size):
				var dx: float = float(x - p_cx)
				var dy: float = float(y - p_cy)
				var d: float = sqrt(dx * dx + dy * dy)
				var max_r: float = float(p_size) / 2.0
				if d < max_r:
					var t: float = d / max_r
					## 径向渐变 + 边缘光晕
					var rr: float = pc_r * (1.0 - t * 0.4)
					var gg: float = pc_g * (1.0 - t * 0.4)
					var bb: float = pc_b * (1.0 - t * 0.4)
					var a: float = 1.0 if t < 0.8 else (1.0 - t) * 5.0
					p_img.set_pixel(x, y, Color(rr, gg, bb, a))
		## 行星环
		if randf() < 0.5:
			var ring_r: float = float(p_size) / 2.0 * 1.4
			var ring_w: int = randi_range(2, 4)
			for y in range(p_size):
				for x in range(p_size):
					var d2: float = sqrt(float(x - p_cx) * float(x - p_cx) + float(y - p_cy) * float(y - p_cy))
					if d2 > ring_r - float(ring_w) / 2.0 and d2 < ring_r + float(ring_w) / 2.0:
						var ring_a: float = 0.4 * (1.0 - abs(d2 - ring_r) / (float(ring_w) / 2.0))
						p_img.set_pixel(x, y, Color(pc_r * 1.2, pc_g * 1.2, pc_b * 1.2, ring_a))
		var p_tex := ImageTexture.create_from_image(p_img)
		planet.texture = p_tex
		planet.position = Vector2(randf_range(100, 1180), randf_range(100, 620))
		planet.z_index = -3
		add_child(planet)

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

	## 星空缓慢滚动
	for star in _stars:
		star.position.y += delta * 6.0
		if star.position.y > 760:
			star.position.y = -40.0
			star.position.x = randf_range(0, 1280)

	## Boss 存活时不生成普通敌人
	if _boss != null and is_instance_valid(_boss):
		return

	## 小行星生成
	_asteroid_timer -= delta
	if _asteroid_timer <= 0:
		_spawn_asteroid()
		_asteroid_timer = randf_range(2.0, 5.0)

	## 敌人生成
	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0:
		_spawn_enemy()
		_enemy_spawn_timer = max(1.2 - GameState.level * 0.06, 0.2)

	_difficulty_timer += delta
	if _difficulty_timer > 8.0:
		_difficulty_timer = 0.0
		_spawn_enemy()

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
	enemy.health = 1 + GameState.level / 2 + enemy_type
	enemy.move_speed = 40.0 + GameState.level * 6.0 + enemy_type * 10.0
	enemy.shoot_cooldown = max(2.0 - GameState.level * 0.12, 0.6)
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
	_boss = _boss_scene.instantiate()
	_boss.position = Vector2(640, -60)
	if _player and is_instance_valid(_player):
		_boss.set_target(_player)
	_boss.boss_died.connect(_on_boss_died)
	add_child(_boss)
	var tween := create_tween()
	tween.tween_property(_boss, "position", Vector2(640, 120), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _show_boss_warning() -> void:
	var warning := Label.new()
	warning.text = "WARNING: BOSS INCOMING"
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

func _on_boss_died() -> void:
	_boss = null

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
