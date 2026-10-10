extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
const CLUSTER = preload("res://world/falling_cluster.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FALLING TEST: " + message)

func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32, 32, 32))
	root.add_child(world)
	world._fill_box(Vector3i.ZERO, Vector3i(32, 2, 32), 0x01886644)
	world.set_effects_observer(Vector3(4, 4, 4))
	world.set_block(Vector3i(4, 2, 4), 0x01112233)
	world.set_block(Vector3i(4, 3, 4), 0x01aabbcc)
	world.set_block(Vector3i(5, 3, 4), 0x01ddeeff)
	world.set_block(Vector3i(4, 2, 4), 0)
	check(world.get_block(Vector3i(4, 3, 4)) == 0 and world.get_block(Vector3i(5, 3, 4)) == 0, "authoritative collapsed blocks must be removed immediately")
	check(world.get_effect_stats().falling == 1, "one detached component must create one grouped falling mesh")
	var cluster: Node3D = world._falling_clusters[0]
	cluster.set_process(false)
	check(cluster.block_count == 2 and cluster.get_child_count() == 1, "falling rendering must use one mesh, without a node per cube")
	check(cluster.position.is_equal_approx(Vector3(5, 3.5, 4.5)), "falling pivot must be mean voxel center")
	cluster.step(0.25)
	check(absf(cluster.position.y - 3.25) < 0.0001, "native first quarter-second fall must translate time*4*dt downward")
	check(not cluster.basis.is_equal_approx(Basis.IDENTITY), "falling mesh must rotate around mapped native axis")
	for step in range(20):
		if cluster.phase != CLUSTER.Phase.FALLING:
			break
		cluster.step(0.05)
	check(cluster.phase == CLUSTER.Phase.DEBRIS and cluster.shatter_reason == "collision", "COM ground collision must shatter the cluster before one-second timeout")
	var stats: Dictionary = cluster.get_effect_stats()
	check(stats.fragments == 12 and stats.smoke == 2 and stats.precise_physics, "near two-surface-cell impact must create native six fragments and one smoke per cell with bounce")
	check(cluster.get_child_count() == 3, "fragments and smoke must use two MultiMesh batches")
	cluster.step(0.5)
	check(world.get_block(Vector3i(4, 3, 4)) == 0, "cosmetic debris must never reinsert map blocks")
	cluster.step(1.6)
	check(cluster.phase == CLUSTER.Phase.COMPLETE and world.get_effect_stats().clusters == 0, "two-second debris expiry must remove active effects")
	await process_frame
	check(not is_instance_valid(cluster), "finished cluster node must be freed")
	var high := CLUSTER.new()
	world.add_child(high)
	var high_cells: Array[Vector3i] = [Vector3i(10, 20, 10)]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	high.setup(world, high_cells, PackedInt32Array([0x01665544]), Vector3(10, 20, 10), material, 123)
	high.set_process(false)
	high.step(1.01)
	check(high.phase == CLUSTER.Phase.DEBRIS and high.shatter_reason == "timeout", "an airborne cluster must fragment after native one-second lifetime")
	check(high.get_effect_stats().fragments == 6, "single airborne voxel must fragment into six sprites")
	high.step(2.1)
	await process_frame
	var far := CLUSTER.new()
	world.add_child(far)
	world.set_effects_observer(Vector3(300, 20, 300))
	far.setup(world, high_cells, PackedInt32Array([0x01665544]), Vector3(300, 20, 300), material, 123)
	far.set_process(false)
	far.step(1.01)
	check(far.phase == CLUSTER.Phase.COMPLETE and far.get_effect_stats().fragments == 0, "effects farther than native170m must clean up without particle allocation")
	await process_frame
	var budgeted := CLUSTER.new()
	world.add_child(budgeted)
	world.set_effects_observer(Vector3(10, 20, 10))
	budgeted.fragment_limit = 3
	budgeted.smoke_limit = 0
	budgeted.setup(world, high_cells, PackedInt32Array([0x01665544]), Vector3(10, 20, 10), material, 123)
	budgeted.set_process(false)
	budgeted.step(1.01)
	check(budgeted.get_effect_stats().fragments == 3 and budgeted.get_effect_stats().smoke == 0, "configured browser particle budgets must be enforced")
	budgeted.step(2.1)
	await process_frame
	check(world.clip_box(Vector3(-1, 5, 4)) and not world.clip_world(Vector3(-1, 5, 4)), "native falling and particle clipping must differ at horizontal bounds")
	world.generate_lab()
	check(world.water_level == 1.0 and world.wade_origin_level == 2.0, "water metadata must distinguish rendered plane from native player-origin wading threshold")
	check(world.get_block(Vector3i(80, 1, 80)) == 0 and world.get_block(Vector3i(80, 0, 80)) != 0, "lab pool must expose water above immutable floor")
	check(world._water_mesh.visible and world.is_water_floor(Vector3i(80, 0, 80)), "water plane must replace dry voxel-floor rendering in the pool")
	world.set_water_enabled(false)
	check(not world._water_mesh.visible and not world.is_water_floor(Vector3i(80, 0, 80)), "water setting must hide water and restore dry floor drawing")
	world.free()
	print("FALLING/WATER TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
