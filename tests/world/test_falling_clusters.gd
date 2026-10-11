extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
const CLUSTER = preload("res://world/falling_cluster.gd")
var assertions: int = 0
var failures: int = 0

class QuerySpy extends Node3D:
	var queries: int = 0
	func clip_box(_position: Vector3) -> bool:
		queries += 1
		return true
	func clip_world(_position: Vector3) -> bool:
		queries += 1
		return true
	func get_effects_observer() -> Vector3:
		queries += 1
		return Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FALLING TEST: " + message)

func signals_for(cluster: FallingVoxelCluster) -> Dictionary:
	var events: Dictionary = {"shattered": 0, "completed": 0, "position": Vector3.ZERO,
		"blocks": -1, "reason": "", "order": []}
	cluster.shattered.connect(func(point: Vector3, count: int, reason: String) -> void:
		events.shattered += 1
		events.position = point
		events.blocks = count
		events.reason = reason
		events.order.append("shattered"))
	cluster.completed.connect(func() -> void:
		events.completed += 1
		events.order.append("completed"))
	return events

func simple_stats(cluster: FallingVoxelCluster) -> bool:
	var stats: Dictionary = cluster.get_effect_stats()
	return stats.fragments == 0 and stats.smoke == 0 and not stats.precise_physics

func _run() -> void:
	var world: VoxelWorld = WORLD.new()
	world.clear_world(Vector3i(32, 32, 32))
	world.data.seed_box(Vector3i.ZERO, Vector3i(32, 2, 32), 0x01886644)
	root.add_child(world)
	world.set_process(false)
	world.set_effects_observer(Vector3(4.0, 4.0, 4.0))
	world.set_block(Vector3i(4, 2, 4), 0x01112233)
	world.set_block(Vector3i(4, 3, 4), 0x01aabbcc)
	world.set_block(Vector3i(5, 3, 4), 0x01ddeeff)
	world.set_block(Vector3i(4, 2, 4), 0)
	check(world.get_block(Vector3i(4, 3, 4)) == 0 and world.get_block(Vector3i(5, 3, 4)) == 0, "authoritative collapsed blocks are removed immediately")
	check(world.get_effect_stats().falling == 1, "one detached component creates one cosmetic group")
	var cluster: FallingVoxelCluster = world._falling_clusters[0] as FallingVoxelCluster
	cluster.set_process(false)
	var events: Dictionary = signals_for(cluster)
	check(cluster.block_count == 2 and cluster.get_child_count() == 1 and cluster.rendered_cells == 2, "small collapse uses one grouped MultiMesh with original cubes")
	check(cluster.position.is_equal_approx(Vector3(5.0, 3.5, 4.5)), "collapse retains the exact mean voxel pivot")
	check(simple_stats(cluster), "falling starts without fragments, smoke or precise collision simulation")
	cluster.step(0.25)
	check(cluster.position.is_equal_approx(Vector3(5.0, 3.375, 4.5)), "quarter-second analytic fall integrates gravity in world Y")
	check(not cluster.basis.is_equal_approx(Basis.IDENTITY), "cosmetic group rotates during its fall")
	cluster.step(0.74)
	check(cluster.phase == CLUSTER.Phase.FALLING and events.shattered == 0 and events.completed == 0, "even a low cluster survives until its real one-second lifetime")
	cluster.step(0.01)
	check(cluster.phase == CLUSTER.Phase.COMPLETE and cluster.shatter_reason == "simplified", "one-second collapse ends directly without a debris stage")
	check(events.shattered == 1 and events.completed == 1 and events.order == ["shattered", "completed"], "World receives one impact then one cleanup notification")
	check(events.blocks == 2 and events.reason == "simplified" and events.position.is_equal_approx(Vector3(5.0, 1.5, 4.5)), "impact notification retains exact authoritative block count and final group position")
	check(simple_stats(cluster) and cluster.get_child_count() == 1, "completion allocates no secondary effects or nodes")
	check(world.get_effect_stats().clusters == 0, "completion immediately removes group from World bookkeeping")
	cluster.step(5.0)
	check(events.shattered == 1 and events.completed == 1, "additional steps cannot repeat completion signals")
	check(world.get_block(Vector3i(4, 3, 4)) == 0, "simplified cosmetic collapse never reinserts map blocks")
	await process_frame
	check(not is_instance_valid(cluster), "completed group node is freed")

	var spy: QuerySpy = QuerySpy.new()
	root.add_child(spy)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	var high_cells: Array[Vector3i] = [Vector3i(10, 100, 10)]
	var high: FallingVoxelCluster = CLUSTER.new()
	spy.add_child(high)
	high.setup(spy, high_cells, PackedInt32Array([0x01000000]), Vector3.ZERO, material, 123)
	high.set_process(false)
	var high_events: Dictionary = signals_for(high)
	check(high.get_effect_stats().rendered_cells == 1 and high.get_child_count() == 1, "single high voxel is retained, including solid black")
	var high_batch: MultiMeshInstance3D = high.get_child(0) as MultiMeshInstance3D
	check(high_batch.multimesh.instance_count == 1 and high_batch.material_override == material, "unit cube group uses the supplied terrain material")
	if DisplayServer.get_name() != "headless":
		check(high_batch.multimesh.get_instance_color(0).is_equal_approx(Color.BLACK), "solid black color survives Compatibility MultiMesh publication")
	else:
		print("FALLING_GPU_SKIPPED: headless MultiMesh color/pose readback")
	var single: FallingVoxelCluster = CLUSTER.new()
	spy.add_child(single)
	single.setup(spy, high_cells, PackedInt32Array([0x01000000]), Vector3(300.0, 20.0, 300.0), material, 456)
	single.set_process(false)
	var shared_mesh: Mesh = (single.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	check(shared_mesh == high_batch.multimesh.mesh, "all components share one immutable unit-cube mesh")
	high.step(0.1)
	high.step(0.2)
	high.step(0.2)
	single.step(0.5)
	check(high.transform.is_equal_approx(single.transform), "one elapsed interval and several smaller intervals yield identical group poses")
	var paused_pose: Transform3D = high.transform
	high.step(-1.0)
	high.step(0.0)
	high.step(NAN)
	check(high.transform.is_equal_approx(paused_pose), "negative, zero and nonfinite durations do not corrupt the group pose")
	high.step(10.0)
	single.step(10.0)
	check(high.phase == CLUSTER.Phase.COMPLETE and high_events.shattered == 1 and high_events.completed == 1 and is_equal_approx(high.elapsed, 1.0), "a long real frame ends the airborne group at its one-second final pose")
	check(single.phase == CLUSTER.Phase.COMPLETE and simple_stats(single), "far observer uses the same bounded lifetime without impact debris")
	check(spy.queries == 0, "setup, falling and completion never query terrain or observer position")
	await process_frame
	check(not is_instance_valid(high) and not is_instance_valid(single), "high and distant groups free on completion")

	var cells: Array[Vector3i] = []
	var colors: PackedInt32Array = PackedInt32Array()
	for y: int in range(40, 48):
		for z: int in range(32):
			for x: int in range(32):
				cells.append(Vector3i(x, y, z))
				colors.append(0x01665544)
	var huge: FallingVoxelCluster = CLUSTER.new()
	spy.add_child(huge)
	huge.setup(spy, cells, colors, Vector3.ZERO, material, 123)
	huge.set_process(false)
	var huge_events: Dictionary = signals_for(huge)
	var huge_batch: MultiMeshInstance3D = huge.get_child(0) as MultiMeshInstance3D
	check(huge.block_count == 8192 and huge.rendered_cells == 64 and huge_batch.multimesh.instance_count == 64, "8192-cell component retains exact source count but uploads only64 cubes")
	check(huge.get_child_count() == 1 and huge.position.is_equal_approx(Vector3(16.0, 44.0, 16.0)), "large component uses one group centered on every authoritative cell")
	if DisplayServer.get_name() != "headless":
		var first: Vector3 = huge_batch.multimesh.get_instance_transform(0).origin + huge.position
		var last: Vector3 = huge_batch.multimesh.get_instance_transform(63).origin + huge.position
		check(first.is_equal_approx(Vector3(cells[0]) + Vector3.ONE * 0.5) and last.is_equal_approx(Vector3(cells[-1]) + Vector3.ONE * 0.5), "bounded samples cover both ends of the component instead of only its first64 cells")
	var batch_rid: RID = huge_batch.multimesh.get_rid()
	for index: int in range(100):
		huge.step(0.005)
	check(huge_batch.multimesh.get_rid() == batch_rid and huge_batch.multimesh.instance_count == 64 and huge.get_child_count() == 1, "falling moves the group while retaining the uploaded cube batch")
	huge.step(0.5)
	check(huge_events.blocks == 8192 and huge_events.completed == 1 and simple_stats(huge) and spy.queries == 0, "large-group finish retains full block count with zero queries and zero debris")
	await process_frame

	for malformed: bool in [false, true]:
		var empty: FallingVoxelCluster = CLUSTER.new()
		spy.add_child(empty)
		var input_cells: Array[Vector3i] = []
		if malformed:
			input_cells = high_cells
		empty.setup(spy, input_cells, PackedInt32Array(), Vector3.ZERO, material)
		empty.set_process(false)
		# Match World: connect the signals after setup, before deferred cleanup.
		var empty_events: Dictionary = signals_for(empty)
		check(empty.get_child_count() == 0 and empty.rendered_cells == 0 and empty_events.completed == 0, "empty/malformed input allocates no rendering and defers completion")
		await process_frame
		check(empty_events.shattered == 1 and empty_events.completed == 1 and empty_events.reason == "simplified", "listeners connected after setup receive malformed-input cleanup exactly once")
		check(empty_events.blocks == input_cells.size(), "malformed cleanup still reports the exact input cell count")
		await process_frame
		check(not is_instance_valid(empty), "empty/malformed group frees safely")
	check(spy.queries == 0, "all malformed/large/far scenarios retain zero terrain queries")
	spy.free()

	# Existing independent world clipping and water behavior remain covered.
	check(world.clip_box(Vector3(-1.0, 5.0, 4.0)) and not world.clip_world(Vector3(-1.0, 5.0, 4.0)), "World clipping contracts remain available to authoritative gameplay")
	world.generate_lab()
	check(world.water_level == 1.0 and world.wade_origin_level == 2.0, "water metadata distinguishes rendered plane from native player-origin wading threshold")
	check(world.get_block(Vector3i(80, 1, 80)) == 0 and world.get_block(Vector3i(80, 0, 80)) != 0, "lab pool exposes water above immutable floor")
	check(world._water_mesh.visible and world.is_water_floor(Vector3i(80, 0, 80)), "water plane replaces dry voxel-floor rendering in the pool")
	world.set_water_enabled(false)
	check(not world._water_mesh.visible and not world.is_water_floor(Vector3i(80, 0, 80)), "water setting hides water and restores dry floor drawing")
	world.free()
	print("FALLING/WATER TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
