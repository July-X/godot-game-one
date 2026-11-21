extends RefCounted
## 安全区是本机屏幕坐标。控件使用画布坐标，战斗世界坐标由相机单独处理。

static func for_viewport(viewport: Viewport) -> Rect2:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return from_display(viewport, Rect2(DisplayServer.get_display_safe_area()))
	return viewport.get_visible_rect()

static func from_display(viewport: Viewport, display_rect: Rect2) -> Rect2:
	var canvas := viewport.get_visible_rect()
	var safe := canvas.intersection(viewport.get_screen_transform().affine_inverse() * display_rect)
	return safe if safe.has_area() else canvas
