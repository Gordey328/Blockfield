extends SceneTree
## Real frontend controls and catalog contracts. Browser rendering remains a separate gate.
const SHELL = preload("res://scenes/game_shell.tscn")
const CATALOG = preload("res://ui/map_catalog.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const SETTINGS := "user://settings.cfg"
var checks: int = 0
var failures: int = 0
var shell: Control
var before: Dictionary = {}
var globals: Dictionary = {}
var launches: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GAME SHELL: " + message)


func frames(count: int) -> void:
	for frame: int in count:
		await process_frame
		await create_timer(0.0).timeout


func run() -> void:
	var exists := FileAccess.file_exists(SETTINGS)
	before = {"exists": exists, "bytes": FileAccess.get_file_as_bytes(SETTINGS) if exists else PackedByteArray()}
	globals = {"size": root.size, "scale_size": root.content_scale_size,
		"scale_aspect": root.content_scale_aspect, "scale_mode": root.content_scale_mode,
		"scale_factor": root.content_scale_factor, "mouse_mode": Input.mouse_mode,
		"locale": TranslationServer.get_locale()}
	test_catalog()
	shell = SHELL.instantiate()
	root.add_child(shell)
	shell.connect("launch_requested", func(configuration: Dictionary): launches.append(configuration.duplicate(true)))
	await frames(4)
	await test_selection()
	await test_layouts()
	await test_launch()
	shell.queue_free()
	await frames(4)
	check(root.content_scale_size == globals.scale_size and root.content_scale_aspect == globals.scale_aspect,
		"leaving the shell restores the game viewport even after scene detachment")
	restore()
	print("GAME SHELL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_catalog() -> void:
	var entries: Array = CATALOG.entries()
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(str(entry.id))
		check(not str(entry.get("name_ru", "")).is_empty() and not str(entry.get("name_en", "")).is_empty(),
			"map has player-facing localized titles: " + str(entry.id))
	check(ids.size() == 4 and ids.has("crossroads") and ids.has("lab") and ids.has("title") and ids.has("mirage"),
		"catalog exposes the four existing playable maps")
	var tdm: Array = CATALOG.available_for("tdm")
	check(tdm.size() == 1 and str(tdm[0].id) == "crossroads", "only authored Crossroads supports team battle")
	check(CATALOG.available_for("training").size() >= 3, "training exposes lab and the two imported maps")
	for map_id: String in ["lab", "title", "mirage"]:
		check(not bool(CATALOG.validate({"mode": "tdm", "map_id": map_id, "weapon": 0}).ok),
			"unsupported team map rejected: " + map_id)
	for cfg: Dictionary in [
		{"mode": "unknown", "map_id": "crossroads", "weapon": 0},
		{"mode": "training", "map_id": "lab", "weapon": -1},
		{"mode": "training", "map_id": "lab", "weapon": 3},
		{"mode": "training", "map_id": "res://assets/maps/../outside.bfmap", "weapon": 0}]:
		var result: Dictionary = CATALOG.validate(cfg)
		check(not bool(result.ok) and not str(result.get("error", "")).is_empty(), "bad mode, weapon or map returns a recoverable reason: " + str(cfg))
	for weapon: int in 3:
		var valid: Dictionary = CATALOG.validate({"mode": "tdm", "map_id": "crossroads", "weapon": weapon})
		check(bool(valid.ok) and valid.configuration.weapon == weapon, "each original firearm is admitted without changing the selection")
	for profile: String in ["0.75", "0.76"]:
		var weapons: Array = CATALOG.weapons(profile)
		check(weapons.size() == 3, "equipment catalog exposes the three original firearms for " + profile)
		for index: int in 3:
			var info: Dictionary = PROFILES.get_info(profile, index)
			check(weapons[index].id == index and weapons[index].clip_size == info.clip_size
				and weapons[index].reserve == info.max_stock and weapons[index].reload_time == info.reload_time
				and weapons[index].reload_per_shell == info.slow_reload,
				"equipment ammunition/reload values follow the actual weapon rules: " + profile + "/" + str(index))
	var extra: Dictionary = CATALOG.validate({"mode": "training", "map_id": "lab", "weapon": 0,
		"resource": "res://assets/maps/../outside.bfmap", "unlimited_ammo": true})
	check(bool(extra.ok) and extra.configuration.size() == 3 and not extra.configuration.has("resource"),
		"scene boundary admits only the three authored setup values")
	var preferences := ConfigFile.new()
	preferences.set_value("profile", "name", "UI fixture preserved name")
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("input", "mouse_sensitivity", 0.371)
	preferences.set_value("fixture", "sentinel", PackedInt32Array([17, 42]))
	check(preferences.save(SETTINGS) == OK, "isolated preferences are written")
	var selected := {"mode": "training", "map_id": "mirage", "weapon": 2}
	CATALOG.save_selection(selected)
	var loaded: Dictionary = CATALOG.load_selection()
	check(loaded.mode == selected.mode and loaded.map_id == selected.map_id and loaded.weapon == selected.weapon,
		"persisted map and firearm survive a fresh catalog load")
	check(preferences.load(SETTINGS) == OK and preferences.get_value("profile", "name") == "UI fixture preserved name"
		and is_equal_approx(float(preferences.get_value("input", "mouse_sensitivity")), 0.371)
		and preferences.get_value("fixture", "sentinel") == PackedInt32Array([17, 42]),
		"saving frontend choice preserves profile, controls and unrelated preference sections")
	var previous: Dictionary = CATALOG.load_selection()
	CATALOG.save_selection({"mode": "tdm", "map_id": "mirage", "weapon": 3})
	check(CATALOG.load_selection() == previous, "invalid choice cannot overwrite the last playable setup")


func button(name_value: String) -> Button:
	return shell.find_child(name_value, true, false) as Button


func press(name_value: String) -> void:
	var target := button(name_value)
	check(target != null and target.is_visible_in_tree() and not target.disabled, "real enabled control is reachable: " + name_value)
	if target != null and target.is_visible_in_tree() and not target.disabled:
		target.pressed.emit()
	await frames(2)


func selection() -> Dictionary:
	return shell.call("get_selection")


func test_selection() -> void:
	shell.call("show_home")
	await frames(2)
	await press("Training")
	await press("Map_mirage")
	await press("EquipmentTab")
	await press("Weapon_2")
	await press("MapsTab")
	check(selection().mode == "training" and selection().map_id == "mirage" and selection().weapon == 2,
		"map and shotgun survive real tab transitions")
	await press("EquipmentTab")
	check(selection().map_id == "mirage" and selection().weapon == 2, "returning to equipment retains both selections")
	await press("SetupBack")
	await press("Play")
	check(selection().mode == "tdm" and selection().map_id == "crossroads", "Play selects the only valid team-combat map")
	shell.call("select_map", "mirage")
	shell.call("select_weapon", 9)
	check(selection().map_id == "crossroads" and int(selection().weapon) in [0, 1, 2], "public selection API cannot create an unsupported launch")
	check(launches.is_empty(), "browsing mode, map and equipment never launches a match")


func test_layouts() -> void:
	for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1280, 720), Vector2i(375, 812), Vector2i(812, 375), Vector2i(568, 320)]:
		root.size = dimensions
		root.content_scale_size = Vector2i(1280, 720)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_factor = 1.0
		await frames(5)
		shell.call("show_home")
		await frames(3)
		var painted_size: Vector2 = root.get_visible_rect().size
		check(absf(painted_size.aspect() - Vector2(dimensions).aspect()) < 0.015,
			"menu render area follows the real device aspect without a16:9 letterbox: " + str(dimensions))
		check_controls(["Play", "Training"], dimensions, "home")
		shell.call("show_setup", "training")
		await frames(3)
		check_controls(["StartGame", "SetupBack", "MapsTab", "EquipmentTab"], dimensions, "map setup")
		for map_id: String in ["lab", "title", "mirage"]:
			await scroll_to(button("Map_" + map_id))
			check_controls(["Map_" + map_id], dimensions, "map card")
		await press("EquipmentTab")
		check_controls(["StartGame", "SetupBack", "MapsTab", "EquipmentTab"], dimensions, "equipment setup")
		for index: int in 3:
			await scroll_to(button("Weapon_" + str(index)))
			check_controls(["Weapon_" + str(index)], dimensions, "weapon card")
		var shown: Dictionary = shell.call("get_display_state")
		check(not shown.is_empty(), "layout exposes the actual drawn state for " + str(dimensions))


func scroll_to(target: Control) -> void:
	if target == null:
		return
	var ancestor: Node = target.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		(ancestor as ScrollContainer).ensure_control_visible(target)
	await frames(3)


func check_controls(names: Array[String], dimensions: Vector2i, page: String) -> void:
	var viewport := root.get_visible_rect()
	var css_scale := Vector2(dimensions) / viewport.size
	var rectangles: Array[Rect2] = []
	for name_value: String in names:
		var target := button(name_value)
		check(target != null and target.is_visible_in_tree(), "%s %s shows %s" % [str(dimensions), page, name_value])
		if target == null or not target.is_visible_in_tree():
			continue
		var rect := target.get_global_rect()
		check(viewport.grow(0.5).encloses(rect), "%s %s keeps %s within the actual viewport" % [str(dimensions), page, name_value])
		if dimensions.x < 900:
			check(rect.size.x * css_scale.x >= 55.5 and rect.size.y * css_scale.y >= 55.5,
				"mobile target remains at least56CSS px after viewport scaling: " + name_value + " " + str(dimensions))
		for previous: Rect2 in rectangles:
			check(not previous.grow(-0.5).intersects(rect.grow(-0.5)), "visible primary targets do not overlap on " + str(dimensions))
		rectangles.append(rect)


func test_launch() -> void:
	shell.call("show_setup", "training")
	await frames(2)
	shell.call("select_map", "lab")
	shell.call("select_weapon", 1)
	await press("StartGame")
	check(launches.size() == 1 and launches[0].mode == "training" and launches[0].map_id == "lab" and launches[0].weapon == 1,
		"real StartGame emits the chosen lab and SMG exactly once")
	var start := button("StartGame")
	if start != null:
		start.pressed.emit()
	await frames(2)
	check(launches.size() == 1, "rapid repeated StartGame signal cannot duplicate scene launch")


func restore() -> void:
	if before.exists:
		var file := FileAccess.open(SETTINGS, FileAccess.WRITE)
		file.store_buffer(before.bytes)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	root.size = globals.size
	root.content_scale_size = globals.scale_size
	root.content_scale_aspect = globals.scale_aspect
	root.content_scale_mode = globals.scale_mode
	root.content_scale_factor = globals.scale_factor
	Input.mouse_mode = globals.mouse_mode
	TranslationServer.set_locale(globals.locale)
