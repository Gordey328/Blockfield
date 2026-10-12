extends Node
## The game shell has no world or simulation; every launch is local.
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/game_shell.tscn") as PackedScene
	if scene == null:
		push_error("Blockfield entry scene unavailable")
		get_tree().quit(1)
		return
	var screen: Node = scene.instantiate()
	add_child(screen)
	get_window().title = "Blockfield"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LabInputBindings.release_actions()
	screen.launch_requested.connect(_launch_game)
	screen.utility_requested.connect(_open_utility)

func _launch_game(configuration: Dictionary) -> void:
	var checked: Dictionary = GameMapCatalog.validate(configuration)
	if not checked.ok: return
	get_tree().set_meta("blockfield_launch", checked.configuration.duplicate(true))
	LabInputBindings.release_actions()
	var scene_path: String = "res://scenes/offline_tdm.tscn" if checked.configuration.mode == "tdm" else "res://scenes/main.tscn"
	get_tree().change_scene_to_file(scene_path)

func _open_utility(kind: String) -> void:
	if kind not in ["settings", "lab"]: return
	get_tree().set_meta("blockfield_utility", kind)
	LabInputBindings.release_actions()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
