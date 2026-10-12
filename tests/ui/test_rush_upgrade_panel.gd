extends SceneTree
## Authority-driven offers, real selection signals and CSS-size layout bounds.
const PANEL = preload("res://ui/rush_upgrade_panel.gd")
const SHELL = preload("res://ui/game_shell.gd")
const CATALOG = preload("res://ui/map_catalog.gd")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
var checks: int = 0
var failures: int = 0
var chosen: Array[String] = []
var launches: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var globals: Dictionary = {"size": root.size, "scale_size": root.content_scale_size,
		"scale_mode": root.content_scale_mode, "scale_aspect": root.content_scale_aspect,
		"mouse_mode": Input.mouse_mode}
	var panel: RushUpgradePanel = PANEL.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.configure("ru")
	panel.upgrade_chosen.connect(func(id: String) -> void: chosen.append(id))
	var state: Dictionary = _offer()
	var original: Dictionary = state.duplicate(true)
	panel.refresh(state)
	await _frames(4)
	var display: Dictionary = panel.get_display_state()
	_check(display.visible and display.title.contains("Выбери"), "Pending Rush offer opens a localized choice panel")
	_check(display.choice_ids == ["power", "armor", "field_kit"] and display.titles == ["Сила", "Броня", "Полевой комплект"], "Cards use the three authority IDs and localized titles")
	_check(display.descriptions[0] == state.choices[0].description_ru, "Gameplay effect copy comes directly from authority")
	_check(display.build.contains("Мощность 1") and display.build.contains("Броня 2") and display.build.contains("Полевой набор 3"), "Current build shows committed levels independently of offers")
	_check(display.stats.contains("7") and display.stats.contains("420") and display.stats.contains("10"), "Score, kills and next threshold follow authoritative values")
	panel._buttons[1].pressed.emit()
	panel._buttons[0].pressed.emit()
	_check(chosen == ["armor"], "Selection emits one ID and blocks duplicate clicks until refreshed")
	_check(state == original and Input.mouse_mode == globals.mouse_mode, "Panel never mutates the supplied state or input capture")
	panel.refresh(state)
	panel._buttons[2].pressed.emit()
	_check(chosen == ["armor", "field_kit"], "Refreshed unchanged offer allows a rejected request to be retried")
	panel.refresh(state)
	var card_identity: Button = panel._buttons[0]
	panel.configure("en")
	display = panel.get_display_state()
	_check(display.title.contains("Choose") and display.titles[0] == "Power" and display.descriptions[1] == state.choices[1].description_en, "Locale updates titles and authoritative effect descriptions")
	panel.configure("en")
	panel.refresh(state)
	_check(panel._buttons[0] == card_identity, "Repeated configuration and refresh retain existing UI nodes")
	state.pending = false
	state.choices = []
	panel.refresh(state)
	panel._buttons[0].pressed.emit()
	_check(not panel.visible and panel._buttons[0].disabled and chosen.size() == 2, "No pending choice means no visible or selectable upgrade")
	state = _offer()
	state.enabled = false
	panel.refresh(state)
	_check(not panel.visible and panel._buttons[1].disabled, "Classic sessions cannot expose Rush choices")
	state = _offer()
	state.choices[0].description_en = "A strong upgrade with a longer authoritative explanation that must stay readable on a narrow screen and remain reachable by scrolling."
	panel.configure("en")
	for dimensions: Vector2i in [Vector2i(375, 812), Vector2i(812, 375), Vector2i(568, 320), Vector2i(1280, 720)]:
		for scaled: bool in [false, true]:
			root.size = dimensions
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if scaled else Window.CONTENT_SCALE_MODE_DISABLED
			root.content_scale_size = Vector2i(1280, 720) if scaled else Vector2i.ZERO
			root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			panel.refresh(state)
			await _frames(5)
			await _check_layout(panel, dimensions, scaled)
	panel.free()
	await _frames(2)
	await _check_quick_launch()
	root.size = globals.size
	root.content_scale_size = globals.scale_size
	root.content_scale_mode = globals.scale_mode
	root.content_scale_aspect = globals.scale_aspect
	_check(Input.mouse_mode == globals.mouse_mode, "Rush UI leaves mouse capture unchanged")
	print("RUSH UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_quick_launch() -> void:
	var settings_path: String = "user://settings.cfg"
	var existed: bool = FileAccess.file_exists(settings_path)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(settings_path) if existed else PackedByteArray()
	var preferences: ConfigFile = ConfigFile.new()
	preferences.load(settings_path)
	preferences.set_value("profile", "locale", "en")
	preferences.save(settings_path)
	var custom: Dictionary = SETTINGS.defaults()
	custom.duration_seconds = 900
	custom.zombie_damage = 35
	CATALOG.save_selection({"mode": "survival", "map_id": "crossroads", "weapon": 2, "survival": custom})
	var saved: Dictionary = CATALOG.load_selection()
	var shell: GameShell = SHELL.new()
	root.add_child(shell)
	shell.launch_requested.connect(func(configuration: Dictionary) -> void: launches.append(configuration.duplicate(true)))
	await _frames(4)
	for locale: String in ["ru", "en"]:
		preferences.load(settings_path)
		preferences.set_value("profile", "locale", locale)
		preferences.save(settings_path)
		shell.show_home()
		for dimensions: Vector2i in [Vector2i(375, 812), Vector2i(812, 375), Vector2i(568, 320), Vector2i(1280, 720)]:
			root.size = dimensions
			await _frames(4)
			var viewport: Rect2 = root.get_visible_rect()
			var css_per_logical: Vector2 = Vector2(dimensions) / viewport.size
			_check((shell.find_child("HomeBrand", true, false) as Label).text == "BLOCKFIELD RUSH", "Home names the primary Rush experience: " + locale)
			if dimensions.y >= 440:
				var intro: Label = shell.find_child("HomeIntro", true, false) as Label
				_check(intro != null and not intro.text.contains("3×3") and (intro.text.contains("усиления") or intro.text.contains("upgrades")), "Home explains survival and upgrades instead of the classic mode: " + locale)
			var rules: Label = shell.find_child("HomeRushRules", true, false) as Label
			if rules != null:
				_check(rules.text.contains("180") and (rules.text.contains("зачистка") or rules.text.contains("cleanup")), "Home distinguishes the wave timer from final cleanup: " + locale)
			for name_value: String in ["Rush", "Play", "Survival", "Training", "Settings"]:
				var target: Button = shell.find_child(name_value, true, false) as Button
				var context: String = "%s %s %s" % [locale, str(dimensions), name_value]
				_check(target != null and viewport.grow(0.5).encloses(target.get_global_rect()), "Home keeps Rush and existing actions immediately reachable: " + context)
				if target != null:
					_check(target.size.x * css_per_logical.x >= 55.5 and target.size.y * css_per_logical.y >= 55.5, "Home action keeps a56CSS target: " + context)
					var ancestor: Node = target.get_parent()
					while ancestor != null:
						if ancestor is Control and ((ancestor as Control).clip_contents or ancestor is ScrollContainer):
							_check((ancestor as Control).get_global_rect().grow(0.5).encloses(target.get_global_rect()), "Entire Home action stays inside its clipping ancestor: " + context)
						ancestor = ancestor.get_parent()
	var selection: Dictionary = shell.get_selection()
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(settings_path)
	var button: Button = shell.find_child("Rush", true, false) as Button
	_check(button != null and button.text.contains("3 minutes"), "Home has an English direct Rush launch button")
	if button != null:
		button.pressed.emit()
		button.pressed.emit()
	_check(launches.size() == 1, "Rush reuses the pending transaction to reject double launch")
	if launches.size() == 1:
		var config: Dictionary = launches[0]
		_check(config.mode == "survival" and config.map_id == "crossroads" and config.weapon == 2, "Rush launches canonical Crossroads with the retained weapon")
		_check(config.survival == SETTINGS.rush_defaults(), "Quick launch uses authored Rush settings without a setup page")
	_check(shell.get_selection() == selection and CATALOG.load_selection() == saved and FileAccess.get_file_as_bytes(settings_path) == bytes_before, "Rush does not overwrite classic selection or custom survival preferences")
	_check(shell.get_display_state().page == "home" and shell.get_display_state().pending and button.disabled, "Rush shows pending feedback directly on Home")
	shell.show_launch_error("Recoverable fixture error")
	_check(not shell.get_display_state().pending and not button.disabled and (shell.find_child("HomeError", true, false) as Label).text == "Recoverable fixture error", "Rejected launch releases Home controls and displays its reason")
	shell.free()
	await _frames(2)
	if existed:
		var output: FileAccess = FileAccess.open(settings_path, FileAccess.WRITE)
		output.store_buffer(before)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))


func _offer() -> Dictionary:
	return {"enabled": true, "pending": true, "kills": 7, "next_kills": 10, "score": 420,
		"levels": {"power": 1, "armor": 2, "field_kit": 3},
		"choices": [
			{"id": "power", "title_ru": "Сила", "title_en": "Power", "description_ru": "Урон +25%", "description_en": "Damage +25%"},
			{"id": "armor", "title_ru": "Броня", "title_en": "Armor", "description_ru": "Защита +15%", "description_en": "Protection +15%"},
			{"id": "field_kit", "title_ru": "Полевой комплект", "title_en": "Field kit", "description_ru": "Пополнение запасов", "description_en": "Refill supplies"}]}


func _check_layout(panel: RushUpgradePanel, dimensions: Vector2i, scaled: bool) -> void:
	var viewport: Rect2 = root.get_visible_rect()
	var css_per_logical: Vector2 = Vector2(dimensions) / viewport.size
	var context: String = "%s scaled=%s" % [str(dimensions), scaled]
	_check(panel._choices.columns == (3 if dimensions.x >= 800 and dimensions.y >= 500 else 1), "Cards adapt columns to available CSS size: " + context)
	_check(viewport.grow(0.5).encloses(panel._scroll.get_global_rect()) and panel._scroll.size.y > 56, "Upgrade content retains a usable scroll area: " + context)
	_check(panel._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Upgrade choices never require horizontal scrolling: " + context)
	for index: int in 3:
		var button: Button = panel._buttons[index]
		var rect: Rect2 = button.get_global_rect()
		_check(rect.size.x * css_per_logical.x >= 55.5 and rect.size.y * css_per_logical.y >= 55.5, "Choice retains a56CSS touch target: " + context)
		_check(rect.grow(0.5).encloses(panel._choice_titles[index].get_global_rect()) and rect.grow(0.5).encloses(panel._choice_details[index].get_global_rect()), "Authority title and full explanation stay inside their card: " + context)
		for previous: int in index:
			_check(not rect.grow(-0.5).intersects(panel._buttons[previous].get_global_rect().grow(-0.5)), "Choice cards do not overlap: " + context)
		panel._scroll.ensure_control_visible(button)
		await _frames(3)
		_check(panel._scroll.get_global_rect().intersects(button.get_global_rect()), "Each choice can be reached in the scroll area: " + context)


func _frames(count: int) -> void:
	for frame: int in count:
		await process_frame
		await create_timer(0.0).timeout


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RUSH UI: " + message)
