extends Node
## Headless offline tests still use the lab; server selection is explicit.
func _ready() -> void:
	var server := OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--server")
	var scene_path := "res://scenes/dedicated_server.tscn" if server else "res://scenes/main.tscn"
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("Blockfield entry scene unavailable")
		get_tree().quit(1)
		return
	add_child(scene.instantiate())
