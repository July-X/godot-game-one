extends Area2D

var _screen_shake_scene = preload("res://scenes/effects/screen_shake.tscn")

var _type: String = "spread"
var _lifetime: float = 10.0
var _bob_timer: float = 0.0
var entity_id: int = 0
var _is_network_ghost: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _glow: Sprite2D = $GlowSprite

func _ready() -> void:
	add_to_group("powerups")
	_setup_visual_style()

func setup(type: String) -> void:
	_type = type
	call_deferred("_apply_sprite")
	## 联机同步链路在 add_child() 之前就调用 setup()（见 main.gd::_rpc_spawn_powerup），
	## 此时 @onready var _sprite 仍是 null，直接访问会抛运行时错误。
	## 未入树时跳过：_ready() 会带着正确的 _type 与 assigned_peer_id 再应用一次样式。
	if is_inside_tree():
		_setup_visual_style()

func get_powerup_type() -> String:
	return _type

func _apply_sprite() -> void:
	_sprite.texture = SpriteFactory.create_powerup_sprite(_type)

var _glow_time: float = 0.0
var _magnet_target: Node2D = null
var _magnet_speed: float = 320.0
var _magnet_elapsed: float = 0.0
var _magnet_requested: bool = false
var _magnet_owner_peer_id: int = 0

func _physics_process(delta: float) -> void:
	if NetworkManager.is_online() and _is_network_ghost:
		## 客户端幽灵掉落物只展示服务器同步位置，避免“来回拉扯”。
		return

	## 磁铁吸引模式：向玩家飞行
	if is_instance_valid(_magnet_target) and not _magnet_target.is_downed:
		_magnet_elapsed += delta
		var accel_t: float = clampf(_magnet_elapsed / 0.35, 0.0, 1.0)
		_magnet_speed = lerpf(320.0, 720.0, accel_t)
		var dir: Vector2 = global_position.direction_to(_magnet_target.global_position)
		global_position += dir * _magnet_speed * delta
		# 接近玩家时逐渐透明
		var mag_dist: float = global_position.distance_to(_magnet_target.global_position)
		var mag_fade: float = clamp(mag_dist / 300.0, 0.1, 1.0)
		_sprite.modulate.a = mag_fade
		if _glow:
			_glow.modulate.a = mag_fade * 0.6
		if global_position.distance_to(_magnet_target.global_position) < 40.0:
			collect()
			return
		return  # 磁铁模式下跳过常规脉动，加载更少
	_magnet_target = null

	_bob_timer += delta * 3.0
	_sprite.position.y = sin(_bob_timer) * 4.0
	_sprite.rotation += delta * 1.5

	_glow_time += delta
	var t: float = _glow_time
	var pulse: float = 0.4 + abs(sin(t * 12.0)) * 0.6
	_sprite.modulate.a = pulse * 0.6 + 0.4

	if _glow:
		var glow_a: float = 0.2 + abs(sin(t * 8.0)) * 0.35
		_glow.modulate.a = glow_a
		var glow_s: float = 0.9 + abs(sin(t * 6.0)) * 0.2
		_glow.scale = Vector2(glow_s, glow_s)

	_lifetime -= delta
	if _lifetime <= 0:
		if NetworkManager.is_online() and multiplayer.is_server():
			var scene := get_tree().current_scene
			if scene and scene.has_method("_on_network_powerup_collected"):
				scene._on_network_powerup_collected(entity_id)
			return
		if NetworkManager.is_online():
			return
		queue_free()
	if _lifetime < 3.0:
		var blink: float = 0.3 + abs(sin(_lifetime * 12)) * 0.7
		_sprite.modulate.a = blink

var _collected: bool = false

func start_magnet(target: Node2D) -> void:
	if _collected or not is_instance_valid(target) or not target.is_in_group("player") or target.is_downed:
		return
	if NetworkManager.is_online():
		var peer_id: int = target.peer_id
		var assigned := int(get_meta("assigned_peer_id", 0))
		if (assigned > 0 and peer_id != assigned) or not GameState.is_player_alive(peer_id):
			return
		if not multiplayer.is_server():
			# 本机只提醒房主检查吸附。远端飞机的幽灵节点不能代本机发请求。
			if not _magnet_requested and peer_id == multiplayer.get_unique_id():
				_magnet_requested = true
				get_parent().request_network_powerup_magnet(entity_id)
			return
		if (_magnet_owner_peer_id > 0 and _magnet_owner_peer_id != peer_id) or _magnet_target == target:
			return
		_magnet_owner_peer_id = peer_id
	_magnet_target = target
	_sprite.modulate.a = 1.0
	if _glow:
		_glow.modulate.a = 1.0
	_magnet_elapsed = 0.0
	_magnet_speed = 320.0

func collect() -> void:
	if _collected:
		return
	if NetworkManager.is_online():
		if multiplayer.is_server() and is_instance_valid(_magnet_target):
			get_parent()._on_network_powerup_collected(entity_id, _magnet_owner_peer_id)
		return

	var reward := GameState.collect_powerup(_type)
	var scene := get_tree().current_scene
	if scene and scene.has_method("on_local_powerup_feedback"):
		scene.on_local_powerup_feedback(_type, global_position, true, reward)
	if _type == "bomb":
		_bomb_effect()
	_finish_visual(0.4)

## 结果已确认，立即退出拾取和同步，只留一小段两端相同的收尾。
func finish_network_pickup(world_pos: Vector2) -> void:
	global_position = world_pos
	reset_physics_interpolation()
	_sprite.modulate.a = 0.75
	_glow.modulate.a = 0.38
	remove_from_group("powerups")
	set_deferred("monitorable", false)
	_finish_visual(0.15, true)

func _finish_visual(seconds: float, wait_for_tween := false) -> void:
	_collected = true
	_magnet_target = null
	set_process(false)
	set_physics_process(false)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(0.1, 0.1), seconds)
	tween.tween_property(_sprite, "modulate:a", 0.0, seconds)
	tween.tween_property(_glow, "scale", Vector2(0.1, 0.1), seconds)
	tween.tween_property(_glow, "modulate:a", 0.0, seconds)
	if wait_for_tween:
		tween.chain()
	tween.tween_callback(queue_free)


func _bomb_effect() -> void:
	SFX.play_explosion()
	call_deferred("_spawn_shake")
	call_deferred("_kill_enemies_sequential")

func _spawn_shake() -> void:
	## 旧实现自己实例化 screen_shake 场景直接写 camera.offset，
	## 会和其他事件的震动互相覆盖。改为转发到 main.gd 的 trauma 入口统一叠加。
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("add_shake"):
		scene.add_shake(scene.SHAKE_EXPLOSION)

var _kill_queue: Array = []
var _kill_idx: int = 0

func _kill_enemies_sequential() -> void:
	_kill_queue = get_tree().get_nodes_in_group("enemies")
	_kill_idx = 0
	_kill_next()

func _kill_next() -> void:
	while _kill_idx < _kill_queue.size():
		var e: Node2D = _kill_queue[_kill_idx]
		_kill_idx += 1
		if is_instance_valid(e) and e.has_method("die"):
			e.die()
			get_tree().create_timer(0.08).timeout.connect(_kill_next)
			return
	_kill_queue.clear()

func _setup_visual_style() -> void:
	match _type:
		"heal":
			_sprite.modulate = Color(0.7, 1.0, 0.75, 1.0)
			if _glow:
				_glow.modulate = Color(0.8, 1.0, 0.85, 0.45)
		"spread":
			_sprite.modulate = Color(0.45, 1.0, 0.85, 1.0)
			if _glow:
				_glow.modulate = Color(0.55, 1.0, 0.9, 0.45)
		"speed":
			_sprite.modulate = Color(0.55, 0.8, 1.0, 1.0)
			if _glow:
				_glow.modulate = Color(0.5, 0.85, 1.0, 0.45)
		"power":
			_sprite.modulate = Color(1.0, 0.55, 0.3, 1.0)
			if _glow:
				_glow.modulate = Color(1.0, 0.5, 0.2, 0.5)
		"bomb":
			_sprite.modulate = Color(1.0, 0.9, 0.35, 1.0)
			if _glow:
				_glow.modulate = Color(1.0, 0.85, 0.2, 0.55)
		"core":
			_sprite.modulate = Color(1.0, 0.9, 0.35, 1.0)
			if _glow:
				_glow.modulate = Color(1.0, 0.82, 0.18, 0.62)
	## 注意：这里**不要**把 assigned_peer_id meta 缓存成成员变量。
	## 三个生成路径（enemy / elite / boss）都是 add_child() → setup() → set_meta()，
	## 缓存会永远读到空值；归属判断一律直接读 meta（见 start_magnet）。
