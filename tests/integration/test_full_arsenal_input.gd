extends SceneTree
## Actual Main/ViewPort input seams. Headless checks do not accept browser pixels.
const SCENE = preload("res://scenes/main.tscn")
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const LOADOUT = preload("res://gameplay/arsenal_loadout.gd")
const MAPS = preload("res://ui/map_catalog.gd")
var app: Node3D
var checks: int = 0
var failures: int = 0
var backups: Dictionary[String, Dictionary] = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FULL ARSENAL INPUT: " + label)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout

func action(id: String, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = id
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func wheel(button: MouseButton = MOUSE_BUTTON_WHEEL_UP) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = Vector2(640, 360)
	event.pressed = true
	event.window_id = root.get_window_id()
	root.push_input(event, true)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	root.push_input(event, true)

func selected() -> String:
	return "source" if app.arsenal_coordinator.source_selected else app.arsenal_coordinator.runtime.selected_item

func wheel_to(id: String) -> void:
	for index: int in 21:
		if selected() == id: return
		wheel()
	check(selected() == id, "actual wheel reaches " + id + " within one finite inventory cycle")

func backup(path: String) -> void:
	backups[path] = {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func restore() -> void:
	for path: String in backups:
		if bool(backups[path].exists):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			check(file != null, "private user preference backup can be restored")
			if file != null:
				file.store_buffer(backups[path].bytes)
				file.close()
		elif FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "fixture-only preferences are removed")

func close_scene() -> void:
	LabInputBindings.release_actions()
	if is_instance_valid(app): app.queue_free()
	await frames(3)
	app = null

func launch(full: bool) -> bool:
	var loadout: Dictionary = CATALOG.defaults()
	if full: loadout.all_items = true
	set_meta("blockfield_launch", {"mode":"training", "map_id":"lab", "weapon":1, "arsenal":loadout})
	app = SCENE.instantiate()
	root.add_child(app)
	current_scene = app
	var deadline: int = Time.get_ticks_msec() + 35000
	while str(app.get_launch_state().status) in ["idle", "loading"] and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(str(app.get_launch_state().status) == "ready", "actual Main launch completes ordinary terrain readiness")
	if str(app.get_launch_state().status) != "ready": return false
	await frames(18)
	app.player.wheel_tool_direction = 1
	app.session.unlimited_ammo = false
	app.player.head.rotation.x = PI * .5
	return true

func full_flow() -> void:
	if not await launch(true): return
	var coordinator: ArsenalCoordinator = app.arsenal_coordinator
	var runtime: ArsenalRuntime = coordinator.runtime
	var session: LocalSession = app.session
	var panel: ArsenalPanel = coordinator.panel
	check(coordinator._loadout.get("all_items", false) and runtime.readout().loadout.get("all_items", false) and selected() == "x01", "canonical full metadata reaches one live lab runtime")
	var cycle: Array[String] = CATALOG.inventory_cycle()
	check(cycle.size() == 21 and cycle[20] == "source", "stable full inventory includes twenty authored IDs and one original-class backup")
	for index: int in 20:
		check(cycle[index] == "x%02d" % (index+1) and runtime.equipped(cycle[index]), "full runtime exposes ordered authored identity " + cycle[index])
	var intent_counts: Dictionary = {"select":0, "apply":0, "loadout":0}
	panel.item_selected.connect(func(_id: String) -> void: intent_counts.select += 1)
	panel.apply_requested.connect(func(_id: String) -> void: intent_counts.apply += 1)
	panel.loadout_changed.connect(func(_kit: Dictionary) -> void: intent_counts.loadout += 1)
	var stock: Dictionary = runtime.readout().stock.duplicate(true)
	var source_clip: int = session.magazine
	var source_reserve: int = session.reserve
	for index: int in range(1,22):
		wheel()
		await frames(2)
		check(selected() == cycle[index%21] and panel.get_display_state().selected_item == cycle[index%21], "Viewport wheel selects stable full-cycle identity " + cycle[index%21])
		check(session.current_weapon == 1 and session.current_tool == LocalSession.Tool.WEAPON and runtime.readout().stock == stock, "full wheel keeps the original SMG enum/tool and never deploys stock")
	check(selected() == "x01" and not runtime.has_pending() and session.magazine == source_clip and session.reserve == source_reserve, "complete21-step wrap selects only and leaves both authorities' finite resources intact")
	check(intent_counts == {"select":0,"apply":0,"loadout":0}, "silent panel wheel synchronization cannot emit recursive selection, deployment or preference intents")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(selected() == "source" and not app.player.uses_arsenal() and session.current_weapon == 1, "reverse wrap selects the existing original-class backup")
	check(LOADOUT.load_saved().enabled and LOADOUT.load_saved().loadout.get("all_items", false), "full Lab source backup retains saved enabled full inventory")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(selected() == "x20", "reverse wheel leaves source backup for the final authored item")
	app.player.wheel_tool_direction = -1
	wheel()
	check(selected() == "x19", "negative existing wheel preference reverses wheel-up direction")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(selected() == "x20", "negative preference also reverses wheel-down direction")
	app.player.wheel_tool_direction = 0
	wheel()
	check(selected() == "x20" and session.current_tool == LocalSession.Tool.WEAPON, "zero wheel preference consumes full wheel without a classic-tool fallback")
	app.player.wheel_tool_direction = 1
	app.hud.set_mobile_controls_mode(1)
	await frames(8)
	check(app.hud.uses_mobile_controls() and app.hud.mobile_controls._enabled, "real touch HUD is active during desktop wheel input")
	wheel()
	check(selected() == "source", "full wheel works before the actual touch-HUD mouse suppression guard")
	wheel()
	check(selected() == "x01" and app.player.uses_arsenal(), "touch HUD still allows wheel wrap from source into authored primary")
	app.hud.set_mobile_controls_mode(0)
	await frames(8)
	# Charge is real held input, canceled by the wheel before the72-tick shot.
	var custom_clip: int = int(runtime.readout().magazine)
	var sequence: int = app.world.data.map_sequence
	action("primary", true)
	await frames(12)
	check(float(runtime.readout().charge) > 0 and int(runtime.readout().magazine) == custom_clip, "real gauss input enters an uncommitted partial charge")
	wheel()
	check(selected() == "x02" and not Input.is_action_pressed("primary") and not runtime._trigger and not runtime._release and runtime._charge == 0, "wheel selection cancels held charge and pending combat release")
	await frames(74)
	check(not runtime.has_pending() and app.world.data.map_sequence == sequence and int(runtime.readout().magazine) == int(CATALOG.get_item("x02").clip), "old held charge cannot fire a delayed shot or automatically fire the newly selected item")
	wheel_to("x01")
	check(int(runtime.readout().magazine) == custom_clip, "return to canceled charged primary preserves its finite magazine")
	wheel_to("x08")
	custom_clip = int(runtime.readout().magazine)
	action("primary", true)
	await frames(3)
	check(int(runtime.readout().magazine) < custom_clip and runtime._trigger, "real vacuum input consumes bounded active fuel before selection")
	var vacuum_clip: int = int(runtime.readout().magazine)
	wheel()
	await frames(8)
	check(selected() == "x09" and not runtime._release and not runtime._trigger and not runtime.has_pending(), "wheel cancels vacuum input without creating a release push or foam placement")
	wheel_to("x08")
	check(int(runtime.readout().magazine) == vacuum_clip, "vacuum roundtrip does not refill spent fuel")
	wheel_to("x03")
	custom_clip = int(runtime.readout().magazine)
	action("primary", true)
	await frames(3)
	action("primary", false)
	check(int(runtime.readout().magazine) == custom_clip-1 and session.magazine == source_clip, "actual Paperclip fire consumes custom ammunition through Player and leaves original SMG stock intact")
	for index: int in 21: wheel()
	await frames(8)
	check(selected() == "x03" and int(runtime.readout().magazine) == custom_clip-1 and runtime.readout().stock == stock, "spent primary magazine survives a complete21-item wheel roundtrip")
	# One actual Sun action verifies finite auxiliary stock survives selection.
	wheel_to("x16")
	var direction: Vector3 = (app.player.global_position + Vector3(12,-.02,0) - app.player.get_aim_origin()).normalized()
	app.player.rotation.y = atan2(-direction.x,-direction.z)
	app.player.head.rotation.x = asin(clampf(direction.y,-1,1))
	action("primary", true)
	action("primary", false)
	await frames(2)
	check(int(runtime.readout().stock.x16) == 0 and runtime.has_pending(), "actual full-inventory primary action admits one finite Sun fuse")
	for index: int in 21: wheel()
	check(selected() == "x16" and int(runtime.readout().stock.x16) == 0, "wheel roundtrip cannot refill or redeploy the spent one-off bomb")
	var gate_selection: String = selected()
	app.hud.set_menu_visible(true)
	await frames(8)
	wheel()
	check(app.hud.is_menu_open() and not app.player.controls_enabled and selected() == gate_selection and session.current_tool == LocalSession.Tool.WEAPON, "actual user pause prevents inventory selection and source-tool fallback")
	app.hud.set_menu_visible(false)
	await frames(8)
	panel._catalog.pressed.emit()
	await frames(8)
	wheel()
	check(coordinator.is_catalog_open() and selected() == gate_selection and session.current_tool == LocalSession.Tool.WEAPON, "actual catalogue scrolling cannot alter the paused combat inventory")
	panel._close_button.pressed.emit()
	await frames(8)
	app.hud.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	wheel()
	check(not app.player.controls_enabled and selected() == gate_selection, "real window focus loss blocks full inventory selection")
	app.hud.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await frames(8)
	# Inject the Main readiness gate synchronously, without a fake authority step.
	var saved_status: String = app._launch_status
	var saved_loading: bool = app._launch_in_progress
	app._launch_status = "loading"
	app._launch_in_progress = true
	wheel()
	check(selected() == gate_selection and session.current_tool == LocalSession.Tool.WEAPON, "Main loading/readiness gate consumes full wheel without changing either selection path")
	app._launch_status = saved_status
	app._launch_in_progress = saved_loading
	session.invulnerable = false
	session.damage_player(1000, app.player.global_position, "fixture")
	await frames(2)
	wheel()
	check(session.health == 0 and selected() == gate_selection and runtime.visuals().is_empty() and not runtime.readout().enabled, "actual mortal lab death blocks wheel and cancels old-life finite bomb")
	await close_scene()

func legacy_flow() -> void:
	if not await launch(false): return
	var coordinator: ArsenalCoordinator = app.arsenal_coordinator
	var session: LocalSession = app.session
	check(not coordinator._loadout.has("all_items") and session.current_tool == LocalSession.Tool.WEAPON, "legacy four-slot launch keeps the optional full flag absent")
	var old: String = selected()
	wheel()
	check(session.current_tool == LocalSession.Tool.GRENADE and selected() == old and session.current_weapon == 1, "full-off wheel retains the existing original four-tool cycle and three-class enum")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(session.current_tool == LocalSession.Tool.WEAPON and selected() == old, "reverse full-off wheel returns to the source weapon tool")
	app.player.wheel_tool_direction = 0
	wheel()
	check(session.current_tool == LocalSession.Tool.WEAPON and selected() == old, "disabled existing wheel preference also retains legacy behavior")
	app.player.wheel_tool_direction = 1
	coordinator.panel._catalog.pressed.emit()
	await frames(8)
	coordinator.panel._all_items.pressed.emit()
	await frames(18)
	check(coordinator._loadout.get("all_items", false) and coordinator.runtime.readout().loadout.get("all_items", false) and LOADOUT.load_saved().loadout.get("all_items", false), "actual Lab catalogue toggle immediately enables canonical and saved full inventory")
	check(coordinator._pending_loadout.is_empty(), "Lab full toggle applies immediately rather than creating a next-attempt promise")
	coordinator.panel._close_button.pressed.emit()
	await frames(8)
	wheel()
	check(selected() == "x02" and session.current_tool == LocalSession.Tool.WEAPON, "newly enabled Lab inventory changes the next actual wheel to authored selection")
	await close_scene()

func run() -> void:
	var window: Dictionary = {"size":root.size,"scale_size":root.content_scale_size,"scale_mode":root.content_scale_mode,"scale_aspect":root.content_scale_aspect}
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for path: String in [MAPS.SETTINGS_PATH,LOADOUT.PATH]: backup(path)
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("profile","locale","ru")
	preferences.set_value("ui","touch_controls",2)
	check(preferences.save(MAPS.SETTINGS_PATH) == OK, "private input fixture profile is seeded")
	await full_flow()
	await close_scene()
	await legacy_flow()
	await close_scene()
	if has_meta("blockfield_launch"): remove_meta("blockfield_launch")
	LabInputBindings.release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restore()
	root.size = window.size
	root.content_scale_size = window.scale_size
	root.content_scale_mode = window.scale_mode
	root.content_scale_aspect = window.scale_aspect
	print("FULL ARSENAL INPUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
