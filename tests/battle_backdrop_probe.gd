extends Node
## 出生、抽卡与受击的轨迹可在同种子下逐行比较。
const MAIN = preload("res://scenes/main.tscn")
const BULLET = preload("res://scenes/entities/bullet.tscn")
const RUN_SEED := 1121
var _failed := 0
var _checks := 0
var _start := 0
var _game

func _ready() -> void:
	process_priority = 100
	call_deferred("_run")

func _process(_delta: float) -> void:
	# 轨迹按固定物理帧比较。受击仍扣血，墙钟驱动的定格在夹具中收口。
	if is_instance_valid(_game):
		_game._hitstop_left = 0.0
		Engine.time_scale = 1.0

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1600, 720)
	var game = MAIN.instantiate()
	_game = game
	var backdrop = game.get_node("Backdrop")

	seed(RUN_SEED)
	var next_random := randi()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	# GameState 的开局和其他场景初始化和测试隔离，只包住背景的 _ready、换图和滚动。
	var extra = MAIN.instantiate()
	var spare = extra.get_node("Backdrop")
	extra.remove_child(spare)
	extra.free()
	seed(RUN_SEED)
	add_child(spare)
	spare.set_boss_mode(true)
	spare.scroll(1000.0)
	spare.set_boss_mode(false)
	_check("background_does_not_draw_game_randomness", randi() == next_random)
	spare.free()

	var view := get_viewport().get_visible_rect()
	var panorama: TextureRect = backdrop.get_node("Panorama")
	var cruise := panorama.texture
	backdrop.set_boss_mode(true)
	var rift := panorama.texture
	_check("both_stage_textures_cover_canvas", cruise != rift and panorama.get_global_rect().encloses(view))
	_check("rift_center_is_dark", rift.get_image().get_pixel(400, 225).get_luminance() < 0.08)
	backdrop.set_boss_mode(false)
	backdrop.scroll(59.0)
	var far: Sprite2D = backdrop._far_stars
	var near: Sprite2D = backdrop._near_stars
	_check("two_parallax_layers_wrap_without_gaps", backdrop.get_child_count() == 4
		and far.position != near.position and _covers(far, view) and _covers(near, view))

	if OS.get_cmdline_user_args().has("hidden"):
		backdrop.hide()
	seed(RUN_SEED)
	game._wave_director._rng.seed = RUN_SEED
	UpgradeDraft._rng.seed = RUN_SEED
	_start = Engine.get_physics_frames()
	game._player._combat._shoot_timer = 120.0
	get_tree().node_added.connect(_on_birth)
	UpgradeDraft.draft_opened.connect(func(_peer, cards): print("[TRACE] draft ", cards))
	UpgradeDraft.card_chosen.connect(func(_peer, card, _index): print("[TRACE] choice ", card))
	UpgradeDraft.open_draft(1)
	UpgradeDraft.choose_card(1, 1)
	await get_tree().physics_frame
	var start_hp := GameState.get_current_health()
	var bullet = Pool.acquire("bullet", BULLET)
	game.add_child(bullet)
	bullet.setup(game._player.global_position - Vector2(0, 30), PI / 2.0, 1, false, 1, 480.0)
	while Engine.get_physics_frames() - _start < 540:
		await get_tree().physics_frame
	var hp := GameState.get_current_health()
	print("[TRACE] result hp=%d/%d kills=%d cards=%s" % [hp, start_hp, GameState.total_kills, GameState.get_card_stacks(1)])
	_check("play_path_had_collision", hp < start_hp)
	print("[BACKDROP] SUMMARY pass=%d failed=%d" % [_checks - _failed, _failed])
	get_tree().quit(int(_failed > 0))

func _covers(tile: Sprite2D, view: Rect2) -> bool:
	return Rect2(tile.position + tile.offset, tile.region_rect.size).encloses(view)

func _on_birth(node: Node) -> void:
	if node.scene_file_path in ["res://scenes/entities/enemy.tscn", "res://scenes/entities/asteroid.tscn"]:
		print("[TRACE] birth %d %s %s" % [Engine.get_physics_frames() - _start, node.scene_file_path, node.position])

func _check(name: String, ok: bool) -> void:
	print("[BACKDROP] %s pass=%s" % [name, ok])
	_checks += 1
	_failed += int(not ok)
