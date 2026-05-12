extends Node
## 表现控制器
##
## 处理行走动画、引擎辉光、无敌闪烁、受击光效。

@onready var _player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _sprite: Sprite2D = _player.get_node("Sprite2D") as Sprite2D if _player.has_node("Sprite2D") else null
@onready var _engine_glow: Sprite2D = _player.get_node("EngineGlow") as Sprite2D if _player.has_node("EngineGlow") else null

var _walk_cycle: float = 0.0
var _invincible_timer: float = 0.0
var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")


func update(delta: float) -> void:
	_invincible_timer = max(_invincible_timer - delta, 0.0)
	_update_walk_animation(delta)
	_update_invincible_flash()
	_update_engine_breathing(delta)


func update_walk_animation(delta: float) -> void:
	_walk_cycle += delta * 8.0


func reset_pose() -> void:
	if _sprite:
		_sprite.rotation = 0.0
	if _engine_glow:
		_engine_glow.position.y = 32.0


var _breath_timer: float = 0.0

func _update_engine_breathing(delta: float) -> void:
	if not _engine_glow or not _engine_glow.visible:
		return
	_breath_timer += delta * 2.5
	var breath: float = 0.85 + sin(_breath_timer) * 0.15
	_engine_glow.modulate.a = breath
	_engine_glow.scale.x = breath

func _update_walk_animation(delta: float) -> void:
	if _player.velocity.length() > 10.0:
		_walk_cycle += delta * 8.0
		var swing: float = sin(_walk_cycle) * 0.02
		var bounce: float = abs(sin(_walk_cycle)) * 0.01
		if _sprite:
			_sprite.rotation = swing
		if _engine_glow:
			_engine_glow.position.y = 32.0 + bounce * 20.0
	else:
		reset_pose()


func _update_invincible_flash() -> void:
	if not _sprite:
		return
	if _invincible_timer > 0:
		_sprite.modulate.a = 0.3 + abs(sin(_invincible_timer * 20)) * 0.7
	else:
		_sprite.modulate.a = 1.0


## ── 外观刷新 ────────────────────────────────────────

var _base_breath_alpha: float = 0.6

func update_appearance() -> void:
	var visual_tier: int = _get_visual_tier()
	var shoot_level: int = GameState.get_shoot_level(_player.peer_id)
	if _sprite:
		_sprite.texture = SpriteFactory.create_player_sprite(visual_tier)
		_apply_peer_tint()
	if _engine_glow:
		_engine_glow.visible = true
		_engine_glow.position.y = 32.0
		_base_breath_alpha = 0.6 + shoot_level * 0.2
		_engine_glow.modulate = Color(1.0, 0.6, 0.2, _base_breath_alpha)
		_engine_glow.scale = Vector2(1.0, 1.0 + shoot_level * 0.06)
		if _engine_glow.texture == null:
			var tex_path: String = "res://assets/sprites/ui/engine_flame.png"
			if ResourceLoader.exists(tex_path):
				_engine_glow.texture = load(tex_path)

func _apply_peer_tint() -> void:
	if not _sprite:
		return
	if not NetworkManager.is_online():
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	if _player.peer_id == 1:
		## 房主：偏青蓝
		_sprite.modulate = Color(0.75, 0.95, 1.25, 1.0)
	else:
		## 加入者：偏橙红
		_sprite.modulate = Color(1.25, 0.85, 0.65, 1.0)


func _get_visual_tier() -> int:
	var tier := int((GameState.level - 1) / 5) + 1
	tier = clampi(tier, 1, 5)
	if NetworkManager.is_online() and _player.peer_id != 1:
		tier = maxi(tier - 1, 1)
	return tier


## ── 受击表现 ────────────────────────────────────────

func trigger_hit() -> void:
	_invincible_timer = 1.0
	_spawn_hit_effect()
	_play_hit_animation()


func _play_hit_animation() -> void:
	if not _sprite:
		return
	var base_color: Color = _sprite.modulate
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.04)
	tween.tween_property(_sprite, "scale", Vector2(1.2, 1.2), 0.04)
	tween.tween_callback(func():
		var recover := create_tween().set_parallel(true)
		recover.tween_property(_sprite, "modulate", base_color, 0.12)
		recover.tween_property(_sprite, "scale", Vector2(1.0, 1.0), 0.12)
	)


func _spawn_hit_effect() -> void:
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = _player.global_position
	hit.start()


func spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = _player.global_position
	SFX.play_explosion()


func play_level_up_effect() -> void:
	var tween := create_tween()
	tween.set_loops(3)
	if _sprite:
		tween.tween_property(_sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
		tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1.0), 0.1)
		tween.finished.connect(func():
			_apply_peer_tint()
		)
