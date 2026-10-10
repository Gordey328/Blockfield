extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
const REFLECTION = preload("res://world/planar_reflection.gd")
const POST = preload("res://presentation/openspades_post_effects.gd")
var assertions := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("REFLECTION DATA: " + message)
func box(parent: Node, location: Vector3, layer: int = 1) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	node.position = location
	node.layers = layer
	parent.add_child(node)
	return node
func _run() -> void:
	var original := Transform3D(Basis.from_euler(Vector3(-0.4, 0.7, 0.1)), Vector3(5, 8, 7))
	var mirrored: Transform3D = REFLECTION.mirrored_transform(original, 2.0)
	check(mirrored.origin == Vector3(5, -4, 7) and absf(mirrored.basis.determinant() - 1) < 0.000001, "mirror eye around water and retain a valid camera basis")
	var original_point := Vector3(9, 2, 5)
	var local := original.affine_inverse() * original_point
	var mirrored_local := mirrored.affine_inverse() * original_point
	check(absf(local.y - mirrored_local.y) < 0.000001 and absf(local.z - mirrored_local.z) < 0.000001 and absf(local.x + mirrored_local.x) < 0.000001, "water-plane points must project consistently with reversed horizontal axis")
	var scene := SubViewport.new()
	scene.size = Vector2i(640, 480)
	scene.own_world_3d = true
	root.add_child(scene)
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	world.water_level = 2.0
	scene.add_child(world)
	world._create_water()
	var camera := Camera3D.new()
	camera.position = Vector3(8, 8, 14)
	world.add_child(camera)
	camera.look_at(Vector3(8, 2, 7))
	camera.current = true
	var normal := box(world, Vector3(8, 4, 7))
	box(world, Vector3(7, 4, 7), REFLECTION.VIEW_LAYER)
	box(world, Vector3(8, -1, 7))
	var custom := box(world, Vector3(9, 4, 7))
	custom.material_override = world._material
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 2.0
	world.add_child(sun)
	world.set_reflection_camera(camera)
	var reflection: Node = world._reflection
	check(not world.water_reflections_enabled and not reflection.enabled and reflection.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "reflection must default off without GPU/CPU work")
	world.set_water_reflections_enabled(true)
	check(reflection.update_now(), "enabled reflection must prepare a real scene")
	var stats: Dictionary = reflection.get_stats()
	check(stats.geometry == 2 and stats.clipped_below == 1 and stats.lights == 1, "mirror must select normal/custom above-water geometry, omit underwater objects and FP/water layers")
	check(stats.resolution == Vector2i(320, 240) and stats.texture_and_depth_bytes == 614400, "mirror target must preserve 4:3 aspect within a bounded color/depth allocation")
	check(reflection.viewport.world_3d != scene.world_3d and reflection._proxies[normal.get_instance_id()].base == normal.mesh, "reflection must use its own clipped scenario and share the source mesh")
	check(reflection._lights[sun.get_instance_id()].light_energy == 2.0 and not reflection._lights[sun.get_instance_id()].shadow_enabled and sun.shadow_enabled, "mirror lights must copy energy while keeping additional shadow atlases disabled")
	var custom_proxy: ShaderMaterial = reflection._proxies[custom.get_instance_id()].materials[0]
	check(custom_proxy.shader.code.contains("discard") and absf(custom_proxy.get_shader_parameter("reflection_clip_level") - 2.002) < 0.000001, "clipped custom shader must preserve the terrain pipeline and bind the actual plane")
	var normal_entry: Dictionary = reflection._proxies[normal.get_instance_id()]
	var old_mesh: Mesh = normal_entry.base
	normal.mesh = BoxMesh.new()
	reflection.update_now()
	check(normal_entry.base == normal.mesh and normal_entry.base != old_mesh and normal_entry.material_rids.size() == 1, "source mesh replacement must rebind a clipped material without cloning the mesh")
	var removal := box(world, Vector3(8, 5, 6))
	reflection.update_now()
	var removal_key := removal.get_instance_id()
	check(reflection._proxies.has(removal_key), "node-added registry must reflect dynamically added world geometry")
	world.remove_child(removal)
	removal.free()
	reflection.update_now()
	check(not reflection._proxies.has(removal_key) and not reflection._source_nodes.has(removal_key), "node removal must release its render proxy and source registry entry")
	camera.h_offset = 0.3
	camera.v_offset = -0.2
	reflection.update_now()
	var expected: Transform3D = REFLECTION.mirrored_transform(camera.get_camera_transform(), reflection.plane_level)
	check(reflection.mirror_camera.get_camera_transform().is_equal_approx(expected), "camera offsets must be mirrored once, without duplication")
	camera.h_offset = 0
	camera.v_offset = 0
	var post := POST.new()
	world.add_child(post)
	post.setup(camera)
	check(post._depth_quad.layers == REFLECTION.VIEW_LAYER, "screen-space depth post quad must be isolated on the excluded view layer")
	for index in range(12):
		box(world, Vector3(2 + index, 4, 6))
	world.set_water_reflection_budget(Vector2i(999, 999), 99, 8)
	reflection.update_now()
	stats = reflection.get_stats()
	check(stats.geometry == 8 and stats.budget_omitted == 6 and stats.updates_per_second == 30 and stats.resolution.x <= 512 and stats.resolution.y <= 512, "geometry, resolution and update rate must enforce their work budgets")
	world.set_water_enabled(false)
	check(not reflection.enabled and reflection.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "water-off must suspend mirror updates")
	world.set_water_enabled(true)
	reflection.update_now()
	camera.position.y = 1
	check(not reflection.update_now() and not world._water_mesh.mesh.surface_get_material(0).get_shader_parameter("reflection_enabled"), "submerged eye must suspend the surface reflection model")
	camera.position.y = 8
	world.set_water_reflections_enabled(false)
	check(not reflection.is_processing() and not world._water_mesh.mesh.surface_get_material(0).get_shader_parameter("reflection_enabled"), "reflection-off must disable actual sampling and scheduling")
	world.clear_world(Vector3i(16, 16, 16))
	check(world._reflection == null, "map reset must release reflection geometry/scenario targets")
	scene.queue_free()
	await process_frame
	await process_frame
	print("REFLECTION DATA TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
