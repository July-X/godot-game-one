extends Node2D

# Vector drawing uses pixel coordinates so the three hulls stay legible at the
# original sprite scale. The hurtbox still belongs to Enemy.
const INK := Color("#101828")
const HOT := Color("#ffbf76")
const COOL := Color("#6ae6f1")
const PRIMARY_RAY := Color(1.0, 0.52, 0.32, 0.82)
const FOLLOW_RAY := Color(1.0, 0.75, 0.39, 0.67)

var ship: Node2D
var drawn_warning_stamp := -1
var warning_visible_usec := 0
var _age := 0.0
var _flight_time := 0.0
var _next_draw := 0.0
var _rays := Node2D.new()

func _ready() -> void:
	_rays.z_index = -1
	_rays.draw.connect(_draw_attack_rays)
	add_child(_rays)
	_rays.set_as_top_level(true)
	_rays.global_transform = Transform2D.IDENTITY
	get_viewport().size_changed.connect(_rays.queue_redraw)

func _process(delta: float) -> void:
	var previous_age := _age
	_age += delta
	_flight_time += delta
	if ship.attack_release and previous_age < 0.10 and _age >= 0.10:
		queue_redraw()
	if ship.attack_phase == ship.AttackPhase.FLIGHT:
		_next_draw -= delta
		if _next_draw <= 0.0:
			_next_draw = 1.0 / 20.0
			queue_redraw()

func phase_changed() -> void:
	_age = 0.0
	warning_visible_usec = 0
	queue_redraw()
	_rays.queue_redraw()

func _draw() -> void:
	var phase: int = ship.attack_phase
	var preparing: bool = phase == ship.AttackPhase.PREPARE
	var following: bool = phase == ship.AttackPhase.FOLLOW_THROUGH
	var recovering: bool = phase == ship.AttackPhase.RECOVER
	var charging := preparing or following
	var firing: bool = ship.attack_release and _age < 0.10
	match ship.enemy_type:
		0: _draw_needle(charging, firing, recovering)
		1: _draw_shear(charging, firing, recovering, charging and ship.attack_first_count == 2)
		2: _draw_ring(charging, firing, recovering)

func _draw_attack_rays() -> void:
	var preparing: bool = ship.attack_phase == ship.AttackPhase.PREPARE
	var following: bool = ship.attack_phase == ship.AttackPhase.FOLLOW_THROUGH
	if not preparing and not following:
		return
	if preparing and drawn_warning_stamp != ship.attack_stamp:
		drawn_warning_stamp = ship.attack_stamp
		if not ship._is_network_ghost and not RenderingServer.frame_post_draw.is_connected(_mark_warning_visible):
			RenderingServer.frame_post_draw.connect(_mark_warning_visible, CONNECT_ONE_SHOT)
	var field := NetworkManager.battle_size(self)
	var first: int = ship.attack_first_count
	for index in range(first if following else 0, ship.attack_angles.size()):
		var start: Vector2 = ship.attack_muzzle(index)
		var dir := Vector2.from_angle(ship.attack_angles[index])
		var edge := _ray_to_edge(start, dir, field)
		var later := index >= first
		var color := FOLLOW_RAY if later else PRIMARY_RAY
		var spans := PackedVector2Array()
		# The intervals identify the second sweep in silhouette as well as by colour.
		var dash := 7.0 if later else 17.0
		for offset in range(0, ceili(edge), 30):
			spans.append(start + dir * float(offset))
			spans.append(start + dir * minf(offset + dash, edge))
		if not spans.is_empty():
			_rays.draw_multiline(spans, color, 2.0)
		var mark := start + dir * minf(edge, 28.0)
		_rays.draw_rect(Rect2(mark - Vector2(1, 1), Vector2(3, 3)), color)

func _mark_warning_visible() -> void:
	if ship.attack_phase == ship.AttackPhase.PREPARE and drawn_warning_stamp == ship.attack_stamp:
		warning_visible_usec = Time.get_ticks_usec()

func _ray_to_edge(start: Vector2, dir: Vector2, field: Vector2) -> float:
	var limit := maxf(field.x, field.y) * 2.0
	if absf(dir.x) > 0.001:
		limit = minf(limit, ((field.x if dir.x > 0.0 else 0.0) - start.x) / dir.x)
	if absf(dir.y) > 0.001:
		limit = minf(limit, ((field.y if dir.y > 0.0 else 0.0) - start.y) / dir.y)
	return maxf(limit, 0.0)

func _rect(x: float, y: float, w: int, h: int, color: Color) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), color)

func _hull(points: Array, color: Color) -> void:
	var vertices := PackedVector2Array(points)
	draw_colored_polygon(vertices, color)
	vertices.append(vertices[0])
	draw_polyline(vertices, INK, 2.0)

func _jet(at: Vector2, recovering: bool) -> void:
	var length := 3 if recovering else 6 + int(fmod(_flight_time * 18.0, 4.0))
	_rect(at.x - 3, at.y, 6, length, Color("#245777"))
	_rect(at.x - 1, at.y, 2, length - 1, COOL)

func _muzzle(at: Vector2, charging: bool, firing: bool) -> void:
	_rect(at.x - 3, at.y, 6, 7, INK)
	_rect(at.x - 1, at.y + 1, 2, 4, HOT if charging or firing else Color("#b2d4dd"))
	if charging:
		_rect(at.x - 3, at.y - 3, 6, 2, HOT)
	if firing:
		_rect(at.x - 4, at.y - 8, 8, 4, HOT)
		_rect(at.x - 1, at.y - 13, 2, 8, Color("#fff2bd"))

func _draw_needle(charging: bool, firing: bool, recovering: bool) -> void:
	var wing := 12 if recovering else 9
	if not charging:
		_jet(Vector2(0, 15), recovering)
	_hull([Vector2(0, -22), Vector2(6, -10), Vector2(wing, 8), Vector2(wing, 13),
		Vector2(4, 10), Vector2(3, 17), Vector2(-3, 17), Vector2(-4, 10),
		Vector2(-wing, 13), Vector2(-wing, 8), Vector2(-6, -10)], Color("#b35b64"))
	_rect(-2, -10, 4, 18, Color("#f0a184"))
	_rect(-3, 0, 6, 7, Color("#58394e"))
	_muzzle(Vector2(0, -22), charging, firing)

func _draw_shear(charging: bool, firing: bool, recovering: bool, split: bool) -> void:
	var tip := 26 if charging else (17 if recovering else 21)
	for side in [-1, 1]:
		var skew := -5 if split and side * sin(ship.attack_angles[1] - ship.attack_heading) > 0.0 else 0
		if not charging:
			_jet(Vector2(side * 11, 11), recovering)
		_hull([Vector2(side * 5, -9), Vector2(side * tip, -6 + skew), Vector2(side * tip, 1 + skew),
			Vector2(side * 15, 9), Vector2(side * 6, 8)], Color("#589f8c"))
		_rect(side * 15 - 3, -3 + skew, 6, 3, Color("#b4d9b2"))
		_muzzle(Vector2(side * 11, -14 + skew), charging, firing)
	_hull([Vector2(-4, -16), Vector2(4, -16), Vector2(9, -4), Vector2(7, 12),
		Vector2(-7, 12), Vector2(-9, -4)], Color("#375b60"))
	_rect(-3, -8, 6, 7, COOL)

func _draw_ring(charging: bool, firing: bool, recovering: bool) -> void:
	var radius := 17.0 if charging else 11.0
	var spin := 0.0 if charging else _flight_time * 1.8
	draw_circle(Vector2.ZERO, 10, INK)
	draw_circle(Vector2.ZERO, 7, Color("#8b75ba"))
	_rect(-3, -3, 6, 6, HOT if charging else COOL)
	for index in range(3):
		var angle := TAU * index / 3.0 + spin
		var at := (Vector2.DOWN.rotated(angle) * radius).round()
		draw_set_transform(at, angle, Vector2.ONE)
		if not charging:
			_jet(Vector2(0, 8), recovering)
		_hull([Vector2(-6, -5), Vector2(6, -5), Vector2(8, 3), Vector2(4, 9),
			Vector2(-4, 9), Vector2(-8, 3)], Color("#a083bd"))
		_rect(-4, 1, 8, 3, HOT if charging or firing else Color("#e0aace"))
	draw_set_transform(Vector2.ZERO)
