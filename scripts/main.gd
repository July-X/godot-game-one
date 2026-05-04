extends Node2D

var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")

var _player: Node2D = null
var _hud: Node = null
var _enemy_spawn_timer: float = 0.0
var _difficulty_timer: float = 0.0
var _bg_scroll: float = 0.0

@onready var _bg1: Sprite2D = $Starfield1
@onready var _bg2: Sprite2D = $Starfield2

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_starfield()
	_spawn_player()
	_spawn_hud()
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)

func _create_starfield() -> void:
	## 生成 1280x720 的星空纹理，直接铺满全屏
	if _bg1:
		_bg1.texture = SpriteFactory.create_star_field(1280, 720, 500)
		_bg1.position = Vector2(640, 360)
	if _bg2:
		_bg2.texture = SpriteFactory.create_star_field(1280, 720, 200)
		_bg2.position = Vector2(640, 360)
		_bg2.modulate = Color(0.5, 0.5, 0.7, 0.4)

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
	_bg_scroll += delta * 15.0
	if _bg1:
		_bg1.position.y = 360.0 + sin(_bg_scroll * 0.01) * 20.0
	if _bg2:
		_bg2.position.y = 360.0 + cos(_bg_scroll * 0.007) * 15.0

	## 敌人生成
	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0:
		_spawn_enemy()
		_enemy_spawn_timer = max(1.8 - GameState.level * 0.08, 0.3)

	## 难度递增
	_difficulty_timer += delta
	if _difficulty_timer > 12.0:
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
