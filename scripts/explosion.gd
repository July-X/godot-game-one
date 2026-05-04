extends Node2D

const FRAME_INTERVAL: float = 0.06

static var _cached_frames: Array[ImageTexture] = []

@onready var _sprite: Sprite2D = $Sprite2D

var _frame_timer: float = 0.0
var _frame_index: int = 0

func _ready() -> void:
	if _cached_frames.is_empty():
		_cached_frames = SpriteFactory.create_explosion_frames()
	if not _cached_frames.is_empty():
		_sprite.texture = _cached_frames[0]

func _process(delta: float) -> void:
	if _cached_frames.is_empty():
		queue_free()
		return
	_frame_timer += delta
	if _frame_timer > FRAME_INTERVAL:
		_frame_timer = 0.0
		_frame_index += 1
		if _frame_index < _cached_frames.size():
			_sprite.texture = _cached_frames[_frame_index]
			_sprite.scale = Vector2(1.0 + _frame_index * 0.15, 1.0 + _frame_index * 0.15)
		else:
			queue_free()
	_sprite.modulate.a = 1.0 - float(_frame_index) / _cached_frames.size()
