## Main — 主游戏场景控制器
## 多人模式：Host 通过显式 RPC 广播玩家/敌人生成与同步，避免依赖自动场景复制。
## 服务器（Host peer_id=1）控制所有敌人生成和 GameState 广播；
## 客户端（Client peer_id=2）只渲染和响应输入。
##
## 单机兼容：NetworkManager.is_online() 为 false 时走原有单人逻辑。
extends Node2D

const MotionController = preload("res://scripts/player/motion_controller.gd")
const Boss = preload("res://scripts/battle/enemies/boss/boss.gd")

var _hit_effect_scene = preload("res://scenes/effects/hit_effect.tscn")
var _bullet_scene = preload("res://scenes/entities/bullet.tscn")
var _laser_scene = preload("res://scenes/entities/laser_bolt.tscn")
var _boss_ultimate_laser_visual_script = preload("res://scripts/battle/enemies/boss/boss_ultimate_laser_visual.gd")
var _wave_director_script = preload("res://scripts/battle/wave_director.gd")
var _player_scene = preload("res://scenes/entities/player.tscn")
var _enemy_scene = preload("res://scenes/entities/enemy.tscn")
var _elite_scene = preload("res://scenes/entities/elite.tscn")
var _boss_scene = preload("res://scenes/entities/boss.tscn")
var _asteroid_scene = preload("res://scenes/entities/asteroid.tscn")
var _powerup_scene = preload("res://scenes/entities/powerup.tscn")
var _hud_scene = preload("res://scenes/ui/hud.tscn")
var _mobile_controls_scene = preload("res://scenes/ui/mobile_controls.tscn")

var _player: Node2D = null
var _hud: Node = null
var _elite: Node2D = null
var _boss: Node2D = null
var _boss_laser_visual: Node2D = null
var _boss_laser_stamp := -1
## 统一震屏入口（trauma 累加模型，见 camera_shake.gd）。
## 各处事件只管调 add_shake()，不要各自去写 camera.offset——那样多处震动
## 会互相覆盖而不是叠加。旧路径 powerup.gd 仍用 screen_shake 场景，由
## _spawn_shake 转发到这里。
var _camera_shake: Node = null
## 波次编排器：接管全部杂兵投放（阵型 / 节奏 / 章节主题）。
## Host 权威运行；单机同样运行。客户端不调用，出怪仍走 _rpc_spawn_enemy 广播，
## 所以联机不新增任何同步包（见 docs/architecture.md §12）。
var _wave_director: Node = null
var _last_wave_phase_text: String = ""
var _boss_variant_cycle: Array[int] = []
var _boss_variant_last: int = 0
var _boss_fight_active: bool = false
var _pending_boss_level: int = 0
## 旧的 `_enemy_spawn_timer` / `_difficulty_timer`（间隔刷怪 + 8 秒脉冲）已删除，
## 杂兵投放改由 `_wave_director` 的乐句节拍统一负责。
var _asteroid_timer: float = 0.0

## 多人模式：存储所有已生成的玩家节点（peer_id → Node）
var _players: Dictionary = {}

## 多人模式：实体追踪（entity_id → Node）
var _next_entity_id: int = 1000
var _entities: Dictionary = {}
var _entity_target_positions: Dictionary = {}
## { peer_id : 远端玩家节点的目标坐标 }，客户端插值用
var _player_target_positions: Dictionary = {}
var _despawned_entity_ids: Dictionary = {}
var _pending_pickup_feedback: Array[Dictionary] = []
var _lan_frozen_frame := -1
var _lan_frozen_msec := 0
var _lan_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _lan_message: Label
const PLAYER_ENTRY_RETRY_MS := 100
const PLAYER_ENTRY_TIMEOUT_MS := 3000
var _player_entry_deadline := 0
var _next_player_entry_request := 0
var _player_entry_ready := false
var _player_entry_message: Label
var _initial_guest_volley_sent := false
var _entry_shot_trace := false
var _entry_shot_trace_counts: Dictionary = {}
var _entity_sync_timer: float = 0.0
var _health_sync_timer: float = 0.0
var _player_report_timer: float = 0.0
## 坐标上报计数（诊断用）：sent 在客户端统计，received 在 Host 统计
var _player_report_received: int = 0
var _player_report_sent: int = 0
var _player_report_rejected: int = 0
var _last_entity_resync_request_msec: int = 0
var _pending_impact := PackedFloat32Array()
var _boss_reward_claimed_peers: Dictionary = {}
const ENTITY_SYNC_INTERVAL: float = 0.022
const ENTITY_SYNC_STRIDE: int = 3
const ENTITY_SHIELD_SYNC_STRIDE: int = 3
const ENTITY_ROTATION_SYNC_STRIDE: int = 2
const ENTITY_RESYNC_REQUEST_INTERVAL_MSEC: int = 750
## 星空平铺贴图边长（像素）。必须与 star 落点避开边缘的规则配套：
## 贴图内不放跨界星星，滚动时按该边长取模循环即可无缝衔接。
## 取 512 而非更小：256 的贴图在 1280 宽的屏幕上会横排重复 5 次，
## 肉眼能直接看出网格状重复（实测截图确认）；512 只重复 2.5 次。
const Palette = preload("res://scripts/visuals/palette.gd")
## 玩家极速兜底值（motion_controller.move_speed 默认 260）。
## 正常情况走 player.get_max_move_speed()，这里只作为玩家节点尚未就绪时的回退。
const PLAYER_MOVE_SPEED_FALLBACK: float = 260.0
## 敌人移动速度上限 = 玩家极速的 80%。
## 弹幕可读性是弹幕射击的第一支柱：玩家唯一的规避手段是走位，
## 敌人一旦快过玩家，玩家就既追不上也躲不开，画面必然糊成一片。
## 原公式 12 级就让 type2 达到 277 px/s（玩家 260）、30 级 1716 px/s。
const ENEMY_SPEED_MAX_RATIO: float = 0.8
const ENEMY_SPEED_MIN: float = 40.0
## 敌速随等级的成长斜率（原为 level*6，太陡）
const ENEMY_SPEED_PER_LEVEL: float = 3.0
const ENEMY_SPEED_PER_TYPE: float = 8.0
## 敌速只吃一点点精英乘区：速度是可读性，血量才是成长感
const ENEMY_SPEED_ELITE_STEP: float = 0.01
const ENEMY_SPEED_ELITE_MAX: float = 1.3
## 精英乘区封顶（原为 1 + 场次*0.05 无上限，20 级已 3.85、40 级 11.7）
const POST_ELITE_MULT_STEP: float = 0.02
const POST_ELITE_MULT_MAX: float = 2.2
## 刷怪密度控制。
## 间隔下限从 0.2 抬到 0.45：0.2s 意味着每秒 5 只，后期同屏数量只增不减，
## 弹幕互相重叠后就没有可读性可言了。
const ENEMY_SPAWN_MIN_INTERVAL: float = 0.45
## 同屏敌人硬上限
const ENEMY_SCREEN_CAP: int = 20
## 命中定格（hitstop）：把 time_scale 压到 HITSTOP_SCALE 维持极短时间再弹回，
## 让"打中了"这一瞬间被身体感知到。只在单机生效（联机见 emit_hit_feedback）。
const HITSTOP_SCALE: float = 0.05
## 各事件的震屏强度分级。日常命中要轻，里程碑事件才允许到 0.45 以上，
## 否则玩家会觉得画面一直在抖、反而读不清弹幕。
const SHAKE_HIT: float = 0.06
const SHAKE_ENEMY_DEATH: float = 0.10
const SHAKE_PLAYER_HURT: float = 0.32
const SHAKE_ELITE_SHIELD_BREAK: float = 0.45
const SHAKE_ELITE_DEATH: float = 0.55
const SHAKE_BOSS_PHASE: float = 0.40
const SHAKE_EXPLOSION: float = 0.60
const SHAKE_LASER_CHARGE: float = 0.50
## 房主用物理帧判定倒地截止时间。
var _rescue_expires_at := 0
var _hitstop_left: float = 0.0
var _hitstop_target: float = 1.0
var _hitstop_last_usec: int = 0
## 玩家位置同步：[peer_id, x, y, rotation]，与实体同步同频（约 45Hz）
const PLAYER_SYNC_STRIDE: int = 4
## 待发送的子弹生成数据（Host → Client 或 Client → Host）
var _pending_bullet_spawns: Array = []
var _pending_scatter_spawns: Array = []
var _pending_laser_spawns: Array = []
var _alive_players: Dictionary = {}
var _fallback_in_progress: bool = false
var _last_elite_shield_break_banner_msec: int = -1000000

const MODE_SWITCH_PROMPT_HOLD_SECONDS: float = 5.0
const DEATH_MARQUEE_HOLD_SECONDS: float = 0.5
const DEATH_MARQUEE_FADE_SECONDS: float = 3.0

@onready var _bg_color: ColorRect = $Backdrop/BgColor
@onready var _backdrop: CanvasLayer = $Backdrop

var _camera_shake_script = preload("res://scripts/visuals/camera_shake.gd")


func _spawn_shake() -> void:
	## 炸弹拾取的震屏。转发到统一的 trauma 入口。
	add_shake(SHAKE_EXPLOSION)


## 累加震屏强度。intensity 语义：0.1 轻微 / 0.3 明显 / 0.6 强烈 / 1.0 极限
func add_shake(intensity: float) -> void:
	if _camera_shake == null:
		return
	_camera_shake.add_trauma(intensity)


func add_boss_laser_hit_bump() -> void:
	if is_instance_valid(_camera_shake):
		_camera_shake.add_soft_hit_bump()


## 统一反馈入口：震屏 + 命中定格 + 音效
## design 见 docs/Design_Decisions.md「命中反馈链」。
## hitstop 只在单机生效：联机会改变物理步进节奏导致两端 desync，
## 联机下降级为"只震屏 + 只出音效"，保证两端表现一致。
func emit_hit_feedback(intensity: float, hitstop_seconds: float = 0.0,
		with_sound: bool = true) -> void:
	add_shake(intensity)
	if with_sound:
		SFX.play_hit_confirm(intensity)
	if hitstop_seconds > 0.0 and not NetworkManager.is_online():
		## 先判断"是否已经在定格中"，再更新倒计时。
		## 只有不在定格中时才记录要恢复到的速度：否则定格期间再触发一次，
		## `_hitstop_target` 会被写成 0.05，结束时把 time_scale 恢复成 0.05，
		## 整局就永久停在 5% 速度了。
		var was_active: bool = _hitstop_left > 0.0
		_hitstop_left = maxf(_hitstop_left, hitstop_seconds)
		if not was_active:
			_hitstop_target = Engine.time_scale
		Engine.time_scale = HITSTOP_SCALE


func _ready() -> void:
	_entry_shot_trace = OS.get_cmdline_user_args().has("--entry-shot-trace")
	_hitstop_last_usec = Time.get_ticks_usec()
	_wave_director = _wave_director_script.new()
	_wave_director.name = "WaveDirector"
	_wave_director.phase_changed.connect(_on_wave_phase_changed)
	add_child(_wave_director)
	## 显式复位：预置开局预算，让第一波阵型在 ~1.6 秒后就进场，
	## 而不是等预算从 0 攒满 3 点（约 3.4 秒空屏）。
	_wave_director.reset()
	_camera_shake = _camera_shake_script.new()
	_camera_shake.name = "CameraShake"
	add_child(_camera_shake)
	if get_viewport() and not get_viewport().size_changed.is_connected(_center_camera_on_viewport):
		get_viewport().size_changed.connect(_center_camera_on_viewport)
	set_process(true)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_center_camera_on_viewport()
	if OS.has_feature("android") or OS.has_feature("ios"):
		_spawn_mobile_controls()
	_spawn_hud()
	GameState.reset_game()
	_rpc_set_boss_bg(false)
	GameState.level_changed.connect(_on_level_up)
	GameState.elite_spawn_requested.connect(_on_elite_spawn_requested)
	GameState.boss_spawn_requested.connect(_on_boss_spawn_requested)
	GameState.game_over.connect(_on_game_over_triggered)
	GameState.rescue_synced.connect(_on_rescue_synced)
	_debug_log_variant_assets()
	var online := NetworkManager.is_online()
	print("[Main] online=", online)
	## 多人：Host 负责权威生成，Client 通过 RPC 复位玩家列表
	if online and multiplayer.is_server():
		## 注册子弹批量刷出处理（每帧 flush）
		set_process(true)

	## 多人模式：订阅连接/断线信号，服务器端负责生成所有玩家
	if online:
		NetworkManager.bind_battle(self)
		NetworkManager.player_connected.connect(_on_multiplayer_player_connected)
		NetworkManager.player_disconnected.connect(_on_multiplayer_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_multiplayer_server_disconnected)
		## 房主保留权威实例，等加入端确认战斗场景已就绪再发送名单。
		if multiplayer.is_server():
			_spawn_networked_player(1)
			for wire in NetworkManager.connected_peers:
				_spawn_networked_player(NetworkManager.slot_for_peer(wire))
		if not multiplayer.is_server() or GameState.rift_remix:
			_player_entry_deadline = Time.get_ticks_msec() + PLAYER_ENTRY_TIMEOUT_MS
		if GameState.rift_remix:
			_player_entry_message = _hud.show_lan_wait()
			_player_entry_message.text = "正在同步两架飞机…"
	else:
		## 单机模式：原有逻辑
		_spawn_player()

func _debug_log_variant_assets() -> void:
	var boss_count := 0
	for i in range(1, 100):
		var p := "res://assets/sprites/enemies/boss/boss_%02d.png" % i
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			break
		boss_count += 1

	var player_count := 0
	for i in range(1, 100):
		var p := "res://assets/sprites/player/variants/lv%02d.png" % i
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			break
		player_count += 1

	print("[variants] boss=", boss_count, " player=", player_count)

func _exit_tree() -> void:
	BGM.stop_bgm()

func _spawn_player() -> void:
	_player = _player_scene.instantiate()
	_player.position = Vector2(_screen_center_x(), 500)
	add_child(_player)
	GameState.ensure_player_state(_player.peer_id)
	_alive_players[_player.peer_id] = true
	_player.died.connect(_on_player_died)


func _get_networked_player_spawn_position(p_peer_id: int) -> Vector2:
	var screen := NetworkManager.battle_size(self)
	if p_peer_id == 1:
		return Vector2(screen.x * 0.32, screen.y * 0.7)
	return Vector2(screen.x * 0.68, screen.y * 0.7)


func _spawn_networked_player(p_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _players.has(p_peer_id):
		return
	var player := _player_scene.instantiate()
	player.name = str(p_peer_id)
	player.position = _get_networked_player_spawn_position(p_peer_id)
	add_child(player)
	GameState.ensure_player_state(p_peer_id)
	_alive_players[p_peer_id] = true
	player.died.connect(_on_networked_player_died.bind(p_peer_id))
	_players[p_peer_id] = player
	## 兼容 _player 引用（指向本机玩家）
	var my_id := NetworkManager.local_player_id()
	if p_peer_id == my_id:
		_player = player
	if player.has_method("on_level_up"):
		player.on_level_up()


## 多人模式：新 peer 连接时（只在服务器端触发）
func _on_multiplayer_player_connected(p_peer_id: int) -> void:
	if multiplayer.is_server():
		_spawn_networked_player(NetworkManager.slot_for_peer(p_peer_id))
		NetworkManager.bind_battle(self)


## Host → 指定 peer：补发当前全部玩家节点（生成 + 坐标）
func _send_player_snapshot_to(peer_id: int) -> void:
	if peer_id <= 0:
		return
	var round_id := GameState.get_sync_round()
	for pid: int in _players:
		var player_node: Node2D = _players[pid]
		if is_instance_valid(player_node):
			_rpc_spawn_networked_player.rpc_id(peer_id, round_id, pid, player_node.position.x, player_node.position.y)


## 多人模式：peer 断线时清理其玩家节点
func _on_multiplayer_player_disconnected(p_peer_id: int) -> void:
	if _players.has(p_peer_id):
		var node: Node2D = _players[p_peer_id]
		if is_instance_valid(node):
			node.queue_free()
		_players.erase(p_peer_id)
	_alive_players.erase(p_peer_id)
	_player_target_positions.erase(p_peer_id)
	if multiplayer.is_server() and not _alive_players.is_empty():
		_fallback_to_single_player("队友已退出，切换为单人模式")
	elif _alive_players.is_empty() and multiplayer.is_server():
		_fallback_to_single_player("联机已断开，切换为单人模式")
	else:
		_refresh_primary_player_target()


## 多人模式：服务器断开（Client 端触发）
func _on_multiplayer_server_disconnected() -> void:
	_fallback_to_single_player("房主已退出，切换为单人模式")


func set_lan_hold(held: bool) -> void:
	if held:
		_lan_frozen_frame = Engine.get_physics_frames()
		_lan_frozen_msec = Time.get_ticks_msec()
		_lan_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var stick := get_node_or_null("MobileControls")
		if stick:
			stick.cancel_move_touch()
		for pilot in _players.values():
			if is_instance_valid(pilot):
				pilot.clear_lan_input()
		_pending_bullet_spawns.clear()
		_pending_scatter_spawns.clear()
		_pending_laser_spawns.clear()
		GameState.clear_unconfirmed_actions()
		_lan_message = _hud.show_lan_wait()
		return
	if _lan_frozen_frame < 0:
		return
	var lost_ticks := int(Engine.get_physics_frames() - _lan_frozen_frame)
	var held_msec := Time.get_ticks_msec() - _lan_frozen_msec
	GameState.extend_graze_time(held_msec)
	if _player_entry_deadline > 0:
		_player_entry_deadline += held_msec
	_lan_frozen_frame = -1
	if _rescue_expires_at > 0:
		_rescue_expires_at += lost_ticks
	for id: int in _players:
		var pilot: Variant = _players[id]
		if is_instance_valid(pilot):
			pilot.set_multiplayer_authority(maxi(1, NetworkManager.peer_for_slot(id)), true)
			pilot.extend_rescue_protection(lost_ticks)
	if is_instance_valid(_lan_message):
		_lan_message.hide()
		_lan_message.queue_free()
	Input.mouse_mode = _lan_mouse_mode

func update_lan_wait(seconds: int, synchronizing: bool) -> void:
	if is_instance_valid(_lan_message):
		_lan_message.text = ("正在同步原局" if synchronizing else "等待联机恢复") + " · %d 秒" % maxi(seconds, 0)


## 可靠同序通道先补齐属性和生成，末尾快照校验当前局号及状态序号。
func send_lan_resume_snapshot(wire: int) -> Dictionary:
	GameState.force_sync_to_peer(wire, true)
	_rpc_set_boss_bg.rpc_id(wire, _boss_fight_active)
	_send_player_snapshot_to(wire)
	var players := {}
	for id: int in _players:
		var pilot: Variant = _players[id]
		if is_instance_valid(pilot):
			players[id] = [_player_target_positions.get(id, pilot.global_position), pilot.rotation, pilot.is_downed,
				maxi(0, pilot._rescue_protected_until - _lan_frozen_frame)]
	var entities := {}
	for id: int in _entities:
		var item: Variant = _entities[id]
		if not is_instance_valid(item) or item.is_queued_for_deletion() or _despawned_entity_ids.has(id):
			continue
		_send_entity_spawn_to_peer(wire, id, item, true)
		var stats := []
		if item.has_method("get_network_health"):
			stats = [item.get_network_health(), item.get_network_max_health()]
		if item.has_method("get_network_shield") and not item is Boss:
			stats.append_array([item.get_network_shield(), item.get_network_max_shield()])
		entities[id] = [item.global_position, item.rotation, stats]
	return {"round": GameState.get_sync_round(), "sequence": GameState.next_sync_sequence() - 1,
		"players": players, "entities": entities, "bullets": _resume_bullets(), "result": not GameState.game_running}

func apply_lan_resume_snapshot(state: Dictionary) -> bool:
	if not GameState.has_received_sync(state.round, state.sequence):
		return false
	for id: int in state.players:
		if not is_instance_valid(_players.get(id)):
			return false
	for id: int in state.entities:
		if not is_instance_valid(_entities.get(id)):
			return false
	for id: int in _players.keys():
		if not state.players.has(id):
			_rpc_despawn_player(id)
	_player_target_positions.clear()
	for id: int in state.players:
		var pilot: Variant = _players[id]
		var row: Array = state.players[id]
		pilot.global_position = row[0]
		pilot.rotation = row[1]
		pilot.reset_physics_interpolation()
		if row[2]:
			_freeze_downed_player(id, row[0])
		else:
			pilot.complete_revive()
			_alive_players[id] = true
		pilot._rescue_protected_until = _lan_frozen_frame + int(row[3]) if int(row[3]) > 0 else 0
	_refresh_primary_player_target()
	for id: int in _entities.keys():
		if not state.entities.has(id):
			_rpc_despawn_entity(id)
	_entity_target_positions.clear()
	for id: int in state.entities:
		var item: Variant = _entities[id]
		var row: Array = state.entities[id]
		item.global_position = row[0]
		item.rotation = row[1]
		item.reset_physics_interpolation()
		var stats: Array = row[2]
		if not stats.is_empty():
			item.apply_network_health(stats[0], stats[1])
		if stats.size() == 4:
			item.apply_network_shield(stats[2], stats[3])
	# 重建当前权威弹幕，不重新播射击声、命中或掉落奖励。
	_restore_resume_bullets(state.bullets)
	UpgradeDraft.release_unconfirmed_choice(NetworkManager.local_player_id())
	if state.result and not _hud._game_over_panel.visible:
		_rpc_force_game_over(GameState.score, GameState.level)
	return true

func _resume_bullets() -> Array:
	var data := []
	for group in ["player_bullets", "enemy_bullets"]:
		for shot in get_tree().get_nodes_in_group(group):
			if shot.is_queued_for_deletion() or shot.get_parent() != self:
				continue
			if shot.scene_file_path == _bullet_scene.resource_path:
				data.append([shot.global_position, shot._direction.angle(), shot._damage, shot._is_player_bullet,
					shot._level, shot._speed, shot.modulate, shot.owner_peer_id, shot._lifetime, shot._has_bounced, false])
			elif shot.scene_file_path == _laser_scene.resource_path:
				data.append([shot.global_position, shot._direction.angle(), shot._damage, true,
					1, shot._speed, shot.modulate, shot.owner_peer_id, shot._lifetime, shot._has_bounced, true])
	return data

func _restore_resume_bullets(data: Array) -> void:
	for group in ["player_bullets", "enemy_bullets"]:
		for shot in get_tree().get_nodes_in_group(group):
			if shot.scene_file_path == _bullet_scene.resource_path:
				Pool.release(shot)
			elif shot.scene_file_path == _laser_scene.resource_path:
				shot.queue_free()
	for row: Array in data:
		var shot: Node2D = _laser_scene.instantiate() if row[10] else Pool.acquire("bullet", _bullet_scene)
		add_child(shot)
		if row[10]:
			shot.setup(row[0], row[1], row[2], row[7])
			shot._speed = row[5]
		else:
			shot.setup(row[0], row[1], row[2], row[3], row[4], row[5], row[7])
		shot.modulate = row[6]
		shot.set_network_ghost(true)
		shot._lifetime = row[8]
		shot.set_bounced(row[9])


## 多人死亡与救援由房主结算。
func _on_networked_player_died(peer_id: int) -> void:
	if _try_go_downed(peer_id):
		return
	_remove_networked_player(peer_id)
	if _alive_players.is_empty():
		if GameState.rescue_peer_id > 0:
			_remove_networked_player(GameState.rescue_peer_id)
			_clear_rescue()
		_finish_multiplayer_game_over(GameState.score, GameState.level)
	else:
		_refresh_primary_player_target()


func _remove_networked_player(peer_id: int) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_despawn_player.rpc(peer_id)
	_rpc_despawn_player(peer_id)


## 常规联机探针用真死亡检查断线隔离，救援专项保持此开关开启。
var rescue_enabled: bool = true


func _try_go_downed(peer_id: int) -> bool:
	if not rescue_enabled or not NetworkManager.is_online() or not multiplayer.is_server():
		return false
	if _alive_players.size() < 2 or not _alive_players.has(peer_id) or GameState.rescues_left == 0:
		return false
	var node: Variant = _players.get(peer_id)
	if not is_instance_valid(node):
		return false
	var at: Vector2 = _player_target_positions.get(peer_id, node.global_position)
	_rescue_expires_at = Engine.get_physics_frames() + GameState.RESCUE_SECONDS * Engine.physics_ticks_per_second
	GameState.set_rescue_target(peer_id, at, GameState.RESCUE_SECONDS)
	_freeze_downed_player(peer_id, at)
	_refresh_primary_player_target()
	GameState.force_sync_to_peer(-1)
	queue_redraw()
	return true


func _physics_process(_delta: float) -> void:
	_tick_rescue_window()


func _tick_rescue_window() -> void:
	var peer_id := GameState.rescue_peer_id
	if peer_id == 0 or not GameState.game_running or not NetworkManager.is_online() or not multiplayer.is_server():
		return
	var frames_left := _rescue_expires_at - Engine.get_physics_frames()
	if frames_left <= 0:
		_remove_networked_player(peer_id)
		_clear_rescue()
		_refresh_primary_player_target()
		GameState.force_sync_to_peer(-1)
		return
	var at := GameState.rescue_position
	var seconds := ceili(float(frames_left) / Engine.physics_ticks_per_second)
	if seconds != GameState.rescue_seconds:
		GameState.set_rescue_target(peer_id, at, seconds)
		queue_redraw()
	var victim: Variant = _players.get(peer_id)
	for pid: int in _alive_players:
		var rescuer: Variant = _players.get(pid)
		if not is_instance_valid(rescuer) or not is_instance_valid(victim):
			continue
		# 判定取有效的最新位置，插值只影响画面。
		var pos: Vector2 = _player_target_positions.get(pid, rescuer.global_position)
		if pos.distance_squared_to(at) <= GameState.RESCUE_RADIUS * GameState.RESCUE_RADIUS \
				and GameState.revive_player(peer_id):
			_rescue_expires_at = 0
			victim.complete_revive()
			_alive_players[peer_id] = true
			_refresh_primary_player_target()
			GameState.force_sync_to_peer(-1)
			queue_redraw()
			break


func _freeze_downed_player(peer_id: int, at: Vector2) -> void:
	var node: Variant = _players.get(peer_id)
	if is_instance_valid(node):
		node.go_downed(at)
	_alive_players.erase(peer_id)
	_player_target_positions.erase(peer_id)


func _on_rescue_synced(previous_peer_id: int, revived: bool) -> void:
	queue_redraw()
	if previous_peer_id == GameState.rescue_peer_id:
		return
	var node: Variant = _players.get(previous_peer_id)
	if revived and is_instance_valid(node):
		node.complete_revive()
		_alive_players[previous_peer_id] = true
	if GameState.rescue_peer_id > 0:
		_freeze_downed_player(GameState.rescue_peer_id, GameState.rescue_position)
	_refresh_primary_player_target()


func _clear_rescue() -> void:
	GameState.set_rescue_target(0)
	_rescue_expires_at = 0
	queue_redraw()


func _fallback_to_single_player(message: String = "") -> void:
	if _fallback_in_progress:
		return
	_fallback_in_progress = true
	var reload_delay := 0.0
	if not message.is_empty():
		reload_delay = MODE_SWITCH_PROMPT_HOLD_SECONDS
		_show_death_marquee_text(message, MODE_SWITCH_PROMPT_HOLD_SECONDS)
	_clear_network_runtime_state()
	NetworkManager.disconnect_network()
	_center_camera_on_viewport()
	call_deferred("_reload_as_single_player_clean", reload_delay)

func _clear_network_runtime_state() -> void:
	UpgradeDraft.clear_drafts()
	_clear_rescue()
	_pending_bullet_spawns.clear()
	_pending_scatter_spawns.clear()
	_pending_laser_spawns.clear()
	_entity_target_positions.clear()
	_player_target_positions.clear()
	_despawned_entity_ids.clear()
	_pending_pickup_feedback.clear()
	_boss_reward_claimed_peers.clear()
	_entities.clear()
	_players.clear()
	_alive_players.clear()
	_clear_runtime_entities_on_game_over()
	if Pool and Pool.has_method("reset_all"):
		Pool.reset_all()

func _reload_as_single_player_clean(delay_seconds: float = 0.0) -> void:
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")

@rpc("authority", "reliable", "call_remote")
func _rpc_despawn_player(p_peer_id: int) -> void:
	if not _players.has(p_peer_id):
		return
	var was_local_player := NetworkManager.is_online() \
		and multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer != null \
		and p_peer_id == NetworkManager.local_player_id()
	var node: Node = _players[p_peer_id]
	if is_instance_valid(node):
		node.queue_free()
	_players.erase(p_peer_id)
	_alive_players.erase(p_peer_id)
	_player_target_positions.erase(p_peer_id)
	if _player != null and is_instance_valid(_player) and _player.name == str(p_peer_id):
		_player = null
	if was_local_player and not _alive_players.is_empty():
		_show_death_marquee_text("你已坠毁，等待队友继续战斗")

func _spawn_hud() -> void:
	_hud = _hud_scene.instantiate()
	add_child(_hud)


## 命中定格的推进：用**真实时间**计时，而不是 `_process` 的 delta。
## `Engine.time_scale` 会把 delta 一起缩放，time_scale=0.05 时倒计时会慢 20 倍，
## 60ms 的定格变成 1.2 秒，整局动作变得黏滞——这是 hitstop 最常见的实现错误。
## 所以这里自己用 `Time.get_ticks_usec()` 算真实间隔。
func _tick_hitstop() -> void:
	var now_usec: int = Time.get_ticks_usec()
	var real_delta: float = float(now_usec - _hitstop_last_usec) / 1000000.0
	_hitstop_last_usec = now_usec
	if _hitstop_left <= 0.0:
		if Engine.time_scale != _hitstop_target:
			Engine.time_scale = _hitstop_target
		return
	_hitstop_left -= real_delta
	if _hitstop_left <= 0.0:
		_hitstop_left = 0.0
		Engine.time_scale = _hitstop_target

func _spawn_mobile_controls() -> void:
	if not has_node("MobileControls"):
		add_child(_mobile_controls_scene.instantiate())

func _process(delta: float) -> void:
	_tick_hitstop()
	if _player_entry_deadline > 0 and NetworkManager.is_online():
		_tick_player_entry()
	if not GameState.game_running:
		return
	_update_boss_hud()

	## 多人：Host 定期同步实体位置 + flush 子弹
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_entity_sync_timer -= delta
			if _entity_sync_timer <= 0.0 and _player_entry_ready:
				_entity_sync_timer = ENTITY_SYNC_INTERVAL
				_batch_sync_entity_positions()
				_batch_sync_players()
			_health_sync_timer -= delta
			if _health_sync_timer <= 0.0 and _player_entry_ready:
				_health_sync_timer = 0.1
				_batch_sync_entity_health()
		else:
			# _player 可能是观战时供敌人瞄准的队友。只发送本机仍在行动的飞机。
			var local_id := NetworkManager.local_player_id()
			var local_pilot: Variant = _players.get(local_id)
			if _alive_players.has(local_id) and is_instance_valid(local_pilot):
				_player_report_timer -= delta
				if _player_report_timer <= 0.0:
					_player_report_timer = ENTITY_SYNC_INTERVAL
					_player_report_sent += 1
					_rpc_report_player_state.rpc_id(1, local_id,
						local_pilot.global_position.x, local_pilot.global_position.y, local_pilot.rotation)
		## 客户端玩家的幽灵节点在 Host 侧也要插值
		_apply_player_interpolation(delta)
		_flush_bullet_spawns()
		_flush_laser_spawns()

	_backdrop.scroll(delta)
	if NetworkManager.is_online() and not multiplayer.is_server():
		_flush_pickup_feedback()
		_apply_entity_interpolation(delta)
		_apply_player_interpolation(delta)
		return

	if _elite != null and is_instance_valid(_elite):
		return
	if _boss != null and is_instance_valid(_boss):
		return

	_asteroid_timer -= delta
	if _asteroid_timer <= 0:
		_spawn_asteroid()
		_asteroid_timer = randf_range(2.0, 5.0)

	_tick_wave_director(delta)


## 波次编排器推进。Host 权威（单机等价于 Host），客户端不跑。
##
## 改造前这里是两个定时器：`max(1.2 - level*0.06, 0.45)` 秒一只 + 每 8 秒补一只。
## 问题不是"慢"，而是**没有形状**：同屏压力是一条恒定直线，
## 而且四通道（刷怪间隔 / 开火 CD / 敌速 / 同屏上限）在 L13~L56 全部走完增长并触顶，
## 35 个等级里玩家的"压力感"几乎不变，只剩敌血在涨。
## 编排器加的是一条**正交维度**：同样的平均强度，排出"起拍→涨潮→浪峰→退潮"的乐句。
## 章节平均速率恒等于旧版速率（tests/wave_probe.gd 门禁），所以这不是加难度，是加节奏。
func _tick_wave_director(delta: float) -> void:
	if _wave_director == null or not is_instance_valid(_wave_director):
		return
	## 联机时只有 Host 推进波次时钟。出怪点照旧走 _rpc_spawn_enemy 广播给客户端，
	## 因此两端看到的波次天然一致，不引入新的同步字段。
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	var alive: int = get_tree().get_nodes_in_group("enemies").size()
	var orders: Array = _wave_director.advance(delta, GameState.level, alive,
		NetworkManager.battle_size(self), ENEMY_SCREEN_CAP)
	for order: Dictionary in orders:
		_spawn_enemy_at(int(order["type"]), order["pos"])
	_refresh_wave_phase_hud()


## 每帧刷新乐句读数。刻意按"变化才重写"处理：
## Label 文本每帧重设会触发重排，1280×720 下 HUD 已经在满负荷边缘，
## 而这一行文本一个关卡周期只变 100 次（进度取整）。
func _refresh_wave_phase_hud() -> void:
	if _hud == null or not _hud.has_method("set_wave_phase"):
		return
	var text: String = _wave_director.phase_readout(GameState.level)
	if text == _last_wave_phase_text:
		return
	_last_wave_phase_text = text
	_hud.set_wave_phase(text, _wave_director.current_phase_color())


## 乐句换拍提示。
##
## 只在"浪峰"和"退潮"播报：这两拍是玩家需要知道边界的两拍。
## 起拍/涨潮每次都弹会变成噪音，而玩家在退潮时最该知道的是
## "接下来的 16 秒是安全的，可以专心清场和读弹道"。
func _on_wave_phase_changed(phase_index: int, phase_name: String) -> void:
	if _hud == null or not _hud.has_method("show_center_banner"):
		return
	match phase_index:
		_wave_director_script.PHASE_CREST:
			_show_elite_warning_style_banner("浪峰来袭", Color(1.0, 0.42, 0.28, 1.0))
		_wave_director_script.PHASE_LULL:
			_show_elite_warning_style_banner("退潮 · 喘息窗口", Color(0.50, 1.0, 0.70, 1.0))


func _show_elite_warning_style_banner(text: String, color: Color) -> void:
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner(text, 1.4, color)

func _apply_entity_interpolation(delta: float) -> void:
	var alpha: float = clampf(delta * 18.0, 0.0, 1.0)
	for eid in _entity_target_positions.keys():
		if not _entities.has(eid):
			continue
		var node: Node2D = _entities[eid] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var target: Vector2 = _entity_target_positions[eid]
		node.global_position = node.global_position.lerp(target, alpha)


## 远端玩家插值：45Hz 同步包 + 60fps 渲染，直接 snap 会有轻微顿挫
## Host 和 Client 都要跑：Host 侧插值的是客户端玩家的幽灵节点
func _apply_player_interpolation(delta: float) -> void:
	var alpha: float = clampf(delta * 18.0, 0.0, 1.0)
	for pid: int in _player_target_positions.keys():
		if not _players.has(pid) or not is_instance_valid(_players[pid]):
			continue
		## 本机节点只由输入驱动，任何情况下都不接受远端坐标
		if NetworkManager.is_online() and pid == NetworkManager.local_player_id():
			continue
		var pnode: Node2D = _players[pid] as Node2D
		if pnode == null:
			continue
		pnode.global_position = pnode.global_position.lerp(_player_target_positions[pid], alpha)


## 玩家、精英和 Boss 共用战场中心入场。
func _screen_center_x() -> float:
	return NetworkManager.battle_size(self).x * 0.5


## 单机跟随画布。联机让完整战场等比落入当前画布，背景和 HUD 自己排版。
func _center_camera_on_viewport() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	var view := get_viewport().get_visible_rect()
	if cam == null or not view.has_area():
		return
	var field := NetworkManager.battle_size(self)
	var online := NetworkManager.is_online()
	var fit := minf(view.size.x / field.x, view.size.y / field.y) if online else 1.0
	var shake_room := ((view.size / fit - field) * 0.5).max(Vector2.ZERO) if online else Vector2.INF
	# 只裁战斗物体。独立画布上的星空与 HUD 仍可显示在边缘以外。
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), online, Rect2(Vector2.ZERO, field))
	RenderingServer.canvas_item_set_clip(get_canvas_item(), online)
	cam.position = field * 0.5
	cam.zoom = Vector2.ONE * fit
	cam.offset = cam.offset.clamp(-shake_room, shake_room)
	_camera_shake.set_offset_limit(shake_room)
	cam.force_update_scroll()
	queue_redraw()

## 显示器坐标含窗口位置和画布缩放。GUI 事件已转为画布坐标，直接交给控件。
func world_to_screen(world_point: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * (get_canvas_transform() * world_point)

func screen_to_world(screen_point: Vector2) -> Vector2:
	var canvas_point := get_viewport().get_screen_transform().affine_inverse() * screen_point
	return get_canvas_transform().affine_inverse() * canvas_point

func _draw() -> void:
	if not NetworkManager.is_online():
		return
	if GameState.rescue_peer_id > 0 and GameState.game_running:
		var ink := Palette.DOWNED_CRITICAL if GameState.rescue_seconds <= GameState.RESCUE_WARNING_SECONDS else Palette.DOWNED_SAFE
		draw_arc(to_local(GameState.rescue_position), GameState.RESCUE_RADIUS, 0, TAU, 64, ink, 2.0, true)


## 敌速上限：优先取本机玩家的真实极速，玩家节点没就绪时用兜底常量。
## 做成访问口而不是常量，是为了让"玩家改速度"和"敌速上限"不会各改各的。
func _enemy_speed_cap() -> float:
	if _player != null and is_instance_valid(_player) and _player.has_method("get_max_move_speed"):
		var spd: float = float(_player.get_max_move_speed())
		if spd > 0.0:
			return spd * ENEMY_SPEED_MAX_RATIO
	return PLAYER_MOVE_SPEED_FALLBACK * ENEMY_SPEED_MAX_RATIO


## 敌人移动速度。设计意图见 docs/Design_Decisions.md「敌速与精英乘区拆开」：
## 速度是可读性属性，不吃满精英乘区，且硬性夹在玩家极速的 80% 以内。
## 做成 static 是为了让 tests/curve_probe.gd 能脱离场景直接回归这条曲线。
static func compute_enemy_speed(level: int, enemy_type: int,
		elite_count: int, speed_cap: float) -> float:
	var base: float = 40.0 + float(level) * ENEMY_SPEED_PER_LEVEL \
		+ float(enemy_type) * ENEMY_SPEED_PER_TYPE
	var speed_mult: float = minf(1.0 + float(elite_count) * ENEMY_SPEED_ELITE_STEP,
		ENEMY_SPEED_ELITE_MAX)
	return clampf(base * speed_mult, ENEMY_SPEED_MIN, speed_cap)


## 精英乘区：只该影响血量与开火频率，且必须有上限。
## 原公式 1 + 场次*0.05 无上限，精英每 20 击杀出一次、累计击杀随等级平方增长，
## 于是这个乘区是指数的：20 级 3.85、40 级 11.7。
static func compute_post_elite_multiplier(elite_count: int) -> float:
	return minf(1.0 + float(elite_count) * POST_ELITE_MULT_STEP, POST_ELITE_MULT_MAX)

## 在指定位置生成指定类型的杂兵。位置与类型全部由波次编排器决定，
## 这里只负责把"章节主题"叠加到基础数值上。
##
## 章节主题（wave_director.gd CHAPTER_THEMES）改的是**怎么躲**而不是"躲不躲得过"：
## 弹速变快的同时敌人变脆、开火变密，玩家的最优应对从"站桩输出"变成
## "贴脸抢输出窗口"。手感因此一章一换，而难度总量没变。
func _spawn_enemy_at(enemy_type: int, pos: Vector2, authored_health := 0, can_drop := true) -> CharacterBody2D:
	var enemy = _enemy_scene.instantiate()
	enemy.position = pos
	enemy.enemy_type = enemy_type
	var mult: float = GameState.post_elite_multiplier
	var theme: Dictionary = _wave_director.theme_for_chapter(
		_wave_director.chapter_for_level(GameState.level))
	var theme_health: float = float(theme.get("enemy_health", 1.0))
	var theme_fire: float = float(theme.get("fire_rate", 1.0))
	var theme_bullet: float = float(theme.get("bullet_speed", 1.0))
	enemy.health = authored_health if authored_health > 0 else maxi(1, int(float(int(1 + GameState.level / 2 + enemy_type) * mult) * theme_health))
	enemy.bullet_speed_mult = theme_bullet
	enemy.move_speed = compute_enemy_speed(GameState.level, enemy_type,
		GameState.elite_encounter_count, _enemy_speed_cap())
	enemy.shoot_cooldown = max((2.0 - GameState.level * 0.12) / (mult * theme_fire), 0.4)
	enemy.drop_chance = 0.20 + enemy_type * 0.12 if can_drop else 0.0
	if _player and is_instance_valid(_player):
		enemy.set_target(_player)
	enemy.enemy_died.connect(_on_enemy_died)
	add_enemy(enemy, mult)
	return enemy

## 普通波次和精英召唤先各自配置属性，再共用实体登记、生成与销毁。
func add_enemy(enemy: CharacterBody2D, spawn_multiplier := 1.0) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		enemy.entity_id = eid
		_entities[eid] = enemy
		enemy.enemy_died.connect(_on_network_enemy_died.bind(eid))
		_rpc_spawn_enemy.rpc(eid, enemy.enemy_type, enemy.position.x, enemy.position.y, enemy.health,
			enemy.move_speed, enemy.shoot_cooldown, enemy.drop_chance, spawn_multiplier,
			enemy.bullet_speed_mult)
	add_child(enemy)

func _on_enemy_died() -> void:
	pass

func _on_network_enemy_died(entity_id: int) -> void:
	_despawned_entity_ids[entity_id] = true
	_entity_target_positions.erase(entity_id)
	if _entities.has(entity_id):
		_entities.erase(entity_id)
	if multiplayer.is_server():
		_rpc_despawn_entity.rpc(entity_id, true)

## Client → Host（经 GameState 转发）：敌人受击
func _on_network_enemy_hit(entity_id: int, damage: int, attacker_peer_id: int = -1) -> void:
	if _entities.has(entity_id):
		var enemy = _entities[entity_id]
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.take_damage(damage, attacker_peer_id)

## Client → Host（经 GameState 转发）：玩家受击
func _on_network_player_hit(damage: int, target_peer_id: int) -> void:
	var player_node = _players.get(target_peer_id)
	if player_node and is_instance_valid(player_node) and player_node.has_method("take_damage"):
		player_node.take_damage(damage)

## Client → Host：请求拾取掉落物
## Client → Host：请求开始磁吸某个掉落物
func request_network_powerup_magnet(entity_id: int) -> void:
	_rpc_request_powerup_magnet.rpc_id(1, GameState.get_sync_round(), entity_id)

## Boss 死亡信号可触发结算或换场，延迟到达的掉落只属于原战场。
func spawn_boss_fragment(kind: String, world_pos: Vector2, assigned_peer_id := 0) -> void:
	if not GameState.game_running or not is_inside_tree() or is_queued_for_deletion() or get_tree().current_scene != self:
		return
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	var item = _powerup_scene.instantiate()
	item.position = to_local(world_pos)
	if assigned_peer_id > 0:
		item.set_meta("assigned_peer_id", assigned_peer_id)
	item.setup(kind)
	add_child(item)
	register_powerup_entity(item, kind)

## Host：注册掉落物实体并广播给客户端
func register_powerup_entity(powerup: Node2D, powerup_type: String) -> void:
	if not NetworkManager.is_online() or not multiplayer.is_server():
		return
	if powerup == null or not is_instance_valid(powerup):
		return
	if powerup.get("entity_id") != 0:
		return
	var eid := _next_entity_id
	_next_entity_id += 1
	powerup.entity_id = eid
	_entities[eid] = powerup
	var assigned_peer_id: int = int(powerup.get_meta("assigned_peer_id", 0))
	_rpc_spawn_powerup.rpc(GameState.get_sync_round(), eid, powerup_type, powerup.global_position, assigned_peer_id)

## 房主先从本局物品表退场，再发奖。重复调用连结算入口都到不了。
func _on_network_powerup_collected(entity_id: int, collector_peer_id: int = 0) -> void:
	if not NetworkManager.is_online() or not multiplayer.is_server() or not GameState.game_running:
		return
	var item: Variant = _entities.get(entity_id)
	if not is_instance_valid(item) or not item.is_in_group("powerups"):
		return
	var touched := collector_peer_id > 0
	var recipient := maxi(1, collector_peer_id)
	if touched and (item._magnet_owner_peer_id != recipient or not _alive_players.has(recipient)):
		return
	var kind: String = item.get_powerup_type()
	var at: Vector2 = item.global_position
	_retire_network_powerup(entity_id, at, touched)
	# 保留过期给房主的现有结算，仅实际吸到手的核心显示断环。
	var eligible := GameState.is_player_alive(recipient)
	var reward := GameState.collect_powerup(kind, recipient)
	var round_id := GameState.get_sync_round()
	var owner := recipient if eligible and recipient != 1 else 0
	_rpc_finish_powerup.rpc(round_id, entity_id, kind if touched else "", at, owner,
		reward if owner > 0 else "", GameState.next_sync_sequence() if owner > 0 else 0)
	if eligible and recipient == 1:
		on_local_powerup_feedback(kind, at, touched, reward)

func _retire_network_powerup(entity_id: int, at: Vector2, animate: bool) -> void:
	_despawned_entity_ids[entity_id] = true
	_entity_target_positions.erase(entity_id)
	var item: Variant = _entities.get(entity_id)
	_entities.erase(entity_id)
	if is_instance_valid(item) and item.is_in_group("powerups"):
		if animate:
			item.finish_network_pickup(at)
		else:
			item.queue_free()

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_powerup_magnet(round_id: int, entity_id: int) -> void:
	if not multiplayer.is_server():
		return
	if round_id != GameState.get_sync_round() or not GameState.game_running:
		return
	var item: Variant = _entities.get(entity_id)
	if not is_instance_valid(item) or not item.is_in_group("powerups"):
		return
	var requester := NetworkManager.gameplay_sender()
	var pilot: Variant = _players.get(requester)
	if not is_instance_valid(pilot) or not _alive_players.has(requester):
		return
	var pickup: CircleShape2D = pilot.get_node("PickupArea/CollisionShape2D").shape
	var drop: CircleShape2D = item.get_node("CollisionShape2D").shape
	var at: Vector2 = _player_target_positions.get(requester, pilot.global_position)
	if item.global_position.distance_to(at) <= pickup.radius + drop.radius:
		item.start_magnet(pilot)

func _spawn_asteroid() -> void:
	var asteroid = _asteroid_scene.instantiate()
	var side := randi() % 4
	var screen := NetworkManager.battle_size(self)
	match side:
		0: asteroid.position = Vector2(randf_range(60, screen.x - 60), -40)
		1: asteroid.position = Vector2(randf_range(60, screen.x - 60), screen.y + 40)
		2: asteroid.position = Vector2(-40, randf_range(60, screen.y - 60))
		3: asteroid.position = Vector2(screen.x + 40, randf_range(60, screen.y - 60))
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		asteroid.name = str(eid)
		asteroid.entity_id = eid
		_entities[eid] = asteroid
		_rpc_spawn_asteroid.rpc(eid, asteroid.position.x, asteroid.position.y)
	add_child(asteroid)

func _on_network_asteroid_destroyed(entity_id: int) -> void:
	if not multiplayer.is_server():
		return
	_despawned_entity_ids[entity_id] = true
	_entity_target_positions.erase(entity_id)
	if _entities.has(entity_id):
		var node: Node = _entities[entity_id]
		if is_instance_valid(node):
			node.queue_free()
		_entities.erase(entity_id)
	_rpc_despawn_entity.rpc(entity_id)

func _on_elite_spawn_requested() -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	if _elite != null and is_instance_valid(_elite):
		return
	call_deferred("_spawn_elite")

const ELITE_ENTRY_SECONDS := 1.5

func _elite_entry_seconds() -> float:
	return ELITE_ENTRY_SECONDS

func _spawn_elite() -> void:
	_show_elite_warning()
	GameState.elite_encounter_count += 1
	_elite = _elite_scene.instantiate()
	_elite.position = Vector2(_screen_center_x(), -60)
	var elite_mult: float = 1.0 + (GameState.elite_encounter_count - 1) * 0.1
	_elite.set_difficulty(elite_mult)
	if _player and is_instance_valid(_player):
		_elite.set_target(_player)
	_elite.elite_died.connect(_on_elite_died)
	if _elite.has_signal("shield_broken_window_started"):
		_elite.shield_broken_window_started.connect(_on_elite_shield_broken_window_started)
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		_elite.entity_id = eid
		_entities[eid] = _elite
		_elite.route_dodge_charging.connect(_publish_elite_dodge_cue.bind(eid))
		_elite.route_attack_changed.connect(_publish_elite_attack_preview.bind(eid))
		_rpc_spawn_elite.rpc(eid, elite_mult)
		_rpc_show_elite_warning.rpc()
	add_child(_elite)
	var tween := create_tween()
	tween.tween_property(_elite, "position", Vector2(_screen_center_x(), 120), _elite_entry_seconds()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_elite_shield_broken_window_started() -> void:
	var eid := -1
	if _elite != null and is_instance_valid(_elite):
		eid = int(_elite.entity_id)
	_show_elite_shield_break_banner()
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_show_elite_shield_break_banner.rpc()
		if eid > 0:
			_rpc_elite_shield_destroyed.rpc(eid)

func _show_elite_shield_break_banner() -> void:
	var now := int(Time.get_ticks_msec())
	if now - _last_elite_shield_break_banner_msec < 600:
		return
	_last_elite_shield_break_banner_msec = now
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("护盾破裂，集火窗口", 0.8, Color(1.0, 0.9, 0.35, 1.0))

func _on_elite_died() -> void:
	if _elite != null:
		var eid: int = _elite.entity_id
		if _entities.has(eid):
			_entities.erase(eid)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_rpc_despawn_entity.rpc(eid, true)
	_elite = null
	GameState.post_elite_multiplier = compute_post_elite_multiplier(GameState.elite_encounter_count)
	if _pending_boss_level > 0 and GameState.game_running:
		call_deferred("_consume_pending_boss_spawn")

func _show_elite_warning() -> void:
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("裂隙猎手接近", 3.0, Color(1.0, 0.38, 0.15, 1.0))
		return
	var warning := Label.new()
	warning.text = "警告: 精英怪 来袭"
	warning.add_theme_font_size_override("font_size", 36)
	warning.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, 1.0))
	warning.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	warning.add_theme_constant_override("shadow_outline_size", 2)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning.position = Vector2(0, 300)
	warning.size = Vector2(NetworkManager.battle_size(self).x, 60)
	warning.z_index = 100
	add_child(warning)
	var tween := create_tween()
	tween.tween_property(warning, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.2)
	tween.tween_property(warning, "modulate:a", 0.0, 0.5)
	tween.tween_callback(warning.queue_free)

## ── Boss 系统 ──────────────────────────────────────────────

func _on_boss_spawn_requested(level: int) -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	if _has_active_boss():
		return
	if not GameState.game_running:
		return
	if _is_elite_blocking_boss_spawn():
		## 精英仍在场时，缓存本次 Boss 触发，待精英死亡后立即补发
		_pending_boss_level = maxi(_pending_boss_level, level)
		return
	_pending_boss_level = 0
	_show_boss_warning()
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if not GameState.game_running:
			return
		if _is_elite_blocking_boss_spawn():
			_pending_boss_level = maxi(_pending_boss_level, level)
			return
		call_deferred("_spawn_boss", level)
	)

func _is_elite_blocking_boss_spawn() -> bool:
	if _elite == null:
		return false
	if not is_instance_valid(_elite):
		_elite = null
		return false
	if _elite.is_queued_for_deletion():
		_elite = null
		return false
	return true

func _has_active_boss() -> bool:
	if _boss == null:
		return false
	if not is_instance_valid(_boss):
		_boss = null
		return false
	if _boss.is_queued_for_deletion():
		_boss = null
		return false
	return true

func _consume_pending_boss_spawn() -> void:
	if _pending_boss_level <= 0 or not GameState.game_running:
		return
	if _is_elite_blocking_boss_spawn():
		call_deferred("_consume_pending_boss_spawn")
		return
	var pending_level: int = _pending_boss_level
	_pending_boss_level = 0
	_on_boss_spawn_requested(pending_level)

func _spawn_boss(level: int) -> void:
	if _has_active_boss():
		return
	if _is_elite_blocking_boss_spawn():
		_pending_boss_level = maxi(_pending_boss_level, level)
		return
	_enter_boss_fight_mode()
	_boss_reward_claimed_peers.clear()
	_boss = _boss_scene.instantiate()
	_boss.position = Vector2(_screen_center_x(), -80)
	var variant_id := _pick_boss_variant_id()
	if _boss.has_method("set_sprite_variant"):
		_boss.set_sprite_variant(variant_id)
	var coop := NetworkManager.is_online() and multiplayer.is_server()
	var pilots: Array[int] = []
	if coop:
		for peer_id: int in _alive_players:
			if is_instance_valid(_players.get(peer_id)) and GameState.is_player_alive(peer_id):
				pilots.append(peer_id)
	_boss.setup(level, coop, pilots)
	if _player and is_instance_valid(_player):
		_boss.set_target(_player)
	_boss.boss_died.connect(_on_boss_died)
	_boss.shield_released.connect(_hud.show_boss_shield_released)
	if _boss.has_signal("phase_changed"):
		_boss.phase_changed.connect(_on_boss_phase_changed)
	if NetworkManager.is_online() and multiplayer.is_server():
		var eid := _next_entity_id
		_next_entity_id += 1
		_boss.entity_id = eid
		_entities[eid] = _boss
	add_child(_boss)
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_spawn_boss.rpc(_boss.entity_id, level, variant_id, _boss_snapshot(_boss))
	_boss.animate_entry(Vector2(_screen_center_x(), 160))

func _pick_boss_variant_id() -> int:
	var variant_count := 0
	for i in range(1, 100):
		var p := "res://assets/sprites/enemies/boss/boss_%02d.png" % i
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			break
		variant_count += 1
	if variant_count <= 0:
		return 0

	if _boss_variant_cycle.is_empty():
		for id in range(1, variant_count + 1):
			_boss_variant_cycle.append(id)
		_boss_variant_cycle.shuffle()

	if _boss_variant_cycle.size() >= 2 and _boss_variant_cycle[0] == _boss_variant_last:
		var tmp: int = _boss_variant_cycle[0]
		_boss_variant_cycle[0] = _boss_variant_cycle[1]
		_boss_variant_cycle[1] = tmp

	var picked: int = _boss_variant_cycle.pop_front()
	_boss_variant_last = picked
	return picked

func _on_boss_died() -> void:
	_clear_boss_laser_visual()
	if _boss != null:
		var eid: int = _boss.entity_id
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_despawned_entity_ids[eid] = true
			_entities.erase(eid)
			_entity_target_positions.erase(eid)
			_rpc_despawn_entity.rpc(eid, true)
	_boss = null
	_exit_boss_fight_mode()
	if _hud and _hud.has_method("hide_boss_status"):
		_hud.hide_boss_status()
	if NetworkManager.is_online() and multiplayer.is_server():
		_grant_random_boss_rewards_to_alive_players()
	elif not NetworkManager.is_online():
		_grant_random_boss_reward_to_peer(-1)

func _on_boss_phase_changed(phase_name: String) -> void:
	if NetworkManager.is_online() and multiplayer.is_server() and _boss != null:
		var vid: int = 1
		if _boss.has_method("get_sprite_variant_id"):
			vid = _boss.get_sprite_variant_id()
		_rpc_sync_boss_phase.rpc(phase_name, vid)

func _update_boss_hud() -> void:
	if _hud == null:
		return
	if not _has_active_boss():
		_hud.hide_boss_status()
		return
	var window: Boss.AttackWindow = _boss.get_attack_window()
	var attack: String = _boss.coop_pulse_label() if window == Boss.AttackWindow.OPEN else ""
	_hud.show_boss_status(_boss.get_network_health(), _boss.get_network_max_health(),
		_boss.get_shield_hp(), _boss.get_max_shield_hp(), _boss.get_phase_name(),
		Boss.ATTACK_WINDOW_LABELS[window] if attack.is_empty() else attack, _boss.is_shield_recharging())

func _enter_boss_fight_mode() -> void:
	_clear_non_boss_entities()
	_rpc_set_boss_bg(true)
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_set_boss_bg.rpc(true)

func _exit_boss_fight_mode() -> void:
	_rpc_set_boss_bg(false)
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_set_boss_bg.rpc(false)

func _clear_non_boss_entities() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == _boss:
			continue
		if n and is_instance_valid(n):
			if NetworkManager.is_online() and multiplayer.is_server() and n.has_method("get_entity_id"):
				var despawn_eid: int = int(n.get_entity_id())
				if despawn_eid > 0:
					_despawned_entity_ids[despawn_eid] = true
					if _entities.has(despawn_eid):
						_entities.erase(despawn_eid)
					_rpc_despawn_entity.rpc(despawn_eid)
			n.queue_free()
	for a in get_tree().get_nodes_in_group("asteroids"):
		if a and is_instance_valid(a):
			if NetworkManager.is_online() and multiplayer.is_server() and a.has_method("get_entity_id"):
				var despawn_aid: int = int(a.get_entity_id())
				if despawn_aid > 0:
					_despawned_entity_ids[despawn_aid] = true
					if _entities.has(despawn_aid):
						_entities.erase(despawn_aid)
					_rpc_despawn_entity.rpc(despawn_aid)
			a.queue_free()
	for b in get_tree().get_nodes_in_group("player_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for p in get_tree().get_nodes_in_group("powerups"):
		if p and is_instance_valid(p):
			if NetworkManager.is_online() and multiplayer.is_server() and p.has_method("get"):
				var despawn_pid: int = int(p.get("entity_id"))
				if despawn_pid > 0:
					_retire_network_powerup(despawn_pid, Vector2.ZERO, false)
					_rpc_finish_powerup.rpc(GameState.get_sync_round(), despawn_pid, "", Vector2.ZERO, 0, "", 0)
					continue
			p.queue_free()

func _show_boss_warning() -> void:
	if _hud and _hud.has_method("show_center_banner"):
		_hud.show_center_banner("裂隙母舰展开", 2.3, Color(1.0, 0.2, 0.25, 1.0))
		return
	var screen := get_viewport_rect().size
	var banner_h: float = maxf(96.0, screen.y * 0.16)
	var banner_y := screen.y * 0.28

	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)

	var overlay := ColorRect.new()
	overlay.color = Color(0.08, 0.0, 0.0, 0.0)
	overlay.position = Vector2(0, banner_y)
	overlay.size = Vector2(screen.x, banner_h)
	cl.add_child(overlay)

	var warning := Label.new()
	warning.text = "BOSS 来袭！"
	warning.add_theme_color_override("font_color", Color(1.0, 0.15, 0.25, 1))
	warning.add_theme_font_size_override("font_size", 52)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning.position = Vector2(0, banner_y)
	warning.size = Vector2(screen.x, banner_h)
	warning.modulate = Color(1, 1, 1, 0)
	cl.add_child(warning)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.72, 0.2)
	tween.parallel().tween_property(warning, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.0)
	tween.tween_property(overlay, "color:a", 0.0, 0.3)
	tween.parallel().tween_property(warning, "modulate:a", 0.0, 0.3)
	tween.tween_callback(cl.queue_free)

func _grant_random_boss_rewards_to_alive_players() -> void:
	var peer_ids := GameState.get_alive_player_ids()
	if peer_ids.is_empty():
		peer_ids = [1]
	for peer_id in peer_ids:
		_grant_random_boss_reward_to_peer(peer_id)

func _grant_random_boss_reward_to_peer(peer_id: int) -> void:
	var pool := _boss_reward_pool()
	if pool.is_empty():
		return
	_apply_boss_reward_for_peer(pool.pick_random(), peer_id)

func _apply_boss_reward_for_peer(reward_type: String, peer_id: int) -> void:
	if not _is_valid_boss_reward(reward_type):
		return
	var resolved_peer := peer_id if peer_id > 0 else 1
	if NetworkManager.is_online():
		if _boss_reward_claimed_peers.has(resolved_peer):
			return
		_boss_reward_claimed_peers[resolved_peer] = true
	GameState.apply_reward(reward_type, resolved_peer)
	if NetworkManager.is_online() and multiplayer.is_server() and resolved_peer != NetworkManager.local_player_id():
		var wire := NetworkManager.peer_for_slot(resolved_peer)
		if wire > 0:
			GameState.force_sync_to_peer(wire)
	_send_boss_reward_feedback(resolved_peer, reward_type)
	if _player and is_instance_valid(_player) and _player.has_method("_update_appearance"):
		_player._update_appearance()

func _is_valid_boss_reward(reward_type: String) -> bool:
	return reward_type in _boss_reward_pool()

func _boss_reward_pool() -> Array[String]:
	return ["laser_cd", "bullet_count", "damage", "speed"]

func _on_player_died() -> void:
	if NetworkManager.is_online():
		var peer_id := NetworkManager.local_player_id()
		_on_networked_player_died(peer_id)
		return
	if _player and is_instance_valid(_player):
		_alive_players.erase(_player.peer_id)
	GameState.stop_game()
	_pending_boss_level = 0
	_clear_runtime_entities_on_game_over()
	_show_death_marquee()
	if _hud and is_instance_valid(_hud) and _hud.has_method("_on_game_over"):
		_hud._on_game_over(GameState.score, GameState.level)

func _on_game_over_triggered(final_score: int, final_level: int) -> void:
	if NetworkManager.is_online() and not _alive_players.is_empty():
		return
	if NetworkManager.is_online():
		_finish_multiplayer_game_over(final_score, final_level)
		return
	_on_player_died()

func _finish_multiplayer_game_over(final_score: int, final_level: int) -> void:
	if not NetworkManager.is_online():
		_on_player_died()
		return
	GameState.stop_game()
	_pending_boss_level = 0
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_force_game_over.rpc(final_score, final_level)
	_clear_runtime_entities_on_game_over()
	_show_death_marquee()
	if _hud and is_instance_valid(_hud) and _hud.has_method("_on_game_over"):
		_hud._on_game_over(final_score, final_level)

@rpc("authority", "reliable", "call_remote")
func _rpc_force_game_over(final_score: int, final_level: int) -> void:
	GameState.game_running = false
	_clear_runtime_entities_on_game_over()
	if _hud and is_instance_valid(_hud) and _hud.has_method("_on_game_over"):
		_hud._on_game_over(final_score, final_level)

func _clear_runtime_entities_on_game_over() -> void:
	queue_redraw()
	var stick := get_node_or_null("MobileControls")
	if stick:
		stick.disable_for_results()
	_rpc_set_boss_bg(false)
	_clear_boss_laser_visual()
	for n in get_tree().get_nodes_in_group("enemies"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("asteroids"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("powerups"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("player_bullets"):
		if n and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy_bullets"):
		if n and is_instance_valid(n):
			n.queue_free()

func _show_death_marquee() -> void:
	var msg: String = GameState.death_message
	if msg.is_empty():
		msg = "被击落"
	_show_death_marquee_text(msg)


func _show_death_marquee_text(msg: String, hold_seconds: float = DEATH_MARQUEE_HOLD_SECONDS) -> void:
	var banner := Label.new()
	var screen := NetworkManager.battle_size(self)
	banner.text = "☠  " + msg + "  ☠"
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	banner.add_theme_constant_override("shadow_outline_size", 2)
	banner.horizontal_alignment = 1
	banner.position = Vector2(0, 20)
	banner.size = Vector2(screen.x, 36)
	banner.z_index = 200
	add_child(banner)

	var tween := create_tween()
	tween.tween_interval(hold_seconds)
	tween.tween_property(banner, "modulate:a", 0.0, DEATH_MARQUEE_FADE_SECONDS)
	tween.tween_callback(banner.queue_free)

func _on_level_up(_new_level: int) -> void:
	if _player and _player.has_method("on_level_up"):
		_player.on_level_up()
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	## 房主为每个存活玩家独立抽卡，加入端只展示快照里的本机批次。
	for pid: int in _alive_peer_ids():
		UpgradeDraft.open_draft(pid)


func _alive_peer_ids() -> Array[int]:
	var out: Array[int] = []
	## 注意：_players 的 key 是 int（peer_id），不是字符串。
	## 写成 `for key: String` 在单机下不报错（_players 为空、循环体不执行），
	## 只在联机真正有玩家时才抛类型错误——必须按 Variant 遍历再转。
	for key: Variant in _players.keys():
		var pid: int = int(key)
		if _alive_players.has(pid):
			out.append(pid)
	if out.is_empty() and _player != null and is_instance_valid(_player):
		out.append(int(_player.get("peer_id")))
	return out


func _input(event: InputEvent) -> void:
	## 选卡用 1/2/3 键而不是鼠标点击：进入战斗后鼠标被捕获用于走位，
	## 用鼠标选卡会打断操作，而"选卡时不能停下手"是本作的设计要求。
	if event is InputEventKey and event.pressed and not event.echo:
		var my_pid: int = -1
		if NetworkManager.is_online() and multiplayer != null \
				and multiplayer.has_multiplayer_peer():
			my_pid = NetworkManager.local_player_id()
		elif _player != null and is_instance_valid(_player):
			my_pid = int(_player.get("peer_id"))
		if my_pid > 0 and UpgradeDraft.has_draft(my_pid):
			match event.keycode:
				KEY_1, KEY_KP_1:
					UpgradeDraft.choose_card(my_pid, 0, "key")
				KEY_2, KEY_KP_2:
					UpgradeDraft.choose_card(my_pid, 1, "key")
				KEY_3, KEY_KP_3:
					UpgradeDraft.choose_card(my_pid, 2, "key")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_R and not GameState.game_running:
		_restart()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _restart() -> void:
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_rpc_restart_game.rpc(GameState.next_sync_round())
		return
	get_tree().reload_current_scene()

@rpc("authority", "reliable", "call_local")
func _rpc_restart_game(round_id: int) -> void:
	if not multiplayer.is_server():
		GameState.expect_sync_round(round_id)
	get_tree().reload_current_scene()

## ── 多人模式 RPC ──────────────────────────────────────────────

func _tick_player_entry() -> void:
	var now := Time.get_ticks_msec()
	if now >= _player_entry_deadline:
		_player_entry_deadline = -1
		if not is_instance_valid(_player_entry_message):
			_player_entry_message = _hud.show_lan_wait()
		_player_entry_message.text = "入局同步超时 · 重试或返回标题" if multiplayer.is_server() else "入局同步超时 · 请房主重试"
		return
	if multiplayer.is_server() or now < _next_player_entry_request:
		return
	var round_id: int = NetworkManager.recovery.round_id
	if round_id <= 0 or round_id < GameState.get_sync_round():
		return
	var slot := NetworkManager.local_player_id()
	var local: Node2D = _players.get(slot)
	var ready: bool = is_instance_valid(local) and local == _player and local._is_locally_controlled_player() and _players.has(1)
	_next_player_entry_request = now + PLAYER_ENTRY_RETRY_MS
	NetworkManager.request_battle_players.rpc_id(1, round_id, ready)

## Called by the persistent LAN dispatcher after matching the request to this round and peer.
func reply_battle_players(peer: int, ready: bool) -> void:
	if _player_entry_deadline < 0 or not _players.has(1) or not _players.has(NetworkManager.slot_for_peer(peer)):
		return
	if ready:
		_confirm_player_entry()
		_rpc_confirm_player_entry.rpc_id(peer, GameState.get_sync_round())
		return
	GameState.force_sync_to_peer(peer)
	_send_player_snapshot_to(peer)
	_rpc_set_boss_bg.rpc_id(peer, _boss_fight_active)
	for item in get_tree().get_nodes_in_group("powerups"):
		if _entities.get(item.entity_id) == item:
			_send_entity_spawn_to_peer(peer, item.entity_id, item)

@rpc("authority", "reliable", "call_remote")
func _rpc_confirm_player_entry(round_id: int) -> void:
	if is_inside_tree() and _player_entry_deadline > 0 and round_id == GameState.get_sync_round():
		_confirm_player_entry()

func _confirm_player_entry() -> void:
	_player_entry_ready = true
	_player_entry_deadline = 0
	if is_instance_valid(_player_entry_message):
		_player_entry_message.queue_free()


## Host → Client：生成玩家节点
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_networked_player(round_id: int, p_peer_id: int, pos_x: float, pos_y: float) -> void:
	if not is_inside_tree() or not NetworkManager.is_online() or round_id != GameState.get_sync_round() or round_id != NetworkManager.recovery.round_id:
		return
	if _players.has(p_peer_id):
		return
	var player := _player_scene.instantiate()
	player.name = str(p_peer_id)
	player.position = Vector2(pos_x, pos_y)
	add_child(player)
	GameState.ensure_player_state(p_peer_id)
	player.died.connect(_on_networked_player_died.bind(p_peer_id))
	_players[p_peer_id] = player
	_alive_players[p_peer_id] = true
	if GameState.rescue_peer_id == p_peer_id:
		_freeze_downed_player(p_peer_id, GameState.rescue_position)
	if p_peer_id == NetworkManager.local_player_id():
		_player = player
	if player.has_method("on_level_up"):
		player.on_level_up()
	_refresh_primary_player_target()

func _refresh_primary_player_target() -> void:
	var new_target: Node2D = null
	if _players.is_empty():
		return
	var preferred_id := NetworkManager.local_player_id()
	if _alive_players.has(preferred_id):
		if _players.has(preferred_id) and is_instance_valid(_players[preferred_id]):
			new_target = _players[preferred_id]
	if new_target == null and NetworkManager.is_online() and _alive_players.has(1):
		if _players.has(1) and is_instance_valid(_players[1]):
			new_target = _players[1]
	if new_target == null:
		for pid in _alive_players.keys():
			if _players.has(pid) and is_instance_valid(_players[pid]):
				new_target = _players[pid]
				break
	if new_target == null:
		return
	_player = new_target
	_retarget_hostile_entities(_player)

func _retarget_hostile_entities(target_player: Node2D) -> void:
	if target_player == null or not is_instance_valid(target_player):
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_method("set_target"):
			e.set_target(target_player)
	if _elite != null and is_instance_valid(_elite) and _elite.has_method("set_target"):
		_elite.set_target(target_player)
	if _boss != null and is_instance_valid(_boss) and _boss.has_method("set_target"):
		_boss.set_target(target_player)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_entity_snapshot() -> void:
	if not multiplayer.is_server():
		return
	if NetworkManager.gameplay_sender() <= 1:
		return
	var requester := multiplayer.get_remote_sender_id()
	if requester <= 0:
		return
	for eid in _entities.keys():
		var entity_id := int(eid)
		if _despawned_entity_ids.has(entity_id):
			continue
		var node: Node = _entities[eid]
		if is_instance_valid(node):
			_send_entity_spawn_to_peer(requester, entity_id, node)

func _request_entity_snapshot_from_host() -> void:
	if not NetworkManager.is_online() or multiplayer.is_server():
		return
	var now := int(Time.get_ticks_msec())
	if now - _last_entity_resync_request_msec < ENTITY_RESYNC_REQUEST_INTERVAL_MSEC:
		return
	_last_entity_resync_request_msec = now
	_rpc_request_entity_snapshot.rpc_id(1)

func _send_entity_spawn_to_peer(peer_id: int, eid: int, node: Node, recovering := false) -> void:
	if peer_id <= 0 or not is_instance_valid(node):
		return
	if node is Boss:
		_rpc_spawn_boss.rpc_id(peer_id, eid, node.get_network_level(), node.get_sprite_variant_id(), _boss_snapshot(node), recovering)
		return
	if node == _elite or (node.is_in_group("enemies") and node.has_method("get_network_shield")):
		_rpc_spawn_elite.rpc_id(peer_id, eid, GameState.post_elite_multiplier)
		var cue_left: float = node.get_route_dodge_cue_left()
		if cue_left > 0.0:
			_rpc_elite_dodge_cue.rpc_id(peer_id, eid, cue_left)
		var preview: Dictionary = node.route_attack_preview()
		if not preview.is_empty():
			_rpc_elite_attack_preview.rpc_id(peer_id, eid, preview, recovering)
		return
	if node.is_in_group("powerups") and node.has_method("get_powerup_type"):
		var powerup_node := node as Node2D
		if powerup_node:
			var assigned_peer_id: int = int(node.get_meta("assigned_peer_id", 0))
			_rpc_spawn_powerup.rpc_id(peer_id, GameState.get_sync_round(), eid, node.get_powerup_type(), powerup_node.global_position, assigned_peer_id)
		return
	if node.is_in_group("asteroids"):
		var asteroid_node := node as Node2D
		if asteroid_node:
			_rpc_spawn_asteroid.rpc_id(peer_id, eid, asteroid_node.global_position.x, asteroid_node.global_position.y)
		return
	if node.is_in_group("enemies"):
		var enemy_node := node as Node2D
		if enemy_node:
			_rpc_spawn_enemy.rpc_id(
				peer_id,
				eid,
				int(node.get("enemy_type")),
				enemy_node.global_position.x,
				enemy_node.global_position.y,
				int(node.get("health")),
				float(node.get("move_speed")),
				float(node.get("shoot_cooldown")),
				float(node.get("drop_chance")),
				1.0,
				float(node.get("bullet_speed_mult"))
			)

## Host → Client：生成敌人幽灵副本
##
## `bullet_mult` 是章节主题的敌弹速度倍率（wave_director.gd CHAPTER_THEMES）。
## 它必须跟着生成包一起走：客户端的敌人是幽灵，不跑 AI 也不开火，
## 但**弹速是纯渲染参数**——不同步的话两端看到的弹幕速度不一样，
## 玩家的擦弹判断和走位预案会直接失效。
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_enemy(eid: int, etype: int, pos_x: float, pos_y: float, hp: int, spd: float, cd: float, drop: float, mult: float, bullet_mult: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	var enemy = _enemy_scene.instantiate()
	enemy.name = str(eid)
	enemy.entity_id = eid
	enemy._is_network_ghost = true
	enemy.enemy_type = etype
	enemy.position = Vector2(pos_x, pos_y)
	enemy.health = hp
	enemy.move_speed = spd
	enemy.shoot_cooldown = cd
	enemy.drop_chance = drop
	enemy.bullet_speed_mult = bullet_mult
	if _player and is_instance_valid(_player):
		enemy.set_target(_player)
	_entities[eid] = enemy
	add_child(enemy)

## Host → Client：生成精英幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_elite(eid: int, elite_mult: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if is_instance_valid(_elite) and _entities.get(eid) == _elite and not _elite.is_queued_for_deletion():
		return  # 同一实体的补发快照随后会同步血盾值，保留其破盾状态。
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	_elite = _elite_scene.instantiate()
	_elite.name = str(eid)
	_elite.entity_id = eid
	_elite._is_network_ghost = true
	_elite.position = Vector2(_screen_center_x(), -60)
	_elite.set_difficulty(elite_mult)
	if _player and is_instance_valid(_player):
		_elite.set_target(_player)
	_entities[eid] = _elite
	if _elite.has_signal("shield_broken_window_started"):
		_elite.shield_broken_window_started.connect(_on_elite_shield_broken_window_started)
	add_child(_elite)

## 侧移预警与变位分开同步。加入端只播放青闪，位移仍走实体位置包。
func _publish_elite_dodge_cue(seconds: float, eid: int) -> void:
	if NetworkManager.is_online() and multiplayer.is_server() and GameState.game_running:
		_rpc_elite_dodge_cue.rpc(eid, seconds)

@rpc("authority", "reliable", "call_remote")
func _rpc_elite_dodge_cue(eid: int, seconds: float) -> void:
	if GameState.game_running and is_instance_valid(_elite) and _elite.entity_id == eid:
		_elite.play_route_dodge_preview(seconds)

func _publish_elite_attack_preview(state: Dictionary, eid: int) -> void:
	if NetworkManager.is_online() and multiplayer.is_server() and GameState.game_running:
		_rpc_elite_attack_preview.rpc(eid, state)

@rpc("authority", "reliable", "call_remote")
func _rpc_elite_attack_preview(eid: int, state: Dictionary, recovering := false) -> void:
	if GameState.game_running and is_instance_valid(_elite) and _elite.entity_id == eid:
		_elite.apply_route_attack_preview(state, recovering)

## Host → Client：强制销毁精英护盾光晕（护盾同步包可能丢包或迟到）
@rpc("authority", "reliable", "call_remote")
func _rpc_elite_shield_destroyed(eid: int) -> void:
	var node: Node = null
	if _entities.has(eid) and is_instance_valid(_entities[eid]):
		node = _entities[eid]
	elif _elite and is_instance_valid(_elite) and int(_elite.entity_id) == eid:
		node = _elite
	if node and node.has_method("force_network_shield_destroyed"):
		node.force_network_shield_destroyed()

## Host → Client：同步 Boss 阶段变换
@rpc("authority", "reliable", "call_remote")
func _rpc_sync_boss_phase(_phase_name: String, variant_id: int) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if _boss.has_method("set_sprite_variant"):
		_boss.set_sprite_variant(variant_id)
	if _boss.has_method("_apply_visual_state"):
		_boss._apply_visual_state()

func _boss_snapshot(boss: Boss) -> Dictionary:
	return {
		"position": boss.global_position, "rotation": boss.global_rotation,
		"hp": boss.get_network_health(), "max_hp": boss.get_network_max_health(),
		"shield_stamp": boss.get_shield_stamp(), "shield": boss.get_shield_hp(), "max_shield": boss.get_max_shield_hp(),
		"stamp": boss.get_attack_window_stamp(), "age": boss.get_laser_visual_age(),
		"from": boss._ultimate_laser_start, "to": boss._ultimate_laser_end,
		"pulse": boss.coop_pulse_snapshot(),
	}

## 同 ID 快照补齐当前状态，保留在播的激光和已经消费的解除事件。
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_boss(eid: int, level: int, variant_id: int, snapshot: Dictionary, recovering := false) -> void:
	if not NetworkManager.is_online() or not GameState.game_running or _despawned_entity_ids.has(eid):
		return
	var stamp: int = snapshot.stamp
	var active := _has_active_boss()
	if active and _boss.entity_id > eid:
		return
	if not active or _boss.entity_id != eid:
		if active:
			_entities.erase(_boss.entity_id)
			_boss.queue_free()
		_clear_boss_laser_visual()
		_boss = _boss_scene.instantiate()
		_boss.name = str(eid)
		_boss.entity_id = eid
		_boss._is_network_ghost = true
		_boss.position = to_local(snapshot.position)
		_boss.set_sprite_variant(variant_id)
		_boss.setup(level)
		if is_instance_valid(_player):
			_boss.set_target(_player)
		_boss.boss_died.connect(_on_boss_died)
		_boss.shield_released.connect(_hud.show_boss_shield_released)
		add_child(_boss)
		_boss.apply_network_rotation(snapshot.rotation)
	_entities[eid] = _boss
	_boss.apply_network_boss_shield(snapshot.shield_stamp, snapshot.shield, snapshot.max_shield)
	_boss.apply_network_coop_pulse(snapshot.get("pulse", {}))
	var previous: int = _boss.get_attack_window_stamp()
	var hp: float = snapshot.hp if previous < 0 else minf(snapshot.hp, _boss.get_network_health())
	_boss.apply_network_health(hp, snapshot.max_hp)
	if stamp < previous:
		return
	if recovering:
		_clear_boss_laser_visual()
	if _boss.get_sprite_variant_id() != variant_id:
		_boss.set_sprite_variant(variant_id)
		_boss._apply_visual_state()
	_boss.apply_network_attack_window(stamp)
	_sync_boss_laser(stamp, snapshot.from, snapshot.to, snapshot.age, false)

## Host → Client：生成掉落物幽灵副本
@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_powerup(round_id: int, eid: int, powerup_type: String, world_pos: Vector2, assigned_peer_id: int = 0) -> void:
	if not NetworkManager.is_online() or round_id <= 0 or round_id != GameState.get_sync_round():
		return
	if _despawned_entity_ids.has(eid) or is_instance_valid(_entities.get(eid)):
		return
	var pu = _powerup_scene.instantiate()
	pu.name = str(eid)
	pu.entity_id = eid
	pu._is_network_ghost = true
	pu.position = to_local(world_pos)
	pu.setup(powerup_type)
	if assigned_peer_id > 0:
		pu.set_meta("assigned_peer_id", assigned_peer_id)
	_entities[eid] = pu
	add_child(pu)

@rpc("authority", "reliable", "call_remote")
func _rpc_finish_powerup(round_id: int, eid: int, kind: String, world_pos: Vector2, recipient: int, reward: String, sequence: int) -> void:
	if not NetworkManager.is_online() or round_id <= 0 or round_id != GameState.get_sync_round() or _despawned_entity_ids.has(eid):
		return
	_retire_network_powerup(eid, world_pos, not kind.is_empty())
	if recipient == NetworkManager.local_player_id():
		_pending_pickup_feedback.append({"round": round_id, "seq": sequence, "kind": kind, "at": world_pos, "reward": reward})

func _flush_pickup_feedback() -> void:
	while not _pending_pickup_feedback.is_empty():
		var pickup := _pending_pickup_feedback.front() as Dictionary
		if not GameState.has_received_sync(pickup.round, pickup.seq):
			return
		_pending_pickup_feedback.pop_front()
		on_local_powerup_feedback(pickup.kind, pickup.at, true, pickup.reward)

func on_local_powerup_feedback(powerup_type: String, world_pos: Vector2, confirmed := true, reward: Variant = null) -> void:
	if _hud and _hud.has_method("show_pickup_toast"):
		_hud.show_pickup_toast(powerup_type, world_pos, powerup_type if reward == null else str(reward))
	if NetworkManager.is_online():
		SFX.play_ui_confirm()
	if powerup_type == "core" and confirmed:
		var ring = Pool.acquire("core_pickup", _hit_effect_scene)
		ring.position = to_local(world_pos)
		add_child(ring)
		ring.start_core_pickup()

func on_local_boss_reward_feedback(_reward_type: String) -> void:
	if _hud == null:
		return
	if _hud.has_method("show_boss_bonus_attribute_feedback"):
		_hud.show_boss_bonus_attribute_feedback()

func _send_boss_reward_feedback(peer_id: int, reward_type: String) -> void:
	var target_peer := peer_id if peer_id > 0 else 1
	if target_peer == NetworkManager.local_player_id():
		on_local_boss_reward_feedback(reward_type)
	else:
		var wire := NetworkManager.peer_for_slot(target_peer)
		if wire > 0:
			_rpc_show_boss_reward_feedback.rpc_id(wire, reward_type)

@rpc("authority", "reliable", "call_remote")
func _rpc_show_boss_reward_feedback(reward_type: String) -> void:
	on_local_boss_reward_feedback(reward_type)

@rpc("authority", "reliable", "call_remote")
func _rpc_show_elite_warning() -> void:
	_show_elite_warning()

@rpc("authority", "reliable", "call_remote")
func _rpc_show_elite_shield_break_banner() -> void:
	_show_elite_shield_break_banner()

@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_asteroid(eid: int, pos_x: float, pos_y: float) -> void:
	if not NetworkManager.is_online():
		return
	if _despawned_entity_ids.has(eid):
		return
	if _entities.has(eid):
		var old_node: Node = _entities[eid]
		if is_instance_valid(old_node):
			old_node.queue_free()
	var asteroid = _asteroid_scene.instantiate()
	asteroid.name = str(eid)
	asteroid.entity_id = eid
	asteroid._is_network_ghost = true
	asteroid.position = Vector2(pos_x, pos_y)
	_entities[eid] = asteroid
	add_child(asteroid)

## Host → Client：销毁实体
@rpc("authority", "reliable", "call_remote")
func _rpc_despawn_entity(eid: int, combat_kill := false) -> void:
	_despawned_entity_ids[eid] = true
	if is_instance_valid(_boss) and _boss.entity_id == eid:
		_clear_boss_laser_visual()
		_boss.hide()
		_hud.hide_boss_status()
	if _entities.has(eid):
		var node = _entities[eid]
		if is_instance_valid(node):
			if combat_kill and node.has_method("play_death_feedback"):
				node.play_death_feedback()
			node.queue_free()
		_entities.erase(eid)
	_entity_target_positions.erase(eid)
	## 兜底：若字典丢失或出现重复实例，按 name/entity_id 全量清理残留节点。
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if n.name == str(eid) or (n.has_method("get_entity_id") and int(n.get_entity_id()) == eid):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("powerups"):
		if not is_instance_valid(n):
			continue
		if n.name == str(eid):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(n):
			continue
		if n.name == str(eid) or (n.has_method("get_entity_id") and int(n.get_entity_id()) == eid):
			n.queue_free()

## Host → Client：实体位置批量同步
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_positions(data: PackedFloat32Array, impact := PackedFloat32Array()) -> void:
	if NetworkManager.recovery.deadline > 0:
		return
	if impact.size() == 3:
		var kind := Pool.Impact.LEGACY
		if impact[2] == Pool.Impact.ORDINARY_ENEMY:
			kind = Pool.Impact.ORDINARY_ENEMY
		elif impact[2] == Pool.Impact.SHIELD:
			kind = Pool.Impact.SHIELD
		elif impact[2] == Pool.Impact.BOSS_SHIELD:
			kind = Pool.Impact.BOSS_SHIELD
		elif impact[2] == Pool.Impact.BOSS_HULL:
			kind = Pool.Impact.BOSS_HULL
		Pool.spawn_hit(Vector2(impact[0], impact[1]), kind)
		if (kind == Pool.Impact.BOSS_SHIELD or kind == Pool.Impact.BOSS_HULL) and _has_active_boss() and _boss.uses_steady_hit_feedback():
			add_boss_laser_hit_bump()
		if not Pool.is_shield_contact(kind):
			SFX.play_hit_confirm(SHAKE_HIT)
	var i := 0
	while i + ENTITY_SYNC_STRIDE - 1 < data.size():
		var eid := int(data[i])
		var x := data[i + 1]
		var y := data[i + 2]
		i += ENTITY_SYNC_STRIDE
		if not _entities.has(eid) or not is_instance_valid(_entities[eid]):
			if not _despawned_entity_ids.has(eid):
				_request_entity_snapshot_from_host()
			continue
		var node: Node2D = _entities[eid] as Node2D
		if node == null:
			continue
		var target_pos := Vector2(x, y)
		if node.get_meta("net_sync_inited", false) == false:
			node.global_position = target_pos
			node.set_meta("net_sync_inited", true)
		_entity_target_positions[eid] = target_pos

## Host → Client：同步实体血量（低频 10Hz）
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_health(data: PackedFloat32Array, boss_shield_stamp := -1, boss_shield_hp := -1.0) -> void:
	if NetworkManager.recovery.deadline > 0:
		return
	var i := 0
	while i + 2 < data.size():
		var eid := int(data[i])
		var hp := data[i + 1]
		var max_hp := data[i + 2]
		i += 3
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			var node: Node = _entities[eid]
			if node == _boss:
				if boss_shield_stamp == _boss.get_shield_stamp() and boss_shield_hp > 0.0 and boss_shield_hp < _boss.get_shield_hp():
					_boss.apply_network_boss_shield(boss_shield_stamp, boss_shield_hp, _boss.get_max_shield_hp())
					SFX.play_shield_hit()
				# 无序血量包可能晚于同一阶段的实体快照。
				hp = minf(hp, _boss.get_network_health())
			if node.has_method("apply_network_health"):
				node.apply_network_health(hp, max_hp)

## Host → Client：只同步带护盾实体的护盾值，避免所有实体同步包膨胀。
@rpc("authority", "reliable", "call_remote")
func _rpc_sync_entity_shields(data: PackedFloat32Array) -> void:
	var i := 0
	while i + ENTITY_SHIELD_SYNC_STRIDE - 1 < data.size():
		var eid := int(data[i])
		var shield := data[i + 1]
		var max_shield := data[i + 2]
		i += ENTITY_SHIELD_SYNC_STRIDE
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			var node: Node = _entities[eid]
			if shield >= 0.0 and node.has_method("apply_network_shield"):
				node.apply_network_shield(shield, max_shield)

## Host → Client：同步少数需要朝向的实体；主位置包仍保持 5 字段，避免所有实体承担 rotation 成本。
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_entity_rotations(data: PackedFloat32Array) -> void:
	if NetworkManager.recovery.deadline > 0:
		return
	var i := 0
	while i + ENTITY_ROTATION_SYNC_STRIDE - 1 < data.size():
		var eid := int(data[i])
		var rot := data[i + 1]
		i += ENTITY_ROTATION_SYNC_STRIDE
		if _entities.has(eid) and is_instance_valid(_entities[eid]):
			var node: Node = _entities[eid]
			if node.has_method("apply_network_rotation"):
				node.apply_network_rotation(rot)

## Host：打包所有实体位置
## Host：每 100ms 单独发送一次血量数据
func _batch_sync_entity_health() -> void:
	if _entities.is_empty():
		return
	var health_data := PackedFloat32Array()
	for eid: int in _entities:
		var node = _entities[eid]
		if is_instance_valid(node) and node.has_method("get_network_health"):
			health_data.append(eid as float)
			health_data.append(float(node.get_network_health()))
			if node.has_method("get_network_max_health"):
				health_data.append(float(node.get_network_max_health()))
	if health_data.size() > 0:
		var shield_stamp: int = _boss.get_shield_stamp() if _has_active_boss() else -1
		var shield_hp: float = _boss.get_shield_hp() if _has_active_boss() else -1.0
		_rpc_sync_entity_health.rpc(health_data, shield_stamp, shield_hp)

## 加入端的子弹只渲染。随已有位置包捎带一个确认落点，避免每发子弹单独通信。
func register_projectile_impact(pos: Vector2, kind: Pool.Impact) -> void:
	if _pending_impact.is_empty():
		_pending_impact = PackedFloat32Array([pos.x, pos.y, float(kind)])

func _batch_sync_entity_positions() -> void:
	if _entities.is_empty() and _pending_impact.is_empty():
		return
	var data := PackedFloat32Array()
	var shield_data := PackedFloat32Array()
	var rotation_data := PackedFloat32Array()
	for eid: int in _entities:
		var node = _entities[eid]
		if is_instance_valid(node):
			data.append(eid as float)
			data.append(node.global_position.x)
			data.append(node.global_position.y)
			if node.has_method("get_network_shield") and node.has_method("get_network_max_shield"):
				shield_data.append(eid as float)
				shield_data.append(float(node.get_network_shield()))
				shield_data.append(float(node.get_network_max_shield()))
			if node.has_method("get_network_rotation") and node.has_method("apply_network_rotation"):
				rotation_data.append(eid as float)
				rotation_data.append(float(node.get_network_rotation()))
	if not _pending_impact.is_empty():
		_rpc_sync_entity_positions.rpc(data, _pending_impact)
		_pending_impact.clear()
	elif not data.is_empty():
		_rpc_sync_entity_positions.rpc(data)
	if shield_data.size() > 0:
		_rpc_sync_entity_shields.rpc(shield_data)
	if rotation_data.size() > 0:
		_rpc_sync_entity_rotations.rpc(rotation_data)


## 玩家位置同步 ────────────────────────────────────────────────
##
## 为什么不用 MultiplayerSynchronizer：引擎的场景复制（SceneCache）依赖
## 「同步器节点路径能被解析到」，而本项目是**每端各自 change_scene 进
## main.tscn**，客户端挂载战斗场景晚于 Host 开始广播，于是引擎会
##   Node not found: "Main/1/MultiplayerSynchronizer" (relative to "/root")
##   Failed to get path from RPC: Main / Invalid packet received
## 并丢弃后续同步包 —— 表现为客户端间歇性丢失远端玩家节点与位置同步。
## 玩家位置改走和敌人/子弹同一条手工管线，行为可预期、可插值、易回归。

## Host：批量广播全部玩家节点坐标（含各端幽灵），与实体同步同频
func _batch_sync_players() -> void:
	var data := PackedFloat32Array()
	for pid: int in _players:
		var node = _players[pid]
		if not is_instance_valid(node):
			continue
		data.append(pid as float)
		data.append(node.global_position.x)
		data.append(node.global_position.y)
		data.append(float(node.rotation))
	if data.size() > 0:
		_rpc_sync_player_states.rpc(data)


## Host → Client：应用远端玩家坐标
@rpc("authority", "unreliable", "call_remote")
func _rpc_sync_player_states(data: PackedFloat32Array) -> void:
	if NetworkManager.recovery.deadline > 0:
		return
	var i := 0
	while i + PLAYER_SYNC_STRIDE - 1 < data.size():
		var pid := int(data[i])
		var pos := Vector2(data[i + 1], data[i + 2])
		var rot := data[i + 3]
		i += PLAYER_SYNC_STRIDE
		if NetworkManager.is_online() and pid == NetworkManager.local_player_id():
			continue
		_apply_remote_player_state(pid, pos, rot)


## Client → Host：上报本机坐标，驱动 Host 上的幽灵节点
@rpc("any_peer", "unreliable", "call_remote")
func _rpc_report_player_state(p_peer_id: int, pos_x: float, pos_y: float, rot: float) -> void:
	# A position report already in flight can arrive as the old battle leaves the tree.
	if not is_inside_tree() or not multiplayer.is_server():
		return
	_player_report_received += 1
	var sender := NetworkManager.gameplay_sender()
	if sender <= 1 or p_peer_id != sender:
		_player_report_rejected += 1
		if _player_report_rejected <= 3:
			print("[SYNC] 上报被拒 p_peer_id=%d sender=%d" % [p_peer_id, sender])
		return
	var pos := Vector2(pos_x, pos_y)
	if not pos.is_finite() or not is_finite(rot):
		return
	var margin := Vector2.ONE * MotionController.EDGE_MARGIN
	_apply_remote_player_state(p_peer_id, pos.clamp(margin, NetworkManager.battle_size(self) - margin), rot)


## 收到过几次客户端坐标上报。联机探针靠它区分"客户端到底有没有在发"，
## 用来判断失败是同步链路的 bug 还是探针自己的时序问题。
func get_player_report_count() -> int:
	return _player_report_received


## 客户端侧发送计数。与 Host 的 received 对比即可区分
## "客户端没发" 与 "发了但没到"。
func get_player_report_sent() -> int:
	return _player_report_sent


## 把远端坐标写入目标点 + 朝向；首次直接吸附，之后由 _apply_entity_interpolation 平滑
func _apply_remote_player_state(p_peer_id: int, pos: Vector2, rot: float) -> void:
	if not _players.has(p_peer_id) or not is_instance_valid(_players[p_peer_id]):
		return
	var node: Node2D = _players[p_peer_id] as Node2D
	if node == null or node.is_downed:
		return
	if node.get_meta("player_sync_inited", false) == false:
		node.global_position = pos
		node.set_meta("player_sync_inited", true)
	_player_target_positions[p_peer_id] = pos
	node.rotation = rot

## 子弹同步 ──────────────────────────────────────────────────

## 注册一颗子弹生成（由 enemy/boss/player 调用）
func register_bullet_spawn(pos: Vector2, angle: float, damage: float, is_player: bool, level: int, speed: float, color: Color = Color(1,1,1,1), owner_peer_id: int = -1, scatter := false) -> void:
	if not NetworkManager.is_online():
		return
	var pending := _pending_scatter_spawns if scatter else _pending_bullet_spawns
	pending.append([pos.x, pos.y, angle, damage, is_player, level, speed, color.r, color.g, color.b, owner_peer_id])
	if _entry_shot_trace and is_player and not scatter and not multiplayer.is_server():
		_trace_entry_shot("queued", owner_peer_id, pending.size())

## 每帧 flush 待发送子弹
func _flush_bullet_spawns() -> void:
	if not _pending_bullet_spawns.is_empty():
		var data := _pending_bullet_spawns.duplicate()
		_pending_bullet_spawns.clear()
		if multiplayer.is_server():
			_rpc_spawn_bullets.rpc(data)
		else:
			var opening := GameState.rift_remix and _player_entry_ready and not _initial_guest_volley_sent
			# Both RPCs spawn the same authoritative bullets. Only the first guest batch needs guaranteed delivery.
			var method := "_rpc_request_scatter" if opening else "_rpc_spawn_bullets"
			var sent := rpc_id(1, method, data)
			if opening and sent == OK:
				_initial_guest_volley_sent = true
			if _entry_shot_trace:
				_trace_entry_shot("flush_initial_reliable" if opening else "flush_ordered", NetworkManager.local_player_id(), data.size(), sent)
	# 技能散射与航道猎手的固定齐射共用可靠队列，加入端能看到实际判定的整轮弹体。
	if not _pending_scatter_spawns.is_empty():
		var data := _pending_scatter_spawns.duplicate()
		_pending_scatter_spawns.clear()
		if multiplayer.is_server():
			_rpc_spawn_scatter.rpc(data)
		else:
			_rpc_request_scatter.rpc_id(1, data)

## 注册激光生成（Host 广播；Client 上报 Host）
func register_laser_spawn(pos: Vector2, angle: float, damage: float, owner_peer_id: int = -1) -> void:
	if not NetworkManager.is_online():
		return
	_pending_laser_spawns.append([pos.x, pos.y, angle, damage, owner_peer_id])

func publish_boss_shield(boss: Boss) -> void:
	if GameState.game_running and boss == _boss and NetworkManager.is_online() and multiplayer.is_server():
		_rpc_sync_boss_shield.rpc(boss.entity_id, boss.get_shield_stamp(), boss.get_shield_hp(), boss.get_max_shield_hp(), boss.global_position)

func publish_boss_pulse(boss: Boss) -> void:
	if GameState.game_running and boss == _boss and NetworkManager.is_online() and multiplayer.is_server():
		_rpc_sync_boss_pulse.rpc(boss.entity_id, boss.coop_pulse_snapshot())

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_boss_pulse(eid: int, pulse: Dictionary) -> void:
	if GameState.game_running and _has_active_boss() and _boss.entity_id == eid:
		_boss.apply_network_coop_pulse(pulse, true)

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_boss_shield(eid: int, stamp: int, hp: float, max_hp: float, origin: Vector2) -> void:
	if not GameState.game_running or not _has_active_boss() or _boss.entity_id != eid:
		return
	var advanced: bool = _boss.apply_network_boss_shield(stamp, hp, max_hp)
	if advanced and stamp % Boss.SHIELD_PHASE_COUNT == Boss.ShieldPhase.EXPOSED:
		_boss.play_shield_release(origin)

func publish_boss_attack_window(boss: Boss) -> void:
	if not GameState.game_running or boss != _boss or boss.is_queued_for_deletion():
		return
	var stamp := boss.get_attack_window_stamp()
	var origin := boss.global_position if boss.get_attack_window() == Boss.AttackWindow.OPEN else boss._ultimate_laser_start
	var target := boss._ultimate_laser_end
	var age := boss.get_laser_visual_age()
	_sync_boss_laser(stamp, origin, target, age, true)
	if NetworkManager.is_online() and multiplayer.is_server():
		_rpc_sync_boss_window.rpc(boss.entity_id, stamp, origin, target, age, boss.get_network_health())

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_boss_window(eid: int, stamp: int, origin: Vector2, target: Vector2, age: float, hp: float) -> void:
	if not GameState.game_running or not _has_active_boss() or _boss.entity_id != eid:
		return
	var previous: int = _boss.get_attack_window_stamp()
	# 唯一有意义的同阶段变更是蓄力已锁向。重复到达不重播预警。
	var aim_update := Boss.window_from_stamp(stamp) == Boss.AttackWindow.CHARGING and not origin.is_equal_approx(target)
	if stamp < previous or (stamp == previous and not aim_update):
		return
	_boss.apply_network_health(minf(hp, _boss.get_network_health()), _boss.get_network_max_health())
	_boss.apply_network_attack_window(stamp)
	_sync_boss_laser(stamp, origin, target, age, stamp > previous)

func _sync_boss_laser(stamp: int, origin: Vector2, target: Vector2, age: float, live_edge: bool) -> void:
	var window := Boss.window_from_stamp(stamp)
	var has_visual := is_instance_valid(_boss_laser_visual) and not _boss_laser_visual.is_queued_for_deletion()
	if window < Boss.AttackWindow.CHARGING:
		if has_visual and _boss_laser_stamp == stamp:
			return
		if live_edge and has_visual and _boss_laser_visual.finish_beam():
			_boss_laser_stamp = stamp
		else:
			_clear_boss_laser_visual()
		return
	var visual_stamp := stamp - 1 if window == Boss.AttackWindow.HOLD else stamp
	if has_visual and _boss_laser_stamp == visual_stamp:
		_boss_laser_visual.advance_to_age(age)
		if window == Boss.AttackWindow.CHARGING and not origin.is_equal_approx(target):
			_apply_boss_laser_aim(origin, target)
		return
	_clear_boss_laser_visual()
	_boss_laser_stamp = visual_stamp
	if window == Boss.AttackWindow.CHARGING:
		_boss_laser_visual = _show_boss_ultimate_laser_charge(origin, Boss.BOSS_ULTIMATE_LASER_CHARGE, age, live_edge)
		if not origin.is_equal_approx(target):
			_apply_boss_laser_aim(origin, target)
	else:
		if _boss._is_network_ghost:
			_boss.apply_network_laser_lock(target - origin)
		var visual := _boss_ultimate_laser_visual_script.new()
		add_child(visual)
		visual.setup_beam(origin, target, Boss.BOSS_ULTIMATE_LASER_TRAVEL, Boss.BOSS_ULTIMATE_LASER_WIDTH, Boss.BOSS_ULTIMATE_LASER_HOLD_SECONDS, age)
		_boss_laser_visual = visual
	if is_instance_valid(_boss) and not _boss._is_network_ghost:
		_boss_laser_visual.authority_boss = _boss

func _apply_boss_laser_aim(origin: Vector2, target: Vector2) -> void:
	_boss_laser_visual.set_charge_direction(target - origin)
	if _boss._is_network_ghost:
		_boss.apply_network_laser_lock(target - origin)

func _clear_boss_laser_visual() -> void:
	if is_instance_valid(_boss_laser_visual):
		_boss_laser_visual.hide()
		_boss_laser_visual.queue_free()
	_boss_laser_visual = null
	_boss_laser_stamp = -1

func _show_boss_ultimate_laser_charge(pos: Vector2, duration: float, age := 0.0, play_warning := true) -> Node2D:
	if play_warning:
		SFX.play_boss_warning()
	var visual := _boss_ultimate_laser_visual_script.new()
	add_child(visual)
	visual.setup_charge(pos, duration, age)
	return visual

## 每帧 flush 待发送激光
func _flush_laser_spawns() -> void:
	if _pending_laser_spawns.is_empty():
		return
	var data := _pending_laser_spawns.duplicate()
	_pending_laser_spawns.clear()
	if multiplayer.is_server():
		_rpc_spawn_lasers.rpc(data)
	else:
		_rpc_request_laser_spawns.rpc_id(1, data)

## Host → Client（或 Client → Host）：刷出子弹视觉副本
@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_spawn_bullets(data: Array) -> void:
	if _entry_shot_trace and is_inside_tree() and multiplayer.is_server():
		_trace_entry_shot("rpc_ordered", multiplayer.get_remote_sender_id(), data.size())
	if not NetworkManager.is_online():
		return
	## Client → Host：Host 接收后需要再广播一次，确保加入端能看到自己的子弹。
	var sender := -1
	if multiplayer.is_server():
		sender = NetworkManager.gameplay_sender()
		if sender <= 1 or not _alive_players.has(sender):
			return
		_rpc_spawn_bullets.rpc(data)
	_spawn_network_bullets(data, sender)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_scatter(data: Array) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var sender := NetworkManager.gameplay_sender()
	if _entry_shot_trace:
		_trace_entry_shot("rpc_reliable", sender, data.size())
	if not NetworkManager.is_online() or not GameState.game_running or not _alive_players.has(sender):
		return
	# The guest's acknowledgement and its reliable shots are ordered on the same reliable stream.
	if GameState.rift_remix and not _player_entry_ready:
		return
	_spawn_network_bullets(data, sender)
	_rpc_spawn_scatter.rpc(data)

@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_scatter(data: Array) -> void:
	if not NetworkManager.is_online() or not GameState.game_running:
		return
	_spawn_network_bullets(data)

func _spawn_network_bullets(data: Array, sender := -1) -> void:
	for entry in data:
		var bullet := Pool.acquire("bullet", _bullet_scene)
		if bullet == null:
			continue
		var is_player := bool(entry[4])
		# 实弹的构筑归属使用房主确认的槽位。广播中的槽位供幽灵弹显示。
		var owner_slot := sender if sender > 0 else (int(entry[10]) if entry.size() > 10 else -1)
		add_child(bullet)
		bullet.setup(
			Vector2(entry[0], entry[1]),  # pos
			entry[2],                      # angle
			entry[3] as int,               # damage
			is_player,
			entry[5],                      # level
			entry[6],                      # speed
			owner_slot
		)
		if entry.size() > 7:
			bullet.modulate = Color(entry[7], entry[8], entry[9], 1.0)
		if is_player and owner_slot > 0:
			bullet.apply_owner_cards(owner_slot)
		if not multiplayer.is_server() and bullet.has_method("set_network_ghost"):
			bullet.set_network_ghost(true)
		elif _entry_shot_trace and is_player and sender > 1:
			_trace_entry_shot("authority_setup", sender, 1)

func _trace_entry_shot(stage: String, slot: int, count: int, status := OK) -> void:
	var seen := int(_entry_shot_trace_counts.get(stage, 0))
	if seen >= 8:
		return
	_entry_shot_trace_counts[stage] = seen + 1
	print("[ENTRY_SHOT] ", stage, " ", JSON.stringify({"round": GameState.get_sync_round(), "slot": slot,
		"count": count, "status": status, "ready": _player_entry_ready, "held": _lan_frozen_frame >= 0,
		"wall_ms": int(Time.get_unix_time_from_system() * 1000)}))

## 激光同步：
@rpc("authority", "reliable", "call_remote")
func _rpc_set_boss_bg(active: bool) -> void:
	var running := GameState.game_running and not _fallback_in_progress
	active = active and running
	_boss_fight_active = active
	_backdrop.set_boss_mode(active)
	if not running:
		BGM.stop_bgm()
	elif active:
		BGM.play_boss_bgm()
	else:
		BGM.play_bgm()

## 技能冷却走可靠确认，已确认的激光弹体用同样的传输保证。
@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_laser_spawns(data: Array) -> void:
	if not multiplayer.is_server():
		return
	if not NetworkManager.is_online() or not GameState.game_running or not _alive_players.has(NetworkManager.gameplay_sender()):
		return
	_spawn_network_lasers(data, false)
	_rpc_spawn_lasers.rpc(data)

@rpc("authority", "reliable", "call_remote")
func _rpc_spawn_lasers(data: Array) -> void:
	if not NetworkManager.is_online() or not GameState.game_running:
		return
	_spawn_network_lasers(data, true)

func _spawn_network_lasers(data: Array, ghost: bool) -> void:
	for entry in data:
		var bolt = _laser_scene.instantiate()
		add_child(bolt)
		var owner_peer := int(entry[4]) if entry.size() > 4 else -1
		bolt.setup(Vector2(entry[0], entry[1]), entry[2], entry[3], owner_peer)
		if ghost:
			bolt.set_network_ghost(true)
