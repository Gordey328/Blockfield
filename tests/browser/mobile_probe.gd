extends Node
## Test-only genuine Main/HUD/Player Web scene. Authored DOM TouchEvents cross
## Godot's JS/WASM boundary; they do not establish physical-phone comfort.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const TURN: float = 400.0 * PI / 180.0
const EPS: float = 0.00006
const TOUCH_BASE: int = 20
const DOM_IDS: Array[int] = [-1, -2, -2147483648, 2147483647, 0]

class PanelInputGuard extends Node:

	var panel: Control
	var button: Button
	var is_injecting: Callable
	var held: Dictionary[int, bool] = {}

	func _input(event: InputEvent) -> void:
		if is_injecting.call() or not is_instance_valid(panel):
			return
		var index: int = -1
		var position: Vector2 = Vector2.ZERO
		var pressed: bool = false
		var released: bool = false
		var canceled: bool = false
		if event is InputEventScreenTouch:
			index = event.index
			position = event.position
			pressed = event.pressed and not event.canceled
			released = not event.pressed or event.canceled
			canceled = event.canceled
		elif event is InputEventScreenDrag:
			index = event.index
			position = event.position
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			position = event.position
			pressed = event.pressed
			released = not event.pressed
		elif event is InputEventMouseMotion:
			position = event.position
		else:
			return
		var local: Vector2 = panel.get_global_transform_with_canvas().affine_inverse() * position
		var inside: bool = Rect2(Vector2.ZERO, panel.size).has_point(local)
		if not inside and not held.has(index):
			return
		# Raw _input precedes GUI routing. This late-added guard consumes the
		# panel footprint before the real full-screen mobile overlay sees it.
		get_viewport().set_input_as_handled()
		var button_local: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * position
		var over_button: bool = Rect2(Vector2.ZERO, button.size).has_point(button_local)
		if pressed:
			held[index] = over_button
		elif released:
			var was_button: bool = held.get(index, false)
			held.erase(index)
			if was_button and over_button and not canceled and not button.disabled:
				button.pressed.emit()

var app: Node3D
var mobile: BlockfieldMobileControls
var panel: PanelContainer
var run_button: Button
var status: Label
var busy: bool = false
var injecting: bool = false
var is_ready: bool = false
var phase: String = "Preparing genuine Main"
var assertions: int = 0
var failures: int = 0
var rows: Array[Dictionary] = []
var run_generation: int = 0

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.session.invulnerable = true
	app.session.unlimited_ammo = false
	app.session.select_team(0)
	app.session.select_weapon(LocalSession.Weapon.RIFLE)
	app.session.select_tool(LocalSession.Tool.WEAPON)
	app.hud.set_mobile_controls_mode(1)
	app.hud.set_hud_hidden(false)
	app.hud.set_menu_visible(false)
	mobile = app.hud.mobile_controls
	_preferences(false)
	for soldier: Node3D in app._target_nodes:
		soldier.queue_free()
	app._target_nodes.clear()
	app.session.targets.clear()
	_prepare_world()
	_create_panel()
	_publish("preparing")
	var deadline: int = Time.get_ticks_msec() + 10000
	while not app.player.can_use_tool() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	is_ready = app.player.can_use_tool()
	phase = "Ready — DOM touch checks" if is_ready else "Weapon readiness timed out"
	run_button.disabled = not is_ready
	_publish("ready" if is_ready else "failed")
	print("MOBILE WEB: genuine Main ready; physical phone untested: ", is_ready)

func _create_panel() -> void:
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.layer = 30
	add_child(overlay)
	panel = PanelContainer.new()
	panel.position = Vector2(12, 100)
	panel.custom_minimum_size = Vector2(340, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.045, 0.065, 0.92)
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var title: Label = Label.new()
	title.text = "MOBILE INPUT — ACTUAL GODOT WEB"
	column.add_child(title)
	run_button = Button.new()
	run_button.text = "Run DOM touch checks"
	run_button.custom_minimum_size = Vector2(316, 42)
	run_button.focus_mode = Control.FOCUS_NONE
	run_button.disabled = true
	run_button.pressed.connect(_run_checks)
	column.add_child(run_button)
	status = Label.new()
	status.custom_minimum_size = Vector2(316, 98)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	var guard: PanelInputGuard = PanelInputGuard.new()
	guard.panel = panel
	guard.button = run_button
	guard.is_injecting = func() -> bool: return injecting
	# Reverse scene order delivers raw input to this guard first.
	overlay.add_child(guard)

func _prepare_world() -> void:
	app.world.clear_world(Vector3i(32, 16, 32))
	app.world.water_enabled = false
	app.world.data.seed_box(Vector3i.ZERO, Vector3i(32, 4, 32), 0x01608070)
	app.world.data.seed_box(Vector3i(13, 4, 7), Vector3i(19, 9, 8), 0x01e8a443)
	app.world._mark_all_chunks()
	app.world.rebuild_now()
	app.player.respawn_at(Vector3(16.5, 4.01, 19.5))
	_reset_pose()

func _preferences(mirrored: bool) -> void:
	app.player.touch_sensitivity = 1.0
	app.player.touch_ads_sensitivity = 1.0
	app.player.invert_touch = false
	app.hud.floating_stick = true
	app.hud.touch_control_scale = 1.0
	app.hud.fire_drag_look = true
	app.hud.left_handed_touch = mirrored
	mobile.set_touch_preferences(true, 1.0, true, mirrored)
	# Desktop mouse remains available on the gameplay fixture. PanelInputGuard
	# reserves the test UI footprint, including clicks while a run is active.
	mobile.set_mouse_preview_enabled(true)

func _process(_delta: float) -> void:
	if status == null:
		return
	status.text = phase + "\n%d checks / %d failures\n" % [assertions, failures] \
		+ "Signed DOM touch IDs; physical phone untested.\n" \
		+ "Actual rendered gameplay; left40% / right60%."

func _publish(state: String) -> void:
	if not OS.has_feature("web"):
		return
	var report: Dictionary = {
		"status": state, "phase": phase, "checks": assertions, "failures": failures,
		"physical_phone_tested": false, "events": "DOM TouchEvent → Godot JS i32 → WASM ScreenTouch/ScreenDrag",
		"touch_identifiers": DOM_IDS,
		"canvas": {"width": mobile.size.x, "height": mobile.size.y}, "results": rows,
	}
	# DOM storage permits read-only browser inspection without reaching engine
	# internals. The isolated preview wrapper displays this same report outside
	# its iframe, so changing preview size never changes a shared browser page.
	var script: String = "(() => { const report = " + JSON.stringify(report) + ";" \
		+ "window.__blockfieldMobileProbe=report;let pre=document.getElementById('mobile-probe-results');" \
		+ "if(!pre){pre=document.createElement('pre');pre.id='mobile-probe-results';" \
		+ "pre.style.cssText='position:absolute;left:12px;bottom:8px;max-height:82px;max-width:calc(100% - 24px);overflow:auto;margin:0;padding:6px;background:#06121de6;color:white;font:11px monospace;pointer-events:none;z-index:5';document.body.appendChild(pre);}" \
		+ "pre.textContent=JSON.stringify(report,null,2);if(window.parent!==window){pre.style.display='none';" \
		+ "window.parent.postMessage({type:'blockfield-mobile-probe',report},window.location.origin);}})();"
	JavaScriptBridge.eval(script, true)

func _check(condition: bool, message: String, observed: Dictionary = {}) -> void:
	assertions += 1
	if not condition:
		failures += 1
	rows.append({"name": message, "passed": condition, "observed": observed})
	print("MOBILE WEB: ", "PASS " if condition else "FAIL ", message)
	_publish("running")

func _reset_pose() -> void:
	app.player.clear_touch_motion()
	app.player.camera_mode = BlockfieldPlayer.CameraMode.FIRST_PERSON
	app.player.rotation = Vector3.ZERO
	app.player.head.rotation = Vector3.ZERO
	app.player._aim_down_state = 0.0
	app.player._aim_toggled = false
	app.player._secondary_held = false

func _freeze(enabled: bool) -> void:
	app.set_process(not enabled)
	app.player.set_process(not enabled)
	app.player.set_physics_process(not enabled)
	app.hud.set_process(not enabled)

func _neutral() -> void:
	mobile.release_all()
	Input.action_release("primary")
	Input.action_release("secondary")
	app.hud.set_menu_visible(false)
	_reset_pose()

func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	if OS.has_feature("web"):
		_dom_touch("touchcancel" if canceled else ("touchstart" if pressed else "touchend"), DOM_IDS[index], position)
		return
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = TOUCH_BASE + index
	# parse_input_event expects window/screen coordinates; Window subsequently
	# localizes them with inverse stretch before the overlay's canvas conversion.
	var to_screen: Transform2D = mobile.get_viewport().get_screen_transform() * mobile.get_global_transform_with_canvas()
	event.position = to_screen * position
	event.window_id = get_window().get_window_id()
	event.pressed = pressed
	event.canceled = canceled
	injecting = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	injecting = false

func _drag(index: int, position: Vector2, wrong_relative: Vector2 = Vector2(9999, -7777)) -> void:
	if OS.has_feature("web"):
		_dom_touch("touchmove", DOM_IDS[index], position)
		return
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = TOUCH_BASE + index
	var to_screen: Transform2D = mobile.get_viewport().get_screen_transform() * mobile.get_global_transform_with_canvas()
	event.position = to_screen * position
	event.relative = to_screen.basis_xform(wrong_relative)
	event.window_id = get_window().get_window_id()
	injecting = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	injecting = false

func _dom_touch(kind: String, identifier: int, position: Vector2) -> void:
	var to_screen: Transform2D = mobile.get_viewport().get_screen_transform() * mobile.get_global_transform_with_canvas()
	var screen_position: Vector2 = to_screen * position
	var script: String = "(() => {const c=document.getElementById('canvas'),r=c.getBoundingClientRect();" \
		+ "const id=" + str(identifier) + ",kind=" + JSON.stringify(kind) + ";" \
		+ "const t=new Touch({identifier:id,target:c,clientX:r.left+" + str(screen_position.x) + "*r.width/c.width," \
		+ "clientY:r.top+" + str(screen_position.y) + "*r.height/c.height});" \
		+ "const active=window.__blockfieldDOMTouches??=new Map();" \
		+ "if(kind==='touchend'||kind==='touchcancel')active.delete(id);else active.set(id,t);" \
		+ "c.dispatchEvent(new TouchEvent(kind,{changedTouches:[t],touches:[...active.values()]," \
		+ "targetTouches:[...active.values()],bubbles:true,cancelable:true}));})();"
	injecting = true
	JavaScriptBridge.eval(script, true)
	Input.flush_buffered_events()
	injecting = false

func _blank_point(zone: String) -> Vector2:
	var regions: Dictionary = mobile.get_hit_regions()
	var bounds: Rect2 = regions[zone]
	for y_ratio: float in [0.55, 0.75, 0.4, 0.2]:
		for x_ratio: float in [0.1, 0.5, 0.85]:
			var point: Vector2 = bounds.position + bounds.size * Vector2(x_ratio, y_ratio)
			var blocked: bool = false
			for name: String in regions:
				if name not in ["move", "look"] and regions[name].has_point(point):
					blocked = true
			var viewport_point: Vector2 = mobile.get_global_transform_with_canvas() * point
			var panel_point: Vector2 = panel.get_global_transform_with_canvas().affine_inverse() * viewport_point
			if not blocked and not Rect2(Vector2.ZERO, panel.size).has_point(panel_point):
				return point
	return bounds.get_center()

func _yaw_is(expected: float) -> bool:
	return absf(angle_difference(app.player.rotation.y, expected)) < EPS

func _run_checks() -> void:
	if busy or not is_ready:
		return
	busy = true
	run_generation += 1
	var generation: int = run_generation
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		if busy and run_generation == generation:
			_check(false, "Bounded mobile probe finished within20 seconds")
			mobile.release_all()
			_freeze(false)
			busy = false
			is_ready = false
			run_generation += 1
			run_button.disabled = true
			phase = "FAIL — probe deadline; reload diagnostic"
			_publish("failed"))
	run_button.disabled = true
	assertions = 0
	failures = 0
	rows.clear()
	phase = "Owned fingers and camera queue"
	_publish("running")
	# Let the physical UI UP complete before the first synthetic gesture.
	await get_tree().process_frame
	if generation != run_generation:
		return
	_preferences(false)
	_neutral()
	_freeze(true)
	var regions: Dictionary = mobile.get_hit_regions()
	var move_rect: Rect2 = regions["move"]
	var look_rect: Rect2 = regions["look"]
	_check(app.hud.uses_mobile_controls() and app.player.controls_enabled and mobile.visible,
		"Actual Main HUD On enables genuine touch input")
	_check(absf(move_rect.size.x / mobile.size.x - 0.4) < EPS \
		and absf(look_rect.size.x / mobile.size.x - 0.6) < EPS \
		and move_rect.size.y == mobile.size.y and look_rect.size.y == mobile.size.y,
		"Full-canvas movement40% / look60%", {"width": mobile.size.x})
	var move: Vector2 = _blank_point("move")
	var look: Vector2 = _blank_point("look")
	var fire: Vector2 = regions["primary"].get_center()
	var delta: Vector2 = Vector2(mobile.size.x * 0.225, mobile.size.x * 0.025)
	_touch(0, move, true)
	_touch(1, look, true)
	_touch(2, fire, true)
	_touch(3, look + Vector2(12, 8), true)
	_drag(0, move + Vector2(0, -65))
	_drag(3, look + Vector2(170, -100))
	_drag(2, fire - Vector2(120, 20))
	# With LOOK already owned, Fire is an ordinary action: leaving releases it
	# and returning holds it again, while neither motion can become look.
	_drag(2, fire)
	_drag(1, look + delta)
	_check(app.player.touch_movement.length() > 0.2 and Input.is_action_pressed("primary"),
		"Movement, one look owner and firing coexist through _input")
	_check(_yaw_is(0.0), "Drag is queued until a presentation/simulation boundary")
	_touch(1, look + delta, false)
	app.player.flush_touch_motion()
	_check(_yaw_is(-PI * 0.5) and absf(app.player.head.rotation.x + TURN * 0.025) < EPS,
		"Owned position produces90deg turn across native browser input; normal UP keeps it",
		{"yaw_degrees": rad_to_deg(app.player.rotation.y), "pitch_degrees": rad_to_deg(app.player.head.rotation.x)})
	_check(not app.player.flush_touch_motion(), "A queued swipe is consumed exactly once")
	_touch(0, move, false)
	_touch(2, fire, false)
	_touch(3, look, false)
	_check(app.player.touch_movement == Vector2.ZERO and not Input.is_action_pressed("primary"),
		"Normal UP clears movement and fire action")
	_neutral()
	phase = "Fire-drag, cancel and lifecycle"
	_touch(2, fire, true)
	_drag(2, fire - Vector2(mobile.size.x * 0.1, 0))
	app.player.flush_touch_motion()
	_check(Input.is_action_pressed("primary") and _yaw_is(TURN * 0.1),
		"Fire button wins DOWN and keeps firing while dragging outside to aim")
	_touch(2, fire, false)
	_neutral()
	_touch(1, look, true)
	_drag(1, look + Vector2(90, 0))
	_touch(1, look, false, true)
	if OS.has_feature("web"):
		# Pinned Godot maps DOM touchcancel to ordinary END. Verify that it
		# releases the claim; native canceled=true separately tests queue clearing.
		var pending_yaw: float = app.player.rotation.y
		app.player.clear_touch_motion()
		_drag(1, look + Vector2(120, 0))
		_check(not app.player.flush_touch_motion() and app.player.rotation.y == pending_yaw,
			"DOM touchcancel releases its signed-ID owner; subsequent MOVE is ignored")
		_neutral()
	else:
		_check(not app.player.flush_touch_motion() and _yaw_is(0.0), "Canceled look clears pending camera motion")
	_touch(0, move, true)
	_drag(0, move + Vector2(0, -65))
	_touch(1, look, true)
	_drag(1, look + Vector2(90, 0))
	_touch(2, fire, true)
	app.hud.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not app.player.controls_enabled and app.player.touch_movement == Vector2.ZERO \
		and not Input.is_action_pressed("primary") and not app.player.flush_touch_motion() and _yaw_is(0.0),
		"Actual HUD focus loss releases actions, movement and queued look")
	app.hud.notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	_neutral()
	_touch(1, look, true)
	_drag(1, look + Vector2(90, 0))
	_touch(2, fire, true)
	_touch(4, regions["menu"].get_center(), true)
	_check(app.hud.is_menu_open() and not app.player.controls_enabled \
		and not Input.is_action_pressed("primary") and not app.player.flush_touch_motion() and _yaw_is(0.0),
		"Actual touch menu button clears held fire and pending turn")
	_neutral()
	phase = "Independent mirrored gesture"
	_preferences(true)
	var mirrored: Dictionary = mobile.get_hit_regions()
	var mirror_ok: bool = true
	for name: String in regions:
		var original: Rect2 = regions[name]
		var expected: Rect2 = Rect2(Vector2(mobile.size.x - original.end.x, original.position.y), original.size)
		mirror_ok = mirror_ok and mirrored[name].is_equal_approx(expected)
	_check(mirror_ok and mobile.left_handed, "Left-handed layout independently mirrors zones and every button")
	move = _blank_point("move")
	look = _blank_point("look")
	fire = mirrored["primary"].get_center()
	_touch(0, move, true)
	_drag(0, move + Vector2(0, -65))
	_touch(1, look, true)
	_drag(1, look + Vector2(mobile.size.x * 0.225, 0))
	_touch(2, fire, true)
	app.player.flush_touch_motion()
	_check(_yaw_is(-PI * 0.5) and app.player.touch_movement.y < -0.2 and Input.is_action_pressed("primary"),
		"Mirrored real events retain camera direction, movement and firing")
	_neutral()
	_preferences(false)
	_prepare_world()
	_freeze(false)
	phase = "Visible actual movement and weapon fire"
	await get_tree().process_frame
	if generation != run_generation:
		return
	var deadline: int = Time.get_ticks_msec() + 5000
	while not app.player.can_use_tool() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if generation != run_generation:
			return
	_check(app.player.can_use_tool(), "Restored actual controller reaches weapon readiness")
	regions = mobile.get_hit_regions()
	move = _blank_point("move")
	fire = regions["primary"].get_center()
	var before_position: Vector3 = app.player.global_position
	var before_shots: int = app.session.shots_fired
	_touch(0, move, true)
	_drag(0, move + Vector2(0, -65))
	_touch(2, fire, true)
	_drag(2, fire - Vector2(mobile.size.x * 0.015, 0))
	await get_tree().create_timer(0.8).timeout
	if generation != run_generation:
		return
	_check(app.player.global_position.distance_to(before_position) > 0.02 \
		and app.session.shots_fired > before_shots,
		"Restored frame loop renders movement and fires the genuine weapon",
		{"distance": app.player.global_position.distance_to(before_position), "shots": app.session.shots_fired - before_shots})
	_touch(0, move, false)
	_touch(2, fire, false)
	mobile.release_all()
	busy = false
	run_button.disabled = false
	phase = "PASS — DOM touch checks" if failures == 0 else "FAIL — inspect DOM results"
	_publish("passed" if failures == 0 else "failed")
	print("MOBILE WEB: ", assertions, " checks / ", failures, " failures; physical phone untested")
