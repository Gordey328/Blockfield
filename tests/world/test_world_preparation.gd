extends SceneTree
## Pure World/Data preparation; no Main, preferences or rendered GPU fixture.
const WORLD = preload("res://world/voxel_world.gd")
const DATA = preload("res://world/voxel_data.gd")
const EARTH := 0x01604020
const RED := 0x01cc2211
const BLUE := 0x011133dd
const BLACK := 0x01000000
var assertions := 0
var failures := 0
var loaded_maps := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("WORLD PREPARATION: " + message)

func make_map(size: Vector3i, epoch: int, color: int = EARTH) -> VoxelData:
	var map := DATA.new()
	map.clear(size, epoch)
	map.seed_box(Vector3i.ZERO, Vector3i(size.x, 2, size.z), color)
	return map

func finish_images(world: VoxelWorld, cap: int = 7) -> int:
	var batches := 0
	while world.is_topdown_pending() or world.get_visual_preparation_stats().water_pending_columns > 0:
		var stats: Dictionary = world.advance_visual_preparation(cap, 1000000)
		if stats.processed_columns <= 0 or stats.processed_columns > cap:
			check(false, "cache preparation must make bounded progress")
			break
		batches += 1
		if batches > 200000:
			check(false, "cache preparation must finish")
			break
	return batches

func run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32, 8, 32))
	root.add_child(world)
	world.set_process(false)
	world.visual_effects_enabled = false
	world.map_loaded.connect(func(_title: String) -> void: loaded_maps += 1)
	var initial := make_map(Vector3i(32, 8, 32), 21)
	check(world.set_map_data(initial, "Synchronous") == OK, "default map adoption succeeds")
	check(world.data == initial and world.get_stats().chunks == 4 and world._dirty.is_empty(), "default adoption retains synchronous mesh/collision flush")
	check(is_instance_valid(world._water_mesh) and world.get_visual_preparation_stats().water_pending_columns == 0, "default adoption completes water before returning")
	var old_chunk: Node = world._chunks.values()[0]
	var old_water: Node = world._water_mesh
	var old_image: Image = world.get_topdown_image()
	check(old_image.get_size() == Vector2i(32, 32) and not world.is_topdown_pending(), "default topdown query synchronously returns completed image")
	var next := make_map(Vector3i(4, 8, 4), 22)
	next.seed_box(Vector3i(0, 2, 0), Vector3i(1, 4, 1), BLUE)
	next.seed_box(Vector3i(3, 2, 3), Vector3i(4, 5, 4), RED)
	var before_bytes := next.snapshot_bytes()
	check(world.set_map_data(next, "Deferred", true) == OK and world.data == next, "deferred adoption immediately uses the same validated writable data object")
	check(world.get_stats().chunks == 0 and world._dirty.size() == 1 and world._water_mesh == null and world._wave_field == null, "deferred adoption queues geometry and water without building nodes")
	check(old_chunk.get_parent() == null and old_chunk.is_queued_for_deletion() and old_water.get_parent() == null and old_water.is_queued_for_deletion(), "deferred epoch install detaches old meshes/collision/water synchronously")
	check(world.dimensions == Vector3i(4, 8, 4) and world.get_spawn_position() == Vector3(2.5, 3, 2.5) and loaded_maps == 2, "map_loaded announces installed data/new spawn independently of visual warming")
	var hit: Dictionary = world.cast_voxel(Vector3(0.5, 7, 0.5), Vector3.DOWN, 10)
	check(hit.hit and hit.cell == Vector3i(0, 3, 0) and world.clip_box(Vector3(0.5, 2.5, 0.5)), "source data ray/collision queries work before Godot collider creation")
	var image: Image = world.get_topdown_image_progressive()
	check(image != old_image and image.get_size() == Vector2i(4, 4) and image.get_pixel(0, 0).a == 0 and image.get_pixel(3, 3).a == 0, "progressive getter allocates new transparent image without scanning columns")
	check(world.get_visual_preparation_stats().topdown_pending_columns == 16 and world.get_visual_preparation_stats().water_pending_columns == 16, "both image preparations expose the complete pending count")
	check(world.advance_visual_preparation(0).processed_columns == 0 and world.advance_visual_preparation(4096, 0).processed_columns == 0, "zero count/time budget leaves cursors and pixels untouched")
	var first: Dictionary = world.advance_visual_preparation(2, 1000000)
	check(first.processed_columns == 2 and world._topdown_cursor == 1 and world._water_cursor == 1, "combined count budget alternates topdown and bottom columns")
	check(image.get_pixel(0, 0) == WORLD.block_color(BLUE) and image.get_pixel(3, 3).a == 0, "one completed column shows exact highest RGB while future columns remain transparent")
	check(next.snapshot_bytes() == before_bytes and next.map_sequence == 0, "visual preparation never mutates authoritative map or sequences")
	world.set_water_fog(Color(0.2, 0.3, 0.4), 91)
	world.set_water_fog_enabled(false)
	world.set_water_waves_enabled(false)
	world.set_water_refraction_enabled(false)
	world.set_water_enabled(false)
	world.set_lighting_enabled(false)
	world.set_block(Vector3i(0, 3, 0), RED)
	world.set_block(Vector3i(0, 3, 0), BLACK)
	check(world._topdown_dirty.size() == 1 and world._topdown_dirty_queue.size() == 1, "repeated visible edits before a budget step coalesce into one queued column")
	world.set_block(Vector3i(0, 2, 0), RED)
	world.set_block(Vector3i(3, 4, 3), BLUE)
	check(world._topdown_dirty.size() == 1, "buried edits and unfilled future columns do not enqueue redundant scans")
	world.set_block(Vector3i(0, 3, 0), 0)
	var revision: int = world.get_visual_preparation_stats().topdown_revision
	var batches := finish_images(world)
	check(batches >= 4 and image == world.get_topdown_image_progressive() and not world.is_topdown_pending(), "bounded batches finish in place without replacing the shared image")
	check(image.get_pixel(0, 0) == WORLD.block_color(RED) and image.get_pixel(3, 3) == WORLD.block_color(BLUE), "removal/recolor of processed and future columns are retained during initial fill")
	check(world.get_visual_preparation_stats().topdown_revision > revision and world._topdown_dirty_queue.is_empty(), "completed batches advance texture revision and release the dirty queue")
	var water_material: ShaderMaterial = world._water_mesh.mesh.surface_get_material(0)
	check(water_material.get_shader_parameter("fog_color") == Vector3(0.2, 0.3, 0.4) and water_material.get_shader_parameter("fog_distance") == 91.0, "fog chosen during warming is retained by delayed material creation")
	check(not world._water_mesh.visible and not world._wave_field.is_processing() and not water_material.get_shader_parameter("waves_enabled") and not water_material.get_shader_parameter("refraction_enabled") and not water_material.get_shader_parameter("fog_enabled") and not water_material.get_shader_parameter("lighting_enabled"), "all water/lighting switches chosen during warming reach actual nodes/material")
	check(world._water_image.get_pixel(3, 3) == WORLD.block_color(EARTH), "water uses original immutable bottom palette rather than highest surface")
	world.rebuild_budget = 1
	world.rebuild_time_budget_ms = 1000.0
	world._process(0)
	check(world.get_stats().chunks == 1 and world.get_stats().faces > 0 and world._chunks.values()[0].collision.shape != null, "existing process budget creates exact mesh/collision after deferred installation")
	check(world.get_visual_preparation_stats().ready, "ready requires mesh and both requested caches to finish")
	world.set_block(Vector3i(1, 2, 0), BLACK)
	check(world.is_topdown_pending(), "new visible edit restarts bounded dirty work on completed image")
	world.advance_visual_preparation(1, 1000000)
	check(image.get_pixel(1, 0) == Color.BLACK and not world.is_topdown_pending(), "one-column budget updates a solid black surface without opacity loss")
	var invalid := DATA.new()
	check(world.set_map_data(invalid, "Invalid", true) == ERR_INVALID_DATA and world.data == next and world.get_topdown_image_progressive() == image, "invalid deferred adoption preserves active data/image/progress")
	var cancel := make_map(Vector3i(8, 8, 8), 23)
	world.set_map_data(cancel, "Cancelled preparation", true)
	var cancelled_image: Image = world.get_topdown_image_progressive()
	world.advance_visual_preparation(2, 1000000)
	var cancelled_pixels := cancelled_image.get_data()
	var replacement := make_map(Vector3i(3, 8, 5), 24, BLUE)
	world.set_map_data(replacement, "Replacement", true)
	var replacement_image: Image = world.get_topdown_image_progressive()
	finish_images(world)
	check(cancelled_image.get_data() == cancelled_pixels and replacement_image != cancelled_image and replacement_image.get_size() == Vector2i(3, 5), "epoch replacement cancels old fill without writing retained old images")
	check(world.get_visual_preparation_stats().epoch == 24 and replacement_image.get_pixel(2, 4) == WORLD.block_color(BLUE), "replacement progresses only its own bounds/data/epoch")
	world.set_map_data(make_map(Vector3i(16, 8, 16), 25), "Fair preparation", true)
	world.get_topdown_image_progressive()
	world.advance_visual_preparation(2, 1000000)
	for step in range(12):
		world.set_block(Vector3i(0, 1, 0), RED if step % 2 == 0 else BLUE)
		world.advance_visual_preparation(4, 1000000)
	check(world._topdown_cursor > 4 and world._water_cursor > 4, "continuously dirty processed columns cannot starve either initial fill")
	check(world.get_topdown_image() == world._topdown_image and not world.is_topdown_pending() and world._topdown_dirty_queue.is_empty(), "synchronous API explicitly completes pending progressive work and dirty edits")
	var medium := make_map(Vector3i(32, 8, 32), 26)
	world.set_map_data(medium, "Frame-driven preparation", true)
	world.get_topdown_image_progressive()
	world._process(0)
	check(world._chunks.size() == 1 and world._dirty.size() == 3, "one process frame respects the configured one-chunk cap with several pending chunks")
	check(world._topdown_cursor > 0 and world._water_cursor > 0 and world.get_visual_preparation_stats().topdown_revision > 0, "normal process drives both caches every frame without repeated HUD getter calls")
	var bounded_mesh_frames := true
	for frame in range(3):
		var chunks_before := world._chunks.size()
		world._process(0)
		bounded_mesh_frames = bounded_mesh_frames and world._chunks.size() - chunks_before == 1
	check(bounded_mesh_frames and world._dirty.is_empty() and medium.map_sequence == 0, "progressive mesh frames complete the correct geometry without authority writes")
	world.set_map_data(make_map(Vector3i(16, 8, 16), 27), "Same-center A")
	var same_center_chunk: Node = world._chunks.values()[0]
	var same_center_spawn := world.get_spawn_position()
	world.set_map_data(make_map(Vector3i(16, 8, 16), 28, BLUE), "Same-center B")
	check(world.get_spawn_position() == same_center_spawn and world._chunks.size() == 1 and world._chunks.values()[0] != same_center_chunk and same_center_chunk.get_parent() == null, "synchronous same-size/same-center reset clears view-chunk sentinel and rebuilds replacement geometry")
	check(world.get_block(Vector3i(8, 1, 8)) == BLUE and world._dirty.is_empty(), "same-center synchronous replacement queries and geometry use only the new palette")
	world.set_map_data(make_map(Vector3i(16, 8, 16), 29, RED), "Same-center C", true)
	check(world.get_spawn_position() == same_center_spawn and world._chunks.is_empty() and world._dirty.size() == 1, "deferred same-size/same-center reset requeues initial chunks after clearing old nodes")
	world._process(0)
	check(world._chunks.size() == 1 and world._dirty.is_empty() and world.get_block(Vector3i(8, 1, 8)) == RED, "same-center deferred replacement creates new geometry through its normal frame budget")
	native_title(world)
	world.free()
	await process_frame
	check(not is_instance_valid(old_chunk) and not is_instance_valid(old_water), "old epoch resources are eventually released")
	print("WORLD PREPARATION TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func native_title(world: VoxelWorld) -> void:
	var file := FileAccess.open("res://assets/openspades/maps/Title.vxl", FileAccess.READ)
	check(file != null, "committed original Title fixture is available without upstream cache")
	if file == null:
		return
	var native := DATA.new()
	check(native.load_vxl_bytes(file.get_buffer(file.get_length()), 901) == OK, "genuine 512x64x512 original Title decodes")
	var started := Time.get_ticks_usec()
	check(world.set_map_data(native, "Native Title deferred", true) == OK, "original Title data adopts without synchronous visual preparation")
	var adopt_usec := Time.get_ticks_usec() - started
	var image: Image = world.get_topdown_image_progressive()
	check(world.get_stats().chunks == 0 and world._water_mesh == null and world._wave_field == null and world._topdown_cursor == 0 and world._water_cursor == 0, "full native installation performs no chunk or per-column preparation before return")
	check(image.get_size() == Vector2i(512, 512) and world.get_visual_preparation_stats().topdown_pending_columns == 262144 and world.get_visual_preparation_stats().water_pending_columns == 262144, "native boundary dimensions and cache pending counts are exact")
	var peak_usec := 0
	var batches := 0
	var cap_valid := true
	started = Time.get_ticks_usec()
	while world.is_topdown_pending() or world.get_visual_preparation_stats().water_pending_columns > 0:
		var stats: Dictionary = world.advance_visual_preparation()
		peak_usec = maxi(peak_usec, stats.elapsed_usec)
		cap_valid = cap_valid and stats.processed_columns > 0 and stats.processed_columns <= 4096
		batches += 1
		if batches > 20000:
			cap_valid = false
			break
	var preparation_usec := Time.get_ticks_usec() - started
	check(cap_valid and batches >= 128 and not world.is_topdown_pending(), "actual native map progresses with a hard 4096-column cap per combined batch")
	var pixels := image.get_data()
	var floor_pixels := world._water_image.get_data()
	var palette_exact := true
	var floor_exact := true
	var packed: PackedInt32Array = native.blocks
	for column in range(262144):
		var color := 0
		for y in range(63, -1, -1):
			if packed[column * 64 + y] != 0:
				color = packed[column * 64 + y]
				break
		var offset := column * 4
		palette_exact = palette_exact and pixels[offset] == ((color >> 16) & 255) and pixels[offset + 1] == ((color >> 8) & 255) and pixels[offset + 2] == (color & 255) and pixels[offset + 3] == 255
		var floor_color := packed[column * 64]
		floor_exact = floor_exact and floor_pixels[offset] == ((floor_color >> 16) & 255) and floor_pixels[offset + 1] == ((floor_color >> 8) & 255) and floor_pixels[offset + 2] == (floor_color & 255) and floor_pixels[offset + 3] == 255
	check(palette_exact, "every one of 262144 progressive Title columns matches original highest-solid RGB/alpha")
	check(floor_exact, "every one of 262144 progressive water bottom pixels matches original floor RGB/alpha")
	check(native.map_sequence == 0 and world.get_stats().chunks == 0, "native image preparation creates no transactions or unbudgeted terrain geometry")
	var boundaries: Array[int] = [0, 511, 512, 262143]
	for column in boundaries:
		var top: Vector2i = native.column_top(column, 63)
		world.set_block(Vector3i(column % 512, top.y, column / 512), BLACK)
	check(world._topdown_dirty.size() == 4, "first/last x columns and z-row boundary edits each enqueue one column")
	check(world.advance_visual_preparation(2, 1000000).processed_columns == 2 and world._topdown_dirty.size() == 2, "native dirty updates also obey exact column budget")
	finish_images(world)
	var boundary_exact := true
	for column in boundaries:
		boundary_exact = boundary_exact and image.get_pixel(column % 512, column / 512) == Color.BLACK
	check(boundary_exact and world.get_visual_preparation_stats().epoch == 901 and native.map_sequence == 4, "native boundary edits update all final pixels once in the current epoch")
	world.clear_world(Vector3i(2, 4, 2))
	var cleared: Image = world.get_topdown_image_progressive()
	finish_images(world)
	check(cleared != image and cleared.get_pixel(1, 1) == Color.TRANSPARENT and world._water_image == null, "world clear cancels native caches/water and progressive empty columns remain transparent")
	print("WORLD PREPARATION METRICS: native_adopt_usec=%d batches=%d total_cache_usec=%d max_cache_batch_usec=%d" % [adopt_usec, batches, preparation_usec, peak_usec])
