extends Node

const MAX_ENTRIES: int = 5

var _entries: Array[Dictionary] = []

func add_entry(score: int, level: int, player_scores: Dictionary = {}) -> void:
	var now := Time.get_datetime_dict_from_system()
	var timestamp: String = "%02d:%02d" % [now.hour, now.minute]
	var players: Dictionary = {}
	for key in player_scores.keys():
		var key_str := str(key)
		if key_str.is_valid_int():
			players[key_str] = int(player_scores[key])
	_entries.append({
		"score": score,
		"level": level,
		"time": timestamp,
		"players": players,
	})
	_entries.sort_custom(func(a, b): return a.score > b.score)
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(0, MAX_ENTRIES)

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate()
