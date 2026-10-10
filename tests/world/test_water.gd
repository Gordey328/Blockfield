extends SceneTree
const WAVES = preload("res://world/spectral_wave.gd")
const WORLD = preload("res://world/voxel_world.gd")
var assertions := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("WATER DATA: " + message)
func _run() -> void:
	check(WAVES.magnitude(0) == 0.0, "DC mode must have no energy")
	check(absf(WAVES.magnitude(1) - 0.006245424039423049) < 0.00000001, "native 128² lowest frequency magnitude golden")
	check(absf(WAVES.angular_speed(1) - 1.4629180792671596) < 0.00000001, "native uint32 phase speed golden")
	check(WAVES.magnitude(1) > WAVES.magnitude(2) * 3.9 and WAVES.magnitude(64) < WAVES.magnitude(1) / 4000.0, "source inverse-square/Gaussian spectrum must suppress fine frequencies")
	var waves := WAVES.new()
	root.add_child(waves)
	waves.setup(3, 1337)
	waves.animated = false
	check(waves.coefficients(0, 0).size() == 32 and waves.get_stats().texture_bytes == 196608, "three bounded layers must use 32 modes and 192 KiB RGBA8 targets")
	var uv := Vector2(0.137, 0.413)
	var value := waves.sample_cpu(uv, 0.7)
	check(value.is_finite() and absf(value.z) < 0.15, "bounded source wave must remain finite and within plausible height")
	check(value.distance_to(waves.sample_cpu(uv + Vector2.ONE, 0.7)) < 0.000001, "wave texture must tile periodically on both axes")
	var step := 1.0 / 128.0
	var dx := waves.sample_cpu(uv + Vector2(step, 0), 0.7).z - waves.sample_cpu(uv - Vector2(step, 0), 0.7).z
	var dy := waves.sample_cpu(uv + Vector2(0, step), 0.7).z - waves.sample_cpu(uv - Vector2(0, step), 0.7).z
	check(absf(value.x - dx) < 0.000001 and absf(value.y - dy) < 0.000001, "packed normals must follow native central differences, not analytic derivative approximation")
	check(value.distance_to(waves.sample_cpu(uv, 1.7)) > 0.0001, "source phase advance must animate real wave height")
	check(value.distance_to(waves.sample_cpu(uv, 0.7, 1)) > 0.0001, "native medium layers must carry independent random spectra")
	waves.set_enabled(false)
	check(not waves.is_processing() and waves._viewports[0].render_target_update_mode == SubViewport.UPDATE_DISABLED, "disabled waves must stop CPU and GPU work")
	waves.free()
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	root.add_child(world)
	world.set_water_fog_enabled(false)
	world._create_water()
	world.set_water_refraction_enabled(false)
	world.set_water_waves_enabled(false)
	var material: ShaderMaterial = world._water_mesh.mesh.surface_get_material(0)
	check(not material.get_shader_parameter("fog_enabled"), "fog setting chosen before water creation must reach actual shader")
	world.set_water_fog_enabled(true)
	check(material.get_shader_parameter("fog_enabled"), "enabling water fog must update the existing material")
	world.set_water_fog_enabled(false)
	world.reload_resources()
	check(not world.water_fog_enabled and not material.get_shader_parameter("fog_enabled"), "resource refresh must retain disabled water fog")
	check(not material.get_shader_parameter("refraction_enabled") and not material.get_shader_parameter("waves_enabled"), "water feature toggles must update actual shader")
	world.set_lighting_enabled(false)
	check(not material.get_shader_parameter("lighting_enabled"), "fullbright setting must also update water lighting")
	world.clear_world(Vector3i(16, 16, 16))
	check(world._wave_field == null and world._water_mesh == null, "world reset must remove wave render targets and water")
	world._create_water()
	check(not world._water_mesh.mesh.surface_get_material(0).get_shader_parameter("fog_enabled"), "recreated map water must retain its fog setting")
	world.free()
	await process_frame
	print("WATER DATA TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
