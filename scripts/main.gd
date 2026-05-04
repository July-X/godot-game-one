extends Node2D

var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")

var _player: Node2D = null
var _hud: Node = null
var _enemy_spawn_timer: float = 0.0
var _difficulty_timer: float = 0.0
var _bg_scroll: float = 0.0

@onready var _bg: Sprite2D = $Background
@onready var _bg2: Sprite2D = $Background2

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_starfield()
	_spawn_player()
	_spawn_hud()
	GameState.reset_game()
	GameState.level_changed.connect(_on_level_up)

func _create_starfield() -> void:
	## 双层视差星空 — 使用 region_rect 实现平铺
	if _bg:
		var tex := SpriteFactory.create_star_field(512, 512, 200)
		_bg.texture = tex
		_bg.region_enabled = true
		_bg.region_rect = Rect2(0, 0, 1280, 720)
		_bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_bg.position = Vector2(0, 0)
	if _bg2:
		var tex2 := SpriteFactory.create_star_field(512, 512, 100)
		_bg2.texture = tex2
		_bg2.region_enabled = true
		_bg2.region_rect = Rect2(0, 0, 1280, 720)
		_bg2.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_bg2.position = Vector2(0, 0)
		_bg2.modulate = Color(0.6, 0.6, 0.8, 0.5)

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

	## 星空滚动
	_bg_scroll += delta * 30.0
	if _bg:
		_bg.region_rect.position = Vector2(fmod(_bg_scroll * 0.3, 512.0), fmod(_bg_scroll, 512.0))
	if _bg2:
		_bg2.region_rect.position = Vector2(fmod(_bg_scroll * 0.15, 512.0), fmod(_bg_scroll * 0.5, 512.0))

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
	## 不同怪物不同掉落率：type0=20%, type1=30%, type2=45%
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
