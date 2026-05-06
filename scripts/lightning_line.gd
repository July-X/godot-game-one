extends Node2D

var _points: PackedVector2Array = PackedVector2Array()
var _lifetime: float = 0.15

func setup(from: Vector2, to: Vector2) -> void:
	global_position = Vector2.ZERO
	z_index = 100
	var segments: int = 7
	var points: PackedVector2Array = [from]
	for i in range(1, segments):
		var t: float = float(i) / (segments - 1)
		var jitter: float = 20.0 * (1.0 - abs(t - 0.5) * 2.0)
		var px: float = from.x + (to.x - from.x) * t + randf_range(-jitter, jitter)
		var py: float = from.y + (to.y - from.y) * t + randf_range(-jitter, jitter)
		points.append(Vector2(px, py))
	_points = points

func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	if _points.size() < 2:
		return
	var local_pts: PackedVector2Array = []
	for p in _points:
		local_pts.append(to_local(p))
	draw_polyline(local_pts, Color(0.5, 0.25, 0.95, 0.8), 3.0)
	draw_polyline(local_pts, Color(0.3, 0.7, 1.0, 0.5), 7.0)
