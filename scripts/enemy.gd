extends CharacterBody3D

signal defeated

@export var move_speed: float = 2.2
@export var chase_speed: float = 3.4
@export var gravity: float = 18.0
@export var health: int = 3
@export var patrol_distance: float = 3.0
@export var aggro_range: float = 6.0
@export var touch_damage: int = 1
@export var touch_cooldown: float = 0.6

var _home_x = 0.0
var _direction = 1.0
var _target = null
var _dead = false
var _touch_timer = 0.0

func _ready() -> void:
	add_to_group("enemies")
	_home_x = global_position.x
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]

func _physics_process(delta: float) -> void:
	if GameState.run_state != "running":
		velocity = Vector3.ZERO
		return

	_touch_timer = max(_touch_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	var desired_speed = move_speed
	if _target != null and global_position.distance_to(_target.global_position) <= aggro_range:
		desired_speed = chase_speed
		_direction = sign(_target.global_position.x - global_position.x)
		if _direction == 0.0:
			_direction = 1.0
	else:
		if global_position.x > _home_x + patrol_distance:
			_direction = -1.0
		elif global_position.x < _home_x - patrol_distance:
			_direction = 1.0

	velocity.x = _direction * desired_speed
	velocity.z = 0.0
	move_and_slide()

	if abs(velocity.x) > 0.1:
		look_at(global_position + Vector3(velocity.x, 0.0, 0.0), Vector3.UP)

	_try_touch_target()

func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0:
		_dead = true
		defeated.emit()
		queue_free()

func _try_touch_target() -> void:
	if _target == null or _touch_timer > 0.0:
		return
	if global_position.distance_to(_target.global_position) > 1.05:
		return
	if _target.has_method("take_damage"):
		_target.take_damage(touch_damage)
		_touch_timer = touch_cooldown
