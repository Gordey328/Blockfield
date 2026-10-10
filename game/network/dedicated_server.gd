extends Node
const RUNTIME = preload("res://network/server_runtime.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPATIBILITY = preload("res://network/compatibility.gd")
var runtime: RUNTIME
var _pristine: VoxelData
var _restart_ticks := 600
var _restart_at := -1

func _ready() -> void:
	var options := {"game-port":"8765","map-port":"8766","bind":"127.0.0.1","map":"lab","mode":"ctf","profile":"0.75","round-restart":"10"}
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
	if not String(options["round-restart"]).is_valid_int() or int(options["round-restart"]) < 1 or int(options["round-restart"]) > 3600:
		_fail("Round restart must be 1..3600 seconds")
		return
	_restart_ticks = int(options["round-restart"])*60
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
	_pristine = data.frozen_copy() as VoxelData
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
	if runtime == null or not runtime.running: return
	if not runtime.step_once(): _fail("Fixed server simulation failed");return
	if runtime.simulation.objectives.winning_team >= 0:
		if _restart_at < 0: _restart_at = runtime.simulation.tick+_restart_ticks
		elif runtime.simulation.tick >= _restart_at: _restart_round()
	else: _restart_at = -1

func _restart_round() -> void:
	if runtime.simulation.epoch >= 0xffffffff: _fail("Match epoch exhausted; restart the process");return
	var restored := DATA.new()
	if restored.clear(_pristine.dimensions,runtime.simulation.epoch+1) != OK:
		_fail("Round baseline allocation failed");return
	# Fresh writable storage restores terrain; clients receive a new barrier.
	restored.blocks = _pristine.blocks.duplicate()
	restored.water_level = _pristine.water_level
	restored.wade_origin_level = _pristine.wade_origin_level
	var changed: Dictionary = runtime.reset_match(restored)
	if not changed.ok: _fail("Round reset failed");return
	_restart_at = -1
	print("BLOCKFIELD SERVER: new match epoch %d" % changed.epoch)

func _exit_tree() -> void:
	if runtime != null: runtime.stop()
