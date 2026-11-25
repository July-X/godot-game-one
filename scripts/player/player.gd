## Player — 玩家飞船控制器（外观层）
##
## 编排 MotionController / CombatController / FeedbackController / ActionRouter 的执行顺序。
## 不再直接实现移动、战斗、动画逻辑，而是委托给子组件。
##
## 多人设计：peer_id 标识原战斗槽位，multiplayer_authority 指向当前的传输身份。
## 单机模式下 multiplayer_authority 默认为 1（服务器），与原逻辑兼容。
extends CharacterBody2D

signal died
## 倒地冻结位置，原节点留给房主救援或淘汰。
var is_downed := false
var _rescue_protected_until := 0
var _collision_layer_before_down := 0


func go_downed(at: Vector2) -> void:
	if is_downed:
		return
	is_downed = true
	global_position = at
	reset_physics_interpolation()
	_invincible_timer = 0.0
	_action_router.consume_actions()
	_combat.cancel_pending_casts()
	_motion.stop_for_downed()
	_feedback.set_downed_visual(true)
	remove_from_group("player")
	_collision_layer_before_down = collision_layer
	set_deferred("collision_layer", 0)
	var stick := get_parent().get_node_or_null("MobileControls")
	if stick and _is_locally_controlled_player():
		stick.cancel_move_touch()


func complete_revive() -> void:
	if not is_downed:
		return
	is_downed = false
	_rescue_protected_until = Engine.get_physics_frames() + Engine.physics_ticks_per_second
	_feedback.set_downed_visual(false)
	add_to_group("player")
	set_deferred("collision_layer", _collision_layer_before_down)

func clear_lan_input() -> void:
	_action_router.consume_actions()
	_combat.cancel_pending_casts()
	_motion.stop_for_downed()

func extend_rescue_protection(ticks: int) -> void:
	if _rescue_protected_until > 0:
		_rescue_protected_until += ticks


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
## 首卡试飞的选卡阶段：允许触摸走位，但不运行战斗、技能或冷却。
var trial_draft_movement_only: bool = false

var _pickup_area: Area2D
var _graze_area: Area2D = null
var _shield_container: Node2D
var ShieldRing = preload("res://scripts/visuals/shield_ring.gd")
var _shield_dirty: bool = false
var _pending_shield_layers: int = 0
const SHIELD_RECHARGE_INTERVAL: float = 8.0
var _shield_recharge_timer: float = SHIELD_RECHARGE_INTERVAL


func _ready() -> void:
	_init_multiplayer()
	_init_components()
	_connect_signals()


func _init_multiplayer() -> void:
	if name.is_valid_int():
		peer_id = name.to_int()
	# 位置由 Main 手动同步，引擎权限仍递归跟随当前传输。
	var wire := NetworkManager.peer_for_slot(peer_id)
	set_multiplayer_authority(wire if wire > 0 else 1, true)


func _init_components() -> void:
	var loads := Time.get_ticks_usec()
	_action_router = _add_component("ActionRouter", "res://scripts/player/action_router.gd")
	_motion = _add_component("MotionController", "res://scripts/player/motion_controller.gd")
	_motion.move_speed = move_speed
	_motion.mouse_sensitivity = mouse_sensitivity
	if OS.has_feature("android") or OS.has_feature("ios"):
		_motion.mobile_mode = true

	_combat = _add_component("CombatController", "res://scripts/player/combat_controller.gd")
	_feedback = _add_component("FeedbackController", "res://scripts/player/feedback_controller.gd")
	NetworkManager.release_remix_pilot_scripts()
	var appearance := Time.get_ticks_usec()
	_feedback.update_appearance()
	var configured := Time.get_ticks_usec()
	_combat.update_pickup_radius()

	_pickup_area = $PickupArea
	_shield_container = $ShieldContainer
	_init_graze()
	if get_parent().has_method("_trace_entry_load"):
		get_parent()._trace_entry_load("player_resources", {"slot": peer_id, "components_us": appearance - loads,
			"appearance_us": configured - appearance, "configure_us": Time.get_ticks_usec() - configured})


## 擦弹判定：GrazeArea 是一个半径 34px 的检测环，
## 比玩家本体判定点（12px）大得多，所以"进了环但没被击中"就是擦弹。
## 关键实现细节：**每颗子弹只计一次**——Area2D 的 area_entered 只在进入时
## 触发一次，子弹如果一直贴在环内移动不会重复计数，所以这里不需要额外去重表。
func _init_graze() -> void:
	_graze_area = $GrazeArea as Area2D
	if _graze_area == null:
		return
	if not _graze_area.area_entered.is_connected(_on_graze_area_entered):
		_graze_area.area_entered.connect(_on_graze_area_entered)
	var circle: CircleShape2D = $GrazeArea/CollisionShape2D.shape
	var base_radius := circle.radius
	circle.radius = base_radius + GameState.get_graze_radius_bonus(peer_id)
	UpgradeDraft.card_chosen.connect(func(pid: int, card: String, _index: int):
		if pid == peer_id and card == "graze_focus":
			circle.radius = base_radius + GameState.get_graze_radius_bonus(pid)
	)


func _on_graze_area_entered(area: Area2D) -> void:
	## 只算敌方子弹：我方子弹也从同一层穿过，会被一并检测到
	if area.get("_is_player_bullet") == true:
		return
	## 联机下擦弹必须由"自己那一端"结算再同步，不能两端各算一份，
	## 否则同一个擦弹会被记两次、层数翻倍
	if NetworkManager.is_online() and not multiplayer.is_server():
		if peer_id != NetworkManager.local_player_id():
			return
	GameState.add_graze(Time.get_ticks_msec(), peer_id)
	SFX.play_graze_tick(GameState.get_graze_stacks())
	_flash_grazed_bullet(area)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("emit_hit_feedback"):
		## 擦弹只给极轻的震屏：它发生得很频繁，重了会毁掉弹幕可读性
		scene.emit_hit_feedback(0.02, 0.0, false)


## 被擦到的子弹闪一下白，给玩家"碰到了"的瞬时确认
func _flash_grazed_bullet(area: Area2D) -> void:
	var sprite := area.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.modulate = Color(2.2, 2.2, 2.2, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.12)


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
		_pickup_area.area_entered.connect(_on_pickup_area_entered)
	GameState.shield_changed.connect(_on_shield_changed)
	## 初始护盾为 0，8 秒充能后获得
	_pending_shield_layers = 0
	_rebuild_shields()
	# 摇杆先于玩家挂在战斗场景；入场时 current_scene 可能还在切换。
	var mc := get_parent().get_node_or_null("MobileControls")
	if mc and _is_locally_controlled_player():
		_motion.mobile_mode = true
		mc.move_input.connect(_motion.handle_mobile_move)


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.game_running or is_downed:
		return
	if event is InputEventMouseMotion and not _motion.mobile_mode:
		_motion.handle_mouse_motion(event)
	_action_router.handle_keyboard_event(event)


func _physics_process(delta: float) -> void:
	if not GameState.game_running:
		return
	if trial_draft_movement_only:
		if _motion.mobile_mode:
			_motion.update(delta, GameState.get_move_speed_multiplier(), NetworkManager.battle_size(self))
			_feedback.update(delta)
		return
	var mp_active := _is_multiplayer_session_active()
	var locally_controlled := _is_locally_controlled_player()
	## 冷却推进与玩家状态同步：
	## - Host 需要为所有玩家都推进 CD（包括加入者对应节点）
	## - Client 仅推进本机玩家，避免非本机节点干扰
	if mp_active:
		if multiplayer.is_server() or locally_controlled:
			_tick_runtime(delta)
	else:
		_tick_runtime(delta)
	## 仅在真实多人会话中做 authority 拦截，避免单机/残留状态误伤战斗链路。
	if mp_active and not locally_controlled:
		return

	if is_downed:
		_motion._tick_dash(delta)
		_feedback.update(delta)
		return

	## 闪避：Shift 触发，位移 + 无敌帧同时给
	_consume_dash()
	_motion.update(delta, GameState.get_move_speed_multiplier(), NetworkManager.battle_size(self))
	if _motion.is_dashing():
		## 冲刺期间强制无敌，且盖过受击后的 1 秒无敌计时
		_invincible_timer = maxf(_invincible_timer, 0.05)
	_combat.update(delta)
	_feedback.update(delta)


## 把 ActionRouter 排队的 dash 动作转成实际闪避
func _consume_dash() -> void:
	for action: String in _action_router.consume_actions():
		if action != "dash":
			_action_router.request_action(action)
			continue
		if is_downed:
			continue
		if _motion.try_dash():
			SFX.play_dash()
			_feedback.trigger_dash()


## 闪避是否处于无敌帧（受击判定要放行）
func is_dash_invincible() -> bool:
	return _motion.is_dashing()


func can_dash() -> bool:
	return _motion.can_dash()


func get_dash_cooldown_ratio() -> float:
	return _motion.get_dash_cooldown_ratio()


## 本机理论极速（px/s）。敌速上限要按它来算，
## 所以对外暴露一个访问口，避免 main.gd 里写死常量后与 move_speed 脱钩。
func get_max_move_speed() -> float:
	return _motion.move_speed if _motion != null else 0.0


func _is_multiplayer_session_active() -> bool:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _is_locally_controlled_player() -> bool:
	if not _is_multiplayer_session_active():
		return true
	if has_method("is_multiplayer_authority") and is_multiplayer_authority():
		return true
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		var local_peer_id := NetworkManager.local_player_id()
		return peer_id == local_peer_id
	## 兜底：联机初始化早期未取到 peer 时，先允许本机节点执行，避免战斗逻辑被误拦截。
	return true


func _compute_shield_max_hp() -> int:
	var bp := GameState.get_bullet_power_level(peer_id)
	var mhp := GameState.get_max_health(peer_id)
	var bonus := GameState.get_shield_bonus(peer_id)
	return maxi(1, int((10 + bp * 2 + int(mhp * 0.2)) * 0.5) + bonus)

func _update_shield_recharge(delta: float) -> void:
	## 充能间隔可被「护盾电容」卡缩短，所以每帧从 GameState 读而不是缓存常量
	var interval: float = GameState.get_shield_interval(peer_id)
	if GameState.get_shield_layers(peer_id) > 0:
		_shield_recharge_timer = interval
		return
	_shield_recharge_timer -= delta
	if _shield_recharge_timer <= 0.0:
		_shield_recharge_timer = interval
		var max_shield := _compute_shield_max_hp()
		GameState.set_shield_layers(peer_id, max_shield)

func _tick_runtime(delta: float) -> void:
	_invincible_timer = max(_invincible_timer - delta, 0.0)
	GameState.tick_skill_cooldown(delta, peer_id)
	GameState.tick_laser_cooldown(delta, peer_id)
	if not is_downed:
		_update_shield_recharge(delta)


## ── 公开入口 ──────────────────────────────────────────

func request_action(action: String) -> void:
	if not is_downed:
		_action_router.request_action(action)


func take_damage(amount: float = 1.0) -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	if is_downed or Engine.get_physics_frames() < _rescue_protected_until \
			or _invincible_timer > 0 or _motion.is_dashing():
		return
	var actual_damage: int = _normalize_incoming_damage(amount)
	if actual_damage <= 0:
		return
	var old_health: int = GameState.get_current_health(peer_id)
	var old_shields: int = GameState.get_shield_layers(peer_id)
	var is_dead := GameState.take_damage(actual_damage, peer_id)
	var new_health: int = GameState.get_current_health(peer_id)
	var new_shields: int = GameState.get_shield_layers(peer_id)
	if new_health < old_health or new_shields < old_shields:
		_invincible_timer = 1.0
		_feedback.trigger_hit()
	if is_dead:
		_emit_knockout()

func force_kill() -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	if Engine.get_physics_frames() < _rescue_protected_until or not GameState.is_player_alive(peer_id):
		return
	var lethal_damage := GameState.get_current_health(peer_id) + GameState.get_shield_layers(peer_id) + 9999
	GameState.take_damage(lethal_damage, peer_id)
	_emit_knockout()

func _emit_knockout() -> void:
	_feedback.spawn_explosion()
	died.emit()
	# 房主的同步回调可以把这架飞机原地留作待救目标。
	if not is_downed:
		queue_free()

func _normalize_incoming_damage(amount: float) -> int:
	if amount <= 0.0:
		return 0
	if GameState.get_shield_layers(peer_id) > 0:
		return maxi(1, int(ceil(amount)))
	if amount < 1.0:
		return 1 if randf() < amount else 0
	return maxi(1, int(round(amount)))


func on_level_up() -> void:
	_feedback.update_appearance()
	_combat.update_pickup_radius()
	_feedback.play_level_up_effect()


## ── 护盾 ──────────────────────────────────────────────

func _on_shield_changed(changed_peer_id: int, layers: int) -> void:
	if changed_peer_id != peer_id:
		return
	_pending_shield_layers = layers
	_rebuild_shields()


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
	if not is_downed and body.is_in_group("powerups") and body.has_method("start_magnet"):
		body.start_magnet(self)

func _on_pickup_area_entered(area: Area2D) -> void:
	if not is_downed and area.is_in_group("powerups") and area.has_method("start_magnet"):
		area.start_magnet(self)
