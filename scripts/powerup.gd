extends Area2D

var _screen_shake_scene = preload("res://scenes/effects/screen_shake.tscn")

var _type: String = "spread"
var _lifetime: float = 10.0
var _bob_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _glow: Sprite2D = $GlowSprite

func _ready() -> void:
	add_to_group("powerups")

func setup(type: String) -> void:
	_type = type
	call_deferred("_apply_sprite")

func _apply_sprite() -> void:
	_sprite.texture = SpriteFactory.create_powerup_sprite(_type)

var _glow_time: float = 0.0

func _physics_process(delta: float) -> void:
	_bob_timer += delta * 3.0
	_sprite.position.y = sin(_bob_timer) * 4.0
	_sprite.rotation += delta * 1.5

	## 闪光脉冲（用一个统一的时间值，避免多次调 Time.get_ticks_msec）
	_glow_time += delta
	var t: float = _glow_time
	var pulse: float = 0.4 + abs(sin(t * 12.0)) * 0.6
	_sprite.modulate.a = pulse * 0.6 + 0.4

	## 外发光脉动
	if _glow:
		var glow_a: float = 0.2 + abs(sin(t * 8.0)) * 0.35
		_glow.modulate.a = glow_a
		var glow_s: float = 0.9 + abs(sin(t * 6.0)) * 0.2
		_glow.scale = Vector2(glow_s, glow_s)

	_lifetime -= delta
	if _lifetime <= 0:
		queue_free()
	## 闪烁警告
	if _lifetime < 3.0:
		var blink: float = 0.3 + abs(sin(_lifetime * 12)) * 0.7
		_sprite.modulate.a = blink

func collect() -> void:
	GameState.collect_powerup(_type)
	if _type == "bomb":
		_bomb_effect()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(3, 3), 0.2)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.2)
	tween.tween_property(_glow, "scale", Vector2(3, 3), 0.2)
	tween.tween_property(_glow, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)

func _bomb_effect() -> void:
	SFX.play_explosion()
	call_deferred("_spawn_shake")
	call_deferred("_kill_enemies_sequential")

func _spawn_shake() -> void:
	var screen_shake = _screen_shake_scene.instantiate()
	get_tree().current_scene.add_child(screen_shake)

var _kill_queue: Array = []
var _kill_idx: int = 0

func _kill_enemies_sequential() -> void:
	_kill_queue = get_tree().get_nodes_in_group("enemies")
	_kill_idx = 0
	_kill_next()

func _kill_next() -> void:
	while _kill_idx < _kill_queue.size():
		var e: Node2D = _kill_queue[_kill_idx]
		_kill_idx += 1
		if is_instance_valid(e) and e.has_method("die"):
			e.die()
			get_tree().create_timer(0.08).timeout.connect(_kill_next)
			return
	_kill_queue.clear()
