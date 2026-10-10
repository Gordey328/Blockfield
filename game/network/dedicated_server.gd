extends Node
const RUNTIME = preload("res://network/server_runtime.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPATIBILITY = preload("res://network/compatibility.gd")
var runtime: RUNTIME

func _ready() -> void:
	var options := {"game-port":"8765","map-port":"8766","bind":"127.0.0.1","map":"lab","mode":"ctf","profile":"0.75"}
	var seen: Dictionary[String,bool] = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--server": continue
		var key := argument.get_slice("=",0).trim_prefix("--")
		if not argument.begins_with("--") or not argument.contains("=") or not options.has(key) or seen.has(key):
			_fail("Unknown or duplicate server option")
			return
		options[key] = argument.substr(argument.find("=")+1)
		seen[key] = true
	for key in ["game-port","map-port"]:
		if not String(options[key]).is_valid_int() or int(options[key]) < 0 or int(options[key]) > 65535:
			_fail("Invalid server port")
			return
	var data := DATA.new()
	var error: Error
	if options.map == "lab": error = data.generate_lab(1)
	else:
		var file := FileAccess.open(options.map,FileAccess.READ)
		if file == null or file.get_length() > 64*1024*1024:
			_fail("Map unavailable or exceeds 64 MiB VXL file budget")
			return
		error = data.load_vxl_bytes(file.get_buffer(file.get_length()),1)
	if error != OK:
		_fail("Map failed validation")
		return
	var simulation := SIMULATION.new()
	if not simulation.configure(data,options.profile,options.mode).ok:
		_fail("Match configuration rejected")
		return
	runtime = RUNTIME.new()
	if not runtime.configure(simulation,COMPATIBILITY.build_hash(),COMPATIBILITY.rules_hash()):
		_fail("Runtime configuration rejected")
		return
	var started := runtime.start(int(options["game-port"]),int(options["map-port"]),options.bind)
	if not started.ok:
		_fail("Server listener startup failed")
		return
	print("BLOCKFIELD SERVER: Godot %s; mode=%s profile=%s; game=%s:%d map=%s:%d" % [Engine.get_version_info().string,options.mode,options.profile,options.bind,started.game_port,options.bind,started.map_port])

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func _process(_delta: float) -> void:
	if runtime != null: runtime.poll()

func _physics_process(_delta: float) -> void:
	if runtime != null and runtime.running and not runtime.step_once(): _fail("Fixed server simulation failed")

func _exit_tree() -> void:
	if runtime != null: runtime.stop()
