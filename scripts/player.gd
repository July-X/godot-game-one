extends CharacterBody3D

signal shoot_requested(origin, direction)
signal took_damage(current_health, max_health)
signal died

@export var move_speed: float = 6.5
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0
@export var max_health: int = 5
@export var fire_cooldown: float = 0.18
@export var hit_invincibility: float = 0.45
@export var shake_intensity: float = 0.18
@export var shake_decay: float = 8.0

@onready var muzzle = $CameraRig/Muzzle
@onready var body_mesh = $MeshInstance3D
@onready var camera_rig = $CameraRig

var current_health = 5
var _fire_timer = 0.0
var _invincibility_timer = 0.0
var _flash_timer = 0.0
var _shake_strength = 0.0
var _camera_rest_pos: Vector3

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	_camera_rest_pos = camera_rig.position

func _physics_process(delta: float) -> void:
	if GameState.run_state != "running":
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_fire_timer = max(_fire_timer - delta, 0.0)
	_invincibility_timer = max(_invincibility_timer - delta, 0.0)
	_flash_timer = max(_flash_timer - delta, 0.0)
	_update_damage_flash()
	_update_camera_shake(delta)

	var input_x := Input.get_axis("ui_left", "ui_right")
	var input_z := Input.get_axis("ui_up", "ui_down")
	var movement := Vector3(input_x, 0.0, input_z)

	if movement.length() > 1.0:
		movement = movement.normalized()

	velocity.x = movement.x * move_speed
	velocity.z = movement.z * move_speed

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
		if Input.is_action_just_pressed("ui_cancel"):
			velocity.y = jump_velocity

	if Input.is_action_just_pressed("ui_accept") and _fire_timer <= 0.0:
		_fire_timer = fire_cooldown
		shoot_requested.emit(muzzle.global_position, -global_transform.basis.z.normalized())

	move_and_slide()

	if movement.length() > 0.1:
		var flat_dir := Vector3(movement.x, 0.0, movement.z)
		look_at(global_position + flat_dir, Vector3.UP)

func take_damage(amount: int = 1) -> void:
	if _invincibility_timer > 0.0:
		return
	current_health = max(current_health - amount, 0)
	_invincibility_timer = hit_invincibility
	_flash_timer = hit_invincibility
	_shake_strength = shake_intensity
	took_damage.emit(current_health, max_health)
	if current_health == 0:
		died.emit()

func _update_damage_flash() -> void:
	if body_mesh == null:
		return
	if _flash_timer > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0:
		body_mesh.visible = false
	else:
		body_mesh.visible = true

func _update_camera_shake(delta: float) -> void:
	if _shake_strength > 0.0:
		var offset := Vector3(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength * 0.5, _shake_strength * 0.5)
		)
		camera_rig.position = _camera_rest_pos + offset
		_shake_strength = max(_shake_strength - shake_decay * delta, 0.0)
	else:
		camera_rig.position = _camera_rest_pos
