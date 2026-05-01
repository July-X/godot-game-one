extends Node3D

@onready var level = $Level
@onready var player = $Player
@onready var hud = $HUD

var _enemy_count: int = 0
var _exit_open: bool = false
var _debug_visible: bool = true

func _ready() -> void:
	GameState.reset_run()
	_bind_player()
	_bind_level()
	_bind_hud()
	_ensure_camera_current()
	_refresh_enemy_count()
	_place_player_at_spawn()
	GameState.set_objective("Neutralize the patrol and reach the relay terminal")
	GameState.set_story_line("Briefing: the outpost is silent, but the corridor is not empty.")
	_update_exit_state()

func _bind_player() -> void:
	player.shoot_requested.connect(_on_player_shoot_requested)
	player.took_damage.connect(_on_player_took_damage)
	player.died.connect(_on_player_died)

func _bind_level() -> void:
	if level.has_signal("player_reached_exit"):
		level.player_reached_exit.connect(_on_player_reached_exit)
	if level.has_signal("player_reached_story_trigger"):
		level.player_reached_story_trigger.connect(_on_player_reached_story_trigger)
	if level.has_method("register_enemy"):
		for enemy in get_tree().get_nodes_in_group("enemies"):
			level.register_enemy(enemy)

func _bind_hud() -> void:
	if hud.has_method("set_health"):
		GameState.health_changed.connect(hud.set_health)
	if hud.has_method("set_objective"):
		GameState.objective_changed.connect(hud.set_objective)
	if hud.has_method("set_story_line"):
		GameState.story_line_changed.connect(hud.set_story_line)
	if hud.has_method("set_run_state"):
		GameState.run_state_changed.connect(hud.set_run_state)
	GameState.health_changed.emit(GameState.current_health, GameState.max_health)
	GameState.objective_changed.emit(GameState.objective_text)
	GameState.story_line_changed.emit(GameState.story_line)
	GameState.run_state_changed.emit(GameState.run_state)
	if hud.has_method("toggle_debug"):
		hud.toggle_debug(_debug_visible)

func _place_player_at_spawn() -> void:
	if level.has_node("PlayerSpawn"):
		player.global_position = level.get_node("PlayerSpawn").global_position

func _ensure_camera_current() -> void:
	if player.has_node("CameraRig/Camera3D"):
		var camera: Camera3D = player.get_node("CameraRig/Camera3D")
		camera.current = true

func _refresh_enemy_count() -> void:
	_enemy_count = get_tree().get_nodes_in_group("enemies").size()
	_update_exit_state()

func _update_exit_state() -> void:
	_exit_open = _enemy_count <= 0
	if level.has_method("set_exit_locked"):
		level.set_exit_locked(not _exit_open)
	if _exit_open:
		GameState.set_objective("Exit through the terminal room")
		GameState.set_story_line("Terminal online. Move now before reinforcements arrive.")
	else:
		GameState.set_objective("Clear the patrol and unlock the exit")
		GameState.set_story_line("Eliminate all hostiles to open the terminal room.")

func _on_player_shoot_requested(origin: Vector3, direction: Vector3) -> void:
	if GameState.run_state != "running":
		return
	var projectile_scene := preload("res://scenes/entities/projectile.tscn")
	var projectile := projectile_scene.instantiate()
	level.add_child(projectile)
	projectile.global_position = origin
	projectile.global_rotation = player.global_rotation
	if projectile.has_method("configure"):
		projectile.configure(direction)

func _on_player_took_damage(current_health: int, max_health: int) -> void:
	GameState.current_health = current_health
	GameState.max_health = max_health
	GameState.health_changed.emit(current_health, max_health)
	if current_health == 0:
		GameState.set_story_line("You were overwhelmed. Restart and push through more cleanly.")
		GameState.set_run_state("failed")

func _on_player_died() -> void:
	GameState.set_story_line("Mission failed.")
	GameState.set_run_state("failed")

func _on_player_reached_exit() -> void:
	if not _exit_open:
		GameState.set_story_line("The exit is still locked. Clear the room first.")
		return
	GameState.set_story_line("Extraction complete. The relay data is secured.")
	GameState.set_run_state("finished")

func _on_player_reached_story_trigger() -> void:
	if GameState.run_state != "running":
		return
	GameState.set_story_line("Signal recovered: hostiles are guarding the final terminal. Push forward.")

func notify_enemy_defeated() -> void:
	_enemy_count = max(_enemy_count - 1, 0)
	_update_exit_state()

func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_F3):
		if not has_meta("debug_toggle_latch"):
			_debug_visible = not _debug_visible
			if hud.has_method("toggle_debug"):
				hud.toggle_debug(_debug_visible)
			set_meta("debug_toggle_latch", true)
	else:
		if has_meta("debug_toggle_latch"):
			remove_meta("debug_toggle_latch")
	if Input.is_key_pressed(KEY_F5):
		get_tree().reload_current_scene()
	if GameState.run_state in ["finished", "failed"] and Input.is_action_just_pressed("ui_accept"):
		get_tree().reload_current_scene()
	_update_debug_overlay()

func _update_debug_overlay() -> void:
	if not _debug_visible:
		return
	if not hud.has_method("set_debug_text"):
		return
	var fps := Engine.get_frames_per_second()
	var player_pos: Vector3 = player.global_position
	var debug_text := "state: %s\nhp: %d/%d\nenemies: %d\npos: (%.2f, %.2f, %.2f)\nfps: %d" % [
		GameState.run_state,
		GameState.current_health,
		GameState.max_health,
		_enemy_count,
		player_pos.x,
		player_pos.y,
		player_pos.z,
		fps
	]
	hud.set_debug_text(debug_text)
