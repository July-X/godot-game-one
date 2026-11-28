extends Node

const Enemy := preload("res://scripts/battle/enemies/enemy.gd")
const Powerup := preload("res://scripts/battle/powerup.gd")
const Bullet := preload("res://scripts/battle/projectiles/bullet.gd")
const BOMB := preload("res://scenes/entities/powerup.tscn")
const SHOT := preload("res://scenes/entities/bullet.tscn")
const TARGET := Vector2(260, 195)

var _battle
var _calibrations := 0
var _deaths := 0
var _explosions := 0
var _drop_count := 0
var _bomb_pickup_frames: Array[int] = []
var _passed := 0
var _failed := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1280, 720)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("Menu/BtnSingle").pressed.emit()
	await get_tree().scene_changed
	_battle = get_tree().current_scene
	_check("normal_title_entry", _battle.scene_file_path == "res://scenes/main.tscn"
		and GameState.normal_growth_enabled and not NetworkManager.is_online())
	_battle._asteroid_timer = INF
	_battle._wave_director._cooldown = INF
	_battle._player.set_physics_process(false)
	GameState.cannon_calibrated.connect(func(): _calibrations += 1)
	GameState.powerup_collected.connect(func(kind):
		if kind == "bomb":
			_bomb_pickup_frames.append(Engine.get_physics_frames()))
	get_tree().node_added.connect(_observe_birth)

	await _two_queues_and_fourth_kill()
	await _mixed_same_frame("cannon_then_bomb", false)
	await _mixed_same_frame("bomb_then_cannon", true)
	await _reentrant_score_callback()
	await _two_physics_shots()
	await _two_physics_pickups()
	print("[ENEMY_DEATH] SUMMARY pass=%d failed=%d" % [_passed, _failed])
	get_tree().quit(int(_failed > 0))

func _two_queues_and_fourth_kill() -> void:
	for i in 2:
		_hit(_spawn_enemy(false))
		await _settle()
	_explosions = 0
	var enemy := _spawn_enemy()
	var first := _spawn_bomb(Vector2(40, 40))
	var second := _spawn_bomb(Vector2(50, 40))
	first._kill_enemies_sequential()
	_check("first_bomb_kills_third_enemy", GameState.total_kills == 3 and enemy.is_queued_for_deletion(),
		"total=%d queued=%s" % [GameState.total_kills, enemy.is_queued_for_deletion()])
	second._kill_enemies_sequential()
	_check("two_bombs_keep_three_kills", GameState.total_kills == 3 and GameState.score == 30
		and _deaths == 1 and not GameState.main_cannon_calibrated and _calibrations == 0, _totals())
	await _settle()
	_check("two_bombs_one_explosion_one_drop", _explosions == 1 and _drop_count == 1, _totals())
	for bomb in [first, second]:
		bomb.queue_free()
	_hit(_spawn_enemy(false))
	await _settle()
	_check("distinct_fourth_enemy_calibrates_once", GameState.total_kills == 4 and GameState.score == 40
		and GameState.main_cannon_calibrated and _calibrations == 1 and _deaths == 1, _totals())

func _mixed_same_frame(label: String, bomb_first: bool) -> void:
	await _reset_case()
	var enemy := _spawn_enemy()
	var bomb := _spawn_bomb(Vector2(40, 40))
	if bomb_first:
		bomb._kill_enemies_sequential()
		_hit(enemy)
	else:
		_hit(enemy)
		bomb._kill_enemies_sequential()
	bomb.queue_free()
	await _settle()
	_check(label, _one_death(), _totals())

func _reentrant_score_callback() -> void:
	await _reset_case()
	var enemy := _spawn_enemy()
	var reentered := [false]
	var callback := func(_score):
		if not reentered[0]:
			reentered[0] = true
			enemy.die()
	GameState.score_changed.connect(callback)
	enemy.die()
	GameState.score_changed.disconnect(callback)
	await _settle()
	_check("death_claimed_before_score_callback", reentered[0] and _one_death(), _totals())

func _two_physics_shots() -> void:
	await _reset_case()
	_spawn_enemy()
	var hits: Array[int] = []
	for offset: float in [-2.0, 2.0]:
		var bullet := _spawn_shot(TARGET + Vector2(offset, 0))
		bullet.body_entered.connect(func(body):
			if body is Enemy:
				hits.append(Engine.get_physics_frames()))
	await _wait_for_physics()
	_check("two_real_bullet_contacts_same_physics_frame", hits.size() == 2 and hits[0] == hits[1], str(hits))
	_check("two_real_contacts_keep_one_death", _one_death(), _totals())

func _two_physics_pickups() -> void:
	await _reset_case()
	_spawn_enemy()
	for offset: float in [-8.0, 8.0]:
		_spawn_bomb(_battle._player.global_position + Vector2(offset, 0)).set_physics_process(true)
	await _wait_for_physics()
	_check("two_real_bomb_pickups_same_physics_frame", _bomb_pickup_frames.size() == 2
		and _bomb_pickup_frames[0] == _bomb_pickup_frames[1], str(_bomb_pickup_frames))
	_check("two_real_pickups_keep_one_death", _one_death(), _totals())

func _spawn_enemy(observe := true) -> Enemy:
	var enemy := _battle._spawn_enemy_at(0, TARGET, 1, false) as Enemy
	enemy.drop_chance = 1.0 if observe else 0.0
	enemy.set_physics_process(false)
	if observe:
		enemy.enemy_died.connect(func(): _deaths += 1)
	return enemy

func _spawn_bomb(at: Vector2) -> Powerup:
	var bomb := BOMB.instantiate() as Powerup
	bomb.setup("bomb")
	bomb.position = at
	_battle.add_child(bomb)
	bomb.set_physics_process(false)
	return bomb

func _spawn_shot(at: Vector2) -> Bullet:
	var bullet := SHOT.instantiate() as Bullet
	_battle.add_child(bullet)
	bullet.setup(at, 0.0, GameState.get_bullet_damage(1), true, 1, GameState.get_main_cannon_speed(), 1)
	return bullet

func _hit(enemy: Enemy) -> void:
	_spawn_shot(enemy.global_position)._on_body_entered(enemy)

func _observe_birth(node: Node) -> void:
	if node.scene_file_path == "res://scenes/effects/explosion.tscn":
		_explosions += 1
	elif node is Powerup and node.position == Vector2.ZERO:
		# Enemy drops enter the tree before the enemy sets their world position.
		_drop_count += 1

func _reset_case() -> void:
	for group: String in ["powerups", "player_bullets"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			node.queue_free()
	await _settle()
	GameState.reset_game(true)
	_calibrations = 0
	_deaths = 0
	_explosions = 0
	_drop_count = 0
	_bomb_pickup_frames.clear()

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _wait_for_physics() -> void:
	for i in 8:
		await get_tree().physics_frame
	await _settle()

func _one_death() -> bool:
	return (GameState.total_kills == 1 and GameState.score == 10 and _deaths == 1 and _explosions == 1 and _drop_count == 1
		and not GameState.main_cannon_calibrated and _calibrations == 0)

func _totals() -> String:
	return "kills=%d score=%d signals=%d blasts=%d drops=%d calibrations=%d" % [
		GameState.total_kills, GameState.score, _deaths, _explosions, _drop_count, _calibrations]

func _check(label: String, ok: bool, detail := "") -> void:
	_passed += int(ok)
	_failed += int(not ok)
	print("[ENEMY_DEATH] ", label, " pass=", ok, " ", detail)
