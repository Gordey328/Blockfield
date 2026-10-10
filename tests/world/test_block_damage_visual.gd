extends SceneTree
## Source GLMapChunk damaged RGB; actual meshes/caches, independent of health timers.
const WORLD = preload("res://world/voxel_world.gd")
const DATA = preload("res://world/voxel_data.gd")
const CHUNK = preload("res://world/voxel_chunk.gd")
const CELL := Vector3i(15, 5, 15)
const PALETTE := 0x01ff8041
const HALVED := 0x017f4020
var assertions: int = 0
var failures: int = 0
var block_events: int = 0
var transaction_events: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BLOCK DAMAGE VISUAL: " + message)

func _on_blocks(_changes: Array) -> void:
	block_events += 1

func _on_transaction(_transaction: Dictionary) -> void:
	transaction_events += 1

func _cell_colors(chunk: Node3D, cell: Vector3i) -> PackedColorArray:
	var result := PackedColorArray()
	if chunk.mesh_instance.mesh == null:
		return result
	var arrays: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for first: int in range(0, vertices.size(), 4):
		var face: int = CHUNK.DIRECTIONS.find(Vector3i(normals[first]))
		var owner: Vector3i = chunk.coordinate * CHUNK.CHUNK_SIZE + Vector3i(vertices[first] - CHUNK.CORNERS[face][0])
		if owner == cell:
			for corner: int in range(4):
				result.append(colors[first + corner])
	return result

func _matches_rgb(colors: PackedColorArray, expected: Color) -> bool:
	if colors.is_empty():
		return false
	for color: Color in colors:
		if absf(color.r - expected.r) > 0.00001 or absf(color.g - expected.g) > 0.00001 or absf(color.b - expected.b) > 0.00001:
			return false
	return true

func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32, 16, 32))
	world.water_enabled = false
	world.visual_effects_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_block(CELL, PALETTE)
	# The nearby upper voxel creates actual AO; the adjoining chunk stays healthy.
	world.set_block(Vector3i(14, 6, 15), 0x01654321)
	world.set_block(Vector3i(16, 5, 15), 0x01876543)
	world.rebuild_now()
	world.blocks_changed.connect(_on_blocks)
	world.map_transaction_committed.connect(_on_transaction)
	var chunk: Node3D = world._chunks[Vector3i.ZERO]
	var adjacent: Node3D = world._chunks[Vector3i(1, 0, 0)]
	var initial: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	var initial_colors: PackedColorArray = initial[Mesh.ARRAY_COLOR]
	var initial_cell: PackedColorArray = _cell_colors(chunk, CELL)
	check(initial_cell.size() == 20 and _matches_rgb(initial_cell, WORLD.block_color(PALETTE)), "five visible faces initially retain odd source RGB bytes")
	var has_occlusion: bool = false
	for color: Color in initial_cell:
		has_occlusion = has_occlusion or color.a < 0.99
	check(has_occlusion, "fixture includes nontrivial native AO before damage")
	var collider: Shape3D = chunk.collision.shape
	var healthy_mesh: Mesh = adjacent.mesh_instance.mesh
	var packed_before: PackedInt32Array = world.data.blocks.duplicate()
	var history_before: Dictionary = world.data.get_journal_stats()
	var map_image: Image = world.get_topdown_image()
	var image_before: PackedByteArray = map_image.get_data()

	world.set_block_damaged(CELL, true)
	check(world.is_block_damaged(CELL), "surviving hit records a persistent presentation mask")
	check(world._dirty.size() == 1 and world._dirty.has(Vector3i.ZERO) and world._collision_dirty.is_empty(), "chunk-border color change invalidates only its mesh")
	world.rebuild_now()
	var damaged: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	var damaged_colors: PackedColorArray = damaged[Mesh.ARRAY_COLOR]
	check(_matches_rgb(_cell_colors(chunk, CELL), WORLD.block_color(HALVED)), "every visible face uses exact native floor-halving of odd RGB")
	check(damaged[Mesh.ARRAY_VERTEX] == initial[Mesh.ARRAY_VERTEX] and damaged[Mesh.ARRAY_NORMAL] == initial[Mesh.ARRAY_NORMAL] and damaged[Mesh.ARRAY_INDEX] == initial[Mesh.ARRAY_INDEX], "damage leaves mesh geometry unchanged")
	check(damaged[Mesh.ARRAY_TEX_UV2] == initial[Mesh.ARRAY_TEX_UV2], "damage leaves native AO tile coordinates unchanged")
	var alpha_unchanged: bool = damaged_colors.size() == initial_colors.size()
	for index: int in range(mini(damaged_colors.size(), initial_colors.size())):
		alpha_unchanged = alpha_unchanged and is_equal_approx(damaged_colors[index].a, initial_colors[index].a)
	check(alpha_unchanged, "damage leaves native AO corner values unchanged")
	check(chunk.collision.shape == collider and adjacent.mesh_instance.mesh == healthy_mesh, "damage retains collider and neighboring chunk mesh objects")
	check(world.data.blocks == packed_before and world.data.get_journal_stats() == history_before, "damage changes neither canonical RGB/occupancy nor transaction history")
	check(world.get_topdown_image() == map_image and map_image.get_data() == image_before, "damage preserves cached topdown source palette")
	check(block_events == 0 and transaction_events == 0, "presentation changes emit no authoritative block/transaction events")
	var damaged_mesh: Mesh = chunk.mesh_instance.mesh
	world.set_block_damaged(CELL, true)
	world.rebuild_now()
	check(world._dirty.is_empty() and chunk.mesh_instance.mesh == damaged_mesh, "another surviving hit does not rebuild an already darkened block")
	world.reload_resources()
	world.rebuild_now()
	check(world.is_block_damaged(CELL) and _matches_rgb(_cell_colors(chunk, CELL), WORLD.block_color(HALVED)) and chunk.collision.shape == collider, "resource reload retains damage while preserving collision")
	world.set_block_damaged(CELL, false)
	world.rebuild_now()
	check(not world.is_block_damaged(CELL) and _matches_rgb(_cell_colors(chunk, CELL), WORLD.block_color(PALETTE)), "adapter recovery restores original RGB on every face")
	check(chunk.collision.shape == collider and world.data.get_journal_stats() == history_before, "recovery retains physics and map history")
	var recovered_mesh: Mesh = chunk.mesh_instance.mesh
	world.set_block_damaged(CELL, false)
	world.clear_block_damage()
	world.rebuild_now()
	check(chunk.mesh_instance.mesh == recovered_mesh, "repeated recovery and clearing an empty mask avoid rebuilds")

	world.set_block_damaged(Vector3i(-1, 5, 15), true)
	world.set_block_damaged(Vector3i(3, 5, 3), true)
	check(world._dirty.is_empty() and not world.is_block_damaged(Vector3i(-1, 5, 15)) and not world.is_block_damaged(Vector3i(3, 5, 3)), "out-of-map and air cannot retain damaged presentation")
	world.set_block_damaged(CELL, true)
	world.set_block_damaged(Vector3i(16, 5, 15), true)
	world.clear_block_damage()
	world.rebuild_now()
	check(not world.is_block_damaged(CELL) and not world.is_block_damaged(Vector3i(16, 5, 15)) and _matches_rgb(_cell_colors(chunk, CELL), WORLD.block_color(PALETTE)), "bulk clear restores all affected chunk palettes")
	world.set_block_damaged(CELL, true)
	world.set_block(CELL, 0x01000000)
	world.rebuild_now()
	check(not world.is_block_damaged(CELL) and world.get_block(CELL) == 0x01000000 and _matches_rgb(_cell_colors(chunk, CELL), Color.BLACK), "repaint clears damage and solid black remains visible geometry")
	world.set_block_damaged(CELL, true)
	world.set_block(CELL, 0)
	check(not world.is_block_damaged(CELL), "deletion clears stale presentation state")
	world.set_block(CELL, PALETTE)
	check(not world.is_block_damaged(CELL), "replacement block does not inherit deleted-block damage")
	world.rebuild_now()

	var authority := DATA.new()
	check(authority.load_snapshot_bytes(world.data.snapshot_bytes(), world.dimensions, world.data.epoch, world.data.map_sequence, world.data.last_tick) == OK, "separate authority receives the same map barrier")
	world.set_block_damaged(CELL, true)
	var repaint: Dictionary = authority.set_block(CELL, 0x01876543)
	check(world.apply_map_transaction(repaint).ok and not world.is_block_damaged(CELL), "committed remote repaint clears damage")
	world.set_block_damaged(CELL, true)
	check(not world.apply_map_transaction(repaint).ok and world.is_block_damaged(CELL), "rejected duplicate transaction preserves current damage state")
	var removal: Dictionary = authority.set_block(CELL, 0)
	check(world.apply_map_transaction(removal).ok and not world.is_block_damaged(CELL), "committed remote removal clears damage")
	world.set_block(CELL, PALETTE)
	world.set_block_damaged(CELL, true)
	world.clear_world(Vector3i(64, 16, 64))
	check(not world.is_block_damaged(CELL), "world reset clears damage masks")

	# Damage survives unloading and is reapplied when its actual chunk returns.
	var streamed_cell := Vector3i(1, 4, 1)
	world.set_block(streamed_cell, PALETTE)
	world._streaming = true
	world.render_radius = 1
	world.set_view_position(Vector3(1, 4, 1))
	world.rebuild_now()
	world.set_block_damaged(streamed_cell, true)
	world.set_view_position(Vector3(49, 4, 49))
	world.rebuild_now()
	check(not world._chunks.has(Vector3i.ZERO) and world.is_block_damaged(streamed_cell), "streaming unload retains presentation state independent of meshes")
	world.set_view_position(Vector3(1, 4, 1))
	world.rebuild_now()
	var streamed_chunk: Node3D = world._chunks[Vector3i.ZERO]
	check(_matches_rgb(_cell_colors(streamed_chunk, streamed_cell), WORLD.block_color(HALVED)), "streamed-in chunk recreates damaged colors")
	var baseline := DATA.new()
	baseline.clear(Vector3i(16, 8, 16), world.data.epoch + 1)
	baseline.seed_box(Vector3i(1, 4, 1), Vector3i(2, 5, 2), PALETTE)
	check(world.set_map_data(baseline, "Fresh barrier") == OK and not world.is_block_damaged(streamed_cell), "network map replacement clears old damage even at matching cell/color")
	world.set_block_damaged(streamed_cell, true)
	world.generate_lab()
	check(not world.is_block_damaged(streamed_cell), "lab reset clears presentation mask")
	world.free()
	await process_frame
	print("BLOCK DAMAGE VISUAL TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
