extends SceneTree
## Opt-in decorative casing/falling CPU comparison; world authority is excluded.
const EFFECTS = preload("res://presentation/openspades_effects.gd")
const CLUSTER = preload("res://world/falling_cluster.gd")
var report_path: String = ""
var label: String = "unlabelled"

class QueryWorld extends Node3D:
	var queries: int = 0
	var water_level: float = -100.0
	func get_block(cell: Vector3i) -> int:
		queries += 1
		return 0x01777777 if cell.y == 0 else 0
	func clip_box(_point: Vector3) -> bool:
		queries += 1
		return false
	func clip_world(point: Vector3) -> bool:
		queries += 1
		return point.y < 0.0
	func get_effects_observer() -> Vector3:
		return Vector3(5, 20, 5)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	call_deferred("run")

func run() -> void:
	var world := QueryWorld.new()
	root.add_child(world)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(5, 6, 10)
	var effects := EFFECTS.new()
	effects.max_particles = 0
	effects.max_tracers = 0
	effects.max_lights = 0
	effects.audio_enabled = false
	effects.shake_level = 0
	root.add_child(effects)
	effects.setup(world, camera)
	effects.set_process(false)
	var contacts: Array[int] = [0]
	effects.casing_contact.connect(func(_point: Vector3, _water: bool, _weapon: int): contacts[0] += 1)
	var before_nodes: int = effects.stats().created_nodes
	var peak_casings: int = 0
	var casing_live_usec: int = 0
	var casing_tail_usec: int = 0
	for frame: int in range(960):
		var started: int = Time.get_ticks_usec()
		if frame < 480 and frame % 4 == 0:
			effects.eject_shell(Vector3(5, 4, 5), Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, (frame / 4) % 2)
		effects.update_effects(1.0 / 60.0)
		var elapsed_usec: int = Time.get_ticks_usec() - started
		if frame < 480:
			casing_live_usec += elapsed_usec
		else:
			casing_tail_usec += elapsed_usec
		peak_casings = maxi(peak_casings, int(effects.stats().casings))
	var casings: Dictionary = {"live_usec": casing_live_usec, "tail_usec": casing_tail_usec,
		"cap": effects.max_casings, "peak": peak_casings, "contacts": contacts[0],
		"terrain_queries": world.queries, "new_nodes": int(effects.stats().created_nodes) - before_nodes,
		"remaining": effects.stats().casings}
	effects.queue_free()
	await process_frame
	var cases: Array[Dictionary] = []
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	for dimension: int in [10, 24]:
		var cells: Array[Vector3i] = []
		var colors := PackedInt32Array()
		for y: int in range(dimension):
			for z: int in range(dimension):
				for x: int in range(dimension):
					cells.append(Vector3i(x, y + 20, z))
					colors.append(0x01665544)
		var cluster := CLUSTER.new()
		world.add_child(cluster)
		cluster.set_process(false)
		world.queries = 0
		var started: int = Time.get_ticks_usec()
		cluster.setup(world, cells, colors, Vector3(5, 20, 5), material, 7341)
		var setup_usec: int = Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		for frame: int in range(190):
			if cluster.phase == CLUSTER.Phase.COMPLETE:
				break
			cluster.step(1.0 / 60.0)
		var step_usec: int = Time.get_ticks_usec() - started
		cases.append({"blocks": cells.size(), "setup_usec": setup_usec, "step_usec": step_usec,
			"terrain_queries": world.queries, "nodes": cluster.get_child_count(), "stats": cluster.get_effect_stats()})
		await process_frame
	var result: Dictionary = {"engine": Engine.get_version_info().string, "label": label,
		"display_server": DisplayServer.get_name(), "casings": casings, "falling": cases,
		"method": "Native headless decorative script timings; public casing emission120 events over8s with8s tail, then1000/13824-cell falling group preparation and lifetime. Timed calls exclude input-data construction. Reduced lifetime/count/geometry/debris are deliberate user replacements. No whole-game FPS/GPU claim."}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot open simple-effects benchmark report")
			quit(1)
			return
		file.store_string(JSON.stringify(result, "  ") + "\n")
		file.close()
	print("SIMPLE_EFFECTS_BENCHMARK: " + JSON.stringify(result))
	world.queue_free()
	camera.queue_free()
	await process_frame
	quit(0)
