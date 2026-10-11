extends SceneTree
## Damage upload and bounded destructive rebuild regressions; no timing thresholds.
const WORLD = preload("res://world/voxel_world.gd")
const CHUNK = preload("res://world/voxel_chunk.gd")
const PALETTE := 0x01ff8041
const HALF := 0x017f4020
const CELL := Vector3i(15,15,15)
var assertions := 0
var failures := 0
var block_events := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BLOCK IMPACT OPTIMIZATION: "+message)

func rgb_matches(chunk: Node3D, cell: Vector3i, expected: Color) -> bool:
	if chunk.mesh_instance.mesh == null:
		return false
	var arrays: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var found := false
	for first: int in range(0,vertices.size(),4):
		var face: int = CHUNK.DIRECTIONS.find(Vector3i(normals[first]))
		var owner: Vector3i = chunk.coordinate*CHUNK.CHUNK_SIZE+Vector3i(vertices[first]-CHUNK.CORNERS[face][0])
		if owner != cell:
			continue
		found = true
		for corner: int in 4:
			var color: Color = colors[first+corner]
			if absf(color.r-expected.r)>0.00001 or absf(color.g-expected.g)>0.00001 or absf(color.b-expected.b)>0.00001:
				return false
	return found

func same_alpha(before: PackedColorArray, after: PackedColorArray) -> bool:
	if before.size() != after.size():
		return false
	for index: int in before.size():
		if not is_equal_approx(before[index].a,after[index].a):
			return false
	return true

func finish_units(world: Node3D, cap: int = 20000) -> int:
	var units := 0
	while int(world.get_rebuild_stats().pending_chunks)>0 and units<cap:
		var result: Dictionary = world.process_rebuild_work(1,1000000)
		check(int(result.processed_units)<=1,"explicit unit budget bounds each deterministic work slice")
		if int(result.processed_units)==0:
			check(false,"queued nearby work must make progress")
			break
		units += int(result.processed_units)
	check(units<cap and int(world.get_rebuild_stats().pending_chunks)==0,"bounded work completes before the fixture safety cap")
	return units

func fixture() -> Node3D:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,32,32))
	world.water_enabled = false
	world.visual_effects_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	world.data.seed_box(Vector3i(4,4,4),Vector3i(28,16,28),PALETTE)
	world.data.seed_box(Vector3i(14,16,15),Vector3i(15,17,16),0x01654321)
	world._mark_all_chunks()
	world.rebuild_now()
	world.blocks_changed.connect(func(_changes: Array) -> void:block_events += 1)
	return world

func raw_attributes(mesh: Mesh) -> PackedByteArray:
	var surface: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(),0)
	return surface.attribute_data

func verify_all_rgb_bytes() -> void:
	# The oracle uses Godot's full add_surface_from_arrays encoding. Attribute
	# uploads must match its RGBA8 conversion exactly, including float rounding.
	var world := WORLD.new()
	world.clear_world(Vector3i(16,8,16))
	world.water_enabled = false
	world.visual_effects_enabled = false
	root.add_child(world)
	world.set_process(false)
	var cell := Vector3i(7,5,7)
	world.set_block(cell,PALETTE)
	world.set_block(Vector3i(6,6,7),0x01654321)
	world.rebuild_now()
	var actual: Node3D = world._chunks[Vector3i.ZERO]
	var retained: Mesh = actual.mesh_instance.mesh
	var collider: Shape3D = actual.collision.shape
	var reference := CHUNK.new()
	var initial: Dictionary = world.get_rebuild_stats()
	for byte: int in 256:
		var packed: int = 0x01000000 | (byte<<16) | ((255-byte)<<8) | byte
		world.set_block(cell,packed)
		world.rebuild_now()
		reference.rebuild(world,world._material,false)
		check(raw_attributes(actual.mesh_instance.mesh)==raw_attributes(reference.mesh_instance.mesh),"healthy RGB byte %d upload exactly matches full-build raw RGBA8/AO/UV encoding"%byte)
		check(actual.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==reference.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR],"healthy RGB byte %d mesh readback matches the full-build palette"%byte)
		world.set_block_damaged(cell,true)
		world.rebuild_now()
		reference.rebuild(world,world._material,false)
		check(raw_attributes(actual.mesh_instance.mesh)==raw_attributes(reference.mesh_instance.mesh),"damaged RGB byte %d upload exactly matches full-build floor-halving and AO encoding"%byte)
		world.set_block_damaged(cell,false)
		world.rebuild_now()
		reference.rebuild(world,world._material,false)
		check(raw_attributes(actual.mesh_instance.mesh)==raw_attributes(reference.mesh_instance.mesh),"recovered RGB byte %d upload exactly matches full-build raw encoding"%byte)
	check(actual.mesh_instance.mesh==retained and actual.collision.shape==collider,"all 256 byte repaints/damage/recovery retain the same live mesh and collider")
	var after: Dictionary = world.get_rebuild_stats()
	check(int(after.mesh_builds)==int(initial.mesh_builds) and int(after.collision_builds)==int(initial.collision_builds),"exhaustive palette updates never trigger full geometry/AO/collider rebuilds")
	reference.free()
	world.free()

func run() -> void:
	verify_all_rgb_bytes()
	var world: Node3D = fixture()
	check(world.has_method("get_rebuild_stats") and world.has_method("process_rebuild_work"),"optimized World exposes reproducible bounded-work counters")
	if not world.has_method("get_rebuild_stats") or not world.has_method("process_rebuild_work"):
		world.free()
		quit(1)
		return
	var chunk: Node3D = world._chunks[Vector3i.ZERO]
	var mesh: Mesh = chunk.mesh_instance.mesh
	var shape: Shape3D = chunk.collision.shape
	var initial: Array = mesh.surface_get_arrays(0)
	var original_colors: PackedColorArray = initial[Mesh.ARRAY_COLOR]
	var journal: Dictionary = world.data.get_journal_stats()
	var initial_stats: Dictionary = world.get_rebuild_stats()
	check(rgb_matches(chunk,CELL,WORLD.block_color(PALETTE)),"fixture renders the odd source RGB bytes before damage")
	var had_ao := false
	for color: Color in original_colors:
		had_ao = had_ao or color.a<0.99
	check(had_ao,"fixture contains nontrivial AO that a color update must preserve")
	world.set_block_damaged(CELL,true)
	check(world.is_block_damaged(CELL) and world._collision_dirty.is_empty(),"first surviving hit changes persistent color mask without collision invalidation")
	world.rebuild_now()
	var damaged: Array = mesh.surface_get_arrays(0)
	var after: Dictionary = world.get_rebuild_stats()
	check(chunk.mesh_instance.mesh==mesh and chunk.collision.shape==shape,"color-only hit retains live mesh and collider objects")
	check(rgb_matches(chunk,CELL,WORLD.block_color(HALF)),"color upload applies exact byte-floor RGB halving to the owning voxel")
	check(damaged[Mesh.ARRAY_VERTEX]==initial[Mesh.ARRAY_VERTEX] and damaged[Mesh.ARRAY_NORMAL]==initial[Mesh.ARRAY_NORMAL] and damaged[Mesh.ARRAY_INDEX]==initial[Mesh.ARRAY_INDEX],"color upload leaves vertex geometry, normals and topology unchanged")
	check(damaged[Mesh.ARRAY_TEX_UV2]==initial[Mesh.ARRAY_TEX_UV2] and same_alpha(original_colors,damaged[Mesh.ARRAY_COLOR]),"color upload preserves source AO UVs and corner alpha")
	check(int(after.mesh_builds)==int(initial_stats.mesh_builds) and int(after.collision_builds)==int(initial_stats.collision_builds),"damage skips voxel scans, AO geometry builds and collision cooking")
	check(int(after.color_updates)>int(initial_stats.color_updates) and int(after.color_vertices)>int(initial_stats.color_vertices),"work counters identify the actual bounded color upload")
	check(int(after.color_vertices)-int(initial_stats.color_vertices)<=24,"one voxel color update touches at most its six visible quads")
	check(int(after.color_upload_bytes)-int(initial_stats.color_upload_bytes)<original_colors.size()*4,"one damaged voxel uploads fewer bytes than all chunk vertex colors")
	check(world.get_block(CELL)==PALETTE and world.data.get_journal_stats()==journal and block_events==0,"presentation hit never changes intrinsic terrain, journal or authority events")

	var repeated: Dictionary = after.duplicate()
	for repeat: int in 30:
		world.set_block_damaged(CELL,true)
		world.rebuild_now()
	var repeated_after: Dictionary = world.get_rebuild_stats()
	check(int(repeated_after.color_updates)==int(repeated.color_updates) and int(repeated_after.mesh_builds)==int(repeated.mesh_builds),"all repeated surviving SMG hits on the dark cell are upload/build no-ops")
	world.set_block_damaged(CELL,false)
	world.rebuild_now()
	check(rgb_matches(chunk,CELL,WORLD.block_color(PALETTE)) and chunk.mesh_instance.mesh==mesh and chunk.collision.shape==shape,"explicit recovery updates RGB in place and keeps physics")
	world.set_block_damaged(CELL,true)
	world.set_block_damaged(CELL,false)
	var toggle_before: Dictionary = world.get_rebuild_stats()
	world.rebuild_now()
	check(rgb_matches(chunk,CELL,WORLD.block_color(PALETTE)) and int(world.get_rebuild_stats().mesh_builds)==int(toggle_before.mesh_builds),"coalesced toggle resolves to the latest mask without a geometry build")

	# Starting a destructive job must retain the previous complete render/collision.
	var cut := Vector3i(8,15,8)
	var removal: Array[Vector3i] = [cut]
	world.remove_blocks(removal)
	var first: Dictionary = world.process_rebuild_work(1,1000000)
	check(int(first.processed_units)==1 and int(world.get_rebuild_stats().pending_chunks)>0,"one unit starts a dense chunk job while further work remains queued")
	check(chunk.mesh_instance.mesh==mesh and chunk.collision.shape==shape,"partial geometry staging publishes neither incomplete mesh nor collider")
	world.set_block_damaged(CELL,true)
	finish_units(world)
	check(world.get_block(cut)==0 and chunk.mesh_instance.mesh!=mesh and chunk.collision.shape!=shape,"completed destruction atomically replaces render and collision geometry")
	check(rgb_matches(chunk,CELL,WORLD.block_color(HALF)),"damage arriving during a geometry job is included in the completed terrain")
	var ray: Dictionary = world.cast_voxel(Vector3(cut)+Vector3(0.5,2,0.5),Vector3.DOWN,4)
	check(ray.hit and ray.cell==cut+Vector3i.DOWN,"source DDA immediately sees the removed top block and surviving support")

	# A later edit invalidates any staged geometry from the earlier map revision.
	var stale_cell := Vector3i(9,15,8)
	world.set_block(stale_cell,0)
	world.process_rebuild_work(1,1000000)
	var previous: Mesh = chunk.mesh_instance.mesh
	world.set_block(stale_cell,0x01000000)
	world.set_block(CELL,0x01876543)
	finish_units(world)
	check(chunk.mesh_instance.mesh!=previous and world.get_block(stale_cell)==0x01000000,"later solid-black replacement supersedes an unfinished removal")
	check(not world.is_block_damaged(CELL) and rgb_matches(chunk,CELL,WORLD.block_color(0x01876543)),"real repaint clears damage and cannot receive a stale color request")
	check(rgb_matches(chunk,stale_cell,Color.BLACK),"optimized geometry preserves solid black rather than encoding it as air")
	await physics_frame
	await physics_frame
	var physics_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cut)+Vector3(0.5,2,0.5),Vector3(cut)+Vector3(0.5,-0.5,0.5)))
	check(not physics_hit.is_empty() and absf(physics_hit.position.y-float(cut.y))<0.001,"published collider preserves the exact removed top-cell opening")

	world.set_block_damaged(stale_cell,true)
	world.set_block(stale_cell,0)
	world.set_block(stale_cell,PALETTE)
	world.rebuild_now()
	check(not world.is_block_damaged(stale_cell) and rgb_matches(chunk,stale_cell,WORLD.block_color(PALETTE)),"queued darkening cannot leak through delete/recreate at matching coordinates")
	world.set_block(Vector3i(10,15,8),0)
	world.process_rebuild_work(1,1000000)
	world.clear_world(Vector3i(16,8,16))
	world.data.seed_box(Vector3i.ZERO,Vector3i(16,2,16),0x01876543)
	world._mark_all_chunks()
	finish_units(world)
	check(world._chunks.size()==1 and int(world.get_rebuild_stats().pending_color_chunks)==0,"map replacement discards all previous staged chunks and color requests")
	check(world.get_block(CELL)==0 and not world.is_block_damaged(CELL),"reset cannot revive an old coordinate, damage mask or staged geometry")
	world.free()
	await process_frame
	print("BLOCK IMPACT OPTIMIZATION TESTS: %d assertions, %d failures"%[assertions,failures])
	quit(1 if failures else 0)
