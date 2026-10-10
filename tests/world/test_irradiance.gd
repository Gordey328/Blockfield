extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
const GI = preload("res://world/voxel_irradiance.gd")
var assertions := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("IRRADIANCE DATA: " + message)
func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	world.water_enabled = false
	root.add_child(world)
	world._fill_box(Vector3i.ZERO, Vector3i(16, 2, 16), 0x01ffffff)
	check(not world.irradiance_enabled and world.get_irradiance_stats().probes == 0, "GI must default off without allocating probes")
	var cache := GI.new(world)
	cache.configure(Vector3(8, 5, 8))
	var native: Array[Vector3] = cache.evaluate(Vector3(8.5, 2.5, 8.5))
	check(absf(native[0].x - 0.3339796582165259) < 0.00001, "native white-plane radiosity base coefficient golden")
	check(absf(native[2].x + 0.18440597134994408) < 0.00001 and absf(native[1].x) < 0.000001, "native directional coefficient must map Z-down to Y-up")
	check(native[0].is_equal_approx(Vector3.ONE * native[0].x), "white palette must remain spectrally neutral")
	world.set_block(Vector3i(8,15,8),0x01000000)
	cache._shadow.clear()
	check(cache._shadow_pixel(8,8) == 0, "opaque black at native sky depth zero must be a real hit, not air/floor fallback")
	world.set_block(Vector3i(8,15,8),0)
	cache._shadow.clear()
	check(cache.get_stats().probes == 125 and cache.get_stats().texture_bytes == 3000, "small maps must allocate bounded four RGB16F volumes")
	cache.probe_budget = 3
	cache.update()
	check(cache.get_stats().computed_probes <= 3 and cache.get_stats().dirty_probes > 0, "incremental update must honor hard probe-count cap")
	cache.flush()
	check(cache.get_stats().dirty_probes == 0 and cache.get_stats().uploads > 0, "flush must update actual textures after completing probes")
	var positive := cache.sample(Vector3(8.5, 2.5, 8.5), Vector3.UP)
	check(positive.x > 0.01 and positive.is_finite(), "sampled coefficients must produce nonzero actual bounce")
	check(cache.sample(Vector3(-100, 4, 4), Vector3.UP) == Vector3.ZERO, "outside-volume radiance must be zero")
	world.set_irradiance_enabled(true)
	world._irradiance.flush()
	var before: Color = world.get_irradiance_at(Vector3(8.5, 4.5, 8.5), Vector3.FORWARD)
	world.set_irradiance_light(Color(1, 0.5, 0.25), 2.0)
	var colored: Color = world.get_irradiance_at(Vector3(8.5, 4.5, 8.5), Vector3.FORWARD)
	check(absf(colored.r - before.r * 2) < 0.000001 and absf(colored.b - before.b * 0.5) < 0.000001, "explicit Sun color/energy must scale real bounce")
	world.set_block(Vector3i(8, 1, 8), 0x01ff0000)
	check(world.get_irradiance_stats().dirty_probes > 0, "palette repaint must invalidate nearby irradiance probes")
	world._irradiance.flush()
	var after: Array[Vector3] = world._irradiance.evaluate(Vector3(8.5, 2.5, 8.5))
	check(after[0].x > after[0].y and after[0].x > after[0].z, "repainted source surface must transfer its palette into bounce")
	world.set_block(Vector3i(8, 1, 8), 0)
	check(world.get_irradiance_stats().dirty_probes > 0, "block removal must invalidate irradiance and sun-shadow columns")
	world.set_irradiance_enabled(false)
	check(world.get_irradiance_at(Vector3(8, 4, 8), Vector3.UP) == Color(0,0,0) and not world._material.get_shader_parameter("irradiance_enabled"), "GI off must disable the actual shader and query contribution")
	world.clear_world(Vector3i(512, 64, 512))
	world._fill_box(Vector3i(200,0,200),Vector3i(350,2,310),0x01ffffff)
	world.set_effects_observer(Vector3(250, 10, 250))
	world.set_irradiance_enabled(true)
	var stats := world.get_irradiance_stats()
	check(stats.probes == 18513 and stats.texture_bytes == 444312 and stats.coefficient_bytes == 888624, "native maps must cap probes at 33×17×33, not native per-voxel storage")
	var old_origin: Vector3 = stats.origin
	world._irradiance.probe_budget = 1
	world._irradiance.update()
	var warmed: Color = world.get_irradiance_at(Vector3(248.5,8.5,248.5),Vector3.UP)
	world.set_effects_observer(Vector3(266, 10, 250))
	check(world.get_irradiance_stats().origin.x > old_origin.x and world.get_irradiance_stats().probes == 18513, "observer movement must recenter fixed-size volume")
	var reused: Color = world.get_irradiance_at(Vector3(248.5,8.5,248.5),Vector3.UP)
	check(world.get_irradiance_stats().reused_probes > 0 and warmed.r > 0 and absf(warmed.r - reused.r) < 0.000001, "moving volume must retain overlapping completed probes and their CPU coefficients")
	world.free()
	await process_frame
	print("IRRADIANCE DATA TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
