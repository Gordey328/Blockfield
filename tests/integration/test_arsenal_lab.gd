extends SceneTree
## Actual training scene: fixed authority, ordinary source controls and life/map seams.
## This fixture establishes native behavior, not Web rendering or phone acceptance.
const SCENE = preload("res://scenes/main.tscn")
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const LOADOUT = preload("res://gameplay/arsenal_loadout.gd")
const MAPS = preload("res://ui/map_catalog.gd")
var checks: int = 0
var failures: int = 0
var app: Node3D
var backups: Dictionary[String, Dictionary] = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ARSENAL LAB: " + label)

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

func aim_at(point: Vector3) -> void:
	var direction: Vector3 = (point - app.player.get_aim_origin()).normalized()
	app.player.rotation.y = atan2(-direction.x, -direction.z)
	app.player.head.rotation.x = asin(clampf(direction.y, -1, 1))

func backup(path: String) -> void:
	backups[path] = {"exists":FileAccess.file_exists(path), "bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func restore() -> void:
	for path: String in backups:
		if bool(backups[path].exists):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			check(file != null, "private preferences can be restored")
			if file != null:
				file.store_buffer(backups[path].bytes)
				file.close()
		elif FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "fixture-only preference file is removed")

func exercise() -> void:
	var loadout: Dictionary = {"primary":"x03", "bomb":"x12", "stratagems":["x17","x20"]}
	set_meta("blockfield_launch", {"mode":"training", "map_id":"lab", "weapon":1, "arsenal":loadout})
	app = SCENE.instantiate()
	root.add_child(app)
	current_scene = app
	var deadline: int = Time.get_ticks_msec() + 35000
	while str(app.get_launch_state().status) in ["idle", "loading"] and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(str(app.get_launch_state().status) == "ready", "explicit training metadata reaches actual Main readiness")
	if str(app.get_launch_state().status) != "ready": return
	await frames(8)
	var session: LocalSession = app.session
	var coordinator: ArsenalCoordinator = app.arsenal_coordinator
	var runtime: ArsenalRuntime = coordinator.runtime
	var bridge: ArsenalBridge = coordinator.bridge
	var terrain: RefCounted = bridge.terrain
	var data: VoxelData = app.world.data
	check(not app.offline_tdm_mode and coordinator.enabled and session.arsenal == runtime and app.player.uses_arsenal(), "actual lab uses optional string-ID equipment alongside the original session")
	check(bridge.data == data and bridge.simulation() == null and session.current_weapon == 1, "lab keeps one map and the original SMG enum outside MatchSimulation")
	session.invulnerable = false
	session.unlimited_ammo = false
	check(not session.invulnerable and not session.unlimited_ammo, "fixture uses finite resources and ordinary mortality")
	# Suspend only Main's render update and automatic coordinator physics. Manual
	# calls below are exactly two fixed steps, independent of session_time/render.
	app.set_process(false)
	coordinator.set_physics_process(false)
	var render_clock: float = session.session_time
	var before: int = int(runtime.readout().tick)
	var host: int = bridge.tick()
	coordinator._physics_process(1.0 / 60.0)
	coordinator._physics_process(1.0 / 60.0)
	check(int(runtime.readout().tick) == before + 2 and bridge.tick() == host + 2 and session.session_time == render_clock, "two actual coordinator physics steps advance authority exactly twice with Main render/session update disabled")
	app.hud.set_menu_visible(true)
	var paused: int = int(runtime.readout().tick)
	coordinator._physics_process(1.0 / 60.0)
	coordinator._physics_process(1.0 / 60.0)
	check(int(runtime.readout().tick) == paused and not app.player.controls_enabled, "ordinary user pause stops lab authority independently of the render update")
	app.hud.set_menu_visible(false)
	await frames(8)
	coordinator.panel._catalog.pressed.emit()
	check(coordinator.is_catalog_open(), "actual arsenal Browse opens the lab modal")
	paused = int(runtime.readout().tick)
	coordinator._physics_process(1.0 / 60.0)
	coordinator._physics_process(1.0 / 60.0)
	check(int(runtime.readout().tick) == paused and not app.player.controls_enabled, "catalogue modal stops lab fixed authority and releases the trigger")
	coordinator.panel._close_button.pressed.emit()
	await frames(2)
	coordinator.set_physics_process(true)
	app.player.head.rotation.x = PI * .5
	var clip: int = session.magazine
	var custom_clip: int = int(runtime.readout().magazine)
	action("primary", true)
	await frames(3)
	action("primary", false)
	check(int(runtime.readout().magazine) == custom_clip - 1 and session.magazine == clip and session.session_time == render_clock, "real lab primary input fires finite custom ammunition on fixed ticks without original fire or a render-driven clock")
	app.set_process(true)
	# Return source controls through the actual Classic button. Source shooting
	# and tool hotkeys must still use their original three-class/profile path.
	coordinator.panel._source.pressed.emit()
	await frames(3)
	check(coordinator.source_selected and not app.player.uses_arsenal(), "actual Classic button restores source equipment selection")
	for frame: int in 70:
		if app.player.can_use_tool(): break
		await frames(1)
	clip = session.magazine
	action("primary", true)
	await frames(3)
	action("primary", false)
	check(session.magazine < clip and session.current_weapon == 1, "ordinary lab source SMG fire still consumes its own magazine")
	action("tool_spade", true)
	action("tool_spade", false)
	await frames(2)
	check(session.current_tool == LocalSession.Tool.SPADE, "original spade hotkey remains available after custom/source switching")
	action("tool_weapon", true)
	action("tool_weapon", false)
	await frames(2)
	coordinator._select("x03")
	await frames(8)
	coordinator.panel._apply.button_down.emit()
	await frames(1)
	check(coordinator._panel_trigger and coordinator.panel._firing, "actual panel Fire holds its override before window focus loss")
	var focus_tick: int = int(runtime.readout().tick)
	var focus_clip: int = int(runtime.readout().magazine)
	app.hud.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	coordinator.prepare_trigger(true)
	check(not app.hud._focused and not app.player.controls_enabled and not coordinator._panel_trigger and not coordinator._mouse_bank_held and not runtime._trigger, "real HUD window-focus notification cancels battle input and held panel override")
	await frames(8)
	check(int(runtime.readout().tick) == focus_tick and int(runtime.readout().magazine) == focus_clip and not coordinator.panel._firing and not coordinator.panel._bank.visible, "unfocused lab pauses new fixed steps and releases/hides actual panel Fire")
	app.hud.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await frames(40)
	check(app.hud._focused and app.player.controls_enabled and coordinator.panel._bank.visible and int(runtime.readout().tick) > focus_tick, "actual focus restoration resumes controls and the live lab timeline")
	check(int(runtime.readout().magazine) == focus_clip and not coordinator._panel_trigger and not runtime._trigger, "focus restoration does not resurrect the old held Fire after its cooldown elapses")
	coordinator.panel._apply.button_up.emit()
	coordinator._select("x16")
	# This distant supported ground target remains outside the blast radius. The
	# owner will die before the four-second fuse, exercising real cancellation.
	var point: Vector3 = app.player.global_position + Vector3(12, -.02, 0)
	aim_at(point)
	coordinator._apply("x16")
	await frames(2)
	check(int(runtime.readout().stock.x16) == 0 and runtime.has_pending(), "actual lab application consumes its one Pocket sun and starts finite ordnance")
	coordinator._select("x03")
	coordinator._select("x16")
	check(int(runtime.readout().stock.x16) == 0, "changing selected equipment does not replenish one-off ordnance")
	coordinator._select("x03")
	var permanent: Vector3i = Vector3i(5, 4, 75)
	var disposable: Vector3i = Vector3i(14, 4, 75)
	var foam: Array[Vector3i] = [Vector3i(8,4,75), Vector3i(8,5,75), Vector3i(8,6,75)]
	check(data.get_block(permanent) == 0 and data.get_block(disposable) == 0 and bridge._foam_clear(foam[0]), "fixture edits are grounded and away from the owner/targets")
	app.world.set_block(permanent, 0x01996644)
	app.world.set_block(disposable, 0x01eeaa77)
	var placed: Dictionary = terrain.queue_place(foam, 0x0144ddff, bridge.tick() + 720, bridge.metadata(), Callable(bridge,"_foam_clear"))
	check(placed.ok, "real canonical temporary foam is admitted with live actor clearance")
	await frames(2)
	check(data.get_block(foam[2]) == 0x0144ddff and int(terrain.get_diagnostics().foam_cells) == 3, "real owned foam exists before the ordinary death")
	check(bridge.remove([disposable]).ok, "existing bounded canonical removal remains pending at the death boundary")
	var epoch: int = data.epoch
	var deaths: int = session.player_deaths
	session.damage_player(1000, app.player.global_position, "fixture")
	await frames(8)
	check(session.health == 0 and session.player_deaths == deaths + 1, "ordinary lab damage creates a real mortal life transition")
	check(coordinator.bridge == bridge and bridge.terrain == terrain and app.world.data == data and data.epoch == epoch, "death keeps the same bridge, helper and canonical map")
	check(data.get_block(permanent) == 0x01996644 and data.get_block(disposable) == 0 and int(terrain.get_diagnostics().foam_cells) == 0, "death safely expires owned foam/completes committed removal and preserves ordinary built terrain")
	check(runtime.visuals().is_empty(), "death cancels the uncommitted large bomb rather than executing its stale fuse")
	deadline = Time.get_ticks_msec() + 5000
	while session.health == 0 and Time.get_ticks_msec() < deadline:
		await frames(1)
	await frames(2)
	check(session.health == 100 and session.respawn_remaining == 0.0, "the existing three-second LocalSession clock performs ordinary respawn")
	check(coordinator.bridge == bridge and bridge.terrain == terrain and app.world.data == data and data.get_block(permanent) == 0x01996644, "ordinary respawn preserves built terrain and existing terrain authority")
	check(runtime.readout().enabled and int(runtime.readout().stock.x16) == 1 and app.player.uses_arsenal(), "ordinary new life re-enables custom inventory through the same bridge")
	# Explicit adoption is distinct from death: replace this map in-place while
	# retaining its epoch, then exercise the generation guard through Main/World.
	app.hud.set_menu_visible(true)
	var generation: int = data.generation
	check(data.clear(data.dimensions, epoch) == OK, "explicit same-epoch fixture map replacement succeeds")
	data.seed_box(Vector3i.ZERO, Vector3i(96,4,96), 0x0179694c)
	check(app.world.set_map_data(data, "Same-data lab generation reset", true) == OK, "World publicly adopts the explicitly replaced canonical data")
	await frames(2)
	check(coordinator.bridge != bridge and coordinator.runtime != runtime and coordinator.bridge.data == data and data.epoch == epoch and data.generation > generation, "same Data/same epoch generation change binds a fresh bridge/runtime")
	check(bridge.data == null and int(terrain.get_diagnostics().foam_cells) == 0 and int(terrain.get_diagnostics().guard_cells) == 0, "old adoption disposes ownership/guards and releases its data reference")
	check(coordinator.runtime.visuals().is_empty() and int(coordinator.runtime.readout().stock.x16) == 1 and data.get_block(permanent) == 0, "explicit map replacement resets new effects/resources and is the only operation that restores terrain")

func run() -> void:
	var window: Dictionary = {"size":root.size, "scale_size":root.content_scale_size, "scale_mode":root.content_scale_mode, "scale_aspect":root.content_scale_aspect}
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for path: String in [MAPS.SETTINGS_PATH, LOADOUT.PATH]: backup(path)
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("ui", "touch_controls", 2)
	check(preferences.save(MAPS.SETTINGS_PATH) == OK, "private lab profile is seeded")
	await exercise()
	LabInputBindings.release_actions()
	if is_instance_valid(app): app.queue_free()
	await frames(3)
	if has_meta("blockfield_launch"): remove_meta("blockfield_launch")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restore()
	root.size = window.size
	root.content_scale_size = window.scale_size
	root.content_scale_mode = window.scale_mode
	root.content_scale_aspect = window.scale_aspect
	print("ARSENAL LAB: %d checks, %d failures" % [checks, failures])
	OS.delay_msec(80)
	quit(1 if failures else 0)
