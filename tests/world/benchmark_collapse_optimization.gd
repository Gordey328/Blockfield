extends SceneTree
## Paired same-process CPU measurement; no rendered browser/FPS implication.
## --headless --path game --script ../tests/world/benchmark_collapse_optimization.gd -- --output=<path>
const DATA = preload("res://world/voxel_data.gd")
const REFERENCE = preload("res://../tests/world/collapse_reference.gd")
const WORLD = preload("res://world/voxel_world.gd")
const CHUNK = preload("res://world/voxel_chunk.gd")
const CHUNK_REFERENCE = preload("res://../tests/world/empty_chunk_reference.gd")
const SAMPLES := 7
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
	return {"samples":ordered.size(),"p50_usec":ordered[int((ordered.size()-1)*0.5)],"p95_usec":ordered[int((ordered.size()-1)*0.95)],"max_usec":ordered[-1],"mean_usec":float(total)/ordered.size()}

func fixture(script: Script, scenario: String) -> RefCounted:
	var data: RefCounted = script.new()
	data.clear(Vector3i(96,48,96),7)
	data.set_journal_budget(0)
	data.seed_box(Vector3i.ZERO,Vector3i(96,2,96),0x01000000)
	match scenario:
		"supported_surface":
			data.seed_box(Vector3i(4,2,4),Vector3i(92,30,92),0x015a8163)
		"roof6400":
			data.seed_box(Vector3i(47,2,47),Vector3i(48,30,48),0x01000000)
			data.seed_box(Vector3i(8,30,8),Vector3i(88,31,88),0x01abcdef)
		"slab25600":
			data.seed_box(Vector3i(47,2,47),Vector3i(48,30,48),0x01000000)
			data.seed_box(Vector3i(8,30,8),Vector3i(88,34,88),0x01abcdef)
	return data

func cut(data: RefCounted, _scenario: String) -> Dictionary:
	var cells: Array[Vector3i] = [Vector3i(47,29,47)]
	return data.remove_blocks(cells,false,{"tick":1})

func collapse_pair(scenario: String) -> void:
	var reference_times: Array[int] = []
	var candidate_times: Array[int] = []
	var changes := 0
	var groups := 0
	# Alternate order to reduce shared-process warm-up/temperature bias.
	for sample: int in SAMPLES+1:
		var reference := fixture(REFERENCE,scenario)
		var candidate := fixture(DATA,scenario)
		var expected: Dictionary
		var actual: Dictionary
		var reference_usec := 0
		var candidate_usec := 0
		if sample%2 == 0:
			var start := Time.get_ticks_usec()
			expected = cut(reference,scenario)
			reference_usec = Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			actual = cut(candidate,scenario)
			candidate_usec = Time.get_ticks_usec()-start
		else:
			var start := Time.get_ticks_usec()
			actual = cut(candidate,scenario)
			candidate_usec = Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			expected = cut(reference,scenario)
			reference_usec = Time.get_ticks_usec()-start
		if actual != expected or candidate.blocks != reference.blocks:
			failed = true
			push_error("COLLAPSE BENCHMARK: paired exact transaction/data mismatch " + scenario)
		changes = actual.changes.size()
		groups = actual.collapse_groups.size()
		if sample > 0:
			reference_times.append(reference_usec)
			candidate_times.append(candidate_usec)
	var row := {"kind":"authority_collapse","scenario":scenario,"changes":changes,"groups":groups,"reference":distribution(reference_times),"candidate":distribution(candidate_times)}
	rows.append(row)
	print("MAXOPT WORLD CPU: " + JSON.stringify(row))

func chunk_pair(scenario: String) -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,32,32))
	world.water_enabled = false
	root.add_child(world)
	world.set_process(false)
	world._ensure_material()
	if scenario == "occupied_single":
		world.data.seed_box(Vector3i(4,4,4),Vector3i(5,5,5),0x01000000)
	elif scenario == "occupied_dense":
		world.data.seed_box(Vector3i.ZERO,Vector3i(16,16,16),0x01abcdef)
	var reference_times: Array[int] = []
	var candidate_times: Array[int] = []
	for sample: int in 41:
		var reference := CHUNK_REFERENCE.new()
		var candidate := CHUNK.new()
		var reference_usec := 0
		var candidate_usec := 0
		if sample%2 == 0:
			var start := Time.get_ticks_usec()
			reference.rebuild(world,world._material)
			reference_usec = Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			candidate.rebuild(world,world._material)
			candidate_usec = Time.get_ticks_usec()-start
		else:
			var start := Time.get_ticks_usec()
			candidate.rebuild(world,world._material)
			candidate_usec = Time.get_ticks_usec()-start
			start = Time.get_ticks_usec()
			reference.rebuild(world,world._material)
			reference_usec = Time.get_ticks_usec()-start
		if reference.face_count != candidate.face_count or reference.collision_face_count != candidate.collision_face_count:
			failed = true
			push_error("EMPTY CHUNK BENCHMARK: face mismatch " + scenario)
		if sample > 0:
			reference_times.append(reference_usec)
			candidate_times.append(candidate_usec)
		reference.free()
		candidate.free()
	world.free()
	var row := {"kind":"chunk_full_cpu","scenario":scenario,"reference":distribution(reference_times),"candidate":distribution(candidate_times)}
	rows.append(row)
	print("MAXOPT WORLD CPU: " + JSON.stringify(row))

func run() -> void:
	for scenario: String in ["supported_surface","roof6400","slab25600"]:
		collapse_pair(scenario)
	for scenario: String in ["empty","occupied_single","occupied_dense"]:
		chunk_pair(scenario)
	failed = failed or rows.size() != 6
	var report := {"engine":Engine.get_version_info().string,"source_reference":"d5516eb2bfd22bd5d03f32ac751dce7c01086876 retained functions","backend":DisplayServer.get_name(),"exact_pairs":not failed,"rows":rows}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file := FileAccess.open(argument.trim_prefix("--output="),FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(report,"\t"))
	print("MAXOPT WORLD BENCHMARK: %d workloads, %d failures" % [rows.size(),1 if failed else 0])
	quit(1 if failed else 0)
