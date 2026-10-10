class_name BlockfieldMobileControls
extends Control
## Input presentation only. Main/HUD owns the InputEventAction bridge; Player
## retains every original tool, ADS, spectator and network-intention rule.
signal action_changed(action: String, pressed: bool)
signal movement_changed(axis: Vector2)
signal look_moved(relative: Vector2)
signal menu_requested

const STICK_SIZE := 160.0
const STICK_RADIUS := 62.0
const STICK_DEADZONE := 0.12
const HUD_BOTTOM_RESERVE := 52.0
const MARGIN := 12.0
const GAP := 8.0
const MIN_BUTTON_SIZE := 60.0
const MAX_BUTTON_SIZE := 72.0
const MAX_POINTERS := 32
const NO_POINTER := -2
const MOUSE_POINTER := -1
const TOP_ACTIONS: Array[String] = ["tool_spade", "tool_block", "tool_weapon", "tool_grenade", "map", "view_toggle", "menu"]
const PLAY_ACTIONS: Array[String] = ["primary", "secondary", "reload", "jump", "crouch", "sprint"]

enum PointerKind { MOVE, LOOK, ACTION, BLOCKED }

class PointerOwner:

	var kind: PointerKind = PointerKind.BLOCKED
	var action: String = ""
	var holding: bool = false

var movement_axis: Vector2 = Vector2.ZERO
var _player: BlockfieldPlayer
var _hud: LabHUD
var _enabled: bool = false
var _active: bool = false
var _regions: Dictionary[String, Rect2] = {}
var _owners: Dictionary[int, PointerOwner] = {}
var _action_counts: Dictionary[String, int] = {}
var _move_owner: int = NO_POINTER
var _look_owner: int = NO_POINTER
var _stick_delta: Vector2 = Vector2.ZERO
var _layout_size: Vector2 = Vector2(-1, -1)
var _button_size: float = MIN_BUTTON_SIZE
var _locale: String = ""
var _normal_style: StyleBoxFlat
var _held_style: StyleBoxFlat
var _font: Font

func setup(player: BlockfieldPlayer, hud: LabHUD) -> void:
	release_all()
	_player = player
	_hud = hud
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Real mouse fallback is handled in _input only over owned controls.
	# The full-screen transparent Control must not block menu or desktop input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_ensure_layout()
	_sync_active()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(_on_resized)
	_normal_style = _make_style(Color(0.035, 0.065, 0.085, 0.42), Color(0.72, 0.86, 0.92, 0.42))
	_held_style = _make_style(Color(0.19, 0.43, 0.56, 0.66), Color(0.86, 0.96, 1.0, 0.92))
	_font = get_theme_default_font()
	_ensure_layout()
	_sync_active()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		release_all()
	_sync_active()

func release_all() -> void:
	# Clear ownership before emitting: menu/focus callbacks may reenter this.
	var actions: Array[String] = []
	for action: String in _action_counts:
		if _action_counts[action] > 0:
			actions.append(action)
	_owners.clear()
	_action_counts.clear()
	_move_owner = NO_POINTER
	_look_owner = NO_POINTER
	_stick_delta = Vector2.ZERO
	_set_movement(Vector2.ZERO)
	for action: String in actions:
		action_changed.emit(action, false)
	queue_redraw()

func get_hit_regions() -> Dictionary:
	_ensure_layout()
	return _regions.duplicate()

## These two public methods use local logical pixels, exactly as _input does
## after converting viewport coordinates. Negative touch indices are invalid.
func handle_touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> bool:
	if index < 0 or not position.is_finite():
		return false
	return _handle_pointer(index, position, pressed, canceled, true)

func handle_drag(index: int, position: Vector2, relative: Vector2) -> bool:
	if index < 0 or not position.is_finite() or not relative.is_finite():
		return false
	return _drag_pointer(index, position, relative)

func _input(event: InputEvent) -> void:
	_sync_active()
	if not _active:
		return
	var handled: bool = false
	if event is InputEventScreenTouch:
		handled = handle_touch(event.index, _local_position(event.position), event.pressed, event.canceled)
	elif event is InputEventScreenDrag:
		var position: Vector2 = _local_position(event.position)
		var relative: Vector2 = position - _local_position(event.position - event.relative)
		handled = handle_drag(event.index, position, relative)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# Touch's synthetic mouse must never fire/rotate through a second path.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			handled = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			handled = _handle_pointer(MOUSE_POINTER, _local_position(event.position), event.pressed, false, true)
		elif event is InputEventMouseMotion and _owners.has(MOUSE_POINTER):
			var position: Vector2 = _local_position(event.position)
			var relative: Vector2 = position - _local_position(event.position - event.relative)
			handled = _drag_pointer(MOUSE_POINTER, position, relative)
	if handled:
		get_viewport().set_input_as_handled()

func _handle_pointer(index: int, position: Vector2, pressed: bool, canceled: bool, allow_look: bool) -> bool:
	if not position.is_finite():
		return false
	_ensure_layout()
	_sync_active()
	if not _active:
		return false
	if canceled or not pressed:
		return _release_pointer(index)
	if _owners.has(index):
		return true # Duplicate down cannot change a pointer's original claim.
	if _owners.size() >= MAX_POINTERS:
		return false
	var region: String = _hit_region(position, allow_look)
	if region.is_empty():
		return false
	if region == "menu":
		release_all()
		menu_requested.emit()
		return true
	var owner := PointerOwner.new()
	_owners[index] = owner
	match region:
		"move":
			if _move_owner == NO_POINTER:
				owner.kind = PointerKind.MOVE
				_move_owner = index
				_update_stick(position)
		"look":
			if _look_owner == NO_POINTER:
				owner.kind = PointerKind.LOOK
				_look_owner = index
		_:
			owner.kind = PointerKind.ACTION
			owner.action = region
			_set_owner_holding(owner, true)
	queue_redraw()
	return true

func _drag_pointer(index: int, position: Vector2, relative: Vector2) -> bool:
	if not position.is_finite() or not relative.is_finite():
		return false
	_ensure_layout()
	_sync_active()
	if not _active or not _owners.has(index):
		return false
	var owner: PointerOwner = _owners[index]
	match owner.kind:
		PointerKind.MOVE:
			_update_stick(position)
		PointerKind.LOOK:
			if relative != Vector2.ZERO:
				look_moved.emit(relative)
		PointerKind.ACTION:
			# An action can release outside and repress inside its original box,
			# but it never becomes another action, a stick, or a look pointer.
			_set_owner_holding(owner, _regions[owner.action].has_point(position))
		_:
			pass
	queue_redraw()
	return true

func _release_pointer(index: int) -> bool:
	if not _owners.has(index):
		return false
	var owner: PointerOwner = _owners[index]
	_owners.erase(index)
	match owner.kind:
		PointerKind.MOVE:
			_move_owner = NO_POINTER
			_stick_delta = Vector2.ZERO
			_set_movement(Vector2.ZERO)
		PointerKind.LOOK:
			_look_owner = NO_POINTER
		PointerKind.ACTION:
			_set_owner_holding(owner, false)
		_:
			pass
	queue_redraw()
	return true

func _set_owner_holding(owner: PointerOwner, holding: bool) -> void:
	if owner.holding == holding:
		return
	owner.holding = holding
	var previous: int = _action_counts.get(owner.action, 0)
	var count: int = maxi(0, previous + (1 if holding else -1))
	if count == 0:
		_action_counts.erase(owner.action)
	else:
		_action_counts[owner.action] = count
	if previous == 0 and count > 0:
		action_changed.emit(owner.action, true)
	elif previous > 0 and count == 0:
		action_changed.emit(owner.action, false)

func _update_stick(position: Vector2) -> void:
	_stick_delta = (position - _regions["move"].get_center()).limit_length(STICK_RADIUS)
	var normalized: Vector2 = _stick_delta / STICK_RADIUS
	var strength: float = normalized.length()
	var axis: Vector2 = Vector2.ZERO
	if strength > STICK_DEADZONE:
		axis = normalized / strength * ((strength - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))
	_set_movement(axis)

func _set_movement(axis: Vector2) -> void:
	if movement_axis == axis:
		return
	movement_axis = axis
	movement_changed.emit(axis)
	queue_redraw()

func _hit_region(position: Vector2, allow_look: bool) -> String:
	for action: String in TOP_ACTIONS:
		if _regions.has(action) and _regions[action].has_point(position):
			return action
	for action: String in PLAY_ACTIONS:
		if _regions.has(action) and _regions[action].has_point(position):
			return action
	if _regions.has("move") and _regions["move"].has_point(position):
		return "move"
	if allow_look and _regions.has("look") and _regions["look"].has_point(position):
		return "look"
	return ""

func _local_position(position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * position

func _process(_delta: float) -> void:
	_ensure_layout()
	_sync_active()
	var locale: String = TranslationServer.get_locale()
	if locale != _locale:
		_locale = locale
		queue_redraw()

func _sync_active() -> void:
	var active: bool = _enabled
	if is_instance_valid(_player):
		active = active and _player.controls_enabled
	if is_instance_valid(_hud):
		active = active and not _hud.is_menu_open() and not _hud.is_chat_open()
	if _active and not active:
		release_all()
	_active = active
	visible = active

func _on_resized() -> void:
	_ensure_layout()

func _ensure_layout() -> void:
	if _layout_size == size:
		return
	release_all()
	_layout_size = size
	_regions.clear()
	if size.x < 440.0 or size.y < 320.0:
		return
	var two_rows: bool = size.x < MIN_BUTTON_SIZE * 7.0 + GAP * 6.0 + MARGIN * 2.0
	var columns: int = 4 if two_rows else 7
	var width_limit: float = (size.x - MARGIN * 2.0 - GAP * (columns - 1)) / columns
	_button_size = clampf(minf(size.y * 0.13, width_limit), MIN_BUTTON_SIZE, MAX_BUTTON_SIZE)
	var top_bottom: float = MARGIN + _button_size
	if two_rows:
		_layout_row(TOP_ACTIONS.slice(0, 4), MARGIN)
		_layout_row(TOP_ACTIONS.slice(4), MARGIN + _button_size + GAP)
		top_bottom += _button_size + GAP
	else:
		_layout_row(TOP_ACTIONS, MARGIN)
	_regions["move"] = Rect2(Vector2(MARGIN, size.y - HUD_BOTTOM_RESERVE - STICK_SIZE), Vector2.ONE * STICK_SIZE)
	var grid_width: float = _button_size * 3.0 + GAP * 2.0
	var grid_origin := Vector2(size.x - MARGIN - grid_width, size.y - HUD_BOTTOM_RESERVE - _button_size * 2.0 - GAP)
	for index: int in range(PLAY_ACTIONS.size()):
		var offset := Vector2(index % 3, floori(float(index) / 3.0)) * (_button_size + GAP)
		_regions[PLAY_ACTIONS[index]] = Rect2(grid_origin + offset, Vector2.ONE * _button_size)
	var look_top: float = top_bottom + GAP
	var look_bottom: float = minf(grid_origin.y, _regions["move"].position.y) - GAP
	_regions["look"] = Rect2(Vector2(size.x * 0.5, look_top), Vector2(size.x * 0.5 - MARGIN, maxf(0, look_bottom - look_top)))
	queue_redraw()

func _layout_row(actions: Array[String], y: float) -> void:
	var width: float = actions.size() * _button_size + (actions.size() - 1) * GAP
	var x: float = (size.x - width) * 0.5
	for action: String in actions:
		_regions[action] = Rect2(Vector2(x, y), Vector2.ONE * _button_size)
		x += _button_size + GAP

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		release_all()

func _exit_tree() -> void:
	release_all()
	_player = null
	_hud = null
	_font = null

func _make_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(13)
	return style

func _draw() -> void:
	if not _active or _regions.is_empty() or _normal_style == null:
		return
	if _font == null:
		_font = get_theme_default_font()
	for action: String in TOP_ACTIONS + PLAY_ACTIONS:
		var rect: Rect2 = _regions[action]
		var held: bool = _action_counts.get(action, 0) > 0
		draw_style_box(_held_style if held else _normal_style, rect)
		var color := Color(1.0, 0.79, 0.58, 0.95) if action == "primary" else Color(0.91, 0.96, 1.0, 0.94)
		_draw_label(rect, _label(action), 15, color)
	var center: Vector2 = _regions["move"].get_center()
	draw_circle(center, STICK_RADIUS, Color(0.035, 0.065, 0.085, 0.28))
	draw_arc(center, STICK_RADIUS, 0, TAU, 64, Color(0.8, 0.91, 1.0, 0.46), 2.0, true)
	draw_circle(center + _stick_delta, 24.0, Color(0.75, 0.9, 1.0, 0.40 if _move_owner == NO_POINTER else 0.72))
	_draw_label(Rect2(Vector2(center.x - 75, center.y + STICK_RADIUS - 4), Vector2(150, 20)), _ui("Движение", "Move"), 12, Color(0.91, 0.96, 1.0, 0.58))
	var look: Rect2 = _regions["look"]
	_draw_label(Rect2(Vector2(look.position.x, look.end.y - 24), Vector2(look.size.x, 24)), _ui("Проведи для поворота", "Drag to look"), 13, Color(0.91, 0.96, 1.0, 0.34))

func _draw_label(rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var lines: PackedStringArray = text.split("\n")
	var height: float = _font.get_height(font_size)
	var y: float = rect.get_center().y - height * lines.size() * 0.5 + _font.get_ascent(font_size)
	for line: String in lines:
		draw_string(_font, Vector2(rect.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)
		y += height

func _label(action: String) -> String:
	match action:
		"primary": return _ui("Огонь", "Fire")
		"secondary": return _ui("Прицел\nALT", "Aim\nALT")
		"reload": return _ui("Перез.", "Reload")
		"jump": return _ui("Прыжок", "Jump")
		"crouch": return _ui("Присед", "Crouch")
		"sprint": return _ui("Бег", "Sprint")
		"tool_spade": return _ui("1\nЛопата", "1\nSpade")
		"tool_block": return _ui("2\nБлок", "2\nBlock")
		"tool_weapon": return _ui("3\nОружие", "3\nGun")
		"tool_grenade": return _ui("4\nГраната", "4\nGrenade")
		"map": return _ui("Карта", "Map")
		"view_toggle": return _ui("Вид", "View")
		"menu": return _ui("Меню", "Menu")
		_: return action

func _ui(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en
