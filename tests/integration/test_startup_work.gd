extends SceneTree
## Observe real scene startup, including child bootstrap work before Main._ready.
class ObservedWorld extends VoxelWorld:
	var lab_generations: int = 0
	func generate_lab() -> void:
		lab_generations += 1
		super.generate_lab()

class ObservedMain extends "res://main.gd":
	var startup_profile: Dictionary = {}
	var _stage_usec: int = 0
	func _setup_input() -> void:
		_stage_usec = Time.get_ticks_usec()
		super._setup_input()
	func _load_settings() -> void:
		startup_profile.effects_and_scene_ms = (Time.get_ticks_usec() - _stage_usec) / 1000.0
		_stage_usec = Time.get_ticks_usec()
		super._load_settings()
	func _setup_graphics() -> void:
		startup_profile.settings_and_session_ms = (Time.get_ticks_usec() - _stage_usec) / 1000.0
		_stage_usec = Time.get_ticks_usec()
		super._setup_graphics()
	func _update_shared_actor_views() -> void:
		startup_profile.graphics_and_hud_ms = (Time.get_ticks_usec() - _stage_usec) / 1000.0
		_stage_usec = Time.get_ticks_usec()
		super._update_shared_actor_views()
		startup_profile.actors_ms = (Time.get_ticks_usec() - _stage_usec) / 1000.0

const SCENES: Array[String] = ["res://scenes/offline_survival.tscn", "res://scenes/offline_tdm.tscn"]
var checks: int = 0
var failures: int = 0
var baseline: bool = false
var saved: PackedByteArray
var had_settings: bool = false

func _initialize() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("STARTUP WORK: " + message)

func run() -> void:
	had_settings = FileAccess.file_exists("user://settings.cfg")
	if had_settings: saved = FileAccess.get_file_as_bytes("user://settings.cfg")
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("graphics", "hdr", false)
	preferences.set_value("ui", "touch_controls", 2)
	preferences.save("user://settings.cfg")
	for path: String in SCENES:
		var began: int = Time.get_ticks_usec()
		var scene: PackedScene = load(path) as PackedScene
		var app: Node3D = scene.instantiate() as Node3D
		var instance_usec: int = Time.get_ticks_usec() - began
		if not baseline:
			var survival: bool = app.offline_survival_mode
			app.set_script(ObservedMain)
			app.offline_tdm_mode = true
			app.offline_survival_mode = survival
		var world: Node = app.get_node("VoxelWorld")
		world.set_script(ObservedWorld)
		began = Time.get_ticks_usec()
		root.add_child(app)
		current_scene = app
		var ready_usec: int = Time.get_ticks_usec() - began
		var generated: int = world.lab_generations
		check(generated == (1 if baseline else 0), "Crossroads avoids the discarded synchronous lab: " + path)
		check(app.world.data == app.session.simulation.data and app.world.map_name.contains("Crossroads"), "correct authority map is adopted")
		check(app.session.paused and not app.player.controls_enabled, "direct scene bootstrap remains safely paused")
		if not baseline:
			var owner: SharedPlayerState = app.session.get_owner_state()
			check(app.player.global_position.is_equal_approx(owner.feet()), "first camera pose already follows the authoritative spawn")
			check(world.get_spawn_position().distance_to(owner.feet()) < .1, "initial streaming starts at the real owner, not map-center cover")
		print("STARTUP SAMPLE %s instance_ms=%.3f ready_ms=%.3f lab_generations=%d" % [path, instance_usec / 1000.0, ready_usec / 1000.0, generated])
		if not baseline: print("STARTUP STAGES ", app.startup_profile)
		app.queue_free()
		for index: int in range(3): await process_frame
	# The standalone world/lab path is still available to the offline test lab.
	var standalone: ObservedWorld = ObservedWorld.new()
	root.add_child(standalone)
	check(standalone.lab_generations == 1 and not standalone.data.blocks.is_empty(), "ordinary lab still bootstraps once")
	standalone.queue_free()
	await process_frame
	if not baseline:
		await test_entry_loading_turn()
	if had_settings:
		var file: FileAccess = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else: DirAccess.remove_absolute("user://settings.cfg")
	print("STARTUP WORK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_entry_loading_turn() -> void:
	var scene: PackedScene = load("res://scenes/entry.tscn") as PackedScene
	var entry: Node = scene.instantiate()
	root.add_child(entry)
	current_scene = entry
	var entry_id: int = entry.get_instance_id()
	var shell: GameShell = entry.get_child(0) as GameShell
	shell.show_setup("survival")
	var start: Button = shell.find_child("StartGame", true, false) as Button
	start.pressed.emit()
	check(current_scene == entry and shell.get_display_state().pending, "pending setup is visible before scene loading")
	await process_frame
	check(current_scene == entry, "entry leaves a complete presentation turn before loading")
	var deadline: int = Time.get_ticks_msec() + 35000
	var checked_loading: bool = false
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != entry_id and current_scene.has_method("get_launch_state"):
			if current_scene.get_launch_state().status == "loading" and not checked_loading:
				check(current_scene.session.paused and not current_scene.player.controls_enabled,
					"chunk preparation keeps authority clock and gameplay input paused")
				checked_loading = true
			if current_scene.get_launch_state().status == "ready": break
			if current_scene.get_launch_state().status == "error": break
	var app: Node = current_scene
	check(app != null and app.get_instance_id() != entry_id and app.has_method("get_launch_state") and app.get_launch_state().status == "ready", "real entry launch still reaches ready")
	if app != null and app.has_method("get_launch_state"):
		check(checked_loading and app.world.get_visual_preparation_stats().ready and app.world.get_rebuild_stats().pending_chunks == 0 and not app.world.get_rebuild_stats().active_build,
			"entry unlocks only after budgeted initial chunk publication completes")
	if app != null:
		app.queue_free()
		for index: int in range(3): await process_frame
