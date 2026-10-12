class_name RushRecords
extends RefCounted
## Local personal records for the fixed Rush rules; one bucket per weapon.
const PATH: String = "user://rush_records.cfg"
const MAX_SCORE: int = 10000000
const SECTION: String = "rush_v1_crossroads"

static func arsenal_best(loadout: Dictionary, map_id: String = "crossroads", path: String = PATH, source_weapon: int = 1) -> int:
	if source_weapon not in [0, 1, 2]: return 0
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK: return 0
	var value: Variant = config.get_value("rush_arsenal_v1", ArsenalLoadout.fingerprint(loadout, map_id, source_weapon), 0)
	return int(value) if typeof(value) == TYPE_INT and value >= 0 and value <= MAX_SCORE else 0

static func arsenal_record(loadout: Dictionary, state: Dictionary,
		map_id: String = "crossroads", path: String = PATH, source_weapon: int = 1) -> Dictionary:
	var previous: int = arsenal_best(loadout, map_id, path, source_weapon)
	var result: Dictionary = {"best": previous, "personal_best": false, "saved": false, "error": ""}
	var score: Variant = state.get("score", -1)
	if source_weapon not in [0, 1, 2] or not bool(state.get("enabled", false)) or not bool(state.get("finished", false)) \
			or str(state.get("outcome", "")) not in ["win", "defeat"] \
			or typeof(score) != TYPE_INT or score < 0 or score > MAX_SCORE or int(score) <= previous:
		return result
	var config: ConfigFile = ConfigFile.new()
	# Loading first preserves original source-weapon buckets and other loadouts.
	config.load(path)
	config.set_value("rush_arsenal_v1", ArsenalLoadout.fingerprint(loadout, map_id, source_weapon), int(score))
	var error: Error = config.save(path)
	if error != OK:
		result.error = "Record could not be saved"
		return result
	result.best = int(score)
	result.personal_best = true
	result.saved = true
	return result

static func best(weapon: int, path: String = PATH) -> int:
	if weapon not in [0, 1, 2]: return 0
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK: return 0
	var value: Variant = config.get_value(SECTION, str(weapon), 0)
	return int(value) if typeof(value) == TYPE_INT and value >= 0 and value <= MAX_SCORE else 0

static func record(weapon: int, state: Dictionary, path: String = PATH) -> Dictionary:
	var previous: int = best(weapon, path)
	var result: Dictionary = {"best": previous, "personal_best": false, "saved": false, "error": ""}
	if weapon not in [0, 1, 2] or not bool(state.get("enabled", false)) \
			or not bool(state.get("finished", false)) or str(state.get("outcome", "")) not in ["win", "defeat"]:
		return result
	var score: Variant = state.get("score", -1)
	if typeof(score) != TYPE_INT or score < 0 or score > MAX_SCORE:
		return result
	if int(score) <= previous: return result
	var config: ConfigFile = ConfigFile.new()
	# A malformed file is recoverable; retain only independently valid buckets.
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(path) == OK and saved.has_section("rush_arsenal_v1"):
		for key: String in saved.get_section_keys("rush_arsenal_v1"):
			var value: Variant = saved.get_value("rush_arsenal_v1", key, -1)
			if key.length() == 64 and key.is_valid_hex_number(false) and typeof(value) == TYPE_INT and value >= 0 and value <= MAX_SCORE:
				config.set_value("rush_arsenal_v1", key, value)
	for id: int in [0, 1, 2]:
		config.set_value(SECTION, str(id), best(id, path))
	config.set_value(SECTION, str(weapon), int(score))
	var error: Error = config.save(path)
	if error != OK:
		result.error = "Record could not be saved"
		return result
	result.best = int(score)
	result.personal_best = true
	result.saved = true
	return result
