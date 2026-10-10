extends SceneTree
## Literal source-math fixtures; no native checkout/compiler needed at runtime.
const DATA = preload("res://world/voxel_data.gd")
const WORLD = preload("res://world/voxel_world.gd")
const COLOR := 0x01604020
var assertions := 0
var failures := 0
var map: VoxelData

class QueryOnlyData extends "res://world/voxel_data.gd":
	var calls := 0
	func get_block(cell: Vector3i) -> int:
		calls += 1
		return 0x01000000 if cell == Vector3i(2, 53, 1) else 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SOURCE RAYS: " + message)

func seed_native(cells: Array, color: int) -> void:
	for native_cell: Vector3i in cells:
		var cell := Vector3i(native_cell.x, 63 - native_cell.z, native_cell.y)
		map.seed_box(cell, cell + Vector3i.ONE, color)

func check_result(label: String, result: Dictionary, expected: Array) -> void:
	check(result.valid and result.error.is_empty(), label + " valid result")
	check(result.hit == expected[0], label + " source hit flag")
	check(result.start_solid == expected[1], label + " source startSolid flag")
	check(result.cell == expected[2], label + " unwrapped native hit/last cell mapped to Godot")
	check(result.normal == expected[3], label + " source normal/tie priority")
	check(result.position == expected[4], label + " binary32 hit position/native corner/miss origin")
	check(result.steps == expected[5], label + " exact crossed-grid-plane count")

func fixture(label: String, origin: Vector3, direction: Vector3, budget: int, solids: Array, source_expected: Array, legacy_expected: Array) -> void:
	seed_native(solids, COLOR)
	check_result(label + " CastRay2", map.cast_source_ray(origin, direction, budget), source_expected)
	check_result(label + " CastRay", map.cast_source_ray_legacy(origin, direction, budget), legacy_expected)
	seed_native(solids, 0)

func run() -> void:
	map = DATA.new()
	check(map.clear(Vector3i(512, 64, 512), 73) == OK, "native map initialized")
	fixture("cardinal", Vector3(1.25,53.75,5.5), Vector3.RIGHT, 4, [Vector3i(5,5,10)],
		[true,false,Vector3i(5,53,5),Vector3i.LEFT,Vector3(5,53.75,5.5),4],
		[true,false,Vector3i(5,53,5),Vector3i.ZERO,Vector3(5,54,5),4])
	fixture("nativeY-beforeZ tie", Vector3(10.5,53.5,10.5), Vector3(0,-1,1), 1, [Vector3i(10,11,10),Vector3i(10,10,11)],
		[true,false,Vector3i(10,53,11),Vector3i.FORWARD,Vector3(10.5,53,11),1],
		[true,false,Vector3i(10,52,10),Vector3i.ZERO,Vector3(10,53,10),1])
	fixture("triple tie", Vector3(20.5,53.5,20.5), Vector3(1,-1,1), 3, [Vector3i(21,21,11)],
		[true,false,Vector3i(21,52,21),Vector3i.UP,Vector3(21,53,21),3],
		[true,false,Vector3i(21,52,21),Vector3i.ZERO,Vector3(21,53,21),3])
	fixture("diagonal step cap", Vector3(1.5,53.5,1.5), Vector3(1,0,1), 4, [Vector3i(4,4,10)],
		[false,false,Vector3i(3,53,3),Vector3i.FORWARD,Vector3(1.5,53.5,1.5),4],
		[false,false,Vector3i(3,53,3),Vector3i.ZERO,Vector3(1.5,53.5,1.5),4])
	fixture("diagonal hit", Vector3(1.5,53.5,1.5), Vector3(1,0,1), 6, [Vector3i(4,4,10)],
		[true,false,Vector3i(4,53,4),Vector3i.FORWARD,Vector3(4,53.5,4),6],
		[true,false,Vector3i(4,53,4),Vector3i.ZERO,Vector3(4,54,4),6])
	fixture("mixed miss", Vector3(.25,51.75,.75), Vector3(.3,-.5,.4), 7, [],
		[false,false,Vector3i(1,48,3),Vector3i.FORWARD,Vector3(.25,51.75,.75),7],
		[false,false,Vector3i(1,48,3),Vector3i.ZERO,Vector3(.25,51.75,.75),7])
	fixture("negative exact face", Vector3(2,53.75,2.25), Vector3.LEFT, 1, [Vector3i(1,2,10)],
		[true,false,Vector3i(1,53,2),Vector3i.RIGHT,Vector3(2,53.75,2.25),1],
		[true,false,Vector3i(1,53,2),Vector3i.ZERO,Vector3(1,54,2),1])
	fixture("positive X wrap", Vector3(511.25,53.75,5.5), Vector3.RIGHT, 1, [Vector3i(0,5,10)],
		[true,false,Vector3i(512,53,5),Vector3i.LEFT,Vector3(512,53.75,5.5),1],
		[true,false,Vector3i(512,53,5),Vector3i.ZERO,Vector3(512,54,5),1])
	fixture("negative X wrap", Vector3(.75,53.75,5.5), Vector3.LEFT, 1, [Vector3i(511,5,10)],
		[true,false,Vector3i(-1,53,5),Vector3i.RIGHT,Vector3(0,53.75,5.5),1],
		[true,false,Vector3i(-1,53,5),Vector3i.ZERO,Vector3(-1,54,5),1])
	fixture("positive nativeY wrap", Vector3(7.2,47.7,511.75), Vector3.BACK, 1, [Vector3i(7,0,16)],
		[true,false,Vector3i(7,47,512),Vector3i.FORWARD,Vector3(7.2,47.7,512),1],
		[true,false,Vector3i(7,47,512),Vector3i.ZERO,Vector3(7,48,512),1])
	fixture("sky entry z0", Vector3(2.25,65.25,2.25), Vector3.DOWN, 2, [Vector3i(2,2,0)],
		[true,false,Vector3i(2,63,2),Vector3i.UP,Vector3(2.25,64,2.25),2],
		[false,false,Vector3i(2,63,2),Vector3i.ZERO,Vector3(2.25,65.25,2.25),2])
	fixture("legacy cached sky column", Vector3(.995,65.0999984741211,.25), Vector3(.1,-1,0), 4, [Vector3i(0,0,1)],
		[false,false,Vector3i(1,62,0),Vector3i.UP,Vector3(.995,65.0999984741211,.25),4],
		[true,false,Vector3i(1,62,0),Vector3i.ZERO,Vector3(1,63,0),4])
	fixture("virtual floor", Vector3(2.25,.75,2.25), Vector3.DOWN, 1, [],
		[true,false,Vector3i(2,-1,2),Vector3i.UP,Vector3(2.25,0,2.25),1],
		[true,false,Vector3i(2,-1,2),Vector3i.ZERO,Vector3(2,0,2),1])
	fixture("departing sky", Vector3(2.25,64.0999984741211,2.25), Vector3.UP, 3, [],
		[false,false,Vector3i(2,67,2),Vector3i.DOWN,Vector3(2.25,64.0999984741211,2.25),3],
		[false,false,Vector3i(2,64,2),Vector3i.ZERO,Vector3(2.25,64.0999984741211,2.25),0])
	fixture("near axis binary32", Vector3(1.0000001192092896,53.75,1.25), Vector3(1e-7,0,1), 2, [Vector3i(1,3,10)],
		[true,false,Vector3i(1,53,3),Vector3i.FORWARD,Vector3(1.000000238418579,53.75,3),2],
		[true,false,Vector3i(1,53,3),Vector3i.ZERO,Vector3(1,54,3),2])
	fixture("47-step float slope", Vector3(30.137,52.271,40.413), Vector3(.372,-.217,.913), 47, [Vector3i(42,70,18)],
		[false,false,Vector3i(41,45,69),Vector3i.FORWARD,Vector3(30.137,52.271,40.413),47],
		[false,false,Vector3i(41,45,69),Vector3i.ZERO,Vector3(30.137,52.271,40.413),47])
	fixture("42-step float hit", Vector3(90.123,42.679,50.879), Vector3(-.71,.41,.203), 63, [Vector3i(68,57,8)],
		[true,false,Vector3i(68,55,57),Vector3i.FORWARD,Vector3(68.71458435058594,55.04161071777344,57),42],
		[true,false,Vector3i(68,55,57),Vector3i.ZERO,Vector3(68,56,57),42])
	fixture("legacy unnormalized", Vector3(1.25,53.75,5.5), Vector3(.25,0,0), 4, [Vector3i(2,5,10)],
		[true,false,Vector3i(2,53,5),Vector3i.LEFT,Vector3(2,53.75,5.5),1],
		[true,false,Vector3i(2,53,5),Vector3i.ZERO,Vector3(2,54,5),1])
	fixture("legacy 1024 quantization", Vector3(31.363269805908203,58.17564010620117,49.84959411621094), Vector3(-.5946354866027832,-.0019327178597450256,.8039930462837219), 128, [],
		[false,false,Vector3i(-23,57,122),Vector3i.UP,Vector3(31.363269805908203,58.17564010620117,49.84959411621094),128],
		[false,false,Vector3i(-23,58,123),Vector3i.ZERO,Vector3(31.363269805908203,58.17564010620117,49.84959411621094),128])
	seed_native([Vector3i(5,5,10)], COLOR)
	check_result("legacy fractional length", map.cast_source_ray_legacy(Vector3(1.25,53.75,5.5),Vector3.RIGHT,3.999999),
		[false,false,Vector3i(4,53,5),Vector3i.ZERO,Vector3(1.25,53.75,5.5),3])
	seed_native([Vector3i(5,5,10)], 0)
	seed_native([Vector3i(3,5,10)], COLOR)
	check_result("legacy float32 rounded length", map.cast_source_ray_legacy(Vector3(1.25,53.75,5.5),Vector3.RIGHT,1.99999999),
		[true,false,Vector3i(3,53,5),Vector3i.ZERO,Vector3(3,54,5),2])
	seed_native([Vector3i(3,5,10)], 0)
	metric_differences()
	start_solid_and_limits()
	wrappers_and_import()
	map = null
	await process_frame
	print("SOURCE RAY TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func metric_differences() -> void:
	seed_native([Vector3i(4,4,10)], COLOR)
	var origin := Vector3(1.5,53.5,1.5)
	check(not map.cast_source_ray(origin,Vector3(1,0,1),4).hit and map.cast_voxel(origin,Vector3(1,0,1),4).hit, "metric metres and source plane counts intentionally differ on diagonal rays")
	seed_native([Vector3i(4,4,10)], 0)
	seed_native([Vector3i(10,11,10),Vector3i(10,10,11)], COLOR)
	check(map.cast_source_ray(Vector3(10.5,53.5,10.5),Vector3(0,-1,1),1).cell == Vector3i(10,53,11) and map.cast_voxel(Vector3(10.5,53.5,10.5),Vector3(0,-1,1),1).cell == Vector3i(10,52,10), "source and metric tie order remain separate contracts")
	seed_native([Vector3i(10,11,10),Vector3i(10,10,11)], 0)
	seed_native([Vector3i(0,5,10)], COLOR)
	check(map.cast_source_ray(Vector3(511.25,53.75,5.5),Vector3.RIGHT,1).hit and not map.cast_voxel(Vector3(511.25,53.75,5.5),Vector3.RIGHT,1).hit, "metric query keeps bounded edges while native source query wraps only sampling")
	seed_native([Vector3i(0,5,10)], 0)
	check(map.cast_source_ray(Vector3(2.25,.75,2.25),Vector3.DOWN,1).hit and not map.cast_voxel(Vector3(2.25,.75,2.25),Vector3.DOWN,1).hit, "source virtual solid floor does not change generic metric empty-map behavior")
	check(map.map_sequence == 0 and map.last_tick == 0 and map.epoch == 73, "all ray queries and bootstrap fixtures leave simulation metadata unchanged")

func start_solid_and_limits() -> void:
	seed_native([Vector3i(1,1,10)], COLOR)
	var origin := Vector3(1.25,53.75,1.25)
	check_result("zero-step starting solid", map.cast_source_ray(origin,Vector3.RIGHT,0),
		[true,true,Vector3i(1,53,1),Vector3i.ZERO,origin,0])
	check(map.cast_source_ray(origin,Vector3.ZERO,7).hit, "zero direction has a defined startSolid result before native next-plane assertion")
	check_result("legacy ignores starting solid", map.cast_source_ray_legacy(origin,Vector3.RIGHT,0),
		[false,false,Vector3i(1,53,1),Vector3i.ZERO,origin,0])
	check_result("integer vertical face native flooring", map.cast_source_ray(Vector3(1.25,54,1.25),Vector3.UP,0),
		[true,true,Vector3i(1,53,1),Vector3i.ZERO,Vector3(1.25,54,1.25),0])
	check(not map.cast_voxel(Vector3(1.25,54,1.25),Vector3.UP,1).hit, "metric Godot-floor boundary remains unchanged")
	seed_native([Vector3i(1,1,10)], 0)
	check_result("zero-step empty source ray", map.cast_source_ray(origin,Vector3.ZERO,0),
		[false,false,Vector3i(1,53,1),Vector3i.ZERO,origin,0])
	check_result("legacy zero direction", map.cast_source_ray_legacy(origin,Vector3.ZERO,9),
		[false,false,Vector3i(1,53,1),Vector3i.ZERO,origin,0])
	check_result("legacy starting below virtual floor", map.cast_source_ray_legacy(Vector3(1.25,-.25,1.25),Vector3.ZERO,0),
		[true,false,Vector3i(1,-1,1),Vector3i.ZERO,Vector3(1,0,1),0])
	check_result("source starting below virtual floor", map.cast_source_ray(Vector3(1.25,-.25,1.25),Vector3.ZERO,0),
		[true,true,Vector3i(1,-1,1),Vector3i.ZERO,Vector3(1.25,-.25,1.25),0])
	check(not map.cast_source_ray(origin,Vector3.ZERO,1).valid, "undefined native zero-direction next-plane case returns explicit invalid status")
	for budget in [-1, DATA.MAX_SOURCE_RAY_STEPS + 1]:
		check(not map.cast_source_ray(origin,Vector3.RIGHT,budget).valid, "source crossing budget rejected atomically")
		check(not map.cast_source_ray_legacy(origin,Vector3.RIGHT,budget).valid, "legacy crossing budget rejected atomically")
	for invalid in [Vector3(NAN,0,0),Vector3(INF,0,0),Vector3(1000001,0,0)]:
		check(not map.cast_source_ray(invalid,Vector3.RIGHT,1).valid, "source nonfinite/out-of-budget origin rejected")
		check(not map.cast_source_ray_legacy(invalid,Vector3.RIGHT,1).valid, "legacy nonfinite/out-of-budget origin rejected")
	check(not map.cast_source_ray(origin,Vector3(INF,0,0),1).valid and not map.cast_source_ray_legacy(origin,Vector3(INF,0,0),1).valid, "both ray variants reject nonfinite direction")
	check(not map.cast_source_ray_legacy(origin,Vector3.RIGHT,NAN).valid and not map.cast_source_ray_legacy(origin,Vector3.RIGHT,INF).valid, "legacy rejects nonfinite scalar lengths")
	check(not map.cast_source_ray_legacy(origin,Vector3(1000000,0,0),8).valid, "legacy endpoint budget avoids undefined native int conversion")
	check_result("hard maximum source count", map.cast_source_ray(origin,Vector3.RIGHT,8192),
		[false,false,Vector3i(8193,53,1),Vector3i.LEFT,origin,8192])
	check_result("hard maximum legacy count", map.cast_source_ray_legacy(origin,Vector3.RIGHT,8192),
		[false,false,Vector3i(8193,53,1),Vector3i.ZERO,origin,8192])
	var query := QueryOnlyData.new()
	query.dimensions = Vector3i(512,64,512)
	check(query.blocks.is_empty() and query.cast_source_ray(origin,Vector3.RIGHT,1).hit and query.calls == 2, "source rays dispatch get_block on data-only historical-style query subclasses")
	check(query.cast_source_ray_legacy(origin,Vector3.RIGHT,1).hit, "legacy ray also dispatches narrow get_block without requiring packed storage")

func wrappers_and_import() -> void:
	var small := DATA.new()
	small.clear(Vector3i(8,8,8),81)
	small.seed_box(Vector3i(0,4,2),Vector3i(1,5,3),COLOR)
	check(not small.cast_source_ray(Vector3(7.75,4.5,2.5),Vector3.RIGHT,1).hit and not small.cast_source_ray_legacy(Vector3(7.75,4.5,2.5),Vector3.RIGHT,1).hit, "authored smaller arenas retain bounded horizontal sampling instead of periodic wrap")
	check(small.cast_source_ray(Vector3(.5,9,.5),Vector3.UP,2).cell.y >= 9 and not small.cast_source_ray(Vector3(.5,9,.5),Vector3.UP,2).hit, "authored small maps have air above their own height")
	var world := WORLD.new()
	world.data = small
	root.add_child(world)
	world.set_process(false)
	check(world.cast_source_ray(Vector3(2.5,4.5,2.5),Vector3.LEFT,3) == small.cast_source_ray(Vector3(2.5,4.5,2.5),Vector3.LEFT,3), "World forwards full source CastRay2 result")
	check(world.cast_source_ray_legacy(Vector3(2.5,4.5,2.5),Vector3.LEFT,3) == small.cast_source_ray_legacy(Vector3(2.5,4.5,2.5),Vector3.LEFT,3), "World forwards full legacy source result")
	deferred_import(world)
	world.free()

func deferred_import(world: VoxelWorld) -> void:
	# One safe z62 floor span per original column, distinct from Title fixture.
	var span := PackedByteArray([0,62,62,0,0x20,0x40,0x60,100])
	var fixture := PackedByteArray()
	fixture.resize(512 * 512 * 8)
	for offset in range(0, fixture.size(), 8):
		for byte in range(8):
			fixture[offset + byte] = span[byte]
	check(world.load_vxl_bytes(fixture,"Deferred floor fixture",true) == OK, "deferred byte import decodes a real-format native map")
	check(world.dimensions == Vector3i(512,64,512) and world._chunks.is_empty() and world._water_mesh == null and world._water_cursor == 0 and world._dirty.size() > 0, "deferred VXL byte import queues visuals without synchronously scanning water or meshing")
	check(world.get_block(Vector3i(0,1,0)) == COLOR and world.get_block(Vector3i(511,0,511)) == COLOR, "deferred real-format import retains BGR palette and duplicated immutable floor at both map boundaries")
	check(world.cast_source_ray(Vector3(.5,5,.5),Vector3.DOWN,4).cell == Vector3i(0,1,0), "source ray queries imported floor before visual preparation")
	var adopted: VoxelData = world.data
	var missing := "user://source-rays-missing-%d.vxl" % Time.get_ticks_usec()
	check(world.load_vxl(missing,true) == ERR_FILE_NOT_FOUND and world.data == adopted and world._chunks.is_empty(), "failed deferred path import preserves installed data and pending visual state")
	var path := "user://source-rays-deferred-%d.vxl" % Time.get_ticks_usec()
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(fixture)
	file.close()
	var imported: Error = world.load_vxl(path,true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(imported == OK and world._chunks.is_empty() and world._water_mesh == null and world._water_cursor == 0, "path import forwards its deferred flag and temporary fixture is removed")
