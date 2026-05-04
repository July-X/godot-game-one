extends Node2D

@onready var _sprite: Sprite2D = $Sprite2D
var _frame_timer: float = 0.0
var _frame_index: int = 0
var _frames: Array[ImageTexture] = []

func _ready() -> void:
	
	_frames = SpriteFactory.create_explosion_frames()
	if _frames.size() > 0:
		_sprite.texture = _frames[0]

func _process(delta: float) -> void:
	if _frames.size() == 0:
		return
	_frame_timer += delta
	if _frame_timer > 0.06:
		_frame_timer = 0.0
		_frame_index += 1
		if _frame_index < _frames.size():
			_sprite.texture = _frames[_frame_index]
			_sprite.scale = Vector2(1.0 + _frame_index * 0.15, 1.0 + _frame_index * 0.15)
		else:
			queue_free()
	## 闪烁
	_sprite.modulate.a = 1.0 - float(_frame_index) / _frames.size()
