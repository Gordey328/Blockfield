@static_unload
class_name OpenSpadesLocalization
extends RefCounted
## Original gettext catalogs are imported by Godot, including contexts/plurals.

const ROOT := "res://assets/openspades/locales/"
const SOURCE_IDS := ["en_us", "ru", "de", "el", "es", "fr", "hu", "id", "ja", "ko", "nl", "pl", "pt_br", "pt_pt", "uk", "vi", "zh_CN"]
static var _installed := false
static var _translations: Array[Translation] = []

# Authored offline-lab text falls back to English outside the original catalogs.
# Keys are the current UI's Russian text so existing labels can use lab(text).
const LAB_RU_TO_EN := {
	"BLOCKFIELD  /  ЛОКАЛЬНЫЙ ПОЛИГОН": "BLOCKFIELD  /  OFFLINE TEST LAB",
	"OPENSPADES → GODOT\nРАЗРАБОТКА · ИТЕРАЦИЯ 1": "OPENSPADES → GODOT\nIN DEVELOPMENT · ITERATION 1",
	"Испытательный полигон": "Test lab",
	"Все оригинальные виды оружия и две команды. Локальная сессия — сервер не нужен.": "All original weapons and both teams. Offline session — no server required.",
	"Арсенал": "Arsenal", "Солдаты": "Soldiers", "Мир и режимы": "World and modes", "Настройки": "Settings", "Проверка": "Checks",
	"ВОЙТИ НА ПОЛИГОН  →": "ENTER TEST LAB  →",
	"ОРУЖИЕ": "WEAPONS", "ИНСТРУМЕНТЫ": "TOOLS",
	"Винтовка": "Rifle", "Пистолет-пулемёт": "SMG", "Дробовик": "Shotgun",
	"Лопата · 1": "Spade · 1", "Блоки · 2": "Blocks · 2", "Оружие · 3": "Weapon · 3", "Граната · 4": "Grenade · 4",
	"Лопата": "Spade", "Блок": "Block", "Граната": "Grenade",
	"Профиль оригинальной игры": "Original game profile",
	"Неограниченные боеприпасы и материалы": "Unlimited ammo and building materials",
	"Пополнить оружие, гранаты и блоки": "Restock weapons, grenades and blocks",
	"Цвет блоков — E берёт цвет из мира": "Block color — E picks a color from the world",
	"В оригинале один солдат с командной окраской.\nПроверяйте оружие, позы, попадания и состояние после смерти.": "The original has one soldier with team colors.\nTest weapons, poses, hits and the dead state.",
	"Синяя команда": "Blue team", "Зелёная команда": "Green team", "Наблюдатель": "Spectator",
	"Неуязвимость для испытаний": "Invulnerability for testing",
	"Нанести себе 25 урона": "Take 25 damage", "Проверить смерть": "Test death", "Возродиться": "Respawn",
	"Вид от первого / третьего лица": "First / third person view",
	"ПОЗЫ МИШЕНЕЙ — применяются ко всем солдатам": "TARGET POSES — applied to every soldier",
	"Стоя": "Standing", "Присев": "Crouching", "Ходьба": "Walking", "Бег": "Sprinting", "После смерти": "Dead",
	"Сбросить испытательный полигон": "Reset test lab",
	"Загрузить оригинальную карту OpenSpades": "Load original OpenSpades map",
	"Сохранить изменённую карту .vxl": "Save edited .vxl map",
	"Локальные правила матча": "Offline match rules",
	"Свободные испытания": "Free testing", "CTF — захват разведданных": "CTF — capture the intel", "TC — контроль территорий": "TC — territorial control",
	"Поле зрения": "Field of view", "Чувствительность мыши": "Mouse sensitivity", "Громкость": "Volume", "Язык": "Language",
	"Проверяйте без подключения к серверу": "Test without connecting to a server",
	"Текущий билд находится в разработке. Полная готовность\nпереноса фиксируется по проверкам возможностей исходной игры.": "This build is in development. Completion is tracked\nagainst verified original-game features.",
	"ЛКМ  действие    ПКМ  прицел / копать / линия\nF  вид от третьего лица    N  карта    Tab  счёт": "LMB  action    RMB  aim / dig / block line\nF  third person    N  map    Tab  scoreboard",
	"WASD  движение   •   1–4  инструменты   •   R  перезарядка   •   Esc  полигон": "WASD  move   •   1–4  tools   •   R  reload   •   Esc  lab",
	"Лопата: ЛКМ бьёт блок, ПКМ копает три блока.\nБлоки: ЛКМ поставить, ПКМ удерживать и отпустить для линии.\nГраната: удерживайте ЛКМ для приготовления, отпустите для броска.": "Spade: LMB hits one block, RMB digs three blocks.\nBlocks: LMB places one, hold and release RMB for a line.\nGrenade: hold LMB to cook, release to throw.",
	"01   Оружие: темп, разброс, отдача, прицел и перезарядка\n02   Солдаты: обе команды, попадания по голове / телу / конечностям\n03   Мир: строительство, линии, разрушение опор и взрывы\n04   Движение: бег, прыжок, приседание, тихий ход, наблюдатель\n05   Матч: смерть, возрождение, CTF, TC, счёт и карта": "01   Weapons: cadence, spread, recoil, aiming and reload\n02   Soldiers: both teams, head / torso / limb hits\n03   World: blocks, lines, collapse and explosions\n04   Movement: sprint, jump, crouch, sneak and spectator\n05   Match: death, respawn, CTF, TC, scoreboard and map",
	"Локальное сообщение — Enter отправить": "Offline message — Enter to send",
	"%d HP   /   %d блоков   /   %d гранат": "%d HP   /   %d blocks   /   %d grenades",
	"Карта: %s  ·  Чанки: %s\nОружие: %s  ·  Профиль: %s": "Map: %s  ·  Chunks: %s\nWeapon: %s  ·  Profile: %s",
	"ЛОКАЛЬНЫЙ МАТЧ\n\nИгрок — %d HP\n\n": "OFFLINE MATCH\n\nPlayer — %d HP\n\n",
	"Мишень %02d   команда %d   HP %d\n": "Target %02d   team %d   HP %d\n",
	"%s  ·  %d урона": "%s  ·  %d damage", "Вы: %s\n": "You: %s\n",
	"ЛОПАТА": "SPADE", "БЛОКИ": "BLOCKS", "ГРАНАТА": "GRENADE",
}

static func normalize_locale(value: String) -> String:
	var candidate := value.replace("-", "_")
	var pieces := candidate.split("_")
	if pieces.size() > 1:
		candidate = pieces[0].to_lower() + "_" + pieces[1].to_upper()
	else:
		candidate = candidate.to_lower()
	if candidate == "en" or candidate == "en_US":
		return "en_US"
	for source_id: String in SOURCE_IDS:
		if source_id.to_lower() == candidate.to_lower():
			return "pt_BR" if source_id == "pt_br" else ("pt_PT" if source_id == "pt_pt" else source_id)
	# Region variants can select the original language-only catalog.
	if pieces.size() > 1 and pieces[0].to_lower() in SOURCE_IDS:
		return pieces[0].to_lower()
	return "en_US"

static func install() -> int:
	if _installed:
		return _translations.size()
	_installed = true
	for source_id: String in SOURCE_IDS:
		if source_id == "en_us":
			continue
		var path: String = ROOT + source_id + "/openspades.po"
		var catalog := load(path) as Translation
		if catalog == null:
			push_error("Original translation catalog unavailable: " + path)
			continue
		catalog.locale = normalize_locale(source_id)
		TranslationServer.add_translation(catalog)
		_translations.append(catalog)
	var lab_catalog := Translation.new()
	lab_catalog.locale = "ru"
	for russian: String in LAB_RU_TO_EN:
		lab_catalog.add_message(LAB_RU_TO_EN[russian], russian, "BlockfieldLab")
	TranslationServer.add_translation(lab_catalog)
	_translations.append(lab_catalog)
	return _translations.size()

static func set_locale(value: String) -> String:
	install()
	var normalized := normalize_locale(value)
	TranslationServer.set_locale(normalized)
	return normalized

static func get_languages() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for source_id: String in SOURCE_IDS:
		var description: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + source_id + ".json"))
		choices.append({"source_id": source_id, "locale": normalize_locale(source_id),
			"label": description.get("description", source_id), "english": description.get("descriptionEnglish", source_id)})
	return choices

static func text(message: String, context: String = "", arguments: Array = []) -> String:
	install()
	var translated: String = TranslationServer.translate(message, context)
	return translated.format(arguments) if not arguments.is_empty() else translated

static func lab(message: String) -> String:
	var source: String = LAB_RU_TO_EN.get(message, message)
	return text(source, "BlockfieldLab")

static func uninstall() -> void:
	for translation in _translations:
		TranslationServer.remove_translation(translation)
	_translations.clear()
	_installed = false
