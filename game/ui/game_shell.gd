class_name GameShell
extends Control
## A presentation-only home and match setup. Main owns every launch and rule.
signal launch_requested(configuration: Dictionary)
signal utility_requested(kind: String)

const CATALOG = preload("res://ui/map_catalog.gd")
const TARGET_CSS: float = 56.0
const NAVY: Color = Color("07121e")
const PANEL: Color = Color("101f2e")
const SELECTED_PANEL: Color = Color("163c40")
const BORDER: Color = Color("294052")

var _selection: Dictionary = {"mode":"tdm", "map_id":"crossroads", "weapon":0}
const SURVIVAL_SETTINGS = preload("res://gameplay/survival_settings.gd")
var _survival_settings: Dictionary = {}
var _growth_preview: Label
var _last_maps: Dictionary[String, String] = {"tdm":"crossroads", "training":"lab"}
var _page: String = "home"
var _active_tab: String = "maps"
var _locale: String = "ru"
var _player_name: String = "Player"
var _pending: bool = false
var _mobile: bool = false
var _compact: bool = false
var _portrait: bool = false
var _css_size: Vector2 = Vector2(1280, 720)
var _logical_size: Vector2 = Vector2(1280, 720)
var _safe_insets: Vector4 = Vector4.ZERO
var _canvas: Control
var _margin: MarginContainer
var _layout: VBoxContainer
var _start: Button
var _rush_start: Button
var _summary: Label
var _error: Label
var _map_preview: TextureRect
var _map_title: Label
var _map_description: Label
var _map_notice: Label
var _maps_scroll: ScrollContainer
var _equipment_scroll: ScrollContainer
var _maps_button: Button
var _equipment_button: Button
var _map_buttons: Dictionary[String, Button] = {}
var _weapon_buttons: Dictionary[int, Button] = {}
var _map_marks: Dictionary[String, Label] = {}
var _weapon_marks: Dictionary[int, Label] = {}
var _textures: Dictionary[String, Texture2D] = {}
var _profile_rows: Array[Dictionary] = []
var _available_maps: Array[Dictionary] = []
var _layout_key: String = ""
var _metrics_age: float = 0.0
var _is_built: bool = false
var _original_scale_size: Vector2i
var _original_scale_aspect: Window.ContentScaleAspect
var _shell_window: Window
var _updating_metrics: bool = false

func _ready() -> void:
	_shell_window = get_window()
	_original_scale_size = get_window().content_scale_size
	_original_scale_aspect = get_window().content_scale_aspect
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_profile()
	var saved: Dictionary = CATALOG.load_selection()
	_survival_settings = CATALOG.load_survival_settings()
	var checked: Dictionary = CATALOG.validate(saved)
	if bool(checked.get("ok", false)):
		_selection = checked.configuration.duplicate(true)
		_last_maps[str(_selection.mode)] = str(_selection.map_id)
	_profile_rows = CATALOG.weapons("0.75")
	_canvas = Control.new()
	_canvas.name = "CSSCanvas"
	add_child(_canvas)
	get_viewport().size_changed.connect(_refresh_metrics)
	_refresh_metrics()
	_build_page()

func show_home() -> void:
	_page = "home"
	_pending = false
	_load_profile()
	if _is_built: _build_page()

func show_setup(mode: String = "tdm") -> void:
	var requested_mode: String = mode if mode in ["tdm", "training", "survival"] else "tdm"
	_available_maps = CATALOG.available_for(requested_mode)
	_selection.mode = requested_mode
	_selection.map_id = _last_maps.get(requested_mode, "lab" if requested_mode == "training" else "crossroads")
	if requested_mode == "survival": _selection.survival = _survival_settings.duplicate(true)
	var checked: Dictionary = CATALOG.validate(_selection)
	if not bool(checked.get("ok", false)) and not _available_maps.is_empty():
		_selection.map_id = str(_available_maps[0].id)
	_page = "setup"
	_pending = false
	_active_tab = "maps"
	_load_profile()
	_save_valid_selection()
	if _is_built: _build_page()

func select_map(id: String) -> void:
	if _pending: return
	var candidate: Dictionary = _selection.duplicate(true)
	candidate.map_id = id
	var checked: Dictionary = CATALOG.validate(candidate)
	if not bool(checked.get("ok", false)): return
	_selection = checked.configuration.duplicate(true)
	_last_maps[str(_selection.mode)] = str(_selection.map_id)
	_save_valid_selection()
	_refresh_selection()

func select_weapon(index: int) -> void:
	if _pending or index not in [0, 1, 2]: return
	var candidate: Dictionary = _selection.duplicate(true)
	candidate.weapon = index
	var checked: Dictionary = CATALOG.validate(candidate)
	if not bool(checked.get("ok", false)): return
	_selection = checked.configuration.duplicate(true)
	_save_valid_selection()
	_refresh_selection()

func get_selection() -> Dictionary:
	return _selection.duplicate(true)

func set_survival_settings(raw: Dictionary) -> bool:
	var checked: Dictionary = SURVIVAL_SETTINGS.validate(raw)
	if not checked.ok: return false
	_survival_settings = checked.settings
	if str(_selection.mode) == "survival":
		_selection.survival = _survival_settings.duplicate(true)
		_save_valid_selection()
		_refresh_selection()
	return true

func _set_wave_option(key: String, value: Variant) -> void:
	var candidate: Dictionary = _survival_settings.duplicate(true)
	candidate[key] = value
	set_survival_settings(candidate)

func _mode_title() -> String:
	match str(_selection.mode):
		"tdm": return _ui("Бой 3×3", "Battle 3×3")
		"survival": return _ui("Волны зомби", "Zombie waves")
		_: return _ui("Тренировка", "Training")

func get_display_state() -> Dictionary:
	var available_ids: Array[String] = []
	for entry: Dictionary in CATALOG.available_for(str(_selection.mode)):
		available_ids.append(str(entry.id))
	var rectangles: Dictionary[String, Rect2] = {}
	if is_instance_valid(_canvas): _collect_button_rects(_canvas, rectangles)
	return {"page":_page, "screen":_page, "selection":get_selection(),
		"mode":str(_selection.mode), "map_id":str(_selection.map_id), "weapon":int(_selection.weapon),
		"pending":_pending, "mobile":_mobile, "active_tab":_active_tab,
		"css_size":_css_size, "logical_size":_logical_size,
		"canvas_scale":_canvas.scale if is_instance_valid(_canvas) else Vector2.ONE,
		"minimum_target_css":TARGET_CSS, "safe_insets_css":_safe_insets,
		"start_disabled":_start.disabled if is_instance_valid(_start) else true,
		"summary_text":_summary.text if is_instance_valid(_summary) else "",
		"available_maps":available_ids, "button_rects_css":rectangles}

func _load_profile() -> void:
	var preferences: ConfigFile = ConfigFile.new()
	if preferences.load("user://settings.cfg") == OK:
		_locale = str(preferences.get_value("profile", "locale", "ru"))
		_player_name = str(preferences.get_value("profile", "name", "Player")).strip_edges()
	if _player_name.is_empty(): _player_name = "Player"

func _save_valid_selection() -> void:
	var checked: Dictionary = CATALOG.validate(_selection)
	if not bool(checked.get("ok", false)): return
	CATALOG.save_selection(checked.configuration)

func _process(delta: float) -> void:
	# The browser canvas can resize independently from the engine's design size.
	_metrics_age += delta
	if _metrics_age >= 0.25:
		_metrics_age = 0.0
		_refresh_metrics()

func _refresh_metrics() -> void:
	if not is_inside_tree() or _canvas == null or _updating_metrics: return
	_updating_metrics = true
	_css_size = Vector2(get_window().size).max(Vector2.ONE)
	_safe_insets = Vector4.ZERO
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("""(() => {
			const canvas = document.getElementById('canvas') || document.querySelector('canvas');
			if (!canvas) return '';
			const rect = canvas.getBoundingClientRect();
			const probe = document.createElement('div');
			probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
			document.body.appendChild(probe);
			const style = getComputedStyle(probe);
			const result = [rect.width, rect.height, parseFloat(style.paddingLeft)||0, parseFloat(style.paddingTop)||0, parseFloat(style.paddingRight)||0, parseFloat(style.paddingBottom)||0];
			probe.remove();
			return JSON.stringify(result);
		})()""")
		if raw is String:
			var decoded: Variant = JSON.parse_string(raw)
			if decoded is Array and decoded.size() == 6 and float(decoded[0]) > 0 and float(decoded[1]) > 0:
				_css_size = Vector2(float(decoded[0]), float(decoded[1]))
				_safe_insets = Vector4(float(decoded[2]), float(decoded[3]), float(decoded[4]), float(decoded[5]))
	elif OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var screen: Vector2i = DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0:
			var factor: Vector2 = _css_size / Vector2(screen)
			_safe_insets = Vector4(safe.position.x * factor.x, safe.position.y * factor.y,
				maxi(0, screen.x-safe.end.x) * factor.x, maxi(0, screen.y-safe.end.y) * factor.y)
	# The ordinary project keeps a 16:9 viewport. A portrait menu must first
	# remove that letterbox: local Control scaling cannot change its render area.
	# Use CSS-sized logical coordinates only while this shell owns the window.
	var desired_size: Vector2i = Vector2i(_css_size.round())
	if get_window().content_scale_size != desired_size:
		get_window().content_scale_size = desired_size
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_logical_size = get_viewport().get_visible_rect().size
	_mobile = _css_size.x < 960.0 or _css_size.y < 560.0
	_compact = _css_size.y < 440.0
	_portrait = _css_size.x < _css_size.y
	_canvas.size = _css_size
	_canvas.scale = _logical_size / _css_size.max(Vector2.ONE)
	var key: String = _metrics_key()
	if _is_built and key != _layout_key: _build_page()
	_layout_key = key
	_updating_metrics = false

func _exit_tree() -> void:
	# SceneTree detaches the old scene before its children exit. Retain the
	# actual Window and block resize callbacks from reapplying the shell scale.
	_updating_metrics = true
	if is_instance_valid(_shell_window):
		_shell_window.content_scale_size = _original_scale_size
		_shell_window.content_scale_aspect = _original_scale_aspect

func _build_page() -> void:
	if _canvas == null: return
	for child: Node in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	_start = null
	_rush_start = null
	_summary = null
	_error = null
	_map_preview = null
	_map_title = null
	_map_description = null
	_map_notice = null
	_maps_scroll = null
	_equipment_scroll = null
	_maps_button = null
	_equipment_button = null
	_map_buttons.clear()
	_weapon_buttons.clear()
	_map_marks.clear()
	_weapon_marks.clear()
	var background: ColorRect = ColorRect.new()
	background.color = NAVY
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_rect(background)
	_canvas.add_child(background)
	_margin = MarginContainer.new()
	_margin.name = "SafeArea"
	_full_rect(_margin)
	var padding: int = 12 if _mobile else 32
	var horizontal_padding: int = padding if _mobile else maxi(padding, floori((_css_size.x - 1440.0) * 0.5))
	_margin.add_theme_constant_override("margin_left", horizontal_padding + ceili(_safe_insets.x))
	_margin.add_theme_constant_override("margin_top", (8 if _compact else padding) + ceili(_safe_insets.y))
	_margin.add_theme_constant_override("margin_right", horizontal_padding + ceili(_safe_insets.z))
	_margin.add_theme_constant_override("margin_bottom", (8 if _compact else padding) + ceili(_safe_insets.w))
	_canvas.add_child(_margin)
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 8 if _mobile else 20)
	_margin.add_child(_layout)
	if _page == "setup":
		_build_setup()
	else:
		_build_home()
	_is_built = true
	_layout_key = _metrics_key()
	_refresh_selection()

func _build_home() -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.custom_minimum_size.y = TARGET_CSS
	_layout.add_child(header)
	var brand: Label = _label("BLOCKFIELD RUSH", 24 if _mobile else 30)
	brand.name = "HomeBrand"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	var profile: Label = _label(_player_name, 14, CombatTheme.MUTED)
	profile.custom_minimum_size.x = 64
	profile.clip_text = true
	profile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	profile.size_flags_horizontal = Control.SIZE_SHRINK_END
	profile.size_flags_stretch_ratio = 0.3
	header.add_child(profile)
	var scroll: ScrollContainer = _scroll("HomeContent")
	_layout.add_child(scroll)
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 40)
	scroll.add_child(content)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.size_flags_stretch_ratio = 0.9
	copy.add_theme_constant_override("separation", 8 if _mobile else 10)
	content.add_child(copy)
	if not _compact:
		copy.add_child(_label(_ui("ВОКСЕЛЬНОЕ ВЫЖИВАНИЕ", "VOXEL SURVIVAL"), 12, CombatTheme.ACCENT))
	var heading: Label = _label(_ui("Три минуты.\nОдна жизнь.", "Three minutes.\nOne life."), 32 if _mobile else 40)
	heading.name = "HomeHeading"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.visible = not _compact
	copy.add_child(heading)
	if not _compact:
		var intro: Label = _label(_ui("Выживай, выбирай усиления, строй и ломай укрытия.", "Survive, choose upgrades, build cover and break through it."), 16, CombatTheme.MUTED)
		intro.name = "HomeIntro"
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(intro)
	_rush_start = _button("Rush", _ui("Rush · 3 минуты  →", "Rush · 3 minutes  →"), _launch_rush, true)
	copy.add_child(_rush_start)
	var rush_note: Label = _label(_ui("Одна жизнь · Выбирай усиления · Разрушай и строй", "One life · Choose upgrades · Destroy and build"), 13, CombatTheme.ACCENT)
	rush_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(rush_note)
	_error = _label("", 14, CombatTheme.DANGER)
	_error.name = "HomeError"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	copy.add_child(_error)
	var secondary: GridContainer = GridContainer.new()
	secondary.name = "HomeSecondaryActions"
	secondary.columns = 2
	secondary.add_theme_constant_override("h_separation", 8)
	secondary.add_theme_constant_override("v_separation", 8)
	copy.add_child(secondary)
	var play: Button = _button("Play", _ui("Играть  →", "Play  →"), func() -> void: show_setup("tdm"))
	secondary.add_child(play)
	secondary.add_child(_button("Survival", _ui("Волны зомби", "Zombie waves"), func() -> void: show_setup("survival")))
	secondary.add_child(_button("Training", _ui("Тренировка", "Training"), func() -> void: show_setup("training")))
	secondary.add_child(_button("Arsenal", _ui("Арсенал · 20 предметов", "Arsenal · 20 items"), func() -> void: utility_requested.emit("arsenal")))
	secondary.add_child(_button("Settings", _ui("Настройки", "Settings"), func() -> void: _request_utility("settings")))
	if not _mobile:
		copy.add_child(_label(_ui("Без сервера · Классические режимы рядом", "No server needed · Classic modes available"), 13, CombatTheme.MUTED))
		var hero: PanelContainer = _panel()
		hero.custom_minimum_size.x = 470
		hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hero.size_flags_stretch_ratio = 1.2
		content.add_child(hero)
		var hero_content: VBoxContainer = VBoxContainer.new()
		hero_content.add_theme_constant_override("separation", 16)
		hero.add_child(hero_content)
		var hero_image: TextureRect = _image(str(CATALOG.get_entry("crossroads").get("preview", "")), Vector2(0, 300), true)
		hero_content.add_child(hero_image)
		hero_content.add_child(_label("CROSSROADS", 23))
		var hero_rules: Label = _label(_ui("Rush · 180 секунд волн, затем зачистка · Одна жизнь", "Rush · 180 seconds of waves, then cleanup · One life"), 14, CombatTheme.ACCENT)
		hero_rules.name = "HomeRushRules"
		hero_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hero_content.add_child(hero_rules)
		var home_note: Label = _label(_ui("Компактная арена из блоков. Каждый пролом открывает новый маршрут.", "A compact block arena. Every breach opens a new route."), 15, CombatTheme.MUTED)
		home_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hero_content.add_child(home_note)

func _build_setup() -> void:
	_available_maps = CATALOG.available_for(str(_selection.mode))
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_layout.add_child(header)
	var back: Button = _button("SetupBack", "←", show_home)
	back.custom_minimum_size.x = TARGET_CSS
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.tooltip_text = _ui("В главное меню", "Back to home")
	header.add_child(back)
	var title_column: VBoxContainer = VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 2)
	header.add_child(title_column)
	title_column.add_child(_label(_ui("Подготовка", "Match setup"), 22 if _mobile else 30))
	title_column.add_child(_label(_mode_title(), 13, CombatTheme.ACCENT))
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	if _mobile and not (_compact and not _portrait):
		_layout.add_child(tabs)
	else:
		header.add_child(tabs)
	_maps_button = _button("MapsTab", _ui("Карта", "Map"), func() -> void: _show_tab("maps"))
	if str(_selection.mode) == "survival": _maps_button.text = _ui("Волны и уровень", "Waves and level")
	_equipment_button = _button("EquipmentTab", _ui("Снаряжение", "Equipment"), func() -> void: _show_tab("equipment"))
	_maps_button.toggle_mode = true
	_equipment_button.toggle_mode = true
	tabs.add_child(_maps_button)
	tabs.add_child(_equipment_button)
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "SetupContent"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	_layout.add_child(body)
	_maps_scroll = _scroll("MapsContent")
	_maps_scroll.size_flags_stretch_ratio = 1.25
	body.add_child(_maps_scroll)
	var maps_column: VBoxContainer = _column(_maps_scroll)
	_build_maps(maps_column)
	_equipment_scroll = _scroll("EquipmentContent")
	_equipment_scroll.size_flags_stretch_ratio = 1.0
	body.add_child(_equipment_scroll)
	var equipment_column: VBoxContainer = _column(_equipment_scroll)
	_build_equipment(equipment_column)
	_build_footer()
	_show_tab(_active_tab)

func _build_maps(column: VBoxContainer) -> void:
	var survival: bool = str(_selection.mode) == "survival"
	if survival: column.add_child(_label(_ui("Уровень", "Level"), 19, CombatTheme.ACCENT))
	if not _mobile and not survival: column.add_child(_label(_ui("Карта", "Map"), 19))
	if not _compact and not survival:
		var featured: PanelContainer = _panel()
		column.add_child(featured)
		var preview_column: VBoxContainer = VBoxContainer.new()
		preview_column.add_theme_constant_override("separation", 10)
		featured.add_child(preview_column)
		_map_preview = _image("", Vector2(0, 150 if _mobile else 195), true)
		_map_preview.name = "SelectedMapPreview"
		preview_column.add_child(_map_preview)
		_map_title = _label("", 21)
		preview_column.add_child(_map_title)
		_map_description = _label("", 14, CombatTheme.MUTED)
		_map_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview_column.add_child(_map_description)
		_map_notice = _label("", 12, CombatTheme.ACCENT)
		_map_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview_column.add_child(_map_notice)
	var cards: GridContainer = GridContainer.new()
	cards.columns = 1 if _portrait or _compact or _available_maps.size() == 1 else 2
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	column.add_child(cards)
	for entry: Dictionary in _available_maps:
		var id: String = str(entry.id)
		var card: Button = _button("Map_"+id, "", func() -> void: select_map(id))
		card.custom_minimum_size.y = 72 if _compact else 100
		card.toggle_mode = true
		card.tooltip_text = _localized(entry, "description")
		cards.add_child(card)
		_map_buttons[id] = card
		var margin: MarginContainer = _card_margin(card, 8 if _compact else 12)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		margin.add_child(row)
		row.add_child(_image(str(entry.get("preview", "")), Vector2(72, 50) if _compact else Vector2(90, 70), true))
		var details: VBoxContainer = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		details.add_theme_constant_override("separation", 5)
		row.add_child(details)
		var name_label: Label = _label(_localized(entry, "name"), 15)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(name_label)
		var mark: Label = _label("", 12, CombatTheme.ACCENT)
		details.add_child(mark)
		_map_marks[id] = mark
		_ignore_mouse(margin)
	if survival: _build_wave_settings(column)
	if str(_selection.mode) == "training":
		var advanced: Button = _button("AdvancedLab", _ui("Расширенный полигон  →", "Advanced lab  →"), func() -> void: _request_utility("lab"))
		column.add_child(advanced)
		var hint: Label = _label(_ui("Импорт карт, мишени и тестовые параметры находятся на полигоне.", "Map import, targets, and test options are available in the lab."), 13, CombatTheme.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(hint)

func _build_wave_settings(column: VBoxContainer) -> void:
	column.add_child(_label(_ui("Настройки волн", "Wave settings"), 19, CombatTheme.ACCENT))
	_wave_number(column, "WaveDurationMinutes", _ui("Выжить, минут", "Survive, minutes"), "duration_seconds", 1, 30, 1, 60.0)
	_wave_number(column, "WaveZombieCount", _ui("Зомби на волну, до", "Zombies per wave, up to"), "zombies_per_wave", 1, 24, 1)
	_wave_number(column, "WaveInterval", _ui("Интервал волн, секунд", "Wave interval, seconds"), "wave_interval_seconds", 30, 120, 5)
	_wave_number(column, "ZombieDamage", _ui("Урон зомби игроку", "Zombie damage to player"), "zombie_damage", 1, 100, 1)
	_wave_number(column, "ZombieBlockDamage", _ui("Урон зомби по блокам", "Zombie damage to blocks"), "zombie_block_damage", 1, 100, 1)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var label: Label = _label(_ui("Рост со временем", "Growth with time"), 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var choice: OptionButton = OptionButton.new()
	choice.name = "WaveGrowthMode"
	choice.custom_minimum_size = Vector2(140, TARGET_CSS)
	for title: String in [_ui("Постоянно", "Constant"), _ui("Плавно", "Linear"), _ui("Ступенями", "Steps")]: choice.add_item(title)
	var modes: Array[String] = ["constant", "linear", "step"]
	choice.select(maxi(0, modes.find(str(_survival_settings.growth_mode))))
	choice.item_selected.connect(func(index: int) -> void: _set_wave_option("growth_mode", modes[index]))
	row.add_child(choice)
	_wave_number(column, "WaveGrowth", _ui("Прибавка зомби / минуту", "Extra zombies / minute"), "growth_per_minute", 0, 6, 0.5)
	_growth_preview = _label("", 13, CombatTheme.ACCENT)
	_growth_preview.name = "WaveGrowthPreview"
	_growth_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_growth_preview)
	var hint: Label = _label(_ui("20 секунд на постройку. Волны пересекаются; одновременно до 12 зомби. По таймеру спавн прекращается — добей оставшихся. Зомби выбирают обход или пролом.", "20 seconds to build. Waves overlap; up to 12 zombies alive. Spawning stops at the time limit — clear the survivors. Zombies choose a detour or a breach."), 13, CombatTheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var grenadier_hint: Label = _label(_ui("Каждый четвёртый зомби — метатель. Замах предупреждает бросок; граната отскакивает и взрывается с задержкой.", "Every fourth zombie is a grenadier. Its windup warns of the throw; the grenade bounces and explodes after a delay."), 13, CombatTheme.MUTED)
	grenadier_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(grenadier_hint)

func _wave_number(column: VBoxContainer, node_name: String, caption: String, key: String,
		minimum: float, maximum: float, step_value: float, divisor: float = 1.0) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var label: Label = _label(caption, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var number: SpinBox = SpinBox.new()
	number.name = node_name
	if key == "zombie_damage": number.tooltip_text = _ui("Урон укуса и максимальный урон гранаты; взрыв ослабевает с расстоянием.", "Bite damage and maximum grenade damage; blast damage falls with distance.")
	if key == "zombie_block_damage": number.tooltip_text = _ui("Урон каждого удара и урон гранаты каждой затронутой клетке. Здоровье блока сохраняется между ударами.", "Damage per strike and per grenade-affected block. Block health persists between hits.")
	number.custom_minimum_size = Vector2(104, TARGET_CSS)
	number.min_value = minimum
	number.max_value = maximum
	number.step = step_value
	number.value = float(_survival_settings[key]) / divisor
	number.value_changed.connect(func(value: float) -> void:
		_set_wave_option(key, value if key == "growth_per_minute" else int(round(value * divisor))))
	row.add_child(number)

func _build_equipment(column: VBoxContainer) -> void:
	if not _compact: column.add_child(_label(_ui("Основное оружие", "Primary weapon"), 19))
	for entry: Dictionary in _profile_rows:
		var index: int = int(entry.id)
		var card: Button = _button("Weapon_%d" % index, "", func() -> void: select_weapon(index))
		card.toggle_mode = true
		card.custom_minimum_size.y = TARGET_CSS if _compact else 126
		column.add_child(card)
		_weapon_buttons[index] = card
		var margin: MarginContainer = _card_margin(card, 8 if _compact else 12)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		margin.add_child(row)
		row.add_child(_image(str(entry.get("preview", "")), Vector2(72, 36) if _compact else Vector2(100, 76), false))
		var details: VBoxContainer = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		details.add_theme_constant_override("separation", 4)
		row.add_child(details)
		var weapon_name: Label = _label(_localized(entry, "name"), 17)
		weapon_name.name = "WeaponName"
		details.add_child(weapon_name)
		var role: Label = _label(_localized(entry, "role"), 13, CombatTheme.MUTED)
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role.visible = not _compact
		details.add_child(role)
		var reload_text: String = _ui("%.1f с / патрон", "%.1f s / shell") if bool(entry.get("reload_per_shell", false)) else _ui("%.1f с", "%.1f s")
		var stats: Label = _label(_ui("%d / %d патр. · Перезарядка ", "%d / %d rounds · Reload ") % [int(entry.clip_size), int(entry.reserve)] + reload_text % float(entry.reload_time), 12, CombatTheme.MUTED)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(stats)
		var mark: Label = _label("", 12, CombatTheme.ACCENT)
		mark.visible = not _compact
		details.add_child(mark)
		_weapon_marks[index] = mark
		_ignore_mouse(margin)
	var kit: PanelContainer = _panel()
	column.add_child(kit)
	var kit_column: VBoxContainer = VBoxContainer.new()
	kit_column.add_theme_constant_override("separation", 8)
	kit.add_child(kit_column)
	kit_column.add_child(_label(_ui("Стандартный комплект", "Standard kit"), 14))
	var tools: Label = _label(_ui("Лопата  ·  50 блоков  ·  3 гранаты", "Spade  ·  50 blocks  ·  3 grenades"), 13, CombatTheme.MUTED)
	tools.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kit_column.add_child(tools)
	var kit_note: String = _ui("В бою 3×3 — синяя команда. Оружие выдаётся при старте.", "In 3×3 you join blue team. Your weapon is issued at match start.") if str(_selection.mode) == "tdm" else _ui("В тренировке доступны обе командные внешности и тестовые параметры.", "Training offers both team appearances and test options.")
	if str(_selection.mode) == "survival": kit_note = _ui("Одна жизнь. Запасы конечны; между атаками ищи пункт снабжения.", "One life. Supplies are finite; find the supply point between attacks.")
	var team: Label = _label(kit_note, 12, CombatTheme.MUTED)
	team.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(team)

func _build_footer() -> void:
	var footer: PanelContainer = _panel(12 if _mobile else 18)
	footer.name = "SetupFooter"
	_layout.add_child(footer)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	footer.add_child(stack)
	_error = _label("", 12, CombatTheme.DANGER)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	stack.add_child(_error)
	var row: BoxContainer = VBoxContainer.new() if _portrait else HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if _mobile else 24)
	stack.add_child(row)
	_summary = _label("", 13 if _mobile else 16)
	_summary.name = "SelectionSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_summary)
	_start = _button("StartGame", "", _launch, true)
	_start.custom_minimum_size.x = 184 if _mobile else 240
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _portrait else Control.SIZE_SHRINK_END
	row.add_child(_start)

func _show_tab(tab: String) -> void:
	_active_tab = tab if tab in ["maps", "equipment"] else "maps"
	if _maps_scroll == null: return
	_maps_scroll.visible = not _mobile or _active_tab == "maps"
	_equipment_scroll.visible = not _mobile or _active_tab == "equipment"
	if _maps_button != null:
		_apply_card_style(_maps_button, _active_tab == "maps")
		_apply_card_style(_equipment_button, _active_tab == "equipment")

func _refresh_selection() -> void:
	if not _is_built: return
	if _page == "home":
		_refresh_home_actions(_canvas)
		if is_instance_valid(_rush_start):
			_rush_start.text = _ui("Подготовка…", "Preparing…") if _pending else _ui("Rush · 3 минуты  →", "Rush · 3 minutes  →")
		return
	if _page != "setup": return
	var entry: Dictionary = CATALOG.get_entry(str(_selection.map_id))
	if _map_preview != null: _map_preview.texture = _texture(str(entry.get("preview", "")))
	if _map_title != null: _map_title.text = _localized(entry, "name")
	if _map_description != null: _map_description.text = _localized(entry, "description")
	if _map_description != null and str(_selection.mode) == "survival": _map_description.text = _localized(entry, "description")
	if _map_notice != null:
		_map_notice.text = _ui("Вы и 2 союзника против 3 ботов · 25 убийств или 5 минут", "You and 2 allies against 3 bots · 25 kills or 5 minutes") if str(_selection.mode) == "tdm" else _ui("Свободная тренировка · Без сервера", "Free training · No server needed")
		if str(_selection.mode) == "survival": _map_notice.text = _ui("Выживание · Волны по времени · Одна жизнь", "Survival · Timed waves · One life")
	if is_instance_valid(_growth_preview) and str(_selection.mode) == "survival":
		var forecast: Array[int] = []
		for minute: int in [0, 5, 10]:
			forecast.append(clampi(roundi(float(_survival_settings.zombies_per_wave) + (0.0 if _survival_settings.growth_mode == "constant" else float(_survival_settings.growth_per_minute) * minute)), 1, 24))
		_growth_preview.text = _ui("Квота в начале / на 5-й / на 10-й минуте: %d / %d / %d", "Quota at start / minute 5 / minute 10: %d / %d / %d") % forecast
	for id: String in _map_buttons:
		var selected: bool = id == str(_selection.map_id)
		_apply_card_style(_map_buttons[id], selected)
		_map_marks[id].text = _ui("✓ Выбрано", "✓ Selected") if selected else _ui("Выбрать", "Select")
	for index: int in _weapon_buttons:
		var selected: bool = index == int(_selection.weapon)
		_apply_card_style(_weapon_buttons[index], selected)
		_weapon_marks[index].text = _ui("✓ Выбрано", "✓ Selected") if selected else _ui("Выбрать", "Select")
		var title: Label = _weapon_buttons[index].find_child("WeaponName", true, false) as Label
		if title != null:
			title.text = _localized(_profile_rows[index], "name") + ("  ✓" if _compact and selected else "")
	var weapon_name: String = ""
	for weapon: Dictionary in _profile_rows:
		if int(weapon.id) == int(_selection.weapon): weapon_name = _localized(weapon, "name")
	if _summary != null:
		_summary.text = "%s · %s\n%s" % [_mode_title(), _localized(entry, "name"), weapon_name]
		if str(_selection.mode) == "survival": _summary.text += _ui(" · %d мин", " · %d min") % (int(_survival_settings.duration_seconds) / 60)
	if _start != null:
		var checked: Dictionary = CATALOG.validate(_selection)
		_start.disabled = _pending or not bool(checked.get("ok", false))
		_start.text = _ui("Подготовка…", "Preparing…") if _pending else (_ui("Начать бой  →", "Start battle  →") if str(_selection.mode) == "tdm" else _ui("Начать тренировку  →", "Start training  →"))
		if str(_selection.mode) == "survival" and not _pending: _start.text = _ui("Начать выживание  →", "Start survival  →")

func show_launch_error(message: String) -> void:
	_pending = false
	_refresh_selection()
	if _error != null:
		_error.text = message
		_error.show()

func _launch() -> void:
	if _pending: return
	var checked: Dictionary = CATALOG.validate(_selection)
	if not bool(checked.get("ok", false)):
		if _error != null:
			_error.text = _ui("Выберите доступную карту и оружие.", "Choose an available map and weapon.")
			_error.show()
		return
	_selection = checked.configuration.duplicate(true)
	CATALOG.save_selection(_selection)
	_pending = true
	_refresh_selection()
	launch_requested.emit(get_selection())

func _launch_rush() -> void:
	if _pending: return
	# Rush is a one-shot launch, independent of the saved classic setup.
	var candidate: Dictionary = {"mode": "survival", "map_id": "crossroads",
		"weapon": int(_selection.weapon), "survival": SURVIVAL_SETTINGS.rush_defaults()}
	var checked: Dictionary = CATALOG.validate(candidate)
	if not bool(checked.get("ok", false)):
		show_launch_error(_ui("Rush недоступен. Проверьте карту и оружие.", "Rush is unavailable. Check the map and weapon."))
		return
	if is_instance_valid(_error): _error.hide()
	_pending = true
	_refresh_selection()
	launch_requested.emit(checked.configuration.duplicate(true))

func _refresh_home_actions(node: Node) -> void:
	if node == null: return
	if node is Button: (node as Button).disabled = _pending
	for child: Node in node.get_children():
		_refresh_home_actions(child)

func _request_utility(kind: String) -> void:
	if _pending: return
	utility_requested.emit(kind)

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _pending: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _page == "setup": show_home()
		get_viewport().set_input_as_handled()

func _ui(ru: String, en: String) -> String:
	return ru if _locale.begins_with("ru") else en

func _metrics_key() -> String:
	return "%s:%s:%s:%s:%s" % [_mobile, _compact, _portrait, _safe_insets, _css_size.round()]

func _localized(entry: Dictionary, key: String) -> String:
	return str(entry.get(key + ("_ru" if _locale.begins_with("ru") else "_en"), entry.get(key+"_en", "")))

func _label(value: String, point_size: int, color: Color = CombatTheme.WHITE) -> Label:
	var result: Label = Label.new()
	result.text = value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font", CombatTheme.font())
	result.add_theme_font_size_override("font_size", point_size)
	result.add_theme_color_override("font_color", color)
	return result

func _button(node_name: String, text_value: String, callback: Callable, primary: bool = false) -> Button:
	var result: Button = Button.new()
	result.name = node_name
	result.text = text_value
	result.custom_minimum_size = Vector2(TARGET_CSS, TARGET_CSS)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_override("font", CombatTheme.font())
	result.add_theme_font_size_override("font_size", 15 if _mobile else 17)
	result.add_theme_color_override("font_color", NAVY if primary else CombatTheme.WHITE)
	result.add_theme_color_override("font_hover_color", NAVY if primary else CombatTheme.WHITE)
	result.add_theme_color_override("font_pressed_color", NAVY if primary else CombatTheme.WHITE)
	result.add_theme_color_override("font_focus_color", NAVY if primary else CombatTheme.WHITE)
	result.add_theme_stylebox_override("normal", _style(CombatTheme.ACCENT if primary else PANEL, CombatTheme.ACCENT if primary else BORDER))
	result.add_theme_stylebox_override("hover", _style(Color("9ceddf") if primary else Color("1c3346"), CombatTheme.ACCENT))
	result.add_theme_stylebox_override("pressed", _style(Color("53bcaf") if primary else SELECTED_PANEL, CombatTheme.ACCENT))
	result.add_theme_stylebox_override("disabled", _style(Color("172531"), BORDER))
	var focus: StyleBoxFlat = _style(Color.TRANSPARENT, CombatTheme.WHITE)
	focus.set_border_width_all(2)
	result.add_theme_stylebox_override("focus", focus)
	result.pressed.connect(callback)
	return result

func _apply_card_style(button: Button, selected: bool) -> void:
	button.set_pressed_no_signal(selected)
	button.add_theme_stylebox_override("normal", _style(SELECTED_PANEL if selected else PANEL, CombatTheme.ACCENT if selected else BORDER))
	button.add_theme_stylebox_override("hover", _style(Color("1d4549") if selected else Color("1c3346"), CombatTheme.ACCENT))

func _style(fill: Color, outline: Color) -> StyleBoxFlat:
	var result: StyleBoxFlat = CombatTheme.panel()
	result.bg_color = fill
	result.border_color = outline
	result.shadow_size = 0
	result.set_corner_radius_all(12)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result

func _panel(padding: int = 16) -> PanelContainer:
	var result: PanelContainer = PanelContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = _style(PANEL, BORDER)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	result.add_theme_stylebox_override("panel", style)
	return result

func _scroll(node_name: String) -> ScrollContainer:
	var result: ScrollContainer = ScrollContainer.new()
	result.name = node_name
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result.follow_focus = true
	result.add_theme_constant_override("h_separation", 0)
	return result

func _column(parent: Node) -> VBoxContainer:
	var result: VBoxContainer = VBoxContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("separation", 12)
	parent.add_child(result)
	return result

func _image(path: String, minimum: Vector2, crop: bool) -> TextureRect:
	var result: TextureRect = TextureRect.new()
	result.texture = _texture(path)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if crop else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.custom_minimum_size = minimum
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL if minimum.x == 0 else Control.SIZE_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if _textures.has(path): return _textures[path]
	if not ResourceLoader.exists(path): return null
	var resource: Resource = load(path)
	if resource is Texture2D:
		_textures[path] = resource
		return resource
	return null

func _card_margin(parent: Control, padding: int) -> MarginContainer:
	var result: MarginContainer = MarginContainer.new()
	_full_rect(result)
	for side: String in ["left", "right", "top", "bottom"]:
		result.add_theme_constant_override("margin_"+side, padding)
	parent.add_child(result)
	return result

func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): _ignore_mouse(child)

func _full_rect(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _collect_button_rects(node: Node, output: Dictionary[String, Rect2]) -> void:
	if node is Button and node.is_visible_in_tree():
		var rectangle: Rect2 = node.get_global_rect()
		var scale_value: Vector2 = _canvas.scale.max(Vector2.ONE * 0.001)
		output[str(node.name)] = Rect2(rectangle.position / scale_value, rectangle.size / scale_value)
	for child: Node in node.get_children(): _collect_button_rects(child, output)
