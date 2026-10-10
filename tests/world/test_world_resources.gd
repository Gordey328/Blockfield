extends SceneTree
const WORLD = preload("res://world/voxel_world.gd")
const AO = preload("res://world/voxel_ao.gd")
const FALLING = preload("res://world/falling_cluster.gd")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
var assertions := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("WORLD RESOURCES: " + message)
func pack_bytes(image: Image) -> PackedByteArray:
	var texture := image.save_png_to_buffer()
	var manifest := {"version":1,"id":"world-textures","title":"World texture test","authors":["Blockfield test"],"license":"CC0 test image","assets":{}}
	for name in ["Gfx/AmbientOcclusion.png","Textures/Smoke1/000.png","Gfx/White.tga"]:
		manifest.assets[name] = {"type":"texture","file":"texture.png","sha256":EXTENSIONS._sha256(texture)}
	var path := OS.get_cache_dir().path_join("blockfield-world-resources-test.zip")
	var writer := ZIPPacker.new()
	writer.open(path)
	writer.start_file("blockfield-pack.json")
	writer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	writer.close_file()
	writer.start_file("texture.png")
	writer.write_file(texture)
	writer.close_file()
	writer.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes
func _run() -> void:
	EXTENSIONS.clear()
	AO.initialize()
	var original: Texture2D = AO.get_texture()
	var smoke: Texture2D = FALLING._smoke_frame(0)
	var world := WORLD.new()
	world.clear_world(Vector3i(16,16,16))
	world.water_enabled = false
	root.add_child(world)
	world.set_block(Vector3i(7,7,7),0x01806040)
	world.rebuild_now()
	var shape: Shape3D = world._chunks[Vector3i.ZERO].collision.shape
	var image := Image.create(256,256,false,Image.FORMAT_RGB8)
	image.fill(Color(0.5,0.5,0.5))
	var loaded: Dictionary = EXTENSIONS.load_pack_bytes(pack_bytes(image))
	check(loaded.ok,"real attributed ZIP pack must load AO/smoke/fragment overrides: " + str(loaded))
	world.reload_resources()
	check(AO.get_texture() != original and absf(AO.atlas_corner(0,0)-128.0/255.0) < 0.01,"resource reload must refresh AO texture and CPU corner cache")
	check(world._material.get_shader_parameter("ambient_occlusion_atlas") == AO.get_texture(),"terrain shader must bind resolved AO override")
	check(FALLING._smoke_frame(0) != smoke,"falling smoke cache must follow resource generation")
	world.rebuild_now()
	check(world._chunks[Vector3i.ZERO].collision.shape == shape,"resource texture refresh must retain collision shape")
	EXTENSIONS.remove_pack("world-textures")
	world.reload_resources()
	check(AO.get_texture() == original and AO.atlas_corner(0,0) == 1.0 and FALLING._smoke_frame(0) == smoke,"removing resource pack must restore source textures and caches")
	var wrong := Image.create(16,16,false,Image.FORMAT_RGB8)
	wrong.fill(Color.WHITE)
	check(EXTENSIONS.load_pack_bytes(pack_bytes(wrong)).ok,"generic texture loader accepts a differently sized replacement")
	world.reload_resources()
	check(AO.get_texture() == original,"invalid AO atlas dimensions must fall back safely to source atlas")
	EXTENSIONS.clear()
	world.reload_resources()
	world.free()
	await process_frame
	print("WORLD RESOURCE TESTS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
