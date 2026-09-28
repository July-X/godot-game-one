extends Node
## 联机回归探针（headless 双进程，真实 ENet 回环）
##
## 用法（推荐直接跑门禁脚本，会自动收口退出码并扫描引擎报错）：
##   tests/run_probe.sh [端口]
## 手工跑（两个终端同时）：
##   godot --headless --path . res://tests/lan_probe.tscn -- host 7788
##   godot --headless --path . res://tests/lan_probe.tscn -- client 7788
##
## 覆盖 docs/AI_HANDOFF_2026-05-12.md 的 4 项待验：
##   1) P1 被 Boss 终局激光内圈秒杀后，P2 会话存活、不回退单机
##   2) P2 记分牌/排行榜按槽位显示 "P2"，不暴露真实 ENet peer_id
##   3) 终局激光蓄力/推进时序正确，且推进阶段只检测光束尖端范围
##   4) 精英在场时 Boss 触发进入 pending，杀精英后补发、不被旧引用卡住
##
## 另覆盖两条联机结构性回归（2026-09-27 补）：
##   5) 玩家节点位置同步归属正确：远端幽灵跟随 Host，本机节点不被 Host 覆盖
##   6) 两端玩家节点数恒为 2（引擎场景复制与手工 RPC 不能各生成一份）
##   7) 激光推进 3s + 持续 10s 全程对束外玩家零伤害
##
## 时序断言统一用物理帧计数（Engine.get_physics_frames）：
## headless 无 vsync，墙钟时间与游戏时间不等价，帧计数才是确定量。
##
## 注意：本脚本自身是启动时的 current_scene，不能用 change_scene_to_file()
## 进入主场景（那会把本脚本作为旧场景释放掉），因此手动挂载并接管
## current_scene —— 游戏内部大量代码依赖 get_tree().current_scene。

const MAIN_SCENE := "res://scenes/main.tscn"
const TAG := "[PROBE]"

## 期望值来自 boss.gd 常量：CHARGE=2.0s / TRAVEL=3.0s，60Hz 物理帧
const EXPECT_CHARGE_TICKS := 120
const EXPECT_TRAVEL_TICKS := 180
const TICK_TOLERANCE := 24
## 激光全程对 P2 允许的额外掉血。外圈持续伤害是 10 HP/s，一旦 P2 真落进束里
## 13 秒能扣 130+；余量只用来吸收非激光来源的偶发伤害。
const LASER_HP_TOLERANCE := 20
## 同步归属验证用的标记位置，都刻意避开两端的自然出生点，
## 一旦某端看到自己的节点跑到别人的标记上，就说明 authority 配错了。
const SYNC_MARKER_P1 := Vector2(760, 300)      ## Host 自己 P1 被挪到的位置
const SYNC_MARKER_GHOST_P2 := Vector2(1120, 660) ## Host 上 P2 幽灵被挪到的位置
const SYNC_MARKER_TOLERANCE := 24.0

var _role: String = "host"
var _port: int = 7788
var _t0: int = 0
var _suppress_until_ms: int = 0
var _last_suppress_ms: int = 0
var _main: Node = null
var _boss: Node = null
var _passed: int = 0
var _failed: int = 0
## 客户端逐帧采样结果，见 _sample_sync_authority
var _p2_overwritten: bool = false
var _p1_followed: bool = false


func _ready() -> void:
	## headless 默认无上限跑帧，会让"2 秒蓄力"这类时序断言失去意义；
	## 锁 60fps 让物理帧与墙钟 1:1。
	Engine.max_fps = 60
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() >= 1:
		_role = argv[0].to_lower()
	if argv.size() >= 2:
		_port = int(argv[1])
	_t0 = Time.get_ticks_msec()
	_log("boot port=%d pid=%d" % [_port, OS.get_process_id()])
	_run()


## 期间清场小怪/陨石/敌弹，避免干扰激光时序与死亡判定
func _process(_delta: float) -> void:
	_sample_sync_authority()
	if Time.get_ticks_msec() > _suppress_until_ms:
		return
	if Time.get_ticks_msec() - _last_suppress_ms < 120:
		return
	_last_suppress_ms = Time.get_ticks_msec()
	for group in ["enemies", "asteroids", "enemy_bullets"]:
		for n in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(n):
				continue
			## 精英/Boss 本身就是本轮验证对象，不能被清场逻辑误杀
			if _main_alive() and (n == _main._elite or n == _main._boss):
				continue
			n.queue_free()


func _run() -> void:
	await get_tree().process_frame
	if _role == "host":
		await _host_scenario()
	else:
		await _client_scenario()
	_log("exit")
	## 断言失败要变成非零退出码，否则探针只能靠人肉 grep 日志，
	## 无法作为回归门禁（配合 tests/run_probe.sh 一起用）。
	get_tree().quit(_summarize())


## 手动进入主场景：挂到 root 并接管 current_scene
func _enter_main_scene() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	_main = packed.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main


## 逐帧检查玩家节点的同步归属（只在客户端跑）
##
## 玩家节点位置没有走 main.gd 的手工实体同步（那条只覆盖 _entities 里的
## 敌人/子弹/掉落物），完全依赖 player.tscn 上的 MultiplayerSynchronizer。
## 因此要同时验证两个方向：
##   - 远端 P1 幽灵必须跟到 Host 挪动的位置（Host → Client 通路）
##   - 本机 P2 不能被 Host 幽灵的坐标拽走（Client → Host 不能反向覆盖自己）
##
## 注意：节点随时可能被 queue_free，必须先 is_instance_valid 再 as 强转，
## 顺序反了会每帧抛 "Trying to cast a freed object"。
func _sample_sync_authority() -> void:
	if _role != "client" or not _main_alive():
		return
	if is_instance_valid(_main._player):
		var own := _main._player as Node2D
		if own != null \
				and own.position.distance_to(SYNC_MARKER_GHOST_P2) <= SYNC_MARKER_TOLERANCE:
			_p2_overwritten = true
	if _main._players.has(1) and is_instance_valid(_main._players[1]):
		var ghost := _main._players[1] as Node2D
		if ghost != null \
				and ghost.position.distance_to(SYNC_MARKER_P1) <= SYNC_MARKER_TOLERANCE:
			_p1_followed = true


## ── 等待条件（具名函数，避免多行 lambda 的解析歧义）────────
func _main_alive() -> bool:
	return _main != null and is_instance_valid(_main) and _main.is_inside_tree()


func _cond_both_players() -> bool:
	if not _main_alive():
		return false
	return NetworkManager.connected_peers.size() >= 1 \
		and _main._players.size() == 2 \
		and _main._alive_players.size() == 2


func _cond_elite_alive() -> bool:
	return _main_alive() and _main._elite != null and is_instance_valid(_main._elite)


func _cond_elite_gone() -> bool:
	return not _cond_elite_alive()


func _cond_boss_alive() -> bool:
	return _main_alive() and _main._boss != null and is_instance_valid(_main._boss)


func _cond_laser_charging() -> bool:
	return _boss != null and is_instance_valid(_boss) and _boss._ultimate_laser_charging


func _cond_laser_firing() -> bool:
	return _boss != null and is_instance_valid(_boss) and _boss._ultimate_laser_firing


## 蓄力或持续束中（激光未结束）
func _cond_laser_busy() -> bool:
	return _cond_laser_charging() or _cond_laser_firing()


func _cond_p1_dead() -> bool:
	return _main_alive() and not _main._alive_players.has(1)


func _cond_p1_gone() -> bool:
	return _main_alive() and not _main._players.has(1)


func _cond_local_node() -> bool:
	if not _main_alive():
		return false
	return _main.get_node_or_null(str(multiplayer.get_unique_id())) != null


## 场景树里实际存在的玩家节点数。玩家有两条生成路径（引擎场景复制 + 手工 RPC），
## 一旦两条都生效就会出现重复节点，客户端画出两个同款飞机。
func _player_node_count() -> int:
	if not _main_alive():
		return 0
	return get_tree().get_nodes_in_group("player").size()


## Host 已把 P1 挪到标记点，本端幽灵是否跟到了
func _cond_remote_followed() -> bool:
	return _p1_followed


## 玩家位置同步必须走 main.gd 的手工管线，不能挂在引擎场景复制上。
##
## player.tscn 曾带 MultiplayerSynchronizer，但引擎的 SceneCache 依赖
## 「同步器节点路径可解析」，而客户端挂载 main.tscn 晚于 Host 开始广播，
## 会持续报 Node not found: "Main/1/MultiplayerSynchronizer" 并丢弃同步包，
## 表现为客户端间歇性丢失远端玩家（连节点一起消失）。
func _nodes_with_engine_synchronizer() -> Array:
	var found: Array = []
	if not _main_alive():
		return found
	for pid: Variant in _main._players.keys():
		var node: Node = _main._players[pid]
		if not is_instance_valid(node):
			continue
		if node.get_node_or_null("MultiplayerSynchronizer") != null:
			found.append(int(pid))
	return found


## ── Host 侧场景 ──────────────────────────────────────────────
func _host_scenario() -> void:
	var err: Error = NetworkManager.create_host(_port)
	_check("h0.host_created", err == OK, "err=%d" % err)
	if err != OK:
		return
	_enter_main_scene()
	var ready_ok: bool = await _wait_until(_main_alive, 10.0)
	_check("h1.main_scene_loaded", ready_ok, "")
	if not ready_ok:
		return

	var joined: bool = await _wait_until(_cond_both_players, 40.0)
	_check("h2.client_joined", joined,
		"peers=%d players=%d alive=%d" % [
			NetworkManager.connected_peers.size(),
			_main._players.size(), _main._alive_players.size()])
	if not joined:
		return

	var client_id: int = NetworkManager.connected_peers[0]

	await _wait_seconds(2.0)
	await _verify_peer_labels("h3")

	## 制造两端分数差，验证记分牌跨端刷新 + 槽位标签
	GameState.add_score(500, 1)
	GameState.add_score(700, client_id)
	GameState.force_sync_to_peer(client_id)
	await _wait_seconds(1.5)
	await _verify_peer_labels("h4")
	_check("h5.exactly_two_player_nodes", _player_node_count() == 2,
		"player_nodes=%d" % _player_node_count())
	await _verify_sync_authority(client_id)

	_suppress_until_ms = Time.get_ticks_msec() + 120000
	## 让两端都扛住前置阶段（精英/Boss 登场）的杂兵伤害，
	## 否则可能在激光触发前就死人，污染"被激光秒杀"的归因。
	_grant_health_buffer(1)
	_grant_health_buffer(client_id)

	await _verify_pending_boss()
	await _verify_ultimate_laser(client_id)

	## P1 已死，Hold 8 秒确认联机会话不被拖回单机
	await _wait_seconds(8.0)
	_verify_session_alive(client_id, "h21")

	## 客户端还要再看守（它以"观察到 P1 消失"为同步点），
	## 客户端在 10 秒看守 + 12 秒收尾后退出，这里固定再留 5 秒即可。
	## 不用共享标记文件做跨进程协调：残留文件会造成"读到上一轮结果"的竞态。
	_log("settle for client, then exit")
	await _wait_seconds(5.0)


## 给指定 peer 挂血量缓冲（测试专用，直接写 GameState 内部状态）
func _grant_health_buffer(peer_id: int, hp: int = 100000) -> void:
	GameState.ensure_player_state(peer_id)
	var st: Dictionary = GameState._state(peer_id)
	st["max_health"] = hp
	st["current_health"] = hp
	GameState._mark_dirty()


## 把两个玩家节点挪到标记位置，验证同步归属方向正确
##
## Host 侧断言：P2 幽灵留在标记点（说明客户端没把本机位置推过来覆盖它）
## 客户端侧断言（c4）：P1 幽灵跟到标记点（说明远端玩家位置仍在同步）
func _verify_sync_authority(client_id: int) -> void:
	if not is_instance_valid(_main._player):
		_check("h6.host_nodes_present", false, "host player missing")
		return
	_main._player.position = SYNC_MARKER_P1
	if _main._players.has(client_id) and is_instance_valid(_main._players[client_id]):
		(_main._players[client_id] as Node2D).position = SYNC_MARKER_GHOST_P2
	await _wait_seconds(2.5)
	## 玩家位置不走 main.gd 的手工实体同步（那条只覆盖 _entities），
	## 完全靠 player.tscn 的 MultiplayerSynchronizer，所以 Host 上的 P2 幽灵
	## 必须被客户端的权威坐标拉回客户端真实位置，而不是冻在 Host 挪的标记点。
	var expected: Vector2 = _main._get_networked_player_spawn_position(client_id)
	var err: float = -1.0
	var from_marker: float = -1.0
	if _main._players.has(client_id) and is_instance_valid(_main._players[client_id]):
		var ghost_pos: Vector2 = (_main._players[client_id] as Node2D).position
		err = ghost_pos.distance_to(expected)
		from_marker = ghost_pos.distance_to(SYNC_MARKER_GHOST_P2)
	## reports 用来区分两种失败：客户端压根没上报（同步链路问题）
	## vs 上报了但没应用（插值/权威问题）
	var reports: int = _main.get_player_report_count() if _main.has_method("get_player_report_count") else -1
	_check("h7.client_drives_own_ghost",
		err >= 0.0 and err <= 64.0 and from_marker > SYNC_MARKER_TOLERANCE,
		"err_to_client_pos=%.1f moved_from_marker=%.1f reports=%d" % [err, from_marker, reports])
	var auth_bad: Array = _nodes_with_engine_synchronizer()
	_check("h8.no_engine_player_synchronizer", auth_bad.is_empty(),
		"players_with_synchronizer=%s" % str(auth_bad))


## 验证项 2：UI 槽位标签不得暴露真实 ENet peer_id
func _verify_peer_labels(tag: String) -> void:
	var hud: Node = _main._hud
	if hud == null:
		_check(tag + ".label", false, "hud missing")
		return
	var client_id: int = -1
	if NetworkManager.connected_peers.size() > 0:
		client_id = NetworkManager.connected_peers[0]
	var l1: String = hud._peer_label(1)
	var l2: String = hud._peer_label(client_id)
	var scores_text: String = ""
	if hud._player_scores_label:
		scores_text = hud._player_scores_label.text
	var leaked: Array = []
	for text in [l1, l2, scores_text]:
		for n in _scan_p_labels(str(text)):
			if n > 2:
				leaked.append(n)
	var ok: bool = l1 == "P1" and l2 == "P2" and leaked.is_empty() \
		and scores_text.contains("P1") and scores_text.contains("P2")
	_check(tag + ".label", ok,
		"raw_client_peer_id=%d l1=%s l2=%s scores='%s' leaked=%s" % [
			client_id, l1, l2, scores_text, str(leaked)])


## 验证项 4：精英在场时 Boss 触发挂起，精英死亡后补发
func _verify_pending_boss() -> void:
	_main._spawn_elite()
	var spawned: bool = await _wait_until(_cond_elite_alive, 5.0)
	_check("h8.elite_spawned", spawned, "")
	if not spawned:
		return

	_main._on_boss_spawn_requested(5)
	await get_tree().process_frame
	var pending_ok: bool = _main._pending_boss_level == 5 and _main._boss == null
	_check("h9.pending_while_elite", pending_ok,
		"pending=%d boss=%s" % [_main._pending_boss_level, str(_main._boss)])

	## 精英有护盾：先破盾（进入易伤窗口），再致命一击
	_main._elite.take_damage(999999, 1)
	await _wait_seconds(0.3)
	_main._elite.take_damage(999999, 1)
	var gone: bool = await _wait_until(_cond_elite_gone, 5.0)
	_check("h10.elite_died", gone, "")

	var boss_ok: bool = await _wait_until(_cond_boss_alive, 12.0)
	_check("h11.pending_boss_spawned_after_elite_died", boss_ok,
		"pending=%d elite=%s" % [_main._pending_boss_level, str(_main._elite)])
	if boss_ok:
		_boss = _main._boss
		_log("boss_variant=%d level=%d max_hp=%.0f" % [
			_main._current_boss_variant_id, _boss._level, _boss._max_health])


## 验证项 3 + 1：终局激光时序 + 内圈秒杀 + P2 存活
func _verify_ultimate_laser(client_id: int) -> void:
	if not _cond_boss_alive():
		_check("h12.laser_setup", false, "boss missing")
		return
	_boss = _main._boss
	## 固定战场：Boss 正上方、P1 正下方、Client 在右侧远处
	var p1: Node2D = _main._player
	_boss.position = Vector2(640, 160)
	if p1 != null and is_instance_valid(p1):
		p1.position = Vector2(640, 520)
	_boss.set_target(p1)
	await _wait_seconds(0.5)

	## 探针验的是「真死亡 ≠ 断线」，要绕过 2 人合作的倒地救援路径
	_main.rescue_enabled = false
	## 掉 30 个百分点血量（> BOSS_ULTIMATE_LASER_HP_INTERVAL 的 25 个百分点）触发终局激光
	var max_hp: float = _boss._max_health
	_boss.apply_network_health(max_hp * 0.70, max_hp)

	var charging: bool = await _wait_until(_cond_laser_charging, 3.0)
	var charge_start: int = Engine.get_physics_frames()
	_check("h12.laser_charging", charging, "hp_ratio=0.70 max_hp=%.0f" % max_hp)

	var firing: bool = await _wait_until(_cond_laser_firing, 5.0)
	var fire_start: int = Engine.get_physics_frames()
	var charge_ticks: int = fire_start - charge_start
	_check("h13.laser_charge_duration",
		firing and absi(charge_ticks - EXPECT_CHARGE_TICKS) <= TICK_TOLERANCE,
		"charge_ticks=%d expect=%d+-%d" % [
			charge_ticks, EXPECT_CHARGE_TICKS, TICK_TOLERANCE])

	var died: bool = await _wait_until(_cond_p1_dead, 8.0)
	var death_ticks: int = Engine.get_physics_frames()
	## 推进阶段只检测尖端：P1 距 Boss 360px，光束全长约 1982px，
	## 因此不可能在开火瞬间命中，应在 travel_progress≈0.18*3s≈0.55s 后才死。
	var travel_ticks: int = death_ticks - fire_start
	var tip_ok: bool = died and travel_ticks > 20 and travel_ticks < EXPECT_TRAVEL_TICKS
	_check("h14.laser_tip_advance_only", tip_ok,
		"fire_to_death_ticks=%d expect(20,%d) died=%s" % [travel_ticks, EXPECT_TRAVEL_TICKS, str(died)])
	_check("h15.p1_killed_by_laser", died,
		"alive_players=%s wall_ms=%d" % [str(_main._alive_players.keys()), Time.get_ticks_msec() - _t0])

	var dist: float = -1.0
	if _main._players.has(client_id):
		var cn: Node = _main._players[client_id]
		if is_instance_valid(cn) and cn is Node2D:
			dist = (cn as Node2D).global_position.distance_to(Vector2(640, 520))
	_log("client_player_dist_from_p1=%.1f" % dist)
	_check("h16.p2_not_in_beam", dist > 55.0, "dist=%.1f half_width=55" % dist)
	_check("h17.game_still_running", GameState.game_running,
		"game_running=%s" % str(GameState.game_running))
	_check("h18.no_fallback_flag", _main._fallback_in_progress == false,
		"fallback=%s" % str(_main._fallback_in_progress))
	_verify_session_alive(client_id, "h19")

	## h16 只验证「P2 被摆在束外」这个几何事实，真正要证明的是
	## 「推进 3s + 持续 10s 全程都没碰到 P2」：逐帧采样 P2 血量，
	## 落进内圈会被秒杀（0 血），落进外圈也会按 10 HP/s 稳定扣，两者都能被抓住。
	var p2_hp_before: int = GameState.get_current_health(client_id)
	var min_p2_hp: int = p2_hp_before
	var beam_deadline: int = Time.get_ticks_msec() + 16000
	while _cond_laser_busy() and Time.get_ticks_msec() < beam_deadline:
		await get_tree().process_frame
		min_p2_hp = mini(min_p2_hp, GameState.get_current_health(client_id))
	var beam_done: bool = not _cond_laser_busy()
	_check("h20.laser_never_touched_p2",
		beam_done and min_p2_hp >= p2_hp_before - LASER_HP_TOLERANCE \
			and _main._alive_players.has(client_id),
		"beam_done=%s p2_hp %d->%d tol=%d alive=%s" % [
			str(beam_done), p2_hp_before, min_p2_hp, LASER_HP_TOLERANCE,
			str(_main._alive_players.has(client_id))])


## 联机会话存活检查：不得断网、不得回退单机、队友仍在
func _verify_session_alive(client_id: int, tag: String) -> void:
	var main_ok: bool = _main_alive()
	var online: bool = NetworkManager.is_online()
	var no_fallback: bool = main_ok and _main._fallback_in_progress == false
	var client_alive: bool = main_ok and _main._alive_players.has(client_id)
	var client_node_ok: bool = main_ok and _main._players.has(client_id) \
		and is_instance_valid(_main._players[client_id])
	var p2_hp_ok: bool = GameState.is_player_alive(client_id)
	_check(tag + ".session_alive",
		main_ok and online and no_fallback and client_alive and client_node_ok and p2_hp_ok,
		"main_alive=%s online=%s no_fallback=%s client_alive=%s node=%s p2_hp=%s" % [
			str(main_ok), str(online), str(no_fallback),
			str(client_alive), str(client_node_ok), str(p2_hp_ok)])


## ── Client 侧场景 ────────────────────────────────────────────
func _client_scenario() -> void:
	var joined: bool = false
	var attempts: int = 0
	## 注意：Godot 4 里 multiplayer.multiplayer_peer 默认是 OfflineMultiplayerPeer，
	## 永远不为 null，不能用它判断"是否已在连接"，必须走 NetworkManager 的信号。
	var link_state: Array = ["idle"]
	NetworkManager.connection_succeeded.connect(func() -> void: link_state[0] = "ok")
	NetworkManager.connection_failed.connect(func() -> void: link_state[0] = "fail")
	var join_deadline: int = Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < join_deadline:
		if NetworkManager.is_online():
			joined = true
			break
		if link_state[0] == "fail":
			attempts += 1
			link_state[0] = "idle"
			NetworkManager.disconnect_network()
			if attempts >= 20:
				break
		elif link_state[0] == "idle":
			NetworkManager.join_host("127.0.0.1", _port)
			link_state[0] = "connecting"
		await _wait_seconds(0.2)
	_check("c0.joined_host", joined, "attempts=%d link_state=%s" % [attempts, str(link_state[0])])
	if not joined:
		return

	_enter_main_scene()
	var ready_ok: bool = await _wait_until(_main_alive, 10.0)
	_check("c1.main_scene_loaded", ready_ok, "")
	if not ready_ok:
		return
	var my_id: int = multiplayer.get_unique_id()
	var has_node: bool = await _wait_until(_cond_local_node, 25.0)
	_check("c2.local_player_node", has_node, "my_peer_id=%d" % my_id)
	if not has_node:
		return

	await _wait_seconds(2.0)
	await _verify_peer_labels_client(my_id, "c3")

	## 同步归属双向验证（配合 Host 侧 h7）：
	## 远端 P1 幽灵必须跟到 Host 挪动的标记点 —— 证明玩家位置同步仍然工作；
	## 本机 P2 绝不能出现在 Host 幽灵的标记点 —— 证明同步器权威没有配反。
	var followed: bool = await _wait_until(_cond_remote_followed, 8.0)
	## local_player_valid 用来判断客户端的 _player 引用是否已就绪：
	## 它是"客户端有没有在上报坐标"的前提，null 就永远不会发
	_check("c4.remote_player_follows_host", followed,
		"p1_ghost_at_marker=%s players=%s local_player_valid=%s reports_sent=%d" % [
			str(_p1_followed), str(_main._players.keys()),
			str(_main._player != null and is_instance_valid(_main._player)),
			_main.get_player_report_sent() if _main.has_method("get_player_report_sent") else -1])
	_check("c5.exactly_two_player_nodes", _player_node_count() == 2,
		"player_nodes=%d" % _player_node_count())

	## 阶段 A：等待观察到 P1（peer 1）被移除 —— 这正是本轮被测事件。
	## 用"观察到 P1 消失"做同步点，比共享标记文件更可靠（无竞态）。
	var saw_p1_gone: bool = await _wait_until(_cond_p1_gone, 90000)
	var detail: String = "main gone"
	if _main_alive():
		detail = "players=%s alive=%s" % [str(_main._players.keys()), str(_main._alive_players.keys())]
	_check("c6.observed_p1_death", saw_p1_gone, detail)

	## 阶段 B：P1 死后继续看守 10 秒，确认本端没有被拖回单机
	var samples: int = 0
	var bad_online: int = 0
	var bad_running: int = 0
	var lost_node: int = 0
	for i in range(10):
		await _wait_seconds(1.0)
		samples += 1
		var online: bool = NetworkManager.is_online()
		var running: bool = GameState.game_running
		var node_ok: bool = _cond_local_node()
		if not online:
			bad_online += 1
		if not running:
			bad_running += 1
		if not node_ok:
			lost_node += 1
		_log("watchdog s=%d online=%s running=%s node=%s" % [
			samples, str(online), str(running), str(node_ok)])
	_check("c7.watched_after_p1_death", samples == 10, "samples=%d" % samples)
	_check("c8.never_disconnected", bad_online == 0, "bad_online=%d/%d" % [bad_online, samples])
	_check("c9.never_game_over", bad_running == 0, "bad_running=%d/%d" % [bad_running, samples])
	_check("c10.never_lost_local_player", lost_node == 0, "lost_node=%d/%d" % [lost_node, samples])

	_verify_session_alive(my_id, "c11")
	## 整轮采样下来本机 P2 都没被 Host 的幽灵坐标覆盖
	_check("c12.local_player_not_overwritten", not _p2_overwritten,
		"own_player_hit_ghost_marker=%s" % str(_p2_overwritten))
	var auth_bad: Array = _nodes_with_engine_synchronizer()
	_check("c13.no_engine_player_synchronizer", auth_bad.is_empty(),
		"players_with_synchronizer=%s" % str(auth_bad))

	## 收尾：Host 还要等激光推进 3s + 持续 10s 跑完（h20/h21），
	## 这段时间本端必须保持在线，否则 Host 会把 P2 判为掉线并清掉幽灵节点。
	## Host 侧 h21 之后只留 5 秒收尾，所以这个 12 秒足够且不会互相等到对方退出。
	_log("settle for host laser tail, then exit")
	await _wait_seconds(12.0)


func _verify_peer_labels_client(my_id: int, tag: String) -> void:
	var hud: Node = _main._hud
	if hud == null:
		_check(tag + ".label", false, "hud missing")
		return
	var self_label: String = hud._peer_label(my_id)
	var scores_text: String = ""
	if hud._player_scores_label:
		scores_text = hud._player_scores_label.text
	var leaked: Array = []
	for n in _scan_p_labels(self_label) + _scan_p_labels(scores_text):
		if n > 2:
			leaked.append(n)
	var ok: bool = self_label == "P2" and leaked.is_empty() \
		and scores_text.contains("P1") and scores_text.contains("P2")
	_check(tag + ".label", ok,
		"raw_my_peer_id=%d self_label=%s scores='%s' leaked=%s" % [
			my_id, self_label, scores_text, str(leaked)])


## ── 工具 ─────────────────────────────────────────────────────
func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _wait_seconds(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _scan_p_labels(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("P(\\d+)")
	for m in re.search_all(text):
		out.append(int(m.get_string(1)))
	return out


func _log(message: String) -> void:
	print("%s[%s] t=%dms %s" % [TAG, _role, Time.get_ticks_msec() - _t0, message])


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("%s[%s] VERDICT %s pass=%s | %s" % [TAG, _role, name, str(ok).to_lower(), detail])


## 打印汇总并返回进程退出码：0 = 全绿，1 = 有断言失败
func _summarize() -> int:
	print("%s[%s] VERDICT SUMMARY pass=%d failed=%d total=%d" % [
		TAG, _role, _passed, _failed, _passed + _failed])
	return 1 if _failed > 0 else 0
