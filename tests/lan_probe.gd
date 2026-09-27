extends Node
## 联机回归探针（headless 双进程，真实 ENet 回环）
##
## 用法（两个终端同时跑，端口可换）：
##   godot --headless --path . res://tests/lan_probe.tscn -- host 7788
##   godot --headless --path . res://tests/lan_probe.tscn -- client 7788
##
## 覆盖 docs/AI_HANDOFF_2026-05-12.md 的 4 项待验：
##   1) P1 被 Boss 终局激光内圈秒杀后，P2 会话存活、不回退单机
##   2) P2 记分牌/排行榜按槽位显示 "P2"，不暴露真实 ENet peer_id
##   3) 终局激光蓄力/推进时序正确，且推进阶段只检测光束尖端范围
##   4) 精英在场时 Boss 触发进入 pending，杀精英后补发、不被旧引用卡住
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

var _role: String = "host"
var _port: int = 7788
var _t0: int = 0
var _suppress_until_ms: int = 0
var _last_suppress_ms: int = 0
var _main: Node = null
var _boss: Node = null


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
	get_tree().quit()


## 手动进入主场景：挂到 root 并接管 current_scene
func _enter_main_scene() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	_main = packed.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main


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


func _cond_p1_dead() -> bool:
	return _main_alive() and not _main._alive_players.has(1)


func _cond_p1_gone() -> bool:
	return _main_alive() and not _main._players.has(1)


func _cond_local_node() -> bool:
	if not _main_alive():
		return false
	return _main.get_node_or_null(str(multiplayer.get_unique_id())) != null


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

	_suppress_until_ms = Time.get_ticks_msec() + 120000
	## 让两端都扛住前置阶段（精英/Boss 登场）的杂兵伤害，
	## 否则可能在激光触发前就死人，污染"被激光秒杀"的归因。
	_grant_health_buffer(1)
	_grant_health_buffer(client_id)

	await _verify_pending_boss()
	await _verify_ultimate_laser(client_id)

	## P1 已死，Hold 8 秒确认联机会话不被拖回单机
	await _wait_seconds(8.0)
	_verify_session_alive(client_id, "h9")

	## 客户端还要再看守 10 秒（它以"观察到 P1 消失"为同步点），
	## 这里固定再留 15 秒给客户端收尾，然后退出。
	## 不用共享标记文件做跨进程协调：残留文件会造成"读到上一轮结果"的竞态。
	_log("settle for client, then exit")
	await _wait_seconds(15.0)


## 给指定 peer 挂血量缓冲（测试专用，直接写 GameState 内部状态）
func _grant_health_buffer(peer_id: int, hp: int = 100000) -> void:
	GameState.ensure_player_state(peer_id)
	var st: Dictionary = GameState._state(peer_id)
	st["max_health"] = hp
	st["current_health"] = hp
	GameState._mark_dirty()


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
	_check("h5.elite_spawned", spawned, "")
	if not spawned:
		return

	_main._on_boss_spawn_requested(5)
	await get_tree().process_frame
	var pending_ok: bool = _main._pending_boss_level == 5 and _main._boss == null
	_check("h6.pending_while_elite", pending_ok,
		"pending=%d boss=%s" % [_main._pending_boss_level, str(_main._boss)])

	## 精英有护盾：先破盾（进入易伤窗口），再致命一击
	_main._elite.take_damage(999999, 1)
	await _wait_seconds(0.3)
	_main._elite.take_damage(999999, 1)
	var gone: bool = await _wait_until(_cond_elite_gone, 5.0)
	_check("h7.elite_died", gone, "")

	var boss_ok: bool = await _wait_until(_cond_boss_alive, 12.0)
	_check("h8.pending_boss_spawned_after_elite_died", boss_ok,
		"pending=%d elite=%s" % [_main._pending_boss_level, str(_main._elite)])
	if boss_ok:
		_boss = _main._boss
		_log("boss_variant=%d level=%d max_hp=%.0f" % [
			_main._current_boss_variant_id, _boss._level, _boss._max_health])


## 验证项 3 + 1：终局激光时序 + 内圈秒杀 + P2 存活
func _verify_ultimate_laser(client_id: int) -> void:
	if not _cond_boss_alive():
		_check("h10.laser_setup", false, "boss missing")
		return
	_boss = _main._boss
	## 固定战场：Boss 正上方、P1 正下方、Client 在右侧远处
	var p1: Node2D = _main._player
	_boss.position = Vector2(640, 160)
	if p1 != null and is_instance_valid(p1):
		p1.position = Vector2(640, 520)
	_boss.set_target(p1)
	await _wait_seconds(0.5)

	## 掉 30% 血量（> 15% 触发间隔）触发终局激光
	var max_hp: float = _boss._max_health
	_boss.apply_network_health(max_hp * 0.70, max_hp)

	var charging: bool = await _wait_until(_cond_laser_charging, 3.0)
	var charge_start: int = Engine.get_physics_frames()
	_check("h10.laser_charging", charging, "hp_ratio=0.70 max_hp=%.0f" % max_hp)

	var firing: bool = await _wait_until(_cond_laser_firing, 5.0)
	var fire_start: int = Engine.get_physics_frames()
	var charge_ticks: int = fire_start - charge_start
	_check("h11.laser_charge_duration",
		firing and absi(charge_ticks - EXPECT_CHARGE_TICKS) <= TICK_TOLERANCE,
		"charge_ticks=%d expect=%d+-%d" % [
			charge_ticks, EXPECT_CHARGE_TICKS, TICK_TOLERANCE])

	var died: bool = await _wait_until(_cond_p1_dead, 8.0)
	var death_ticks: int = Engine.get_physics_frames()
	## 推进阶段只检测尖端：P1 距 Boss 360px，光束全长约 1982px，
	## 因此不可能在开火瞬间命中，应在 travel_progress≈0.18*3s≈0.55s 后才死。
	var travel_ticks: int = death_ticks - fire_start
	var tip_ok: bool = died and travel_ticks > 20 and travel_ticks < EXPECT_TRAVEL_TICKS
	_check("h12.laser_tip_advance_only", tip_ok,
		"fire_to_death_ticks=%d expect(20,%d) died=%s" % [travel_ticks, EXPECT_TRAVEL_TICKS, str(died)])
	_check("h13.p1_killed_by_laser", died,
		"alive_players=%s wall_ms=%d" % [str(_main._alive_players.keys()), Time.get_ticks_msec() - _t0])

	var dist: float = -1.0
	if _main._players.has(client_id):
		var cn: Node = _main._players[client_id]
		if is_instance_valid(cn) and cn is Node2D:
			dist = (cn as Node2D).global_position.distance_to(Vector2(640, 520))
	_log("client_player_dist_from_p1=%.1f" % dist)
	_check("h14.p2_not_in_beam", dist > 55.0, "dist=%.1f half_width=55" % dist)
	_check("h15.game_still_running", GameState.game_running,
		"game_running=%s" % str(GameState.game_running))
	_check("h16.no_fallback_flag", _main._fallback_in_progress == false,
		"fallback=%s" % str(_main._fallback_in_progress))
	_verify_session_alive(client_id, "h17")


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

	## 阶段 A：等待观察到 P1（peer 1）被移除 —— 这正是本轮被测事件。
	## 用"观察到 P1 消失"做同步点，比共享标记文件更可靠（无竞态）。
	var saw_p1_gone: bool = await _wait_until(_cond_p1_gone, 90000)
	var detail: String = "main gone"
	if _main_alive():
		detail = "players=%s alive=%s" % [str(_main._players.keys()), str(_main._alive_players.keys())]
	_check("c4.observed_p1_death", saw_p1_gone, detail)

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
	_check("c5.watched_after_p1_death", samples == 10, "samples=%d" % samples)
	_check("c6.never_disconnected", bad_online == 0, "bad_online=%d/%d" % [bad_online, samples])
	_check("c7.never_game_over", bad_running == 0, "bad_running=%d/%d" % [bad_running, samples])
	_check("c8.never_lost_local_player", lost_node == 0, "lost_node=%d/%d" % [lost_node, samples])

	_verify_session_alive(my_id, "c9")


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
	print("%s[%s] VERDICT %s pass=%s | %s" % [TAG, _role, name, str(ok).to_lower(), detail])
