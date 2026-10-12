class_name ArsenalPanel
extends CanvasLayer
## Browse/equip locally and emit intents. Main owns admission, aim and capture.
signal loadout_changed(loadout: Dictionary)
signal item_selected(id: String)
signal apply_requested(id: String)
signal reload_requested
signal trigger_changed(held: bool)
signal catalog_toggled(open: bool)

const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const THEME = preload("res://ui/combat_theme.gd")
const TARGET_CSS: float = 56.0
const MAX_TOUCHES: int = 32
var _locale: String = "ru"
var _built: bool = false
var _enabled: bool = false
var _home_mode: bool = false
var _combat_visible: bool = true
var _catalog_open: bool = false
var _category: String = "primary"
var _strat_slot: int = 0
var _selected: String = "source"
var _loadout: Dictionary = {}
var _readout: Dictionary = {}
var _targeting: bool = false
var _actions_open: bool = false
var _compact_bank: bool = false
var _submitted: bool = false
var _firing: bool = false
var _canvas: Control
var _bank: PanelContainer
var _overlay: PanelContainer
var _catalog_margin: MarginContainer
var _slots: Array[Button] = []
var _more: Button
var _actions_row: HBoxContainer
var _all_buttons: Array[Button] = []
var _cards: Dictionary[String, Button] = {}
var _card_titles: Dictionary[String, Label] = {}
var _card_details: Dictionary[String, Label] = {}
var _tabs: Dictionary[String, Button] = {}
var _strat_buttons: Array[Button] = []
var _grid: GridContainer
var _scroll: ScrollContainer
var _hint: Label
var _meter: Label
var _apply: Button
var _reload: Button
var _source: Button
var _home_source: Button
var _catalog: Button
var _close_button: Button
var _title: Label
var _instruction: Label
var _logical_per_css: Vector2 = Vector2.ONE
var _css_extent: Vector2 = Vector2.ZERO
var _layout_age: float = 1.0
var _css_poll_age: float = 1.0
var _touches: Dictionary = {}
var _canceled_touches: Dictionary[int, bool] = {}
var _stock_text: String = ""
var _entries: Array[Dictionary] = []
var _entry_by_id: Dictionary[String, Dictionary] = {}

func _ready() -> void:
	_ensure_built()
	get_viewport().size_changed.connect(_refresh_layout)
	_refresh_layout()

func configure(locale: String = "ru") -> void:
	_locale = locale
	_ensure_built()
	_render()

func set_readout(readout: Dictionary) -> void:
	_ensure_built()
	_readout = readout.duplicate(true)
	_submitted = false
	if readout.get("loadout", null) is Dictionary and readout.loadout != _loadout: _loadout = CATALOG.canonical_loadout(readout.loadout)
	var selected: String = str(readout.get("selected_item", _selected))
	if selected != _selected:
		_cancel_touches()
		_actions_open = false
		_targeting = false
	_selected = selected
	if _selected == "source": _targeting = false
	if readout.has("targeting"): _targeting = bool(readout.targeting)
	_render()

func set_loadout(loadout: Dictionary) -> void:
	_ensure_built()
	_loadout = CATALOG.canonical_loadout(loadout)
	_render()

func set_enabled(value: bool) -> void:
	_ensure_built()
	_enabled = value
	if not value:
		_cancel_touches()
		_touches.clear()
		_canceled_touches.clear()
		_actions_open = false
		if _catalog_open: show_catalog(false)
	_render()

func set_home_mode(value: bool) -> void:
	_ensure_built()
	if value != _home_mode:
		_cancel_touches()
		_actions_open = false
	_home_mode = value
	_render()

func set_combat_visible(value: bool) -> void:
	_ensure_built()
	if _combat_visible and not value:
		_cancel_touches()
		_actions_open = false
	_combat_visible = value
	_render()

func show_catalog(open: bool) -> void:
	_ensure_built()
	if open and not _enabled: return
	if _catalog_open == open: return
	_cancel_touches()
	_actions_open = false
	_targeting = false
	_catalog_open = open
	_render()
	catalog_toggled.emit(open)

func close() -> void:
	show_catalog(false)
	_cancel_touches()
	_actions_open = false
	_targeting = false
	_render()

func is_catalog_open() -> bool:
	return _catalog_open

func request_application(id: String) -> void:
	# Keyboard shortcuts use exactly the same stock gates and aim/confirm path
	# as the visible action button; Main still validates the authoritative ray.
	_ensure_built()
	if not _enabled or not _combat_visible or _home_mode or _catalog_open: return
	var entry: Dictionary = _entry(id)
	if entry.is_empty(): return
	var primary: bool = str(entry.get("category", "")) == "primary"
	var stock: Dictionary = _readout.get("stock", {})
	var cooldowns: Dictionary = _readout.get("cooldowns", {})
	if not primary and (int(stock.get(id, entry.get("stock", 0))) <= 0 or float(cooldowns.get(id, 0.0)) > 0): return
	if id != _selected:
		_cancel_touches()
		_actions_open = false
		_selected = id
		_targeting = false
		_submitted = false
		item_selected.emit(id)
	_render()
	if not primary: _request_apply()

func get_safe_zones() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not _built: return result
	if _overlay.visible:
		result.append(_overlay.get_global_rect())
	elif _bank.visible:
		result.append(_bank.get_global_rect())
	return result

func get_display_state() -> Dictionary:
	var visible_ids: Array[String] = []
	for id: String in _cards:
		if _cards[id].visible: visible_ids.append(id)
	return {"enabled": _enabled, "catalog_open": _catalog_open,
		"selected_item": _selected, "category": _category,
		"loadout": _loadout.duplicate(true), "visible_ids": visible_ids,
		"catalog_count": _cards.size(), "targeting": _targeting,
		"apply_disabled": _apply.disabled, "apply_text": _apply.text,
		"hint": _hint.text, "stock_text": _meter.text,
		"columns": _grid.columns, "minimum_target_css": TARGET_CSS,
		"actions_open": _actions_open, "compact_bank": _compact_bank}

func _ensure_built() -> void:
	if _built: return
	_built = true
	layer = 130
	_loadout = CATALOG.defaults()
	_entries = CATALOG.entries()
	for entry: Dictionary in _entries: _entry_by_id[str(entry.id)] = entry
	_canvas = Control.new()
	_canvas.name = "ArsenalCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_bank = PanelContainer.new()
	_bank.name = "ArsenalCompactBank"
	_bank.mouse_filter = Control.MOUSE_FILTER_STOP
	_bank.add_theme_stylebox_override("panel", _style(Color("101f2e")))
	_canvas.add_child(_bank)
	var bank_layout: VBoxContainer = VBoxContainer.new()
	bank_layout.add_theme_constant_override("separation", 5)
	_bank.add_child(bank_layout)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	bank_layout.add_child(row)
	for index: int in 4:
		var button: Button = _button("ArsenalSlot%d" % index, _select_slot.bind(index))
		button.add_theme_font_size_override("font_size", 12)
		row.add_child(button)
		_slots.append(button)
	_more = _button("ArsenalMore", _toggle_actions)
	_more.size_flags_horizontal = Control.SIZE_SHRINK_END
	_more.add_theme_font_size_override("font_size", 12)
	row.add_child(_more)
	_actions_row = HBoxContainer.new()
	_actions_row.add_theme_constant_override("separation", 5)
	bank_layout.add_child(_actions_row)
	_catalog = _button("ArsenalBrowse", func() -> void: show_catalog(true))
	_source = _button("ArsenalSource", _return_source)
	_reload = _button("ArsenalReload", _request_reload)
	_apply = _button("ArsenalApply", _request_apply)
	_apply.button_down.connect(_press_fire)
	_apply.button_up.connect(_release_fire)
	for button: Button in [_catalog, _source, _reload, _apply]: _actions_row.add_child(button)
	_meter = _label("", 12, THEME.MUTED)
	bank_layout.add_child(_meter)
	_hint = _label("", 12, THEME.WARNING)
	bank_layout.add_child(_hint)
	_overlay = PanelContainer.new()
	_overlay.name = "ArsenalCatalog"
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_theme_stylebox_override("panel", _style(Color("101f2e")))
	_canvas.add_child(_overlay)
	_catalog_margin = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: _catalog_margin.add_theme_constant_override("margin_" + side, 12)
	_overlay.add_child(_catalog_margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_catalog_margin.add_child(layout)
	var heading: HBoxContainer = HBoxContainer.new()
	layout.add_child(heading)
	_title = _label("", 22, THEME.ACCENT)
	heading.add_child(_title)
	_home_source = _button("ArsenalHomeClassic", _return_source)
	_home_source.size_flags_horizontal = Control.SIZE_SHRINK_END
	_home_source.custom_minimum_size.x = 128
	heading.add_child(_home_source)
	_close_button = _button("ArsenalClose", func() -> void: close())
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	heading.add_child(_close_button)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	layout.add_child(tabs)
	for category: String in ["primary", "bomb", "stratagem"]:
		var button: Button = _button("ArsenalTab_" + category, _choose_category.bind(category))
		tabs.add_child(button)
		_tabs[category] = button
	var slots_row: HBoxContainer = HBoxContainer.new()
	layout.add_child(slots_row)
	for index: int in 2:
		var button: Button = _button("ArsenalStratSlot%d" % index, _choose_strat_slot.bind(index))
		slots_row.add_child(button)
		_strat_buttons.append(button)
	_instruction = _label("", 13, THEME.MUTED)
	layout.add_child(_instruction)
	_scroll = ScrollContainer.new()
	_scroll.name = "ArsenalScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "ArsenalCards"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	for entry: Dictionary in _entries:
		var id: String = str(entry.id)
		var button: Button = _button("ArsenalCard_" + id, _equip.bind(id))
		button.custom_minimum_size.y = 142
		button.clip_text = false
		button.add_theme_stylebox_override("normal", _style(Color("1c3346"), entry.get("color", THEME.ACCENT)))
		_grid.add_child(button)
		_cards[id] = button
		var content: VBoxContainer = VBoxContainer.new()
		# The preset must resolve against its actual card parent, including on the
		# first open before the deferred GridContainer sort has run.
		button.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 12
		content.offset_right = -12
		content.offset_top = 10
		content.offset_bottom = -10
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 7)
		var title: Label = _label("", 17, entry.get("color", THEME.ACCENT))
		content.add_child(title)
		_card_titles[id] = title
		var detail: Label = _label("", 13)
		content.add_child(detail)
		_card_details[id] = detail
	_render()

func _render() -> void:
	if not _built: return
	_bank.visible = _enabled and not _catalog_open and not _home_mode and _combat_visible
	_overlay.visible = _enabled and _catalog_open
	_title.text = _ui("Арсенал · 20 идей", "Arsenal · 20 inventions")
	_close_button.text = _ui("Готово", "Done")
	_catalog.text = _ui("Арсенал", "Arsenal")
	_source.text = _ui("Обычное", "Classic")
	_home_source.text = _ui("Обычный набор", "Classic kit")
	_home_source.visible = _home_mode
	_reload.text = _ui("Зарядить", "Reload")
	_tabs.primary.text = _ui("Оружие · 10", "Weapons · 10")
	_tabs.bomb.text = _ui("Бомбы · 6", "Bombs · 6")
	_tabs.stratagem.text = _ui("Поддержка · 4", "Support · 4")
	for category: String in _tabs: _tabs[category].button_pressed = category == _category
	for index: int in 2:
		_strat_buttons[index].visible = _category == "stratagem"
		_strat_buttons[index].text = _ui("В слот поддержки %d", "Equip support slot %d") % (index + 1)
		_strat_buttons[index].button_pressed = index == _strat_slot
	_instruction.text = _ui("Выбери предмет: 1 оружие, 1 бомба, 2 поддержки. Применяй после закрытия.", "Choose one weapon, one bomb and two supports. Use them after closing.")
	for index: int in 4:
		var id: String = _slot_item(index)
		_slots[index].text = "%s\n%s" % [_slot_label(index), _name(id)]
		_slots[index].tooltip_text = _description(id)
		_slots[index].button_pressed = id == _selected
	for id: String in _cards:
		var entry: Dictionary = _entry(id)
		_cards[id].visible = str(entry.get("category", "")) == _category
		_cards[id].disabled = not _enabled
		_card_titles[id].text = _name(id) + ("  ✓" if _is_equipped(id) else "")
		_card_details[id].text = _description(id) + "\n" + _stock_label(id, entry)
	var selected_entry: Dictionary = _entry(_selected)
	var primary: bool = str(selected_entry.get("category", "")) == "primary"
	var support: bool = str(selected_entry.get("category", "")) == "stratagem"
	var stock: Dictionary = _readout.get("stock", {})
	var cooldowns: Dictionary = _readout.get("cooldowns", {})
	var ready: bool = _enabled and _selected != "source" and not _submitted
	if not primary: ready = ready and int(stock.get(_selected, selected_entry.get("stock", 0))) > 0 and float(cooldowns.get(_selected, 0.0)) <= 0.0
	if support and _targeting: ready = ready and bool(_readout.get("target_valid", true))
	_apply.disabled = not ready
	_reload.disabled = not _enabled or not primary
	_apply.text = _ui("Огонь", "Fire") if primary else (_ui("Подтвердить", "Confirm") if _targeting else (_ui("Навести", "Aim") if support else _ui("Бросить", "Throw")))
	_meter.text = _ui("Обычный набор · выбери новый предмет", "Classic kit · choose an invention") if _selected == "source" else _name(_selected) + " · " + _stock_label(_selected, selected_entry)
	if primary:
		_meter.text += _ui(" · заряд %d%% · нагрев %d%%", " · charge %d%% · heat %d%%") % [roundi(float(_readout.get("charge", 0.0)) * 100), roundi(float(_readout.get("heat", 0.0)) * 100)]
	if float(_readout.get("jet_remaining", 0.0)) > 0.0:
		_meter.text += _ui(" · тяга %.1f с", " · thrust %.1f s") % float(_readout.jet_remaining)
	_stock_text = _meter.text
	_hint.text = str(_readout.get("target_reason", _ui("Наведи прицел на видимое место и подтверди вызов", "Aim at a visible location and confirm support"))) if _targeting else ""
	_hint.visible = _targeting
	_refresh_layout()

func _choose_category(category: String) -> void:
	_category = category
	_scroll.scroll_vertical = 0
	_render()

func _choose_strat_slot(index: int) -> void:
	_strat_slot = clampi(index, 0, 1)
	_render()

func _equip(id: String) -> void:
	if not _enabled or not _catalog_open: return
	var entry: Dictionary = _entry(id)
	if entry.is_empty(): return
	_release_fire()
	var category: String = str(entry.category)
	if category == "stratagem":
		var supports: Array = _loadout.get("stratagems", []).duplicate()
		if supports.size() != 2: supports = ["x17", "x19"]
		var other: int = 1 - _strat_slot
		if str(supports[other]) == id: supports[other] = supports[_strat_slot]
		supports[_strat_slot] = id
		_loadout.stratagems = supports
	else: _loadout[category] = id
	_loadout = CATALOG.canonical_loadout(_loadout)
	_selected = id
	_targeting = false
	loadout_changed.emit(_loadout.duplicate(true))
	item_selected.emit(id)
	_render()

func _select_slot(index: int) -> void:
	if not _enabled or not _combat_visible or _home_mode or _catalog_open: return
	_cancel_touches()
	_actions_open = false
	_selected = _slot_item(index)
	_targeting = false
	item_selected.emit(_selected)
	_render()

func _return_source() -> void:
	if not _enabled: return
	_cancel_touches()
	_actions_open = false
	_selected = "source"
	_targeting = false
	item_selected.emit("source")
	close()
	_render()

func _request_reload() -> void:
	if not _reload.disabled and _enabled and _combat_visible and not _home_mode and not _catalog_open: reload_requested.emit()

func _request_apply() -> void:
	if _apply.disabled or not _enabled or not _combat_visible or _home_mode or _catalog_open: return
	var entry: Dictionary = _entry(_selected)
	if str(entry.get("category", "")) == "primary": return
	if str(entry.get("category", "")) == "stratagem" and not _targeting:
		_cancel_touches()
		_actions_open = false
		_targeting = true
		_render()
		return
	_submitted = true
	_cancel_touches()
	_actions_open = false
	_targeting = false
	apply_requested.emit(_selected)
	_render()

func _press_fire() -> void:
	if _apply.disabled or not _enabled or not _combat_visible or _home_mode or _catalog_open: return
	if str(_entry(_selected).get("category", "")) != "primary": return
	if _firing: return
	_firing = true
	trigger_changed.emit(true)

func _release_fire() -> void:
	if not _firing: return
	_firing = false
	trigger_changed.emit(false)

func _toggle_actions() -> void:
	if not _enabled or not _combat_visible or _home_mode or _catalog_open: return
	if _targeting:
		_request_apply()
		return
	_cancel_touches()
	_actions_open = not _actions_open
	_render()

func _cancel_touches() -> void:
	_release_fire()
	for index: int in _touches:
		if _canceled_touches.size() < MAX_TOUCHES: _canceled_touches[index] = true
	_touches.clear()

func _slot_item(index: int) -> String:
	if index < 2: return str(_loadout.get("primary" if index == 0 else "bomb", ""))
	var supports: Array = _loadout.get("stratagems", [])
	return str(supports[index - 2]) if supports.size() >= index - 1 else ""

func _slot_label(index: int) -> String:
	return [_ui("Оружие", "Weapon"), _ui("Бомба", "Bomb"), _ui("Поддержка 1", "Support 1"), _ui("Поддержка 2", "Support 2")][index]

func _is_equipped(id: String) -> bool:
	for index: int in 4:
		if _slot_item(index) == id: return true
	return false

func _name(id: String) -> String:
	var entry: Dictionary = _entry(id)
	return str(entry.get("name_ru" if _locale.begins_with("ru") else "name_en", entry.get("name", "—")))

func _description(id: String) -> String:
	var entry: Dictionary = _entry(id)
	return str(entry.get("description_ru" if _locale.begins_with("ru") else "description_en", entry.get("description", "")))

func _entry(id: String) -> Dictionary:
	return _entry_by_id.get(id, {})

func _stock_label(id: String, entry: Dictionary) -> String:
	var stock: Dictionary = _readout.get("stock", {})
	var cooldowns: Dictionary = _readout.get("cooldowns", {})
	var cooldown: float = float(cooldowns.get(id, 0.0))
	if str(entry.get("category", "")) == "primary":
		var label: String = _ui("стартовые патроны %d / %d", "starting ammo %d / %d") if _home_mode or id != _selected else _ui("патроны %d / %d", "ammo %d / %d")
		return label % [int(_readout.get("magazine", entry.get("clip", 0))) if id == _selected else int(entry.get("clip", 0)), int(_readout.get("reserve", entry.get("reserve", 0))) if id == _selected else int(entry.get("reserve", 0))]
	var label: String = _ui("запас %d", "stock %d") % int(stock.get(id, entry.get("stock", 0)))
	if cooldown > 0.0: label += _ui(" · готово через %.1f с", " · ready in %.1f s") % cooldown
	return label

func _refresh_layout() -> void:
	if not _built or not is_inside_tree(): return
	var css: Vector2 = _css_size()
	_layout_age = 0.0
	_logical_per_css = get_viewport().get_visible_rect().size / css
	_canvas.scale = _logical_per_css
	_canvas.size = css
	var compact: bool = css.y < 440.0
	var inset: Vector2 = Vector2(8, 8)
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window_position: Vector2i = get_window().position
		if safe.size.x > 0 and safe.size.y > 0:
			inset.x = maxf(8, float(safe.position.x - window_position.x))
			inset.y = maxf(8, float(safe.position.y - window_position.y))
	_overlay.position = inset
	_overlay.size = css - inset * 2
	_grid.columns = 2 if css.x >= 800 and css.y >= 500 else 1
	var next_compact: bool = css.y < 500.0
	if next_compact != _compact_bank:
		_cancel_touches()
		_actions_open = false
	_compact_bank = next_compact
	_more.visible = _compact_bank
	_more.text = _ui("Подтвердить", "Confirm") if _targeting else _ui("Ещё", "More")
	_more.tooltip_text = _hint.text if _targeting else _ui("Арсенал, обычный набор, перезарядка и применение", "Arsenal, classic kit, reload and application")
	_more.disabled = _apply.disabled if _targeting else not _enabled
	_actions_row.visible = not _compact_bank or _actions_open
	_meter.max_lines_visible = 1 if _compact_bank else -1
	_meter.text = _hint.text if _compact_bank and _targeting else _stock_text
	_hint.visible = _targeting and not _compact_bank
	_instruction.visible = not compact
	_title.add_theme_font_size_override("font_size", 18 if compact else 22)
	var width: float = minf(css.x - inset.x * 2, 580.0)
	_bank.position = Vector2((css.x - width) * .5, maxf(inset.y, 76.0 if compact else 82.0))
	_bank.size = Vector2(width, 0)
	for button: Button in _all_buttons: button.custom_minimum_size.x = TARGET_CSS
	_more.custom_minimum_size.x = maxf(TARGET_CSS, ceilf(_more.get_theme_font("font").get_string_size(_more.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0))
	_home_source.custom_minimum_size.x = 128
	var panel_padding: float = _overlay.get_theme_stylebox("panel").get_minimum_size().x
	var margins: float = _catalog_margin.get_theme_constant("margin_left") + _catalog_margin.get_theme_constant("margin_right")
	# Reserve scrollbar width even before AUTO visibility has settled. The
	# resulting wrap width is conservative when a small category needs no scroll.
	var scrollbar: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var gap: float = _grid.get_theme_constant("h_separation") * (_grid.columns - 1)
	var text_width: float = maxf(32.0, floorf((_overlay.size.x - panel_padding - margins - scrollbar - gap) / _grid.columns) - 24.0)
	for id: String in _cards:
		# A label/container minimum at its old or zero width can be thousands of
		# pixels tall. Never feed that transient value back into the card minimum.
		var text_height: float = _wrapped_height(_card_titles[id], text_width) + _wrapped_height(_card_details[id], text_width)
		_cards[id].custom_minimum_size.y = maxf(142.0, ceilf(text_height + 7.0 + 20.0))
	_close_button.text = _ui("Готово", "Done")
	for button: Button in _tabs.values(): button.add_theme_font_size_override("font_size", 12 if css.x < 420 else 14)

func _wrapped_height(label: Label, width: float) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var flags: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var measured: float = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, flags).y
	var lines: int = maxi(1, ceili(measured / maxf(1.0, font.get_height(font_size))))
	return ceilf(measured) + maxf(0.0, float(label.get_theme_constant("line_spacing"))) * (lines - 1) + 2.0

func _process(delta: float) -> void:
	_layout_age += maxf(delta, 0.0)
	_css_poll_age += maxf(delta, 0.0)
	if _enabled and (_layout_age >= .25 or (_uses_css_layout() and _css_poll_age >= .25)): _refresh_layout()

func _css_size() -> Vector2:
	var fallback: Vector2 = Vector2(get_window().size).max(Vector2.ONE)
	if not _uses_css_layout(): return fallback
	# HUD renders may run several times per update. Only a browser read resets
	# this clock, so frequent renders cannot retain a pre-ready canvas forever.
	if _css_poll_age >= .25:
		_css_poll_age = 0.0
		var raw: Variant = _read_css_rect()
		if raw is String:
			var dimensions: Variant = JSON.parse_string(raw)
			if dimensions is Array and dimensions.size() == 2 and float(dimensions[0]) > 0 and float(dimensions[1]) > 0: _css_extent = Vector2(float(dimensions[0]), float(dimensions[1]))
	return _css_extent if _css_extent != Vector2.ZERO else fallback

func _uses_css_layout() -> bool:
	return OS.has_feature("web")

func _read_css_rect() -> Variant:
	return JavaScriptBridge.eval("(() => {const c=document.getElementById('canvas')||document.querySelector('canvas');if(!c)return '';const r=c.getBoundingClientRect();return JSON.stringify([r.width,r.height]);})()")

func _input(event: InputEvent) -> void:
	if not _enabled or not _built: return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		if _catalog_open or _within_bank(event.position): get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if _canceled_touches.has(event.index):
			if not event.pressed: _canceled_touches.erase(event.index)
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			if not _catalog_open and not _within_bank(event.position): return
			if _touches.has(event.index) or _touches.size() >= MAX_TOUCHES:
				get_viewport().set_input_as_handled()
				return
			var button: Button = _button_at(event.position)
			_touches[event.index] = {"button": button, "position": event.position, "start": event.position, "moved": false}
			if button == _apply and not button.disabled: _press_fire()
		elif _touches.has(event.index):
			var claim: Dictionary = _touches[event.index]
			_touches.erase(event.index)
			var button: Button = claim.button
			if button == _apply: _release_fire()
			if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and not event.canceled and not bool(claim.moved) and button.get_global_rect().has_point(event.position): button.pressed.emit()
		else: return
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _canceled_touches.has(event.index):
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var claim: Dictionary = _touches[event.index]
		var movement: Vector2 = event.position - Vector2(claim.position)
		if event.position.distance_to(Vector2(claim.start)) > 6 * _logical_per_css.y: claim.moved = true
		if bool(claim.moved):
			_release_fire()
			if _catalog_open and _scroll.get_global_rect().has_point(event.position): _scroll.scroll_vertical -= roundi(movement.y / _logical_per_css.y)
		claim.position = event.position
		_touches[event.index] = claim
		get_viewport().set_input_as_handled()

func _within_bank(point: Vector2) -> bool:
	return _bank.visible and _bank.get_global_rect().has_point(point)

func _button_at(point: Vector2) -> Button:
	for index: int in range(_all_buttons.size() - 1, -1, -1):
		var button: Button = _all_buttons[index]
		if not button.is_visible_in_tree() or button.disabled or not button.get_global_rect().has_point(point): continue
		if button in _cards.values() and not _scroll.get_global_rect().has_point(point): continue
		return button
	return null

func _button(label: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.name = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(TARGET_CSS, TARGET_CSS)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.clip_text = true
	button.add_theme_font_override("font", THEME.font())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", THEME.WHITE)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]: button.add_theme_stylebox_override(state, _style(Color("28495b") if state == "hover" else Color("1c3346"), THEME.ACCENT if state in ["pressed", "focus"] else Color("536775")))
	button.pressed.connect(callback)
	_all_buttons.append(button)
	return button

func _label(value: String, font_size: int, color: Color = THEME.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", THEME.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _style(background: Color, border: Color = Color("3e5466")) -> StyleBoxFlat:
	var style: StyleBoxFlat = THEME.panel()
	style.bg_color = background
	style.border_color = border
	style.shadow_size = 0
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _ui(ru: String, en: String) -> String:
	return ru if _locale.begins_with("ru") else en
