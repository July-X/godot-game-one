extends Area2D
## 子弹 — 支持对象池复用

var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")

var _direction: Vector2 = Vector2.ZERO
var _speed: float = 600.0
var _damage: float = 1.0
var _is_player_bullet: bool = true
var _lifetime: float = 4.0
var _has_bounced: bool = false
var _level: int = 1
var _pooled: bool = false

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	if not is_connected("body_entered", _on_body_entered):
		body_entered.connect(_on_body_entered)
	if not is_connected("area_entered", _on_area_entered):
		area_entered.connect(_on_area_entered)

## 从对象池取出后调用此方法替代第二次 _ready
func reset() -> void:
	_direction = Vector2.ZERO
	_speed = 600.0
	_damage = 1.0
	_has_bounced = false
	_level = 1
	_lifetime = 4.0
	_sprite.modulate = Color(1, 1, 1, 1)

func setup(pos: Vector2, angle: float, damage: float, is_player: bool, level: int = 1, speed: float = 600.0) -> void:
	global_position = pos
	_direction = Vector2.from_angle(angle)
	rotation = angle + PI * 0.5
	_damage = damage
	_is_player_bullet = is_player
	_has_bounced = false
	_level = level
	_speed = speed
	if is_player:
		add_to_group("player_bullets")
	_apply_bullet_appearance()

func _exit_tree() -> void:
	if _is_player_bullet:
		remove_from_group("player_bullets")

func _apply_bullet_appearance() -> void:
	if _is_player_bullet:
		_sprite.texture = SpriteFactory.create_bullet_sprite(true, _level)
		var scale_val: float = (1.0 + min(_damage * 0.15, 1.5)) * 0.667
		_sprite.scale = Vector2(scale_val, scale_val)
	else:
		_sprite.texture = SpriteFactory.create_bullet_sprite(false, 1)
		_sprite.scale = Vector2(0.67, 0.67)

func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_lifetime -= delta

	## 屏幕外裁剪：超出屏幕一定距离后回收
	var screen := get_viewport_rect().size
	var margin: float = 60.0

	if _is_player_bullet:
		if not _has_bounced:
			var b_margin: float = 10.0
			var bounced: bool = false
			if global_position.x < b_margin:
				global_position.x = b_margin; _direction.x = abs(_direction.x); bounced = true
			elif global_position.x > screen.x - b_margin:
				global_position.x = screen.x - b_margin; _direction.x = -abs(_direction.x); bounced = true
			if global_position.y < b_margin:
				global_position.y = b_margin; _direction.y = abs(_direction.y); bounced = true
			elif global_position.y > screen.y - b_margin:
				global_position.y = screen.y - b_margin; _direction.y = -abs(_direction.y); bounced = true
			if bounced:
				_has_bounced = true; _speed *= 1.3
				_direction = _direction.normalized()
				rotation = _direction.angle() + PI * 0.5
				_sprite.modulate = Color(1.0, 0.5, 0.2, 1.0)

	if global_position.x < -margin or global_position.x > screen.x + margin \
		or global_position.y < -margin or global_position.y > screen.y + margin:
		_recycle()
		return

	if _lifetime <= 0:
		_recycle()

func _recycle() -> void:
	Pool.release(self)

func _on_body_entered(body: Node2D) -> void:
	if not GameState.game_running:
		return
	if _is_player_bullet:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(_damage)
			_spawn_hit()
			_recycle()
	else:
		if body.is_in_group("player") and body.has_method("take_damage"):
			var source: String = "弹幕子弹"
			if _damage >= 0.45:
				source = "狙击子弹"
			elif _damage >= 0.25:
				source = "散弹子弹"
			GameState.death_message = "被 " + source + " 击落"
			body.take_damage(_damage)
			_spawn_hit()
			_recycle()

func _on_area_entered(area: Area2D) -> void:
	if not GameState.game_running:
		return
	if _is_player_bullet:
		if area.is_in_group("enemy_hitbox") and area.get_parent().has_method("take_damage"):
			area.get_parent().take_damage(_damage)
			_spawn_hit()
			_recycle()

func _spawn_hit() -> void:
	var hit = Pool.acquire("hit_effect", _hit_effect_scene)
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position
	hit.start()
