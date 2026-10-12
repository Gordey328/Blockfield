class_name RushUpgradePanel
extends Control
## Displays authoritative offers. HUD owns pause, capture and upgrade admission.
signal upgrade_chosen(id: String)

const THEME = preload("res://ui/combat_theme.gd")
const TARGET_CSS: float = 56.0

var _locale: String = "ru"
var _state: Dictionary = {}
var _built: bool = false
var _submitted: bool = false
var _canvas: Control
var _margin: MarginContainer
var _title: Label
var _hint: Label
var _stats: Label
var _build: Label
var _scroll: ScrollContainer
var _choices: GridContainer
var _buttons: Array[Button] = []
var _card_content: Array[VBoxContainer] = []
var _choice_titles: Array[Label] = []
var _choice_details: Array[Label] = []
var _choice_ids: Array[String] = ["", "", ""]
var _logical_per_css: Vector2 = Vector2.ONE
var _css_extent: Vector2 = Vector2.ZERO
var _css_read_age: float = 1.0


func _ready() -> void:
	_ensure_built()
	resized.connect(_refresh_layout)
	get_viewport().size_changed.connect(_refresh_layout)
	_refresh_layout()


func configure(locale: String = "ru") -> void:
	_ensure_built()
	if _locale == locale: return
	_locale = locale
	_render_state()


func refresh(state: Dictionary) -> void:
	_ensure_built()
	_submitted = false
	visible = bool(state.get("enabled", false)) and bool(state.get("pending", false))
	if _state == state:
		_refresh_buttons()
		return
	_state = state.duplicate(true)
	_render_state()


func _render_state() -> void:
	_title.text = _ui("Rush · Выбери усиление", "Rush · Choose an upgrade")
	_hint.text = _ui("Одно усиление за выбор. Продолжай забег с новым преимуществом.", "Choose one upgrade, then continue your run with a new advantage.")
	_stats.text = _ui("Убийства %d · Счёт %d · Следующий выбор: %d убийств", "Kills %d · Score %d · Next choice: %d kills") % [int(_state.get("kills", 0)), int(_state.get("score", 0)), int(_state.get("next_kills", 0))]
	var raw_levels: Variant = _state.get("levels", {})
	var levels: Dictionary = raw_levels if raw_levels is Dictionary else {}
	_build.text = _ui("Твой набор: Мощность %d · Броня %d · Полевой набор %d", "Your build: Firepower %d · Armor %d · Field kit %d") % [int(levels.get("power", 0)), int(levels.get("armor", 0)), int(levels.get("field_kit", 0))]
	var raw_choices: Variant = _state.get("choices", [])
	var choices: Array = raw_choices if raw_choices is Array else []
	for index: int in 3:
		var raw_choice: Variant = choices[index] if index < choices.size() else {}
		var choice: Dictionary = raw_choice if raw_choice is Dictionary else {}
		_choice_ids[index] = str(choice.get("id", ""))
		_choice_titles[index].text = _localized(choice, "title")
		_choice_details[index].text = _localized(choice, "description")
		_buttons[index].visible = not _choice_ids[index].is_empty()
	_refresh_buttons()
	_refresh_layout()


func _refresh_buttons() -> void:
	var allowed: bool = bool(_state.get("enabled", false)) and bool(_state.get("pending", false)) and not _submitted
	for index: int in 3:
		_buttons[index].disabled = not allowed or _choice_ids[index].is_empty()


func _choose(index: int) -> void:
	if index < 0 or index >= _buttons.size() or _buttons[index].disabled or not is_visible_in_tree(): return
	var id: String = _choice_ids[index]
	if id.is_empty(): return
	_submitted = true
	_refresh_buttons()
	upgrade_chosen.emit(id)


func _ensure_built() -> void:
	if _built: return
	_built = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = Control.new()
	_canvas.name = "RushCanvas"
	add_child(_canvas)
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop: StyleBoxFlat = THEME.panel()
	backdrop.bg_color = Color("101f2e")
	backdrop.shadow_size = 0
	panel.add_theme_stylebox_override("panel", backdrop)
	_canvas.add_child(panel)
	_margin = MarginContainer.new()
	panel.add_child(_margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_margin.add_child(layout)
	_title = _label("", 24, THEME.ACCENT)
	_title.name = "RushUpgradeTitle"
	layout.add_child(_title)
	_hint = _label("", 14, THEME.MUTED)
	layout.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.name = "RushUpgradeContent"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_scroll.add_child(content)
	_stats = _label("", 15)
	content.add_child(_stats)
	_build = _label("", 14, THEME.WARNING)
	content.add_child(_build)
	_choices = GridContainer.new()
	_choices.name = "RushUpgradeChoices"
	_choices.add_theme_constant_override("h_separation", 12)
	_choices.add_theme_constant_override("v_separation", 12)
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_choices)
	for index: int in 3:
		var button: Button = _choice_button(index)
		_choices.add_child(button)
		_buttons.append(button)
	_render_state()


func _choice_button(index: int) -> Button:
	var button: Button = Button.new()
	button.name = "RushChoice%d" % index
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(TARGET_CSS, 108)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBoxFlat = THEME.panel()
		style.shadow_size = 0
		style.set_corner_radius_all(12)
		style.bg_color = Color("1c3346")
		style.border_color = THEME.ACCENT
		if state == "hover": style.bg_color = Color("28495b")
		if state == "pressed": style.bg_color = Color("163c40")
		if state == "disabled": style.border_color = THEME.MUTED
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = THEME.WHITE
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	button.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	content.resized.connect(_refresh_layout)
	margin.add_child(content)
	var title: Label = _label("", 20, THEME.ACCENT)
	content.add_child(title)
	var detail: Label = _label("", 14)
	content.add_child(detail)
	_card_content.append(content)
	_choice_titles.append(title)
	_choice_details.append(detail)
	button.pressed.connect(_choose.bind(index))
	return button


func _refresh_layout() -> void:
	if not _built or not is_inside_tree(): return
	var css: Vector2 = _css_size()
	_logical_per_css = get_viewport().get_visible_rect().size / css
	_canvas.scale = _logical_per_css
	_canvas.size = size / _logical_per_css.max(Vector2.ONE * 0.0001)
	_choices.columns = 3 if _canvas.size.x >= 800.0 and _canvas.size.y >= 500.0 else 1
	var compact: bool = _canvas.size.y < 420.0
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 12 if compact else 20)
	_title.add_theme_font_size_override("font_size", 20 if compact else 24)
	_hint.visible = not compact
	for index: int in _buttons.size():
		_buttons[index].custom_minimum_size = Vector2(TARGET_CSS, maxf(108.0, _card_content[index].get_combined_minimum_size().y + 28.0))


func _process(delta: float) -> void:
	_css_read_age += delta
	if is_visible_in_tree() and OS.has_feature("web") and _css_read_age >= 0.25:
		_refresh_layout()


func _css_size() -> Vector2:
	var fallback: Vector2 = Vector2(get_window().size).max(Vector2.ONE)
	if not OS.has_feature("web"): return fallback
	if _css_read_age >= 0.25 or _css_extent == Vector2.ZERO:
		_css_read_age = 0.0
		var raw: Variant = JavaScriptBridge.eval("(() => {const c=document.getElementById('canvas')||document.querySelector('canvas');if(!c)return '';const r=c.getBoundingClientRect();return JSON.stringify([r.width,r.height]);})()")
		if raw is String:
			var dimensions: Variant = JSON.parse_string(raw)
			if dimensions is Array and dimensions.size() == 2 and float(dimensions[0]) > 0 and float(dimensions[1]) > 0:
				_css_extent = Vector2(float(dimensions[0]), float(dimensions[1]))
	return _css_extent if _css_extent != Vector2.ZERO else fallback


func get_display_state() -> Dictionary:
	_ensure_built()
	var titles: Array[String] = []
	var descriptions: Array[String] = []
	for index: int in 3:
		titles.append(_choice_titles[index].text)
		descriptions.append(_choice_details[index].text)
	return {"visible": visible, "title": _title.text, "stats": _stats.text,
		"build": _build.text, "choice_ids": _choice_ids.duplicate(),
		"titles": titles, "descriptions": descriptions,
		"columns": _choices.columns, "minimum_target_css": TARGET_CSS}


func _label(value: String, point_size: int, color: Color = THEME.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", THEME.font())
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", color)
	return label


func _localized(value: Dictionary, key: String) -> String:
	return str(value.get(key + ("_ru" if _locale.begins_with("ru") else "_en"), value.get(key + "_en", "")))


func _ui(ru: String, en: String) -> String:
	return ru if _locale.begins_with("ru") else en
