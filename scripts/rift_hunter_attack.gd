extends Node2D
## 航道猎手的出招和预警共用一份世界坐标。加入端只推进预警显示。

signal preview_changed(snapshot: Dictionary)

enum Pattern { NONE, LINE, RING }
enum Stage { REST, WARNING, FOLLOWUP }

const FIRST_DELAY := 0.55
const LINE_WARNING := 0.60
const LINE_REPEAT := 0.18
const LINE_LEAD := 0.23
const LINE_HALF_ANGLE := PI / 20.0
const LINE_SPEED := 480.0
const RING_WARNING := 0.65
const RING_SLOTS := 14
const RING_STEP := TAU / RING_SLOTS
const RING_HALF_GAP := RING_STEP * 1.5
const RING_SPEED := 380.0
const RECOVERY := 0.82
const LOW_HULL_RECOVERY := 0.62
const MUZZLE := 28.0
const LINE_COLOR := Color("ff8152")
const RING_COLOR := Color("ffbb72")

var _hunter: CharacterBody2D
var _stage := Stage.REST
var _next := Pattern.LINE
var _pattern := Pattern.NONE
var _left := 0.0
var _origin := Vector2.ZERO
var _angle := 0.0
var _slot := 0
var _stamp := 0
var _shown: int = Pattern.NONE
var _show_left := 0.0
var _last_positions: Dictionary[int, Vector2] = {}
var _velocities: Dictionary[int, Vector2] = {}


func configure(hunter: CharacterBody2D, entry_seconds: float) -> void:
	_hunter = hunter
	top_level = true
	# 预警原点是离散的世界坐标，首帧不能从上一次原点插值滑入。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = -1
	_left = entry_seconds + FIRST_DELAY


func attack_pending() -> bool:
	return _stage != Stage.REST


func tick(delta: float, exposed: bool, dodging: bool) -> void:
	var pilots: Array[Node2D] = _hunter.route_live_pilots()
	for pilot in pilots:
		var slot: int = pilot.peer_id
		var at := pilot.global_position
		var previous: Vector2 = _last_positions.get(slot, at)
		var motion := (at - previous) / delta
		_velocities[slot] = _velocities.get(slot, Vector2.ZERO).lerp(motion.limit_length(400.0), minf(delta * 12.0, 1.0))
		_last_positions[slot] = at
	if exposed:
		return
	_left = maxf(0.0, _left - delta)
	if _left > 0.0:
		return
	match _stage:
		Stage.REST:
			if not dodging and not pilots.is_empty():
				_begin(pilots)
		Stage.WARNING:
			_fire()
			if _pattern == Pattern.LINE:
				_stage = Stage.FOLLOWUP
				_left = LINE_REPEAT
			else:
				_recover()
			_publish() # 首发已经可见，撤掉蓄力轮廓。
		Stage.FOLLOWUP:
			_fire()
			_recover()


func _begin(pilots: Array[Node2D]) -> void:
	_pattern = _next
	_next = Pattern.RING if _pattern == Pattern.LINE else Pattern.LINE
	_origin = _hunter.global_position
	if _pattern == Pattern.LINE:
		var target: Node2D = _hunter.choose_route_line_target(pilots)
		_slot = target.peer_id
		var prediction: Vector2 = target.global_position + _velocities.get(_slot, Vector2.ZERO) * LINE_LEAD
		var field := NetworkManager.battle_size(_hunter)
		var aim := Vector2(prediction).clamp(Vector2.ZERO, field)
		_angle = _origin.direction_to(aim).angle()
		_left = LINE_WARNING
	else:
		var nearest := pilots[0]
		for pilot in pilots:
			if _origin.distance_squared_to(pilot.global_position) < _origin.distance_squared_to(nearest.global_position):
				nearest = pilot
		_slot = nearest.peer_id
		_angle = _ring_gap_towards(nearest.global_position)
		_left = RING_WARNING
	_stage = Stage.WARNING
	_publish()


func _ring_gap_towards(at: Vector2) -> float:
	var ray := _origin.direction_to(at)
	if ray.is_zero_approx():
		ray = Vector2.DOWN
	var field := NetworkManager.battle_size(_hunter)
	var flyable := Rect2(Vector2(24, 24), field - Vector2(48, 48))
	var stride := minf(90.0, _origin.distance_to(at) * 0.36)
	var side := ray.orthogonal() * stride
	var left := at + side
	var right := at - side
	if not flyable.has_point(left) and not flyable.has_point(right):
		return _origin.direction_to(at.move_toward(flyable.get_center(), stride)).angle()
	var left_open := flyable.has_point(left) and (not flyable.has_point(right)
		or left.distance_squared_to(flyable.get_center()) <= right.distance_squared_to(flyable.get_center()))
	var offset := RING_HALF_GAP + deg_to_rad(3.0)
	return ray.angle() + (offset if left_open else -offset)


func _fire() -> void:
	var narrow := _pattern == Pattern.LINE
	for direction in projectile_angles(_pattern, _angle):
		var start := _origin + Vector2.from_angle(direction) * MUZZLE
		_hunter._spawn_enemy_bullet(start, direction, 2.0 if narrow else 1.0,
			LINE_SPEED if narrow else RING_SPEED, LINE_COLOR if narrow else RING_COLOR, true)
	SFX.play_enemy_volley()


static func projectile_angles(pattern: int, axis: float) -> PackedFloat32Array:
	var angles := PackedFloat32Array()
	if pattern == Pattern.LINE:
		return PackedFloat32Array([axis - LINE_HALF_ANGLE, axis, axis + LINE_HALF_ANGLE])
	# 两格留空，真实相邻弹道之间有三个格距的开口。
	for i in range(1, RING_SLOTS - 1):
		angles.append(axis + (i + 0.5) * RING_STEP)
	return angles


func _recover() -> void:
	_stage = Stage.REST
	_left = LOW_HULL_RECOVERY if _hunter.get_network_health() <= _hunter.get_network_max_health() * 0.35 else RECOVERY


func cancel() -> void:
	var was_warning := _stage == Stage.WARNING
	_recover()
	if was_warning:
		_publish()


func delay_after_summon() -> void:
	_left = maxf(_left, RECOVERY)


func snapshot() -> Dictionary:
	return {"stamp": _stamp, "pattern": _pattern if _stage == Stage.WARNING else Pattern.NONE,
		"left": _left if _stage == Stage.WARNING else 0.0, "origin": _origin, "angle": _angle, "slot": _slot}


func _publish() -> void:
	_stamp += 1
	var state := snapshot()
	_show(state)
	preview_changed.emit(state)


func apply_preview(state: Dictionary, recovering: bool) -> void:
	var stamp: int = state.stamp
	if stamp < _stamp or (stamp == _stamp and not recovering):
		return
	_stamp = stamp
	_show(state)


func _show(state: Dictionary) -> void:
	_shown = int(state.pattern)
	_show_left = float(state.left)
	_angle = float(state.angle)
	_slot = int(state.slot)
	global_position = state.origin
	queue_redraw()


func tick_preview(delta: float) -> void:
	if _shown != Pattern.NONE:
		_show_left = maxf(_show_left - delta, 0.0)
		if _show_left == 0.0:
			_shown = Pattern.NONE
			queue_redraw()


func _draw() -> void:
	match _shown:
		Pattern.LINE:
			for direction in projectile_angles(_shown, _angle):
				var ray := Vector2.from_angle(direction)
				draw_dashed_line(ray * MUZZLE, ray * NetworkManager.battle_size(self).length(),
					Color(LINE_COLOR, 0.76), 2.0, 12.0, false)
			var axis := Vector2.from_angle(_angle)
			var side := axis.orthogonal() * 12.0
			draw_polyline(PackedVector2Array([axis * 42.0 + side, axis * 57.0, axis * 42.0 - side]), LINE_COLOR, 2.0)
		Pattern.RING:
			# 和护盾的外沿拉开距离，玩家能看到缺口两边的端点。
			draw_arc(Vector2.ZERO, 106.0, _angle + RING_HALF_GAP, _angle + TAU - RING_HALF_GAP, 48,
				Color(RING_COLOR, 0.72), 2.0, true)
			for direction in projectile_angles(_shown, _angle):
				var ray := Vector2.from_angle(direction)
				draw_line(ray * 99.0, ray * 123.0, RING_COLOR, 2.0, true)
