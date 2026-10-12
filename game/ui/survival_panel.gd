class_name SurvivalPanel
extends Control
## Read-only pause/result content. The HUD owns input capture and session pause.
signal resume_requested
signal restart_requested
signal home_requested

const THEME = preload("res://ui/combat_theme.gd")
const TARGET_CSS: float = 48.0

var _session: Object
var _locale: String = "ru"
var _state: Dictionary = {}
var _built: bool = false
var _canvas: Control
var _margin: MarginContainer
var _title: Label
var _phase: Label
var _timer: Label
var _wave: Label
var _quota: Label
var _supply: Label
var _supply_progress: ProgressBar
var _detail: Label
var _settings: Label
var _scroll: ScrollContainer
var _actions: GridContainer
var _resume: Button
var _restart: Button
var _home: Button
var _refresh_age: float = 0.0
var _rush_record: Dictionary = {}
var _logical_per_css: Vector2 = Vector2.ONE
var _css_extent: Vector2 = Vector2.ZERO
var _css_read_age: float = 1.0


func _ready() -> void:
	_ensure_built()
	resized.connect(_refresh_layout)
	get_viewport().size_changed.connect(_refresh_layout)
	_refresh_layout()
	refresh()


func configure(session: Object, locale: String = "ru") -> void:
	_session = session
	_locale = locale
	_css_read_age = 1.0
	_ensure_built()
	refresh()


func set_menu_open(value: bool) -> void:
	visible = value
	if value:
		_css_read_age = 1.0
		refresh()


func refresh() -> void:
	if is_instance_valid(_session) and _session.has_method("get_survival_state"):
		var value: Variant = _session.call("get_survival_state")
		if value is Dictionary:
			update_state(value)
	else:
		update_state(_state)

func set_rush_record(record: Dictionary) -> void:
	_rush_record = record.duplicate(true)
	refresh()


func update_state(state: Dictionary) -> void:
	_ensure_built()
	_state = state.duplicate(true)
	var phase: String = str(state.get("phase", "preparation"))
	var outcome: String = str(state.get("outcome", ""))
	var finished: bool = bool(state.get("finished", phase == "finished"))
	_title.text = _ui("Выживание", "Survival")
	match outcome:
		"win": _title.text = _ui("Вы выжили", "You survived")
		"defeat": _title.text = _ui("Попытка завершена", "Run ended")
		"interrupted": _title.text = _ui("Арена недоступна", "Arena unavailable")
	_phase.text = _phase_text(phase, outcome, bool(state.get("paused", false)))
	_phase.add_theme_color_override("font_color", THEME.DANGER if outcome in ["defeat", "interrupted"] else THEME.ACCENT)
	var elapsed: float = _number(state, "elapsed_seconds")
	var remaining: float = _number(state, "time_remaining")
	var settings: Dictionary = state.get("settings", {}) if state.get("settings", {}) is Dictionary else {}
	var endless: bool = float(settings.get("duration_seconds", 600.0)) <= 0.0
	if phase == "preparation":
		_timer.text = _ui("До первой волны: ", "First wave in: ") + _clock(_number(state, "preparation_remaining"), true)
	elif phase == "cleanup":
		_timer.text = _ui("Зачистка: осталось %d", "Cleanup: %d remaining") % int(state.get("live", 0))
	elif finished:
		_timer.text = _ui("Время выживания: ", "Survival time: ") + _clock(elapsed)
	else:
		_timer.text = (_ui("Время: ", "Elapsed: ") + _clock(elapsed)) if endless else (_ui("Осталось: ", "Remaining: ") + _clock(remaining, true))
	_wave.text = _ui("Волна %d · Живых %d / %d", "Wave %d · Alive %d / %d") % [int(state.get("wave", 0)), int(state.get("live", 0)), int(state.get("live_limit", 12))]
	_quota.text = _ui("Появилось %d из %d · Пропущено %d", "Appeared %d of %d · Skipped %d") % [int(state.get("wave_spawned", 0)), int(state.get("wave_planned", 0)), int(state.get("wave_skipped", 0))]
	if phase == "active":
		if _number(state, "window_remaining") > 0.0:
			_quota.text += _ui("\nПоявления продолжаются ещё %d с", "\nSpawning continues for %d s") % ceili(_number(state, "window_remaining"))
		else:
			_quota.text += _ui("\nСледующая волна через %d с", "\nNext wave in %d s") % ceili(_number(state, "next_wave_seconds"))
	_supply.text = _supply_text(str(state.get("supply_status", "unavailable")))
	_supply_progress.value = clampf(_number(state, "supply_progress"), 0.0, 1.0)
	_supply_progress.visible = not finished
	_supply.visible = not finished
	_detail.text = _result_detail(state, outcome) if finished else _ui("Волны идут по времени. Живые зомби продолжают атаковать.\nСнабжение: стойте у отмеченного пункта 2 секунды без опасности; одно пополнение за волну.", "Waves follow the timer. Surviving zombies keep attacking.\nSupply: stay at the marked point for 2 safe seconds; one refill per wave.")
	_settings.text = _settings_text(settings)
	if str(settings.get("run_style", "classic")) == "rush":
		var rush: Dictionary = _session.get_rush_state() if is_instance_valid(_session) and _session.has_method("get_rush_state") else {}
		if not finished: _rush_record.clear()
		_title.text = "Blockfield Rush" if not finished else _title.text + " · Rush"
		var levels: Dictionary = rush.get("levels", {})
		_settings.text = _ui("3 минуты + зачистка · Усиления за убийства\nУрон %d/3 · Броня %d/3", "3 minutes + cleanup · Upgrades for kills\nPower %d/3 · Armor %d/3") % [int(levels.get("power", 0)), int(levels.get("armor", 0))]
		_detail.text += _ui("\nОчки: %d", "\nScore: %d") % int(rush.get("score", 0))
		if finished and not _rush_record.is_empty():
			_detail.text += _ui(" · Личный рекорд: %d", " · Personal best: %d") % int(_rush_record.get("best", 0))
			if bool(_rush_record.get("personal_best", false)): _detail.text += _ui("\nНовый рекорд!", "\nNew personal best!")
	_resume.text = _ui("Продолжить", "Resume")
	_resume.visible = not finished
	_resume.disabled = finished
	_restart.text = _ui("Повторить", "Restart")
	_home.text = _ui("Главное меню", "Home")
	_refresh_layout()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_age += delta
	_css_read_age += delta
	if _refresh_age >= 0.1:
		_refresh_age = 0.0
		refresh()


func get_display_state() -> Dictionary:
	_ensure_built()
	return {"title": _title.text, "phase": _phase.text, "timer": _timer.text,
		"wave": _wave.text, "quota": _quota.text, "supply": _supply.text,
		"detail": _detail.text, "settings": _settings.text,
		"resume_visible": _resume.visible, "resume_disabled": _resume.disabled,
		"action_columns": _actions.columns, "minimum_target_css": TARGET_CSS,
		"supply_progress": _supply_progress.value}


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = Control.new()
	_canvas.name = "SurvivalCanvas"
	add_child(_canvas)
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style: StyleBoxFlat = THEME.panel()
	style.bg_color = Color("101f2e")
	style.shadow_size = 0
	panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(panel)
	_margin = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(_margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	_margin.add_child(layout)
	_title = _label("", 24)
	_title.name = "SurvivalTitle"
	layout.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "SurvivalContent"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	_phase = _label("", 17, THEME.ACCENT)
	_timer = _label("", 22)
	_wave = _label("", 17)
	_quota = _label("", 14, THEME.MUTED)
	_supply = _label("", 14, THEME.WARNING)
	_detail = _label("", 14, THEME.MUTED)
	_settings = _label("", 13, THEME.MUTED)
	for label: Label in [_phase, _timer, _wave, _quota, _supply]:
		content.add_child(label)
	_supply_progress = ProgressBar.new()
	_supply_progress.name = "SupplyProgress"
	_supply_progress.max_value = 1.0
	_supply_progress.show_percentage = false
	_supply_progress.custom_minimum_size.y = 8
	content.add_child(_supply_progress)
	content.add_child(_detail)
	content.add_child(_settings)
	_actions = GridContainer.new()
	_actions.name = "SurvivalActions"
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	layout.add_child(_actions)
	_resume = _button("SurvivalResume", func() -> void: resume_requested.emit(), true)
	_restart = _button("SurvivalRestart", func() -> void: restart_requested.emit())
	_home = _button("SurvivalHome", func() -> void: home_requested.emit())
	for button: Button in [_resume, _restart, _home]:
		_actions.add_child(button)


func _refresh_layout() -> void:
	if not is_inside_tree() or not _built:
		return
	var css: Vector2 = _css_size()
	_logical_per_css = get_viewport().get_visible_rect().size / css
	_canvas.scale = _logical_per_css
	_canvas.size = size / _logical_per_css.max(Vector2.ONE * 0.0001)
	_actions.columns = 1 if _canvas.size.x < 520.0 else (2 if not _resume.visible else 3)
	var compact: bool = _canvas.size.y < 420.0
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 10 if compact else 16)
	_title.add_theme_font_size_override("font_size", 21 if compact else 24)
	for button: Button in [_resume, _restart, _home]:
		button.custom_minimum_size = Vector2(TARGET_CSS, TARGET_CSS)


func _css_size() -> Vector2:
	var fallback: Vector2 = Vector2(get_window().size).max(Vector2.ONE)
	if not OS.has_feature("web"):
		return fallback
	if _css_read_age >= 0.25 or _css_extent == Vector2.ZERO:
		_css_read_age = 0.0
		var raw: Variant = JavaScriptBridge.eval("(() => {const c=document.getElementById('canvas')||document.querySelector('canvas');if(!c)return '';const r=c.getBoundingClientRect();return JSON.stringify([r.width,r.height]);})()")
		if raw is String:
			var dimensions: Variant = JSON.parse_string(raw)
			if dimensions is Array and dimensions.size() == 2 and float(dimensions[0]) > 0 and float(dimensions[1]) > 0:
				_css_extent = Vector2(float(dimensions[0]), float(dimensions[1]))
	return _css_extent if _css_extent != Vector2.ZERO else fallback


func _phase_text(phase: String, outcome: String, paused: bool) -> String:
	if phase == "finished":
		match outcome:
			"win": return _ui("Все зомби уничтожены", "All zombies cleared")
			"defeat": return _ui("Игрок погиб", "Player defeated")
			_: return _ui("Забег прерван · результат не засчитан", "Run interrupted · no result recorded")
	if paused:
		return _ui("Пауза · время остановлено", "Paused · timer stopped")
	match phase:
		"preparation": return _ui("Подготовка · стройте укрытие", "Preparation · build cover")
		"cleanup": return _ui("Финальная зачистка · новых волн нет", "Final cleanup · no new waves")
		_: return _ui("Выживание · волны пересекаются", "Survival · waves overlap")


func _supply_text(status: String) -> String:
	match status:
		"ready": return _ui("Снабжение готово · подойдите к пункту", "Supply ready · approach the point")
		"progress": return _ui("Пополнение · оставайтесь у пункта", "Refilling · stay at the point")
		"unsafe": return _ui("Снабжение остановлено · рядом опасность", "Supply blocked · danger nearby")
		"used": return _ui("Снабжение получено в этой волне", "Supply used for this wave")
		_: return _ui("Снабжение пока закрыто", "Supply currently unavailable")


func _result_detail(state: Dictionary, outcome: String) -> String:
	var message: String = _ui("Убийства: %d · Попаданий в голову: %d\nПолученный урон: %d · Последняя волна: %d", "Kills: %d · Head hits: %d\nDamage taken: %d · Last wave: %d") % [int(state.get("kills", 0)), int(state.get("headshots", 0)), int(state.get("damage_taken", 0)), int(state.get("wave", 0))]
	if outcome == "interrupted":
		message = (_ui("Нет доступного места для зомби. Повторите забег.", "No available zombie spawn. Restart the run.") if str(state.get("finish_reason", "")) == "spawn_unavailable" else _ui("Зомби не могут добраться до игрока. Повторите забег.", "Zombies cannot reach the player. Restart the run.")) + "\n" + message
	return message


func _settings_text(settings: Dictionary) -> String:
	if settings.is_empty():
		return ""
	var duration: float = float(settings.get("duration_seconds", 600.0))
	var duration_text: String = _ui("Бесконечно", "Endless") if duration <= 0 else _clock(duration)
	var growth_mode: String = str(settings.get("growth_mode", "linear"))
	var growth: String = _ui("Постоянная квота", "Constant quota") if growth_mode == "constant" else (_ui("Рост ступенями", "Step growth") if growth_mode == "step" else _ui("Плавный рост", "Linear growth"))
	var gain: float = 0.0 if growth_mode == "constant" else float(settings.get("growth_per_minute", 1.0))
	var text: String = _ui("Длительность %s · Интервал %d с\nДо %d зомби · %s %.1f / мин", "Duration %s · Interval %d s\nUp to %d zombies · %s %.1f / min") % [duration_text, int(settings.get("wave_interval_seconds", 60)), int(settings.get("zombies_per_wave", 6)), growth, gain]
	return text + (_ui("\nУрон игроку %d · Урон блокам %d", "\nPlayer damage %d · Block damage %d") % [int(settings.get("zombie_damage", 20)), int(settings.get("zombie_block_damage", 40))])


func _ui(ru: String, en: String) -> String:
	return ru if _locale.begins_with("ru") else en


static func _number(state: Dictionary, key: String) -> float:
	var value: float = float(state.get(key, 0.0))
	return maxf(value, 0.0) if is_finite(value) else 0.0


static func _clock(seconds: float, round_up: bool = false) -> String:
	var value: int = ceili(seconds) if round_up else floori(seconds)
	value = maxi(value, 0)
	return "%02d:%02d" % [floori(float(value) / 60.0), value % 60]


func _label(text_value: String, font_size: int, color: Color = THEME.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", THEME.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(node_name: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(TARGET_CSS, TARGET_CSS)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", THEME.font())
	button.add_theme_font_size_override("font_size", 15)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBoxFlat = THEME.panel()
		style.shadow_size = 0
		style.set_corner_radius_all(12)
		style.bg_color = THEME.ACCENT if primary else Color("1c3346")
		if state == "hover": style.bg_color = Color("9ceddf") if primary else Color("28495b")
		if state == "pressed": style.bg_color = Color("53bcaf") if primary else Color("163c40")
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = THEME.WHITE
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("07121e") if primary else THEME.WHITE)
	button.pressed.connect(callback)
	return button
