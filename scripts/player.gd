## Player — 玩家飞船控制器（外观层）
##
## 编排 MotionController / CombatController / FeedbackController / ActionRouter 的执行顺序。
## 不再直接实现移动、战斗、动画逻辑，而是委托给子组件。
##
## 多人设计：每个玩家节点的 multiplayer_authority = 该玩家的 peer_id。
## 单机模式下 multiplayer_authority 默认为 1（服务器），与原逻辑兼容。
extends CharacterBody2D

signal died
signal downed_changed(is_downed: bool)
signal revive_progress_changed(ratio: float)

## ── 倒地 / 救援（2 人合作）────────────────────────────────
##
## 原来阵亡 = 节点直接 despawn，人变成无载具旁观者直到队友也死。
## 这是合作体验最大的坑：一个人失误，整局就变成"看别人打"。
## 现在联机下一次死亡进入倒地状态，队友可以救援。
##
## 参数（见 Design_Decisions「倒地与救援」）：
##   倒地期间：不能射击、移速 30%、每 2 秒流失 10% 最大生命
##   救援：靠近 60px 内**按住 1.2 秒**——这个数字是关键，
##        必须有代价，否则合作退化成"走过去按一下键"
const DOWNED_BLEED_INTERVAL: float = 2.0
const DOWNED_BLEED_RATIO: float = 0.10
const DOWNED_MAX_SECONDS: float = 20.0
const REVIVE_HOLD_SECONDS: float = 1.2
const REVIVE_RADIUS: float = 60.0
const REVIVE_HEALTH_RATIO: float = 0.5
const DOWNED_MOVE_MULTIPLIER: float = 0.3

var is_downed: bool = false
var _downed_left: float = DOWNED_MAX_SECONDS
var _downed_bleed_timer: float = DOWNED_BLEED_INTERVAL
var _revive_hold: float = 0.0


func get_downed_time_left() -> float:
	return _downed_left if is_downed else 0.0


func get_revive_ratio() -> float:
	return clampf(_revive_hold / REVIVE_HOLD_SECONDS, 0.0, 1.0)


## 进入倒地。联机且队友仍在时才会走到这里。
func go_downed() -> void:
	if is_downed:
		return
	is_downed = true
	_downed_left = DOWNED_MAX_SECONDS
	_downed_bleed_timer = DOWNED_BLEED_INTERVAL
	_revive_hold = 0.0
	## 倒地时清空无敌帧，否则会带着 1 秒无敌显得"倒地还能挨打免疫"，
	## 队友靠近时被弹幕连累会非常挫败
	_invincible_timer = 0.0
	set_process(true)
	downed_changed.emit(true)
	revive_progress_changed.emit(0.0)


## 队友按住救援键满 1.2 秒后调用。Host 权威校验。
func complete_revive() -> bool:
	if not is_downed:
		return false
	is_downed = false
	_downed_left = 0.0
	_revive_hold = 0.0
	GameState.revive_player(peer_id, REVIVE_HEALTH_RATIO, 3.0, 1)
	## 救回来给 3 秒无敌，避免刚站起来就被同一波弹幕带走
	_invincible_timer = 3.0
	downed_changed.emit(false)
	revive_progress_changed.emit(0.0)
	return true


## 倒地期间的推进：流血倒计时 + 救援按住进度
func _tick_downed(delta: float) -> void:
	_downed_left -= delta
	_downed_bleed_timer -= delta
	if _downed_bleed_timer <= 0.0:
		_downed_bleed_timer = DOWNED_BLEED_INTERVAL
		var mhp: int = maxi(1, GameState.get_max_health(peer_id))
		GameState.take_damage(maxi(1, int(float(mhp) * DOWNED_BLEED_RATIO)), peer_id)


## 由 Host 每帧调用：判断是否有人在救援本机
func update_revive_hold(helping: bool, delta: float) -> void:
	if not is_downed:
		return
	var target: float = REVIVE_HOLD_SECONDS if helping else 0.0
	_revive_hold = move_toward(_revive_hold, target, delta)
	revive_progress_changed.emit(get_revive_ratio())

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
var _graze_area: Area2D = null
var _shield_container: Node2D
var ShieldRing = preload("res://scripts/shield_ring.gd")
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
	## 必须递归设置：player.tscn 里的 MultiplayerSynchronizer 是子节点，
	## 不递归的话它的权威会停在默认值 1（Host），造成两个方向都错位：
	##   - Host 上 P2 幽灵的同步器权威=Host → Host 把幽灵坐标广播给客户端，
	##     客户端本机 P2 被拽向幽灵位置（Host 幽灵不动，玩家像被橡皮筋拽住）
	##   - 客户端本机 P2 的同步器权威=Host → 客户端不发送自己的位置，
	##     Host 上的幽灵永远冻结在出生点
	## 递归后：每个玩家节点只有自己的持有端发送坐标，对端只负责应用。
	set_multiplayer_authority(peer_id, true)


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
	_init_graze()


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


func _on_graze_area_entered(area: Area2D) -> void:
	## 只算敌方子弹：我方子弹也从同一层穿过，会被一并检测到
	if area.get("_is_player_bullet") == true:
		return
	## 联机下擦弹必须由"自己那一端"结算再同步，不能两端各算一份，
	## 否则同一个擦弹会被记两次、层数翻倍
	if NetworkManager.is_online() and not multiplayer.is_server():
		if peer_id != multiplayer.get_unique_id():
			return
	GameState.add_graze(Time.get_ticks_msec())
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
		## 倒地：Host 权威推进流血倒计时；其他端只读同步状态，不自行计时
		if not mp_active or multiplayer.is_server():
			_tick_downed(delta)
		## 倒地仍能挪动（移速 30%），但不能射击——不能动的救援目标没有博弈
		_motion.update(delta, GameState.get_move_speed_multiplier()
			* DOWNED_MOVE_MULTIPLIER, get_viewport_rect().size)
		_feedback.update(delta)
		return

	_motion.update(delta, GameState.get_move_speed_multiplier(), get_viewport_rect().size)
	_combat.update(delta)
	_feedback.update(delta)


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
		var local_peer_id := multiplayer.get_unique_id()
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
	_update_shield_recharge(delta)


## ── 公开入口 ──────────────────────────────────────────

func request_action(action: String) -> void:
	_action_router.request_action(action)


func take_damage(amount: float = 1.0) -> void:
	if _invincible_timer > 0:
		return
	## 已倒地：不再重复触发死亡流程，只吃流血伤害
	if is_downed:
		GameState.take_damage(maxi(1, int(round(amount))), peer_id)
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
		_feedback.spawn_explosion()
		died.emit()
		queue_free()

func force_kill() -> void:
	if not GameState.is_player_alive(peer_id):
		return
	var lethal_damage := GameState.get_current_health(peer_id) + GameState.get_shield_layers(peer_id) + 9999
	GameState.take_damage(lethal_damage, peer_id)
	_feedback.spawn_explosion()
	died.emit()
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
	if body.is_in_group("powerups") and body.has_method("start_magnet"):
		body.start_magnet(self)

func _on_pickup_area_entered(area: Area2D) -> void:
	if area.is_in_group("powerups") and area.has_method("start_magnet"):
		area.start_magnet(self)
