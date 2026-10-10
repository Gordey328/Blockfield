extends SceneTree
## Actual GPU evidence; intentionally requires Compatibility graphics, not headless.
## godot --path game --rendering-method gl_compatibility --script ../tests/world/render_lighting.gd -- --output=<absolute directory>
const WORLD = preload("res://world/voxel_world.gd")
var assertions := 0
var failures := 0
var _output := ""
var _viewport: SubViewport

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("LIGHTING GPU: " + message)

func capture(label: String) -> Image:
	for frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.save_png(_output.path_join(label + ".png"))
	return image

func mean_brightness(image: Image) -> float:
	var total := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			total += (color.r + color.g + color.b) / 3.0
	return total / float(image.get_width() * image.get_height())

func difference(a: Image, b: Image) -> Dictionary:
	var darkened := 0
	var total := 0.0
	var absolute := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := (ca.r + ca.g + ca.b - cb.r - cb.g - cb.b) / 3.0
			total += delta
			absolute += absf(delta)
			if delta > 0.025:
				darkened += 1
	return {"mean": total / float(a.get_width() * a.get_height()), "absolute": absolute / float(a.get_width() * a.get_height()), "darkened_pixels": darkened}

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("LIGHTING GPU probe requires an actual graphics renderer")
		quit(1)
		return
	_output = OS.get_cache_dir().path_join("blockfield-world-lighting")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(640, 480)
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 480)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	world.water_enabled = false
	_viewport.add_child(world)
	world._fill_box(Vector3i(2, 0, 2), Vector3i(14, 2, 14), 0x01806040)
	world._fill_box(Vector3i(7, 2, 7), Vector3i(9, 7, 9), 0x01a9bed0)
	world._mark_all_chunks()
	world.rebuild_now()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.015, 0.015)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.0
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.position = Vector3(19, 17, 23)
	world.add_child(camera)
	camera.look_at(Vector3(8, 2, 8))
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.0
	sun.visible = false
	sun.shadow_normal_bias = 0.8
	sun.shadow_bias = 0.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 50.0
	world.add_child(sun)
	var omni := OmniLight3D.new()
	omni.position = Vector3(11, 9, 12)
	omni.omni_range = 25.0
	omni.light_energy = 3.0
	omni.visible = false
	world.add_child(omni)
	var spot := SpotLight3D.new()
	spot.position = Vector3(11, 10, 13)
	spot.spot_range = 25.0
	spot.spot_angle = 40.0
	spot.light_energy = 3.0
	spot.visible = false
	world.add_child(spot)
	spot.look_at(Vector3(8, 2, 8))
	var dark: Image = await capture("01-dark")
	omni.visible = true
	var point_lit: Image = await capture("02-omni")
	check(mean_brightness(point_lit) > mean_brightness(dark) + 0.025, "omni light must visibly illuminate real voxel geometry")
	world.set_ambient_occlusion_enabled(false)
	var point_no_ao: Image = await capture("03-omni-ao-off")
	var direct_ao := difference(point_lit, point_no_ao)
	check(direct_ao.absolute < 0.001, "native detail AO must affect ambient, leaving direct lights unchanged")
	omni.visible = false
	spot.visible = true
	var spot_lit: Image = await capture("04-spot")
	check(mean_brightness(spot_lit) > mean_brightness(dark) + 0.01, "spot flashlight must visibly illuminate real voxel geometry")
	spot.visible = false
	environment.ambient_light_energy = 0.8
	var ambient_open: Image = await capture("05-ambient-ao-off")
	world.set_ambient_occlusion_enabled(true)
	var ambient_ao: Image = await capture("06-ambient-ao-on")
	var ambient_difference := difference(ambient_open, ambient_ao)
	check(ambient_difference.darkened_pixels > 50 and ambient_difference.mean > 0.0002, "AO must visibly darken ambient-lit contact corners")
	environment.ambient_light_energy = 0.1
	sun.visible = true
	sun.shadow_enabled = false
	await capture("07-sun-shadows-off")
	sun.shadow_enabled = true
	world._chunks[Vector3i.ZERO].mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var no_casters: Image = await capture("08-sun-no-casters")
	world._chunks[Vector3i.ZERO].mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var shadows: Image = await capture("09-sun-casters")
	var shadow_difference := difference(no_casters, shadows)
	check(shadow_difference.darkened_pixels > 100 and shadow_difference.mean > 0.0005, "voxel pillar must cast a visible directional shadow onto terrain")
	var shadow_point := Vector2i(camera.unproject_position(Vector3(10.0, 2.002, 5.0)))
	var unblocked := no_casters.get_pixel(shadow_point.x, shadow_point.y)
	var blocked := shadows.get_pixel(shadow_point.x, shadow_point.y)
	check((unblocked.r + unblocked.g + unblocked.b - blocked.r - blocked.g - blocked.b) / 3.0 > 0.04, "known floor point in pillar shadow must darken while the same shadow rendering path stays active")
	sun.visible = false
	environment.ambient_light_energy = 0.0
	world.set_lighting_enabled(false)
	world.set_ambient_occlusion_enabled(false)
	var fullbright: Image = await capture("10-fullbright-palette")
	var point := Vector2i(camera.unproject_position(Vector3(5.5, 2.002, 10.5)))
	var color := fullbright.get_pixel(point.x, point.y)
	check(absf(color.r - 128.0 / 255.0) < 0.012 and absf(color.g - 96.0 / 255.0) < 0.012 and absf(color.b - 64.0 / 255.0) < 0.012, "fullbright fallback must preserve original palette at a real rendered pixel")
	var metrics := {"renderer": RenderingServer.get_video_adapter_name(), "dark": mean_brightness(dark), "omni": mean_brightness(point_lit), "spot": mean_brightness(spot_lit), "direct_ao_difference": direct_ao, "ambient_ao_difference": ambient_difference, "shadow_difference": shadow_difference, "palette_pixel": [color.r, color.g, color.b], "assertions": assertions, "failures": failures}
	var report := FileAccess.open(_output.path_join("metrics.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(metrics, "  "))
	print("LIGHTING GPU TESTS: %d assertions, %d failures; %s" % [assertions, failures, _output])
	print(JSON.stringify(metrics))
	_viewport.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
