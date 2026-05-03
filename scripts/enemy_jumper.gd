extends CharacterBody3D

signal defeated

@export var move_speed: float = 3.0
@export var jump_force: float = 5.0
@export var gravity: float = 18.0
@export var health: int = 2
@export var touch_damage: int = 1
@export var touch_cooldown: float = 0.8
@export var jump_cooldown: float = 1.5
@export var aggro_range: float = 8.0

var _target = null
var _dead = false
var _touch_timer: float = 0.0
var _jump_timer: float = 0.0
var _model_root: Node3D
var _damage_number_scene = preload("res://scenes/entities/damage_number.tscn")

func _ready() -> void:
	add_to_group("enemies")
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]
	_model_root = $ModelRoot

func _physics_process(delta: float) -> void:
	if GameState.run_state != "running":
		velocity = Vector3.ZERO
		return

	_touch_timer = max(_touch_timer - delta, 0.0)
	_jump_timer = max(_jump_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	if _target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var dist: float = global_position.distance_to(_target.global_position)
	var dir: Vector3 = (_target.global_position - global_position)
	dir.y = 0
	if dir.length() > 0.1:
		dir = dir.normalized()
		look_at(global_position + dir, Vector3.UP)

	## 在追击范围内时移动 + 跳跃
	if dist <= aggro_range:
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed

		## 跳跃型敌人：在地面上且冷却完毕时跳跃
		if is_on_floor() and _jump_timer <= 0.0:
			_jump_timer = jump_cooldown
			velocity.y = jump_force
			SFX.play_enemy_hurt()  ## 用敌人受伤音效作为跳跃音效
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
	_try_touch_target()

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
