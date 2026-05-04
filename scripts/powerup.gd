extends Area2D

var _type: String = "spread"
var _lifetime: float = 8.0
var _bob_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("powerups")
	connect("body_entered", _on_body_entered)

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
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)
	## 闪烁警告
	if _lifetime < 3.0:
		_sprite.modulate.a = 0.3 + abs(sin(_lifetime * 10)) * 0.7

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		GameState.collect_powerup(_type)
		if _type == "bomb":
			_bomb_effect()
		queue_free()

func _bomb_effect() -> void:
	## 清屏 — 杀死所有敌人
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e.has_method("die"):
			e.die()
	SFX.play_explosion()
	## 屏幕震动
	var screen_shake = preload("res://scenes/effects/screen_shake.tscn").instantiate()
	get_tree().current_scene.add_child(screen_shake)
