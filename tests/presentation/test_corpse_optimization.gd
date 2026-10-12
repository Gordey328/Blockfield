extends SceneTree
## Compare against the independent original equations, not an optimized mirror.
## Optional timing is component script CPU and never a whole-game FPS claim.
const CORPSE = preload("res://presentation/corpse.gd")
const REFERENCE = preload("corpse_reference.gd")
const WORLD = preload("res://world/voxel_world.gd")
const DATA = preload("res://world/voxel_data.gd")
const MODELS = preload("res://presentation/openspades_models.gd")
const REFERENCE_SHA256 := "f265dab2369eb362ae570d3c0c6d7067715168c144615f6b760e0c7e2614bc9e"
const PART_NAMES: Array[String] = ["Torso","Head","Arm1","Arm2","Leg1","Leg2"]
var assertions: int = 0
var failures: int = 0
var benchmark: bool = false
var report_path: String = ""

class ProxyWorld extends Node3D:
	var source: VoxelWorld
	var dimensions: Vector3i:
		get:return source.dimensions
	var water_level: float:
		get:return source.water_level
	func get_block(cell: Vector3i) -> int:return source.get_block(cell)
	func clip_box(point: Vector3) -> bool:return source.clip_box(point)

class ReentrantWorld extends ProxyWorld:
	var corpse: Node3D
	var querying: bool = false
	var nested_result: Dictionary = {}
	func get_block(cell: Vector3i) -> int:
		if not querying:
			querying = true
			nested_result = corpse._ray(Vector3(1.5,5.5,1.5),Vector3(1.6,5.5,1.5),8)
			querying = false
		return source.get_block(cell)

class OverrideWorld extends VoxelWorld:
	var clip_calls: int = 0
	func clip_box(point: Vector3) -> bool:
		clip_calls += 1
		# A custom world's predicate may have effects within one source step.
		return clip_calls%11 == 0 or super.clip_box(point)

class OverrideData extends VoxelData:
	var clip_calls: int = 0
	func clip_box(point: Vector3) -> bool:
		clip_calls += 1
		return clip_calls%13 == 0 or super.clip_box(point)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--benchmark":benchmark = true
		elif argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
	call_deferred("_run")

func _run() -> void:
	for scenario: String in ["floor","wall","water","bounds","variable"]:
		await _differential(scenario)
	await _override_checks()
	await _data_override_checks()
	await _ray_contracts()
	var report: Dictionary = {"assertions":assertions,"failures":failures,"reference_sha256":REFERENCE_SHA256}
	if benchmark:
		report["cohorts"] = await _benchmark()
		report["assertions"] = assertions
		report["failures"] = failures
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report,"\t"))
			file.close()
	print("CORPSE OPTIMIZATION: %d assertions, %d failures" % [assertions,failures])
	if benchmark:print("CORPSE COMPONENT BENCHMARK: "+JSON.stringify(report))
	MODELS.clear_cache()
	quit(0 if failures == 0 else 1)

func _world() -> VoxelWorld:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,16,32))
	world.data.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x01605040)
	world.data.seed_box(Vector3i(16,2,4),Vector3i(17,11,28),0x01ccaa88)
	world.water_level = -10
	return world

func _state(seed_value: int = 42) -> Dictionary:
	return {"feet_position":Vector3(13.5,2,12.5),"yaw":.24,"team":seed_value%2,"player_id":seed_value,"seed":seed_value,"velocity":Vector3(1.8,.2,.3),"impulse":Vector3(.5,1.2,.4)}

func _differential(scenario: String) -> void:
	var world: VoxelWorld = _world()
	var proxy := ProxyWorld.new()
	proxy.source = world
	var candidate := CORPSE.new()
	var reference := REFERENCE.new()
	var generic := CORPSE.new()
	root.add_child(candidate)
	root.add_child(reference)
	root.add_child(generic)
	var state: Dictionary = _state()
	match scenario:
		"wall":state.feet_position = Vector3(15.5,2,12.5);state.velocity = Vector3(4,1,-2)
		"water":world.water_level = 7;state.feet_position = Vector3(8,2,8)
		"bounds":state.feet_position = Vector3(31.8,.1,-.1);state.velocity = Vector3(5,-1,-3)
		"variable":state.crouch = true;state.yaw = -1.4
	candidate.setup(world,state)
	reference.setup(world,state)
	generic.setup(proxy,state)
	for frame: int in range(100):
		if frame == 23:
			world.data.set_block(Vector3i(14,1,12),0)
			world.data.set_block(Vector3i(15,3,12),0x01aaccee)
		if frame == 49:
			world.data.clear(Vector3i(24,12,24),world.data.epoch+1)
			world.data.seed_box(Vector3i.ZERO,Vector3i(24,2,24),0x018899aa)
		if frame == 73:
			var replacement := DATA.new()
			replacement.clear(Vector3i(32,16,32),world.data.epoch+1)
			replacement.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x0199aabb)
			world.data = replacement
			world.water_level = 3
		if frame%17 == 0:
			var impulse := Vector3(.1,.5,-.2)
			candidate.add_impulse(impulse)
			reference.add_impulse(impulse)
			generic.add_impulse(impulse)
		var delta: float = [1.0/60.0,1.0/30.0,.07,.2,.5,0.0][frame%6] if scenario == "variable" else 1.0/60.0
		candidate.step(delta)
		reference.step(delta)
		generic.step(delta)
		_check(_snapshot(candidate) == _snapshot(reference), "Independent source exact state/matrix equivalence %s frame %d" % [scenario,frame])
		_check(_snapshot(generic) == _snapshot(reference), "Generic Node3D fallback exact equivalence %s frame %d" % [scenario,frame])
		_check(candidate._step_cells.is_empty() and candidate._step_world == null and not candidate._step_cache_enabled, "No occupancy/world version survives source step")
	# Queries outside step must immediately observe edits and their old semantics.
	world.data.set_block(Vector3i(3,1,3),0x01aabbcc)
	_check(candidate._clip(Vector3(3.2,.2,3.2)) == reference._clip(Vector3(3.2,.2,3.2)), "Live outside-step clip retains source y0 remap")
	_check(candidate._solid_wrapped(Vector3i(35,1,3)) == reference._solid_wrapped(Vector3i(35,1,3)), "Live outside-step ray occupancy retains horizontal wrap")
	_check(candidate._query_cell(Vector3i(3,1,3)), "New cache helper falls back to live queries outside step")
	candidate.free()
	reference.free()
	generic.free()
	proxy.free()
	world.free()
	await process_frame
	await process_frame

func _override_checks() -> void:
	var candidate_world := OverrideWorld.new()
	var reference_world := OverrideWorld.new()
	for world: VoxelWorld in [candidate_world,reference_world]:
		world.clear_world(Vector3i(32,16,32))
		world.data.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x01605040)
		world.water_level = -10
	var candidate := CORPSE.new()
	var reference := REFERENCE.new()
	root.add_child(candidate)
	root.add_child(reference)
	candidate.setup(candidate_world,_state())
	reference.setup(reference_world,_state())
	for frame: int in range(40):
		candidate.step(.07)
		reference.step(.07)
		_check(_snapshot(candidate) == _snapshot(reference) and candidate_world.clip_calls == reference_world.clip_calls, "Custom VoxelWorld override keeps virtual calls and synchronous effects frame %d" % frame)
	candidate.free()
	reference.free()
	candidate_world.free()
	reference_world.free()
	await process_frame
	await process_frame

func _benchmark() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for workload: Dictionary in [{"name":"normal60","delta":1.0/60.0,"frames":120},{"name":"slow100ms","delta":.1,"frames":32},{"name":"resume250ms","delta":.25,"frames":12}]:
		var world: VoxelWorld = _world()
		var candidates: Array[OpenSpadesCorpse] = []
		var references: Array[Node3D] = []
		for index: int in range(16):
			var state: Dictionary = _state(42+index)
			state.feet_position = Vector3(6.5+index%4*2,2,6.5+floori(index/4.0)*2)
			var candidate := CORPSE.new()
			var reference := REFERENCE.new()
			root.add_child(candidate)
			root.add_child(reference)
			candidate.setup(world,state)
			reference.setup(world,state)
			candidates.append(candidate)
			references.append(reference)
		await process_frame
		for frame: int in range(120):
			for corpse: OpenSpadesCorpse in candidates:corpse.step(1.0/60.0)
			for corpse: Node3D in references:corpse.step(1.0/60.0)
		var samples: Array[Dictionary] = []
		for repeat: int in range(3):
			var candidate_usec: int = 0
			var reference_usec: int = 0
			for mode: String in ["reference","candidate"] if repeat%2 == 0 else ["candidate","reference"]:
				var started: int = Time.get_ticks_usec()
				for frame: int in range(int(workload.frames)):
					if mode == "candidate":
						for corpse: OpenSpadesCorpse in candidates:corpse.step(float(workload.delta))
					else:
						for corpse: Node3D in references:corpse.step(float(workload.delta))
				var elapsed: int = Time.get_ticks_usec()-started
				if mode == "candidate":candidate_usec = elapsed
				else:reference_usec = elapsed
			var exact: bool = true
			for index: int in range(16):exact = exact and _snapshot(candidates[index]) == _snapshot(references[index])
			_check(exact, "Measured16-body cohort retains independent exact states")
			samples.append({"reference_usec":reference_usec,"candidate_usec":candidate_usec,"exact":exact})
		results.append({"workload":workload.name,"delta":workload.delta,"frames":workload.frames,"corpses":16,
			"substeps_per_corpse_frame":maxi(4,ceili(float(workload.delta)*240.0)),"samples":samples})
		for corpse: Node3D in references:corpse.free()
		for corpse: OpenSpadesCorpse in candidates:corpse.free()
		world.free()
		await process_frame
		await process_frame
	return results

func _data_override_checks() -> void:
	var worlds: Array[VoxelWorld] = [_world(),_world()]
	for world: VoxelWorld in worlds:
		var custom := OverrideData.new()
		custom.clear(Vector3i(32,16,32),1)
		custom.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x01605040)
		custom.water_level = -10
		world.data = custom
	var candidate := CORPSE.new()
	var reference := REFERENCE.new()
	root.add_child(candidate)
	root.add_child(reference)
	candidate.setup(worlds[0],_state())
	reference.setup(worlds[1],_state())
	for frame: int in range(20):
		candidate.step(.07)
		reference.step(.07)
		_check(_snapshot(candidate) == _snapshot(reference) and (worlds[0].data as OverrideData).clip_calls == (worlds[1].data as OverrideData).clip_calls, "Custom VoxelData preserves virtual predicates and effects frame %d" % frame)
	candidate.free()
	reference.free()
	for world: VoxelWorld in worlds:world.free()
	await process_frame
	await process_frame

func _ray_contracts() -> void:
	var world: VoxelWorld = _world()
	var candidate := CORPSE.new()
	var reference := REFERENCE.new()
	root.add_child(candidate)
	root.add_child(reference)
	candidate.setup(world,_state())
	reference.setup(world,_state())
	for pair: Array in [[Vector3(15.5,5.5,12.5),Vector3(17.5,5.5,12.5)],
		[Vector3(17.5,5.5,12.5),Vector3(15.5,5.5,12.5)],
		[Vector3(1.5,3.5,1.5),Vector3(3.5,5.5,3.5)],
		[Vector3(16.5,5.5,12.5),Vector3(17.5,5.5,12.5)],
		[Vector3(16.5,5.5,12.5),Vector3(16.5,5.5,12.5)]]:
		var original: Dictionary = reference._ray(pair[0],pair[1],8)
		var actual: Dictionary = candidate._ray(pair[0],pair[1],8)
		_check(actual == original, "Owned ray result matches source hit/startsolid/tie/zero-segment fields")
		var saved: Dictionary = actual.duplicate()
		candidate._ray(Vector3(2,3,2),Vector3(4,3,4),8)
		_check(actual == saved, "Later ray casts cannot alias a caller's retained Dictionary")
	for corpse: Node3D in [candidate,reference]:
		corpse.positions[0] = Vector3(15.5,5.5,12.5)
		corpse.positions[1] = Vector3(17.5,5.5,12.5)
		corpse.last_positions = corpse.positions.duplicate()
		corpse.velocities.fill(Vector3.ZERO)
	candidate._step_world = world
	candidate._step_cache_enabled = true
	candidate._step_dimensions = world.dimensions
	candidate._line_collision(0,1,.01)
	reference._line_collision(0,1,.01)
	_check(_snapshot(candidate) == _snapshot(reference), "Two retained internal ray records preserve wall penetration/escape exactly")
	_check(candidate._first_line_ray != candidate._second_line_ray and candidate._first_line_ray.hit and candidate._second_line_ray.hit, "Opposite line casts retain independent hit results")
	for index: int in range(400):candidate._query_cell(Vector3i(index%32,1,index/32))
	_check(candidate._step_cells.size() == 256, "Occupancy cache has a hard256-cell bound under excess distinct queries")
	candidate._step_cache_enabled = false
	candidate._step_world = null
	candidate._step_cells.clear()
	var candidate_proxy := ReentrantWorld.new()
	var reference_proxy := ReentrantWorld.new()
	candidate_proxy.source = world
	reference_proxy.source = world
	candidate_proxy.corpse = candidate
	reference_proxy.corpse = reference
	candidate.world = candidate_proxy
	reference.world = reference_proxy
	_check(candidate._ray(Vector3(15.5,5.5,12.5),Vector3(17.5,5.5,12.5),8) == reference._ray(Vector3(15.5,5.5,12.5),Vector3(17.5,5.5,12.5),8), "Reentrant custom world retains independent outer ray fields")
	_check(candidate_proxy.nested_result == reference_proxy.nested_result and not candidate_proxy.nested_result.hit, "Reentrant custom world retains independent nested miss fields")
	candidate.free()
	reference.free()
	candidate_proxy.free()
	reference_proxy.free()
	world.free()
	await process_frame
	await process_frame

func _snapshot(corpse: Node3D) -> Array:
	var values: Array = [corpse.positions,corpse.velocities,corpse.last_positions,corpse.last_forces,
		corpse._edge_velocities,corpse._edge_initialized,corpse.simulation_time]
	for part: String in PART_NAMES:values.append((corpse._parts[part] as Node3D).transform)
	return values

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)
