extends SceneTree
const RECORDS = preload("res://gameplay/rush_records.gd")
const PATH: String = "user://rush_records_fixture.cfg"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RUSH RECORDS: " + label)

func run() -> void:
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(PATH)
	check(RECORDS.best(0, PATH) == 0, "missing storage starts with no record")
	var state: Dictionary = {"enabled": true, "finished": true, "outcome": "defeat", "score": 375}
	var first: Dictionary = RECORDS.record(0, state, PATH)
	check(first.saved and first.personal_best and RECORDS.best(0, PATH) == 375, "finished defeat can save earned points")
	check(not RECORDS.record(0, state, PATH).personal_best, "duplicate finish never claims new record")
	state.score = 200
	check(not RECORDS.record(0, state, PATH).saved and RECORDS.best(0, PATH) == 375, "lower result preserves best")
	state.score = 1000
	state.outcome = "win"
	check(RECORDS.record(1, state, PATH).saved and RECORDS.best(0, PATH) == 375 and RECORDS.best(1, PATH) == 1000, "weapons have independent records")
	state.outcome = "interrupted"
	state.score = 3000
	check(not RECORDS.record(0, state, PATH).saved, "technical interruption cannot set a record")
	state.outcome = "win"
	state.finished = false
	check(not RECORDS.record(0, state, PATH).saved, "unfinished run cannot set a record")
	state.finished = true
	state.enabled = false
	check(not RECORDS.record(0, state, PATH).saved, "classic mode cannot set a Rush record")
	state.enabled = true
	state.score = NAN
	check(not RECORDS.record(0, state, PATH).saved, "noninteger score is rejected")
	state.score = 2000
	check(not RECORDS.record(3, state, PATH).saved, "unknown weapon is rejected")
	var corrupted: ConfigFile = ConfigFile.new()
	corrupted.set_value(RECORDS.SECTION, "0", "huge")
	corrupted.set_value(RECORDS.SECTION, "1", 1000)
	corrupted.save(PATH)
	check(RECORDS.best(0, PATH) == 0, "malformed bucket is recoverable")
	check(RECORDS.record(0, state, PATH).saved and RECORDS.best(1, PATH) == 1000, "recovery preserves other valid records")
	var failure: Dictionary = RECORDS.record(2, state, "user://missing-rush-dir/records.cfg")
	check(not failure.saved and not failure.error.is_empty(), "storage failure is explicit without losing gameplay")
	DirAccess.remove_absolute(PATH)
	print("Rush records: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
