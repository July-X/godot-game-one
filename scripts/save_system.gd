extends Node

## 存档系统
## 保存最佳通关时间、总击杀数、通关次数到本地文件

const SAVE_PATH := "user://save_data.json"

var best_time: float = 0.0  ## 最佳通关时间（秒），0 表示未通关过
var total_kills: int = 0    ## 累计击杀数
var total_runs: int = 0     ## 累计游戏次数
var best_kills: int = 0     ## 单局最高击杀数

func _ready() -> void:
	load_game()

func save_game() -> void:
	var data: Dictionary = {
		"best_time": best_time,
		"total_kills": total_kills,
		"total_runs": total_runs,
		"best_kills": best_kills
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		return
	var data: Dictionary = json.data
	best_time = data.get("best_time", 0.0)
	total_kills = data.get("total_kills", 0)
	total_runs = data.get("total_runs", 0)
	best_kills = data.get("best_kills", 0)

func record_run(kills: int, time: float, success: bool) -> void:
	total_runs += 1
	total_kills += kills
	if kills > best_kills:
		best_kills = kills
	if success:
		if best_time <= 0.0 or time < best_time:
			best_time = time
	save_game()

func reset_save() -> void:
	best_time = 0.0
	total_kills = 0
	total_runs = 0
	best_kills = 0
	save_game()

func get_best_time_string() -> String:
	if best_time <= 0.0:
		return "--:--"
	var minutes := int(best_time) / 60
	var seconds := int(best_time) % 60
	return "%d:%02d" % [minutes, seconds]
