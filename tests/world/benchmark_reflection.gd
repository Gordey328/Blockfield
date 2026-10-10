extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
var world: Node3D
func _initialize() -> void:
	call_deferred("_run")
func measure(label: String) -> Dictionary:
	var reflection: Node = world._reflection
	reflection.set_process(false)
	var measurements: Array[int] = []
	for frame in range(20):
		var started := Time.get_ticks_usec()
		reflection.update_now()
		measurements.append(Time.get_ticks_usec() - started)
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	measurements.sort()
	return {"map":label,"prepare_min_usec":measurements.front(),"prepare_median_usec":measurements[10],"prepare_max_usec":measurements.back(),"stats":world.get_reflection_stats()}
func _run() -> void:
	var scene := SubViewport.new()
	scene.size = Vector2i(640, 480)
	scene.own_world_3d = true
	scene.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(scene)
	world = WORLD.new()
	scene.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.55
	var env := WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 180, 0)
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(48, 8, 85)
	camera.look_at(Vector3(48, 4, 45))
	camera.current = true
	world.set_reflection_camera(camera)
	world.set_water_reflections_enabled(true)
	var lab: Dictionary = await measure("lab")
	world.load_vxl("res://assets/openspades/maps/Title.vxl")
	camera.position = world.get_spawn_position() + Vector3(0, 3, 16)
	camera.look_at(camera.position + Vector3(0, -0.1, -1))
	var native: Dictionary = await measure("Title.vxl")
	print("REFLECTION BENCHMARK: " + JSON.stringify({"renderer":RenderingServer.get_video_adapter_name(), "lab":lab,"native":native}))
	scene.queue_free()
	await process_frame
	await process_frame
	quit()
