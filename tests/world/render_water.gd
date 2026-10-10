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
		push_error("WATER GPU: " + message)
func capture(label: String) -> Image:
	for frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
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
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = OS.get_cache_dir().path_join("blockfield-water")
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
	world.water_level = 2.2
	viewport.add_child(world)
	for z in range(16):
		for x in range(16):
			world._fill_box(Vector3i(x, 0, z), Vector3i(x + 1, 2, z + 1), 0x01806040 if (x + z) % 2 == 0 else 0x01205090)
	world._fill_box(Vector3i(7, 2, 7), Vector3i(9, 6, 9), 0x01e02010)
	world._mark_all_chunks()
	world.rebuild_now()
	world._create_water()
	world._wave_field.animated = false
	world._wave_field.set_time(0.7)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.02)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	var camera := Camera3D.new()
	camera.position = Vector3(19, 13, 24)
	world.add_child(camera)
	camera.look_at(Vector3(8, 1.5, 8))
	camera.current = true
	var omni := OmniLight3D.new()
	omni.position = Vector3(8, 10, 11)
	omni.omni_range = 25.0
	omni.light_energy = 3.0
	omni.visible = false
	world.add_child(omni)
	var original: Image = await capture("01-waves-refraction")
	var wave_image: Image = world._wave_field.get_texture().get_image()
	wave_image.save_png(output.path_join("wave-field.png"))
	var cpu: Vector3 = world._wave_field.sample_cpu(Vector2(24.5, 52.5) / 128.0, 0.7)
	var encoded := Color(clampf(cpu.x * 100 + 0.5, 0, 1), clampf(cpu.y * 100 + 0.5, 0, 1), 1, clampf(-cpu.z * 5 + 0.5, 0, 1))
	var gpu := wave_image.get_pixel(24, 52)
	check(absf(gpu.r - encoded.r) < 0.012 and absf(gpu.g - encoded.g) < 0.012 and absf(gpu.a - encoded.a) < 0.012, "GPU spectral normal/height must match source-shaped CPU numeric evaluation")
	world.set_water_refraction_enabled(false)
	var no_refraction: Image = await capture("02-refraction-off")
	var refraction_diff := difference(original, no_refraction)
	check(refraction_diff > 0.0001, "real screen refraction must change submerged checker geometry")
	world.set_water_refraction_enabled(true)
	world.set_water_waves_enabled(false)
	var flat: Image = await capture("03-waves-off")
	var waves_diff := difference(original, flat)
	check(waves_diff > 0.00001, "bounded spectral normals must visibly change water")
	world.set_water_waves_enabled(true)
	world._wave_field.set_time(1.7)
	var animated: Image = await capture("04-wave-animation")
	var animation_diff := difference(original, animated)
	check(animation_diff > 0.00001, "native phase advance must visibly animate water")
	omni.visible = true
	var lit: Image = await capture("05-omni-light")
	check(difference(animated, lit) > 0.001, "water must respond to actual dynamic lighting")
	var above_point := Vector2i(camera.unproject_position(Vector3(8.5, 4.5, 9.002)))
	var above_original := original.get_pixelv(above_point)
	var above_plain := no_refraction.get_pixelv(above_point)
	check(absf(above_original.r - above_plain.r) + absf(above_original.g - above_plain.g) + absf(above_original.b - above_plain.b) < 0.01, "above-water opaque object must retain its image across refraction toggle")
	world.set_water_fog(Color(0.2, 0.9, 0.3), 16.0)
	var fog_on: Image = await capture("06-water-fog-on")
	world.set_water_fog_enabled(false)
	var fog_off: Image = await capture("07-water-fog-off")
	var fog_diff := difference(fog_on, fog_off)
	check(fog_diff > 0.01, "water fog toggle must visibly remove channel-dependent surface haze")
	var above_fog_on := fog_on.get_pixelv(above_point)
	var above_fog_off := fog_off.get_pixelv(above_point)
	check(above_fog_on.is_equal_approx(above_fog_off), "water fog toggle must preserve above-water opaque geometry")
	world.set_water_enabled(false)
	var dry: Image = await capture("08-water-off")
	check(difference(original, dry) > 0.001, "water plane must blend depth-dependent shoreline and floor color")
	var metrics := {"renderer":RenderingServer.get_video_adapter_name(), "wave_cpu":[cpu.x,cpu.y,cpu.z], "wave_gpu":[gpu.r,gpu.g,gpu.b,gpu.a], "refraction_difference":refraction_diff, "waves_difference":waves_diff, "animation_difference":animation_diff, "fog_difference":fog_diff, "assertions":assertions,"failures":failures}
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	print("WATER GPU TESTS: %d assertions, %d failures; %s" % [assertions,failures,output])
	print(JSON.stringify(metrics))
	viewport.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
