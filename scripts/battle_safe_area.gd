extends RefCounted
## 安全区是本机屏幕坐标。控件使用画布坐标，战斗世界坐标由相机单独处理。

const MENU_MARGIN := 16.0

static func for_viewport(viewport: Viewport) -> Rect2:
	var canvas := viewport.get_visible_rect()
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return canvas
	var safe := from_display(viewport, Rect2(DisplayServer.get_display_safe_area()))
	if OS.has_feature("android") and Engine.has_singleton("HarmonyNearbyGame"):
		var platform := Engine.get_singleton("HarmonyNearbyGame")
		if platform.has_method("getWindowUiInsets"):
			var edges: PackedInt32Array = platform.getWindowUiInsets()
			if edges.size() == 4:
				var window := viewport.get_screen_transform() * canvas
				var gestures := window.grow_individual(-edges[0], -edges[1], -edges[2], -edges[3])
				var inset := safe.intersection(from_display(viewport, gestures))
				if inset.has_area():
					safe = inset
	return safe

static func from_display(viewport: Viewport, display_rect: Rect2) -> Rect2:
	var canvas := viewport.get_visible_rect()
	var safe := canvas.intersection(viewport.get_screen_transform().affine_inverse() * display_rect)
	return safe if safe.has_area() else canvas
