extends CharacterBody3D

signal defeated

@export var move_speed: float = 2.2
@export var chase_speed: float = 3.4
@export var gravity: float = 18.0
@export var health: int = 2
@export var patrol_distance: float = 3.0
@export var aggro_range: float = 6.0
@export var touch_damage: int = 1
@export var touch_cooldown: float = 1.0

var _home_x = 0.0
var _direction = 1.0
var _target = null
var _dead = false
var _touch_timer = 0.0
var _patrol_pause: float = 0.0
@export var patrol_wait_time: float = 1.0
var _mesh_instance: MeshInstance3D
var _original_material: Material
var _model_root: Node3D

func _ready() -> void:
	add_to_group("enemies")
	_home_x = global_position.x
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]
	_mesh_instance = $MeshInstance3D
	if _mesh_instance and _mesh_instance.material_override:
		_original_material = _mesh_instance.material_override.duplicate()
	_model_root = $ModelRoot
	_apply_procedural_textures()

func _apply_procedural_textures() -> void:
	if _model_root == null:
		return
	for child in _model_root.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat:
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
				mat.normal_scale = 0.2

func _physics_process(delta: float) -> void:
	if GameState.run_state != "running":
		velocity = Vector3.ZERO
		return

	_touch_timer = max(_touch_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	## 巡逻停顿逻辑
	if _patrol_pause > 0.0:
		_patrol_pause -= delta
		velocity.x = 0.0
		move_and_slide()
		_try_touch_target()
		return

	var desired_speed = move_speed
	if _target != null and global_position.distance_to(_target.global_position) <= aggro_range:
		desired_speed = chase_speed
		_direction = sign(_target.global_position.x - global_position.x)
		if _direction == 0.0:
			_direction = 1.0
	else:
		## 到达巡逻端点时停顿
		if global_position.x > _home_x + patrol_distance:
			_direction = -1.0
			_patrol_pause = patrol_wait_time
		elif global_position.x < _home_x - patrol_distance:
			_direction = 1.0
			_patrol_pause = patrol_wait_time

	velocity.x = _direction * desired_speed
	velocity.z = 0.0
	move_and_slide()

	if abs(velocity.x) > 0.1:
		look_at(global_position + Vector3(velocity.x, 0.0, 0.0), Vector3.UP)

	_try_touch_target()

var _damage_number_scene = preload("res://scenes/entities/damage_number.tscn")

func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	health -= amount
	_flash_hit()
	_spawn_damage_number(amount)
	if health <= 0:
		_dead = true
		defeated.emit()
		SFX.play_enemy_death()
		_death_animation()
	else:
		SFX.play_enemy_hurt()

func _spawn_damage_number(amount: int) -> void:
	var dn := _damage_number_scene.instantiate()
	get_tree().current_scene.add_child(dn)
	dn.global_position = global_position + Vector3(0, 1.2, 0)
	dn.setup(amount, false)

func _flash_hit() -> void:
	## 受击时所有部件白色闪烁
	if _model_root == null:
		return
	for child in _model_root.get_children():
		if child is MeshInstance3D and child.material_override:
			var mat = child.material_override as StandardMaterial3D
			if mat:
				mat.emission_enabled = true
				mat.emission = Color(1.0, 1.0, 1.0)
				mat.emission_energy_multiplier = 2.0
				var tween := create_tween()
				tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.12)
				tween.tween_callback(func():
					mat.emission_enabled = false
				)

func _death_animation() -> void:
	## 死亡动画：缩小消失 + 红色闪烁，然后 queue_free
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.35)
	if _model_root:
		for child in _model_root.get_children():
			if child is MeshInstance3D and child.material_override:
				var mat = child.material_override as StandardMaterial3D
				if mat:
					mat.emission_enabled = true
					mat.emission = Color(1.0, 0.2, 0.1)
					mat.emission_energy_multiplier = 3.0
					tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.35)
	tween.tween_callback(queue_free).set_delay(0.35)

func _try_touch_target() -> void:
	if _target == null or _touch_timer > 0.0:
		return
	if global_position.distance_to(_target.global_position) > 1.05:
		return
	if _target.has_method("take_damage"):
		_target.take_damage(touch_damage)
		_touch_timer = touch_cooldown
