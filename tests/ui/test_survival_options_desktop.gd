extends SceneTree
## Desktop controls -> canonical saved launch settings, without mobile UI runs.
const SHELL = preload("res://scenes/game_shell.tscn")
var checks: int = 0
var failures: int = 0
var saved: PackedByteArray
var existed: bool = false
var emitted: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SURVIVAL OPTIONS: " + message)
func run() -> void:
	existed = FileAccess.file_exists("user://settings.cfg")
	if existed: saved = FileAccess.get_file_as_bytes("user://settings.cfg")
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("ui", "touch_controls", 2)
	preferences.save("user://settings.cfg")
	root.size = Vector2i(1280, 720)
	var shell: GameShell = SHELL.instantiate() as GameShell
	root.add_child(shell)
	shell.show_setup("survival")
	await process_frame
	check(GameMapCatalog.available_for("survival").size() == 3, "three real available survival levels")
	var player_damage: SpinBox = shell.find_child("ZombieDamage", true, false) as SpinBox
	var block_damage: SpinBox = shell.find_child("ZombieBlockDamage", true, false) as SpinBox
	check(player_damage != null and block_damage != null, "two independently labelled damage controls exist")
	check(player_damage.value == 20 and block_damage.value == 40, "damage defaults retain ordinary melee balance")
	player_damage.value = 7
	block_damage.value = 65
	shell.select_map("mira_hq")
	shell.select_weapon(2)
	shell.launch_requested.connect(func(value: Dictionary) -> void: emitted = value.duplicate(true))
	(shell.find_child("StartGame", true, false) as Button).pressed.emit()
	check(emitted.get("map_id") == "mira_hq" and emitted.get("weapon") == 2, "selected real level and original shotgun cross launch boundary")
	check(emitted.survival.zombie_damage == 7 and emitted.survival.zombie_block_damage == 65, "distinct damage values cross launch boundary")
	var remembered: Dictionary = GameMapCatalog.load_selection()
	check(remembered == emitted and GameMapCatalog.load_survival_settings().zombie_block_damage == 65, "both settings and level persist canonically")
	shell.show_launch_error("Fixture retry")
	check(not shell.get_display_state().pending and not (shell.find_child("StartGame", true, false) as Button).disabled, "recoverable preparation failure enables retry")
	var invalid: Dictionary = emitted.duplicate(true)
	invalid.survival.zombie_damage = 101
	check(not GameMapCatalog.validate(invalid).ok, "launch rejects unsupported damage before creating world")
	invalid = emitted.duplicate(true)
	invalid.mode = "tdm"
	check(not GameMapCatalog.validate(invalid).ok, "survival imports do not silently enter unsupported TDM")
	var session: OfflineSurvivalSession = OfflineSurvivalSession.new()
	root.add_child(session)
	var level: Dictionary = SurvivalLevels.load_level("mira_hq")
	check(session.configure_survival(level.data, level.arena, emitted.survival).ok, "selected damage settings configure the actual level authority")
	var panel: Node = (load("res://ui/survival_panel.gd") as Script).new()
	root.add_child(panel)
	panel.configure(session, "ru")
	check(str(panel.get_display_state().settings).contains("Урон игроку 7") and str(panel.get_display_state().settings).contains("Урон блокам 65"), "desktop pause/results report the independent settings")
	panel.queue_free()
	session.free()
	shell.queue_free()
	await process_frame
	if existed:
		var file: FileAccess = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else: DirAccess.remove_absolute("user://settings.cfg")
	print("SURVIVAL OPTIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
