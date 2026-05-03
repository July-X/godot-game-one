extends CharacterBody3D

signal defeated
signal phase_changed(new_phase: int)

# 导出配置
@export var max_health: int = 12
@export var move_speed_phase1: float = 2.0
@export var move_speed_phase2: float = 3.5
@export var shoot_cooldown_phase1: float = 2.5
@export var shoot_cooldown_phase2: float = 1.5
@export var aggro_range: float = 15.0
@export var shoot_range: float = 12.0
@export var touch_damage: int = 2
@export var touch_cooldown: float = 1.2
# 动态计算 Phase 切换阈值 (max_health * 0.5)

# 内部状态
var current_health: int
var _current_phase: int = 1
var _target = null
var _dead: bool = false
var _touch_timer: float = 0.0
var _shoot_timer: float = 0.0
var _model_root: Node3D

# 预加载场景
var _shoot_effect_scene = preload("res://scenes/entities/hit_effect.tscn")
var _damage_number_scene = preload("res://scenes/entities/damage_number.tscn")


func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]
	_model_root = $ModelRoot

func _physics_process(delta: float) -> void:
	if GameState.run_state != "running":
		velocity = Vector3.ZERO
		return
	
	_touch_timer = max(_touch_timer - delta, 0.0)
	_shoot_timer = max(_shoot_timer - delta, 0.0)
	
	# 重力
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0
	
	# 追击逻辑（参考 enemy.gd）
	if _target != null:
		var dist: float = global_position.distance_to(_target.global_position)
		
		# 在 aggro 范围内追击
		if dist <= aggro_range:
			var dir_to_target: Vector3 = (_target.global_position - global_position)
			dir_to_target.y = 0
			if dir_to_target.length() > 0.1:
				look_at(global_position + dir_to_target, Vector3.UP)
			
			# 移动
			var speed: float = move_speed_phase1 if _current_phase == 1 else move_speed_phase2
			velocity.x = dir_to_target.normalized().x * speed
			velocity.z = dir_to_target.normalized().z * speed
			
			# 在射程内且冷却完毕时射击
			if dist <= shoot_range and _shoot_timer <= 0.0:
				var cooldown: float = shoot_cooldown_phase1 if _current_phase == 1 else shoot_cooldown_phase2
				_shoot_timer = cooldown
				_shoot_at_target()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
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
	
	# 发射投射物
	var projectile_scene := preload("res://scenes/entities/projectile.tscn")
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	var spawn_pos: Vector3 = global_position + Vector3(0, 0.8, 0) + dir * 0.5
	projectile.global_position = spawn_pos
	projectile.global_rotation = global_rotation
	if projectile.has_method("configure"):
		projectile.configure(dir)
	
	# 射击音效和特效
	SFX.play_shoot()
	var effect := _shoot_effect_scene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = spawn_pos

func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	current_health -= amount
	_spawn_damage_number(amount)
	
	# Phase 切换检测
	if current_health <= max_health * 0.5 and _current_phase == 1:
		_switch_phase(2)
	
	if current_health <= 0:
		_dead = true
		defeated.emit()
		SFX.play_enemy_death()
		_death_animation()
	else:
		SFX.play_enemy_hurt()
		_flash_hit()

func _switch_phase(new_phase: int) -> void:
	_current_phase = new_phase
	phase_changed.emit(new_phase)
	
	# Phase 2: 修改材质为深红常亮
	if new_phase == 2 and _model_root:
		for child in _model_root.get_children():
			if child is MeshInstance3D and child.material_override:
				var mat = child.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color = Color(0.8, 0.2, 0.1)
					mat.emission_enabled = true
					mat.emission = Color(0.9, 0.1, 0.1)
					mat.emission_energy_multiplier = 1.5
	
	# 播放爆炸音效
	SFX.play_explosion()
	
	# 屏幕震动
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var player = players[0]
		if player.has_method("add_screen_shake"):
			player.add_screen_shake(0.5, 0.3)
	
	# 通知玩家
	GameState.set_story_line("Boss enraged! Speed and fire rate increased!")

func _try_touch_target() -> void:
	if _target == null or _touch_timer > 0.0:
		return
	if global_position.distance_to(_target.global_position) > 1.05:
		return
	if _target.has_method("take_damage"):
		_target.take_damage(touch_damage)
		_touch_timer = touch_cooldown

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

func _spawn_damage_number(amount: int) -> void:
	var dmg_n := _damage_number_scene.instantiate()
	get_tree().current_scene.add_child(dmg_n)
	dmg_n.global_position = global_position + Vector3(0, 1.2, 0)
	dmg_n.setup(amount, false)

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
