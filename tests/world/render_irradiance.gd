extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
var assertions := 0
var failures := 0
var output := ""
var viewport: SubViewport
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("IRRADIANCE GPU: " + message)
func capture(label: String) -> Image:
	for frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(output.path_join(label + ".png"))
	return image
func mean_brightness(image: Image) -> float:
	var sum := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			sum += (color.r + color.g + color.b) / 3.0
	return sum / (image.get_width() * image.get_height())
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = OS.get_cache_dir().path_join("blockfield-irradiance")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	world.water_enabled = false
	viewport.add_child(world)
	world._fill_box(Vector3i.ZERO, Vector3i(16, 2, 16), 0x01ffffff)
	world._fill_box(Vector3i(3, 2, 8), Vector3i(13, 8, 9), 0x01ff1008)
	world._mark_all_chunks()
	world.rebuild_now()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.015, 0.015)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.0
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	camera.position = Vector3(20, 16, -9)
	world.add_child(camera)
	camera.look_at(Vector3(8, 2, 7))
	camera.current = true
	var dark: Image = await capture("01-gi-off")
	world.set_irradiance_light(Color.WHITE, 1.0)
	world.set_irradiance_enabled(true)
	world._irradiance.flush()
	var red_bounce: Image = await capture("02-red-bounce")
	check(mean_brightness(red_bounce) > mean_brightness(dark) + 0.003, "actual coefficient textures must illuminate terrain with GI on")
	var point := Vector2i(camera.unproject_position(Vector3(8.5, 2.002, 5.5)))
	var red := red_bounce.get_pixelv(point)
	check(red.r > red.g + 0.015 and red.r > red.b + 0.015, "red Sun-lit source wall must transfer color onto unchanged white floor")
	var ray_origin := camera.project_ray_origin(Vector2(point) + Vector2.ONE * 0.5)
	var ray_direction := camera.project_ray_normal(Vector2(point) + Vector2.ONE * 0.5)
	var actual_point := ray_origin + ray_direction * ((2.0 - ray_origin.y) / ray_direction.y)
	var query: Color = world.get_irradiance_at(actual_point, Vector3.UP)
	# Compare through the same actual renderer color transfer, rather than
	# assuming raw linear shader values equal 8-bit framebuffer RGB.
	var reference_shader := Shader.new()
	reference_shader.code = "shader_type spatial; render_mode unshaded; uniform vec3 radiance; void fragment(){ALBEDO=radiance;}"
	var reference_material := ShaderMaterial.new()
	reference_material.shader = reference_shader
	reference_material.set_shader_parameter("radiance", Vector3(query.r,query.g,query.b))
	world._chunks[Vector3i.ZERO].mesh_instance.material_override = reference_material
	var reference_image: Image = await capture("02b-cpu-radiance-reference")
	var reference_pixel := reference_image.get_pixelv(point)
	world._chunks[Vector3i.ZERO].mesh_instance.material_override = null
	check(absf(red.r - reference_pixel.r) < 0.008 and absf(red.g - reference_pixel.g) < 0.008 and absf(red.b - reference_pixel.b) < 0.008, "GPU RGB16F interpolation must match CPU radiance rendered through the same Compatibility color transfer")
	for y in range(2, 8):
		for x in range(3, 13):
			world.set_block(Vector3i(x, y, 8), 0x0108ff10)
	world.rebuild_now()
	world._irradiance.flush()
	var green_bounce: Image = await capture("03-green-bounce")
	var green := green_bounce.get_pixelv(point)
	check(green.g > green.r + 0.015 and green.g > green.b + 0.015 and green.g > red.g + 0.015, "source palette edits must update actual green bounce without repainting receiver")
	world.set_irradiance_light(Color.WHITE, 0.0)
	var no_energy: Image = await capture("04-zero-source-energy")
	check(absf(mean_brightness(no_energy) - mean_brightness(dark)) < 0.0001, "zero source energy must remove GI contribution")
	world.set_irradiance_light(Color.WHITE, 1.0)
	world.set_irradiance_enabled(false)
	var off: Image = await capture("05-gi-off-after-edit")
	check(absf(mean_brightness(off) - mean_brightness(dark)) < 0.0001, "GI switch must remove real bounce rather than a no-op uniform")
	var stats: Dictionary = world.get_irradiance_stats()
	var metrics := {"renderer":RenderingServer.get_video_adapter_name(), "red_pixel":[red.r,red.g,red.b], "green_pixel":[green.r,green.g,green.b], "cpu_red_radiance":[query.r,query.g,query.b], "cpu_rendered_reference":[reference_pixel.r,reference_pixel.g,reference_pixel.b],"sampled_world_point":actual_point, "dark_mean":mean_brightness(dark), "gi_mean":mean_brightness(red_bounce), "stats":stats, "assertions":assertions,"failures":failures}
	FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	print("IRRADIANCE GPU TESTS: %d assertions, %d failures; %s" % [assertions,failures,output])
	print(JSON.stringify(metrics))
	viewport.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
