extends Node2D

const FRAME_INTERVAL: float = 0.06
const ORDINARY_PATH := "res://assets/sprites/explosion/ordinary_death.png"
static var _ordinary_strip: Texture2D = load(ORDINARY_PATH) if ResourceLoader.exists(ORDINARY_PATH) else null
static var _cached_frames: Array[ImageTexture] = []

@onready var _sprite: Sprite2D = $Sprite2D

var _frame_timer: float = 0.0
var _frame_index: int = 0
var _combat_duration := 0.0
var _debris_radius := 0.0

func setup_ordinary_death() -> void:
	setup_combat(0.15, 0.82, 0.0 if _ordinary_strip else 23.0)
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	if _ordinary_strip:
		var sprite: Sprite2D = $Sprite2D
		sprite.texture = _ordinary_strip
		sprite.hframes = 9

func setup_combat(duration: float, size: float, debris_radius := 0.0) -> void:
	_combat_duration = duration
	_debris_radius = debris_radius
	scale = Vector2.ONE * size
	z_index = -1

func _ready() -> void:
	if _sprite.hframes > 1:
		return
	if _cached_frames.is_empty():
		_cached_frames = SpriteFactory.create_explosion_frames()
	if not _cached_frames.is_empty():
		if _combat_duration > 0.0:
			_frame_index = mini(2, _cached_frames.size() - 1)
		_sprite.texture = _cached_frames[_frame_index]

func _process(delta: float) -> void:
	if _sprite.texture == null:
		queue_free()
		return
	_frame_timer += delta
	if _combat_duration > 0.0:
		var progress := _frame_timer / _combat_duration
		if progress >= 1.0:
			queue_free()
		else:
			# 击毁从已经展开的帧起播，与几根细线的命中火花区分。
			if _sprite.hframes > 1:
				_sprite.frame = mini(int(progress * _sprite.hframes), _sprite.hframes - 1)
			else:
				var frame := _frame_index + int(progress * (_cached_frames.size() - _frame_index))
				_sprite.texture = _cached_frames[frame]
			_sprite.modulate.a = 1.0 - progress * progress
			if _debris_radius > 0.0:
				queue_redraw()
		return
	if _frame_timer > FRAME_INTERVAL:
		_frame_timer = 0.0
		_frame_index += 1
		if _frame_index < _cached_frames.size():
			_sprite.texture = _cached_frames[_frame_index]
			_sprite.scale = Vector2(1.0 + _frame_index * 0.15, 1.0 + _frame_index * 0.15)
		else:
			queue_free()
	_sprite.modulate.a = 1.0 - float(_frame_index) / _cached_frames.size()

func _draw() -> void:
	if _debris_radius <= 0.0:
		return
	# 残片从机体边缘散开，精英掉落物堆在中心时也能读出击毁。
	var t := clampf(_frame_timer / _combat_duration, 0.0, 1.0)
	var color := Color(1.0, 0.66, 0.32, 1.0 - t)
	for i in 6:
		var axis := Vector2.from_angle(0.35 + TAU * i / 6.0)
		var tip := axis * _debris_radius * lerpf(0.65, 1.0, t)
		draw_line((tip - axis * 5).round(), tip.round(), color, 3.0)
