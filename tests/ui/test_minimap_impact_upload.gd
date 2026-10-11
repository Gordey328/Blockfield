extends SceneTree
## Actual LabMap/World path: buried firearm edits must not upload identical
## full-map textures, while progressive surface changes and reset still upload.
const WORLD = preload("res://world/voxel_world.gd")
const DATA = preload("res://world/voxel_data.gd")
const MAP = preload("res://ui/lab_map.gd")
const EARTH: int = 0x01604020
const RED: int = 0x01cc2211
var assertions: int = 0
var failures: int = 0

class NoRevisionWorld extends VoxelWorld:
	func get_visual_preparation_stats() -> Dictionary:
		return {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("MINIMAP IMPACT UPLOAD: " + message)

func make_map(size: Vector3i, epoch: int, color: int = EARTH) -> VoxelData:
	var data := DATA.new()
	data.clear(size, epoch)
	data.seed_box(Vector3i.ZERO, Vector3i(size.x, 5, size.z), color)
	return data

func run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(8, 8, 8))
	world.water_enabled = false
	world.visual_effects_enabled = false
	root.add_child(world)
	world.set_process(false)
	var initial := make_map(Vector3i(8, 8, 8), 20)
	initial.seed_box(Vector3i(6, 4, 6), Vector3i(7, 5, 7), RED)
	check(world.set_map_data(initial, "Initial", true) == OK, "initial map adopts before visual preparation")
	var map := MAP.new()
	map.hide()
	root.add_child(map)
	map.set_process(false)
	map.setup(world, null, null)
	map._process(0.3)
	check(map.get_terrain_upload_count() == 1 and map._dirty, "first transparent progressive image uploads and retains pending polling")
	map._process(0.3)
	check(map.get_terrain_upload_count() == 1 and map._dirty, "unchanged pending image polls without an identical upload")
	world.advance_visual_preparation(4, 1000000)
	map._process(0.3)
	check(map.get_terrain_upload_count() == 2 and map._dirty, "partial completed columns upload a new revision and retain pending polling")
	world.get_topdown_image()
	map._process(0.3)
	check(map.get_terrain_upload_count() == 3 and not map._dirty, "final revision uploads even when preparation finished between polls")
	var baseline: int = map.get_terrain_upload_count()
	var revision: int = world.get_visual_preparation_stats().topdown_revision
	for index: int in range(20):
		world.set_block(Vector3i(1 + index % 5, 2, 1 + index / 5), 0)
		map._process(0.3)
		check(map.get_terrain_upload_count() == baseline and not map._dirty, "buried destruction does not upload identical highest-surface pixels")
	check(world.get_visual_preparation_stats().topdown_revision == revision, "buried destruction keeps the completed image revision")
	world.set_block(Vector3i(6, 4, 6), 0)
	map._process(0.3)
	check(map.get_terrain_upload_count() == baseline and map._dirty, "visible destruction waits for pending surface work without uploading stale pixels")
	world.advance_visual_preparation(64, 1000000)
	map._process(0.3)
	check(map.get_terrain_upload_count() == baseline + 1 and not map._dirty, "visible destruction uploads the completed surface revision once")
	check(world.get_topdown_image_progressive().get_pixel(6, 6) == WORLD.block_color(EARTH), "removed surface reveals the intrinsic underlying color")
	baseline = map.get_terrain_upload_count()
	world.set_map_data(make_map(Vector3i(8, 8, 8), 21, RED), "Same-size reset", true)
	map._process(0.3)
	check(map.get_terrain_upload_count() == baseline + 1 and map._dirty, "same-size reset uploads its replacement image")
	revision = world.get_visual_preparation_stats().topdown_revision
	world.set_map_data(make_map(Vector3i(8, 8, 8), 22), "Same revision reset", true)
	map._process(0.3)
	check(world.get_visual_preparation_stats().topdown_revision == revision and map.get_terrain_upload_count() == baseline + 2, "image identity forces same-size reset upload even at an equal revision")
	world.get_topdown_image()
	map._process(0.3)
	check(map.get_terrain_upload_count() == baseline + 3 and not map._dirty, "replacement image final completion still uploads")
	baseline = map.get_terrain_upload_count()
	map.reload_resources()
	map._dirty = true
	map._process(0.3)
	check(map.get_terrain_upload_count() == baseline, "icon resource refresh preserves unchanged terrain texture")
	world.set_map_data(make_map(Vector3i(4, 8, 4), 23, RED), "Resized reset", true)
	map._process(0.3)
	check(map.get_terrain_upload_count() == baseline + 1 and map._texture.get_size() == Vector2(4, 4), "resized reset creates the correct texture dimensions")
	var follower := MAP.new()
	follower.hide()
	root.add_child(follower)
	follower.set_process(false)
	follower.setup(world, null, null, map)
	follower._process(0.3)
	check(follower.get_terrain_upload_count() == 0 and follower._texture == null, "large-map follower shares the primary texture without uploading")
	baseline = map.get_terrain_upload_count()
	map._upload_terrain(null)
	check(map.get_terrain_upload_count() == baseline, "null source leaves the usable texture untouched")
	var fallback := NoRevisionWorld.new()
	fallback.clear_world(Vector3i(4, 8, 4))
	map.world = fallback
	var fallback_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fallback_image.fill(Color.BLUE)
	map._upload_terrain(fallback_image)
	map._upload_terrain(fallback_image)
	check(map.get_terrain_upload_count() == baseline + 2, "missing revision keeps compatibility uploads for repeated mutable images")
	map.world = world
	fallback.free()
	follower.queue_free()
	map.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	print("MINIMAP IMPACT UPLOAD: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
