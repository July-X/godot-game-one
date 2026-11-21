extends CanvasLayer
## 本机装饰画布。两层星点尝试的是视差，战场和全局随机源由游戏自己控制。

const CRUISE := preload("res://assets/background/cruise.png")
const RIFT := preload("res://assets/background/rift.png")
const TILE := 512
const FAR_SPEED := Vector2(1.8, 12.0)
const NEAR_SPEED := Vector2(4.2, 28.0)

@onready var _panorama: TextureRect = $Panorama
var _far_stars: Sprite2D
var _near_stars: Sprite2D

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21112026
	_far_stars = _make_star_layer(rng, 27, 1, Color("#5a7495b3"))
	_near_stars = _make_star_layer(rng, 9, 2, Color("#83a5c8b3"))
	set_boss_mode(false)
	_resize_stars()
	get_viewport().size_changed.connect(_resize_stars)

func set_boss_mode(active: bool) -> void:
	_panorama.texture = RIFT if active else CRUISE

func scroll(delta: float) -> void:
	_far_stars.position = (_far_stars.position + FAR_SPEED * delta).posmod(TILE)
	_near_stars.position = (_near_stars.position + NEAR_SPEED * delta).posmod(TILE)

func _resize_stars() -> void:
	var size := get_viewport().get_visible_rect().size + Vector2.ONE * TILE
	_far_stars.region_rect = Rect2(Vector2.ZERO, size)
	_near_stars.region_rect = Rect2(Vector2.ZERO, size)

func _make_star_layer(rng: RandomNumberGenerator, count: int, width: int, tint: Color) -> Sprite2D:
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for i in count:
		var pos := Vector2i(rng.randi_range(1, TILE - width - 1), rng.randi_range(1, TILE - width - 1))
		var ink := tint
		ink.a *= rng.randf_range(0.4, 1.0)
		image.fill_rect(Rect2i(pos, Vector2i(width, width)), ink)
	var star_field := Sprite2D.new()
	star_field.texture = ImageTexture.create_from_image(image)
	star_field.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	star_field.centered = false
	star_field.region_enabled = true
	star_field.offset = -Vector2.ONE * TILE
	add_child(star_field)
	return star_field
