extends "res://scripts/opening_trial.gd"
## Authored encounter clock; player and projectile physics remain in Main.
enum Leg { INTERCEPT, BUILD, ELITE, BOSS }
const CARD_TICK := 35 * 60
const ELITE_LEG := 90 * 60
const SETTLE_TICK := 197 * 60
const BOSS_LEG := 210 * 60
const HUNTER_EXPOSURE_BONUS := 1.0
const PRACTICE_WAVES := {78: .28, 1110: .72}
const BUILD_WAVES := [CARD_TICK + 90, CARD_TICK + 760, CARD_TICK + 1770, ELITE_LEG + 54, 138 * 60, 168 * 60]
const LEG_NAMES := ["拦截齐射", "让卡牌改变航线", "裂隙猎手", "裂隙母舰"]
var leg := Leg.INTERCEPT
var _draft_wait := false
var _pending_slots: Dictionary[int, bool] = {}
var _route_outcome := ""
var _hunter_defeated := false
var _remote_cues: Dictionary[int, int] = {}

func _ready() -> void:
	super._ready()
	$TrialUI/Options/Buttons/Retry.visible = _authoritative()
	if _authoritative():
		volley_interrupted.connect(func(role: String, _at: Vector2, deadline: int):
			_log("interrupted", {"role": role, "release": deadline}))
	_log("start", {})
	_update_countdown()

func _authoritative() -> bool:
	return not NetworkManager.is_online() or multiplayer.is_server()

func _physics_process(_delta: float) -> void:
	# Invoke Main's rescue tick through the extracted production hook.
	_tick_rescue_window()
	if finished or not GameState.game_running:
		return
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
		_elite.enable_route_combat(ELITE_ENTRY_SECONDS)
		_elite.route_evaded.connect(func(): _log("elite_side_step", {}))
	if trial_tick == SETTLE_TICK:
		_elite = null
		_clear_non_boss_entities()
		_fighters.clear()
		_breaks.clear()
		_cues.queue_redraw()
		_show_route_leg(leg, true)
		if NetworkManager.is_online():
			_rpc_route_leg.rpc(leg, true)
	if trial_tick == BOSS_LEG:
		_set_leg(Leg.BOSS)
		_start_route_boss()
	if not _fighters.is_empty() or not _breaks.is_empty():
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
			_hunter_defeated = false

func _on_elite_died() -> void:
	if _authoritative() and leg == Leg.ELITE and is_instance_valid(_elite) and _elite.route_evasion:
		_hunter_defeated = true
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
	interruptions = cuts
	_route_outcome = outcome
	_finish(outcome)

func _set_leg(value: Leg) -> void:
	leg = value
	_log("leg", {"leg": leg})
	_update_countdown()
	if NetworkManager.is_online():
		_rpc_route_leg.rpc(leg, false)

func _update_countdown() -> void:
	_show_route_leg(leg, false)

func _show_route_leg(next_leg: int, settling: bool) -> void:
	_hud.set_wave_phase("裂隙航道 · " + ("整备，母舰将至" if settling else LEG_NAMES[next_leg]), Color.LIGHT_CYAN)

@rpc("authority", "reliable", "call_remote")
func _rpc_route_leg(next_leg: int, settling: bool) -> void:
	if next_leg in range(LEG_NAMES.size()):
		leg = next_leg
		_show_route_leg(leg, settling)

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
	_rpc_route_leg(state.route.leg, state.route.settling)
	if not str(state.route.outcome).is_empty():
		_rpc_route_result(state.route.outcome, state.route.cuts)
	return true

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
