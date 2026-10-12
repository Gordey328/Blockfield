extends SceneTree
## Real scene/input/session/AI seams; headless results do not accept Web pixels or phones.
const SCENE = preload("res://scenes/offline_survival.tscn")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const LOADOUT = preload("res://gameplay/arsenal_loadout.gd")
const RECORDS = preload("res://gameplay/rush_records.gd")
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
		push_error("ARSENAL SCENE: " + label)

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

func touch(button: Button, pressed: bool, index: int = 19) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = button.get_global_rect().get_center()
	event.pressed = pressed
	event.window_id = root.get_window_id()
	# Use the real Viewport adapter with logical pixels. Headless Windows retain
	# a different physical input scale; parse_input_event would rescale twice.
	root.push_input(event, true)

func backup(path: String) -> void:
	backups[path] = {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func restore() -> void:
	for path: String in backups:
		if bool(backups[path].exists):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			check(file != null, "private fixture backup can be restored")
			if file != null:
				file.store_buffer(backups[path].bytes)
				file.close()
		elif FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "fixture-only persisted file is removed")

func close_scene() -> void:
	LabInputBindings.release_actions()
	if is_instance_valid(app): app.queue_free()
	await frames(3)
	app = null

func launch(loadout: Dictionary) -> bool:
	set_meta("blockfield_launch", {"mode": "survival", "map_id": "crossroads", "weapon": 1, "survival": SETTINGS.rush_defaults(), "arsenal": loadout.duplicate(true)})
	app = SCENE.instantiate()
	root.add_child(app)
	current_scene = app
	await wait_ready("arsenal scene launch")
	if str(app.get_launch_state().status) != "ready": return false
	var coordinator: ArsenalCoordinator = app.arsenal_coordinator
	check(coordinator != null and coordinator.enabled and app.player.arsenal_runtime == coordinator.runtime and app.session.arsenal == coordinator.runtime, "ordinary metadata binds one runtime to player, local authority and coordinator")
	check(app._launch_configuration.get("arsenal", {}) == CATALOG.canonical_loadout(loadout) and app.session.arsenal_loadout == CATALOG.canonical_loadout(loadout), "validated canonical loadout survives Main and records authority")
	check(app.world.data == coordinator.bridge.data and app.world.data == app.session.simulation.data, "rendering, new arsenal and original rules adopt exactly one VoxelData")
	return coordinator != null and coordinator.enabled

func wait_ready(label: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 35000
	while str(app.get_launch_state().status) in ["idle", "loading"] and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(str(app.get_launch_state().status) == "ready", label + " completes preparation")
	if str(app.get_launch_state().status) == "ready":
		check(app.world.get_visual_preparation_stats().ready and not app.session.paused and app.player.controls_enabled, "ready terrain opens battle authority and input together")
		await frames(8)

func aim_at(point: Vector3) -> void:
	var direction: Vector3 = (point - app.player.get_aim_origin()).normalized()
	app.player.rotation.y = atan2(-direction.x, -direction.z)
	app.player.head.rotation.x = asin(clampf(direction.y, -1, 1))

func clear_near(session: OfflineSurvivalSession, distance: float) -> Vector3:
	var owner: Vector3 = session.get_owner_state().feet()
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var point: Vector3 = owner + direction * distance
		var floor_cell: Vector3i = Vector3i(point.floor()) + Vector3i.DOWN
		if session.simulation.data.get_block(floor_cell) != 0 and session.simulation._spawn_clear(point) and app.arsenal_coordinator.bridge.line_clear(owner + Vector3.UP * 1.25, point + Vector3.UP * 1.25): return point
	return Vector3.INF

func brain_state(session: OfflineSurvivalSession, id: int) -> String:
	for row: Dictionary in session._zombie_director.get_diagnostics().bots:
		if int(row.actor_id) == id: return str(row.state)
	return "missing"

func apply_compact(slot: int) -> void:
	var panel: ArsenalPanel = app.arsenal_coordinator.panel
	for frame: int in 30:
		if panel._enabled and panel._combat_visible and panel._bank.is_visible_in_tree(): break
		await frames(1)
	check(panel._enabled and panel._combat_visible and panel._bank.is_visible_in_tree(), "actual compact bank is available after modal resume before selection")
	var item: String = panel._slot_item(slot)
	panel._slots[slot].pressed.emit()
	await frames(8)
	check(app.arsenal_coordinator.runtime.selected_item == item, "actual equipped compact button selects its intended item: " + item)
	for frame: int in 150:
		if not panel._apply.disabled: break
		await frames(1)
	panel._apply.pressed.emit()
	if slot >= 2:
		check(panel.get_display_state().targeting, "support first compact action enters confirmation without spending")
		panel._apply.pressed.emit()
	await frames(2)

func main_flow() -> void:
	if not await launch(CATALOG.defaults()): return
	var session: OfflineSurvivalSession = app.session
	var coordinator: ArsenalCoordinator = app.arsenal_coordinator
	var runtime: ArsenalRuntime = coordinator.runtime
	var panel: ArsenalPanel = coordinator.panel
	check(session.phase == "preparation", "custom equipment starts in ordinary five-second countdown")
	var source_clip: int = session.magazine
	var initial_custom: int = int(runtime.readout().magazine)
	action("primary", true)
	await frames(74)
	action("primary", false)
	check(int(runtime.readout().magazine) == initial_custom - 1 and session.magazine == source_clip, "actual charged custom Fire consumes one new round and suppresses original SMG fire")
	check(int(runtime.readout().tick) > 60 and session.phase == "preparation", "arsenal clocks advance with ordinary countdown authority")
	app.hud.set_mobile_controls_mode(1)
	await frames(8)
	check(app.hud.mobile_controls._enabled, "real touch controls admit the active custom loadout")
	var mobile_clip: int = int(runtime.readout().magazine)
	await frames(25)
	touch(panel._apply, true)
	check(coordinator._panel_trigger and panel._firing, "viewport ScreenTouch claims the actual compact Fire button")
	await frames(74)
	touch(panel._apply, false)
	check(int(runtime.readout().magazine) == mobile_clip - 1 and session.magazine == source_clip, "ScreenTouch through actual arsenal Fire claims hold/release and consumes only custom ammunition")
	check(not coordinator._panel_trigger and not panel._firing, "touch release does not leave a primary action held")
	panel._catalog.pressed.emit()
	await frames(2)
	check(coordinator.is_catalog_open() and session.paused and not app.player.controls_enabled and not app.hud.mobile_controls._enabled, "actual catalogue claims the modal and releases battle/mobile controls")
	var catalog_tick: int = session.simulation.tick
	var catalog_runtime_tick: int = int(runtime.readout().tick)
	var reached: Array[String] = []
	for category: String in ["primary", "bomb", "stratagem"]:
		panel._tabs[category].pressed.emit()
		for id: String in panel.get_display_state().visible_ids:
			reached.append(id)
			check(panel._cards[id].is_visible_in_tree() and not panel._cards[id].disabled, "authored card is reachable in its actual category: " + id)
	check(reached.size() == 20 and panel.get_display_state().catalog_count == 20, "twenty unique equipment cards are reachable through three real category buttons")
	for ordinal: int in range(1, 21):
		check(reached.has("x%02d" % ordinal), "stable authored identity is reachable: x%02d" % ordinal)
	await frames(6)
	check(session.simulation.tick == catalog_tick and int(runtime.readout().tick) == catalog_runtime_tick, "catalogue modal freezes both clocks")
	action("pause", true)
	action("pause", false)
	await frames(2)
	check(not coordinator.is_catalog_open() and not app.hud.is_menu_open() and not session.paused and app.player.controls_enabled, "Escape closes catalogue once and resumes without opening another modal")
	panel._reload.pressed.emit()
	await frames(153)
	check(int(runtime.readout().magazine) == int(CATALOG.get_item("x01").clip) and int(runtime.readout().reserve) < int(CATALOG.get_item("x01").reserve), "actual new Reload draws from finite reserve")
	# Two fixture deaths prime the real Rush threshold. The final death below is
	# caused by the ordinary charged weapon/input path, not a direct fixture kill.
	var point: Vector3 = clear_near(session, 7.0)
	check(point.is_finite(), "supported visible nearby zombie position exists")
	if not point.is_finite(): return
	for life: int in 2:
		check(session.simulation.spawn_zombie_slot(12, point).ok, "real reusable zombie slot admitted for threshold")
		session.simulation.damage_actor(12, 100, 1, "fixture")
		await frames(2)
	check(session.simulation.spawn_zombie_slot(12, point).ok, "new generation admitted for actual custom hit")
	var victim: SharedPlayerState = session.simulation.get_actor(12)
	session.simulation.damage_actor(12, 75, 0, "fixture")
	aim_at(victim.feet() + Vector3.UP * 1.25)
	panel._slots[0].pressed.emit()
	await frames(8)
	# Auxiliary intents start before the charge. They create real pending pop
	# children/jet fuel at the eventual seventy-two-tick killing-shot boundary.
	coordinator._apply("x12")
	coordinator._apply("x20")
	action("primary", true)
	for tick: int in 110:
		if not victim.is_alive() or session.get_rush_state().pending: break
		aim_at(victim.feet() + Vector3.UP * 1.25)
		await frames(1)
	action("primary", false)
	await frames(2)
	check(not victim.is_alive() and int(session.get_rush_state().kills) >= 3 and session.get_rush_state().pending, "actual charged custom death receives kill credit and produces a real Rush choice")
	if not session.get_rush_state().pending: return
	check(int(runtime.readout().stock.x12) == 1 and int(runtime.readout().stock.x20) == 1 and runtime.has_pending(), "queued bomb/jet resources are finite and effects survive up to the choice boundary")
	var frozen: Dictionary = runtime.readout().duplicate(true)
	var visuals: Array[Dictionary] = runtime.visuals()
	var frozen_tick: int = session.simulation.tick
	await frames(12)
	check(session.simulation.tick == frozen_tick and runtime.readout() == frozen and runtime.visuals() == visuals, "Rush choice freezes new fuses, flight, fuel, cooldowns and resources")
	check(not app.player.controls_enabled and not app.hud.mobile_controls._enabled and app.hud._rush_panel.is_visible_in_tree(), "actual choice claims desktop/touch battle input")
	var stock: Dictionary = runtime.readout().stock.duplicate()
	check(session.choose_upgrade("field_kit").ok, "actual offered field kit is accepted by local authority")
	await frames(2)
	check(runtime.readout().stock == stock and int(runtime.readout().reserve) == int(CATALOG.get_item("x01").reserve), "field kit restores primary reserve and never restores consumed bomb/support stocks")
	# Actual compact selection/confirmation must work independently of the source
	# three-class enum. Aim at a supported, distant point to avoid self-damage.
	aim_at(point + Vector3.DOWN * .02)
	var drill_stock: int = int(runtime.readout().stock.x17)
	await apply_compact(2)
	check(int(runtime.readout().stock.x17) == drill_stock - 1 and runtime.has_pending(), "equipped support selection plus actual Confirm spends one delayed drill call")
	app.hud.set_menu_visible(true)
	var paused: Dictionary = runtime.readout().duplicate(true)
	var pause_tick: int = session.simulation.tick
	await frames(8)
	check(session.paused and runtime.readout() == paused and session.simulation.tick == pause_tick, "ordinary pause freezes delayed support and new resources")
	app.hud._survival_panel._resume.pressed.emit()
	await frames(2)
	check(not session.paused, "actual Resume restores arsenal authority")
	await apply_compact(1)
	check(int(runtime.readout().stock.x12) == 0, "equipped bomb compact selection and actual Throw consume the final charge")
	# A real mid-run card change is saved for the next attempt. The source kit
	# remains a backup in this frozen run and must not overwrite that preference.
	var next_loadout: Dictionary = CATALOG.defaults()
	next_loadout.primary = "x03"
	panel._catalog.pressed.emit()
	await frames(2)
	panel._tabs.primary.pressed.emit()
	panel._cards.x03.pressed.emit()
	await frames(2)
	check(coordinator._pending_loadout == next_loadout and LOADOUT.load_saved().loadout == next_loadout and LOADOUT.load_saved().enabled, "real mid-run catalogue card saves the next canonical loadout")
	check(session.arsenal_loadout == CATALOG.defaults() and coordinator._frozen_loadout == CATALOG.defaults() and runtime.equipped("x01") and not runtime.equipped("x03"), "mid-run choice cannot change current equipped rules or scoring identity")
	panel._close_button.pressed.emit()
	await frames(8)
	panel._source.pressed.emit()
	await frames(2)
	check(coordinator.source_selected and not app.player.uses_arsenal() and LOADOUT.load_saved().enabled and LOADOUT.load_saved().loadout == next_loadout, "actual source backup selection preserves the saved next-attempt equipment")
	session.simulation.damage_actor(1, 1000, 0, "fixture")
	await frames(3)
	check(session.finished and session.outcome == "defeat", "real owner death closes the custom Rush run")
	check(runtime.visuals().is_empty() and not runtime.readout().enabled and runtime._queue.is_empty() and runtime._status.is_empty(), "terminal owner death immediately cancels visuals, queued actions and statuses without another authority step")
	check(RECORDS.arsenal_best(CATALOG.defaults()) == int(session.get_rush_state().score) and RECORDS.best(1) == 0, "finished custom scene records only the new full-loadout bucket")
	check(RECORDS.arsenal_best(next_loadout) == 0, "old run finish cannot contaminate the newly selected kit's record")
	var stored: ConfigFile = ConfigFile.new()
	stored.load(RECORDS.PATH)
	stored.set_value("rush_arsenal_v1", LOADOUT.fingerprint(CATALOG.defaults()), 0)
	stored.save(RECORDS.PATH)
	for index: int in 3: app.hud._update_survival_status()
	check(RECORDS.arsenal_best(CATALOG.defaults()) == 0, "HUD writes each actual finish once per epoch, independently of later refreshes")
	var old_runtime: ArsenalRuntime = runtime
	var epoch: int = session.simulation.epoch
	app.hud._survival_panel._restart.pressed.emit()
	check(not app.player.controls_enabled and session.paused, "actual repeat closes authority/input before restored map readiness")
	await wait_ready("custom Rush repeat")
	check(session.simulation.epoch > epoch and coordinator.runtime != old_runtime and coordinator.runtime.visuals().is_empty(), "epoch restart installs a fresh runtime and cancels all old ordnance/statuses")
	check(coordinator._pending_loadout.is_empty() and session.arsenal_loadout == next_loadout and coordinator.runtime.selected_item == "x03" and not coordinator.source_selected, "actual Replay adopts and selects the saved next kit while clearing its pending change")
	check(LOADOUT.fingerprint(session.arsenal_loadout, "crossroads", session.current_weapon) != LOADOUT.fingerprint(CATALOG.defaults(), "crossroads", 1), "next attempt uses the new full-loadout/source-class record identity")
	check(coordinator.runtime.readout().stock == {"x01":0,"x02":0,"x03":0,"x04":0,"x05":0,"x06":0,"x07":0,"x08":0,"x09":0,"x10":0,"x11":3,"x12":2,"x13":1,"x14":2,"x15":3,"x16":1,"x17":2,"x18":2,"x19":2,"x20":2}, "explicit new attempt replenishes exactly the authored starting stocks")
	check(session.simulation.spawn_zombie_slot(12, point).ok, "new-kit attempt admits a counted scoring life")
	session.simulation.damage_actor(12,1000,1,"fixture")
	await frames(2)
	session.simulation.damage_actor(1,1000,0,"fixture")
	await frames(3)
	check(RECORDS.arsenal_best(next_loadout, "crossroads", RECORDS.PATH, 1) == int(session.get_rush_state().score) and RECORDS.arsenal_best(CATALOG.defaults()) == 0 and RECORDS.best(1) == 0, "next attempt writes only its selected new-kit bucket after an actual finish")
	await close_scene()

func ai_flow() -> void:
	var loadout: Dictionary = {"primary":"x05", "bomb":"x14", "stratagems":["x17","x20"]}
	if not await launch(loadout): return
	var session: OfflineSurvivalSession = app.session
	var coordinator: ArsenalCoordinator = app.arsenal_coordinator
	var runtime: ArsenalRuntime = coordinator.runtime
	var near: Vector3 = clear_near(session, 1.6)
	var far: Vector3 = clear_near(session, 8.0)
	check(near.is_finite() and far.is_finite(), "AI fixture uses supported visible real-map positions")
	if not near.is_finite() or not far.is_finite(): return
	check(session.simulation.spawn_zombie_slot(12, near).ok and session.simulation.spawn_zombie_slot(13, far).ok, "real near/far zombie generations are admitted")
	await frames(2)
	check(session._attacks.has(12), "near zombie begins a real bite windup before the lure")
	if not session._attacks.has(12): return
	var started: int = int(session._attacks[12].started)
	var lure_point: Vector3 = far + (far - session.get_owner_state().feet()).normalized() * 3.0
	aim_at(lure_point + Vector3.DOWN * .02)
	coordinator._apply("x14")
	await frames(3)
	check(brain_state(session,13) == "decoy" and runtime.lure_target(session.simulation.get_actor(13).motion.physics_eye()).is_finite(), "actually deployed disco changes a reachable zombie's production AI target")
	check(session._attacks.has(12) and int(session._attacks[12].started) == started and brain_state(session,12) != "decoy", "lure preserves an already started bite windup")
	# Put actual grounded cover between the far zombie and the decoy while it
	# remains distant, rather than putting a wall into the actor's body.
	var lure: Vector3 = runtime.lure_target(session.simulation.get_actor(13).motion.physics_eye())
	var between: Vector3 = (session.simulation.get_actor(13).motion.physics_eye() + lure) * .5
	var cell: Vector3i = Vector3i(between.floor())
	for y: int in range(4, 8):
		var receipt: Dictionary = session.simulation.data.set_block(Vector3i(cell.x,y,cell.z),0x01447788,{"tick":session.simulation.tick,"actor_id":1})
		session.simulation._commit(receipt)
	await frames(1)
	check(not runtime.lure_target(session.simulation.get_actor(13).motion.physics_eye()).is_finite(), "canonical terrain wall prevents decoy influence through cover")
	var actor: SharedPlayerState = session.simulation.get_actor(12)
	action("primary", true)
	for tick: int in 32:
		aim_at(actor.feet() + Vector3.UP * 1.25)
		await frames(1)
		if runtime.movement_scale(12) == 0.0: break
	action("primary", false)
	check(runtime.movement_scale(12) == 0.0 and session._attacks.has(12), "actual four cold hits freeze the live attacker before its bite resolves")
	if session._attacks.has(12) and runtime.movement_scale(12) == 0.0:
		var deadline: int = int(session._attacks[12].deadline)
		var position: Vector3 = actor.feet()
		var health: int = session.get_owner_state().health
		await frames(8)
		check(Vector2(actor.feet().x, actor.feet().z) == Vector2(position.x, position.z) and int(session._attacks[12].deadline) >= deadline + 8 and session.get_owner_state().health == health, "zero movement clears horizontal momentum and extends existing attack deadline without phantom bites")
	# The deadline is explicitly shortened only inside this fixture. Main's
	# serialized Rush still uses180seconds; this is completion logic evidence.
	session._preparation_ticks = int(SETTINGS.rush_defaults().preparation_seconds) * 60 - 1
	var spawn_deadline: int = Time.get_ticks_msec() + 4000
	while session._spawned == 0 and not session.finished and Time.get_ticks_msec() < spawn_deadline:
		await frames(1)
	check(session.phase == "active" and session._spawned > 0, "real schedule admits counted wave lives before completion probe")
	session._active_ticks = session._duration_ticks - 1
	await frames(1)
	check(session.phase == "cleanup", "production deadline transitions to cleanup")
	for id: int in session.ZOMBIE_IDS:
		var target: SharedPlayerState = session.simulation.get_actor(id)
		if target != null and target.is_alive(): session.simulation.damage_actor(id,1000,1,"fixture")
	await frames(2)
	if session.get_rush_state().pending:
		check(session.choose_upgrade("field_kit").ok, "cleanup milestone choice remains actionable")
		await frames(2)
	check(session._live_count() == 0 and runtime.has_pending() and not session.finished, "cleanup waits for actual remaining dangerous disco ordnance after the last hostile dies")
	var deadline: int = Time.get_ticks_msec() + 12000
	while not session.finished and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(session.finished and session.outcome == "win" and not runtime.has_pending(), "finite ordnance completes and permits authoritative survival victory")
	await close_scene()

func run() -> void:
	var window: Dictionary = {"size": root.size, "scale_size": root.content_scale_size, "scale_mode": root.content_scale_mode, "scale_aspect": root.content_scale_aspect}
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for path: String in [MAPS.SETTINGS_PATH, LOADOUT.PATH, RECORDS.PATH]: backup(path)
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("ui", "touch_controls", 2)
	check(preferences.save(MAPS.SETTINGS_PATH) == OK, "private real scene profile seeded")
	if FileAccess.file_exists(RECORDS.PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS.PATH))
	await main_flow()
	await close_scene()
	await ai_flow()
	await close_scene()
	if has_meta("blockfield_launch"): remove_meta("blockfield_launch")
	LabInputBindings.release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restore()
	root.size = window.size
	root.content_scale_size = window.scale_size
	root.content_scale_mode = window.scale_mode
	root.content_scale_aspect = window.scale_aspect
	print("ARSENAL SCENE: %d checks, %d failures" % [checks, failures])
	OS.delay_msec(80)
	quit(1 if failures else 0)
