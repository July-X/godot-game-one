extends Node

const SAVE_PATH: String = "user://leaderboard.cfg"
const MAX_ENTRIES: int = 5

func add_entry(score: int, level: int) -> void:
	var entries: Array[Dictionary] = _load_entries()
	var now := Time.get_datetime_dict_from_system()
	var timestamp: String = "%04d-%02d-%02d %02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute]
	entries.append({"score": score, "level": level, "time": timestamp})
	entries.sort_custom(func(a, b): return a.score > b.score)
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(0, MAX_ENTRIES)
	_save_entries(entries)

func get_entries() -> Array[Dictionary]:
	return _load_entries()

func is_high_score(score: int) -> bool:
	var entries := _load_entries()
	if entries.size() < MAX_ENTRIES:
		return true
	return score > entries[-1].score

func _load_entries() -> Array[Dictionary]:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		return []
	var result: Array[Dictionary] = []
	for i in range(MAX_ENTRIES):
		if not config.has_section_key("Leaderboard", "entry_%d_score" % i):
			break
		result.append({
			"score": config.get_value("Leaderboard", "entry_%d_score" % i, 0),
			"level": config.get_value("Leaderboard", "entry_%d_level" % i, 1),
			"time": config.get_value("Leaderboard", "entry_%d_time" % i, ""),
		})
	return result

func _save_entries(entries: Array[Dictionary]) -> void:
	var config := ConfigFile.new()
	for i in range(entries.size()):
		config.set_value("Leaderboard", "entry_%d_score" % i, entries[i].score)
		config.set_value("Leaderboard", "entry_%d_level" % i, entries[i].level)
		config.set_value("Leaderboard", "entry_%d_time" % i, entries[i].time)
	config.save(SAVE_PATH)
