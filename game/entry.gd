extends Node
## The game shell has no world or simulation. Server selection stays explicit.
func _ready() -> void:
	var server := OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--server")
	var scene_path := "res://scenes/dedicated_server.tscn" if server else "res://scenes/game_shell.tscn"
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("Blockfield entry scene unavailable")
		get_tree().quit(1)
		return
	var screen: Node = scene.instantiate()
	add_child(screen)
	if not server:
		get_window().title = "Blockfield"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_release_client_actions()
		screen.launch_requested.connect(_launch_game)
		screen.utility_requested.connect(_open_utility)

func _launch_game(configuration: Dictionary) -> void:
	var catalog: Script = load("res://ui/map_catalog.gd")
	var checked: Dictionary = catalog.validate(configuration)
	if not checked.ok: return
	get_tree().set_meta("blockfield_launch", checked.configuration.duplicate(true))
	_release_client_actions()
	var scene_path: String = "res://scenes/offline_tdm.tscn" if checked.configuration.mode == "tdm" else "res://scenes/main.tscn"
	get_tree().change_scene_to_file(scene_path)

func _open_utility(kind: String) -> void:
	if kind not in ["settings", "network", "lab"]: return
	get_tree().set_meta("blockfield_utility", kind)
	_release_client_actions()
	get_tree().change_scene_to_file("res://scenes/network.tscn" if kind == "network" else "res://scenes/main.tscn")

func _release_client_actions() -> void:
	# The filtered server pack has no client global-class registry. Resolve
	# this helper only on the client route instead of compiling a global name.
	var bindings: Script = load("res://ui/input_bindings.gd")
	bindings.release_actions()
