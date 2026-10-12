extends SceneTree
## Isolated durable identity/storage; original records and preferences are untouched.
const RECORDS = preload("res://gameplay/rush_records.gd")
const LOADOUT = preload("res://gameplay/arsenal_loadout.gd")
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const MAPS = preload("res://ui/map_catalog.gd")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
const PATH: String = "user://arsenal_records_fixture.cfg"
const PREFS: String = "user://arsenal_loadout_fixture.cfg"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ARSENAL RECORDS: " + label)

func remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "fixture storage removes cleanly")

func state(score: Variant = 400) -> Dictionary:
	return {"enabled": true, "finished": true, "outcome": "defeat", "score": score}

func identity_checks() -> void:
	var loadout: Dictionary = CATALOG.defaults()
	var reordered: Dictionary = {"stratagems": ["x17", "x20"], "bomb": "x12", "primary": "x01"}
	check(LOADOUT.fingerprint(loadout) == LOADOUT.fingerprint(reordered), "dictionary key order does not create another record identity")
	check(LOADOUT.fingerprint(loadout) == LOADOUT.fingerprint(reordered.merged({"cosmetic": "ignored", "weapon": 19})), "ignored fields cannot create another scoring bucket")
	check(LOADOUT.fingerprint(loadout).length() == 64, "rules/map/full-loadout fingerprint is durable SHA256 identity")
	for key: String in ["primary", "bomb", "stratagems"]:
		var different: Dictionary = loadout.duplicate(true)
		different[key] = "x03" if key == "primary" else ("x16" if key == "bomb" else ["x18", "x20"])
		check(LOADOUT.fingerprint(different) != LOADOUT.fingerprint(loadout), "changing " + key + " separates gameplay rules")
	check(LOADOUT.fingerprint(loadout, "crossroads") != LOADOUT.fingerprint(loadout, "mira_hq"), "map is part of record identity")
	check(LOADOUT.fingerprint(loadout, "crossroads", 0) != LOADOUT.fingerprint(loadout, "crossroads", 1) and LOADOUT.fingerprint(loadout, "crossroads", 2) != LOADOUT.fingerprint(loadout, "crossroads", 1) and LOADOUT.fingerprint(loadout, "crossroads", 0) != LOADOUT.fingerprint(loadout, "crossroads", 2), "each available original backup class changes the full scoring identity")
	var swapped: Dictionary = loadout.duplicate(true)
	swapped.stratagems = ["x20", "x17"]
	check(LOADOUT.fingerprint(swapped) != LOADOUT.fingerprint(loadout), "equipped support slot order has its own full-loadout identity")
	var invalid: Dictionary = {"primary": "x20", "bomb": "x01", "stratagems": ["x17", "x17"], "node": "res://unsafe.gd"}
	check(CATALOG.canonical_loadout(invalid) == loadout, "wrong categories/duplicate supports sanitize to canonical defaults")
	check(LOADOUT.save(invalid, true, PREFS) == OK and LOADOUT.load_saved(PREFS) == {"enabled": true, "loadout": loadout}, "saved preferences sanitize equipment and extra fields")
	check(LOADOUT.save(reordered, false, PREFS) == OK and LOADOUT.load_saved(PREFS) == {"enabled": false, "loadout": loadout}, "returning to source kit persists disabled without losing selected equipment")
	var config: ConfigFile = ConfigFile.new()
	config.set_value("arsenal", "enabled", "true")
	config.set_value("arsenal", "loadout", "res://bad.tscn")
	config.save(PREFS)
	check(LOADOUT.load_saved(PREFS) == {"enabled": false, "loadout": loadout}, "malformed enabled/loadout storage never activates equipment")
	var launch: Dictionary = {"mode": "survival", "map_id": "crossroads", "weapon": 1, "survival": SETTINGS.rush_defaults(), "arsenal": invalid, "unlimited_ammo": true}
	var validated: Dictionary = MAPS.validate(launch)
	check(validated.ok and validated.configuration.get("arsenal", {}) == loadout and not validated.configuration.has("unlimited_ammo"), "launch validation preserves sanitized optional equipment without lab cheats")
	launch.erase("arsenal")
	validated = MAPS.validate(launch)
	check(validated.ok and not validated.configuration.has("arsenal"), "source launch remains a separate unchanged three-weapon path")
	launch.arsenal = "x20"
	validated = MAPS.validate(launch)
	check(not validated.ok or not validated.configuration.has("arsenal"), "malformed expansion cannot become an arbitrary launch value")

func storage_checks() -> void:
	var original: Array[int] = [100, 200, 300]
	for weapon: int in 3:
		check(RECORDS.record(weapon, state(original[weapon]), PATH).saved, "original source bucket seeded independently")
	var loadout: Dictionary = CATALOG.defaults()
	check(RECORDS.arsenal_best(loadout, "crossroads", PATH) == 0, "new rules begin with no inherited original score")
	var first: Dictionary = RECORDS.arsenal_record(loadout, state(450), "crossroads", PATH)
	check(first.saved and first.personal_best and first.best == 450, "finished expansion defeat stores earned points")
	for weapon: int in 3:
		check(RECORDS.best(weapon, PATH) == original[weapon], "expansion cannot modify source bucket%d" % weapon)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	var duplicate: Dictionary = RECORDS.arsenal_record(loadout, state(450), "crossroads", PATH)
	check(not duplicate.saved and not duplicate.personal_best and FileAccess.get_file_as_bytes(PATH) == before, "same finish saves at most once and does not rewrite storage")
	check(not RECORDS.arsenal_record(loadout, state(200), "crossroads", PATH).saved, "lower expansion result preserves the existing record")
	var other: Dictionary = loadout.duplicate(true)
	other.bomb = "x16"
	check(RECORDS.arsenal_record(other, state(700), "crossroads", PATH).saved and RECORDS.arsenal_best(loadout, "crossroads", PATH) == 450, "different bomb loadout has an independent record")
	check(RECORDS.arsenal_record(loadout, state(900), "mira_hq", PATH).saved and RECORDS.arsenal_best(loadout, "crossroads", PATH) == 450, "different map has an independent record")
	check(RECORDS.arsenal_record(loadout, state(625), "crossroads", PATH, 0).saved and RECORDS.arsenal_record(loadout, state(775), "crossroads", PATH, 2).saved, "same custom kit independently records rifle and shotgun backup runs")
	check(RECORDS.arsenal_best(loadout, "crossroads", PATH, 0) == 625 and RECORDS.arsenal_best(loadout, "crossroads", PATH, 1) == 450 and RECORDS.arsenal_best(loadout, "crossroads", PATH, 2) == 775, "three source backup classes keep distinct expansion bests")
	check(not RECORDS.arsenal_record(loadout, state(2000), "crossroads", PATH, 3).saved and RECORDS.arsenal_best(loadout, "crossroads", PATH, 3) == 0, "unknown backup class cannot create an expansion record")
	check(RECORDS.record(1, state(250), PATH).saved and RECORDS.arsenal_best(loadout, "crossroads", PATH) == 450 and RECORDS.arsenal_best(other, "crossroads", PATH) == 700 and RECORDS.arsenal_best(loadout, "mira_hq", PATH) == 900 and RECORDS.arsenal_best(loadout, "crossroads", PATH, 0) == 625 and RECORDS.arsenal_best(loadout, "crossroads", PATH, 2) == 775, "a later original source record preserves every expansion/map/backup-class record")
	for invalid_score: Variant in [-1, 1.5, NAN, INF, "9999", RECORDS.MAX_SCORE + 1]:
		check(not RECORDS.arsenal_record(loadout, state(invalid_score), "crossroads", PATH).saved, "invalid expansion score is rejected: " + str(invalid_score))
	for key: String in ["enabled", "finished", "outcome"]:
		var rejected: Dictionary = state(1500)
		rejected[key] = "interrupted" if key == "outcome" else false
		check(not RECORDS.arsenal_record(loadout, rejected, "crossroads", PATH).saved, "non-counting result rejects record: " + key)
	var corrupted: ConfigFile = ConfigFile.new()
	check(corrupted.load(PATH) == OK, "record store remains parseable")
	corrupted.set_value("rush_arsenal_v1", LOADOUT.fingerprint(loadout), "bad-score")
	corrupted.save(PATH)
	check(RECORDS.arsenal_best(loadout, "crossroads", PATH) == 0, "malformed expansion bucket is recoverable")
	check(RECORDS.arsenal_record(loadout, state(800), "crossroads", PATH).saved and RECORDS.best(1, PATH) == 250 and RECORDS.arsenal_best(other, "crossroads", PATH) == 700 and RECORDS.arsenal_best(loadout, "crossroads", PATH, 0) == 625 and RECORDS.arsenal_best(loadout, "crossroads", PATH, 2) == 775, "repair preserves valid original, expansion and backup-class neighbors")
	var error: Dictionary = RECORDS.arsenal_record(loadout, state(1000), "crossroads", "user://arsenal_fixture_missing_7352/record.cfg")
	check(not error.saved and not str(error.error).is_empty(), "storage failure is explicit and does not claim a saved result")

func run() -> void:
	remove_fixture(PATH)
	remove_fixture(PREFS)
	identity_checks()
	storage_checks()
	remove_fixture(PATH)
	remove_fixture(PREFS)
	print("ARSENAL RECORDS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
