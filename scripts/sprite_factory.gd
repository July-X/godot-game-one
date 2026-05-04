extends Node

func create_player_sprite() -> ImageTexture:
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(8, 40):
		for x in range(8, 24):
			var t: float = float(y - 8) / 32.0
			var r: float = 0.15 + t * 0.1
			var g: float = 0.35 + t * 0.3
			var b: float = 0.8 - t * 0.2
			img.set_pixel(x, y, Color(r, g, b, 1.0))
	for y in range(4, 8):
		for x in range(10, 22):
			img.set_pixel(x, y, Color(0.4, 0.7, 1.0, 1.0))
	for y in range(0, 4):
		for x in range(13, 19):
			img.set_pixel(x, y, Color(0.6, 0.85, 1.0, 1.0))
	for y in range(10, 18):
		for x in range(12, 20):
			var cx: float = float(x - 16) / 4.0
			var cy: float = float(y - 14) / 4.0
			if cx * cx + cy * cy < 1.0:
				img.set_pixel(x, y, Color(0.3, 0.9, 0.9, 0.9))
	for y in range(20, 28):
		for x in range(2, 30):
			var wing_w: int = int(8.0 - abs(y - 24) * 1.5)
			if abs(x - 16) < wing_w:
				img.set_pixel(x, y, Color(0.1, 0.25, 0.6, 1.0))
	for y in range(40, 46):
		for x in range(10, 15):
			var t: float = float(y - 40) / 6.0
			img.set_pixel(x, y, Color(1.0, 0.5 + t * 0.3, 0.1, 1.0))
		for x in range(17, 22):
			var t2: float = float(y - 40) / 6.0
			img.set_pixel(x, y, Color(1.0, 0.5 + t2 * 0.3, 0.1, 1.0))
	for y in range(48):
		for x in range(32):
			if img.get_pixel(x, y).a > 0:
				continue
			var has_n: bool = false
			for dx2 in range(-1, 2):
				for dy2 in range(-1, 2):
					var nx: int = x + dx2
					var ny: int = y + dy2
					if nx >= 0 and nx < 32 and ny >= 0 and ny < 48:
						if img.get_pixel(nx, ny).a > 0:
							has_n = true
					if has_n:
						break
				if has_n:
					break
			if has_n:
				img.set_pixel(x, y, Color(0.05, 0.1, 0.2, 0.5))
	var tex := ImageTexture.create_from_image(img)
	return tex

func create_enemy_sprite() -> ImageTexture:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(28):
		for x in range(28):
			var cx: float = abs(x - 14.0) / 14.0
			var cy: float = abs(y - 14.0) / 14.0
			if cx + cy < 0.85:
				var t: float = (cx + cy) * 0.5
				img.set_pixel(x, y, Color(0.8 - t * 0.3, 0.15 + t * 0.1, 0.1 + t * 0.05, 1.0))
	for y in range(8, 12):
		for x in range(6, 10):
			var cx: float = float(x - 8) / 2.0
			var cy: float = float(y - 10) / 2.0
			if cx * cx + cy * cy < 1.0:
				img.set_pixel(x, y, Color(1.0, 0.9, 0.2, 1.0))
	for y in range(8, 12):
		for x in range(18, 22):
			var cx: float = float(x - 20) / 2.0
			var cy: float = float(y - 10) / 2.0
			if cx * cx + cy * cy < 1.0:
				img.set_pixel(x, y, Color(1.0, 0.9, 0.2, 1.0))
	img.set_pixel(8, 10, Color(0.2, 0.0, 0.0, 1.0))
	img.set_pixel(19, 10, Color(0.2, 0.0, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex

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
			var cx: float = float(x - size / 2) / (size / 2.0)
			var cy2: float = float(y - size / 2) / (size / 2.0)
			var dist: float = sqrt(cx * cx + cy2 * cy2)
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
	img.fill(Color(0.02, 0.02, 0.06, 1.0))
	for i in count:
		var x: int = randi() % width
		var y: int = randi() % height
		var brightness: float = randf_range(0.3, 1.0)
		var pix_size: int = 1 if randf() < 0.8 else 2
		for dy in range(pix_size):
			for dx in range(pix_size):
				var px: int = x + dx
				var py: int = y + dy
				if px < width and py < height:
					img.set_pixel(px, py, Color(brightness, brightness, brightness, randf_range(0.5, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	return tex
