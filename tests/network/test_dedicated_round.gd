extends SceneTree
const DEDICATED = preload("res://network/dedicated_server.gd")
const RUNTIME = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPAT = preload("res://network/compatibility.gd")
class Harness extends DEDICATED:
	var errors: Array[String] = []
	func _ready() -> void: pass # Test supplies ephemeral native listeners.
	func _fail(message: String) -> void: errors.append(message)
var assertions := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value: failures += 1;push_error("DEDICATED ROUND: "+message)
func _run() -> void:
	var node := Harness.new()
	root.add_child(node)
	node.set_process(false);node.set_physics_process(false)
	var data := DATA.new()
	check(data.clear(Vector3i(32,16,32),86)==OK,"canonical round map")
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	node._pristine = data.frozen_copy()
	node._restart_ticks = 3
	var match_sim := MATCH.new()
	check(match_sim.configure(data,"0.76","ctf").ok,"authored server policy")
	node.runtime = RUNTIME.new()
	check(node.runtime.configure(match_sim,COMPAT.build_hash(),COMPAT.rules_hash()),"runtime setup")
	check(node.runtime.start().ok,"actual ephemeral sockets")
	# The objective suite separately verifies how a winner is produced. This
	# fixture checks the dedicated coordinator's countdown and pristine restore.
	match_sim.objectives.winning_team = 0
	var cell := Vector3i(10,3,10)
	data.blocks[data.index(cell)] = 0
	node._physics_process(1.0/60)
	check(node._restart_at==4 and node.runtime.simulation.epoch==86,"win starts fixed-step restart deadline")
	for step in 2: node._physics_process(1.0/60)
	check(node.runtime.simulation.epoch==86 and data.get_block(cell)==0,"destroyed terrain persists before deadline")
	node._physics_process(1.0/60)
	var restored: MatchSimulation = node.runtime.simulation
	check(restored.epoch==87 and restored.tick==0,"deadline creates newer closed match epoch")
	check(restored.data!=data and restored.data.get_block(cell)==0x01608070,"fresh writable terrain restores pristine map")
	check(restored.data.map_sequence==0 and restored.grenades.is_empty() and restored.event_sequence==0,"map/projectile/event cursors reset")
	check(restored.mode=="ctf" and restored.profile=="0.76" and restored.objectives.winning_team==-1,"mode/profile retained and objective victory cleared")
	check(node._restart_at==-1 and node.errors.is_empty(),"coordinator countdown cleared")
	for step in 6: node._physics_process(1.0/60)
	check(restored==node.runtime.simulation and restored.epoch==87,"idle round does not repeatedly reset")
	restored.epoch = 0xffffffff
	node._restart_round()
	check(node.errors==["Match epoch exhausted; restart the process"],"epoch exhaustion never wraps")
	node.runtime.stop()
	node.queue_free()
	for frame in 3: await process_frame
	print("DEDICATED ROUND: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
