extends SceneTree
const SHELL = preload("res://ui/game_shell.gd")
const CATALOG = preload("res://ui/map_catalog.gd")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SURVIVAL SETUP: " + label)

func frames(count: int) -> void:
	for index: int in count:
		await process_frame
		await create_timer(0.0).timeout

func run() -> void:
	var exists: bool = FileAccess.file_exists("user://settings.cfg")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://settings.cfg") if exists else PackedByteArray()
	var size_before: Vector2i = root.size
	var prefs: ConfigFile = ConfigFile.new()
	prefs.set_value("profile", "locale", "ru")
	prefs.set_value("graphics", "quality", 7)
	prefs.save("user://settings.cfg")
	check(CATALOG.available_for("survival").size() == 3, "authored arena and two validated survival adaptations are available")
	check(not CATALOG.validate({"mode":"survival", "map_id":"dust2", "weapon":0}).ok, "imported map cannot claim zombie route support")
	var configuration: Dictionary = {"mode":"survival", "map_id":"crossroads", "weapon":1, "survival":SETTINGS.defaults()}
	configuration.survival.duration_seconds = 120
	configuration.survival.wave_interval_seconds = 30
	configuration.survival.zombies_per_wave = 8
	configuration.survival.growth_per_minute = 1.5
	configuration.survival.growth_mode = "step"
	check(CATALOG.validate(configuration).ok, "canonical bounded survival settings cross launch boundary")
	check(CATALOG.save_selection(configuration) == OK and CATALOG.load_selection() == configuration, "wave settings and weapon survive reload")
	prefs.load("user://settings.cfg")
	check(prefs.get_value("graphics", "quality", 0) == 7, "saving wave choices preserves unrelated preferences")
	var invalid: Dictionary = configuration.duplicate(true)
	invalid.survival.preparation_seconds = 0
	check(not CATALOG.validate(invalid).ok, "production launch cannot use fast fixture timing")
	var emitted: Array[Dictionary] = []
	for viewport_size: Vector2i in [Vector2i(1280,720), Vector2i(375,812), Vector2i(812,375)]:
		CATALOG.save_selection(configuration)
		root.size = viewport_size
		var shell: GameShell = SHELL.new()
		root.add_child(shell)
		current_scene = shell
		await frames(3)
		var home: Button = shell.find_child("Survival", true, false) as Button
		check(home != null, "Home exposes zombie mode at %s" % viewport_size)
		if home != null: home.pressed.emit()
		await frames(3)
		check(shell.get_selection().mode == "survival" and shell.get_selection().survival == configuration.survival, "setup restores actual wave choices")
		for id: String in ["WaveDurationMinutes", "WaveZombieCount", "WaveInterval", "WaveGrowth", "WaveGrowthMode"]:
			var field: Control = shell.find_child(id, true, false) as Control
			check(field != null and field.custom_minimum_size.y >= 44, "touch field exists with usable height: " + id)
		var duration: SpinBox = shell.find_child("WaveDurationMinutes", true, false) as SpinBox
		duration.value = 1
		check(shell.get_selection().survival.duration_seconds == 60, "visible minutes update authoritative seconds")
		var count: SpinBox = shell.find_child("WaveZombieCount", true, false) as SpinBox
		count.value = 12
		check(shell.get_selection().survival.zombies_per_wave == 12, "visible count updates launch quota")
		var bad: Dictionary = shell.get_selection().survival.duplicate(true)
		bad.zombies_per_wave = 1000
		check(not shell.set_survival_settings(bad) and shell.get_selection().survival.zombies_per_wave == 12, "invalid settings preserve previous valid setup")
		shell.launch_requested.connect(func(value: Dictionary) -> void: emitted.append(value))
		var start: Button = shell.find_child("StartGame", true, false) as Button
		check(start != null and not start.disabled and start.text.contains("выживание"), "real start is available and names survival")
		start.pressed.emit()
		check(emitted.back().mode == "survival" and emitted.back().survival.duration_seconds == 60, "real launch emits chosen bounded mode settings")
		shell.queue_free()
		await frames(2)
	root.size = size_before
	if exists:
		var file: FileAccess = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("SURVIVAL SETUP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
