extends Node3D

@onready var level = $Level
var _current_level: int = 1
var _level_scenes: Dictionary = {}
@onready var player = $Player
@onready var hud = $HUD
@onready var title_screen = $TitleScreen
@onready var briefing_screen = $BriefingScreen
@onready var screen_transition = $ScreenTransition


var _enemy_count: int = 0
var _kill_count: int = 0
var _total_enemies: int = 0
var _exit_open: bool = false
var _debug_visible: bool = true
var _result_shown: bool = false
var _start_time: float = 0.0
var _hp_lost: int = 0
var _story_texts: Dictionary = {}

func _ready() -> void:
	GameState.reset_run()
	_level_scenes = {
		1: preload("res://scenes/levels/level_01.tscn"),
		2: preload("res://scenes/levels/level_02.tscn"),
		3: preload("res://scenes/levels/level_03.tscn"),
		4: preload("res://scenes/levels/level_04.tscn")
	}
	_current_level = 1
	briefing_screen.visible = false
	_show_title()

func _show_title() -> void:
	BGM.play_title_music()
	level.visible = false
	player.visible = false
	player.process_mode = PROCESS_MODE_DISABLED
	hud.visible = false
	title_screen.visible = true
	briefing_screen.visible = false

func _start_briefing() -> void:
	BGM.stop_music()
	screen_transition.fade_out(0.4)
	await screen_transition.transition_finished
	title_screen.visible = false
	briefing_screen.visible = true
	if briefing_screen.has_signal("briefing_finished"):
		briefing_screen.briefing_finished.connect(_start_game, CONNECT_ONE_SHOT)
	screen_transition.fade_in(0.3)
	await screen_transition.transition_finished

func _start_game() -> void:
	## 切换到下一关
	if level != null:
		level.queue_free()
	if _level_scenes.has(_current_level):
		level = _level_scenes[_current_level].instantiate()
		add_child(level)

	BGM.play_game_music()
	screen_transition.fade_out(0.4)
	await screen_transition.transition_finished
	briefing_screen.visible = false
	level.visible = true
	player.visible = true
	player.process_mode = PROCESS_MODE_INHERIT
	hud.visible = true
	_bind_player()
	_bind_level()
	_bind_hud()
	_ensure_camera_current()
	_refresh_enemy_count()
	_place_player_at_spawn()
	_hp_lost = 0
	_start_time = Time.get_ticks_msec() / 1000.0
	var level_name: String = "Neutralize the patrol and reach the relay terminal"
	if _current_level == 2:
		level_name = "Clear the forward base and secure the data core"
	elif _current_level == 3:
		level_name = "Assault the command center and eliminate all hostiles"
	elif _current_level == 4:
		level_name = "Assault the command center and eliminate the Boss"
	GameState.set_objective(level_name)
	GameState.set_story_line("Eliminate all hostiles to open the terminal room.")
	_update_exit_state()
	GameState.set_run_state("running")
	screen_transition.fade_in(0.5)
	await screen_transition.transition_finished

func _bind_player() -> void:
	## 防止信号重复连接（关卡切换时 player 节点保留）
	if player.shoot_requested.is_connected(_on_player_shoot_requested):
		player.shoot_requested.disconnect(_on_player_shoot_requested)
	if player.took_damage.is_connected(_on_player_took_damage):
		player.took_damage.disconnect(_on_player_took_damage)
	if player.died.is_connected(_on_player_died):
		player.died.disconnect(_on_player_died)
	player.shoot_requested.connect(_on_player_shoot_requested)
	player.took_damage.connect(_on_player_took_damage)
	player.died.connect(_on_player_died)

func _bind_level() -> void:
	if level.has_signal("player_reached_exit"):
		level.player_reached_exit.connect(_on_player_reached_exit)
	if level.has_signal("player_reached_story_trigger"):
		level.player_reached_story_trigger.connect(_on_player_reached_story_trigger)
	## 多段剧情文本，按触发器索引映射
	if _current_level == 1:
		_story_texts = {
			1: "Corridor ahead is quiet. Stay alert.",
			2: "Signal is getting stronger. The terminal is close.",
			3: "Warning: heavy resistance near the exit. Prepare for combat."
		}
	elif _current_level == 2:
		_story_texts = {
			1: "Forward base ahead. Multiple hostiles detected.",
			2: "Shooter units spotted. Use cover wisely.",
			3: "The data core is just ahead. Clear the area."
		}
	else:
		_story_texts = {
			1: "Command center ahead. Heavy resistance expected.",
			2: "All enemy types detected. Stay sharp.",
			3: "Final push. Clear the area and extract."
		}
	if _current_level == 4:
		_story_texts = {
			1: "Detecting base core area - The Ultimate Guardian awaits.",
			2: "ALERT! Ultimate Guardian has appeared! Eliminate it to complete the mission!"
		}
	if level.has_method("register_enemy"):
		for enemy in get_tree().get_nodes_in_group("enemies"):
			level.register_enemy(enemy)
	# Boss 关卡特殊绑定
	if _is_boss_level() and level.has_signal("boss_defeated"):
		level.boss_defeated.connect(_on_boss_defeated)

func _bind_hud() -> void:
	## 防止信号重复连接
	if GameState.health_changed.is_connected(hud.set_health):
		GameState.health_changed.disconnect(hud.set_health)
	if GameState.objective_changed.is_connected(hud.set_objective):
		GameState.objective_changed.disconnect(hud.set_objective)
	if GameState.story_line_changed.is_connected(hud.set_story_line):
		GameState.story_line_changed.disconnect(hud.set_story_line)
	if GameState.run_state_changed.is_connected(hud.set_run_state):
		GameState.run_state_changed.disconnect(hud.set_run_state)
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
	_total_enemies = _enemy_count
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

func _is_boss_level() -> bool:
	"""判断是否为 Boss 关卡"""
	return _current_level == 4

func _on_boss_defeated() -> void:
	"""Boss 被击败信号回调"""
	notify_boss_defeated()

func notify_boss_defeated() -> void:
	"""Boss 击败处理：Boss 关卡专属结算"""
	if _result_shown:
		return
	_result_shown = true
	BGM.stop_music()
	GameState.set_run_state("boss_defeated")
	_hide_game_hud()
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _start_time
	SaveSystem.record_run(_kill_count, elapsed, true)
	# 检查成就
	var new_achievements: Array = Achievements.check_achievements(
		_kill_count, _total_enemies, elapsed, true, _hp_lost
	)
	if new_achievements.size() > 0:
		hud.show_achievement_unlocks(new_achievements)
	screen_transition.fade_out(0.5)
	await screen_transition.transition_finished
	hud.show_boss_result_screen("FINAL BOSS DEFEATED", _kill_count, _total_enemies, _get_elapsed_time())

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
	var damage_taken: int = GameState.current_health - current_health
	_hp_lost += damage_taken
	GameState.current_health = current_health
	GameState.max_health = max_health
	GameState.health_changed.emit(current_health, max_health)
	if hud.has_method("show_damage_feed") and damage_taken > 0:
		hud.show_damage_feed("-%d HP" % damage_taken)
	if current_health == 0:
		GameState.set_story_line("You were overwhelmed. Restart and push through more cleanly.")
		_trigger_result()

func _on_player_died() -> void:
	GameState.set_story_line("Mission failed.")
	_trigger_result()

func _get_elapsed_time() -> String:
	var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
	var minutes := int(elapsed) / 60
	var seconds := int(elapsed) % 60
	return "%d:%02d" % [minutes, seconds]

func _trigger_result() -> void:
	if _result_shown:
		return
	_result_shown = true
	BGM.stop_music()
	GameState.set_run_state("failed")
	_hide_game_hud()
	## 记录存档（失败也记录）
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _start_time
	SaveSystem.record_run(_kill_count, elapsed, false)
	## 检查成就
	var _new_achievements: Array = Achievements.check_achievements(_kill_count, _total_enemies, elapsed, false, _hp_lost)
	screen_transition.fade_out(0.3)
	await screen_transition.transition_finished
	hud.show_result_screen(GameState.run_state, GameState.story_line, _kill_count, _total_enemies, _get_elapsed_time())

func _hide_game_hud() -> void:
	hud.get_node("Root/TopBar").visible = false
	hud.get_node("Root/DialogueBox").visible = false

func _on_player_reached_exit() -> void:
	# Boss 关卡无出口，不应触发此方法
	if _is_boss_level():
		return
	if not _exit_open:
		GameState.set_story_line("The exit is still locked. Clear the room first.")
		return
	if _result_shown:
		return
	_result_shown = true
	## 记录存档（成功通关）
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _start_time
	SaveSystem.record_run(_kill_count, elapsed, true)
	## 检查成就
	var new_achievements: Array = Achievements.check_achievements(_kill_count, _total_enemies, elapsed, true, _hp_lost)
	if new_achievements.size() > 0:
		hud.show_achievement_unlocks(new_achievements)

	## 检查是否还有下一关
	if _current_level < _level_scenes.size():
		## 进入下一关
		_current_level += 1
		BGM.stop_music()
		screen_transition.fade_out(0.5)
		await screen_transition.transition_finished
		_result_shown = false
		_kill_count = 0
		_exit_open = false
		_start_game()
		return

	## 全部关卡完成，显示结算
	BGM.play_result_music()
	GameState.set_story_line("Extraction complete. The relay data is secured.")
	GameState.set_run_state("finished")
	_hide_game_hud()
	screen_transition.fade_out(0.3)
	await screen_transition.transition_finished
	hud.show_result_screen(GameState.run_state, GameState.story_line, _kill_count, _total_enemies, _get_elapsed_time())

func _on_player_reached_story_trigger(trigger_index: int = 0) -> void:
	if GameState.run_state != "running":
		return
	var text: String = _story_texts.get(trigger_index, "Push forward.")
	GameState.set_story_line(text)

func notify_enemy_defeated() -> void:
	_enemy_count = max(_enemy_count - 1, 0)
	_kill_count += 1
	_update_exit_state()

func _process(_delta: float) -> void:
	## Esc 键切换鼠标模式和窗口模式
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	## F11 切换全屏
	if Input.is_key_pressed(KEY_F11):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		set_meta("fullscreen_latch", true)
	else:
		if has_meta("fullscreen_latch"):
			remove_meta("fullscreen_latch")
	if GameState.run_state == "title" and Input.is_action_just_pressed("ui_accept"):
		SFX.play_ui_confirm()
		_start_briefing()
		return
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
		_return_to_title()
	_update_debug_overlay()

func _return_to_title() -> void:
	_current_level = 1
	get_tree().reload_current_scene()

func _update_debug_overlay() -> void:
	if not _debug_visible:
		return
	if not hud.has_method("set_debug_text"):
		return
	var fps := Engine.get_frames_per_second()
	var player_pos: Vector3 = player.global_position
	var debug_text := "state: %s\nhp: %d/%d\nenemies: %d\nkills: %d\npos: (%.2f, %.2f, %.2f)\nfps: %d" % [
		GameState.run_state,
		GameState.current_health,
		GameState.max_health,
		_enemy_count,
		_kill_count,
		player_pos.x,
		player_pos.y,
		player_pos.z,
		fps
	]
	hud.set_debug_text(debug_text)
