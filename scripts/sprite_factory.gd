extends Node

func create_player_sprite(level: int = 1) -> ImageTexture:
	var w: int = 32 + level * 4
	var h: int = 48 + level * 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = w / 2
	var cy: int = h / 2
	## 机身颜色随等级变化
	var body_r: float = 0.15 + level * 0.05
	var body_g: float = 0.35 + level * 0.08
	var body_b: float = 0.8 - level * 0.03
	## 主体
	for y in range(8, h - 8):
		for x in range(4, w - 4):
			var t: float = float(y - 8) / float(h - 16)
			var rr: float = body_r + t * 0.1
			var gg: float = body_g + t * 0.2
			var bb: float = body_b - t * 0.15
			var edge: float = 1.0 - abs(float(x - cx)) / (w * 0.4)
			if edge > 0:
				img.set_pixel(x, y, Color(rr, gg, bb, edge))
	## 驾驶舱
	for y in range(cy - 8, cy + 4):
		for x in range(cx - 4, cx + 4):
			var dx: float = float(x - cx) / 4.0
			var dy: float = float(y - (cy - 2)) / 6.0
			if dx * dx + dy * dy < 1.0:
				img.set_pixel(x, y, Color(0.3, 0.9, 0.9, 0.9))
	## 机翼 — 随等级变宽
	var wing_w: int = 6 + level * 2
	for y in range(cy - 4, cy + 8):
		for x in range(0, w):
			var wing_dist: int = int(wing_w - abs(y - (cy + 2)) * 1.2)
			if wing_dist > 0 and (x < cx - wing_dist or x > cx + wing_dist):
				img.set_pixel(x, y, Color(0.08, 0.2, 0.5, 1.0))
	## 引擎喷口
	for i in range(2 + level / 2):
		var px: int = cx - (2 + level / 2) + i * 3 + 2
		for y in range(h - 10, h - 4):
			for x in range(px - 1, px + 2):
				if x >= 0 and x < w:
					var t: float = float(y - (h - 10)) / 6.0
					img.set_pixel(x, y, Color(1.0, 0.5 + t * 0.3, 0.1, 1.0))
	## 等级指示条纹
	if level >= 2:
		for y in range(cy - 2, cy + 2):
			for x in range(cx - 6, cx + 6):
				if abs(x - cx) < level * 2:
					img.set_pixel(x, y, Color(0.9, 0.7, 0.2, 0.8))
	var tex := ImageTexture.create_from_image(img)
	return tex

func create_enemy_sprite(type: int = 0) -> ImageTexture:
	var size: int = 24 + type * 4
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
	## 红色菱形
	for y in range(size):
		for x in range(size):
			var dx: float = abs(float(x - cx)) / (size * 0.45)
			var dy: float = abs(float(y - cy)) / (size * 0.45)
			if dx + dy < 1.0:
				var t: float = dx + dy
				img.set_pixel(x, y, Color(0.8 - t * 0.3, 0.15 + t * 0.1, 0.1, 1.0))
	## 眼睛
	_set_eye(img, cx - 5, cy - 2, 3)
	_set_eye(img, cx + 5, cy - 2, 3)

func _draw_enemy_type1(img: Image, cx: int, cy: int, size: int) -> void:
	## 绿色六边形
	for y in range(size):
		for x in range(size):
			var dx: float = abs(float(x - cx)) / (size * 0.42)
			var dy: float = abs(float(y - cy)) / (size * 0.42)
			var dist: float = max(dx, dy)
			if dist < 1.0:
				var t: float = dist
				img.set_pixel(x, y, Color(0.1 + t * 0.1, 0.7 - t * 0.2, 0.2 + t * 0.1, 1.0))
	## 眼睛
	_set_eye(img, cx - 5, cy - 2, 3)
	_set_eye(img, cx + 5, cy - 2, 3)

func _draw_enemy_type2(img: Image, cx: int, cy: int, size: int) -> void:
	## 紫色圆形
	for y in range(size):
		for x in range(size):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < size * 0.42:
				var t: float = dist / (size * 0.42)
				img.set_pixel(x, y, Color(0.6 - t * 0.2, 0.1 + t * 0.1, 0.8 - t * 0.3, 1.0))
	## 眼睛
	_set_eye(img, cx - 6, cy - 3, 4)
	_set_eye(img, cx + 6, cy - 3, 4)

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

func create_bullet_sprite(is_player: bool) -> ImageTexture:
	var size: int = 8 if is_player else 6
	var img := Image.create(size, size * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy: int = size * 3 / 2
	for y in range(size * 3):
		for x in range(size):
			var t: float = 1.0 - abs(y - cy) / float(cy)
			var alpha: float = clamp(t * 1.5, 0.0, 1.0)
			if is_player:
				img.set_pixel(x, y, Color(0.3 + t * 0.7, 0.6 + t * 0.4, 1.0, alpha))
			else:
				img.set_pixel(x, y, Color(1.0, 0.3 + t * 0.3, 0.2, alpha))
	var tex := ImageTexture.create_from_image(img)
	return tex

func create_powerup_sprite(type: String) -> ImageTexture:
	var size: int = 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color
	match type:
		"spread": col = Color(0.2, 0.8, 0.3)
		"speed": col = Color(0.2, 0.5, 1.0)
		"power": col = Color(1.0, 0.3, 0.2)
		"heal": col = Color(0.2, 1.0, 0.4)
		"bomb": col = Color(1.0, 0.8, 0.2)
		_: col = Color(0.5, 0.5, 0.5)
	for y in range(size):
		for x in range(size):
			var dx: float = float(x - size / 2) / (size / 2.0)
			var dy: float = float(y - size / 2) / (size / 2.0)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 0.9:
				var b: float = 1.0 - dist * 0.5
				img.set_pixel(x, y, Color(col.r * b, col.g * b, col.b * b, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex

func create_explosion_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in range(8):
		var size: int = 48
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var progress: float = float(f) / 7.0
		var radius: float = 8.0 + progress * 16.0
		for y in range(size):
			for x in range(size):
				var dx: float = float(x - size / 2)
				var dy: float = float(y - size / 2)
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist < radius:
					var t: float = dist / radius
					var brightness: float = 1.0 - progress
					var alpha: float = brightness * (1.0 - t * 0.5)
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
	## 星云效果
	for i in range(5):
		var nx: int = randi() % width
		var ny: int = randi() % height
		var nr: int = randi_range(20, 60)
		var nc: Color = Color(randf_range(0.1, 0.3), randf_range(0.05, 0.15), randf_range(0.2, 0.4), 0.02)
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
