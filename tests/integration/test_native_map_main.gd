extends SceneTree
## Native map adoption uses actual Main, respawn/reset/cancellation and save rules.
const MAIN = preload("res://scenes/main.tscn")
const MAP = preload("res://world/blockfield_map.gd")
var checks: int = 0
var failures: int = 0
var app: Node3D

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("NATIVE MAP MAIN: "+label)

func frames(count: int) -> void:
	for index: int in count: await process_frame

func run() -> void:
	app = MAIN.instantiate()
	root.add_child(app)
	await frames(3)
	app.hud.set_menu_visible(true)
	var bundled_path: String = "res://assets/maps/csgo_mirage.bfmap"
	var paths: Array[String] = app.get_local_map_paths()
	check(paths.has(bundled_path),"published map is available through the normal menu catalog")
	check(not paths.has("res://assets/local_maps/csgo_mirage.bfmap"),"bundled map takes precedence over a duplicate local filename")
	var lab_data: VoxelData = app.world.data
	await app.load_local_map("res://assets/maps/../outside.bfmap")
	check(app.world.data == lab_data,"shortcut rejects paths outside the enumerated catalog")
	await app.load_local_map(bundled_path)
	check(app.world.dimensions == Vector3i(171,61,165) and app._map_baseline_name == "csgo_mirage.bfmap","bundled Mirage loads through actual Main shortcut")
	app.reset_lab()
	await frames(3)
	var source: VoxelData = VoxelData.new()
	source.clear(Vector3i(24,10,24))
	source.seed_box(Vector3i.ZERO,Vector3i(24,3,24),0x017d705f)
	source.seed_box(Vector3i(10,3,8),Vector3i(12,6,12),0x01cbb390)
	var metadata: Dictionary = {"format":1,"title":"Native fixture","dimensions":[24,10,24],
		"spawn":[6.5,3.01,6.5],"yaw_radians":0.75,"water_enabled":false}
	var bytes: PackedByteArray = MAP.encode(source,metadata)
	check(not bytes.is_empty(),"fixture encodes independent full-color data")
	app._upload_kind = "map"
	var before: VoxelData = app.world.data
	app._apply_upload(bytes,"fixture.bfmap")
	check(app.world.data == before,"loading yields before atomic adoption")
	app.reset_lab()
	await frames(3)
	check(app.world.data.dimensions == Vector3i(96,32,96) and app._map_baseline.is_empty(),"reset cancels native load without stale baseline")
	app.player.head.rotation.x = -0.8
	await app._apply_upload(bytes,"fixture.bin")
	check(app.world.dimensions == Vector3i(24,10,24),"signature selects native map without relying on extension")
	check(app.world.map_name == "Native fixture" and app._map_baseline_name == "fixture.bin","title and source reset baseline retained")
	check(app.world.get_spawn_position().is_equal_approx(Vector3(6.5,3.01,6.5)),"manifest feet spawn retained by World")
	check(app.player.global_position.is_equal_approx(app.world.get_spawn_position()),"actual player appears at manifest spawn")
	check(is_equal_approx(app.player.rotation.y,0.75) and is_zero_approx(app.player.head.rotation.x),"source view direction applied without retaining prior downward pitch")
	check(app.session.targets.is_empty(),"arbitrary imported geometry receives no misplaced test-ground roster")
	check(not app.world.water_enabled,"dry map metadata disables water presentation")
	app._apply_graphics()
	check(not app.world.water_enabled,"applying graphics preferences retains dry map override")
	var original_color: int = app.world.get_block(Vector3i(10,4,9))
	app.world.set_block(Vector3i(10,4,9),0x01000000)
	check(app.world.get_block(Vector3i(10,4,9)) == 0x01000000,"native black repaint remains solid")
	await app.reset_match()
	check(app.world.get_block(Vector3i(10,4,9)) == original_color,"reset restores imported full interior colors")
	check(app.player.global_position.is_equal_approx(Vector3(6.5,3.01,6.5)),"reset retains safe source spawn")
	app.world.set_block(Vector3i(6,2,6),0)
	app.player.respawn_at(Vector3(8.5,3.01,6.5))
	var saved_metadata: Dictionary = app._native_save_metadata()
	var saved_feet: Vector3 = Vector3(float(saved_metadata.spawn[0]),float(saved_metadata.spawn[1]),float(saved_metadata.spawn[2]))
	check(saved_feet.is_equal_approx(Vector3(8.5,3.01,6.5)) and not MAP.encode(app.world.data,saved_metadata).is_empty(),"edited map saves with current safe feet when original spawn support was destroyed")
	check(app._map_metadata.spawn == [6.5,3.01,6.5],"save spawn fallback does not alter original reset metadata")
	await app.reset_match()
	var installed: VoxelData = app.world.data
	var baseline: PackedByteArray = app._map_baseline.duplicate()
	await app._apply_upload(PackedByteArray([66,70,77,49]),"bad.bfmap")
	check(app.world.data == installed and app._map_baseline == baseline,"malformed package preserves installed world and reset baseline")
	check(not app._map_metadata.is_empty(),"failed import cannot clear native metadata")
	app.save_map()
	app.reset_lab()
	await frames(3)
	check(app._map_metadata.is_empty() and app._vxl_notice_caption.is_empty(),"lab reset cancels native save and clears map metadata")
	check(app.world.water_enabled == bool(app.graphics_options.water),"return to lab restores user's water graphics preference")
	check(app.session.targets.size() == 6,"return to lab restores the original roster")
	app.stop_audio()
	app.queue_free()
	await frames(4)
	print("NATIVE MAP MAIN TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
