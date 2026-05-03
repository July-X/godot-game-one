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
@export var mouse_sensitivity: float = 0.002
@export var fall_damage_height: float = -5.0

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

var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _blaster: Node3D

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
	## 为所有 FPModel 子节点的材质添加程序化纹理
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var grad = GradientTexture2D.new()
	grad.width = 256
	grad.height = 256
	var g = Gradient.new()
	g.colors = [Color(0.35, 0.35, 0.4, 1), Color(0.12, 0.12, 0.15, 1)]
	g.offsets = [0.0, 1.0]
	grad.gradient = g
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 256
	noise_tex.height = 256
	for child in fp_model.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat and mat.albedo_color.r < 0.5:
				mat.albedo_texture = noise_tex
				mat.roughness_texture = grad

func _unhandled_input(event: InputEvent) -> void:
	# ESC 释放鼠标，方便操作界面或切换窗口
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# 点击窗口重新捕获鼠标
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and GameState.run_state == "running":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and GameState.run_state == "running":
		## 鼠标控制视角：Y轴旋转玩家，X轴旋转相机俯仰
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -PI * 0.45, PI * 0.45)
		if camera:
			camera.rotation.x = _pitch

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

	## 基于玩家自身朝向计算移动方向（第一人称）
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

	if move_dir.length() > 0.1:
		move_dir = move_dir.normalized()
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
		var shoot_dir: Vector3 = -camera.global_transform.basis.z.normalized()
		shoot_requested.emit(muzzle.global_position, shoot_dir)
		_recoil_pose()
		SFX.play_shoot()

	move_and_slide()

	if global_position.y < fall_damage_height:
		_respawn_at_spawn()

	if _is_moving:
		_walk_cycle += delta * 8.0
		_update_walk_animation()
	else:
		_reset_pose()

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

func _update_walk_animation() -> void:
	var swing: float = sin(_walk_cycle) * 0.25
	var bounce: float = abs(sin(_walk_cycle)) * 0.03

	## 手臂摆动
	if _arm_l:
		_arm_l.rotation.x = -swing * 0.6
		_arm_l.position.y = -0.25 + bounce
	if _arm_r:
		_arm_r.rotation.x = swing * 0.6
		_arm_r.position.y = -0.25 + bounce

	## 枪随手臂摆动
	if _blaster:
		_blaster.rotation.x = swing * 0.3
		_blaster.position.y = -0.35 + bounce * 0.5

	## 腿部摆动
	if _leg_l:
		_leg_l.rotation.x = swing
	if _leg_r:
		_leg_r.rotation.x = -swing

	## 相机轻微上下起伏（呼吸感）
	if camera:
		camera.position = Vector3(0, 0.7 + bounce * 0.5, 0)

func _reset_pose() -> void:
	_walk_cycle = 0.0
	if _arm_l:
		_arm_l.rotation.x = 0.0
		_arm_l.position.y = -0.25
	if _arm_r:
		_arm_r.rotation.x = 0.0
		_arm_r.position.y = -0.25
	if _blaster:
		_blaster.rotation.x = 0.0
		_blaster.position.y = -0.35
	if _leg_l:
		_leg_l.rotation.x = 0.0
	if _leg_r:
		_leg_r.rotation.x = 0.0
	if camera:
		camera.position = Vector3(0, 0.7, 0)

func _recoil_pose() -> void:
	if _blaster:
		var tween := create_tween()
		tween.tween_property(_blaster, "rotation_degrees:x", -6.0, 0.04)
		tween.tween_property(_blaster, "rotation_degrees:x", 0.0, 0.1)
		tween.tween_property(_blaster, "position:z", -0.5, 0.04)
		tween.tween_property(_blaster, "position:z", -0.55, 0.1)

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

func heal(amount: int) -> void:
	"""恢复生命值，不超过 max_health"""
	if current_health >= max_health:
		return
	current_health = min(current_health + amount, max_health)
	took_damage.emit(current_health, max_health)
	SFX.play_pickup()
	_spawn_heal_number(amount)

func _spawn_heal_number(amount: int) -> void:
	"""显示绿色治疗数字"""
	var heal_dn := _damage_number_scene.instantiate()
	get_tree().current_scene.add_child(heal_dn)
	heal_dn.global_position = global_position + Vector3(0, 1.2, 0)
	heal_dn.setup(amount, true, Color(0.2, 0.9, 0.3, 1.0))

func _update_damage_flash() -> void:
	## 第一人称不需要隐藏身体，改为屏幕震动
	pass

func add_screen_shake(strength: float, decay: float = -1.0) -> void:
	## 外部调用接口：触发屏幕震动
	_shake_strength = strength
	if decay > 0.0:
		shake_decay = decay

func _update_camera_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake_strength > 0.0:
		var offset := Vector3(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength),
			0
		)
		camera.position = Vector3(0, 0.7, 0) + offset
		_shake_strength = max(_shake_strength - shake_decay * delta, 0.0)
	else:
		camera.position = Vector3(0, 0.7, 0)
