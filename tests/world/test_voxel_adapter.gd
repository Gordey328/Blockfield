extends SceneTree

const DATA = preload("res://world/voxel_data.gd")
const WORLD = preload("res://world/voxel_world.gd")
const RED := 0x01cc2211
const BLUE := 0x011133dd
var assertions := 0
var failures := 0
var block_batches := 0
var transaction_batches := 0
var loaded_maps := 0
var last_changes: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func changed(changes: Array) -> void:
	block_batches += 1
	last_changes = changes

func committed(_transaction: Dictionary) -> void:
	transaction_batches += 1

func loaded(_title: String) -> void:
	loaded_maps += 1

func run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,8,32))
	world._fill_box(Vector3i.ZERO,Vector3i(32,2,32),RED)
	root.add_child(world)
	world.set_process(false)
	world.blocks_changed.connect(changed)
	world.map_transaction_committed.connect(committed)
	world.map_loaded.connect(loaded)
	world.set_block(Vector3i(4,2,4),RED)
	world.set_block(Vector3i(4,3,4),RED)
	world.set_block(Vector3i(5,3,4),RED)
	world.set_block(Vector3i(4,2,4),0)
	check(world.data.map_sequence == 4 and world.get_effect_stats().falling == 1,"offline methods delegate one atomic sequence per edit including collapse")
	check(block_batches == 4 and transaction_batches == 4 and last_changes.size() == 3 and last_changes[1].collapsed,"legacy changes and wire transaction each emitted once")
	var old_cluster: Node3D = world._falling_clusters[0]
	world._create_water()
	var old_water: MeshInstance3D = world._water_mesh
	var old_waves: Node = world._wave_field
	world.rebuild_now()
	var old_chunk: Node3D = world._chunks.values()[0]
	var old_map: Image = world.get_topdown_image()
	world.set_irradiance_enabled(true)
	check(world._irradiance != null and world.get_stats().faces > 0,"old map has lighting and mesh caches before install")
	var baseline := DATA.new()
	check(baseline.clear(Vector3i(16,8,16),29) == OK,"new baseline initialized")
	baseline.seed_box(Vector3i.ZERO,Vector3i(16,2,16),BLUE)
	baseline.seed_box(Vector3i(8,2,8),Vector3i(9,4,9),BLUE)
	baseline.seed_box(Vector3i(4,2,4),Vector3i(5,4,5),RED)
	baseline.seed_box(Vector3i(5,3,4),Vector3i(6,4,5),RED)
	check(baseline.load_snapshot_bytes(baseline.snapshot_bytes(),baseline.dimensions,29,4,70) == OK,"validated network baseline carries epoch/map/tick barrier")
	check(world.set_map_data(baseline,"Join baseline") == OK and world.data == baseline,"world adopts validated model without serialization or map copy")
	check(world.dimensions == Vector3i(16,8,16) and world.map_name == "Join baseline" and world.data.epoch == 29 and world.data.map_sequence == 4,"baseline metadata installed")
	check(world.get_spawn_position() == Vector3(8.5,5,8.5),"baseline spawn recalculated from highest center block")
	check(world.get_block(Vector3i(8,3,8)) == BLUE and world.get_block(Vector3i(31,1,31)) == 0,"queries use new cells and dimensions")
	var new_map: Image = world.get_topdown_image()
	check(new_map != old_map and new_map.get_size() == Vector2i(16,16) and new_map.get_pixel(8,8) == WORLD.block_color(BLUE),"cached topdown image discarded and regenerated from baseline")
	check(world.get_effect_stats().clusters == 0 and old_cluster.is_queued_for_deletion() and old_cluster.get_parent() == null,"old falling clusters removed on baseline install")
	check(old_chunk.is_queued_for_deletion() and old_chunk.get_parent() == null and world.get_stats().chunks == 1,"old collision/chunk nodes replaced by new map mesh")
	check(old_water.is_queued_for_deletion() and old_waves.is_queued_for_deletion() and world._water_mesh != old_water and world._wave_field != old_waves,"water caches recreated for baseline dimensions")
	check(world._irradiance == null and loaded_maps == 1 and block_batches == 4 and transaction_batches == 4,"map install clears GI and emits loaded only, without replaying edit events")
	var authority := DATA.new()
	check(authority.load_snapshot_bytes(baseline.snapshot_bytes(),baseline.dimensions,29,4,70) == OK,"separate pure authority mirrors baseline")
	var cuts: Array[Vector3i] = [Vector3i(4,2,4)]
	var transaction: Dictionary = authority.remove_blocks(cuts,false,{"tick":71,"actor_id":8,"action_id":40})
	check(world.apply_map_transaction(transaction).ok and world.data.blocks == authority.blocks and baseline.map_sequence == 5,"rendered replica commits subsequent authority transaction exactly once")
	check(block_batches == 5 and transaction_batches == 5 and world.get_effect_stats().falling == 1,"remote collapse creates one cosmetic group and event batch")
	check(world.get_topdown_image().get_pixel(4,4) == WORLD.block_color(BLUE),"remote removal invalidates topdown column")
	world.rebuild_now()
	var before_faces: int = world.get_stats().faces
	check(not world.apply_map_transaction(transaction).ok and block_batches == 5 and transaction_batches == 5 and world.get_effect_stats().falling == 1 and world.get_stats().faces == before_faces,"double applying same shared model transaction rejected without duplicate visuals")
	world._blocks[world._index(Vector3i(2,1,2))] = RED
	check(world.data.get_block(Vector3i(2,1,2)) == RED,"legacy packed property mutation aliases Data storage")
	var invalid := DATA.new()
	check(world.set_map_data(invalid) == ERR_INVALID_DATA and world.data == baseline,"uninitialized map adoption leaves old map intact")
	var frozen: RefCounted = baseline.frozen_copy()
	check(world.set_map_data(frozen) == ERR_INVALID_DATA and world.data == baseline,"read-only frozen map cannot become writable presentation model")
	invalid.clear(Vector3i(2,2,2),30)
	invalid.epoch = 0
	check(world.set_map_data(invalid) == ERR_INVALID_DATA and world.data == baseline,"invalid metadata map adoption is atomic")
	invalid.epoch = 30
	invalid.blocks.resize(2)
	check(world.set_map_data(invalid) == ERR_INVALID_DATA and world.data == baseline,"wrong packed count rejected without clearing old presentation")
	await process_frame
	check(not is_instance_valid(old_chunk) and not is_instance_valid(old_cluster) and not is_instance_valid(old_water) and not is_instance_valid(old_waves),"old baseline node resources are freed")
	world.free()
	await process_frame
	print("VOXEL ADAPTER TESTS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
