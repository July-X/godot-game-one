extends CharacterBody3D

signal defeated

@export var gravity: float = 18.0
@export var health: int = 2
@export var touch_damage: int = 1
@export var touch_cooldown: float = 1.0
@export var shoot_cooldown: float = 2.0
@export var shoot_range: float = 8.0
@export var aggro_range: float = 10.0

var _target = null
var _dead = false
var _touch_timer: float = 0.0
var _shoot_timer: float = 0.0
var _model_root: Node3D
var _shoot_effect_scene = preload("res://scenes/entities/hit_effect.tscn")
var _damage_number_scene = preload("res://scenes/entities/damage_number.tscn")

func _ready() -> void:
	add_to_group("enemies")
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]
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
	_shoot_timer = max(_shoot_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	## 射击型敌人不移动，只转向目标
	if _target != null:
		var dir_to_target: Vector3 = _target.global_position - global_position
		dir_to_target.y = 0
		if dir_to_target.length() > 0.1:
			look_at(global_position + dir_to_target, Vector3.UP)

		## 在射程内且冷却完毕时射击
		if dir_to_target.length() <= shoot_range and _shoot_timer <= 0.0:
			_shoot_timer = shoot_cooldown
			_shoot_at_target()

	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	_try_touch_target()

func _shoot_at_target() -> void:
	if _target == null:
		return
	var dir: Vector3 = (_target.global_position - global_position).normalized()
	dir.y = 0
	if dir.length() < 0.1:
		return

	## 发射投射物
	var projectile_scene := preload("res://scenes/entities/projectile.tscn")
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	## 从敌人头部位置发射
	var spawn_pos: Vector3 = global_position + Vector3(0, 0.8, 0) + dir * 0.5
	projectile.global_position = spawn_pos
	projectile.global_rotation = global_rotation
	if projectile.has_method("configure"):
		projectile.configure(dir)

	## 射击音效和特效
	SFX.play_shoot()
	var effect := _shoot_effect_scene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = spawn_pos

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
