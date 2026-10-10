class_name BlockfieldServerBook
extends RefCounted
## Guest endpoint favorites only. No discovery, sockets or session capabilities.
const MAX_SERVERS := 64
const MAX_CONFIG_BYTES := 512 * 1024
const MAX_ID := 0xffffffff
const FIELDS := ["id", "name", "game_url", "map_url", "spectator"]
var _entries: Dictionary[int, Dictionary] = {}
var _next_id := 1
var _path := "user://servers.cfg"

static func _result(ok: bool, error: String = "") -> Dictionary:
	return {"ok": ok, "error": error}

static func _text_valid(value: String, limit: int) -> bool:
	if value.is_empty() or value.to_utf8_buffer().size() > limit:
		return false
	for index in value.length():
		var character := value.unicode_at(index)
		if character < 32 or (character >= 127 and character <= 159):
			return false
	return true

static func _digits(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		if value.unicode_at(index) < 48 or value.unicode_at(index) > 57:
			return false
	return true

static func valid_url(value: String) -> bool:
	if not _text_valid(value, 2048) or not (value.begins_with("ws://") or value.begins_with("wss://")):
		return false
	# Guest capabilities travel in HELLO, never saved URL userinfo/query/fragment.
	if value.contains("@") or value.contains("#") or value.contains("?") or value.contains("\\"):
		return false
	for index in value.length():
		var character := value.unicode_at(index)
		if character <= 32 or character in [0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] or (character >= 0x2000 and character <= 0x200a):
			return false
	var start := value.find("://") + 3
	var end := value.find("/", start)
	var authority := value.substr(start, (value.length() if end < 0 else end) - start)
	if authority.is_empty():
		return false
	var host := authority
	var port := ""
	if authority.begins_with("["):
		var closing := authority.find("]")
		if closing < 0:
			return false
		host = authority.substr(1, closing - 1)
		if not host.contains(":") or not host.is_valid_ip_address():
			return false
		var suffix := authority.substr(closing + 1)
		if not suffix.is_empty():
			if not suffix.begins_with(":"):
				return false
			port = suffix.substr(1)
			if port.is_empty():
				return false
	else:
		if authority.count(":") > 1:
			return false
		if authority.contains(":"):
			var split := authority.find(":")
			host = authority.substr(0, split)
			port = authority.substr(split + 1)
			if port.is_empty():
				return false
		if host.is_empty() or host.length() > 253:
			return false
		var labels := host.trim_suffix(".").split(".", true)
		for label: String in labels:
			if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
				return false
			for index in label.length():
				var character := label.unicode_at(index)
				if not ((character >= 48 and character <= 57) or (character >= 65 and character <= 90) or (character >= 97 and character <= 122) or character == 45):
					return false
	if not port.is_empty() and (not _digits(port) or port.length() > 5 or int(port) < 1 or int(port) > 65535):
		return false
	return true

static func _record_error(record: Dictionary, require_id: bool) -> String:
	if record.size() != (5 if require_id else 4):
		return "Saved server has unexpected fields."
	for field: String in FIELDS:
		if field == "id" and not require_id:
			continue
		if not record.has(field):
			return "Saved server is incomplete."
	if require_id and (typeof(record.id) != TYPE_INT or record.id <= 0 or record.id > MAX_ID):
		return "Saved server ID is invalid."
	if typeof(record.name) != TYPE_STRING or not _text_valid(record.name, 64) or record.name.strip_edges() != record.name:
		return "Use a server name of up to 64 UTF-8 bytes."
	if typeof(record.game_url) != TYPE_STRING or typeof(record.map_url) != TYPE_STRING or not valid_url(record.game_url) or not valid_url(record.map_url):
		return "Use public ws:// or wss:// addresses without credentials or query parameters."
	if typeof(record.spectator) != TYPE_BOOL:
		return "Saved spectator choice is invalid."
	return ""

func list(filter: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var match_text := filter.strip_edges().to_lower()
	for record: Dictionary in _entries.values():
		if match_text.is_empty() or record.name.to_lower().contains(match_text):
			result.append(record.duplicate(true))
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_name: String = first.name.to_lower()
		var second_name: String = second.name.to_lower()
		return first_name < second_name if first_name != second_name else int(first.id) < int(second.id))
	return result

func get_entry(id: int) -> Dictionary:
	return _entries[id].duplicate(true) if _entries.has(id) else {}

func upsert(record: Dictionary) -> Dictionary:
	var has_id := record.has("id")
	var error := _record_error(record, has_id)
	if not error.is_empty():
		return _result(false, error)
	if has_id and not _entries.has(int(record.id)):
		return _result(false, "Saved server is no longer available.")
	if not has_id and (_entries.size() >= MAX_SERVERS or _next_id > MAX_ID):
		return _result(false, "The saved server list is full.")
	var id: int = int(record.id) if has_id else _next_id
	var owned := record.duplicate(true)
	owned.id = id
	_entries[id] = owned
	if not has_id:
		_next_id += 1
	var result := _result(true)
	result["id"] = id
	return result

func remove(id: int) -> Dictionary:
	if not _entries.has(id):
		return _result(false, "Saved server is no longer available.")
	_entries.erase(id)
	return _result(true)

static func _path_valid(path: String) -> bool:
	return path.begins_with("user://") and path.ends_with(".cfg") and not path.contains("..") and _text_valid(path, 256)

func set_storage_path(path: String) -> Dictionary:
	if not _path_valid(path):
		return _result(false, "Saved server file path is invalid.")
	_path = path
	return _result(true)

func load(path: String = "user://servers.cfg") -> Dictionary:
	if not _path_valid(path):
		return _result(false, "Saved server file path is invalid.")
	if not FileAccess.file_exists(path):
		_entries.clear()
		_next_id = 1
		_path = path
		return _result(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_CONFIG_BYTES:
		return _result(false, "Saved server file is unavailable or too large.")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var source := bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes:
		return _result(false, "Saved server file contains invalid text.")
	var config := ConfigFile.new()
	if config.parse(source) != OK:
		return _result(false, "Saved server file is invalid.")
	var sections := config.get_sections()
	if sections.size() > MAX_SERVERS + 1 or not sections.has("book"):
		return _result(false, "Saved server count or format is invalid.")
	var book_keys := config.get_section_keys("book")
	if book_keys.size() != 2 or not book_keys.has("version") or not book_keys.has("next_id"):
		return _result(false, "Saved server format is unsupported.")
	var version: Variant = config.get_value("book", "version")
	if typeof(version) != TYPE_INT or version != 1:
		return _result(false, "Saved server format is unsupported.")
	var next_id: Variant = config.get_value("book", "next_id")
	if typeof(next_id) != TYPE_INT or next_id <= 0 or next_id > MAX_ID + 1:
		return _result(false, "Saved server identity counter is invalid.")
	var entries: Dictionary[int, Dictionary] = {}
	for section: String in sections:
		if section == "book":
			continue
		if not section.begins_with("server_") or not _digits(section.substr(7)):
			return _result(false, "Saved server section is invalid.")
		var keys := config.get_section_keys(section)
		if keys.size() != 4:
			return _result(false, "Saved server has unexpected fields.")
		var record: Dictionary = {"id": int(section.substr(7))}
		for field: String in ["name", "game_url", "map_url", "spectator"]:
			if not keys.has(field):
				return _result(false, "Saved server is incomplete.")
			record[field] = config.get_value(section, field)
		if not _record_error(record, true).is_empty() or entries.has(record.id) or record.id >= next_id:
			return _result(false, "Saved server entry is invalid.")
		entries[record.id] = record
	_entries = entries
	_next_id = next_id
	_path = path
	return _result(true)

func save() -> Dictionary:
	var config := ConfigFile.new()
	config.set_value("book", "version", 1)
	config.set_value("book", "next_id", _next_id)
	for record: Dictionary in list():
		var section := "server_%d" % int(record.id)
		for field: String in ["name", "game_url", "map_url", "spectator"]:
			config.set_value(section, field, record[field])
	var status := config.save(_path)
	return _result(status == OK, "" if status == OK else "Saved server file could not be written.")
