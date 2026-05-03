extends Node

## 成就系统
## 追踪玩家成就，与存档系统联动

signal achievement_unlocked(achievement_id: String)

const ACHIEVEMENT_SAVE_PATH := "user://achievements.json"

## 成就定义：id => {name, description, icon_color}
var _achievements: Dictionary = {
	"first_blood": {
		"name": "First Blood",
		"description": "Eliminate your first enemy",
		"unlocked": false
	},
	"clean_sweep": {
		"name": "Clean Sweep",
		"description": "Clear all enemies in a single run",
		"unlocked": false
	},
	"speed_run": {
		"name": "Speed Runner",
		"description": "Complete the mission in under 60 seconds",
		"unlocked": false
	},
	"survivor": {
		"name": "Survivor",
		"description": "Complete the mission without taking damage",
		"unlocked": false
	},
	"veteran": {
		"name": "Veteran",
		"description": "Complete 5 missions",
		"unlocked": false
	},
	"elite": {
		"name": "Elite Operator",
		"description": "Accumulate 50 total kills",
		"unlocked": false
	}
}

func _ready() -> void:
	load_achievements()

func load_achievements() -> void:
	if not FileAccess.file_exists(ACHIEVEMENT_SAVE_PATH):
		return
	var file := FileAccess.open(ACHIEVEMENT_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	var data: Dictionary = json.data
	file.close()
	for id in data:
		if _achievements.has(id):
			_achievements[id]["unlocked"] = data[id].get("unlocked", false)

func save_achievements() -> void:
	var data: Dictionary = {}
	for id in _achievements:
		data[id] = {"unlocked": _achievements[id]["unlocked"]}
	var file := FileAccess.open(ACHIEVEMENT_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func is_unlocked(achievement_id: String) -> bool:
	if _achievements.has(achievement_id):
		return _achievements[achievement_id]["unlocked"]
	return false

func get_unlocked_count() -> int:
	var count: int = 0
	for id in _achievements:
		if _achievements[id]["unlocked"]:
			count += 1
	return count

func get_all_achievements() -> Dictionary:
	return _achievements

## 检查并解锁成就，返回新解锁的成就 id 数组
func check_achievements(kills: int, total_enemies: int, time: float, success: bool, hp_lost: int) -> Array:
	var newly_unlocked: Array = []

	## First Blood：首次击杀
	if not _achievements["first_blood"]["unlocked"] and kills >= 1:
		_unlock("first_blood", newly_unlocked)

	if success:
		## Clean Sweep：全灭敌人
		if not _achievements["clean_sweep"]["unlocked"] and kills >= total_enemies:
			_unlock("clean_sweep", newly_unlocked)

		## Speed Run：60秒内通关
		if not _achievements["speed_run"]["unlocked"] and time < 60.0:
			_unlock("speed_run", newly_unlocked)

		## Survivor：无伤通关
		if not _achievements["survivor"]["unlocked"] and hp_lost <= 0:
			_unlock("survivor", newly_unlocked)

		## Veteran：完成5次任务（在 record_run 后检查）
		if not _achievements["veteran"]["unlocked"] and SaveSystem.total_runs >= 5:
			_unlock("veteran", newly_unlocked)

	## Elite：累计50击杀
	if not _achievements["elite"]["unlocked"] and SaveSystem.total_kills >= 50:
		_unlock("elite", newly_unlocked)

	if newly_unlocked.size() > 0:
		save_achievements()

	return newly_unlocked

func _unlock(id: String, newly_unlocked: Array) -> void:
	_achievements[id]["unlocked"] = true
	newly_unlocked.append(id)
	achievement_unlocked.emit(id)
