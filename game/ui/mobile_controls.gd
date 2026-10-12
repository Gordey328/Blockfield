class_name BlockfieldMobileControls
extends Control
## Input presentation only. Main/HUD owns the InputEventAction bridge; Player
## retains every original tool, ADS, spectator and local match rule.
signal action_changed(action: String, pressed: bool)
signal movement_changed(axis: Vector2)
signal look_moved(relative: Vector2)
signal look_canceled
signal menu_requested

const STICK_SIZE := 160.0
const STICK_RADIUS := 62.0
const STICK_DEADZONE := 0.12
const HUD_BOTTOM_RESERVE := 52.0
const MARGIN := 12.0
const GAP := 8.0
const MIN_BUTTON_SIZE := 60.0
const MAX_BUTTON_SIZE := 72.0
const MIN_CSS_BUTTON_SIZE := 56.0
const MIN_CSS_LABEL_SIZE := 12.0
const MAX_POINTERS := 32
const NO_POINTER := -2
const MOUSE_POINTER := -1
const MOVE_WIDTH_RATIO := 0.4
const TOP_ACTIONS: Array[String] = ["tool_spade", "tool_block", "tool_weapon", "tool_grenade", "map", "view_toggle", "menu"]
const PLAY_ACTIONS: Array[String] = ["primary", "secondary", "reload", "jump", "crouch", "sprint"]
const TOOL_ACTIONS: Array[String] = ["tool_spade", "tool_block", "tool_weapon", "tool_grenade"]
const UTILITY_ACTIONS: Array[String] = ["map", "view_toggle", "menu"]

enum PointerKind { MOVE, LOOK, ACTION, BLOCKED, ACTION_LOOK }

class PointerOwner:

	var kind: PointerKind = PointerKind.BLOCKED
	var action: String = ""
	var holding: bool = false
	var previous_position: Vector2 = Vector2.ZERO

var movement_axis: Vector2 = Vector2.ZERO
var _floating_stick: bool = true
var _control_scale: float = 1.0
var _fire_drag_look: bool = true
var _left_handed: bool = false
var floating_stick: bool:
	get: return _floating_stick
	set(value): set_touch_preferences(value, _control_scale, _fire_drag_look, _left_handed)
var control_scale: float:
	get: return _control_scale
	set(value): set_touch_preferences(_floating_stick, value, _fire_drag_look, _left_handed)
var fire_drag_look: bool:
	get: return _fire_drag_look
	set(value): set_touch_preferences(_floating_stick, _control_scale, value, _left_handed)
var left_handed: bool:
	get: return _left_handed
	set(value): set_touch_preferences(_floating_stick, _control_scale, _fire_drag_look, value)
var _player: BlockfieldPlayer
var _hud: LabHUD
var _enabled: bool = false
var _active: bool = false
var _regions: Dictionary[String, Rect2] = {}
var _look_hint_rect: Rect2 = Rect2()
var _owners: Dictionary[int, PointerOwner] = {}
var _action_counts: Dictionary[String, int] = {}
var _move_owner: int = NO_POINTER
var _look_owner: int = NO_POINTER
var _stick_delta: Vector2 = Vector2.ZERO
var _stick_center: Vector2 = Vector2.ZERO
var _resting_stick_center: Vector2 = Vector2.ZERO
var _move_grab_offset: Vector2 = Vector2.ZERO
var _stick_extent: float = STICK_SIZE
var _stick_radius: float = STICK_RADIUS
var _mouse_preview_enabled: bool = true
var _layout_size: Vector2 = Vector2(-1, -1)
var _button_size: float = MIN_BUTTON_SIZE
var _button_font_size: int = 15
var _hint_font_size: int = 13
var _locale: String = ""
var _normal_style: StyleBoxFlat
var _held_style: StyleBoxFlat
var _font: Font
var _displayed_tool: int = -1
var _layout_height: float = 0.0
var _css_unit: float = 1.0

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
	get_viewport().size_changed.connect(_on_canvas_resized)
	_normal_style = _make_style(Color(0.035, 0.055, 0.075, 0.38), Color(0.88, 0.94, 1.0, 0.28))
	_held_style = _make_style(Color(0.08, 0.24, 0.30, 0.64), Color(0.45, 0.88, 1.0, 0.90))
	_font = CombatTheme.font()
	_ensure_layout()
	_sync_active()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		release_all()
	_sync_active()

func set_touch_preferences(floating: bool, scale: float, fire_look: bool, left: bool = false) -> void:
	# A new layout/gesture policy cannot inherit a held pointer's old baseline.
	release_all()
	_floating_stick = floating
	if is_finite(scale): _control_scale = clampf(scale, 0.8, 1.4)
	_fire_drag_look = fire_look
	_left_handed = left
	_layout_size = Vector2(-1, -1)
	_ensure_layout()

func set_mouse_preview_enabled(enabled: bool) -> void:
	_mouse_preview_enabled = enabled
	if not enabled: _release_pointer(MOUSE_POINTER, true)

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
	_move_grab_offset = Vector2.ZERO
	_stick_center = _resting_stick_center
	_set_movement(Vector2.ZERO)
	# Previously emitted look may still be queued until the player's next frame.
	look_canceled.emit()
	for action: String in actions:
		action_changed.emit(action, false)
	queue_redraw()

func get_hit_regions() -> Dictionary:
	_ensure_layout()
	return _regions.duplicate()

## HUD placement uses these copied rectangles, never an assumed action grid.
func get_action_rects() -> Dictionary[String, Rect2]:
	_ensure_layout()
	var rectangles: Dictionary[String, Rect2] = {}
	for action: String in TOP_ACTIONS + PLAY_ACTIONS:
		if _regions.has(action): rectangles[action] = _regions[action]
	return rectangles

func get_tool_rects() -> Dictionary[String, Rect2]:
	_ensure_layout()
	var rectangles: Dictionary[String, Rect2] = {}
	for action: String in TOOL_ACTIONS:
		if _regions.has(action): rectangles[action] = _regions[action]
	return rectangles

## Bottom edge of the tool/utility band in local logical pixels.
func get_layout_height() -> float:
	_ensure_layout()
	return _layout_height

## These two public methods use local logical pixels, exactly as _input does
## after converting viewport coordinates. Web Touch.identifier is signed32;
## normalize native IDs separately from internal negative mouse/empty markers.
func handle_touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> bool:
	if index < -2147483648 or index > 2147483647 or not position.is_finite():
		return false
	return _handle_pointer(index & 0xffffffff, position, pressed, canceled, true)

func handle_drag(index: int, position: Vector2, relative: Vector2) -> bool:
	if index < -2147483648 or index > 2147483647 or not position.is_finite() or not relative.is_finite():
		return false
	return _drag_pointer(index & 0xffffffff, position, relative)

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
		elif _mouse_preview_enabled and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			handled = _handle_pointer(MOUSE_POINTER, _local_position(event.position), event.pressed, false, true)
		elif _mouse_preview_enabled and event is InputEventMouseMotion and _owners.has(MOUSE_POINTER):
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
		return _release_pointer(index, canceled)
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
	owner.previous_position = position
	_owners[index] = owner
	match region:
		"move":
			if _move_owner == NO_POINTER:
				owner.kind = PointerKind.MOVE
				_move_owner = index
				if _floating_stick:
					var bounds: Rect2 = _regions["move"]
					_stick_center = Vector2(clampf(position.x, bounds.position.x + _stick_radius, bounds.end.x - _stick_radius), clampf(position.y, bounds.position.y + _stick_radius, bounds.end.y - _stick_radius))
					# Edge-clamping the visible base must not move on initial DOWN.
					_move_grab_offset = position - _stick_center
					_stick_delta = Vector2.ZERO
					_set_movement(Vector2.ZERO)
				else:
					_move_grab_offset = Vector2.ZERO
					_update_stick(position)
		"look":
			if _look_owner == NO_POINTER:
				owner.kind = PointerKind.LOOK
				_look_owner = index
		_:
			owner.kind = PointerKind.ACTION
			owner.action = region
			if region == "primary" and _look_owner == NO_POINTER and _can_fire_drag_look():
				owner.kind = PointerKind.ACTION_LOOK
				_look_owner = index
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
		PointerKind.LOOK, PointerKind.ACTION_LOOK:
			# Web changed-touch list order can corrupt engine relative motion.
			# Both samples belong to this exact down-to-up owner in local pixels.
			var owned_delta := position - owner.previous_position
			if not owned_delta.is_finite(): return false
			owner.previous_position = position
			if owned_delta != Vector2.ZERO:
				look_moved.emit(owned_delta)
		PointerKind.ACTION:
			# An action can release outside and repress inside its original box,
			# but it never becomes another action, a stick, or a look pointer.
			_set_owner_holding(owner, _regions[owner.action].has_point(position))
		_:
			pass
	queue_redraw()
	return true

func _release_pointer(index: int, canceled: bool = false) -> bool:
	if not _owners.has(index):
		return false
	var owner: PointerOwner = _owners[index]
	var cancel_look: bool = canceled and _look_owner == index
	_owners.erase(index)
	match owner.kind:
		PointerKind.MOVE:
			_move_owner = NO_POINTER
			_stick_delta = Vector2.ZERO
			_move_grab_offset = Vector2.ZERO
			_stick_center = _resting_stick_center
			_set_movement(Vector2.ZERO)
		PointerKind.LOOK:
			_look_owner = NO_POINTER
		PointerKind.ACTION:
			_set_owner_holding(owner, false)
		PointerKind.ACTION_LOOK:
			if _look_owner == index: _look_owner = NO_POINTER
			_set_owner_holding(owner, false)
		_:
			pass
	if cancel_look:
		look_canceled.emit()
	queue_redraw()
	return true

func _can_fire_drag_look() -> bool:
	if not _fire_drag_look: return false
	if not is_instance_valid(_player): return true
	return _player.controls_enabled and _player.session != null and _player.session.health > 0 and _player.session.team < 2 \
		and _player.camera_mode in [BlockfieldPlayer.CameraMode.FIRST_PERSON, BlockfieldPlayer.CameraMode.THIRD_PERSON]

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
	_stick_delta = (position - _move_grab_offset - _stick_center).limit_length(_stick_radius)
	var normalized: Vector2 = _stick_delta / _stick_radius
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
	# Only invalidate paint when the session changes its selected tool.
	var displayed_tool: int = _player.session.current_tool if is_instance_valid(_player) and _player.session != null else -1
	if displayed_tool != _displayed_tool:
		_displayed_tool = displayed_tool
		queue_redraw()
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

func _on_canvas_resized() -> void:
	# A CSS resize can change physical hit sizes without changing logical size.
	_layout_size = Vector2(-1, -1)
	_ensure_layout()

func _logical_button_floor() -> float:
	var css_scale: float = 1.0
	if OS.has_feature("web") and is_inside_tree():
		var extent: Vector2 = get_viewport().get_visible_rect().size
		if extent.is_finite() and extent.x > 0.0 and extent.y > 0.0:
			# Layout-time only; DPR is irrelevant to CSS touch target dimensions.
			var script := "(() => {const c=document.querySelector('canvas');if(!c)return 0;const r=c.getBoundingClientRect();return Math.min(r.width/%f,r.height/%f);})()" % [extent.x, extent.y]
			var measured: Variant = JavaScriptBridge.eval(script)
			if measured is float or measured is int:
				var transform: Transform2D = get_global_transform_with_canvas()
				var local_scale: float = minf(transform.x.length(), transform.y.length())
				var value: float = float(measured) * local_scale
				if is_finite(value) and value > 0.0: css_scale = value
	return MIN_CSS_BUTTON_SIZE / css_scale

func _ensure_layout() -> void:
	if _layout_size == size:
		return
	release_all()
	_layout_size = size
	_regions.clear()
	_look_hint_rect = Rect2()
	_layout_height = 0.0
	var button_floor: float = _logical_button_floor()
	var css_unit: float = button_floor / MIN_CSS_BUTTON_SIZE
	_css_unit = css_unit
	# A320px outer viewport can lose1px at the canvas edge and <1px when expanded.
	if size.x < 318.0 * css_unit or size.y < 318.0 * css_unit:
		return
	# Measure CSS scale only when laying out, keeping Web interop out of _draw.
	var font_floor: int = ceili(button_floor * MIN_CSS_LABEL_SIZE / MIN_CSS_BUTTON_SIZE)
	_button_font_size = maxi(ceili(15.0 * _control_scale * css_unit), font_floor)
	_hint_font_size = maxi(ceili(13.0 * css_unit), font_floor)
	var margin: float = MARGIN * css_unit
	var gap: float = GAP * css_unit
	var top_band: Dictionary[String, float] = _layout_top_band(css_unit, margin, gap, button_floor)
	var combat_top: float = top_band["combat_top"]
	var combat_gap: float = top_band["gap"]
	var bottom: float = size.y - HUD_BOTTOM_RESERVE - margin
	var move_width: float = size.x * MOVE_WIDTH_RATIO
	var look_width: float = size.x - margin - move_width - combat_gap
	# Fit the thumb arc as a whole. CSS minima survive both narrow portrait and
	# large control preferences; fire retains at least 1.2× the minimum target.
	var low: float = 0.0
	var high: float = _control_scale
	for iteration: int in range(16):
		var candidate: float = (low + high) * 0.5
		var dimensions: Dictionary[String, float] = _combat_dimensions(css_unit, candidate, button_floor)
		if _combat_fits(dimensions, look_width, bottom - combat_top, combat_gap): low = candidate
		else: high = candidate
	var combat: Dictionary[String, float] = _combat_dimensions(css_unit, low, button_floor)
	_layout_combat(combat, size.x - margin, bottom, move_width + combat_gap, combat_gap)
	var sprint_size: float = maxf(button_floor, 60.0 * css_unit * _control_scale)
	var desired_stick: float = STICK_SIZE * css_unit * _control_scale
	_stick_extent = maxf(32.0 * css_unit, minf(desired_stick, bottom - _layout_height - gap * 3.0 - sprint_size))
	if not _floating_stick:
		# A fixed activation pad must fit inside the movement column. Floating
		# mode keeps the existing radius and only clamps its visible base.
		_stick_extent = minf(_stick_extent, move_width - margin * 2.0)
	_stick_radius = STICK_RADIUS * _stick_extent / STICK_SIZE
	_resting_stick_center = Vector2(margin + _stick_extent * 0.5, bottom - _stick_extent * 0.5)
	if _floating_stick:
		# Buttons have hit-test priority. The left thumb need not hit a small
		# drawn circle to begin movement; each gesture starts neutral at DOWN.
		_regions["move"] = Rect2(Vector2.ZERO, Vector2(move_width, size.y))
		_stick_radius = minf(_stick_radius, minf(move_width, _regions["move"].size.y) * 0.5)
		_resting_stick_center.x = clampf(_resting_stick_center.x, _stick_radius, move_width - _stick_radius)
	else:
		_regions["move"] = Rect2(Vector2(margin, bottom - _stick_extent), Vector2.ONE * _stick_extent)
	var sprint_x: float = clampf(_resting_stick_center.x + _stick_extent * 0.12 - sprint_size * 0.5, margin, move_width - margin - sprint_size)
	_regions["sprint"] = Rect2(Vector2(sprint_x, bottom - _stick_extent - gap - sprint_size), Vector2.ONE * sprint_size)
	# Blank space behind the toolbar, thumb arc and footer can begin look;
	# buttons win the DOWN hit test, then this role stays owned until release.
	_regions["look"] = Rect2(Vector2(move_width, 0.0), Vector2(size.x - move_width, size.y))
	var actions_top: float = size.y
	for action: String in PLAY_ACTIONS:
		if action != "sprint": actions_top = minf(actions_top, _regions[action].position.y)
	var hint_height: float = 24.0 * css_unit
	_look_hint_rect = Rect2(Vector2(move_width, actions_top - gap - hint_height), Vector2(size.x - move_width - margin, hint_height))
	if _left_handed:
		for name: String in _regions:
			_regions[name] = _mirror_rect(_regions[name])
		_resting_stick_center.x = size.x - _resting_stick_center.x
		_look_hint_rect = _mirror_rect(_look_hint_rect)
	_stick_center = _resting_stick_center
	queue_redraw()

func _mirror_rect(rect: Rect2) -> Rect2:
	return Rect2(Vector2(size.x - rect.end.x, rect.position.y), rect.size)

func _layout_row(actions: Array[String], origin: Vector2, extent: float, gap: float) -> void:
	var x: float = origin.x
	for action: String in actions:
		_regions[action] = Rect2(Vector2(x, origin.y), Vector2.ONE * extent)
		x += extent + gap

func _layout_top_band(css_unit: float, margin: float, gap: float, floor_size: float) -> Dictionary[String, float]:
	var tool_size: float = maxf(floor_size, 60.0 * css_unit * _control_scale)
	tool_size = minf(tool_size, (size.x - margin * 2.0 - gap * 3.0) / 4.0)
	var utility_size: float = maxf(floor_size, 56.0 * css_unit * _control_scale)
	utility_size = minf(utility_size, (size.x - margin * 2.0 - gap * 2.0) / 3.0)
	var tool_width: float = tool_size * 4.0 + gap * 3.0
	var utility_width: float = utility_size * 3.0 + gap * 2.0
	var utility_x: float = size.x - margin - utility_width
	_button_size = tool_size
	if tool_width + gap * 3.0 <= utility_x - margin:
		var tool_x: float = margin + (utility_x - margin - gap * 3.0 - tool_width) * 0.5
		_layout_row(TOOL_ACTIONS, Vector2(tool_x, margin), tool_size, gap)
		_layout_row(UTILITY_ACTIONS, Vector2(utility_x, margin), utility_size, gap)
		_layout_height = margin + maxf(tool_size, utility_size)
		return {"combat_top": _layout_height + gap, "gap": gap}
	if size.y < 400.0 * css_unit:
		# A short, narrow canvas cannot spare two complete top rows. Keep the
		# utilities on the right and compact the tools onto the unused left.
		var compact_gap: float = 4.0 * css_unit
		var compact_utility_width: float = floor_size * 3.0 + compact_gap * 2.0
		_layout_row(UTILITY_ACTIONS, Vector2(size.x - margin - compact_utility_width, margin), floor_size, compact_gap)
		if floor_size * 7.0 + compact_gap * 6.0 + margin * 2.0 <= size.x:
			_layout_row(TOOL_ACTIONS, Vector2(margin, margin), floor_size, compact_gap)
			_layout_height = margin + floor_size
		else:
			_layout_row(TOOL_ACTIONS.slice(0, 2), Vector2(margin, margin), floor_size, compact_gap)
			_layout_row(TOOL_ACTIONS.slice(2), Vector2(margin, margin + floor_size + compact_gap), floor_size, compact_gap)
			_layout_height = margin + floor_size * 2.0 + compact_gap
		var compact_combat_gap: float = 6.0 * css_unit
		return {"combat_top": margin + floor_size + compact_combat_gap, "gap": compact_combat_gap}
	_layout_row(UTILITY_ACTIONS, Vector2(utility_x, margin), utility_size, gap)
	_layout_row(TOOL_ACTIONS, Vector2((size.x - tool_width) * 0.5, margin + utility_size + gap), tool_size, gap)
	_layout_height = margin + utility_size + gap + tool_size
	return {"combat_top": _layout_height + gap, "gap": gap}

func _combat_dimensions(css_unit: float, factor: float, floor_size: float) -> Dictionary[String, float]:
	return {
		"primary": maxf(floor_size * 1.2, 96.0 * css_unit * factor),
		"secondary": maxf(floor_size, 76.0 * css_unit * factor),
		"reload": maxf(floor_size, 56.0 * css_unit * factor),
		"jump": maxf(floor_size, 68.0 * css_unit * factor),
		"crouch": maxf(floor_size, 64.0 * css_unit * factor),
	}

func _combat_fits(dimensions: Dictionary[String, float], width: float, height: float, gap: float) -> bool:
	var column_width: float = dimensions["primary"] + maxf(dimensions["jump"], dimensions["crouch"]) + gap
	if column_width > width: return false
	var folded: bool = column_width + dimensions["secondary"] + gap > width
	var required_height: float = dimensions["crouch"] * 0.5 + dimensions["primary"] + gap + dimensions["reload"]
	if folded:
		required_height = maxf(dimensions["crouch"] * 0.5 + dimensions["primary"] + gap + dimensions["secondary"], dimensions["crouch"] + dimensions["jump"] + gap * 2.0 + dimensions["reload"])
	return required_height <= height

func _layout_combat(dimensions: Dictionary[String, float], right: float, bottom: float, left: float, gap: float) -> void:
	var primary_size: float = dimensions["primary"]
	var secondary_size: float = dimensions["secondary"]
	var reload_size: float = dimensions["reload"]
	var jump_size: float = dimensions["jump"]
	var crouch_size: float = dimensions["crouch"]
	var posture_width: float = maxf(jump_size, crouch_size)
	var fire_x: float = right - posture_width - gap - primary_size
	var fire_bottom: float = bottom - crouch_size * 0.5
	var fire_y: float = fire_bottom - primary_size
	var jump_y: float = bottom - crouch_size - gap - jump_size
	_regions["primary"] = Rect2(Vector2(fire_x, fire_y), Vector2.ONE * primary_size)
	_regions["jump"] = Rect2(Vector2(right - jump_size, jump_y), Vector2.ONE * jump_size)
	_regions["crouch"] = Rect2(Vector2(right - crouch_size, bottom - crouch_size), Vector2.ONE * crouch_size)
	if fire_x - gap - secondary_size >= left:
		_regions["secondary"] = Rect2(Vector2(fire_x - gap - secondary_size, fire_bottom - secondary_size * 0.8), Vector2.ONE * secondary_size)
		_regions["reload"] = Rect2(Vector2(fire_x + (primary_size - reload_size) * 0.5, fire_y - gap - reload_size), Vector2.ONE * reload_size)
	else:
		_regions["secondary"] = Rect2(Vector2(fire_x, fire_y - gap - secondary_size), Vector2.ONE * secondary_size)
		_regions["reload"] = Rect2(Vector2(right - reload_size, jump_y - gap - reload_size), Vector2.ONE * reload_size)

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
	style.set_corner_radius_all(20)
	style.anti_aliasing = true
	return style

func _draw() -> void:
	if not _active or _regions.is_empty() or _normal_style == null:
		return
	if _font == null:
		_font = CombatTheme.font()
	for action: String in TOP_ACTIONS + PLAY_ACTIONS:
		var rect: Rect2 = _regions[action]
		var held: bool = _action_counts.get(action, 0) > 0
		_draw_action(rect, action, held)
	var center: Vector2 = _stick_center
	var moving: bool = _move_owner != NO_POINTER
	var stick_color: Color = Color(0.45, 0.88, 1.0, 0.90) if moving else Color(0.92, 0.96, 1.0, 0.60)
	draw_circle(center, _stick_radius, Color(0.035, 0.055, 0.075, 0.22))
	draw_arc(center, _stick_radius, 0.0, TAU, 64, Color(0.91, 0.96, 1.0, 0.30), 1.0, true)
	draw_arc(center, _stick_radius * 0.66, 0.0, TAU, 48, Color(0.91, 0.96, 1.0, 0.09), 1.0, true)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + direction * (_stick_radius - 7.0), center + direction * (_stick_radius - 3.0), Color(0.92, 0.96, 1.0, 0.34), 1.5, true)
	var knob: Vector2 = center + _stick_delta
	var knob_radius: float = 24.0 * _stick_radius / STICK_RADIUS
	if moving:
		draw_line(center, knob, Color(0.45, 0.88, 1.0, 0.28), 2.0, true)
	draw_circle(knob, knob_radius, Color(0.035, 0.055, 0.075, 0.46 if moving else 0.30))
	draw_arc(knob, knob_radius, 0.0, TAU, 48, stick_color, 1.5, true)
	draw_circle(knob, 2.5 * _stick_radius / STICK_RADIUS, stick_color)
	var hint_y: float = minf(center.y + _stick_radius - 4.0, size.y - HUD_BOTTOM_RESERVE - 24.0)
	_draw_label(Rect2(Vector2(center.x - 75, hint_y), Vector2(150, 24)), _ui("Движение", "Move"), _hint_font_size, Color(0.91, 0.96, 1.0, 0.54))
	_draw_label(_look_hint_rect, _ui("Проведи для поворота", "Drag to look"), _hint_font_size, Color(0.91, 0.96, 1.0, 0.42))

func _draw_action(rect: Rect2, action: String, held: bool) -> void:
	var is_play_action: bool = PLAY_ACTIONS.has(action)
	var is_round: bool = is_play_action or UTILITY_ACTIONS.has(action)
	var tool_index: int = TOP_ACTIONS.find(action)
	var is_tool: bool = tool_index >= 0 and tool_index < 4
	var selected: bool = is_tool and _displayed_tool == tool_index
	var emphasized: bool = held or selected
	var color: Color = Color(0.45, 0.88, 1.0, 0.96) if emphasized else Color(0.95, 0.97, 1.0, 0.90)
	var inactive_secondary: bool = action == "secondary" and _displayed_tool == LocalSession.Tool.GRENADE
	if inactive_secondary: color.a = 0.28
	if is_round:
		var radius: float = minf(rect.size.x, rect.size.y) * 0.5 - 2.0
		var fill: Color = Color(0.08, 0.24, 0.30, 0.64) if held else Color(0.035, 0.055, 0.075, 0.34)
		var ring: Color = Color(0.45, 0.88, 1.0, 0.96) if held else Color(0.92, 0.96, 1.0, 0.36)
		if action == "primary" and not held:
			ring = Color(0.45, 0.88, 1.0, 0.65)
			fill.a = 0.46
		if inactive_secondary:
			fill.a = 0.18
			ring.a = 0.16
		draw_circle(rect.get_center(), radius, fill)
		draw_arc(rect.get_center(), radius, 0.0, TAU, 64, ring, 2.2 if action == "primary" else 1.3, true)
	else:
		draw_style_box(_held_style if emphasized else _normal_style, rect.grow(-1.0))
		if selected:
			var center: Vector2 = rect.get_center()
			draw_line(Vector2(center.x - rect.size.x * 0.15, rect.end.y - 5.0), Vector2(center.x + rect.size.x * 0.15, rect.end.y - 5.0), color, 2.0, true)
	var label_size: int = mini(_button_font_size, _hint_font_size)
	var label_height: float = _font.get_height(label_size)
	var icon_extent: float = minf(rect.size.x * 0.42, maxf(16.0 * _css_unit, rect.size.y - label_height - 14.0 * _css_unit))
	var icon_center: Vector2 = Vector2(rect.get_center().x, rect.position.y + (rect.size.y - label_height) * 0.42)
	CombatTheme.draw_icon(self, action, Rect2(icon_center - Vector2.ONE * icon_extent * 0.5, Vector2.ONE * icon_extent), color)
	var label_rect: Rect2 = Rect2(Vector2(rect.position.x + 2.0 * _css_unit, rect.end.y - label_height - 11.0 * _css_unit), Vector2(rect.size.x - 4.0 * _css_unit, label_height))
	_draw_label(label_rect, _label(action), label_size, color)
	if is_tool:
		var number_rect: Rect2 = Rect2(rect.position + Vector2(4.0, 3.0), Vector2(label_height, label_height))
		_draw_label(number_rect, str(tool_index + 1), label_size, Color(0.45, 0.88, 1.0, 0.84) if selected else Color(0.91, 0.96, 1.0, 0.45))

func _draw_label(rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var lines: PackedStringArray = text.split("\n")
	var height: float = _font.get_height(font_size)
	var y: float = rect.get_center().y - height * lines.size() * 0.5 + _font.get_ascent(font_size)
	for line: String in lines:
		draw_string(_font, Vector2(rect.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)
		y += height

func _label(action: String) -> String:
	if action == "primary":
		match _displayed_tool:
			LocalSession.Tool.SPADE: return _ui("Удар", "Strike")
			LocalSession.Tool.BLOCK: return _ui("Блок", "Place")
			LocalSession.Tool.GRENADE: return _ui("Бросок", "Throw")
	if action == "secondary":
		match _displayed_tool:
			LocalSession.Tool.SPADE: return _ui("Копать", "Dig")
			LocalSession.Tool.BLOCK: return _ui("Линия", "Line")
			LocalSession.Tool.GRENADE: return ""
	match action:
		"primary": return _ui("Огонь", "Fire")
		"secondary": return _ui("Прицел", "Aim")
		"reload": return _ui("Перез.", "Reload")
		"jump": return _ui("Прыжок", "Jump")
		"crouch": return _ui("Присед", "Crouch")
		"sprint": return _ui("Бег", "Sprint")
		"tool_spade": return _ui("Лопата", "Spade")
		"tool_block": return _ui("Блок", "Block")
		"tool_weapon": return _ui("Оружие", "Gun")
		"tool_grenade": return _ui("Гран.", "Gren.")
		"map": return _ui("Карта", "Map")
		"view_toggle": return _ui("Вид", "View")
		"menu": return _ui("Меню", "Menu")
		_: return action

func _ui(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en
