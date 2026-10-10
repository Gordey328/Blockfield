extends SceneTree
## CPU baseline. Exported-browser frame time still requires browser verification.
const WORLD = preload("res://world/voxel_world.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	root.add_child(world)
	var started := Time.get_ticks_msec()
	world.generate_lab()
	print("LAB BASELINE: ", {"milliseconds": Time.get_ticks_msec() - started, "stats": world.get_stats()})
	started = Time.get_ticks_msec()
	var lab_bytes := world.encode_vxl()
	print("LAB SAVE BASELINE: ", {"milliseconds": Time.get_ticks_msec() - started, "bytes": lab_bytes.size()})
	var map_path := "res://assets/openspades/maps/Title.vxl"
	started = Time.get_ticks_msec()
	var error: Error = world.load_vxl(map_path)
	print("VXL BASELINE: ", {"error": error, "milliseconds": Time.get_ticks_msec() - started, "spawn": world.get_spawn_position(), "stats": world.get_stats()})
	started = Time.get_ticks_msec()
	var native_bytes := world.encode_vxl()
	print("VXL SAVE BASELINE: ", {"milliseconds": Time.get_ticks_msec() - started, "bytes": native_bytes.size()})
	world.free()
	quit(1 if error != OK else 0)
