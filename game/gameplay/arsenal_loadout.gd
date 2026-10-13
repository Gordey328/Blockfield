class_name ArsenalLoadout
extends RefCounted
## Trusted local equipment preferences, independent of the original three classes.
const PATH: String = "user://arsenal_loadout.cfg"

static func load_saved(path: String = PATH) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return {"enabled": false, "loadout": ArsenalCatalog.defaults()}
	var raw: Variant = config.get_value("arsenal", "loadout", {})
	var enabled: Variant = config.get_value("arsenal", "enabled", false)
	return {"enabled": typeof(enabled) == TYPE_BOOL and enabled,
		"loadout": ArsenalCatalog.canonical_loadout(raw if raw is Dictionary else {})}

static func save(loadout: Dictionary, enabled: bool = true, path: String = PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("arsenal", "enabled", enabled)
	config.set_value("arsenal", "loadout", ArsenalCatalog.canonical_loadout(loadout))
	return config.save(path)

static func fingerprint(loadout: Dictionary, map_id: String = "crossroads", source_weapon: int = 1) -> String:
	var canonical: Dictionary = ArsenalCatalog.canonical_loadout(loadout)
	var rules: String = ArsenalCatalog.FULL_RULES_VERSION if canonical.get("all_items", false) else ArsenalCatalog.RULES_VERSION
	return ("%s|%s|source:%d|%s|%s|%s|%s" % [rules, map_id, source_weapon, canonical.primary,
		canonical.bomb, canonical.stratagems[0], canonical.stratagems[1]]).sha256_text()
