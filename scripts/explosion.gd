extends Node2D

@onready var _particles: CPUParticles2D = $CPUParticles2D
@onready var _flash: Sprite2D = $Flash

func _ready() -> void:
	_particles.emitting = true
	## 闪光
	_flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): _flash.visible = false)
	## 粒子结束后删除
	await get_tree().create_timer(0.5).timeout
	queue_free()
