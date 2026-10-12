class_name ArsenalCatalog
extends RefCounted
## Authored expansion identities; source weapon/profile indices remain separate.

const RULES_VERSION: String = "arsenal_v1"
static var _cached: Array[Dictionary] = []
static var _by_id: Dictionary[String,Dictionary] = {}

static func entries() -> Array[Dictionary]:
	_ensure_cached()
	return _cached.duplicate()

static func _ensure_cached() -> void:
	if not _cached.is_empty(): return
	_cached = _build_entries()
	for item: Dictionary in _cached:
		item.make_read_only()
		_by_id[str(item.id)] = item

static func _build_entries() -> Array[Dictionary]:
	var rows: Array[Array] = [
		["x01", "Штопор", "Corkscrew", "Заряди гаусс-бур: до 8 блоков и двух целей.", "Charge a drill: pierce up to eight blocks and two targets.", 3, 12, 1.5, Color("ffbf65")],
		["x02", "Кирпичемёт", "Brick launcher", "Тяжёлый куб по дуге раскалывает опору и отбрасывает.", "Lob a heavy brick to break support and knock enemies back.", 4, 20, .75, Color("e88c63")],
		["x03", "Скрепка", "Paperclip", "Дуга прыгает по четырём видимым целям и замедляет.", "Arc between four visible enemies and briefly slow them.", 8, 32, .5, Color("64dfff")],
		["x04", "Утюг", "Hot iron", "Липкое пламя: четыре секунды топлива и опасные пятна.", "Four seconds of sticky flame; burning patches also hurt you.", 240, 480, .016667, Color("ff6747")],
		["x05", "Морозилка", "Freezer", "Накопи холод; разбей замороженную цель тяжёлым ударом.", "Build up cold, then shatter the ice with a heavy hit.", 24, 72, .1, Color("9eefff")],
		["x06", "Бумеранг мясника", "Butcher's boomerang", "Пила рикошетит три раза и возвращается, осторожнее.", "A returning saw bounces three times; watch the return path.", 1, 5, 3.0, Color("c7e49c")],
		["x07", "Улей", "Beehive", "Захвати видимую цель и выпусти три микророкеты.", "Lock onto a visible target and launch three micro rockets.", 3, 12, 1.0, Color("ffde65")],
		["x08", "Пылесос проблем", "Problem vacuum", "Стяни три цели в конус; отпусти, чтобы оттолкнуть.", "Pull three enemies into a cone, then release to push them.", 180, 360, .016667, Color("c396ff")],
		["x09", "Пеноплюй", "Foam spitter", "До девяти хрупких блоков укрытия на двенадцать секунд.", "Build up to nine fragile cover blocks lasting twelve seconds.", 4, 8, .7, Color("ff9edb")],
		["x10", "Гравимолот", "Gravity hammer", "Замах, отбрасывание и разрушение рядом. Боезапас не нужен.", "Wind up, push enemies away and break nearby cover. No ammo.", 1, 0, 1.5, Color("c3a5ff")],
		["x11", "Снос по расписанию", "Scheduled demolition", "Поставь до трёх зарядов. Альтернативное действие взрывает все.", "Attach three charges; alternate action detonates them together.", 0, 0, .4, Color("ff8a73")],
		["x12", "Попкорн", "Popcorn", "Пять подпрыгивающих зарядов, пять последовательных хлопков.", "Five bouncing charges make five staggered explosions.", 0, 0, 2.0, Color("fff0a7")],
		["x13", "Чёрная дырочка", "Tiny black hole", "Две секунды притяжения, затем один взрыв.", "Two seconds of attraction followed by a single blast.", 0, 0, 2.0, Color("a88bff")],
		["x14", "Дискотека", "Disco decoy", "Приманка меняет цель зомби на шесть секунд.", "A six-second decoy changes the zombies' pursuit target.", 0, 0, 2.0, Color("79ffe1")],
		["x15", "Банановая республика", "Banana republic", "Три видимые мины: взведение, подброс и цепная реакция.", "Three visible mines: arm, launch and chain-react.", 0, 0, 2.0, Color("ffe870")],
		["x16", "Карманное солнце", "Pocket sun", "Одна бомба за жизнь. Четыре секунды сирены и большой кратер.", "One bomb per run. Four-second warning and a large crater.", 0, 0, 4.0, Color("fffbd3")],
		["x17", "Небесный перфоратор", "Sky drill", "Маяк, две секунды предупреждения, узкий пролом сверху.", "Mark a spot; after two seconds drill a narrow hole from above.", 0, 0, 60.0, Color("76ddff")],
		["x18", "Рояль в кустах", "Piano surprise", "Пять пианино падают вдоль видимой отмеченной линии.", "Five pianos fall along a visible marked line.", 0, 0, 75.0, Color("ffc0e9")],
		["x19", "Турель в чемодане", "Suitcase turret", "Одна разрушаемая турель: 60 патронов, 15 секунд.", "One destructible turret: sixty rounds and fifteen seconds.", 0, 0, 60.0, Color("9cefaa")],
		["x20", "Пинок небес", "Sky kick", "Три секунды ограниченной тяги. Потолок и падение опасны.", "Three seconds of limited thrust. Ceilings and falls still hurt.", 0, 0, 45.0, Color("8fd9ff")]
	]
	var result: Array[Dictionary] = []
	for index: int in range(rows.size()):
		var row: Array = rows[index]
		var category: String = "primary" if index < 10 else ("bomb" if index < 16 else "stratagem")
		var stock: int = 0 if index < 10 else (3 if index == 10 or index == 14 else (1 if index == 12 or index == 15 else 2))
		result.append({"id":row[0], "name_ru":row[1], "name_en":row[2], "name":row[1],
			"description_ru":row[3], "description_en":row[4], "description":row[3],
			"category":category, "clip":row[5], "reserve":row[6], "cooldown":row[7],
			"color":row[8], "stock":stock, "power":index in [0,1,2,3,4,5,6]})
	return result

static func get_item(id: String) -> Dictionary:
	_ensure_cached()
	return _by_id.get(id,{})

static func valid(id: String) -> bool:
	return not get_item(id).is_empty()

static func defaults() -> Dictionary:
	return {"primary":"x01", "bomb":"x12", "stratagems":["x17","x20"]}

static func canonical_loadout(raw: Dictionary) -> Dictionary:
	var result: Dictionary = defaults()
	for key: String in ["primary", "bomb"]:
		var value: Variant = raw.get(key, result[key])
		if value is String and get_item(value).get("category", "") == key: result[key] = value
	var support: Variant = raw.get("stratagems", result.stratagems)
	if support is Array and support.size() == 2:
		if support[0] is String and support[1] is String and support[0] != support[1] \
				and get_item(support[0]).get("category", "") == "stratagem" and get_item(support[1]).get("category", "") == "stratagem":
			result.stratagems = support.duplicate()
	return result
