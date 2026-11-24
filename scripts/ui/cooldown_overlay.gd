extends ColorRect
## 简化冷却覆盖层：冷却中半透明暗色遮罩，就绪时完全透明

var _progress: float = 0.0

func set_ready_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	## 冷却中加深遮罩，就绪后完全透明
	color = Color(0.0, 0.0, 0.0, 0.5 * (1.0 - _progress))
