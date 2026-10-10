extends SceneTree
## Source GLFlatMapRenderer color/axis/cache/edit semantics.
const WORLD = preload("res://world/voxel_world.gd")
const READER = preload("res://world/vxl_reader.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TOPDOWN TEST: " + message)

func _run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(4, 8, 4))
	world.visual_effects_enabled = false
	world._fill_box(Vector3i.ZERO, Vector3i(4, 2, 4), 0x01604020)
	root.add_child(world)
	var image: Image = world.get_topdown_image()
	check(image.get_size() == Vector2i(4, 4), "map image must use full x/z dimensions")
	check(image.get_pixel(0, 0).is_equal_approx(WORLD.block_color(0x01604020)), "initial map must show highest native terrain color")
	check(world.get_topdown_image() == image, "unchanged query must return the same cached Image")
	world.set_block(Vector3i(1, 4, 3), 0x01000000)
	check(world.get_topdown_image() == image and image.get_pixel(1, 3).is_equal_approx(Color.BLACK), "new highest black cell must be opaque and use x/z pixel order")
	check(image.get_pixel(3, 1).is_equal_approx(WORLD.block_color(0x01604020)), "column edits must not transpose image axes")
	world.set_block(Vector3i(1, 4, 3), 0x01aabbcc)
	check(image == world.get_topdown_image() and image.get_pixel(1, 3).is_equal_approx(WORLD.block_color(0x01aabbcc)), "highest recolor must update the existing Image")
	world.set_block(Vector3i(1, 2, 3), 0x01ff0000)
	check(world._topdown_dirty.is_empty() and world.get_topdown_image() == image, "buried repaint must not dirty or scan a visible column")
	world.set_block(Vector3i(1, 4, 3), 0)
	world.get_topdown_image()
	check(image.get_pixel(1, 3).is_equal_approx(WORLD.block_color(0x01ff0000)), "highest removal must reveal the next surviving surface")
	var observed: Array[Color] = []
	var listener := func(_changes: Array) -> void: observed.append(world.get_topdown_image().get_pixel(2, 2))
	world.blocks_changed.connect(listener)
	world.set_block(Vector3i(2, 3, 2), 0x014488cc)
	check(observed.size() == 1 and observed[0].is_equal_approx(WORLD.block_color(0x014488cc)), "blocks_changed consumer must read the updated column immediately")
	world.blocks_changed.disconnect(listener)
	world.clear_world(Vector3i(8, 4, 8))
	var cleared: Image = world.get_topdown_image()
	check(cleared != image and cleared.get_size() == Vector2i(8, 8) and cleared.get_pixel(0, 0).a == 0.0, "world reset must replace dimensions/cache and empty columns are transparent")
	world.generate_lab()
	check(world.get_topdown_image().get_size() == Vector2i(96, 96), "lab map must be a full-resolution cache")
	var file := FileAccess.open("res://assets/openspades/maps/Title.vxl", FileAccess.READ)
	var decoded: Dictionary = READER.decode(file.get_buffer(file.get_length()))
	check(decoded.error == OK, "committed native map fixture must decode for source image comparison")
	if decoded.error == OK:
		world.clear_world(decoded.size)
		world._blocks = decoded.blocks
		var native: Image = world.get_topdown_image()
		var pixels: PackedByteArray = native.get_data()
		var matching := true
		var data: PackedInt32Array = decoded.blocks
		for column in range(512 * 512):
			var packed := 0
			for y in range(63, -1, -1):
				if data[column * 64 + y] != 0:
					packed = data[column * 64 + y]
					break
			var offset := column * 4
			if pixels[offset] != ((packed >> 16) & 255) or pixels[offset + 1] != ((packed >> 8) & 255) or pixels[offset + 2] != (packed & 255) or pixels[offset + 3] != 255:
				matching = false
				break
		check(native.get_size() == Vector2i(512, 512) and matching, "every original Title column must match source highest-color bitmap")
	world.free()
	print("TOPDOWN TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
