extends Node
## The game shell has no world or simulation; every launch is local.
const SURVIVAL_PATH: String = "res://scenes/offline_survival.tscn"
var _survival_scene: PackedScene
var _warming: bool = false
var _warm_error: bool = false
var _screen: GameShell
var _request_started: bool = false
var _warm_resources: Array[Resource] = []
var _warm_paths: Array[String] = []
var _warm_cursor: int = 0
var _warm_turns: int = 0
var _arsenal_panel: ArsenalPanel
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/game_shell.tscn") as PackedScene
	if scene == null:
		push_error("Blockfield entry scene unavailable")
		get_tree().quit(1)
		return
	var screen: Node = scene.instantiate()
	_screen = screen as GameShell
	add_child(screen)
	get_window().title = "Blockfield"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LabInputBindings.release_actions()
	screen.launch_requested.connect(_launch_game)
	screen.utility_requested.connect(_open_utility)
	_warm_survival()

func _warm_survival() -> void:
	if _warming or _survival_scene != null: return
	_warming = true
	_warm_error = false
	_warm_turns = 0
	set_process(true)

func _process(_delta: float) -> void:
	if not _warming: return
	_warm_turns += 1
	if _warm_turns <= 2: return # Draw Home before cold resources.
	if _survival_scene == null and not _request_started:
		var error: Error = ResourceLoader.load_threaded_request(SURVIVAL_PATH, "PackedScene", false)
		if error != OK:
			_warm_error = true
			_warming = false
			return
		_request_started = true
	if _request_started:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(SURVIVAL_PATH)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_survival_scene = ResourceLoader.load_threaded_get(SURVIVAL_PATH) as PackedScene
			_request_started = false
			_warm_error = _survival_scene == null
			if _survival_scene != null:
				_warm_paths.append("res://presentation/openspades_post_effects.gd")
				for folder: String in ["Player", "Weapons/Rifle", "Weapons/SMG", "Weapons/Shotgun", "Weapons/Grenade", "Weapons/Spade", "Weapons/Block", "MapObjects"]:
					var directory: String = "res://assets/openspades/models/" + folder
					for filename: String in DirAccess.get_files_at(directory):
						if filename.get_extension() != "glb": continue
						_warm_paths.append(directory + "/" + filename)
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_warm_error = true
			_warming = false
			return
		if _request_started: return
	# One model resource per frame; no suspended coroutine survives Entry teardown.
	if _warm_cursor < _warm_paths.size():
		var resource: Resource = load(_warm_paths[_warm_cursor])
		if resource != null: _warm_resources.append(resource)
		_warm_cursor += 1
	else:
		_warming = false
		set_process(false)

func _launch_game(configuration: Dictionary) -> void:
	var checked: Dictionary = GameMapCatalog.validate(configuration)
	if not checked.ok: return
	var equipment: Dictionary = ArsenalLoadout.load_saved()
	if bool(equipment.enabled) and str(checked.configuration.mode) in ["training", "survival"]:
		checked.configuration.arsenal = equipment.loadout.duplicate(true)
	# Let the shell's pending/loading state render before loading the game scene.
	# Two process boundaries cover requests emitted during the current input turn.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree(): return
	if checked.configuration.mode == "survival":
		if _survival_scene == null and not _warming: _warm_survival()
		var deadline: int = Time.get_ticks_msec() + 45000
		while (_survival_scene == null or _warming) and not _warm_error and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if not is_inside_tree(): return
		if _survival_scene == null or _warming:
			_screen.show_launch_error("Не удалось подготовить режим. Попробуйте ещё раз.")
			return
		get_tree().set_meta("blockfield_warm_resources", _warm_resources.duplicate())
	get_tree().set_meta("blockfield_launch", checked.configuration.duplicate(true))
	LabInputBindings.release_actions()
	var scene_path: String = "res://scenes/offline_tdm.tscn" if checked.configuration.mode == "tdm" else "res://scenes/main.tscn"
	if checked.configuration.mode == "survival":
		get_tree().change_scene_to_packed(_survival_scene)
	else: get_tree().change_scene_to_file(scene_path)

func _exit_tree() -> void:
	# A fast quit can otherwise tear down shader/script resources while the
	# loader still reads them. Only drain our one outstanding request on exit.
	if _request_started:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(SURVIVAL_PATH)
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_survival_scene = ResourceLoader.load_threaded_get(SURVIVAL_PATH) as PackedScene
		_request_started = false
	_survival_scene = null
	_warm_resources.clear()

func _open_utility(kind: String) -> void:
	if kind == "arsenal":
		if not is_instance_valid(_arsenal_panel):
			_arsenal_panel = ArsenalPanel.new()
			add_child(_arsenal_panel)
			_arsenal_panel.set_home_mode(true)
			_arsenal_panel.loadout_changed.connect(func(loadout: Dictionary) -> void: ArsenalLoadout.save(loadout))
			_arsenal_panel.item_selected.connect(func(id: String) -> void:
				if id == "source": ArsenalLoadout.save(ArsenalLoadout.load_saved().loadout, false))
		_arsenal_panel.set_loadout(ArsenalLoadout.load_saved().loadout)
		_arsenal_panel.set_enabled(true)
		_arsenal_panel.show_catalog(true)
		return
	if kind not in ["settings", "lab"]: return
	get_tree().set_meta("blockfield_utility", kind)
	LabInputBindings.release_actions()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
