extends Node2D

var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")

var _player: Node2D = null
var _hud: Node = null
var _enemy_spawn_timer: float = 0.0
var _difficulty_timer: float = 0.0
var _stars: Array[Node2D] = []

@onready var _bg_color: ColorRect = $BgColor

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_starfield()
	_spawn_player()
	_spawn_hud()
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)

func _create_starfield() -> void:
	## 全屏底色
	if _bg_color:
		_bg_color.color = Color(0.01, 0.01, 0.03, 1.0)
		_bg_color.size = Vector2(1280, 720)
		_bg_color.position = Vector2(0, 0)
	## 生成星星节点
	for i in range(300):
		var star := Sprite2D.new()
		var brightness: float = randf_range(0.3, 1.0)
		var pix_size: int = 1 if randf() < 0.7 else 2
		var img := Image.create(pix_size, pix_size, false, Image.FORMAT_RGBA8)
		img.fill(Color(brightness, brightness, brightness * 1.2, randf_range(0.4, 1.0)))
		var tex := ImageTexture.create_from_image(img)
		star.texture = tex
		star.position = Vector2(randf_range(0, 1280), randf_range(0, 720))
		star.z_index = -10
		add_child(star)
		_stars.append(star)
	## 生成星云
	for i in range(8):
		var nebula := Sprite2D.new()
		var neb_size: int = randi_range(40, 100)
		var neb_img := Image.create(neb_size, neb_size, false, Image.FORMAT_RGBA8)
		var nc_r: float = randf_range(0.1, 0.3)
		var nc_g: float = randf_range(0.05, 0.15)
		var nc_b: float = randf_range(0.2, 0.4)
		for y in range(neb_size):
			for x in range(neb_size):
				var dx: float = float(x - neb_size / 2) / (neb_size / 2.0)
				var dy: float = float(y - neb_size / 2) / (neb_size / 2.0)
				var d: float = sqrt(dx * dx + dy * dy)
				if d < 1.0:
					var a: float = (1.0 - d) * 0.03
					neb_img.set_pixel(x, y, Color(nc_r, nc_g, nc_b, a))
		var neb_tex := ImageTexture.create_from_image(neb_img)
		nebula.texture = neb_tex
		nebula.position = Vector2(randf_range(0, 1280), randf_range(0, 720))
		nebula.z_index = -5
		add_child(nebula)
		_stars.append(nebula)

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
		star.position.y += delta * 8.0
		if star.position.y > 740:
			star.position.y = -20.0
			star.position.x = randf_range(0, 1280)

	## 敌人生成 — 加快速率
	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0:
		_spawn_enemy()
		_enemy_spawn_timer = max(1.2 - GameState.level * 0.06, 0.2)

	## 难度递增
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

func _on_player_died() -> void:
	GameState.game_running = false

func _on_level_up(_new_level: int) -> void:
	if _player and _player.has_method("on_level_up"):
		_player.on_level_up()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and not GameState.game_running:
		_restart()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventKey and event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _restart() -> void:
	get_tree().reload_current_scene()
