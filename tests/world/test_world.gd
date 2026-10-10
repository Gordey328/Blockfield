extends SceneTree
## Run: godot --headless --path game --script ../tests/world/test_world.gd

const WORLD = preload("res://world/voxel_world.gd")
const READER = preload("res://world/vxl_reader.gd")
var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("WORLD TEST: " + message)

func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32, 32, 32))
	root.add_child(world)
	var black := WORLD.pack_color(Color.BLACK)
	check(black == 0x01000000, "solid black must not become air")
	world.set_block(Vector3i(15, 5, 8), black)
	world.set_block(Vector3i(16, 5, 8), 0x01ff8040)
	world.rebuild_now()
	check(world.get_stats().faces == 10, "adjacent blocks across a chunk border must hide both internal faces")
	world.set_block(Vector3i(15, 5, 8), 0x01aabbcc)
	check(world.get_stats().dirty_chunks == 2, "border edit must dirty only its chunk and the touched neighbor")
	world.rebuild_now()
	world.set_block(Vector3i(14, 5, 8), black)
	check(world.get_stats().dirty_chunks == 1, "interior edit must dirty only its own chunk")
	world.rebuild_now()
	check(world.get_stats().faces == 14, "rebuild must hide new adjacent block faces without affecting other chunks")
	var ray := world.cast_voxel(Vector3(15.5, 10, 8.5), Vector3.DOWN, 20)
	check(ray.hit and ray.cell == Vector3i(15, 5, 8), "DDA must hit the first solid cell")
	check(ray.normal == Vector3i.UP and ray.position.is_equal_approx(Vector3(15.5, 6, 8.5)), "DDA top hit must have correct face normal and position")
	check(not world.cast_voxel(Vector3(15.5, 10, 8.5), Vector3.UP, 20).hit, "DDA must return miss away from blocks")
	check(not world.cast_voxel(Vector3.ZERO, Vector3.ZERO, 10).hit, "zero direction must terminate without a hit")
	var side_ray := world.cast_voxel(Vector3(-5, 5.5, 8.5), Vector3.RIGHT, 30)
	check(side_ray.hit and side_ray.normal == Vector3i.LEFT, "DDA from outside map bounds must enter correctly")
	world.clear_world(Vector3i(32, 32, 32))
	world._fill_box(Vector3i(4, 0, 4), Vector3i(9, 2, 5), 0x01775544)
	for y in range(2, 5):
		world.set_block(Vector3i(4, y, 4), black)
		world.set_block(Vector3i(8, y, 4), black)
	for x in range(4, 9):
		world.set_block(Vector3i(x, 5, 4), black)
	world.set_block(Vector3i(4, 2, 4), 0)
	check(world.get_block(Vector3i(6, 5, 4)) != 0, "bridge with one surviving support must remain")
	world.set_block(Vector3i(8, 2, 4), 0)
	check(world.get_block(Vector3i(6, 5, 4)) == 0, "bridge must collapse after final support is severed")
	check(world.get_block(Vector3i(4, 1, 4)) != 0, "supported lower terrain must survive collapse")
	world.explode(Vector3(6.5, 0.5, 4.5), 3)
	check(world.get_block(Vector3i(6, 0, 4)) != 0 and world.get_block(Vector3i(6, 1, 4)) != 0, "explosions must preserve bottom two map layers")
	world.clear_world(Vector3i(32, 32, 32))
	world._fill_box(Vector3i(4, 0, 4), Vector3i(9, 2, 9), black)
	world.set_block(Vector3i(6, 2, 6), black)
	world.rebuild_now()
	var actor := CharacterBody3D.new()
	var actor_collision := CollisionShape3D.new()
	var actor_shape := BoxShape3D.new()
	actor_shape.size = Vector3.ONE * 0.5
	actor_collision.shape = actor_shape
	actor.add_child(actor_collision)
	root.add_child(actor)
	actor.position = Vector3(6.5, 5.0, 6.5)
	for frame in range(90):
		await physics_frame
		actor.velocity = Vector3(0, -5, 0)
		actor.move_and_slide()
	check(actor.is_on_floor() and absf(actor.position.y - 3.25) < 0.05, "generated chunk collision must support a player body on the block top")
	world.set_block(Vector3i(6, 2, 6), 0)
	world.rebuild_now()
	for frame in range(40):
		await physics_frame
		actor.velocity = Vector3(0, -5, 0)
		actor.move_and_slide()
	check(actor.is_on_floor() and absf(actor.position.y - 2.25) < 0.05, "block removal must replace collision and allow a player to fall onto the new floor")
	actor.free()
	world.clear_world(Vector3i(16, 16, 16))
	world._fill_box(Vector3i(1, 0, 1), Vector3i(8, 8, 8), black)
	var explosion_counts: Array[int] = [0]
	var explosion_listener := func(changes: Array) -> void: explosion_counts[0] = changes.size()
	world.blocks_changed.connect(explosion_listener)
	world.explode(Vector3(4.5, 4.5, 4.5), 999.0)
	check(explosion_counts[0] == 27, "native grenade must remove exactly a 3-cube neighborhood independent of player-damage radius")
	check(world.get_block(Vector3i(3, 3, 3)) == 0 and world.get_block(Vector3i(5, 5, 5)) == 0 and world.get_block(Vector3i(2, 4, 4)) != 0, "native grenade must include cube corners and preserve the neighboring wall")
	world.blocks_changed.disconnect(explosion_listener)
	var floor_span := PackedByteArray([0, 62, 62, 0, 1, 2, 3, 255])
	var fixture := PackedByteArray()
	fixture.resize(512 * 512 * floor_span.size())
	for column in range(512 * 512):
		for byte_index in range(floor_span.size()):
			fixture[column * floor_span.size() + byte_index] = floor_span[byte_index]
	var decoded: Dictionary = READER.decode(fixture)
	check(decoded.error == OK, "full-sized VXL fixture must decode")
	if decoded.error == OK:
		var data: PackedInt32Array = decoded.blocks
		check(data[0] == 0x01030201 and data[1] == 0x01030201, "VXL BGR colors and immutable bottom duplication must match source")
		check(data[2] == 0 and data[64 * (511 + 512 * 511) + 1] == 0x01030201, "VXL axis conversion must preserve the last column and empty sky")
		check(decoded.consumed == fixture.size(), "VXL decoder must consume all column spans")
	check(READER.decode(fixture.slice(0, fixture.size() - 1)).error == ERR_FILE_CORRUPT, "truncated VXL must be rejected")
	var layered_span := PackedByteArray([3, 10, 10, 0, 7, 8, 9, 255, 10, 11, 12, 255, 0, 62, 62, 20, 1, 2, 3, 255])
	var layered := PackedByteArray()
	layered.resize(512 * 512 * layered_span.size())
	for column in range(512 * 512):
		for byte_index in range(layered_span.size()):
			layered[column * layered_span.size() + byte_index] = layered_span[byte_index]
	var layers: Dictionary = READER.decode(layered)
	check(layers.error == OK, "VXL with interior, lower surface and air gap must decode")
	if layers.error == OK:
		var data: PackedInt32Array = layers.blocks
		check(data[53] == 0x01090807 and data[44] == 0x010c0b0a, "VXL top and bottom surface colors must map to the correct heights")
		check(data[50] != 0 and data[43] == 0 and data[2] == 0, "VXL hidden solid interior and next air gap must be preserved")
	var source_path := "res://assets/openspades/maps/Title.vxl"
	check(FileAccess.file_exists(source_path), "committed Title.vxl fixture must be available without source cache")
	if FileAccess.file_exists(source_path):
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		var original: Dictionary = READER.decode(source_file.get_buffer(source_file.get_length()))
		check(original.error == OK, "pinned OpenSpades Title.vxl must import")
		if original.error == OK:
			check(original.consumed == source_file.get_length(), "original Title.vxl parser must consume entire file")
			var original_data: PackedInt32Array = original.blocks
			check(original_data.size() - original_data.count(0) == 3778939, "original Title.vxl occupancy must equal source decoder golden count")
	world.free()
	print("WORLD TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
