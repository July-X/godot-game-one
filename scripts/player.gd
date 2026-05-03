extends CharacterBody3D

signal shoot_requested(origin, direction)
signal took_damage(current_health, max_health)
signal died

@export var move_speed: float = 6.5
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0
@export var max_health: int = 4
@export var fire_cooldown: float = 0.18
@export var hit_invincibility: float = 0.5
@export var shake_intensity: float = 0.18
@export var shake_decay: float = 8.0
@export var turn_speed: float = 8.0
@export var fall_damage_height: float = -5.0

@onready var muzzle = $CameraRig/Muzzle
@onready var body_mesh = $MeshInstance3D
@onready var camera_rig = $CameraRig
@onready var model_root = $ModelRoot

var current_health: int = max_health
var _fire_timer: float = 0.0
var _invincibility_timer: float = 0.0
var _flash_timer: float = 0.0
var _shake_strength: float = 0.0
var _camera_rest_pos: Vector3
var _walk_cycle: float = 0.0
var _is_moving: bool = false
var _target_rotation: float = 0.0

@onready var _leg_l: Node3D = $ModelRoot/LegL
@onready var _leg_r: Node3D = $ModelRoot/LegR
@onready var _arm_l: Node3D = $ModelRoot/ArmL
@onready var _arm_r: Node3D = $ModelRoot/ArmR
@onready var _blaster: Node3D = $CameraRig/Muzzle/Blaster

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	_camera_rest_pos = camera_rig.position
	_target_rotation = global_rotation.y

func _physics_process(delta: float) -> void:
	if GameState.run_state != "running":
		velocity = Vector3.ZERO
		move_and_slide()
		_reset_pose()
		return

	_fire_timer = max(_fire_timer - delta, 0.0)
	_invincibility_timer = max(_invincibility_timer - delta, 0.0)
	_flash_timer = max(_flash_timer - delta, 0.0)
	_update_damage_flash()
	_update_camera_shake(delta)

	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_up", "move_down")
	var input_dir := Vector2(input_x, input_z)

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	## 基于相机朝向计算移动方向
	var cam_basis: Basis = camera_rig.global_transform.basis
	var cam_forward: Vector3 = -cam_basis.z
	cam_forward.y = 0.0
	if cam_forward.length() > 0.01:
		cam_forward = cam_forward.normalized()
	var cam_right: Vector3 = cam_basis.x
	cam_right.y = 0.0
	if cam_right.length() > 0.01:
		cam_right = cam_right.normalized()

	var move_dir: Vector3 = (cam_forward * (-input_dir.y) + cam_right * input_dir.x)
	move_dir.y = 0.0

	if move_dir.length() > 0.1:
		move_dir = move_dir.normalized()
		## 平滑转向
		_target_rotation = atan2(move_dir.x, move_dir.z)
		var current_rot: float = global_rotation.y
		var diff: float = wrapf(_target_rotation - current_rot, -PI, PI)
		global_rotation.y += clamp(diff, -turn_speed * delta, turn_speed * delta)
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		_is_moving = true
	else:
		_is_moving = false

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	if Input.is_action_just_pressed("shoot") and _fire_timer <= 0.0:
		_fire_timer = fire_cooldown
		var shoot_dir: Vector3 = -global_transform.basis.z.normalized()
		shoot_requested.emit(muzzle.global_position, shoot_dir)
		_recoil_pose()
		SFX.play_shoot()

	move_and_slide()

	## 掉落检测：超出地图边界时重置到出生点
	if global_position.y < fall_damage_height:
		_respawn_at_spawn()

	if _is_moving:
		_walk_cycle += delta * 8.0
		_update_walk_animation()
	else:
		_reset_pose()

func _respawn_at_spawn() -> void:
	## 掉落重置：回到出生点并恢复部分血量
	if has_node("/root/Main"):
		var main_node = get_node("/root/Main")
		if main_node.has_node("Level"):
			var lvl = main_node.get_node("Level")
			if lvl.has_node("PlayerSpawn"):
				global_position = lvl.get_node("PlayerSpawn").global_position
				velocity = Vector3.ZERO
				current_health = max(current_health, 1)
				return
	## 备用：重置到原点
	global_position = Vector3(0, 2, 0)
	velocity = Vector3.ZERO
	current_health = max(current_health, 1)

func _update_walk_animation() -> void:
	var swing: float = sin(_walk_cycle) * 0.3
	var bounce: float = abs(sin(_walk_cycle)) * 0.04

	if _leg_l:
		_leg_l.rotation.x = swing
	if _leg_r:
		_leg_r.rotation.x = -swing
	if _arm_l:
		_arm_l.rotation.x = -swing * 0.7
	if _arm_r:
		_arm_r.rotation.x = swing * 0.7

	model_root.position.y = bounce

func _reset_pose() -> void:
	_walk_cycle = 0.0
	model_root.position.y = 0.0
	if _leg_l:
		_leg_l.rotation.x = 0.0
	if _leg_r:
		_leg_r.rotation.x = 0.0
	if _arm_l:
		_arm_l.rotation.x = 0.0
	if _arm_r:
		_arm_r.rotation.x = 0.0

func _recoil_pose() -> void:
	if _blaster:
		var tween := create_tween()
		tween.tween_property(_blaster, "rotation_degrees:x", -8.0, 0.05)
		tween.tween_property(_blaster, "rotation_degrees:x", 0.0, 0.12)

var _damage_number_scene = preload("res://scenes/entities/damage_number.tscn")

func _spawn_damage_number(amount: int) -> void:
	var dn := _damage_number_scene.instantiate()
	get_tree().current_scene.add_child(dn)
	dn.global_position = global_position + Vector3(0, 1.2, 0)
	dn.setup(amount, true)

func take_damage(amount: int = 1) -> void:
	if _invincibility_timer > 0.0:
		return
	current_health = max(current_health - amount, 0)
	_invincibility_timer = hit_invincibility
	_flash_timer = hit_invincibility
	_shake_strength = shake_intensity
	took_damage.emit(current_health, max_health)
	SFX.play_player_hurt()
	_spawn_damage_number(amount)
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
