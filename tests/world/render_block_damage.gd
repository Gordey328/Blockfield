extends SceneTree
## Actual Compatibility pixels supplement exact mesh-byte checks. No health timers.
## godot --path game --rendering-method gl_compatibility --script ../tests/world/render_block_damage.gd -- --output=<absolute directory>
const WORLD = preload("res://world/voxel_world.gd")
const CELL := Vector3i(1, 1, 1)
var assertions: int = 0
var failures: int = 0
var _output: String = ""
var _viewport: SubViewport

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BLOCK DAMAGE GPU: " + message)

func capture(label: String) -> Image:
	for frame: int in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.save_png(_output.path_join(label + ".png"))
	return image

func difference(a: Image, b: Image) -> Dictionary:
	var total: float = 0.0
	var pixels: int = 0
	for y: int in range(a.get_height()):
		for x: int in range(a.get_width()):
			var before: Color = a.get_pixel(x, y)
			var after: Color = b.get_pixel(x, y)
			var delta: float = (absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b)) / 3.0
			total += delta
			if delta > 0.025:
				pixels += 1
	return {"mean_absolute": total / float(a.get_width() * a.get_height()), "changed_pixels": pixels}

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BLOCK DAMAGE GPU probe requires an actual graphics renderer")
		quit(1)
		return
	_output = OS.get_cache_dir().path_join("blockfield-block-damage")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(_output)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(320, 240)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world := WORLD.new()
	world.clear_world(Vector3i(4, 4, 4))
	world.water_enabled = false
	world.visual_effects_enabled = false
	_viewport.add_child(world)
	world.set_process(false)
	world.set_lighting_enabled(false)
	world.set_ambient_occlusion_enabled(false)
	world.set_block(CELL, 0x01ff8041)
	world.rebuild_now()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.0
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(4, 3, 5)
	world.add_child(camera)
	camera.look_at(Vector3(CELL) + Vector3.ONE * 0.5)
	camera.current = true
	var healthy: Image = await capture("01-healthy")
	var chunk: Node3D = world._chunks[Vector3i.ZERO]
	var collider: Shape3D = chunk.collision.shape
	world.set_block_damaged(CELL, true)
	world.rebuild_now()
	var damaged: Image = await capture("02-damaged")
	world.set_block_damaged(CELL, false)
	world.rebuild_now()
	var recovered: Image = await capture("03-recovered")
	var changed: Dictionary = difference(healthy, damaged)
	var restored: Dictionary = difference(healthy, recovered)
	var healthy_pixel: Color = healthy.get_pixel(160, 120)
	var damaged_pixel: Color = damaged.get_pixel(160, 120)
	check(healthy_pixel.r > 0.5 and healthy_pixel.g > 0.1, "actual mesh is visible at camera target")
	check(damaged_pixel.r < healthy_pixel.r - 0.1 and damaged_pixel.g < healthy_pixel.g - 0.05, "source damaged RGB visibly darkens the surviving block")
	check(changed.changed_pixels > 500 and changed.mean_absolute > 0.01, "darkening reaches the rendered cube faces")
	check(restored.changed_pixels == 0 and restored.mean_absolute < 0.001, "clearing presentation damage restores actual rendered appearance")
	check(world.get_block(CELL) == 0x01ff8041 and chunk.collision.shape == collider, "rendered damage/recovery preserve source RGB and collider")
	var report := {"assertions": assertions, "failures": failures, "damage_difference": changed, "recovery_difference": restored, "healthy_center": [healthy_pixel.r, healthy_pixel.g, healthy_pixel.b], "damaged_center": [damaged_pixel.r, damaged_pixel.g, damaged_pixel.b]}
	var file := FileAccess.open(_output.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("BLOCK DAMAGE GPU: %d assertions, %d failures; %s" % [assertions, failures, JSON.stringify(report)])
	_viewport.queue_free()
	await process_frame
	quit(1 if failures else 0)
