## Player — 玩家飞船控制器（外观层）
##
## 编排 MotionController / CombatController / FeedbackController / ActionRouter 的执行顺序。
## 不再直接实现移动、战斗、动画逻辑，而是委托给子组件。
##
## 多人设计：每个玩家节点的 multiplayer_authority = 该玩家的 peer_id。
## 单机模式下 multiplayer_authority 默认为 1（服务器），与原逻辑兼容。
extends CharacterBody2D

signal died

@export var move_speed: float = 260.0
@export var friction: float = 500.0
@export var mouse_sensitivity: float = 0.008

## 多人模式下标识本玩家属于哪个 peer（生成时由 main.gd 设置）
var peer_id: int = 1
var _invincible_timer: float = 0.0

var _action_router: Node
var _motion: Node
var _combat: Node
var _feedback: Node

var _pickup_area: Area2D
var _shield_container: Node2D
var ShieldRing = preload("res://scripts/shield_ring.gd")
var _shield_dirty: bool = false
var _pending_shield_layers: int = 0


func _ready() -> void:
	_init_multiplayer()
	_init_components()
	_connect_signals()


func _init_multiplayer() -> void:
	if name.is_valid_int():
		peer_id = name.to_int()
	set_multiplayer_authority(peer_id)


func _init_components() -> void:
	_action_router = _add_component("ActionRouter", "res://scripts/player/action_router.gd")
	_motion = _add_component("MotionController", "res://scripts/player/motion_controller.gd")
	_motion.move_speed = move_speed
	_motion.mouse_sensitivity = mouse_sensitivity
	if OS.has_feature("android") or OS.has_feature("ios"):
		_motion.mobile_mode = true

	_combat = _add_component("CombatController", "res://scripts/player/combat_controller.gd")
	_feedback = _add_component("FeedbackController", "res://scripts/player/feedback_controller.gd")
	_feedback.update_appearance()
	_combat.update_pickup_radius()

	_pickup_area = $PickupArea
	_shield_container = $ShieldContainer


func _add_component(name_prefix: String, script_path: String) -> Node:
	var node := Node.new()
	node.name = name_prefix
	node.set_script(load(script_path))
	add_child(node)
	return node


func _connect_signals() -> void:
	add_to_group("player")
	if _pickup_area:
		_pickup_area.body_entered.connect(_on_pickup_body_entered)
	GameState.shield_changed.connect(_on_shield_changed)
	if _motion.mobile_mode:
		var mc := get_tree().current_scene.find_child("MobileControls", true, false)
		if mc:
			mc.move_input.connect(_motion.handle_mobile_move)


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.game_running:
		return
	if event is InputEventMouseMotion and not _motion.mobile_mode:
		_motion.handle_mouse_motion(event)
	_action_router.handle_keyboard_event(event)


func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return
	## 仅在真实联机时才做 authority 拦截，避免单机被残留联机状态误伤。
	if NetworkManager.is_online() and not is_multiplayer_authority():
		return

	_tick_runtime(delta)
	_motion.update(delta, GameState.get_move_speed_multiplier(), get_viewport_rect().size)
	_combat.update(delta)
	_feedback.update(delta)


func _tick_runtime(delta: float) -> void:
	_invincible_timer = max(_invincible_timer - delta, 0.0)
	GameState.tick_skill_cooldown(delta)
	GameState.tick_laser_cooldown(delta)


## ── 公开入口 ──────────────────────────────────────────

func request_action(action: String) -> void:
	_action_router.request_action(action)


func take_damage(amount: float = 1.0) -> void:
	if _invincible_timer > 0:
		return
	var actual_damage: int = amount as int
	if amount > 0.0 and amount < 1.0 and randf() < amount:
		actual_damage = 1
	var old_health: int = GameState.current_health
	GameState.take_damage(actual_damage)
	if GameState.current_health < old_health:
		_invincible_timer = 1.0
		_feedback.trigger_hit()
	if GameState.current_health <= 0:
		_feedback.spawn_explosion()
		died.emit()
		queue_free()


func on_level_up() -> void:
	_feedback.update_appearance()
	_combat.update_pickup_radius()
	_feedback.play_level_up_effect()


## ── 护盾 ──────────────────────────────────────────────

func _on_shield_changed(layers: int) -> void:
	_pending_shield_layers = layers
	if not _shield_dirty:
		_shield_dirty = true
		call_deferred("_rebuild_shields")


func _rebuild_shields() -> void:
	_shield_dirty = false
	var layers: int = _pending_shield_layers
	for child in _shield_container.get_children():
		child.queue_free()
	if layers <= 0:
		return
	var ring := ShieldRing.new()
	ring.setup(layers, 1.0)
	ring.z_index = 3
	_shield_container.add_child(ring)


func _on_pickup_body_entered(body: Node2D) -> void:
	if body.is_in_group("powerups") and body.has_method("start_magnet"):
		body.start_magnet(self)
