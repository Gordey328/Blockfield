class_name GameMapCatalog
extends RefCounted
## Curated offline launch choices. Paths are authored here, never read from settings.

const WEAPON_PROFILES = preload("res://simulation/weapon_profiles.gd")
const SURVIVAL_SETTINGS = preload("res://gameplay/survival_settings.gd")
const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "play_selection"
const DEFAULT_CONFIGURATION: Dictionary = {"mode": "tdm", "map_id": "crossroads", "weapon": 0}
const PREVIEW_ROOT: String = "res://assets/ui/menu/"

static func entries() -> Array[Dictionary]:
	var training_modes: Array[String] = ["training"]
	var battle_modes: Array[String] = ["tdm", "survival"]
	return [
		{"id": "crossroads", "name_ru": "Crossroads", "name_en": "Crossroads",
			"description_ru": "Компактная арена с укрытиями и обходными путями. Вы и два союзника против трёх ботов.",
			"description_en": "A compact arena with cover and flank routes. You and two allies against three bots.",
			"modes": battle_modes, "resource": "", "preview": PREVIEW_ROOT + "map_crossroads.png"},
		{"id":"minecraft_chunk", "name_ru":"Minecraft · Лесной участок", "name_en":"Minecraft · Small chunk",
			"description_ru":"Небольшой участок Minecraft из карты Teardown: деревья и разрушаемые укрытия.",
			"description_en":"A compact Minecraft area adapted from a Teardown map, with trees and destructible cover.",
			"modes":["survival"], "resource":"res://assets/maps/survival_minecraft_chunk.bfmap", "preview":PREVIEW_ROOT + "map_survival_minecraft_chunk.png"},
		{"id":"mira_hq", "name_ru":"Among Us · MIRA HQ", "name_en":"Among Us · MIRA HQ",
			"description_ru":"Компактная адаптация MIRA HQ из Teardown: помещения, коридоры и разрушаемые перегородки.",
			"description_en":"A compact Teardown MIRA HQ adaptation, with rooms, corridors and destructible partitions.",
			"modes":["survival"], "resource":"res://assets/maps/survival_mira_hq.bfmap", "preview":PREVIEW_ROOT + "map_survival_mira_hq.png"},
		{"id": "lab", "name_ru": "Полигон", "name_en": "Training grounds",
			"description_ru": "Проверьте оружие, стройте и разрушайте блоки, тренируйтесь на мишенях.",
			"description_en": "Try the weapons, build and destroy blocks, and practice on targets.",
			"modes": training_modes.duplicate(), "resource": "", "preview": PREVIEW_ROOT + "map_lab.png"},
		{"id": "title", "name_ru": "Title", "name_en": "Title",
			"description_ru": "Оригинальный воксельный ландшафт OpenSpades для свободной тренировки.",
			"description_en": "An original OpenSpades voxel landscape for free practice.",
			"modes": training_modes.duplicate(), "resource": "res://assets/openspades/maps/Title.vxl",
			"preview": PREVIEW_ROOT + "map_title.png"},
		{"id": "mirage", "name_ru": "Mirage", "name_en": "Mirage",
			"description_ru": "Воксельная версия Mirage: улицы, дворы и разрушаемые укрытия. Режим тренировки.",
			"description_en": "Voxel Mirage: streets, courtyards and destructible cover. Training mode.",
			"modes": training_modes.duplicate(), "resource": "res://assets/maps/csgo_mirage.bfmap",
			"preview": PREVIEW_ROOT + "map_mirage.png"},
		{"id": "dust2", "name_ru": "Dust2", "name_en": "Dust2",
			"description_ru": "Воксельная версия Dust2 с крупными разрушаемыми блоками. Режим тренировки.",
			"description_en": "Voxel Dust2 with large destructible blocks. Training mode.",
			"modes": training_modes.duplicate(), "resource": "res://assets/maps/dust2.bfmap",
			"preview": PREVIEW_ROOT + "map_dust2.png"}
	]

static func available_for(mode: String) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	if mode not in ["tdm", "training", "survival"]:
		return choices
	for entry: Dictionary in entries():
		if (entry.modes as Array).has(mode) and _resource_available(entry):
			choices.append(entry)
	return choices

static func get_entry(id: String) -> Dictionary:
	for entry: Dictionary in entries():
		if str(entry.id) == id:
			return entry
	return {}

static func validate(configuration: Dictionary) -> Dictionary:
	# Whitelist launch identity and the separately validated survival settings.
	# Extra values can never become resource paths or lab cheats.
	if typeof(configuration.get("mode")) != TYPE_STRING or str(configuration.mode) not in ["tdm", "training", "survival"]:
		return _invalid("Choose a supported offline mode.")
	if typeof(configuration.get("map_id")) != TYPE_STRING:
		return _invalid("Choose a map from the catalog.")
	var entry: Dictionary = get_entry(str(configuration.map_id))
	if entry.is_empty() or not (entry.modes as Array).has(str(configuration.mode)):
		return _invalid("This map does not support the selected mode.")
	if not _resource_available(entry):
		return _invalid("The selected map is missing from this build.")
	if typeof(configuration.get("weapon")) != TYPE_INT or not WEAPON_PROFILES.valid("0.75", int(configuration.weapon)):
		return _invalid("Choose rifle, SMG or shotgun.")
	var canonical: Dictionary = {"mode": str(configuration.mode), "map_id": str(configuration.map_id), "weapon": int(configuration.weapon)}
	if canonical.mode == "survival":
		var raw: Variant = configuration.get("survival", SURVIVAL_SETTINGS.defaults())
		if not raw is Dictionary: return _invalid("Invalid wave settings.")
		var checked: Dictionary = SURVIVAL_SETTINGS.validate(raw)
		if not checked.ok: return _invalid(str(checked.error))
		canonical.survival = checked.settings
	if configuration.has("arsenal"):
		if not configuration.arsenal is Dictionary or canonical.mode == "tdm":
			return _invalid("Arsenal loadout requires training or survival.")
		canonical.arsenal = ArsenalCatalog.canonical_loadout(configuration.arsenal)
	return {"ok": true, "error": "", "configuration": canonical}

static func load_survival_settings() -> Dictionary:
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK: return SURVIVAL_SETTINGS.defaults()
	var raw: Variant = settings.get_value(SETTINGS_SECTION, "survival", SURVIVAL_SETTINGS.defaults())
	if not raw is Dictionary: return SURVIVAL_SETTINGS.defaults()
	var checked: Dictionary = SURVIVAL_SETTINGS.validate(raw)
	return checked.settings if checked.ok else SURVIVAL_SETTINGS.defaults()

static func load_selection() -> Dictionary:
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return DEFAULT_CONFIGURATION.duplicate(true)
	var candidate: Dictionary = {
		"mode": settings.get_value(SETTINGS_SECTION, "mode", DEFAULT_CONFIGURATION.mode),
		"map_id": settings.get_value(SETTINGS_SECTION, "map_id", DEFAULT_CONFIGURATION.map_id),
		"weapon": settings.get_value(SETTINGS_SECTION, "weapon", DEFAULT_CONFIGURATION.weapon)}
	if candidate.mode == "survival": candidate.survival = load_survival_settings()
	var result: Dictionary = validate(candidate)
	return result.configuration if bool(result.ok) else DEFAULT_CONFIGURATION.duplicate(true)

static func save_selection(configuration: Dictionary) -> Error:
	var result: Dictionary = validate(configuration)
	if not bool(result.ok):
		return ERR_INVALID_PARAMETER
	var settings: ConfigFile = ConfigFile.new()
	var loaded: Error = settings.load(SETTINGS_PATH)
	# A malformed or unreadable settings file must not be overwritten: it may
	# contain unrelated input, graphics, profile and audio preferences.
	if loaded not in [OK, ERR_FILE_NOT_FOUND]:
		return loaded
	for key: String in ["mode", "map_id", "weapon"]:
		settings.set_value(SETTINGS_SECTION, key, result.configuration[key])
	if result.configuration.mode == "survival":
		settings.set_value(SETTINGS_SECTION, "survival", result.configuration.survival)
	return settings.save(SETTINGS_PATH)

static func weapons(profile: String = "0.75") -> Array[Dictionary]:
	var selected_profile: String = profile if WEAPON_PROFILES.valid(profile) else "0.75"
	var names_ru: Array[String] = ["Винтовка", "Пистолет-пулемёт", "Дробовик"]
	var names_en: Array[String] = ["Rifle", "SMG", "Shotgun"]
	var roles_ru: Array[String] = ["Точные одиночные выстрелы", "Автоматический огонь", "Дробь для ближнего боя"]
	var roles_en: Array[String] = ["Accurate single shots", "Automatic fire", "Close-range pellets"]
	var image_names: Array[String] = ["rifle", "smg", "shotgun"]
	var choices: Array[Dictionary] = []
	for index: int in 3:
		var stats: Dictionary = WEAPON_PROFILES.get_info(selected_profile, index)
		choices.append({"id": index, "name_ru": names_ru[index], "name_en": names_en[index],
			"role_ru": roles_ru[index], "role_en": roles_en[index],
			"clip_size": int(stats.clip_size), "reserve": int(stats.max_stock),
			"reload_time": float(stats.reload_time), "reload_per_shell": bool(stats.slow_reload),
			"profile": selected_profile, "preview": PREVIEW_ROOT + "weapon_" + image_names[index] + ".png"})
	return choices

static func _resource_available(entry: Dictionary) -> bool:
	var path: String = str(entry.resource)
	return path.is_empty() or FileAccess.file_exists(path)

static func _invalid(error: String) -> Dictionary:
	return {"ok": false, "error": error, "configuration": DEFAULT_CONFIGURATION.duplicate(true)}
