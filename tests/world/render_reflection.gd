extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
const REFLECTION = preload("res://world/planar_reflection.gd")
const MODELS = preload("res://presentation/openspades_models.gd")
var assertions := 0
var failures := 0
var output := ""
var viewport: SubViewport
var world: Node3D
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("REFLECTION GPU: " + message)
func capture(label: String, mirror: bool = false) -> Image:
	for frame in range(5):
		if world._reflection != null:
			world._reflection.update_now()
		await process_frame
		await RenderingServer.frame_post_draw
	var texture: Texture2D = world._reflection.viewport.get_texture() if mirror else viewport.get_texture()
	var image := texture.get_image()
	image.save_png(output.path_join(label + ".png"))
	return image
func difference(a: Image, b: Image) -> float:
	var total := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(a.get_width() * a.get_height() * 3)
func marker(parent: Node, position: Vector3, color: Color, size: Vector3 = Vector3.ONE, layer: int = 1) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material = material
	node.mesh = mesh
	node.position = position
	node.layers = layer
	parent.add_child(node)
	return node
func brightest_near(image: Image, pixel: Vector2i, radius: int = 2) -> Color:
	var color := Color.BLACK
	for y in range(maxi(0, pixel.y - radius), mini(image.get_height(), pixel.y + radius + 1)):
		for x in range(maxi(0, pixel.x - radius), mini(image.get_width(), pixel.x + radius + 1)):
			var sampled := image.get_pixel(x, y)
			if sampled.r + sampled.g + sampled.b > color.r + color.g + color.b:
				color = sampled
	return color
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = OS.get_cache_dir().path_join("blockfield-reflection")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	world.water_level = 2.2
	viewport.add_child(world)
	for z in range(16):
		for x in range(16):
			world._fill_box(Vector3i(x, 0, z), Vector3i(x + 1, 2, z + 1), 0x01242424)
	world._fill_box(Vector3i(3, 2, 7), Vector3i(5, 6, 9), 0x01e02010)
	world._mark_all_chunks()
	world.rebuild_now()
	world._create_water()
	world.set_water_waves_enabled(false)
	world.set_water_refraction_enabled(false)
	world.set_lighting_enabled(false)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.025, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	var camera := Camera3D.new()
	camera.position = Vector3(8, 5.5, 20)
	world.add_child(camera)
	camera.look_at(Vector3(8, 2.2, 7))
	camera.current = true
	var green := marker(world, Vector3(11, 5, 8), Color(0.03, 0.9, 0.04), Vector3(2, 4, 2))
	var submerged := marker(world, Vector3(8, 1.5, 7), Color(0.05, 0.08, 1), Vector3(2, 1, 2))
	var partial := marker(world, Vector3(8, 2, 11), Color(1, 0.04, 0.9), Vector3(2, 2, 1))
	var view_marker := marker(world, Vector3(8, 5, 10), Color(1, 1, 0), Vector3(2, 2, 2), REFLECTION.VIEW_LAYER)
	var model: Node3D = MODELS.create("Player/Head")
	model.position = Vector3(8, 4, 8)
	model.scale = Vector3.ONE * 0.1
	world.add_child(model)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var batch_material := StandardMaterial3D.new()
	batch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	batch_material.vertex_color_use_as_albedo = true
	batch_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = batch_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(2, 4, 11)))
	multimesh.set_instance_color(0, Color(0.05, 0.8, 0.9))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multimesh
	world.add_child(batch)
	var sprite := Sprite3D.new()
	sprite.texture = load("res://assets/openspades/images/Gfx/White.png")
	sprite.pixel_size = 1.5 / float(sprite.texture.get_width())
	sprite.position = Vector3(13, 4, 11)
	sprite.modulate = Color(1, 0.4, 0.02)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.add_child(sprite)
	world.set_reflection_camera(camera)
	var off: Image = await capture("01-reflection-off")
	world.set_water_reflections_enabled(true)
	world._reflection.set_process(false)
	var on: Image = await capture("02-reflection-on")
	var mirror: Image = await capture("mirror-on", true)
	check(difference(off, on) > 0.001, "real planar reflection must change the water image")
	var mirror_camera: Camera3D = world._reflection.mirror_camera
	var green_pixel := Vector2i(mirror_camera.unproject_position(Vector3(11, 5, 9.002)))
	var green_sample := brightest_near(mirror, green_pixel)
	check(green_sample.g > green_sample.r * 3.0 and green_sample.g > green_sample.b * 3.0, "source colored geometry must appear at its mirror-camera projection")
	var terrain_pixel := Vector2i(mirror_camera.unproject_position(Vector3(4, 4.5, 9.002)))
	var terrain_sample := brightest_near(mirror, terrain_pixel)
	check(terrain_sample.r > terrain_sample.g * 2.5, "cloned full terrain shader must retain original palette in the mirror")
	var batch_sample := brightest_near(mirror, Vector2i(mirror_camera.unproject_position(Vector3(2, 4, 11))), 1)
	check(batch_sample.g > 0.5 and batch_sample.b > 0.6 and batch_sample.r < 0.15, "shared MultiMesh proxy must retain per-instance fragment colors")
	var sprite_sample := brightest_near(mirror, Vector2i(mirror_camera.unproject_position(Vector3(13, 4, 11))), 1)
	check(sprite_sample.r > 0.8 and sprite_sample.g > 0.1 and sprite_sample.b < 0.15, "sprite proxy must face the mirror camera and retain its source texture/tint")
	var reflected_green_position := Vector3(11, world._water_mesh.global_position.y * 2.0 - 5.0, 9.002)
	var water_green_pixel := Vector2i(camera.unproject_position(reflected_green_position))
	var water_green_sample := on.get_pixelv(water_green_pixel)
	var water_green_off_sample := off.get_pixelv(water_green_pixel)
	check(water_green_sample.g > water_green_sample.r * 1.1 and water_green_sample.g > water_green_off_sample.g + 0.003, "the mirror buffer must project the colored object into its physical reflection on the water surface")
	var before_hidden: Image = mirror.duplicate()
	view_marker.visible = false
	submerged.visible = false
	var after_hidden: Image = await capture("mirror-hidden-excluded", true)
	check(difference(before_hidden, after_hidden) < 0.00001, "below-plane geometry and first-person layer must never enter the mirror buffer")
	var below_partial_pixel := Vector2i(mirror_camera.unproject_position(Vector3(8, 1.8, 11.502)))
	var above_partial_pixel := Vector2i(mirror_camera.unproject_position(Vector3(8, 2.7, 11.502)))
	var below_sample := brightest_near(mirror, below_partial_pixel, 0)
	var above_sample := brightest_near(mirror, above_partial_pixel, 0)
	check(below_sample.r < 0.15 and above_sample.r > 0.4 and above_sample.b > 0.2, "reflection fragment clip must cut a model intersecting the water plane")
	var on_again: Image = await capture("03-excluded-hidden")
	green.position.x -= 2.0
	var moved: Image = await capture("04-marker-moved")
	check(difference(on_again, moved) > 0.0001, "moving source geometry must update actual reflection")
	var updated_mirror: Image = await capture("mirror-moved", true)
	check(difference(after_hidden, updated_mirror) > 0.001, "reflection proxies must follow source transforms")
	world.set_lighting_enabled(true)
	var omni := OmniLight3D.new()
	omni.position = Vector3(4, 5, 12)
	omni.omni_range = 12
	omni.light_energy = 6
	omni.visible = false
	world.add_child(omni)
	var dark_mirror: Image = await capture("mirror-light-off", true)
	omni.visible = true
	var lit_mirror: Image = await capture("mirror-light-on", true)
	check(difference(dark_mirror, lit_mirror) > 0.001, "mirror must copy live lighting, not an image of palette colors alone")
	world.set_water_reflections_enabled(false)
	var disabled: Image = await capture("05-disabled")
	check(not world._reflection.is_processing() and not world._water_mesh.mesh.surface_get_material(0).get_shader_parameter("reflection_enabled"), "disable must stop scheduling and geometric reflection sampling")
	var metrics := {"renderer":RenderingServer.get_video_adapter_name(), "reflection_difference":difference(off,on), "moved_difference":difference(after_hidden,updated_mirror), "light_difference":difference(dark_mirror,lit_mirror), "green_sample":[green_sample.r,green_sample.g,green_sample.b], "water_green_sample":[water_green_sample.r,water_green_sample.g,water_green_sample.b], "water_green_off_sample":[water_green_off_sample.r,water_green_off_sample.g,water_green_off_sample.b], "terrain_sample":[terrain_sample.r,terrain_sample.g,terrain_sample.b], "below_clip_sample":[below_sample.r,below_sample.g,below_sample.b], "above_clip_sample":[above_sample.r,above_sample.g,above_sample.b], "stats":world.get_reflection_stats(), "assertions":assertions,"failures":failures}
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	print("REFLECTION GPU TESTS: %d assertions, %d failures; %s" % [assertions,failures,output])
	print(JSON.stringify(metrics))
	partial.queue_free()
	viewport.queue_free()
	await process_frame
	await process_frame
	MODELS.clear_cache()
	quit(1 if failures else 0)
