extends SceneTree
## Opt-in isolated CPU throughput fixture; not production4ms frame scheduling.
## --path <profile copy>/game --script res://__probe/native.gd -- --scenario=title --output=<json>
const HARNESS = preload("res://__probe/impact.gd")
const STEP := 1.0/60.0
const SEED := 1389961
var harness: Node
var frame_index := 0

func _initialize() -> void:
	call_deferred("run")

func tick(primary: bool) -> void:
	var start := Time.get_ticks_usec()
	seed(SEED+frame_index*7919)
	harness.app.effects.rng.seed = SEED+frame_index*32452843
	harness.tether()
	if primary:
		Input.action_press("primary")
	else:
		Input.action_release("primary")
	# Manual order is fixed for both source copies. Synchronous flush measures
	# complete CPU throughput instead of deadline-dependent partial chunk work.
	harness.app._process(STEP)
	harness.app.player._physics_process(STEP)
	harness.app.world.rebuild_now()
	harness.app.world.advance_visual_preparation(4096,1000000)
	for cluster: Node3D in harness.app.world._falling_clusters.duplicate():
		if is_instance_valid(cluster) and not cluster.is_queued_for_deletion():
			cluster.step(STEP)
	harness.app.effects.update_effects(STEP)
	harness.app.audio._process(STEP)
	harness.app.hud._process(STEP)
	harness.app.hud._map._process(STEP)
	harness.app.hud._large_map._process(STEP)
	harness.sample_frame(float(Time.get_ticks_usec()-start)/1000.0)
	frame_index += 1

func run() -> void:
	var scenario := "title"
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			scenario = argument.trim_prefix("--scenario=")
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	harness = HARNESS.new()
	harness.manual = true
	root.add_child(harness)
	var prepared: bool = await harness.prepare_scenario(scenario)
	if not prepared:
		push_error("Warm impact CPU profile failed to find/settle original editable terrain")
		quit(1)
		return
	# All automatic script callbacks stop; calls below remain explicit. Engine
	# physics/audio servers may still use wall time, which is recorded as a limit.
	var previous_process_mode := root.process_mode
	root.process_mode = Node.PROCESS_MODE_DISABLED
	harness.result = {"scenario":scenario,"engine":Engine.get_version_info().string,"renderer":DisplayServer.get_name(),
		"mode":"fixed60Hz manual Main→Player→synchronous World→Effects→Audio→HUD CPU throughput",
		"fixed_delta":STEP,"seed":SEED,"preparation":harness.preparation,
		"limits":"GPU excluded; synchronous chunk flush differs from production4ms queue; engine mixer/physics servers use wall time"}
	harness.start_phase("idle")
	for frame: int in 120:
		tick(false)
	harness.finish_phase()
	harness.start_phase("shoot")
	for frame: int in 480:
		tick(true)
	harness.finish_phase()
	harness.start_phase("tail")
	for frame: int in 720:
		tick(false)
		if frame>=120 and harness.settled() and harness.effects_finished():
			break
	harness.finish_phase()
	harness.finish_scenario()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null:
			push_error("Cannot write CPU profile output "+output)
			quit(1)
			return
		file.store_string(JSON.stringify(harness.result,"  ")+"\n")
	var valid: bool = harness.result.valid
	var cleanup_started := Time.get_ticks_usec()
	root.process_mode = previous_process_mode
	harness.app.stop_audio()
	print("PROFILE_CLEANUP_AUDIO_USEC: "+str(Time.get_ticks_usec()-cleanup_started))
	harness.queue_free()
	# Drain deferred resources and the real mixer before reporting cleanup.
	await process_frame
	print("PROFILE_CLEANUP_TREE_USEC: "+str(Time.get_ticks_usec()-cleanup_started))
	await create_timer(0.2).timeout
	print("PROFILE_CLEANUP_TOTAL_USEC: "+str(Time.get_ticks_usec()-cleanup_started))
	print("WARM BLOCK IMPACT CPU PROFILE: "+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
