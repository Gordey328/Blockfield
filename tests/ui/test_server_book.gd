extends SceneTree
## Pure favorite persistence and hostile-config checks; no Main or preferences.
const BOOK = preload("res://ui/server_book.gd")
const PATH := "user://server-book-test.cfg"
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SERVER BOOK: " + message)

func entry(name: String = "Local test", spectator: bool = false) -> Dictionary:
	return {"name": name, "game_url": "ws://127.0.0.1:19132/play", "map_url": "ws://127.0.0.1:19133/map", "spectator": spectator}

func backup(path: String) -> Dictionary:
	return {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func restore(path: String, saved: Dictionary) -> void:
	if saved.exists:
		var file := FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "fixture backup can be restored")
		if file != null:
			file.store_buffer(saved.bytes)
			file.close()
	elif FileAccess.file_exists(path):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "temporary fixture removed")

func equal_file(path: String, saved: Dictionary) -> bool:
	return FileAccess.file_exists(path) == saved.exists and (not saved.exists or FileAccess.get_file_as_bytes(path) == saved.bytes)

func config_for(records: int = 1) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("book", "version", 1)
	config.set_value("book", "next_id", records + 1)
	for index in records:
		for key: String in entry().keys():
			config.set_value("server_%d" % (index + 1), key, entry("Server %02d" % index)[key])
	return config

func reject_config(book: BOOK, config: ConfigFile, message: String) -> void:
	check(config.save(PATH) == OK, "corrupt fixture writes: " + message)
	var before := book.list()
	var result := book.load(PATH)
	check(not result.ok and not str(result.error).is_empty() and book.list() == before, "corrupt file rejected atomically: " + message)

func _run() -> void:
	var fixture_before := backup(PATH)
	var settings_before := backup("user://settings.cfg")
	var production_before := backup("user://servers.cfg")
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var book := BOOK.new()
	check(book.load(PATH).ok and book.list().is_empty() and not FileAccess.file_exists(PATH), "missing file yields empty catalog without creation")
	var first := entry("Zulu", true)
	var added := book.upsert(first)
	check(added.ok and added.id == 1 and not FileAccess.file_exists(PATH), "memory add does not persist until explicit save")
	first.name = "Mutated caller"
	check(book.get_entry(1).name == "Zulu", "book owns a copy of inserted record")
	check(book.upsert(entry("alpha")).ok and book.upsert(entry("Alpha second")).ok, "independent named favorites can be added")
	check(book.list()[0].name == "alpha" and book.list()[1].name == "Alpha second", "stable case-insensitive name sort")
	check(book.list(" ALP ").size() == 2 and book.list("missing").is_empty(), "filter matches names without modifying catalog")
	var listed := book.list()
	listed[0].name = "Changed returned list"
	var obtained := book.get_entry(1)
	obtained.game_url = "wss://changed.example/play"
	check(book.get_entry(1).game_url == entry().game_url and book.list()[0].name == "alpha", "list and lookup return isolated owned copies")
	check(book.save().ok and FileAccess.file_exists(PATH), "explicit save writes separate config")
	var saved := FileAccess.get_file_as_bytes(PATH)
	var second := BOOK.new()
	check(second.load(PATH).ok and second.list() == book.list() and second.get_entry(1).spectator, "fresh book restores exact addresses and spectator role")
	second.list("z"); second.get_entry(1)
	check(FileAccess.get_file_as_bytes(PATH) == saved, "load, filter and selection lookup never write")
	var update := entry("Renamed", false)
	update.id = 1
	check(second.upsert(update).ok and second.get_entry(1).name == "Renamed" and not second.get_entry(1).spectator, "update keeps identity and changes all public fields")
	check(second.remove(1).ok and second.get_entry(1).is_empty() and not second.remove(1).ok, "delete only removes existing selected identity")
	check(second.upsert(entry("Next")).id == 4, "deleted IDs are never reused")
	check(second.save().ok, "update/delete changes persist explicitly")
	var third := BOOK.new()
	check(third.load(PATH).ok and third.list() == second.list(), "persisted update/delete survives new instance")
	check(not third.set_storage_path("res://wrong.cfg").ok and third.set_storage_path(PATH).ok, "storage selection accepts only explicit user config paths without writing")
	var before := third.list()
	for key in ["resume_token", "bulk_token", "password", "role", "browser_secret"]:
		var private_record := entry()
		private_record[key] = "SECRET_NEVER_SAVED"
		check(not third.upsert(private_record).ok and third.list() == before, "extra private field rejected: " + key)
	var wrong_id := entry()
	wrong_id.id = 999
	check(not third.upsert(wrong_id).ok and third.list() == before, "unknown update cannot silently create record")
	for name in ["", " ", " leading", "trailing ", "name\nline", "name\u0085", "x".repeat(65), "я".repeat(33)]:
		check(not third.upsert(entry(name)).ok, "invalid or overlong display name rejected")
	check(third.upsert(entry("x".repeat(64))).ok and third.upsert(entry("я".repeat(32))).ok, "name boundary counts UTF-8 bytes")
	for role: Variant in [0, 1, "false", null]:
		var invalid_role := entry()
		invalid_role.spectator = role
		check(not third.upsert(invalid_role).ok, "role requires boolean, not coerced value")
	for url in ["wss://game.example/play", "ws://127.0.0.1:19132/play", "ws://localhost/map", "wss://example.test.:443/a", "ws://[::1]:19133/map", "wss://[2001:db8::1]/play", "wss://host/" + "a".repeat(2037)]:
		check(BOOK.valid_url(url), "valid public guest endpoint: " + url.substr(0, 70))
	for url in ["", "http://host/play", "WSS://host/play", "wss:///play", "wss://user:password@host/play", "wss://host/play#secret", "wss://host/play?token=secret", "wss://host/a b", "wss://host/a\u00a0b", "wss://host/a\nb", "wss://host\\play", "ws://[bad]:1/map", "ws://::1/map", "ws://-host/map", "ws://host-/map", "ws://a..b/map", "ws://host:/map", "ws://host:0/map", "ws://host:65536/map", "ws://host:abc/map", "ws://host:1:2/map", "wss://host/" + "я".repeat(1019)]:
		check(not BOOK.valid_url(url), "invalid or private endpoint rejected: " + url.substr(0, 70).replace("\n", "\\n"))
	var full := BOOK.new()
	for index in BOOK.MAX_SERVERS:
		check(full.upsert(entry("Server %02d" % index)).ok, "bounded catalog insert")
	check(full.list().size() == 64 and not full.upsert(entry("65th")).ok, "65th favorite is rejected without eviction")
	var at_capacity := entry("Updated at capacity")
	at_capacity.id = 1
	check(full.upsert(at_capacity).ok and full.list().size() == 64, "capacity does not prevent existing update")
	check(full.remove(17).ok and full.upsert(entry("Replacement")).id == 65, "deleted slot frees capacity while IDs remain monotonic")
	var corrupt := config_for()
	corrupt.set_value("book", "version", 1.0)
	reject_config(third, corrupt, "version type")
	corrupt = config_for(); corrupt.set_value("book", "version", 2)
	reject_config(third, corrupt, "unsupported version")
	corrupt = config_for(); corrupt.set_value("book", "next_id", 1)
	reject_config(third, corrupt, "nonmonotonic identity counter")
	corrupt = config_for(); corrupt.set_value("server_1", "resume_token", "SECRET_NEVER_SAVED")
	reject_config(third, corrupt, "extra private field")
	corrupt = config_for(); corrupt.set_value("server_1", "spectator", 1)
	reject_config(third, corrupt, "coerced role")
	corrupt = config_for(); corrupt.set_value("server_1", "game_url", "wss://host/play?token=SECRET_NEVER_SAVED")
	reject_config(third, corrupt, "credential query")
	corrupt = config_for(); corrupt.set_value("unknown", "value", true)
	reject_config(third, corrupt, "unknown section")
	corrupt = config_for(65)
	reject_config(third, corrupt, "oversized catalog")
	corrupt = config_for(); corrupt.set_value("book", "next_id", BOOK.MAX_ID + 2)
	reject_config(third, corrupt, "counter exceeds numeric bound")
	corrupt = config_for(); corrupt.set_value("server_1", "name", "")
	reject_config(third, corrupt, "empty saved name")
	corrupt = config_for()
	corrupt.set_value("book", "next_id", BOOK.MAX_ID + 1)
	for key: String in entry().keys(): corrupt.set_value("server_%d" % BOOK.MAX_ID, key, entry("Last identity")[key])
	corrupt.erase_section("server_1")
	check(corrupt.save(PATH) == OK and full.load(PATH).ok and full.list().size() == 1, "highest u32 identity and exhausted next counter load within bounds")
	check(not full.upsert(entry("Counter overflow")).ok and full.list().size() == 1, "exhausted identity counter cannot wrap or overwrite")
	var large := FileAccess.open(PATH, FileAccess.WRITE)
	large.store_string("x".repeat(BOOK.MAX_CONFIG_BYTES + 1)); large.close()
	var before_large := third.list()
	check(not third.load(PATH).ok and third.list() == before_large, "oversized bytes rejected before config parse with memory preserved")
	for path in ["res://servers.cfg", "user://../servers.cfg", "user://servers.txt", "C:/servers.cfg"]:
		check(not third.load(path).ok and third.list() == before_large, "non-user/config path rejected")
	check(third.save().ok and not FileAccess.get_file_as_string(PATH).contains("SECRET_NEVER_SAVED"), "failed hostile loads retain valid path and never persist private fields")
	check(equal_file("user://settings.cfg", settings_before), "exact application preference bytes preserved")
	check(equal_file("user://servers.cfg", production_before), "production favorites untouched by pure fixture tests")
	restore(PATH, fixture_before)
	check(equal_file(PATH, fixture_before), "fixture restored byte-for-byte")
	print("SERVER BOOK CHECKS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)
