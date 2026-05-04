extends Area2D

var _type: String = "spread"
var _lifetime: float = 10.0
var _bob_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("powerups")

func setup(type: String) -> void:
	_type = type
	match type:
		"spread":
			_sprite.modulate = Color(0.2, 0.8, 0.3)
		"speed":
			_sprite.modulate = Color(0.2, 0.5, 1.0)
		"power":
			_sprite.modulate = Color(1.0, 0.3, 0.2)
		"heal":
			_sprite.modulate = Color(0.2, 1.0, 0.4)
		"bomb":
			_sprite.modulate = Color(1.0, 0.8, 0.2)

func _physics_process(delta: float) -> void:
	_bob_timer += delta * 3.0
	_sprite.position.y = sin(_bob_timer) * 3.0
	_lifetime -= delta
	if _lifetime <= 0:
		queue_free()
	## 闪烁警告
	if _lifetime < 3.0:
		_sprite.modulate.a = 0.3 + abs(sin(_lifetime * 10)) * 0.7

func collect() -> void:
	GameState.collect_powerup(_type)
	if _type == "bomb":
		_bomb_effect()
	## 拾取特效
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(2, 2), 0.15)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)

func _bomb_effect() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e.has_method("die"):
			e.call_deferred("die")
	SFX.play_explosion()
	call_deferred("_spawn_shake")

func _spawn_shake() -> void:
	var screen_shake = preload("res://scenes/effects/screen_shake.tscn").instantiate()
	get_tree().current_scene.add_child(screen_shake)
