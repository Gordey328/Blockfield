extends SceneTree
## Packed AO/dirty-region/API tests. GPU lighting is checked separately.
const WORLD = preload("res://world/voxel_world.gd")
const AO = preload("res://world/voxel_ao.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("LIGHTING TEST: " + message)

func _run() -> void:
	AO.initialize()
	check(is_equal_approx(AO.atlas_corner(0, 0), 1.0) and is_equal_approx(AO.atlas_corner(0, 3), 1.0), "native empty AO tile must be fully exposed")
	check(absf(AO.atlas_corner(1, 0) - 184.0 / 255.0) < 0.00001, "native negative-u occluder must match atlas golden corner 184")
	check(AO.atlas_corner(1, 1) > 0.99, "opposite native corner must remain exposed")
	check(absf(AO.atlas_corner(255, 0) - 112.0 / 255.0) < 0.00001, "eight native occluders must match dense-atlas golden corner 112")
	var world := WORLD.new()
	world.clear_world(Vector3i(32, 32, 32))
	world.water_enabled = false
	root.add_child(world)
	var palette := 0x01806040
	world.set_block(Vector3i(7, 7, 7), palette)
	world.rebuild_now()
	var chunk: Node3D = world._chunks[Vector3i.ZERO]
	var isolated: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	check(isolated[Mesh.ARRAY_VERTEX].size() == 24 and isolated[Mesh.ARRAY_INDEX].size() == 36, "one block must use four indexed vertices per face")
	var all_exposed := true
	for color in isolated[Mesh.ARRAY_COLOR]:
		all_exposed = all_exposed and absf(color.a - 1.0) < 0.00001
	check(all_exposed, "isolated cube must have no AO shadow on its six faces")
	world.set_block(Vector3i(6, 8, 7), palette)
	world.rebuild_now()
	var arrays: Array = chunk.mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var near := -1.0
	var far := -1.0
	var palette_unchanged := true
	for index in range(vertices.size()):
		var color := colors[index]
		palette_unchanged = palette_unchanged and absf(color.r - 128.0 / 255.0) < 0.0001 and absf(color.g - 96.0 / 255.0) < 0.0001 and absf(color.b - 64.0 / 255.0) < 0.0001
		if normals[index].dot(Vector3.UP) > 0.999 and vertices[index].is_equal_approx(Vector3(7, 8, 7)):
			near = color.a
		if normals[index].dot(Vector3.UP) > 0.999 and vertices[index].is_equal_approx(Vector3(8, 8, 7)):
			far = color.a
	check(palette_unchanged, "mesh RGB must preserve every source palette channel on all orientations")
	check(absf(near - 184.0 / 255.0) < 0.0001 and far > 0.99, "real top face native corner factors (near=%f far=%f)" % [near, far])
	var mesh_before: Mesh = chunk.mesh_instance.mesh
	var shape_before: Shape3D = chunk.collision.shape
	world.set_ambient_occlusion_enabled(false)
	check(world._material.get_shader_parameter("ambient_occlusion_strength") == 0.0, "AO toggle must update shared material")
	world.set_lighting_enabled(false)
	check(not world._material.get_shader_parameter("lighting_enabled"), "lighting toggle must update shared material")
	check(chunk.mesh_instance.mesh == mesh_before and chunk.collision.shape == shape_before and world.get_stats().dirty_chunks == 0, "lighting toggles must not allocate mesh or rebuild collision")
	world.set_lighting_enabled(true)
	world.set_ambient_occlusion_enabled(true)
	check(world._material.get_shader_parameter("lighting_enabled") and world._material.get_shader_parameter("ambient_occlusion_strength") == 1.0, "both lighting settings must re-enable")
	world.set_block(Vector3i(7, 7, 7), 0x01708030)
	world.rebuild_now()
	check(chunk.collision.shape == shape_before and chunk.mesh_instance.mesh != mesh_before, "palette repaint must rebuild visible colors without recooking identical collision")
	world.clear_world(Vector3i(16, 16, 16))
	world._fill_box(Vector3i.ZERO, Vector3i(16, 2, 16), palette)
	world._mark_all_chunks()
	world.rebuild_now()
	var slab: Node3D = world._chunks[Vector3i.ZERO]
	check(slab.face_count == 640 and slab.collision_face_count == 6, "uniform slab must keep voxel render faces but merge collision into six exact rectangles")
	await physics_frame
	await physics_frame
	var solid_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(6.5, 3, 7.5), Vector3(6.5, 1.5, 7.5)))
	check(not solid_hit.is_empty() and absf(solid_hit.position.y - 2.0) < 0.001, "merged collider must register and physically cover the slab surface")
	world._blocks[world._index(Vector3i(7, 1, 7))] = 0
	world._mark_dirty(Vector3i(7, 1, 7))
	world.rebuild_now()
	await physics_frame
	await physics_frame
	var hole_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(7.5, 3, 7.5), Vector3(7.5, 1.5, 7.5)))
	check(slab.collision_face_count > 6 and hole_hit.is_empty(), "greedy collision must preserve a removed cell opening")
	world.clear_world(Vector3i(32, 32, 32))
	world.set_block(Vector3i(15, 15, 15), palette)
	check(world.get_stats().dirty_chunks == 8, "corner edit must invalidate all eight AO-dependent chunks")
	world._dirty.clear()
	world.set_block(Vector3i(15, 5, 15), palette)
	check(world.get_stats().dirty_chunks == 4, "edge edit must invalidate four AO-dependent chunks")
	world._dirty.clear()
	world.set_block(Vector3i(15, 5, 8), palette)
	check(world.get_stats().dirty_chunks == 2, "single-border edit must invalidate only two chunks")
	world._dirty.clear()
	world.set_block(Vector3i(14, 5, 8), palette)
	check(world.get_stats().dirty_chunks == 1, "interior edit must invalidate only one chunk")
	world._create_water()
	check(world.set_draw_distance(81.0) == 96.0 and world.get_draw_distance() == 96.0, "draw distance must round upward to whole chunks")
	check(world._water_mesh.mesh.surface_get_material(0).get_shader_parameter("fog_distance") == 96.0, "water fog must track quantized draw distance")
	check(world.set_draw_distance(0.0) == 16.0 and world.set_draw_distance(900.0) == 160.0, "draw distance must enforce browser-facing 16..160 bounds")
	world.clear_world(Vector3i(512, 64, 512))
	world.set_block(Vector3i(511, 1, 0), palette)
	var halo: Dictionary = AO.build_halo(world, Vector3i.ZERO)
	var x_edge := 2 + 18 * (0 + 18)
	check(halo.blocks[x_edge] == 0 and halo.solids[x_edge] == 1, "native AO wraps horizontal map boundaries while physical collision remains bounded")
	check(halo.solids[18 * (1 + 18)] == 1 and halo.blocks[18 * (1 + 18)] == 0, "below-map AO must be solid without creating physical voxels")
	var upper: Dictionary = AO.build_halo(world, Vector3i(0, 64, 0))
	check(upper.solids[2 + 18 * (1 + 18)] == 0, "above-map AO must be open sky")
	world.free()
	print("LIGHTING DATA TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
