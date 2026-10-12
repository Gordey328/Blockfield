extends SceneTree
## Selected frontend configuration enters real Main/authority, never a test double.
const LAB_SCENE = preload("res://scenes/main.tscn")
const TDM_SCENE = preload("res://scenes/offline_tdm.tscn")
const FILES: Array[String] = ["user://settings.cfg", "user://servers.cfg"]
var checks: int = 0
var failures: int = 0
var app: Node3D
var before: Dictionary = {}
var input_globals: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GAME LAUNCH: " + message)


func frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout


func action(name_value: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name_value
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	for path: String in FILES:
		var exists := FileAccess.file_exists(path)
		before[path] = {"exists": exists, "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	input_globals = {"mouse_mode": Input.mouse_mode, "emulation": Input.emulate_mouse_from_touch,
		"locale": TranslationServer.get_locale()}
	var preferences := ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("ui", "touch_controls", 2)
	check(preferences.save(FILES[0]) == OK, "controlled temporary preferences are written")
	await test_tdm()
	await free_scene()
	await test_training_lab()
	await free_scene()
	await test_bundled_map()
	await free_scene()
	await test_invalid_launch()
	await free_scene()
	await restore()
	print("GAME LAUNCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func launch(scene: PackedScene, configuration: Dictionary) -> Dictionary:
	set_meta("blockfield_launch", configuration.duplicate(true))
	app = scene.instantiate()
	root.add_child(app)
	current_scene = app
	check(not has_meta("blockfield_launch"), "Main consumes launch metadata exactly once")
	var deadline: int = Time.get_ticks_msec() + 45000
	var state: Dictionary = app.call("get_launch_state")
	while str(state.get("status", "")) in ["idle", "loading"] and Time.get_ticks_msec() < deadline:
		await frames(1)
		state = app.call("get_launch_state")
	check(str(state.get("status", "")) in ["ready", "error"], "launch reaches a finite ready/error result")
	return state


func test_tdm() -> void:
	var selected := {"mode": "tdm", "map_id": "crossroads", "weapon": 1}
	var state: Dictionary = await launch(TDM_SCENE, selected)
	check(state.status == "ready" and state.configuration == selected, "Crossroads SMG launch reports the chosen configuration")
	if state.status != "ready":
		return
	var session: OfflineTDMSession = app.get_node("LocalSession")
	var owner: SharedPlayerState = session.simulation.get_actor(session.local_player_id())
	check(app.offline_tdm_mode and not app.network_mode and app.network_client == null,
		"selected battle is serverless TDM with no network transport")
	check(session.simulation.actors.size() == 6 and session.get_diagnostics().team_counts == [3, 3],
		"selected battle admits exactly one human and five bots")
	check(app.world.data == session.simulation.data and app.world.map_name.contains("Crossroads"),
		"battle presents the real Crossroads authority map")
	check(owner.weapon == 1 and owner.pending_weapon == -1 and session.current_weapon == 1,
		"SMG is the actual starting class rather than a request waiting for respawn")
	check(owner.magazine == int(session.get_weapon_info().clip_size), "starting selected class receives its correct full magazine")
	check(not session.paused and not app.hud.is_menu_open() and app.player.controls_enabled,
		"launch directly enters live battle with the legacy startup menu closed")
	var tick: int = session.simulation.tick
	var start: Vector3 = owner.feet()
	action("forward", true)
	await frames(12)
	action("forward", false)
	check(session.simulation.tick > tick and owner.feet().distance_to(start) > 0.1,
		"normal gameplay input advances the selected battle authority and player")
	check(owner.weapon == 1 and owner.pending_weapon == -1,
		"later frames do not reapply selection or queue another class change")


func test_training_lab() -> void:
	var selected := {"mode": "training", "map_id": "lab", "weapon": 2}
	var state: Dictionary = await launch(LAB_SCENE, selected)
	check(state.status == "ready" and state.configuration == selected, "training launches its selected lab and shotgun")
	if state.status != "ready":
		return
	check(not app.offline_tdm_mode and not app.network_mode and app.session.mode == "sandbox",
		"training retains the independent offline lab adapter")
	check(app.world.dimensions == Vector3i(96, 32, 96) and app.session.targets.size() == 6,
		"Lab selection installs the real laboratory map and its original test roster")
	check(app.session.current_weapon == 2 and app.session.magazine == int(app.session.get_weapon_info().clip_size),
		"training starts with a replenished actual shotgun")
	check(not app.hud.is_menu_open() and app.player.controls_enabled,
		"training launch closes preparation and enables gameplay immediately")


func test_bundled_map() -> void:
	var selected := {"mode": "training", "map_id": "mirage", "weapon": 0}
	var state: Dictionary = await launch(LAB_SCENE, selected)
	check(state.status == "ready" and state.configuration == selected, "selected native Mirage finishes a bounded real load")
	if state.status != "ready":
		return
	check(app.world.dimensions == Vector3i(171, 61, 165) and app._map_baseline_name == "csgo_mirage.bfmap",
		"Mirage selection loads the bundled resource and retains its reset baseline")
	check(app.session.targets.is_empty() and not app.world.water_enabled,
		"Mirage does not receive misplaced lab actors or water")
	check(app.player.global_position.distance_to(app.world.get_spawn_position()) < 0.2
		and not app.hud.is_menu_open() and app.player.controls_enabled,
		"selected native map enters play at its validated feet spawn")
	# Leaving while actions are held must not pass input into the next scene.
	action("forward", true)
	action("primary", true)
	var previous: WeakRef = weakref(app)
	app.call("open_game_home")
	await frames(5)
	check(not Input.is_action_pressed("forward") and not Input.is_action_pressed("primary"),
		"return Home releases held movement and fire actions")
	check(previous.get_ref() == null, "return Home tears down gameplay and its audio/controller ownership")
	app = null
	check(current_scene != null and current_scene.find_child("GameShell", true, false) != null,
		"return Home opens the actual lightweight game shell")
	if current_scene != null:
		check(current_scene.find_child("VoxelWorld", true, false) == null,
			"Home contains no active gameplay world")
		var home: Node = current_scene
		current_scene = null
		home.queue_free()
		await frames(4)


func test_invalid_launch() -> void:
	var selected := {"mode": "tdm", "map_id": "mirage", "weapon": 9}
	var state: Dictionary = await launch(TDM_SCENE, selected)
	check(state.status == "error" and not str(state.get("error", "")).is_empty(),
		"invalid saved setup gives a recoverable launch error")
	check(not app.player.controls_enabled and app.session.paused,
		"invalid setup cannot enter battle or enable gameplay input")
	var tick: int = app.session.simulation.tick
	action("forward", true)
	action("primary", true)
	await frames(8)
	check(app.session.simulation.tick == tick, "held input cannot advance authority behind the launch error")
	LabInputBindings.release_actions()
	var return_button: Button = app.find_child("LaunchHome", true, false) as Button
	check(return_button != null and return_button.is_visible_in_tree() and not return_button.disabled,
		"launch error exposes a real enabled return Home action")
	if return_button != null:
		var previous: WeakRef = weakref(app)
		return_button.pressed.emit()
		await frames(5)
		check(previous.get_ref() == null and current_scene != null
			and current_scene.find_child("GameShell", true, false) != null,
			"error Home control recovers into the real frontend")
		app = null
		if current_scene != null:
			var home: Node = current_scene
			current_scene = null
			home.queue_free()
			await frames(4)


func free_scene() -> void:
	if app == null or not is_instance_valid(app):
		app = null
		return
	LabInputBindings.release_actions()
	app.call("stop_audio")
	if current_scene == app:
		current_scene = null
	var previous: WeakRef = weakref(app)
	app.queue_free()
	await frames(5)
	check(previous.get_ref() == null, "previous Main is fully freed before another launch")
	app = null
	if has_meta("blockfield_launch"):
		remove_meta("blockfield_launch")


func restore() -> void:
	LabInputBindings.release_actions()
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		await process_frame
	for path: String in FILES:
		if before[path].exists:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(before[path].bytes)
			file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Input.mouse_mode = input_globals.mouse_mode
	Input.emulate_mouse_from_touch = input_globals.emulation
	TranslationServer.set_locale(input_globals.locale)
