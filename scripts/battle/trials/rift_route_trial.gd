extends "res://scripts/battle/trials/opening_trial.gd"
## Authored encounter clock; player and projectile physics remain in Main.
enum Leg { INTERCEPT, BUILD, ELITE, BOSS }
const HUNTER_ENTRY_SECONDS := 0.26
const CARD_TICK := 35 * 60
const ELITE_LEG := 90 * 60
const SETTLE_TICK := 197 * 60
const BOSS_LEG := 210 * 60
const HUNTER_EXPOSURE_BONUS := 1.0
const PRACTICE_WAVES := {78: .28, 1110: .72}
const BUILD_WAVES := [CARD_TICK + 90, CARD_TICK + 760, CARD_TICK + 1770, ELITE_LEG + 54, 138 * 60, 168 * 60]
const LEG_NAMES := ["拦截齐射", "让卡牌改变航线", "裂隙猎手", "裂隙母舰"]
const LEG_HINTS := ["", "从侧翼截断齐射，中路可绕行", "可绕行 · 击破猎手，母舰首次破盾多 1 秒", "被标记先横移，侧翼打盾"]
const HUNTER_NOTICE := {"earned": "猎手已击破 · 母舰首次破盾多 1 秒",
	"spent": "猎手奖励兑现 · 这次破盾多 1 秒"}
const LEG_HINT_SECONDS := 2.0
const CUT_CUE_TICKS := 27
var leg := Leg.INTERCEPT
var _settling := false
var _route_hint_left := 0.0
var _build_hint_pending := false
var _draft_wait := false
var _pending_slots: Dictionary[int, bool] = {}
var _route_outcome := ""
var _hunter_defeated := false
var _hunter_reward_spent := false
var _route_notice := ""
var _remote_cues: Dictionary[int, int] = {}
var _cut_cues: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	$TrialUI/Options/Buttons/Retry.visible = _authoritative()
	if _authoritative():
		volley_interrupted.connect(func(role: String, _at: Vector2, deadline: int):
			_log("interrupted", {"role": role, "release": deadline}))
	else:
		(multiplayer as SceneMultiplayer).peer_packet.connect(_on_route_packet)
	_log("start", {})
	_update_countdown()

func _authoritative() -> bool:
	return not NetworkManager.is_online() or multiplayer.is_server()

func _elite_entry_seconds() -> float:
	return HUNTER_ENTRY_SECONDS

func _physics_process(delta: float) -> void:
	# Invoke Main's rescue tick through the extracted production hook.
	_tick_rescue_window()
	if finished or not GameState.game_running:
		return
	while not _cut_cues.is_empty() and trial_tick >= int(_cut_cues[0].until):
		_cut_cues.pop_front()
		_cues.queue_redraw()
	if _route_hint_left > 0.0:
		_route_hint_left = maxf(0.0, _route_hint_left - delta)
		if _route_hint_left == 0.0:
			_route_notice = ""
			_update_countdown()
	if not _authoritative():
		trial_tick += 1
		for eid: int in _remote_cues.keys():
			var ship: Node2D = _entities.get(eid)
			if trial_tick >= _remote_cues[eid]:
				_remote_cues.erase(eid)
			elif is_instance_valid(ship):
				_fighters[str(eid)] = {"ship": ship, "fire": _remote_cues[eid]}
		for key: String in _fighters.keys():
			if not _remote_cues.has(int(key)) or not is_instance_valid(_fighters[key].ship):
				_fighters.erase(key)
		_cues.queue_redraw()
		return
	if _draft_wait:
		return
	trial_tick += 1
	if trial_tick == CARD_TICK:
		_set_leg(Leg.BUILD)
		_open_route_drafts()
	if PRACTICE_WAVES.has(trial_tick):
		_add_fighter("intercept-%d" % trial_tick, 1, Vector2(PRACTICE_WAVES[trial_tick], .36), 174)
		_log("wave", {"id": trial_tick, "type": "intercept"})
	if trial_tick in BUILD_WAVES:
		var slot := BUILD_WAVES.find(trial_tick)
		if slot < 2:
			_add_intercept_wave(slot == 1)
		else:
			_add_build(.025, slot % 2 == 1)
		_log("wave", {"id": slot, "type": "build", "mirrored": slot % 2 == 1})
	if trial_tick == ELITE_LEG:
		_set_leg(Leg.ELITE)
	if trial_tick == ELITE_LEG + 155:
		_spawn_elite()
		_elite.enable_route_combat(HUNTER_ENTRY_SECONDS)
		_elite.route_evaded.connect(func(): _log("elite_side_step", {}))
	if trial_tick == SETTLE_TICK:
		_elite = null
		_clear_non_boss_entities()
		_fighters.clear()
		_breaks.clear()
		_cut_cues.clear()
		_cues.queue_redraw()
		_apply_route_leg(leg, true)
		if NetworkManager.is_online():
			_rpc_route_leg.rpc(leg, true)
	if trial_tick == BOSS_LEG:
		_set_leg(Leg.BOSS)
		_start_route_boss()
	if not _fighters.is_empty() or not _breaks.is_empty() or not _cut_cues.is_empty():
		_move_fighters()
		while not _breaks.is_empty() and trial_tick >= int(_breaks[0].until):
			_breaks.pop_front()
		_cues.queue_redraw()
	if trial_tick % 60 == 0 and (trial_tick < SETTLE_TICK or trial_tick >= BOSS_LEG):
		_update_countdown()

func _add_intercept_wave(mirrored: bool) -> void:
	var column := .74 if mirrored else .26
	var cluster := .35 if mirrored else .65
	var wing := .14 if mirrored else .86
	var side := -1.0 if mirrored else 1.0
	_add_fighter("column-front", 0, Vector2(column, .54), 0, 0, -15.0 * side)
	_add_fighter("column-middle", 0, Vector2(column, .405), 0, 0, 19.0 * side)
	_add_fighter("column-rear", 1, Vector2(column, .27), 225 if mirrored else 201)
	_add_fighter("cluster-front", 0, Vector2(cluster, .42))
	_add_fighter("cluster-neighbor", 0, Vector2(cluster, .39), 0, 0, -47.0 * side)
	_add_fighter("cluster-rear", 1, Vector2(cluster, .39), 194 if mirrored else 220, 0, 47.0 * side)
	_add_fighter("wing", 1, Vector2(wing, .38), 208 if mirrored else 193, ARMOR_HP)

func _draw_fan_heading(center: Vector2, at: Vector2, progress: float) -> void:
	var ink := Color(1.0, .60, .40, lerpf(.3, .82, progress))
	for offset: float in FAN_EXIT_OFFSETS:
		var direction := _fan_direction(at, offset)
		_cues.draw_dashed_line(center + direction * 34, center + direction * lerpf(82, 140, progress),
			ink, 1.5, 9.0, false)
	if leg == Leg.BUILD:
		for side: float in [-1.0, 1.0]:
			var edge := center + Vector2(side * 24.0, 0)
			_cues.draw_polyline(PackedVector2Array([edge + Vector2(-side * 7, -9), edge,
				edge + Vector2(-side * 7, 9)]), ink, 2.5, true)

func _draw_cues() -> void:
	super._draw_cues()
	if leg == Leg.BUILD and _fighters.values().any(func(order: Dictionary): return _is_charging(order)):
		for side: float in [-1.0, 1.0]:
			var x := field.x * .5 + side * minf(field.x * .045, 32.0)
			_cues.draw_dashed_line(Vector2(x, field.y * .44), Vector2(x, field.y * .66),
				Color(.54, .87, 1.0, .24), 1.5, 10.0, false)
	for cue: Dictionary in _cut_cues:
		var alpha := float(int(cue.until) - trial_tick) / CUT_CUE_TICKS
		for index: int in 3:
			var at: Vector2 = cue.at + Vector2((index - 1) * 13, 37 - (1.0 - alpha) * 14)
			_cues.draw_line(at + Vector2(-4, 5), at + Vector2(4, -5),
				Color(.66, 1.0, .88, alpha), 2.5, true)

func _on_emitter_died(role: String) -> void:
	var cuts_before := interruptions
	super._on_emitter_died(role)
	if interruptions == cuts_before:
		return
	var order: Dictionary = _fighters[role]
	# Cancel the queued release explicitly before showing a confirmed cut.
	order.fire = -1
	if leg == Leg.BUILD:
		var at: Vector2 = order.ship.global_position
		_show_cut(at)
		_send_route_packet(["cut", at])

func _show_cut(at: Vector2) -> void:
	_cut_cues.append({"at": _cues.to_local(at), "until": trial_tick + CUT_CUE_TICKS})
	_cues.queue_redraw()

func _send_route_packet(event: Array) -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		var packet := var_to_bytes([GameState.get_sync_round(), event])
		(multiplayer as SceneMultiplayer).send_bytes(packet, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE)

func _on_route_packet(peer: int, packet: PackedByteArray) -> void:
	if peer != 1 or finished or _lan_frozen_frame >= 0:
		return
	var envelope: Variant = bytes_to_var(packet)
	if not envelope is Array or envelope.size() != 2 or envelope[0] != GameState.get_sync_round():
		return
	var event: Variant = envelope[1]
	if not event is Array or event.size() != 2:
		return
	if event[0] == "cut" and event[1] is Vector2:
		_show_cut(event[1])
	elif event[0] == "hunter" and event[1] is String and HUNTER_NOTICE.has(event[1]):
		_show_hunter_notice(event[1])

func _show_hunter_notice(event: String) -> void:
	_route_notice = HUNTER_NOTICE[event]
	_route_hint_left = LEG_HINT_SECONDS
	_update_countdown()
	_log("hunter_notice", {"event": event})

func _publish_hunter_notice(event: String) -> void:
	_show_hunter_notice(event)
	_send_route_packet(["hunter", event])

func _open_route_drafts() -> void:
	var slots: Array[int] = [1]
	if NetworkManager.is_online():
		slots = GameState.get_alive_player_ids()
	for id: int in slots:
		_pending_slots[id] = true
	for id: int in slots:
		UpgradeDraft.offer_cards(id, OFFER)
	_draft_wait = not _pending_slots.is_empty()
	if NetworkManager.is_online():
		GameState.force_sync_to_peer(-1)

func _on_choice(pid: int, card: String, _index: int) -> void:
	if _build_hint_pending and pid == NetworkManager.local_player_id():
		_build_hint_pending = false
		_route_hint_left = LEG_HINT_SECONDS
		_update_countdown()
	if not _authoritative() or not _pending_slots.has(pid):
		return
	_pending_slots.erase(pid)
	_log("draft", {"slot": pid, "card": card, "source": UpgradeDraft.get_draft(pid).get("source")})
	_draft_wait = not _pending_slots.is_empty()

func _start_route_boss() -> void:
	_show_boss_warning()
	_spawn_boss(5)
	if is_instance_valid(_boss):
		_boss.enable_route_inducement()
		if _hunter_defeated:
			_boss.extend_first_exposure(HUNTER_EXPOSURE_BONUS)
			_boss.first_exposure_bonus_used.connect(func():
				_hunter_reward_spent = true
				_publish_hunter_notice("spent"), CONNECT_ONE_SHOT)

func _on_elite_died() -> void:
	if _authoritative() and leg == Leg.ELITE and is_instance_valid(_elite) and _elite.route_evasion:
		_hunter_defeated = true
		_publish_hunter_notice("earned")
	super._on_elite_died()

func _on_boss_died() -> void:
	super._on_boss_died()
	_complete_route("通关")

func _on_player_died() -> void:
	if NetworkManager.is_online():
		_on_networked_player_died(NetworkManager.local_player_id())
		return
	_complete_route("被击落")

func _finish_multiplayer_game_over(_final_score: int, _final_level: int) -> void:
	_complete_route("被击落")

func _complete_route(outcome: String) -> void:
	if not _authoritative() or finished:
		return
	_log("result", {"outcome": outcome, "interruptions": interruptions})
	if NetworkManager.is_online():
		_rpc_route_result.rpc(outcome, interruptions)
	else:
		_rpc_route_result(outcome, interruptions)

@rpc("authority", "reliable", "call_local")
func _rpc_route_result(outcome: String, cuts: int) -> void:
	if finished:
		return
	interruptions = cuts
	_route_outcome = outcome
	_finish(outcome)

func _set_leg(value: Leg) -> void:
	_apply_route_leg(value, false)
	_log("leg", {"leg": leg})
	if NetworkManager.is_online():
		_rpc_route_leg.rpc(leg, false)

func _update_countdown() -> void:
	var title: String = "裂隙航道 · " + ("整备，母舰将至" if _settling else LEG_NAMES[leg])
	var hint: String = LEG_HINTS[leg] if _route_notice.is_empty() else _route_notice
	_hud.set_wave_phase(hint if _route_hint_left > 0.0 else title, Color.LIGHT_CYAN)

func _apply_route_leg(next_leg: int, settling: bool, announce := true) -> void:
	if next_leg not in range(LEG_NAMES.size()):
		return
	if settling or not announce:
		_build_hint_pending = false
		_route_hint_left = 0.0
		_route_notice = ""
		_cut_cues.clear()
		_cues.queue_redraw()
	elif next_leg != leg:
		_route_notice = ""
		# The build transition opens cards on the same tick. Show its hint after the local choice.
		_build_hint_pending = next_leg == Leg.BUILD and not UpgradeDraft.get_draft(NetworkManager.local_player_id()).get("chosen", false)
		_route_hint_left = LEG_HINT_SECONDS if not _build_hint_pending and not LEG_HINTS[next_leg].is_empty() else 0.0
	leg = next_leg
	_settling = settling
	_update_countdown()

@rpc("authority", "reliable", "call_remote")
func _rpc_route_leg(next_leg: int, settling: bool) -> void:
	if not finished:
		_apply_route_leg(next_leg, settling)

func _add_fighter(role: String, kind: int, station: Vector2, fire := 0, health := 0, side := 0.0) -> void:
	super._add_fighter(role, kind, station, fire, health, side)
	if fire > 0 and NetworkManager.is_online():
		_rpc_route_cue.rpc(_fighters[role].ship.entity_id, fire)

@rpc("authority", "reliable", "call_remote")
func _rpc_route_cue(eid: int, left: int) -> void:
	_remote_cues[eid] = trial_tick + left

func _retire_trial_fighter(ship: Node2D) -> void:
	if NetworkManager.is_online():
		var eid: int = ship.entity_id
		_despawned_entity_ids[eid] = true
		_entities.erase(eid)
		_entity_target_positions.erase(eid)
		_rpc_despawn_entity.rpc(eid)
	super._retire_trial_fighter(ship)

func send_lan_resume_snapshot(wire: int) -> Dictionary:
	var state := super.send_lan_resume_snapshot(wire)
	var cues := {}
	for order: Dictionary in _fighters.values():
		if is_instance_valid(order.ship) and not order.ship.is_queued_for_deletion() and int(order.fire) > trial_tick:
			cues[int(order.ship.entity_id)] = int(order.fire) - trial_tick
	state.route = {"leg": leg, "settling": trial_tick >= SETTLE_TICK and trial_tick < BOSS_LEG,
		"cues": cues, "outcome": _route_outcome, "cuts": interruptions}
	state.result = false # Do not enter the ordinary leaderboard path.
	return state

func apply_lan_resume_snapshot(state: Dictionary) -> bool:
	if not super.apply_lan_resume_snapshot(state) or not state.has("route"):
		return false
	_remote_cues.clear()
	_fighters.clear()
	for eid: int in state.route.cues:
		_rpc_route_cue(eid, state.route.cues[eid])
	_apply_route_leg(state.route.leg, state.route.settling, false)
	if not str(state.route.outcome).is_empty():
		_rpc_route_result(state.route.outcome, state.route.cuts)
	return true

func set_lan_hold(held: bool) -> void:
	if held:
		_cut_cues.clear()
		_cues.queue_redraw()
	if held and (_route_hint_left > 0.0 or _build_hint_pending):
		_build_hint_pending = false
		_route_hint_left = 0.0
		_route_notice = ""
		_update_countdown()
	super.set_lan_hold(held)

func _finish(outcome: String) -> void:
	if finished:
		return
	_build_hint_pending = false
	_route_hint_left = 0.0
	_route_notice = ""
	_cut_cues.clear()
	_cues.queue_redraw()
	_update_countdown()
	super._finish(outcome)
	_result.text += "\n" + _next_attempt_tip(outcome)
	_layout_options()

func _next_attempt_tip(outcome: String) -> String:
	if outcome == "通关":
		return "下局试试另一张首卡或另一条拦截路线"
	if outcome == "被击落":
		if interruptions == 0:
			return "下局试着先切掉一股齐射"
		if leg == Leg.BOSS:
			return "下局试着横移，再从侧翼打盾"
	return "下局试着换一条拦截路线"

func _on_level_up(_new_level: int) -> void:
	# Authored mode has exactly one explicit draft, even if a future wave count changes.
	pass

func _reload_as_single_player_clean(delay_seconds: float = 0.0) -> void:
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	if is_inside_tree():
		_return_to_title()

func _return_to_title() -> void:
	if NetworkManager.is_online():
		NetworkManager.disconnect_network()
	super._return_to_title()

func _log(event: String, details: Dictionary) -> void:
	if "--rift-log" in OS.get_cmdline_user_args():
		print("[RIFT] ", JSON.stringify({"event": event, "tick": trial_tick, "details": details}))
