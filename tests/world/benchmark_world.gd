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
	var edit_total := 0
	var edit_maximum := 0
	for repeat in range(20):
		world.set_block(Vector3i(36, 5, 18), 0x01aabbcc if repeat % 2 == 0 else 0x01b58a62)
		var edit_started := Time.get_ticks_usec()
		world.rebuild_now()
		var duration := Time.get_ticks_usec() - edit_started
		edit_total += duration
		edit_maximum = maxi(edit_maximum, duration)
	print("LAB SINGLE-CHUNK PAINT: ", {"average_usec": float(edit_total) / 20.0, "maximum_usec": edit_maximum})
	var removal_started := Time.get_ticks_usec()
	world.set_block(Vector3i(36, 5, 18), 0)
	var removal_chunks: int = world.get_stats().dirty_chunks
	world.rebuild_now()
	print("LAB DESTRUCTIVE EDIT: ", {"chunks": removal_chunks, "microseconds": Time.get_ticks_usec() - removal_started})
	world.set_block(Vector3i(15, 15, 15), 0x014488cc)
	var dirty: int = world.get_stats().dirty_chunks
	var corner_started := Time.get_ticks_usec()
	world.rebuild_now()
	print("LAB AO CORNER REBUILD: ", {"chunks": dirty, "microseconds": Time.get_ticks_usec() - corner_started})
	world.generate_lab()
	started = Time.get_ticks_msec()
	var lab_bytes := world.encode_vxl()
	print("LAB SAVE BASELINE: ", {"milliseconds": Time.get_ticks_msec() - started, "bytes": lab_bytes.size()})
	var map_path := "res://assets/openspades/maps/Title.vxl"
	started = Time.get_ticks_msec()
	var error: Error = world.load_vxl(map_path)
	print("VXL BASELINE: ", {"error": error, "milliseconds": Time.get_ticks_msec() - started, "spawn": world.get_spawn_position(), "stats": world.get_stats()})
	started = Time.get_ticks_msec()
	var topdown: Image = world.get_topdown_image()
	print("VXL TOPDOWN CACHE: ", {"milliseconds": Time.get_ticks_msec() - started, "pixels": topdown.get_size()})
	var cached_started := Time.get_ticks_usec()
	for repeat in range(100):
		world.get_topdown_image()
	print("VXL CACHED TOPDOWN QUERIES: ", {"100_queries_usec": Time.get_ticks_usec() - cached_started})
	started = Time.get_ticks_msec()
	world.set_draw_distance(128.0)
	world.rebuild_now()
	print("VXL NATIVE DRAW DISTANCE: ", {"milliseconds": Time.get_ticks_msec() - started, "distance": world.get_draw_distance(), "stats": world.get_stats()})
	started = Time.get_ticks_msec()
	var native_bytes := world.encode_vxl()
	print("VXL SAVE BASELINE: ", {"milliseconds": Time.get_ticks_msec() - started, "bytes": native_bytes.size()})
	world.free()
	quit(1 if error != OK else 0)
