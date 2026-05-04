extends Node2D

var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")

var _player: Node2D = null
var _hud: Node = null
var _enemy_spawn_timer: float = 0.0
var _difficulty_timer: float = 0.0
var _enemies_alive: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spawn_starfield()
	_spawn_player()
	_spawn_hud()
	GameState.reset_game()

func _spawn_starfield() -> void:
	var starfield := Node2D.new()
	starfield.name = "Starfield"
	add_child(starfield)
	for i in 200:
		var star := Sprite2D.new()
		var grad := Gradient.new()
		var brightness := randf_range(0.3, 1.0)
		grad.colors = [Color(brightness, brightness, brightness, 1.0)]
		grad.offsets = [0.0]
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 2
		tex.height = 2
		star.texture = tex
		star.position = Vector2(randf_range(-100, 1380), randf_range(-100, 820))
		star.scale = Vector2(randf_range(0.3, 1.5), randf_range(0.3, 1.5))
		starfield.add_child(star)

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

	## 敌人生成
	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0:
		_spawn_enemy()
		## 随等级加快生成
		_enemy_spawn_timer = max(2.0 - GameState.level * 0.1, 0.4)

	## 难度递增
	_difficulty_timer += delta
	if _difficulty_timer > 15.0:
		_difficulty_timer = 0.0
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy = _enemy_scene.instantiate()
	## 随机屏幕边缘位置
	var side := randi() % 4
	var pos := Vector2.ZERO
	var screen := get_viewport_rect().size
	match side:
		0: pos = Vector2(randf_range(0, screen.x), -30)
		1: pos = Vector2(randf_range(0, screen.x), screen.y + 30)
		2: pos = Vector2(-30, randf_range(0, screen.y))
		3: pos = Vector2(screen.x + 30, randf_range(0, screen.y))
	enemy.position = pos
	## 随等级增强
	enemy.health = 1 + GameState.level / 3
	enemy.move_speed = 50.0 + GameState.level * 8.0
	enemy.shoot_cooldown = max(2.5 - GameState.level * 0.15, 0.8)
	if _player and is_instance_valid(_player):
		enemy.set_target(_player)
	enemy.enemy_died.connect(_on_enemy_died)
	add_child(enemy)
	_enemies_alive += 1

func _on_enemy_died() -> void:
	_enemies_alive = max(_enemies_alive - 1, 0)

func _on_player_died() -> void:
	GameState.game_running = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and not GameState.game_running:
		_restart()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _restart() -> void:
	get_tree().reload_current_scene()
