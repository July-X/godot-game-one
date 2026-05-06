extends Node

func create_player_sprite(level: int = 1) -> ImageTexture:
	var w: int = 64 + level * 8
	var h: int = 96 + level * 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = w / 2
	var cy: int = h / 2

	## 机身颜色随等级变化
	var body_r: float = 0.12 + level * 0.04
	var body_g: float = 0.30 + level * 0.06
	var body_b: float = 0.75 - level * 0.02

	## ===== 尾翼/垂直安定面 =====
	for y in range(12, 24):
		for x in range(cx - 6, cx + 6):
			var dy: float = float(y - 12) / 12.0
			var wing_t: float = 1.0 - dy
			var half_w: int = int(6 * wing_t)
			if abs(x - cx) < half_w:
				var t: float = float(y - 12) / 12.0
				var rr: float = body_r * 0.6 + t * 0.2
				var gg: float = body_g * 0.6 + t * 0.15
				var bb: float = body_b * 0.6 + t * 0.1
				img.set_pixel(x, y, Color(rr, gg, bb, 0.8))

	## ===== 主机身 =====
	for y in range(20, h - 12):
		for x in range(6, w - 6):
			var t: float = float(y - 20) / float(h - 32)
			var body_width: float = 1.0 - abs(float(x - cx)) / (w * 0.35)
			if body_width > 0:
				var rr: float = body_r + t * 0.15
				var gg: float = body_g + t * 0.2
				var bb: float = body_b - t * 0.15
				## 机身边缘高光
				var edge_glow: float = 1.0 - abs(float(x - cx)) / (w * 0.35)
				var brightness: float = 0.7 + edge_glow * 0.3
				img.set_pixel(x, y, Color(rr * brightness, gg * brightness, bb * brightness, 1.0))

	## ===== 机身中线面板细节 =====
	for y in range(30, h - 20):
		for x in range(cx - 2, cx + 3):
			if y % 6 < 2:
				img.set_pixel(x, y, Color(body_r * 0.5, body_g * 0.5, body_b * 0.5, 0.4))

	## ===== 机翼（后掠三角翼） =====
	for y in range(cy - 10, cy + 20):
		for x in range(0, w):
			var wing_span: int = int(20 + (cy + 15 - y) * 1.4)
			if wing_span > 0 and (x < cx - wing_span or x > cx + wing_span):
				var outer: float = min(abs(x - cx) - wing_span, 10.0) / 10.0
				if outer > 0:
					var wing_r: float = 0.06 + level * 0.03
					var wing_g: float = 0.15 + level * 0.05
					var wing_b: float = 0.45 - level * 0.02
					var alpha: float = 1.0
					if outer < 0.3:
						alpha = outer / 0.3
					img.set_pixel(x, y, Color(wing_r, wing_g, wing_b, alpha))
	## 翼尖灯
	for i in range(2):
		var wingtip_offset: int = 34
		var lx: int = cx - wingtip_offset - 1 if i == 0 else cx + wingtip_offset + 1
		var ly: int = cy + 5
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy <= 4:
					var px: int = lx + dx
					var py: int = ly + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						img.set_pixel(px, py, Color(1.0, 0.2, 0.1, 0.7) if i == 0 else Color(0.1, 0.8, 0.2, 0.7))

	## ===== 翼尖武器挂架（随等级变大变强） =====
	var mount_size: int = 1 + level / 2
	for i in [-1, 1]:
		var mpx: int = cx + i * (16 + level * 2)
		var mpy: int = cy + 8
		for dy in range(-mount_size, 3 + mount_size):
			for dx in range(-mount_size, 1 + mount_size):
				var px: int = mpx + dx * i
				var py: int = mpy + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, Color(0.5, 0.5, 0.55, 0.9))
	## ===== 炮管（随等级增长加粗加长） =====
	var barrel_len: int = 8 + level * 3
	var barrel_w: int = 1 + level / 2
	for i in [-1, 1]:
		var bx: int = cx + i * 14
		for dy in range(-barrel_len, 0):
			for dx in range(-barrel_w, barrel_w + 1):
				var px: int = bx + dx
				var py: int = cy - 2 + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					var b_r: float = 0.35 + level * 0.05
					var b_g: float = 0.35 + level * 0.05
					var b_b: float = 0.4 + level * 0.04
					img.set_pixel(px, py, Color(b_r, b_g, b_b, 0.9))
	## ===== 额外炮塔（等级3+ 机翼外侧加装） =====
	if level >= 3:
		for i in [-1, 1]:
			var tx: int = cx + i * (22 + level)
			for dy in range(-6, 0):
				for dx in range(-2, 3):
					var px: int = tx + dx * i
					var py: int = cy - 2 + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						img.set_pixel(px, py, Color(0.6, 0.3 + level * 0.06, 0.1, 0.95))
	## ===== 机头整流锥（随等级更尖锐） =====
	var nose_len: int = 8 + level * 2
	for dy in range(-nose_len, 0):
		var half_w: int = max(1, int(4 * (1.0 - float(-dy) / float(nose_len))))
		for dx in range(-half_w, half_w + 1):
			var px: int = cx + dx
			var py: int = cy - 16 + dy
			if px >= 0 and px < w and py >= 0 and py < h:
				var t: float = float(-dy) / float(nose_len)
				img.set_pixel(px, py, Color(body_r * (0.8 + t * 0.3), body_g * (0.8 + t * 0.3), body_b * (0.8 + t * 0.3), 1.0))

	## ===== 驾驶舱 =====
	var ck_cx: int = cx
	var ck_cy: int = cy - 12
	for y in range(ck_cy - 10, ck_cy + 8):
		for x in range(ck_cx - 8, ck_cx + 8):
			var dx: float = float(x - ck_cx) / 7.0
			var dy: float = float(y - (ck_cy - 1)) / 9.0
			if dx * dx + dy * dy < 1.0:
				var depth: float = dx * dx + dy * dy
				var cockpit_r: float = 0.2 + depth * 0.3
				var cockpit_g: float = 0.7 + depth * 0.3
				var cockpit_b: float = 0.9 + depth * 0.1
				img.set_pixel(x, y, Color(cockpit_r, cockpit_g, cockpit_b, 0.85 - depth * 0.2))
	## 驾驶舱反射高光
	for i in range(3):
		var hx: int = ck_cx - 3 + i * 3
		var hy: int = ck_cy - 6
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px: int = hx + dx
				var py: int = hy + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, Color(0.8, 0.95, 1.0, 0.3 + (1.0 - abs(dx)) * 0.3))

	## ===== 引擎进气口 =====
	for y in range(h - 24, h - 12):
		for x in range(cx - 8, cx + 8):
			var inner: float = 1.0 - abs(float(x - cx)) / 8.0
			if inner > 0:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.08, 0.9 * inner))

	## ===== 引擎喷口+尾焰 =====
	var nozzle_count: int = 2 + level / 2
	for i in range(nozzle_count):
		var px: int = cx - nozzle_count * 3 + i * 6 + 3
		for y in range(h - 14, h - 4):
			for x in range(px - 2, px + 3):
				if x >= 0 and x < w:
					var t: float = float(y - (h - 14)) / 10.0
					var flame_r: float = 1.0
					var flame_g: float = 0.6 - t * 0.3
					var flame_b: float = 0.2 - t * 0.15
					var flame_a: float = 1.0 - t * 0.3
					img.set_pixel(x, y, Color(flame_r, flame_g, flame_b, flame_a))
	## 外焰/辉光
	var glow_cx: int = cx
	for y in range(h - 6, h):
		for x in range(glow_cx - 10, glow_cx + 10):
			var d: float = abs(float(x - glow_cx)) / 10.0
			if d < 1.0:
				var t: float = float(y - (h - 6)) / 6.0
				var a: float = (1.0 - d * 0.5) * (0.12 - t * 0.08)
				if a > 0:
					img.set_pixel(x, y, Color(1.0, 0.7, 0.3, a))

	## ===== 等级标识条纹 =====
	if level >= 2:
		var stripe_y: int = cy + 16
		for y in range(stripe_y, stripe_y + 6):
			for x in range(cx - 12, cx + 12):
				if abs(x - cx) < 5 + level * 2:
					var stripe_alpha: float = 0.6 + 0.2 * (1.0 - abs(float(y - stripe_y - 3)) / 3.0)
					img.set_pixel(x, y, Color(0.9, 0.7, 0.2, stripe_alpha))

	var tex := ImageTexture.create_from_image(img)
	return tex

func create_enemy_sprite(type: int = 0) -> ImageTexture:
	var size: int = 48 + type * 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = size / 2
	var cy: int = size / 2
	match type:
		0: _draw_enemy_type0(img, cx, cy, size)
		1: _draw_enemy_type1(img, cx, cy, size)
		2: _draw_enemy_type2(img, cx, cy, size)
		_: _draw_enemy_type0(img, cx, cy, size)
	var tex := ImageTexture.create_from_image(img)
	return tex

func _draw_enemy_type0(img: Image, cx: int, cy: int, size: int) -> void:
	for y in range(size):
		for x in range(size):
			var dx: float = abs(float(x - cx)) / (size * 0.42)
			var dy: float = abs(float(y - cy)) / (size * 0.42)
			if dx + dy < 1.0:
				var t: float = dx + dy
				img.set_pixel(x, y, Color(0.8 - t * 0.3, 0.15 + t * 0.1, 0.1, 1.0))
	_set_eye(img, cx - size / 5, cy - size / 8, size / 5)
	_set_eye(img, cx + size / 5, cy - size / 8, size / 5)

func _draw_enemy_type1(img: Image, cx: int, cy: int, size: int) -> void:
	for y in range(size):
		for x in range(size):
			var dx: float = abs(float(x - cx)) / (size * 0.40)
			var dy: float = abs(float(y - cy)) / (size * 0.40)
			var dist: float = max(dx, dy)
			if dist < 1.0:
				var t: float = dist
				img.set_pixel(x, y, Color(0.1 + t * 0.1, 0.7 - t * 0.2, 0.2 + t * 0.1, 1.0))
	_set_eye(img, cx - size / 5, cy - size / 8, size / 5)
	_set_eye(img, cx + size / 5, cy - size / 8, size / 5)

func _draw_enemy_type2(img: Image, cx: int, cy: int, size: int) -> void:
	for y in range(size):
		for x in range(size):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < size * 0.42:
				var t: float = dist / (size * 0.42)
				img.set_pixel(x, y, Color(0.6 - t * 0.2, 0.1 + t * 0.1, 0.8 - t * 0.3, 1.0))
	_set_eye(img, cx - size / 4, cy - size / 6, size / 4)
	_set_eye(img, cx + size / 4, cy - size / 6, size / 4)

func _set_eye(img: Image, x: int, y: int, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var px: int = x + dx
				var py: int = y + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, Color(1.0, 0.9, 0.2, 1.0))
					if dx * dx + dy * dy <= (r / 2) * (r / 2):
						img.set_pixel(px, py, Color(0.2, 0.0, 0.0, 1.0))

func apply_asteroid_texture(sprite: Sprite2D, size: int) -> void:
	var img := Image.create(size + 10, size + 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = (size + 10) / 2
	var cy: int = (size + 10) / 2
	var base_r: float = randf_range(0.55, 0.85)
	var base_g: float = randf_range(0.35, 0.55)
	var base_b: float = randf_range(0.15, 0.35)
	var max_r: float = float(size) / 2.0
	## 生成不规则多边形顶点
	var vertex_count: int = randi_range(7, 12)
	var vertices: Array[Vector2] = []
	for i in range(vertex_count):
		var angle: float = float(i) / float(vertex_count) * TAU
		var r_offset: float = randf_range(0.6, 1.0)
		var v: Vector2 = Vector2(cos(angle), sin(angle)) * max_r * r_offset
		vertices.append(v)
	## 发光外圈（沿多边形轮廓发光）
	for y in range(size + 10):
		for x in range(size + 10):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var inside: bool = _point_in_polygon(Vector2(dx, dy), vertices)
			var outside_glow: bool = false
			var glow_dist: float = 0.0
			for v in vertices:
				var d: float = sqrt((dx - v.x) * (dx - v.x) + (dy - v.y) * (dy - v.y))
				if d < 8.0 and not inside:
					var g: float = (8.0 - d) / 8.0
					if g > glow_dist:
						glow_dist = g
					outside_glow = true
			if outside_glow and glow_dist > 0:
				img.set_pixel(x, y, Color(1.0, 0.6, 0.15, glow_dist * 0.65))
	## 主体填充（多边形内部）
	for y in range(size + 10):
		for x in range(size + 10):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			if _point_in_polygon(Vector2(dx, dy), vertices):
				var noise: float = sin(x * 0.3 + y * 0.2) * 0.12 + sin(x * 0.5 - y * 0.4) * 0.08
				var dist_center: float = sqrt(dx * dx + dy * dy) / max_r
				var t: float = min(dist_center, 1.0)
				var r: float = base_r + t * 0.15 + noise * 0.08
				var g: float = base_g + t * 0.08 + noise * 0.06
				var b: float = base_b + t * 0.05 + noise * 0.04
				var a: float = 1.0 - t * 0.15
				img.set_pixel(x, y, Color(r, g, b, a))
	## 高光边缘（多边形轮廓内侧）
	for y in range(size + 10):
		for x in range(size + 10):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			if not _point_in_polygon(Vector2(dx, dy), vertices):
				continue
			var near_edge: bool = false
			for v in vertices:
				var d: float = sqrt((dx - v.x) * (dx - v.x) + (dy - v.y) * (dy - v.y))
				if d < max_r * 0.25:
					near_edge = true
					break
			if near_edge:
				for v in vertices:
					var d: float = sqrt((dx - v.x) * (dx - v.x) + (dy - v.y) * (dy - v.y))
					if d < max_r * 0.25:
						var ha: float = (1.0 - d / (max_r * 0.25)) * 0.6
						var existing := img.get_pixel(x, y)
						img.set_pixel(x, y, Color(min(existing.r + ha * 0.4, 1.0), min(existing.g + ha * 0.3, 1.0), min(existing.b + ha * 0.15, 1.0), existing.a))
						break
	## 陨石坑
	for i in range(size / 4):
		var cx2: int = randi_range(max_r * 0.2, max_r * 1.4)
		var cy2: int = randi_range(max_r * 0.2, max_r * 1.4)
		var cr: int = randi_range(2, size / 6)
		for dy in range(-cr, cr + 1):
			for dx in range(-cr, cr + 1):
				var d2: float = sqrt(float(dx * dx + dy * dy))
				if d2 < cr:
					var px: int = cx2 + dx
					var py: int = cy2 + dy
					if px >= 0 and px < size + 10 and py >= 0 and py < size + 10:
						var pt := Vector2(float(px - cx), float(py - cy))
						if _point_in_polygon(pt, vertices):
							var depth: float = 1.0 - d2 / float(cr)
							img.set_pixel(px, py, Color(base_r * 0.3, base_g * 0.3, base_b * 0.3, depth * 0.85))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.z_index = 1
	sprite.self_modulate = Color(1.3, 1.1, 0.9, 1.0)

func _point_in_polygon(point: Vector2, vertices: Array[Vector2]) -> bool:
	var inside: bool = false
	var j: int = vertices.size() - 1
	for i in range(vertices.size()):
		if (vertices[i].y > point.y) != (vertices[j].y > point.y):
			var intersect_x: float = (vertices[j].x - vertices[i].x) * (point.y - vertices[i].y) / (vertices[j].y - vertices[i].y) + vertices[i].x
			if point.x < intersect_x:
				inside = not inside
		j = i
	return inside

func create_boss_sprite() -> ImageTexture:
	var w: int = 160
	var h: int = 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = w / 2
	var cy: int = h / 2
	## 主体机身（深红）
	for y in range(18, h - 12):
		for x in range(12, w - 12):
			var body_w: float = 1.0 - abs(float(x - cx)) / (w * 0.38)
			if body_w > 0:
				var t: float = float(y - 18) / float(h - 30)
				var r: float = 0.45 + t * 0.2
				var g: float = 0.08 + t * 0.12
				var b: float = 0.05 + t * 0.08
				img.set_pixel(x, y, Color(r, g, b, body_w))
	## 机翼（宽大后掠翼）
	for y in range(cy - 14, cy + 30):
		for x in range(0, w):
			var span: int = int(42 + (cy + 26 - y) * 1.8)
			if span > 0 and (x < cx - span or x > cx + span):
				var alpha: float = min(abs(x - cx) - span, 16.0) / 16.0
				if alpha > 0:
					img.set_pixel(x, y, Color(0.35, 0.06, 0.04, alpha))
	## 驾驶舱（暗色弧面）
	for y in range(cy - 20, cy + 4):
		for x in range(cx - 14, cx + 14):
			var dx: float = float(x - cx) / 13.0
			var dy: float = float(y - (cy - 8)) / 12.0
			if dx * dx + dy * dy < 1.0:
				var depth: float = dx * dx + dy * dy
				img.set_pixel(x, y, Color(0.15, 0.4, 0.5, 0.7 - depth * 0.3))
	## 武器炮管（加粗）
	for i in [-1, 1]:
		for dy in range(0, 18):
			var px: int = cx + i * 22
			var py: int = cy - 6 + dy
			if py >= 0 and py < h:
				img.set_pixel(px, py, Color(0.5, 0.5, 0.55, 0.9))
				img.set_pixel(px + i, py, Color(0.4, 0.4, 0.45, 0.7))
				img.set_pixel(px + i * 2, py, Color(0.3, 0.3, 0.35, 0.5))
	## 引擎喷口（3个大喷口）
	for i in range(3):
		var px: int = cx - 12 + i * 12
		for y in range(h - 18, h - 4):
			for x in range(px - 3, px + 4):
				if x >= 0 and x < w:
					var t: float = float(y - (h - 18)) / 14.0
					img.set_pixel(x, y, Color(1.0, 0.6 - t * 0.3, 0.1, 1.0 - t * 0.4))
	## 护盾发生器环（装饰）
	for y in range(6, h - 6):
		for x in range(6, w - 6):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var d: float = sqrt(dx * dx + dy * dy)
			if d > 55.0 and d < 59.0:
				var a: float = 0.2 * (1.0 - abs(d - 57.0) / 2.0)
				img.set_pixel(x, y, Color(0.3, 0.6, 1.0, a))
	## 装甲板细节
	for i in range(3):
		var lx: int = cx - 30 + i * 30
		for dy in range(-14, 14):
			var px: int = lx
			var py: int = cy + dy
			if px >= 0 and px < w and py >= 0 and py < h:
				if abs(dy) % 8 < 2:
					img.set_pixel(px, py, Color(0.2, 0.2, 0.25, 0.4))
	var tex := ImageTexture.create_from_image(img)
	return tex

func create_bullet_sprite(is_player: bool, level: int = 1) -> ImageTexture:
	var size: int = 8 if is_player else 12
	var h: int = size * 3
	var img := Image.create(size, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy: int = h / 2
	for y in range(h):
		for x in range(size):
			var t: float = 1.0 - abs(y - cy) / float(cy)
			var alpha: float = clamp(t * 1.5, 0.0, 1.0)
			if is_player:
				var r: float
				var g: float
				var b: float
				if level <= 1:
					r = 0.3 + t * 0.7; g = 0.6 + t * 0.4; b = 1.0
				elif level <= 2:
					r = 0.1 + t * 0.3; g = 0.8 + t * 0.2; b = 0.9
				elif level <= 3:
					r = 0.6 + t * 0.4; g = 0.2 + t * 0.3; b = 0.9
				else:
					r = 1.0; g = 0.8 + t * 0.2; b = 0.2
				img.set_pixel(x, y, Color(r, g, b, alpha))
			else:
				img.set_pixel(x, y, Color(1.0, 0.3 + t * 0.3, 0.2, alpha))
	if is_player and level >= 3:
		for y in range(h):
			var t: float = 1.0 - abs(y - cy) / float(cy)
			var alpha: float = clamp(t * 3.0, 0.0, 1.0)
			img.set_pixel(size / 2, y, Color(1.0, 1.0, 1.0, alpha))
			if level >= 4:
				img.set_pixel(size / 2 - 1, y, Color(1.0, 1.0, 0.8, alpha * 0.5))
				img.set_pixel(size / 2 + 1, y, Color(1.0, 1.0, 0.8, alpha * 0.5))
	var tex := ImageTexture.create_from_image(img)
	return tex

func create_powerup_sprite(type: String) -> ImageTexture:
	if _powerup_cache.has(type):
		return _powerup_cache[type]

	var w: int = 32
	var h: int = 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = w / 2
	var cy: int = h / 2
	var col: Color
	match type:
		"spread": col = Color(0.2, 0.9, 0.3)
		"speed": col = Color(0.2, 0.6, 1.0)
		"power": col = Color(1.0, 0.3, 0.2)
		"heal": col = Color(1.0, 0.25, 0.2)
		"bomb": col = Color(1.0, 0.8, 0.2)
		_: col = Color(0.5, 0.5, 0.5)

	match type:
		"heal":
			_draw_heart(img, w, h, col)
		"spread":
			_draw_star(img, w, h, col)
		"speed":
			_draw_diamond(img, w, h, col)
		"power":
			_draw_hexagon(img, w, h, col)
		"bomb":
			_draw_bomb(img, w, h, col)
		_:
			_draw_hexagon(img, w, h, col)

	_draw_glow_ring(img, w, h, col)
	var tex := ImageTexture.create_from_image(img)
	_powerup_cache[type] = tex
	return tex

var _powerup_cache: Dictionary = {}

func _draw_glow_ring(img: Image, w: int, h: int, col: Color) -> void:
	var r: int = 14
	var cx: int = w / 2
	var cy: int = h / 2
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0:
				continue
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var d: float = sqrt(dx * dx + dy * dy)
			if d > r - 2.5 and d < r + 1.5:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 0.2))

func _draw_heart(img: Image, w: int, h: int, col: Color) -> void:
	var cx: int = w / 2
	var cy: int = h / 2
	for y in range(h):
		for x in range(w):
			var dx: float = float(x - cx) / 14.0
			var dy: float = float(y - cy + 2) / 14.0
			var eq: float = (dx * dx + dy * dy - 1.0) * (dx * dx + dy * dy - 1.0) * (dx * dx + dy * dy - 1.0) - dx * dx * dy * dy * dy
			if eq <= 0.0:
				var depth: float = sqrt(dx * dx + dy * dy) / 1.5
				var r: float = col.r * (1.0 - depth * 0.3)
				var g: float = col.g * (1.0 - depth * 0.3)
				var b: float = col.b * (1.0 - depth * 0.3)
				img.set_pixel(x, y, Color(r, g, b, 1.0))

func _draw_star(img: Image, w: int, h: int, col: Color) -> void:
	var cx: int = w / 2
	var cy: int = h / 2
	for y in range(h):
		for x in range(w):
			var inside: bool = false
			var j: int = 9
			for i in range(10):
				var angle_i: float = float(i) * TAU / 10.0 - PI / 2.0
				var angle_j: float = float(j) * TAU / 10.0 - PI / 2.0
				var ri: float = 14.0 if i % 2 == 0 else 7.0
				var rj: float = 14.0 if j % 2 == 0 else 7.0
				var xi: float = cx + cos(angle_i) * ri
				var yi: float = cy + sin(angle_i) * ri
				var xj: float = cx + cos(angle_j) * rj
				var yj: float = cy + sin(angle_j) * rj
				if (yi > float(y)) != (yj > float(y)):
					var intersect_x: float = (xj - xi) * (float(y) - yi) / (yj - yi) + xi
					if float(x) < intersect_x:
						inside = not inside
				j = i
			if inside:
				var d: float = sqrt(float(x - cx) * float(x - cx) + float(y - cy) * float(y - cy)) / 14.0
				img.set_pixel(x, y, Color(col.r * (1.0 - d * 0.2), col.g * (1.0 - d * 0.2), col.b * (1.0 - d * 0.2), 1.0))

func _draw_diamond(img: Image, w: int, h: int, col: Color) -> void:
	var cx: int = w / 2
	var cy: int = h / 2
	for y in range(h):
		for x in range(w):
			var dx: float = abs(float(x - cx)) / 16.0
			var dy: float = abs(float(y - cy)) / 16.0
			if dx + dy < 1.0:
				var t: float = (dx + dy) * 0.5
				var rr: float = col.r * (1.0 - t * 0.4)
				var gg: float = col.g * (1.0 - t * 0.4)
				var bb: float = col.b * (1.0 - t * 0.4)
				img.set_pixel(x, y, Color(rr, gg, bb, 1.0))

func _draw_hexagon(img: Image, w: int, h: int, col: Color) -> void:
	var cx: int = w / 2
	var cy: int = h / 2
	for y in range(h):
		for x in range(w):
			var inside: bool = false
			var j: int = 5
			for i in range(6):
				var ai: float = float(i) * TAU / 6.0
				var aj: float = float(j) * TAU / 6.0
				var xi: float = cx + cos(ai) * 14.0
				var yi: float = cy + sin(ai) * 14.0
				var xj: float = cx + cos(aj) * 14.0
				var yj: float = cy + sin(aj) * 14.0
				if (yi > float(y)) != (yj > float(y)):
					var ix: float = (xj - xi) * (float(y) - yi) / (yj - yi) + xi
					if float(x) < ix:
						inside = not inside
				j = i
			if inside:
				var d: float = sqrt(float(x - cx) * float(x - cx) + float(y - cy) * float(y - cy)) / 14.0
				img.set_pixel(x, y, Color(col.r * (1.0 - d * 0.2), col.g * (1.0 - d * 0.2), col.b * (1.0 - d * 0.2), 1.0))

func _draw_bomb(img: Image, w: int, h: int, col: Color) -> void:
	var cx: int = w / 2
	var cy: int = h / 2
	## 圆
	for y in range(h):
		for x in range(w):
			var d: float = sqrt(float(x - cx) * float(x - cx) + float(y - cy) * float(y - cy))
			if d < 12.0:
				var t: float = d / 12.0
				img.set_pixel(x, y, Color(col.r * (1.0 - t * 0.3), col.g * (1.0 - t * 0.3), col.b * (1.0 - t * 0.3), 1.0))
	## 引信
	for dy in range(-6, -1):
		var px: int = cx
		var py: int = cy - 12 + dy
		if py >= 0 and py < h:
			img.set_pixel(px, py, Color(0.6, 0.6, 0.6, 1.0))
	## 火星
	var fx: int = cx
	var fy: int = cy - 18
	if fy >= 0 and fy < h:
		for dy2 in range(-1, 2):
			for dx2 in range(-1, 2):
				var px2: int = fx + dx2
				var py2: int = fy + dy2
				if px2 >= 0 and px2 < w and py2 >= 0 and py2 < h:
					if dx2 * dx2 + dy2 * dy2 <= 1:
						img.set_pixel(px2, py2, Color(1.0, 0.5, 0.1, 1.0))

func create_explosion_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in range(10):
		var size: int = 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var progress: float = float(f) / 9.0
		var radius: float = 8.0 + progress * 24.0
		for y in range(size):
			for x in range(size):
				var dx: float = float(x - size / 2)
				var dy: float = float(y - size / 2)
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist < radius:
					var t: float = dist / radius
					var brightness: float = 1.0 - progress
					var alpha: float = brightness * (1.0 - t * 0.6)
					img.set_pixel(x, y, Color(1.0, 0.6 * (1.0 - t) + 0.2, 0.2 * (1.0 - t), alpha))
		frames.append(ImageTexture.create_from_image(img))
	return frames

func create_star_field(width: int, height: int, count: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.015, 0.015, 0.04, 1.0))
	## 大星星
	for i in range(count / 5):
		var x: int = randi() % width
		var y: int = randi() % height
		var brightness: float = randf_range(0.5, 1.0)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px: int = x + dx
				var py: int = y + dy
				if px >= 0 and px < width and py >= 0 and py < height:
					var d: float = sqrt(float(dx * dx + dy * dy))
					var b: float = brightness * (1.0 - d * 0.3)
					img.set_pixel(px, py, Color(b, b, b * 1.2, randf_range(0.6, 1.0)))
	## 小星星
	for i in range(count):
		var x: int = randi() % width
		var y: int = randi() % height
		var brightness: float = randf_range(0.2, 0.8)
		img.set_pixel(x, y, Color(brightness, brightness, brightness * 1.1, randf_range(0.3, 0.9)))
	## 星云
	for i in range(8):
		var nx: int = randi() % width
		var ny: int = randi() % height
		var nr: int = randi_range(30, 80)
		var nc: Color = Color(randf_range(0.1, 0.3), randf_range(0.05, 0.15), randf_range(0.2, 0.4), 0.015)
		for dy2 in range(-nr, nr):
			for dx2 in range(-nr, nr):
				var d: float = sqrt(float(dx2 * dx2 + dy2 * dy2))
				if d < nr:
					var px: int = nx + dx2
					var py: int = ny + dy2
					if px >= 0 and px < width and py >= 0 and py < height:
						var alpha: float = nc.a * (1.0 - d / nr)
						img.set_pixel(px, py, Color(nc.r, nc.g, nc.b, alpha))
	var tex := ImageTexture.create_from_image(img)
	return tex
