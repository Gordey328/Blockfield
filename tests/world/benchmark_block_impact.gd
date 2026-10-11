extends SceneTree
## Opt-in CPU benchmark; virtual SMG cadence is not a rendered-FPS measurement.
## godot --headless --path game --script ../tests/world/benchmark_block_impact.gd -- --output=<json path>
const WORLD = preload("res://world/voxel_world.gd")
const SESSION = preload("res://gameplay/local_session.gd")
const CHUNK = preload("res://world/voxel_chunk.gd")
const SAMPLES := 24
const REPEATS := 3
const FRAME_SECONDS := 1.0 / 60.0
var rows: Array[Dictionary] = []
var failed := false

func _initialize() -> void:
	call_deferred("run")

func distribution(values: Array[int]) -> Dictionary:
	var ordered: Array[int] = values.duplicate()
	ordered.sort()
	var total := 0
	for value: int in ordered:
		total += value
	if ordered.is_empty():
		return {"samples":0,"p50_usec":0,"p95_usec":0,"max_usec":0,"mean_usec":0.0}
	return {"samples":ordered.size(),"p50_usec":ordered[int((ordered.size()-1)*0.5)],
		"p95_usec":ordered[int((ordered.size()-1)*0.95)],"max_usec":ordered[-1],"mean_usec":float(total)/ordered.size()}

func work(world: Node3D) -> Dictionary:
	return world.get_rebuild_stats() if world.has_method("get_rebuild_stats") else {}

func delta_work(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["mesh_builds","collision_builds","color_updates","color_vertices","color_upload_bytes","build_cancellations"]:
		if before.has(key) and after.has(key):
			result[key] = int(after[key])-int(before[key])
	return result

func fixture() -> Node3D:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,32,32))
	world.water_enabled = false
	world.visual_effects_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	world.data.seed_box(Vector3i(4,4,4),Vector3i(28,16,28),0x01bf8051)
	world._mark_all_chunks()
	world.rebuild_now()
	return world

func visible_cells(world: Node3D, chunk_key: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var chunk: Node3D = world._chunks[chunk_key]
	if chunk.mesh_instance.mesh == null:
		return result
	var arrays: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var seen: Dictionary = {}
	for first: int in range(0,vertices.size(),4):
		var face: int = CHUNK.DIRECTIONS.find(Vector3i(normals[first]))
		var cell: Vector3i = chunk_key*CHUNK.CHUNK_SIZE+Vector3i(vertices[first]-CHUNK.CORNERS[face][0])
		if cell.y > 1 and not seen.has(cell):
			seen[cell] = true
			result.append(cell)
	return result

func damage(world: Node3D, title: String, cells: Array[Vector3i], repeated: bool, cadence: bool) -> void:
	var operation: Array[int] = []
	var presentation: Array[int] = []
	var slices: Array[int] = []
	var peak_pending := 0
	var work_delta: Dictionary = {}
	var delay: float = SESSION.WEAPON_PROFILES["0.75"][1].delay
	var frames_per_shot := ceili(delay/FRAME_SECONDS)
	for repeat: int in REPEATS:
		if not repeated:
			world.clear_block_damage()
			world.rebuild_now()
		var before: Dictionary = work(world)
		for cell: Vector3i in cells:
			var started := Time.get_ticks_usec()
			world.set_block_damaged(cell,true)
			operation.append(Time.get_ticks_usec()-started)
			peak_pending = maxi(peak_pending,int(world.get_stats().dirty_chunks))
			started = Time.get_ticks_usec()
			if cadence:
				for frame: int in frames_per_shot:
					var slice_start := Time.get_ticks_usec()
					world._process(FRAME_SECONDS)
					slices.append(Time.get_ticks_usec()-slice_start)
			else:
				world.rebuild_now()
			presentation.append(Time.get_ticks_usec()-started)
		var repeat_work: Dictionary = delta_work(before,work(world))
		for key: String in repeat_work:
			work_delta[key] = int(work_delta.get(key,0))+int(repeat_work[key])
	world.rebuild_now()
	var row := {"map":title,"phase":"already_dark" if repeated else "first_hit",
		"flush":"virtual_60hz_cadence" if cadence else "synchronous","smg_delay_seconds":delay,
		"shots_per_repeat":cells.size(),"repeats":REPEATS,"operation":distribution(operation),
		"presentation":distribution(presentation),"frame_slices":distribution(slices),"peak_pending_chunks":peak_pending,
		"work_delta":work_delta,"final_work":work(world),"world":world.get_stats()}
	rows.append(row)
	print("BLOCK_IMPACT_BENCHMARK_ROW: "+JSON.stringify(row))

func destruction(world: Node3D, title: String, cells: Array[Vector3i]) -> void:
	world.clear_block_damage()
	world.rebuild_now()
	var operation: Array[int] = []
	var presentation: Array[int] = []
	var slices: Array[int] = []
	var peak_pending := 0
	var before: Dictionary = work(world)
	var actual := 0
	for cell: Vector3i in cells:
		if world.get_block(cell) == 0:
			continue
		actual += 1
		var started := Time.get_ticks_usec()
		var removal: Array[Vector3i] = [cell]
		world.remove_blocks(removal)
		operation.append(Time.get_ticks_usec()-started)
		peak_pending = maxi(peak_pending,int(world.get_stats().dirty_chunks))
		started = Time.get_ticks_usec()
		for frame: int in ceili(float(SESSION.WEAPON_PROFILES["0.75"][1].delay)/FRAME_SECONDS):
			var slice_start := Time.get_ticks_usec()
			world._process(FRAME_SECONDS)
			slices.append(Time.get_ticks_usec()-slice_start)
		presentation.append(Time.get_ticks_usec()-started)
	world.rebuild_now()
	var row := {"map":title,"phase":"destroy","flush":"virtual_60hz_cadence","requested_shots":cells.size(),
		"actual_shots":actual,"operation":distribution(operation),"presentation":distribution(presentation),
		"frame_slices":distribution(slices),"peak_pending_chunks":peak_pending,
		"work_delta":delta_work(before,work(world)),"final_work":work(world),"world":world.get_stats()}
	rows.append(row)
	print("BLOCK_IMPACT_BENCHMARK_ROW: "+JSON.stringify(row))

func measure_map(world: Node3D, title: String, key: Vector3i) -> void:
	var exposed: Array[Vector3i] = visible_cells(world,key)
	var cells: Array[Vector3i] = []
	# Spread samples across the chunk's exposed cells rather than one small patch.
	for sample: int in mini(SAMPLES,exposed.size()):
		cells.append(exposed[int(sample*exposed.size()/mini(SAMPLES,exposed.size()))])
	if cells.is_empty():
		failed = true
		push_error("Block impact benchmark needs visible solid cells in "+title)
		return
	for cadence: bool in [false,true]:
		damage(world,title,cells,false,cadence)
		damage(world,title,cells,true,cadence)
	destruction(world,title,cells)

func run() -> void:
	var world: Node3D = fixture()
	measure_map(world,"grounded_dense_wall",Vector3i.ZERO)
	var error: Error = world.load_vxl("res://assets/openspades/maps/Title.vxl")
	if error != OK:
		failed = true
		push_error("Block impact Title import failed: "+str(error))
	else:
		var most_faces := -1
		var chosen := Vector3i.ZERO
		for key: Vector3i in world._chunks:
			var chunk: Node3D = world._chunks[key]
			if chunk.face_count > most_faces:
				most_faces = chunk.face_count
				chosen = key
		measure_map(world,"Title.vxl densest streamed chunk "+str(chosen),chosen)
	var result := {"engine":Engine.get_version_info().string,"renderer":DisplayServer.get_name(),
		"method":"CPU operations and manually stepped virtual SMG cadence; excludes real frame intervals, GPU and physical-device FPS",
		"rows":rows,"failed":failed}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var path: String = argument.trim_prefix("--output=")
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file := FileAccess.open(path,FileAccess.WRITE)
			if file == null:
				failed = true
				push_error("Cannot write block impact benchmark output "+path)
			else:
				file.store_string(JSON.stringify(result,"  ")+"\n")
	world.free()
	await process_frame
	print("BLOCK_IMPACT_BENCHMARK: "+JSON.stringify(result))
	quit(1 if failed else 0)
