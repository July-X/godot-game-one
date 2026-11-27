extends "res://scripts/battle/trials/opening_trial.gd"
## Authored encounter clock; player and projectile physics remain in Main.
enum Leg { INTERCEPT, BUILD, ELITE, BOSS }
const HUNTER_ENTRY_SECONDS := 0.26
const RouteRules := preload("res://scripts/battle/trials/rift_route_rules.gd")
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
const FLANK_SPARK_TICKS := 19
const DUAL_EMITTER_TICK := 90
const DUAL_BOSS_TICK := 9 * 60
const DUAL_PULSE_TICKS := [12 * 60, 19 * 60]
const DUAL_END_TICK := 25 * 60
const DUAL_SIDES := ["left", "right"]
var leg := Leg.INTERCEPT
var _settling := false
var remix := false
var dual_intercept := false
var _route_hint_left := 0.0
var _build_hint_pending := false
var _draft_wait := false
var _pending_slots: Dictionary[int, bool] = {}
var _route_outcome := ""
var _hunter_defeated := false
var _hunter_reward_spent := false
var _flank_hits := 0
var _last_duo_success_stamp := 0
var _route_review: Dictionary = {}
var _dual_cut_side := ""
var _route_notice := ""
var _remote_cues: Dictionary[int, int] = {}
var _cut_cues: Array[Dictionary] = []
var _flank_sparks: Array[Dictionary] = []
@onready var _spark_layer: Node2D = $FlankSparks

func _ready() -> void:
	remix = GameState.rift_remix
	dual_intercept = remix and GameState.rift_dual_intercept and NetworkManager.is_online()
	super._ready()
	_spark_layer.draw.connect(_draw_flank_sparks)
	# Ships and their end-of-run effects can still be visible behind the result.
	_result.add_theme_color_override("font_outline_color", Color("#0b1424"))
	_result.add_theme_constant_override("outline_size", 5)
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
	if remix and NetworkManager.is_online() and not _player_entry_ready:
		return
	while not _cut_cues.is_empty() and trial_tick >= int(_cut_cues[0].until):
		_cut_cues.pop_front()
		_cues.queue_redraw()
	while not _flank_sparks.is_empty() and trial_tick >= int(_flank_sparks[0].until):
		_flank_sparks.pop_front()
		_spark_layer.queue_redraw()
	if not _flank_sparks.is_empty():
		_spark_layer.queue_redraw()
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
	if dual_intercept:
		_advance_dual_intercept()
	else:
		_advance_route()
	if not _fighters.is_empty() or not _breaks.is_empty() or not _cut_cues.is_empty():
		_move_fighters()
		while not _breaks.is_empty() and trial_tick >= int(_breaks[0].until):
			_breaks.pop_front()
		_cues.queue_redraw()
	if not dual_intercept and trial_tick % 60 == 0 and (trial_tick < SETTLE_TICK or trial_tick >= BOSS_LEG):
		_update_countdown()

func _advance_dual_intercept() -> void:
	if trial_tick == DUAL_EMITTER_TICK:
		_add_fighter(DUAL_SIDES[0], 1, Vector2(.25, .38), CHARGE_TICKS, 8)
		_add_fighter(DUAL_SIDES[1], 1, Vector2(.75, .38), CHARGE_TICKS, 8)
	elif trial_tick == DUAL_BOSS_TICK:
		_set_leg(Leg.BOSS)
		_start_route_boss()
	elif trial_tick in DUAL_PULSE_TICKS and is_instance_valid(_boss):
		_boss.try_intercept_trial_pulse()
	elif trial_tick == DUAL_END_TICK:
		_complete_route("完成")

func _advance_route() -> void:
	if trial_tick == CARD_TICK:
		_set_leg(Leg.BUILD)
		_open_route_drafts()
	if PRACTICE_WAVES.has(trial_tick):
		_add_fighter("intercept-%d" % trial_tick, 1, Vector2(PRACTICE_WAVES[trial_tick], .36), 174)
		_log("wave", {"id": trial_tick, "type": "intercept"})
	if trial_tick in BUILD_WAVES:
		var slot := BUILD_WAVES.find(trial_tick)
		var mirrored := slot % 2 == 1
		if slot < 2:
			var remix_second := remix and slot == 1
			mirrored = mirrored and not remix_second
			_add_intercept_wave(mirrored, remix_second)
		else:
			_add_build(.025, mirrored)
		_log("wave", {"id": slot, "type": "build", "mirrored": mirrored, "remix": remix})
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

func _add_intercept_wave(mirrored: bool, remix_second := false) -> void:
	var column := .74 if mirrored else .26
	var cluster := .35 if mirrored else .65
	var wing := .14 if mirrored else .86
	var side := -1.0 if mirrored else 1.0
	var releases := [225, 194, 208] if mirrored else [201, 220, 193]
	if remix_second:
		releases = [194, 208, 225]
	_add_fighter("column-front", 0, Vector2(column, .54), 0, 0, -15.0 * side)
	_add_fighter("column-middle", 0, Vector2(column, .405), 0, 0, 19.0 * side)
	_add_fighter("column-rear", 1, Vector2(column, .27), releases[0])
	_add_fighter("cluster-front", 0, Vector2(cluster, .42))
	_add_fighter("cluster-neighbor", 0, Vector2(cluster, .39), 0, 0, -47.0 * side)
	_add_fighter("cluster-rear", 1, Vector2(cluster, .39), releases[1], 0, 47.0 * side)
	_add_fighter("wing", 1, Vector2(wing, .38), releases[2], ARMOR_HP)

func _draw_fan_heading(center: Vector2, at: Vector2, progress: float) -> void:
	var ink := Color(1.0, .60, .40, lerpf(.3, .82, progress))
	for offset: float in FAN_EXIT_OFFSETS:
		var direction := _fan_direction(at, offset)
		_cues.draw_dashed_line(center + direction * 34, center + direction * lerpf(82, 140, progress),
			ink, 1.5, 9.0, false)
	if leg == Leg.BUILD or dual_intercept:
		for side: float in [-1.0, 1.0]:
			var edge := center + Vector2(side * 24.0, 0)
			_cues.draw_polyline(PackedVector2Array([edge + Vector2(-side * 7, -9), edge,
				edge + Vector2(-side * 7, 9)]), ink, 2.5, true)

func _draw_cues() -> void:
	super._draw_cues()
	if (leg == Leg.BUILD or (dual_intercept and leg == Leg.INTERCEPT)) and _fighters.values().any(func(order: Dictionary): return _is_charging(order)):
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
func _draw_flank_sparks() -> void:
	for spark: Dictionary in _flank_sparks:
		var life := float(int(spark.until) - trial_tick) / FLANK_SPARK_TICKS
		var center: Vector2 = spark.at
		for index: int in 3:
			var outward: Vector2 = spark.outward
			var d := outward.rotated(float(index - 1) * .65)
			var at := center + d * lerpf(32.0, 14.0, life)
			var tip := d * 7.0
			var edge := d.orthogonal() * 4.0
			_spark_layer.draw_polyline(PackedVector2Array([at - tip, at + edge, at + tip, at - edge, at - tip]),
				Color(.60, 1.0, .78, life), 2.5, true)

func _on_emitter_died(role: String) -> void:
	var cuts_before := interruptions
	super._on_emitter_died(role)
	if interruptions == cuts_before:
		return
	var order: Dictionary = _fighters[role]
	# Cancel the queued release explicitly before showing a confirmed cut.
	order.fire = -1
	if dual_intercept and role in DUAL_SIDES:
		_dual_cut_side = role
	if leg == Leg.BUILD or dual_intercept:
		var at: Vector2 = order.ship.global_position
		_show_cut(at)
		_send_route_packet(["cut", at])

func _show_cut(at: Vector2) -> void:
	_cut_cues.append({"at": _cues.to_local(at), "until": trial_tick + CUT_CUE_TICKS})
	_cues.queue_redraw()
	if dual_intercept:
		SFX.play_ui_confirm()

func _fire_fan(ship: CharacterBody2D, reliable := false) -> void:
	super._fire_fan(ship, reliable or dual_intercept)
	if dual_intercept:
		_log("dual_volley", {"side": str(ship.name).get_slice("-", 1), "bullets": FAN_EXIT_OFFSETS.size()})

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
	elif event[0] == "flank_hit" and event[1] is Vector2:
		_show_flank_hit(event[1])
	elif event[0] == "duo_success" and event[1] is int:
		_show_duo_success(event[1])
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

func _show_flank_hit(at: Vector2) -> void:
	var outward := _boss.global_position.direction_to(at) if is_instance_valid(_boss) else Vector2.UP
	_flank_sparks.append({"at": _spark_layer.to_local(at), "outward": outward, "until": trial_tick + FLANK_SPARK_TICKS})
	_spark_layer.queue_redraw()

func _on_flank_hit(at: Vector2, slot: int, shield_before: float, shield_after: float) -> void:
	_flank_hits += 1
	_show_flank_hit(at)
	_send_route_packet(["flank_hit", at])
	_log("flank_hit", {"slot": slot, "position": str(at), "shield_before": shield_before, "shield_after": shield_after})

func _show_duo_success(stamp: int) -> void:
	if not remix or not is_instance_valid(_boss) or stamp <= _last_duo_success_stamp:
		return
	_last_duo_success_stamp = stamp
	_boss.play_route_duo_success()

func _on_duo_success(stamp: int, marked: int, wing: int) -> void:
	_show_duo_success(stamp)
	_send_route_packet(["duo_success", stamp])
	_log("duo_success", {"stamp": stamp, "marked": marked, "wing": wing})

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
		if dual_intercept:
			_boss.enable_intercept_trial_pulses(interruptions == DUAL_SIDES.size())
			return
		_boss.enable_route_inducement(remix)
		_boss.route_flank_hit.connect(_on_flank_hit)
		_boss.route_duo_success.connect(_on_duo_success)
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
	_complete_route("完成" if dual_intercept else "通关")

func _grant_random_boss_reward_to_peer(peer_id: int) -> void:
	if not dual_intercept:
		super._grant_random_boss_reward_to_peer(peer_id)

func spawn_boss_fragment(kind: String, world_pos: Vector2, assigned_peer_id := 0) -> void:
	if not dual_intercept:
		super.spawn_boss_fragment(kind, world_pos, assigned_peer_id)

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
	var round_id := GameState.get_sync_round() if NetworkManager.is_online() else 0
	var review := {"hunter": _hunter_defeated, "reward_used": _hunter_reward_spent, "flank_hits": _flank_hits}
	if dual_intercept:
		review = {"cut_side": _dual_cut_side} if interruptions == 1 and not _dual_cut_side.is_empty() else {}
	_log("result", {"outcome": outcome, "interruptions": interruptions, "review": review})
	if NetworkManager.is_online():
		_rpc_route_result.rpc(round_id, outcome, interruptions, leg, review)
	else:
		_rpc_route_result(round_id, outcome, interruptions, leg, review)

@rpc("authority", "reliable", "call_local")
func _rpc_route_result(round_id: int, outcome: String, cuts: int, reached_leg: int, review: Dictionary) -> void:
	if finished or (NetworkManager.is_online() and round_id != GameState.get_sync_round()):
		return
	interruptions = cuts
	if reached_leg in range(LEG_NAMES.size()):
		leg = reached_leg
	if dual_intercept:
		var side: Variant = review.get("cut_side")
		if cuts == 1 and side is String and side in DUAL_SIDES:
			_route_review = {"cut_side": side}
	elif review.get("hunter") is bool and review.get("reward_used") is bool and review.get("flank_hits") is int:
		_route_review = review
	_route_outcome = outcome
	_finish(outcome)

func _set_leg(value: Leg) -> void:
	_apply_route_leg(value, false)
	_log("leg", {"leg": leg})
	if NetworkManager.is_online():
		_rpc_route_leg.rpc(leg, false)

func _update_countdown() -> void:
	if dual_intercept:
		var phase := "裂隙母舰" if leg == Leg.BOSS else "双线截击 · 中路可绕行"
		_hud.set_wave_phase(phase, Color.LIGHT_CYAN)
		return
	var title: String = "裂隙航道 · " + ("整备，母舰将至" if _settling else LEG_NAMES[leg])
	var hint: String = LEG_HINTS[leg] if _route_notice.is_empty() else _route_notice
	if remix and leg == Leg.BUILD:
		hint = RouteRules.REMIX_BUILD_HINT
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
		"cues": cues, "outcome": _route_outcome, "cuts": interruptions, "remix": remix, "review": _route_review}
	state.result = false # Do not enter the ordinary leaderboard path.
	return state

func apply_lan_resume_snapshot(state: Dictionary) -> bool:
	if not state.has("route") or state.route.get("remix") != remix or not super.apply_lan_resume_snapshot(state):
		return false
	if dual_intercept and finished:
		return true
	_remote_cues.clear()
	_fighters.clear()
	for eid: int in state.route.cues:
		_rpc_route_cue(eid, state.route.cues[eid])
	if dual_intercept:
		interruptions = state.route.cuts
	_apply_route_leg(state.route.leg, state.route.settling, false)
	if not str(state.route.outcome).is_empty():
		_rpc_route_result(state.round, state.route.outcome, state.route.cuts, state.route.leg, state.route.get("review", {}))
	return true

func set_lan_hold(held: bool) -> void:
	if held:
		if is_instance_valid(_boss):
			_boss.cancel_route_duo_window()
		_cut_cues.clear()
		_flank_sparks.clear()
		_spark_layer.queue_redraw()
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
	_flank_sparks.clear()
	_spark_layer.queue_redraw()
	_cues.queue_redraw()
	_update_countdown()
	super._finish(outcome)
	if dual_intercept:
		_result.text = _dual_result_text(outcome)
		_layout_options()
		return
	if not _route_review.is_empty():
		var hunter := "猎手未击破"
		if _route_review.hunter:
			hunter = "猎手击破 · 奖励已兑现" if _route_review.reward_used else "猎手击破 · 奖励未用"
		_result.text += "\n%s · 盾沿命中 %d 次" % [hunter, _route_review.flank_hits]
	_result.text += "\n" + _next_attempt_tip(outcome)
	_layout_options()

func _dual_result_text(outcome: String) -> String:
	match interruptions:
		0:
			return "%s · 未截断\n下局分飞，抢在亮弧收紧前击破" % outcome
		1:
			var side := "截断 1 侧"
			match _route_review.get("cut_side", ""):
				"left": side = "已截断左侧"
				"right": side = "已截断右侧"
			return "%s · %s\n下局试着各守一侧" % [outcome, side]
		2:
			return "%s · 双侧截断\n解锁母舰首轮宽缺口" % outcome
		_:
			return "%s · 截断 %d 次" % [outcome, interruptions]

func _next_attempt_tip(outcome: String) -> String:
	if outcome == "通关":
		return "下局试试另一张首卡或另一条拦截路线"
	if outcome == "被击落":
		if interruptions == 0:
			return "下局试着先切掉一股齐射"
		if leg == Leg.BOSS:
			if not _route_review.is_empty() and int(_route_review.flank_hits) > 0:
				return "下局试着在第一次破盾时集中火力" if _route_review.hunter else "下局试着击破猎手，多争取 1 秒反打"
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
