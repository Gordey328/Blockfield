extends CanvasLayer
## Foreground launch lifecycle. It cannot author map or player state.
signal home_requested
signal retry_requested

var _root: Control
var _panel: PanelContainer
var _caption: Label
var _details: Label
var _retry: Button
var _home: Button

func _ready() -> void:
	layer = 40
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var background: ColorRect = ColorRect.new()
	background.color = Color("0b1421")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", CombatTheme.panel())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_root.add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	_caption = Label.new()
	_caption.add_theme_font_override("font", CombatTheme.font())
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_color_override("font_color", CombatTheme.WHITE)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_caption)
	_details = Label.new()
	_details.add_theme_font_override("font", CombatTheme.font())
	_details.add_theme_font_size_override("font_size", 18)
	_details.add_theme_color_override("font_color", CombatTheme.MUTED)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_details)
	_retry = _button("RetryLaunch")
	_retry.pressed.connect(func(): retry_requested.emit())
	column.add_child(_retry)
	_home = _button("LaunchHome")
	_home.pressed.connect(func(): home_requested.emit())
	column.add_child(_home)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _button(identifier: String) -> Button:
	var button: Button = Button.new()
	button.name = identifier
	button.add_theme_font_override("font", CombatTheme.font())
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", CombatTheme.ACCENT)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, CombatTheme.panel())
	return button

func _layout() -> void:
	if not is_inside_tree(): return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pixel_size: Vector2 = Vector2(get_window().size)
	if OS.has_feature("web"):
		var dimensions: Variant = JavaScriptBridge.eval("JSON.stringify([document.getElementById('canvas').clientWidth,document.getElementById('canvas').clientHeight])")
		var parsed: Variant = JSON.parse_string(str(dimensions))
		if parsed is Array and parsed.size() == 2:
			pixel_size = Vector2(float(parsed[0]), float(parsed[1]))
	var factor: float = maxf(1.0, viewport_size.y / maxf(1.0, pixel_size.y))
	var width: float = minf(620.0, viewport_size.x - 32.0 * factor)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -160.0 * factor
	_panel.offset_bottom = 160.0 * factor
	_retry.custom_minimum_size.y = 56.0 * factor
	_home.custom_minimum_size.y = 56.0 * factor

func show_progress(title: String, details: String, russian: bool) -> void:
	_caption.text = title
	_details.text = details
	_retry.hide()
	_home.text = "В главное меню" if russian else "Main menu"

func show_error(message: String, can_retry: bool, russian: bool) -> void:
	_caption.text = "Не удалось начать игру" if russian else "Unable to start game"
	_details.text = message
	_retry.text = "Повторить" if russian else "Retry"
	_retry.visible = can_retry
	_home.text = "В главное меню" if russian else "Main menu"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		home_requested.emit()
