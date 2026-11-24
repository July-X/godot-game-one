extends Node
## 恢复握手只管理连接。战斗权威和原玩家槽位始终保留在 Main。

const GRACE_MS := 20_000
const QUIET_MS := 3_000
const REOPEN_MS := 6_000
const RETRY_MS := 2_500
const NONCE_SIZE := 16
const TAG_SIZE := 32

@onready var _network: Node = get_parent()
@onready var _api := multiplayer as SceneMultiplayer
var _timer: Timer
var battle: Node
var guest_slot := 0
var guest_wire := 0
var round_id := 0
var ticket := PackedByteArray()
var local_background := false
var remote_background := false
var deadline := 0
var _heard_at := 0
var _attempt_at := 0
var _epoch := 0
var _offered := 0
var _offered_at := 0
var _applied := 0
var _challenges := {}
var _verified_peer := 0
var _crypto := Crypto.new()
var _owns_pause := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_api.auth_timeout = 2.0
	_api.peer_authenticating.connect(_on_authenticating)
	_api.peer_authentication_failed.connect(_forget_auth)
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.ignore_time_scale = true
	_timer.timeout.connect(_service)
	add_child(_timer)


func bind_battle(node: Node, host_round: int) -> void:
	battle = node
	_heard_at = Time.get_ticks_msec()
	_timer.start()
	if not _network.is_host:
		_api.auth_callback = _authenticate
		return
	if guest_slot == 0 and not _network.connected_peers.is_empty():
		guest_slot = _network.connected_peers[0]
		guest_wire = guest_slot
	if guest_slot > 0 and host_round != round_id:
		_api.auth_callback = _authenticate
		round_id = host_round
		ticket = _crypto.generate_random_bytes(TAG_SIZE)
		_rpc_ticket.rpc_id(guest_wire, round_id, guest_slot, ticket)


func is_reserved() -> bool:
	return is_instance_valid(battle) and round_id > 0 and ticket.size() == TAG_SIZE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		set_background(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		set_background(false)


func set_background(background: bool) -> void:
	if not is_reserved() or background == local_background:
		return
	local_background = background
	if not background and _expired():
		_service()
		return
	if background:
		_hold()
	_send_presence()
	if not background:
		_service()


func slot_for_wire(peer_id: int) -> int:
	if peer_id == guest_wire and guest_slot > 0:
		return guest_slot
	return peer_id if guest_slot == 0 or peer_id == 1 else 0


func wire_for_slot(slot: int) -> int:
	return guest_wire if guest_slot > 0 and slot == guest_slot else slot


func clear() -> void:
	_release()
	battle = null
	guest_slot = 0
	guest_wire = 0
	round_id = 0
	ticket.clear()
	local_background = false
	remote_background = false
	_applied = 0
	_epoch = 0
	_attempt_at = 0
	_challenges.clear()
	_verified_peer = 0
	_api.auth_callback = Callable()
	_timer.stop()


func _wire() -> int:
	return guest_wire if _network.is_host else 1


func _linked() -> bool:
	return _network.is_online() and _wire() > 0 and _api.get_peers().has(_wire())


func _trusted_sender() -> bool:
	return is_reserved() and _linked() and multiplayer.get_remote_sender_id() == _wire()

func _expired() -> bool:
	return deadline > 0 and Time.get_ticks_msec() >= deadline


func _hold() -> void:
	if deadline > 0:
		return
	deadline = Time.get_ticks_msec() + GRACE_MS
	_owns_pause = not get_tree().paused
	battle.set_lan_hold(true)
	battle.update_lan_wait(ceili(float(GRACE_MS) / 1000.0), false)
	get_tree().paused = true


func _release() -> void:
	if deadline == 0:
		return
	deadline = 0
	_offered = 0
	if is_instance_valid(battle):
		battle.set_lan_hold(false)
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false


func on_transport_lost() -> void:
	_hold()
	_offered = 0
	remote_background = true
	guest_wire = 0
	_challenges.clear()
	_verified_peer = 0
	_heard_at = Time.get_ticks_msec()
	_attempt_at = 0


func on_wire_ready(peer_id: int) -> void:
	if deadline == 0:
		return
	if _network.is_host and _verified_peer == peer_id:
		guest_wire = peer_id
		_verified_peer = 0
	elif not _network.is_host:
		guest_wire = multiplayer.get_unique_id()
	if peer_id != _wire():
		return
	_heard_at = Time.get_ticks_msec()
	_send_presence()


func notify_exit() -> bool:
	if is_reserved() and _linked():
		var method := "_rpc_host_exit" if _network.is_host else "_rpc_guest_exit"
		var sent := rpc_id(_wire(), method, round_id)
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		peer.host.flush()
		return sent == OK
	return false


func _service() -> void:
	if not is_reserved():
		return
	var now := Time.get_ticks_msec()
	if deadline > 0 and now >= deadline:
		if not local_background:
			_network.finish_lan_wait("联机恢复超时，切换为单人模式")
		return
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if is_instance_valid(peer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_network.drop_lan_transport()
	if _linked():
		if _network.is_host:
			_rpc_host_heartbeat.rpc_id(_wire(), round_id)
		else:
			_rpc_guest_heartbeat.rpc_id(1, round_id)
		var quiet := now - _heard_at
		if quiet >= QUIET_MS and not local_background and deadline == 0:
			_hold()
			_send_presence()
		if quiet >= REOPEN_MS and not local_background:
			if _network.is_host:
				var old_wire := _wire()
				on_transport_lost()
				_network.connected_peers.erase(old_wire)
				_api.disconnect_peer(old_wire)
			else:
				_network.drop_lan_transport()
			return
	elif deadline > 0 and not local_background and now - _attempt_at >= RETRY_MS:
		_attempt_at = now
		_network.retry_lan_transport()
	if deadline > 0 and is_instance_valid(battle):
		battle.update_lan_wait(ceili(float(deadline - now) / 1000.0), _linked() and not remote_background)
	_offer_if_ready()


func _send_presence() -> void:
	if _linked():
		if _network.is_host:
			_rpc_host_presence.rpc_id(_wire(), round_id, local_background, deadline > 0)
		else:
			_rpc_guest_presence.rpc_id(1, round_id, local_background, deadline > 0)
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		peer.host.flush()


func _offer_if_ready() -> void:
	if not _network.is_host or deadline == 0 or _expired() or local_background or remote_background or not _linked():
		return
	var now := Time.get_ticks_msec()
	if now - _heard_at >= QUIET_MS or (_offered > 0 and now - _offered_at < RETRY_MS):
		return
	_epoch += 1
	_offered = _epoch
	_offered_at = now
	var state: Dictionary = battle.send_lan_resume_snapshot(_wire())
	_rpc_resume_snapshot.rpc_id(_wire(), round_id, _offered, state)


@rpc("authority", "reliable", "call_remote")
func _rpc_ticket(new_round: int, slot: int, key: PackedByteArray) -> void:
	if _network.is_host or new_round <= round_id or key.size() != TAG_SIZE:
		return
	round_id = new_round
	guest_slot = slot
	guest_wire = multiplayer.get_unique_id()
	ticket = key
	_heard_at = Time.get_ticks_msec()


@rpc("authority", "reliable", "call_remote", 1)
func _rpc_host_heartbeat(match_round: int) -> void:
	_hear_heartbeat(match_round)

@rpc("any_peer", "reliable", "call_remote", 1)
func _rpc_guest_heartbeat(match_round: int) -> void:
	if not multiplayer.is_server():
		return
	_hear_heartbeat(match_round)

func _hear_heartbeat(match_round: int) -> void:
	if not _trusted_sender() or match_round != round_id:
		return
	_heard_at = Time.get_ticks_msec()


@rpc("authority", "reliable", "call_remote")
func _rpc_host_presence(match_round: int, background: bool, held: bool) -> void:
	_receive_presence(match_round, background, held)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_guest_presence(match_round: int, background: bool, held: bool) -> void:
	if not multiplayer.is_server():
		return
	_receive_presence(match_round, background, held)

func _receive_presence(match_round: int, background: bool, held: bool) -> void:
	if not _trusted_sender() or match_round != round_id:
		return
	_heard_at = Time.get_ticks_msec()
	remote_background = background
	if background or held:
		_hold()
	if background:
		_offered = 0
	_offer_if_ready()


@rpc("authority", "reliable", "call_remote")
func _rpc_resume_snapshot(match_round: int, epoch: int, state: Dictionary) -> void:
	if not _trusted_sender() or match_round != round_id or epoch <= _applied or local_background or _expired():
		return
	_hold()
	if not battle.apply_lan_resume_snapshot(state):
		return
	_applied = epoch
	_rpc_resume_ready.rpc_id(1, match_round, epoch)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_resume_ready(match_round: int, epoch: int) -> void:
	if not multiplayer.is_server():
		return
	if not _trusted_sender() or match_round != round_id or epoch == 0 or epoch != _offered or local_background or remote_background or _expired():
		return
	_rpc_resume_play.rpc_id(_wire(), match_round, epoch)
	_release()


@rpc("authority", "reliable", "call_remote")
func _rpc_resume_play(match_round: int, epoch: int) -> void:
	if _trusted_sender() and match_round == round_id and epoch == _applied and not local_background and not _expired():
		remote_background = false
		_release()


@rpc("authority", "reliable", "call_remote")
func _rpc_host_exit(match_round: int) -> void:
	_receive_exit(match_round)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_guest_exit(match_round: int) -> void:
	if not multiplayer.is_server():
		return
	_receive_exit(match_round)

func _receive_exit(match_round: int) -> void:
	if _trusted_sender() and match_round == round_id:
		var message := "队友已退出，切换为单人模式" if _network.is_host else "房主已退出，切换为单人模式"
		_network.finish_lan_wait.call_deferred(message)


func _on_authenticating(peer_id: int) -> void:
	if not is_reserved():
		_api.complete_auth(peer_id)
		return
	if not _network.is_host:
		return  # 加入端等房主先证明持有同一个凭证。
	if deadline == 0 or Time.get_ticks_msec() >= deadline or guest_wire != 0:
		_api.disconnect_peer(peer_id)
		return
	var nonce := _crypto.generate_random_bytes(NONCE_SIZE)
	_challenges[peer_id] = nonce
	_api.send_auth(peer_id, nonce + _proof(nonce, "host"))


func _proof(nonce: PackedByteArray, side: String) -> PackedByteArray:
	return _crypto.hmac_digest(HashingContext.HASH_SHA256, ticket, (side + str(round_id)).to_utf8_buffer() + nonce)

func _forget_auth(peer_id: int) -> void:
	_challenges.erase(peer_id)
	if _verified_peer == peer_id:
		_verified_peer = 0


func _authenticate(peer_id: int, data: PackedByteArray) -> void:
	if not is_reserved() or deadline == 0 or Time.get_ticks_msec() >= deadline:
		_api.disconnect_peer(peer_id)
		return
	if _network.is_host:
		var nonce: PackedByteArray = _challenges.get(peer_id, PackedByteArray())
		_challenges.erase(peer_id)
		if nonce.is_empty() or guest_wire != 0 or not _crypto.constant_time_compare(data, _proof(nonce, "guest")):
			_api.disconnect_peer(peer_id)
			return
		_verified_peer = peer_id
	else:
		var nonce := data.slice(0, NONCE_SIZE)
		if peer_id != 1 or data.size() != NONCE_SIZE + TAG_SIZE or not _crypto.constant_time_compare(data.slice(NONCE_SIZE), _proof(nonce, "host")):
			_api.disconnect_peer(peer_id)
			return
		_api.send_auth(peer_id, _proof(nonce, "guest"))
	_api.complete_auth(peer_id)
