extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(96,32,96))
	root.add_child(world)
	world.generate_lab()
	var started := Time.get_ticks_usec()
	world.set_irradiance_enabled(true)
	var setup_usec := Time.get_ticks_usec() - started
	for iteration in range(120):
		world._irradiance.update()
	print(JSON.stringify({"map":"lab","setup_usec":setup_usec,"stats":world.get_irradiance_stats()}))
	world.load_vxl("res://assets/openspades/maps/Title.vxl")
	started = Time.get_ticks_usec()
	world._ensure_irradiance()
	setup_usec = Time.get_ticks_usec() - started
	for iteration in range(120):
		world._irradiance.update()
	print(JSON.stringify({"map":"Title.vxl","setup_usec":setup_usec,"stats":world.get_irradiance_stats()}))
	world.free()
	await process_frame
	quit()
