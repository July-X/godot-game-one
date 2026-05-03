extends CharacterBody3D

signal shoot_requested(origin, direction)
signal took_damage(current_health, max_health)
signal died

## 移动参数
@export var move_speed: float = 7.0
@export var acceleration: float = 12.0
@export var deceleration: float = 10.0
@export var air_acceleration: float = 4.0
@export var air_speed_cap: float = 3.0
@export var jump_velocity: float = 5.5
@export var gravity: float = 16.0
@export var mouse_sensitivity: float = 0.0018
@export var mouse_smoothing: float = 0.15
@export var fall_damage_height: float = -5.0

## 战斗参数
@export var max_health: int = 4
@export var fire_cooldown: float = 0.15
@export var hit_invincibility: float = 0.5
@export var shake_intensity: float = 0.12
@export var shake_decay: float = 10.0

## 模型动画参数
@export var walk_cycle_speed: float = 10.0
@export var walk_swing_amount: float = 0.35
@export var walk_bounce_amount: float = 0.025
@export var head_bob_strength: float = 0.015
@export var turn_speed: float = 10.0

var muzzle: Marker3D
var camera: Camera3D
var fp_model: Node3D

var current_health: int = max_health
var _fire_timer: float = 0.0
var _invincibility_timer: float = 0.0
var _flash_timer: float = 0.0
var _shake_strength: float = 0.0
var _walk_cycle: float = 0.0
var _is_moving: bool = false
var _pitch: float = 0.0
var _yaw_velocity: float = 0.0
var _pitch_velocity: float = 0.0
var _current_speed: float = 0.0
var _head_bob_timer: float = 0.0
var _last_shoot_time: float = 0.0

@onready var _leg_l: Node3D = $FPModel/LegL
@onready var _leg_r: Node3D = $FPModel/LegR
@onready var _arm_l: Node3D = $FPModel/ArmL
@onready var _arm_r: Node3D = $FPModel/ArmR
@onready var _blaster: Node3D = $FPModel/Blaster_Body

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	muzzle = get_node("FPModel/Muzzle") as Marker3D
	camera = get_node("Camera3D") as Camera3D
	fp_model = get_node("FPModel") as Node3D
	_leg_l = get_node("FPModel/LegL") as Node3D
	_leg_r = get_node("FPModel/LegR") as Node3D
	_arm_l = get_node("FPModel/ArmL") as Node3D
	_arm_r = get_node("FPModel/ArmR") as Node3D
	_blaster = get_node("FPModel/Blaster_Body") as Node3D
	_apply_procedural_textures()

func _apply_procedural_textures() -> void:
	for child in fp_model.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat == null:
				continue
			if mat.emission_energy_multiplier > 0.5:
				continue
			var noise = FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = randf_range(0.03, 0.08)
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = randi_range(3, 5)
			var noise_tex = NoiseTexture2D.new()
			noise_tex.noise = noise
			noise_tex.width = 128
			noise_tex.height = 128
			mat.albedo_texture = noise_tex
			mat.normal_enabled = true
			mat.normal_texture = noise_tex
			mat.normal_scale = 0.15

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and GameState.run_state == "running":
		var target_yaw: float = -event.relative.x * mouse_sensitivity
		var target_pitch: float = -event.relative.y * mouse_sensitivity
		_yaw_velocity = lerp(_yaw_velocity, target_yaw, mouse_smoothing)
		_pitch_velocity = lerp(_pitch_velocity, target_pitch, mouse_smoothing)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and GameState.run_state == "running":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

	## 鼠标视角（平滑插值）
	rotate_y(_yaw_velocity)
	_pitch = clamp(_pitch + _pitch_velocity, -PI * 0.45, PI * 0.45)
	if camera:
		camera.rotation.x = _pitch
	_yaw_velocity *= 0.85
	_pitch_velocity *= 0.85

	## 输入
	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_up", "move_down")
	var input_dir := Vector2(input_x, input_z)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	## 基于玩家朝向计算移动方向
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length() > 0.01:
		forward = forward.normalized()
	var right: Vector3 = global_transform.basis.x
	right.y = 0.0
	if right.length() > 0.01:
		right = right.normalized()

	var move_dir: Vector3 = (forward * (-input_dir.y) + right * input_dir.x)
	move_dir.y = 0.0

	## 加速度控制
	var target_speed: float = 0.0
	if move_dir.length() > 0.1:
		move_dir = move_dir.normalized()
		target_speed = move_speed
		_is_moving = true
	else:
		_is_moving = false

	var accel: float = acceleration
	var max_spd: float = move_speed
	if not is_on_floor():
		accel = air_acceleration
		max_spd = air_speed_cap

	if target_speed > 0.0:
		_current_speed = move_toward(_current_speed, target_speed, accel * delta)
	else:
		_current_speed = move_toward(_current_speed, 0.0, deceleration * delta)

	velocity.x = move_dir.x * _current_speed
	velocity.z = move_dir.z * _current_speed

	## 跳跃
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	## 射击
	if Input.is_action_just_pressed("shoot") and _fire_timer <= 0.0:
		_fire_timer = fire_cooldown
		_last_shoot_time = Time.get_ticks_msec() / 1000.0
		var shoot_dir: Vector3 = -camera.global_transform.basis.z.normalized()
		shoot_requested.emit(muzzle.global_position, shoot_dir)
		_recoil_pose()
		SFX.play_shoot()

	move_and_slide()

	## 地图边界
	global_position.x = clamp(global_position.x, -11.0, 11.0)
	global_position.z = clamp(global_position.z, -11.0, 11.0)

	if global_position.y < fall_damage_height:
		_respawn_at_spawn()

	## 行走动画
	if _is_moving and is_on_floor():
		_walk_cycle += delta * walk_cycle_speed
		_head_bob_timer += delta * walk_cycle_speed * 0.5
		_update_walk_animation()
	else:
		_reset_pose()

func _update_walk_animation() -> void:
	var swing: float = sin(_walk_cycle) * walk_swing_amount
	var bounce: float = abs(sin(_walk_cycle)) * walk_bounce_amount
	var head_bob: float = sin(_head_bob_timer) * head_bob_strength

	if _leg_l:
		_leg_l.rotation.x = swing
	if _leg_r:
		_leg_r.rotation.x = -swing
	if _arm_l:
		_arm_l.rotation.x = -swing * 0.7
		_arm_l.position.y = -0.35 + bounce
	if _arm_r:
		_arm_r.rotation.x = swing * 0.7
		_arm_r.position.y = -0.35 + bounce
	if _blaster:
		_blaster.rotation.x = swing * 0.3
		_blaster.position.y = -0.5 + bounce * 0.5
	if camera:
		camera.position = Vector3(0, 0.7 + head_bob + bounce * 0.3, 0)

func _reset_pose() -> void:
	_walk_cycle = 0.0
	_head_bob_timer = 0.0
	if _arm_l:
		_arm_l.rotation.x = 0.0
		_arm_l.position.y = -0.35
	if _arm_r:
		_arm_r.rotation.x = 0.0
		_arm_r.position.y = -0.35
	if _blaster:
		_blaster.rotation.x = 0.0
		_blaster.position.y = -0.5
	if _leg_l:
		_leg_l.rotation.x = 0.0
	if _leg_r:
		_leg_r.rotation.x = 0.0
	if camera:
		camera.position = Vector3(0, 0.7, 0)

func _recoil_pose() -> void:
	if _blaster:
		var tween := create_tween()
		tween.tween_property(_blaster, "rotation_degrees:x", -8.0, 0.03)
		tween.tween_property(_blaster, "rotation_degrees:x", 0.0, 0.08)
		tween.tween_property(_blaster, "position:z", -0.5, 0.03)
		tween.tween_property(_blaster, "position:z", -0.55, 0.08)
	if camera:
		_pitch = clamp(_pitch + 0.03, -PI * 0.45, PI * 0.45)

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
	pass

func _update_camera_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake_strength > 0.0:
		var offset := Vector3(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength) * 0.5,
			0
		)
		camera.position = Vector3(0, 0.7, 0) + offset
		_shake_strength = max(_shake_strength - shake_decay * delta, 0.0)
	else:
		camera.position = Vector3(0, 0.7, 0)

func _respawn_at_spawn() -> void:
	if has_node("/root/Main"):
		var main_node = get_node("/root/Main")
		if main_node.has_node("Level"):
			var lvl = main_node.get_node("Level")
			if lvl.has_node("PlayerSpawn"):
				global_position = lvl.get_node("PlayerSpawn").global_position
				velocity = Vector3.ZERO
				current_health = max(current_health, 1)
				return
	global_position = Vector3(0, 2, 0)
	velocity = Vector3.ZERO
	current_health = max(current_health, 1)
