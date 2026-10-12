extends SceneTree
## Empty-halo publication, cancellation and exact near/boundary faces.
const WORLD = preload("res://world/voxel_world.gd")
const CHUNK = preload("res://world/voxel_chunk.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("EMPTY CHUNK OPTIMIZATION: " + message)

func rebuild(chunk: Node3D, world: Node3D, collision: bool = true) -> Dictionary:
	chunk.begin_rebuild(world,collision)
	var units := 0
	var mesh_units := 0
	var collision_units := 0
	while chunk.is_rebuilding() and units < 1000:
		var result: Dictionary = chunk.advance_rebuild_slice(world,world._material,{},1,0,true)
		check(result.processed_units == 1,"unit cap remains exactly one until atomic publication")
		units += result.processed_units
		mesh_units += result.stage_units[1]
		collision_units += result.stage_units[2]
	check(not chunk.is_rebuilding(),"finite bounded staged job completes")
	return {"units":units,"mesh_units":mesh_units,"collision_units":collision_units}

func run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,32,32))
	world.water_enabled = false
	root.add_child(world)
	world.set_process(false)
	world._ensure_material()
	var chunk := CHUNK.new()
	var empty: Dictionary = rebuild(chunk,world)
	check(empty.units == 325 and empty.mesh_units == 0 and empty.collision_units == 0,"all-zero halo skips empty mesh/collision stages")
	check(chunk.face_count == 0 and chunk.collision_face_count == 0 and chunk.mesh_instance.mesh == null and chunk.collision.shape == null,"empty publication yields no geometry or collider")
	# Halo-only occupancy is conservative: never treat it as a centre solid.
	world.data.seed_box(Vector3i(16,5,5),Vector3i(17,6,6),0x01000000)
	var neighbor: Dictionary = rebuild(chunk,world)
	check(neighbor.mesh_units == 256 and neighbor.collision_units == 96 and chunk.face_count == 0,"neighboring solid black runs unchanged stages with empty centre")
	world.data.seed_box(Vector3i(15,5,5),Vector3i(16,6,6),0x01abcdef)
	rebuild(chunk,world)
	check(chunk.face_count == 5 and chunk.collision_face_count == 5,"border neighbor hides exactly one render/collision face")
	var retained: Shape3D = chunk.collision.shape
	world.data.seed_box(Vector3i(15,5,5),Vector3i(16,6,6),0)
	world.data.seed_box(Vector3i(16,5,5),Vector3i(17,6,6),0)
	var color_only: Dictionary = rebuild(chunk,world,false)
	check(color_only.mesh_units == 0 and chunk.mesh_instance.mesh == null and chunk.collision.shape == retained,"empty color-only rebuild retains existing collider contract")
	rebuild(chunk,world,true)
	check(chunk.mesh_instance.mesh == null and chunk.collision.shape == null and chunk.get_cached_color_bytes() == 0,"geometry removal clears previous mesh/collider/color indexes atomically")
	chunk.begin_rebuild(world)
	chunk.advance_rebuild_slice(world,world._material,{},323)
	check(chunk.is_rebuilding() and chunk._job.stage == 0,"pre-halo-completion job remains cancelable")
	chunk.cancel_rebuild()
	check(not chunk.is_rebuilding() and chunk.mesh_instance.mesh == null,"cancelled empty job publishes nothing")
	world.data.seed_box(Vector3i(2,2,2),Vector3i(3,3,3),0x01000000)
	rebuild(chunk,world)
	check(chunk.face_count == 6 and chunk.collision_face_count == 6,"fresh post-cancellation solid black uses full geometry path")
	chunk.free()
	world.free()
	print("EMPTY CHUNK OPTIMIZATION TESTS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
