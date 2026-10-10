extends SceneTree
## Exercise production touch ownership and its real source-controller bridge.
## No Main/HUD readiness, user settings, rendering or audio-device setup.
const MOBILE = preload("res://ui/mobile_controls.gd")
const PLAYER = preload("res://gameplay/player_controller.gd")
const LOCAL = preload("res://gameplay/local_session.gd")
const NETWORK = preload("res://network/network_session.gd")
const CLIENT = preload("res://network/client_replica.gd")
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPAT = preload("res://network/compatibility.gd")
const RULES = preload("res://simulation/player_rules.gd")
const DT := 1.0 / 60.0
const BUTTONS: Array[String] = ["primary", "secondary", "reload", "jump", "crouch", "sprint", "tool_spade", "tool_block", "tool_weapon", "tool_grenade", "map", "view_toggle", "menu"]
const ACTIONS: Array[String] = ["left", "right", "forward", "back", "jump", "crouch", "sprint", "sneak", "primary", "secondary", "reload", "tool_spade", "tool_block", "tool_weapon", "tool_grenade", "map", "view_toggle", "eyedropper", "last_tool"]
var assertions := 0
var failures := 0
var new_actions: Array[String] = []
var overlay: MOBILE
var action_events: Array[Dictionary] = []
var look_events: Array[Vector2] = []
var movement_events: Array[Vector2] = []
var menu_events := 0
var player: PLAYER
var session: LOCAL
var world: VoxelWorld
var lab: MinimalLab
var server: SERVER
var simulation: MATCH
var client: CLIENT
var started := {}

class MinimalLab extends Node3D:

	var network_client: CLIENT
	var audio: Object
	var effects: Object
	var hud: Object
	var browser_pointer_fallback := false
	var graphics_options := {"shake": 0}
	func handle_focus_input(_event: InputEvent) -> bool: return false
	func get_player_corpse_center() -> Vector3: return Vector3(8, 4, 8)
	func spawn_tracer(_origin: Vector3, _end: Vector3) -> void: pass

class MinimalSkin extends Node3D:

	func set_selection(_tool: int, _weapon: int) -> void: pass
	func set_team(_team: int, _color: Color) -> void: pass
	func set_block_color(_color: Color) -> void: pass
	func set_ammo(_rounds: int, _size: int) -> void: pass
	func set_grenade_cook(_age: float) -> void: pass
	func set_tool_action(_kind: int, _progress: float, _ready: float) -> void: pass
	func set_motion_state(_velocity: Vector3, _walk: float, _turn: Vector3, _offset: Vector3) -> void: pass
	func set_animations_enabled(_enabled: bool) -> void: pass
	func set_simulation_state(_values: Dictionary) -> void: pass
	func update_pose(_dt: float, _aim: bool, _sprint: bool, _crouch: bool, _speed: float, _reload: float) -> void: pass
	func cancel_reload() -> void: pass
	func reload_completed() -> void: pass
	func reload() -> void: pass
	func fire() -> void: pass
	func is_changing_tool() -> bool: return false
	func get_displayed_tool() -> int: return 2
	func get_muzzle_transform() -> Transform3D: return global_transform

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("MOBILE CONTROLS: " + message)

func _bridge_action(action: String, pressed: bool) -> void:
	action_events.append({"action": action, "pressed": pressed})
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)

func _bridge_movement(axis: Vector2) -> void:
	movement_events.append(axis)
	if is_instance_valid(player): player.touch_movement = axis

func _bridge_look(relative: Vector2) -> void:
	look_events.append(relative)
	if is_instance_valid(player): player.apply_mouse_motion(relative)

func make_overlay(size: Vector2, bound_player: PLAYER = null) -> void:
	overlay = MOBILE.new()
	root.add_child(overlay)
	overlay.setup(bound_player, null)
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = Vector2.ZERO
	overlay.size = size
	overlay.action_changed.connect(_bridge_action)
	overlay.movement_changed.connect(_bridge_movement)
	overlay.look_moved.connect(_bridge_look)
	overlay.menu_requested.connect(func(): menu_events += 1)
	overlay.set_enabled(true)
	clear_trace()

func clear_trace() -> void:
	action_events.clear()
	look_events.clear()
	movement_events.clear()
	menu_events = 0

func events_for(action: String, pressed: bool) -> int:
	var count := 0
	for event: Dictionary in action_events:
		if event.action == action and event.pressed == pressed: count += 1
	return count

func center(region: String) -> Vector2:
	return (overlay.get_hit_regions()[region] as Rect2).get_center()

func release_inputs() -> void:
	for action: String in ACTIONS: Input.action_release(action)

func settle_input() -> void:
	# Public handlers can enqueue several action edges within one fixture turn.
	# Drain as a real frame does before inspecting global Input state. A second
	# drain also covers actions emitted while dispatching a real pointer event.
	Input.flush_buffered_events()
	await process_frame
	Input.flush_buffered_events()

func geometry(size: Vector2) -> void:
	make_overlay(size)
	var regions := overlay.get_hit_regions()
	check(regions.size() == BUTTONS.size() + 2, "advertised complete control set at %s" % size)
	for name: String in BUTTONS + ["move", "look"]:
		check(regions.has(name), "region %s exists at %s" % [name, size])
		if not regions.has(name): continue
		var rect: Rect2 = regions[name]
		check(rect.position.is_finite() and rect.size.is_finite() and rect.size.x > 0 and rect.size.y > 0, "finite usable region %s" % name)
		check(Rect2(Vector2.ZERO, size).encloses(rect), "region %s stays inside logical viewport" % name)
		if name in BUTTONS: check(rect.size.x >= 60 and rect.size.y >= 60, "minimum touch target %s" % name)
	for i: int in range(BUTTONS.size()):
		var a: Rect2 = regions[BUTTONS[i]]
		for j: int in range(i + 1, BUTTONS.size()):
			check(not a.intersects(regions[BUTTONS[j]]), "button regions do not overlap: %s/%s" % [BUTTONS[i], BUTTONS[j]])
		check(not a.intersects(regions.move) and not a.intersects(regions.look), "button %s is separated from stick/look" % BUTTONS[i])
	check(not (regions.move as Rect2).intersects(regions.look), "stick and look are separate")
	check((regions.move as Rect2).end.y <= size.y - 52, "stick leaves bottom HUD reserve")
	overlay.free()
	overlay = null

func ownership() -> void:
	make_overlay(Vector2(960, 540))
	var move := center("move")
	var look := center("look")
	var primary := center("primary")
	check(overlay.handle_touch(0, move + Vector2(0, -62), true), "first finger owns stick")
	check(overlay.handle_touch(1, look, true), "second finger owns look")
	check(overlay.handle_touch(2, primary, true), "third finger owns fire")
	await settle_input()
	check(overlay.movement_axis.is_equal_approx(Vector2(0, -1)) and Input.is_action_pressed("primary"), "movement and held fire coexist")
	check(overlay.handle_drag(1, primary, Vector2(12, -6)), "look owner may cross a button")
	check(look_events == [Vector2(12, -6)] and overlay.movement_axis.is_equal_approx(Vector2(0, -1)), "look emits supplied local delta without disturbing movement")
	check(events_for("primary", true) == 1 and events_for("primary", false) == 0, "look crossing does not release or duplicate held fire")
	check(overlay.handle_touch(3, move, true) and overlay.handle_touch(4, look, true), "extra stick/look touches are consumed")
	check(overlay.handle_drag(3, look, Vector2(99, 99)) and overlay.handle_drag(4, primary, Vector2(99, 99)), "blocked owners keep their original claims")
	check(look_events.size() == 1 and overlay.movement_axis.is_equal_approx(Vector2(0, -1)), "second stick/look owners cannot steal control")
	check(not overlay.handle_drag(31, look, Vector2(10, 10)) and look_events.size() == 1, "unclaimed drag cannot rotate view")
	check(overlay.handle_drag(0, look, Vector2(3, 4)) and look_events.size() == 1 and overlay.movement_axis.length() <= 1.000001, "stick drag cannot become look and stays bounded")
	overlay.release_all()
	await settle_input()
	check(overlay.movement_axis == Vector2.ZERO and not Input.is_action_pressed("primary") and events_for("primary", false) == 1, "release_all clears the three simultaneous controls")
	check(not overlay.handle_drag(0, move, Vector2.ONE) and not overlay.handle_drag(1, look, Vector2.ONE), "released finger IDs have no residual claims")
	clear_trace()
	check(overlay.handle_touch(5, primary, true) and overlay.handle_touch(6, primary, true), "two fingers can share one action")
	await settle_input()
	check(events_for("primary", true) == 1, "shared button emits one down edge")
	check(overlay.handle_touch(5, primary, false), "first button owner releases")
	await settle_input()
	check(Input.is_action_pressed("primary") and events_for("primary", false) == 0, "first owner release does not release second owner")
	check(overlay.handle_touch(6, primary, false, true), "last button owner cancels")
	await settle_input()
	check(not Input.is_action_pressed("primary") and events_for("primary", false) == 1, "last owner cancel emits one up edge")
	check(overlay.handle_touch(6, primary, true), "canceled finger ID can be reused")
	check(overlay.handle_touch(6, look, true) and events_for("primary", true) == 2, "duplicate down cannot change original button claim")
	check(overlay.handle_drag(6, look, Vector2(8, 5)), "button owner drags outside")
	await settle_input()
	check(not Input.is_action_pressed("primary") and look_events.is_empty(), "dragging outside releases button without turning into look")
	check(overlay.handle_drag(6, center("reload"), Vector2.ONE) and not Input.is_action_pressed("reload"), "dragging button to another button cannot acquire it")
	check(overlay.handle_drag(6, primary, Vector2.ONE), "button owner returns inside")
	await settle_input()
	check(Input.is_action_pressed("primary"), "returning inside represses original button")
	overlay.handle_touch(6, primary, false)
	await settle_input()
	check(events_for("primary", true) == 3 and events_for("primary", false) == 3, "outside/back/up produces balanced button edges")
	clear_trace()
	overlay.handle_touch(0, move + Vector2(3, 0), true)
	check(overlay.movement_axis == Vector2.ZERO, "joystick center deadzone")
	overlay.handle_drag(0, move + Vector2(31, 0), Vector2(28, 0))
	check(absf(overlay.movement_axis.x - (0.5 - 0.12) / 0.88) < 0.00001 and overlay.movement_axis.y == 0, "radial deadzone remaps analog strength")
	overlay.handle_touch(0, move, false, true)
	check(overlay.movement_axis == Vector2.ZERO and movement_events.back() == Vector2.ZERO, "stick cancel publishes neutral movement")
	check(not overlay.handle_touch(-1, primary, true) and not overlay.handle_touch(0, Vector2(NAN, 0), true) and not overlay.handle_drag(0, look, Vector2(INF, 0)), "invalid public pointer input cannot claim control")
	for action: String in BUTTONS:
		if action == "menu": continue
		clear_trace()
		check(overlay.handle_touch(20, center(action), true), "advertised %s button acquires a finger" % action)
		await settle_input()
		check(Input.is_action_pressed(action), "advertised %s button reaches InputEventAction bridge" % action)
		check(overlay.handle_touch(20, center(action), false), "advertised %s button releases its finger" % action)
		await settle_input()
		check(not Input.is_action_pressed(action), "advertised %s button releases InputEventAction" % action)
	overlay.free()
	overlay = null

func lifecycle() -> void:
	make_overlay(Vector2(960, 540))
	for transition: String in ["release_all", "disable", "resize", "focus", "pause", "menu"]:
		overlay.set_enabled(true)
		clear_trace()
		overlay.handle_touch(0, center("move") + Vector2(0, -62), true)
		overlay.handle_touch(1, center("look"), true)
		overlay.handle_touch(2, center("primary"), true)
		await settle_input()
		match transition:
			"release_all": overlay.release_all(); overlay.release_all()
			"disable": overlay.set_enabled(false)
			"resize": overlay.size = Vector2(854, 480); overlay.get_hit_regions()
			"focus": overlay.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"pause": overlay.notification(Node.NOTIFICATION_PAUSED)
			"menu": overlay.handle_touch(3, center("menu"), true)
		await settle_input()
		check(overlay.movement_axis == Vector2.ZERO and not Input.is_action_pressed("primary"), "%s neutralizes held movement/fire" % transition)
		check(events_for("primary", false) == 1 and not overlay.handle_drag(1, center("look"), Vector2.ONE), "%s clears ownership with exactly one release" % transition)
		if transition == "disable": check(not overlay.handle_touch(0, center("primary"), true), "disabled overlay cannot acquire a finger")
		if transition == "menu": check(menu_events == 1, "menu has a dedicated one-shot signal")
		overlay.set_enabled(true)
		check(overlay.handle_touch(0, center("primary"), true), "%s permits clean finger claim reuse" % transition)
		await settle_input()
		check(Input.is_action_pressed("primary"), "%s permits clean finger reuse" % transition)
		overlay.release_all()
		await settle_input()
		overlay.size = Vector2(960, 540)
		overlay.get_hit_regions()
	# Test the actual viewport-event adapter with a transformed Control. The
	# public handlers above deliberately use local coordinates; _input must not.
	overlay.position = Vector2(7, 11)
	overlay.scale = Vector2(1.25, 1.25)
	var presses := events_for("primary", true)
	var touch := InputEventScreenTouch.new()
	touch.window_id = root.get_window_id()
	touch.index = 7
	touch.position = overlay.get_global_transform_with_canvas() * center("primary")
	touch.pressed = true
	# Headless Windows use a 64×64 physical window with a 1280×720 logical
	# viewport. Inject logical pointer pixels through the real Viewport adapter.
	root.push_input(touch, true)
	await settle_input()
	check(events_for("primary", true) == presses + 1, "real ScreenTouch emits exactly one new primary edge")
	check(Input.is_action_pressed("primary"), "real ScreenTouch converts viewport coordinates to local button pixels")
	touch = InputEventScreenTouch.new()
	touch.window_id = root.get_window_id()
	touch.index = 7; touch.position = Vector2(-30, -30); touch.pressed = false
	root.push_input(touch, true)
	await settle_input()
	check(not Input.is_action_pressed("primary"), "real ScreenTouch up outside releases the claimed button")
	overlay.free()
	overlay = null

func mouse_button(position: Vector2, pressed: bool, emulated: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = overlay.get_global_transform_with_canvas() * position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	if emulated: event.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(event, true)
	await settle_input()

func mouse_motion(position: Vector2, relative: Vector2, emulated: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = overlay.get_global_transform_with_canvas() * position
	event.relative = overlay.get_global_transform_with_canvas().basis_xform(relative)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	if emulated: event.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(event, true)
	await settle_input()

func desktop_pointer() -> void:
	make_overlay(Vector2(960, 540))
	await mouse_button(center("move") + Vector2(0, -62), true)
	check(overlay.movement_axis.is_equal_approx(Vector2(0, -1)) and not Input.is_action_pressed("primary"), "real mouse stick uses touch movement without firing")
	await mouse_motion(center("look"), Vector2(12, 4))
	check(look_events.is_empty() and overlay.movement_axis.length() <= 1.000001, "mouse stick claim cannot turn into look")
	await mouse_button(Vector2(-100, -100), false)
	check(overlay.movement_axis == Vector2.ZERO, "mouse up outside releases stick")
	clear_trace()
	await mouse_button(center("reload"), true)
	check(Input.is_action_pressed("reload") and not Input.is_action_pressed("primary") and events_for("reload", true) == 1, "mouse non-fire button emits its own action")
	await mouse_button(center("reload"), false)
	check(not Input.is_action_pressed("reload") and events_for("reload", false) == 1, "mouse button up emits one release")
	await mouse_button(center("look"), true)
	await mouse_motion(center("primary"), Vector2(10, -8))
	check(look_events == [Vector2(10, -8)] and not Input.is_action_pressed("primary"), "designated mouse look survives crossing fire without acquiring it")
	await mouse_button(center("primary"), false)
	clear_trace()
	await mouse_button(center("primary"), true, true)
	await mouse_motion(center("look"), Vector2(20, 20), true)
	await mouse_button(center("primary"), false, true)
	check(action_events.is_empty() and look_events.is_empty() and overlay.movement_axis == Vector2.ZERO, "touch-emulated mouse cannot duplicate component button/look paths")
	await mouse_button(Vector2(400, 530), true)
	await mouse_motion(center("look"), Vector2(8, 8))
	check(action_events.is_empty() and look_events.is_empty(), "mouse starting outside advertised controls cannot acquire look by dragging in")
	await mouse_button(center("look"), false)
	overlay.free()
	overlay = null

func make_player(bound_session: LOCAL, data: DATA) -> void:
	session = bound_session
	root.add_child(session)
	world = VoxelWorld.new()
	root.add_child(world)
	check(world.set_map_data(data, "Mobile controls fixture") == OK, "real source-query world adopts validated fixture terrain")
	world.set_process(false)
	lab = MinimalLab.new(); lab.network_client = client; root.add_child(lab)
	player = PLAYER.new()
	var head := Node3D.new(); head.name = "Head"; player.add_child(head)
	var camera := Camera3D.new(); camera.name = "Camera3D"; head.add_child(camera)
	var weapons := Node3D.new(); weapons.name = "WeaponRoot"; camera.add_child(weapons)
	var collision := CollisionShape3D.new(); collision.name = "CollisionShape3D"; collision.shape = BoxShape3D.new(); player.add_child(collision)
	var skin := MinimalSkin.new(); weapons.add_child(skin); player._weapon_view = skin
	player.world = world; player.session = session; player.lab = lab; player.controls_enabled = true
	root.add_child(player)
	player.set_physics_process(false)
	# Keep actual _unhandled_input enabled: the bridge must deliver real edges.
	player._physics_process(DT)
	make_overlay(Vector2(960, 540), player)

func destroy_player() -> void:
	if overlay != null: overlay.free(); overlay = null
	release_inputs()
	if player != null: player.free(); player = null
	if world != null: world.free(); world = null
	if lab != null: lab.free(); lab = null
	if session != null: session.free(); session = null

func offline_handoff() -> void:
	var data := DATA.new()
	check(data.clear(Vector3i(32, 16, 32), 301) == OK, "offline fixture map")
	data.seed_box(Vector3i.ZERO, Vector3i(32, 4, 32), 0x01607080)
	make_player(LOCAL.new(), data)
	player.respawn_at(Vector3(8.5, 4.01, 20.5))
	player.touch_movement = Vector2(3, 4)
	check(player.touch_movement.is_equal_approx(Vector2(3, 4).normalized()), "controller clamps finite touch intent")
	player.touch_movement = Vector2(NAN, 1)
	check(player.touch_movement == Vector2.ZERO, "controller rejects nonfinite touch intent")
	var start := player.global_position
	overlay.handle_touch(0, center("move") + Vector2(0, -62), true)
	Input.action_press("right")
	check(player.get_source_movement_axis().is_equal_approx(Vector2(1, -1).normalized()), "physical keys and analog touch share normalized source movement")
	Input.action_release("right")
	for i: int in range(12):
		session.update(DT)
		player._physics_process(DT)
	check(player.global_position.z < start.z - 0.05 and absf(player.global_position.x - start.x) < 0.00001, "real offline source motion moves forward from touch stick")
	var rounds := session.magazine
	overlay.handle_touch(1, center("primary"), true)
	await process_frame
	for i: int in range(4):
		session.update(DT); player._physics_process(DT)
	check(session.magazine == rounds - 1 and session.shots_fired == 1, "touch primary reaches actual offline source weapon cadence once")
	overlay.handle_touch(1, center("primary"), false)
	await process_frame
	for i: int in range(40): session.update(DT); player._physics_process(DT)
	check(session.magazine == rounds - 1, "released touch primary stops later ready shots")
	overlay.handle_touch(2, center("tool_block"), true)
	await process_frame
	check(session.current_tool == 1, "touch tool edge reaches real controller selection")
	overlay.handle_touch(2, center("tool_block"), false)
	overlay.handle_touch(3, center("reload"), true)
	await process_frame
	check(not session.is_reloading, "touch reload preserves the weapon-only source gate")
	overlay.handle_touch(3, center("reload"), false)
	overlay.handle_touch(4, center("tool_weapon"), true)
	await process_frame
	overlay.handle_touch(4, center("tool_weapon"), false)
	overlay.handle_touch(3, center("reload"), true)
	await process_frame
	check(session.current_tool == 2 and session.is_reloading, "touch weapon/reload edges reach real local authority")
	overlay.handle_touch(3, center("reload"), false)
	var yaw := player.rotation.y
	overlay.handle_touch(5, center("look"), true)
	overlay.handle_drag(5, center("look") + Vector2(20, 0), Vector2(20, 0))
	check(absf(angle_difference(yaw, player.rotation.y)) > 0.001, "touch look reaches actual source controller mouse transform")
	player.controls_enabled = false
	check(player.touch_movement == Vector2.ZERO and not overlay.handle_drag(0, center("move"), Vector2.ONE) and not Input.is_action_pressed("primary"), "menu gate clears touch movement and component claims")
	player.controls_enabled = true
	check(overlay.handle_touch(0, center("move") + Vector2(62, 0), true) and player.touch_movement.x > 0.999, "menu close allows clean stick reentry")
	destroy_player()

func pump_network() -> void:
	server.poll()
	client.poll()
	check(server.step_once(), "actual runtime fixed step")
	if session is NETWORK: session.update(0)
	for event: Dictionary in client.drain_events():
		var network_session := session as NETWORK
		if network_session == null: continue
		if event.get("predicted", false):
			network_session.ingest_cosmetic(event)
			if player != null: player.apply_network_cosmetic(event)
		elif event.get("type", "") != "map_installed": network_session.ingest_event(event, event.get("predicted_already_played", false))
	await create_timer(DT).timeout

func wait_network(predicate: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if client.status == "failed":
			check(false, message + ": " + client.last_error)
			return false
		if predicate.call(): check(true, message); return true
		await pump_network()
	check(false, message + " timed out")
	return false

func network_handoff() -> void:
	var data := DATA.new()
	check(data.clear(Vector3i(32, 16, 32), 302) == OK, "network fixture map")
	data.seed_box(Vector3i.ZERO, Vector3i(32, 4, 32), 0x01607080)
	simulation = MATCH.new()
	check(simulation.configure(data, "0.75", "sandbox").ok, "real source network match")
	server = SERVER.new()
	check(server.configure(simulation, COMPAT.build_hash(), COMPAT.rules_hash()), "real network runtime compatibility")
	started = server.start()
	check(started.ok, "actual loopback game/map listeners")
	if not started.ok: return
	client = CLIENT.new()
	check(client.connect_to("ws://127.0.0.1:%d/play" % started.game_port, "ws://127.0.0.1:%d/map" % started.map_port, "Mobile fixture").ok, "actual authenticated replica connection")
	if not await wait_network(func(): return client.status == "live", "real map/state barriers become live"): return
	var net_session := NETWORK.new()
	net_session.bind_replica(client)
	make_player(net_session, client.data)
	if not await wait_network(func(): return client.prediction.get_status().pending == 0, "initial controller input acknowledged"): return
	# World adoption may take wall time. Let genuine new snapshots synchronize
	# the clock; no fixture edits to timestamps, prediction or authority state.
	for i: int in range(6): await pump_network()
	player._physics_process(DT)
	if not await wait_network(func(): return client.prediction.get_status().pending == 0, "fresh installed-world controller input acknowledges"): return
	if not await wait_network(func(): return client.get_owner_state().tool_raise >= 0.999, "actual source weapon becomes ready"): return
	var actor := simulation.get_actor(client.actor_id)
	check(actor != null and actor.is_alive(), "mobile fixture has actual playing authority owner")
	if actor == null or not actor.is_alive(): return
	var start := actor.feet()
	var rounds := actor.magazine
	overlay.handle_touch(0, center("move") + Vector2(0, -62), true)
	overlay.handle_touch(1, center("primary"), true)
	await process_frame
	for i: int in range(8):
		client.poll()
		player._physics_process(DT)
		await pump_network()
	check(client.status == "live" and client.get_owner_state().input_move.is_equal_approx(Vector2(0, -1)), "touch axis reaches the actual replica command/prediction")
	check(actor.feet().z < start.z - 0.02 and actor.magazine == rounds - 1, "actual socket authority moves and fires from touch intent")
	check((actor.input_buttons & RULES.Buttons.PRIMARY) != 0, "held touch fire remains an authenticated shared button")
	overlay.release_all()
	await process_frame
	for i: int in range(6):
		client.poll(); player._physics_process(DT); await pump_network()
	check(actor.input_move == Vector2.ZERO and actor.input_buttons == 0 and player.touch_movement == Vector2.ZERO, "touch release reaches authority as neutral command")
	check(server.get_stats().totals.input_rejections == 0 and server.get_stats().totals.stale_inputs == 0, "short real socket fixture needs no admission relaxation or stale retirement")
	check(client.prediction.get_status().pending <= 32, "touch handoff keeps bounded prediction history")
	client.close(); server.stop()
	destroy_player()

func run() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action); new_actions.append(action)
	release_inputs()
	for size: Vector2 in [Vector2(960, 540), Vector2(854, 480), Vector2(480, 854), Vector2(844, 390)]: geometry(size)
	await ownership()
	await lifecycle()
	await desktop_pointer()
	await offline_handoff()
	await network_handoff()
	finish()

func finish() -> void:
	destroy_player()
	if client != null: client.close(); client = null
	if server != null: server.stop(); server = null
	simulation = null
	release_inputs()
	for action: String in new_actions: InputMap.erase_action(action)
	print("MOBILE CONTROLS: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
