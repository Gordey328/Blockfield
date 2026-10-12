extends SceneTree
## Same native warm-menu click timeline against the previous freeze and current.
var baseline: bool = false
var saved: PackedByteArray
var existed: bool = false
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LAUNCH LATENCY: " + message)
func run() -> void:
	existed = FileAccess.file_exists("user://settings.cfg")
	if existed: saved = FileAccess.get_file_as_bytes("user://settings.cfg")
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("graphics", "hdr", false)
	preferences.set_value("ui", "touch_controls", 2)
	preferences.save("user://settings.cfg")
	var entry: Node = (load("res://scenes/entry.tscn") as PackedScene).instantiate()
	root.add_child(entry)
	current_scene = entry
	var entry_id: int = entry.get_instance_id()
	var shell: GameShell = entry.get_child(0) as GameShell
	shell.show_setup("survival")
	for index: int in range(60): await process_frame
	if not baseline:
		var warm_deadline: int = Time.get_ticks_msec() + 45000
		while entry.get("_warming") and Time.get_ticks_msec() < warm_deadline: await process_frame
		check(entry.get("_survival_scene") != null and not entry.get("_warm_resources").is_empty(), "Home warms packed scene and bounded model resources without a world")
		check(entry.find_child("VoxelWorld", true, false) == null, "warming adds no hidden simulation")
	var began: int = Time.get_ticks_usec()
	var previous: int = began
	var max_frame: int = 0
	var frame_count: int = 0
	(shell.find_child("StartGame", true, false) as Button).pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		max_frame = maxi(max_frame, now - previous)
		previous = now
		frame_count += 1
		if current_scene != null and current_scene.get_instance_id() != entry_id and current_scene.has_method("get_launch_state"):
			if current_scene.get_launch_state().status in ["ready", "error"]: break
	check(current_scene != null and current_scene.has_method("get_launch_state") and current_scene.get_launch_state().status == "ready", "ordinary click reaches finite ready state")
	print("LAUNCH LATENCY baseline=%s click_to_ready_ms=%.3f max_process_gap_ms=%.3f frames=%d" % [str(baseline), (Time.get_ticks_usec()-began)/1000.0, max_frame/1000.0, frame_count])
	var app: Node = current_scene
	if not baseline:
		check(app.hdr_scene.scene_viewport == null, "disabled HDR allocates no scene/exposure pyramid")
		check(app.session.simulation.tick < 5 and not app.session.paused, "preparation clock starts after warming, not during it")
		app.set_graphics_option("hdr", true)
		check(app.hdr_scene.scene_viewport != null and app.hdr_scene.exposure != null and app.hdr_scene.enabled, "turning HDR on later initializes the retained pipeline")
		app.set_graphics_option("hdr", false)
		check(not app.hdr_scene.enabled, "HDR can return to the ordinary renderer")
	app.queue_free()
	for index: int in range(3): await process_frame
	if existed:
		var file: FileAccess = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else: DirAccess.remove_absolute("user://settings.cfg")
	print("LAUNCH LATENCY: %d checks, %d failures" % [checks, failures])
	OS.delay_msec(80) # Stop native audio callback references after measurement.
	for index: int in range(3): await process_frame
	quit(1 if failures else 0)
