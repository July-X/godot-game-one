extends RefCounted
## Used by the combat authority. Stable pilot slots, never transport peer IDs.
const DAMAGE_SHARE := 0.10
const RECENT_DAMAGE_SECONDS := 5.0
const CLOSE_SCORE := 0.065
var _recent_damage: Dictionary[int, float] = {}
var _recent_targets: Dictionary[String, Array] = {}

func advance(delta: float) -> void:
	var decay := exp(-delta * 2.0 / RECENT_DAMAGE_SECONDS)
	for slot: int in _recent_damage:
		_recent_damage[slot] *= decay

func record_damage(slot: int, applied: float) -> void:
	if slot > 0 and applied > 0.0:
		_recent_damage[slot] = _recent_damage.get(slot, 0.0) + applied

func damage_score(slot: int, durability: float) -> float:
	return clampf(_recent_damage.get(slot, 0.0) / maxf(1.0, durability * DAMAGE_SHARE), 0.0, 1.0)

func rank(attack: String, range_by_slot: Dictionary, positions: Dictionary, durability: float) -> Array[int]:
	var recent: Array = _recent_targets.get(attack, [])
	var ranked: Array[int] = []
	var scores := {}
	for slot: int in range_by_slot:
		ranked.append(slot)
		var pressure := float(recent.count(slot)) / 2.0
		scores[slot] = .50 * damage_score(slot, durability) + .35 * float(range_by_slot[slot]) + .15 * (1.0 - pressure)
	ranked.sort_custom(func(a: int, b: int):
		var diff: float = scores[a] - scores[b]
		if absf(diff) > CLOSE_SCORE:
			return diff > 0.0
		if not recent.is_empty() and recent.back() in [a, b]:
			var last: int = recent.back()
			return a != last if recent.count(last) >= 2 else a == last
		var pa: Vector2 = positions[a]
		var pb: Vector2 = positions[b]
		return pa.y < pb.y if is_equal_approx(pa.x, pb.x) else pa.x < pb.x)
	return ranked

func select(attack: String, slot: int) -> void:
	if not _recent_targets.has(attack):
		_recent_targets[attack] = []
	var recent := _recent_targets[attack]
	recent.append(slot)
	if recent.size() > 2:
		recent.pop_front()
