extends SceneTree
## Runtime GLB and PNG replacements must change an actual GPU frame.
const Extensions = preload("res://presentation/openspades_extensions.gd")
const Models = preload("res://presentation/openspades_models.gd")
const Character = preload("res://presentation/character_view.gd")
var output: String
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	output = OS.get_cache_dir().path_join("blockfield-extension-preview")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	Extensions.clear()
	root.size = Vector2i(960,540)
	var scene := Node3D.new()
	root.add_child(scene)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-35,0)
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.13,0.16,0.21)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0,1.6,4)
	camera.look_at(Vector3(0,1.3,0))
	camera.current = true
	var soldier := Character.new()
	scene.add_child(soldier)
	soldier.set_team(0)
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	var icon := TextureRect.new()
	icon.position = Vector2(30,30)
	icon.size = Vector2(64,64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = Extensions.texture("Gfx/AlertIcon.png")
	overlay.add_child(icon)
	var baseline: Image = await _capture("original")
	var bytes := FileAccess.get_file_as_bytes("res://assets/openspades/models/Player/Head.glb")
	var description: Dictionary = JSON.parse_string(bytes.slice(20,20+bytes.decode_u32(12)).get_string_from_utf8())
	var binary := 28+bytes.decode_u32(12)
	for primitive in description.meshes[0].primitives:
		var accessor: Dictionary = description.accessors[int(primitive.attributes.COLOR_0)]
		var view: Dictionary = description.bufferViews[int(accessor.bufferView)]
		for index in range(int(accessor.count)):
			var offset := binary+int(view.byteOffset)+index*16
			bytes.encode_float(offset,1)
			bytes.encode_float(offset+4,0.03)
			bytes.encode_float(offset+8,1)
	var result := Extensions.load_pack_bytes(_pack("model-test","Models/Player/Head.kv6","head.glb","model",bytes))
	if not result.ok: failures += 1; push_error(str(result))
	soldier.refresh_resources()
	var model_image: Image = await _capture("model-override")
	var model_difference := _difference(baseline,model_image)
	if model_difference < 0.00003: failures += 1; push_error("Runtime model replacement produced no GPU difference")
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	result = Extensions.load_pack_bytes(_pack("texture-test","Gfx/AlertIcon.png","icon.png","texture",image.save_png_to_buffer()))
	if not result.ok: failures += 1; push_error(str(result))
	icon.texture = Extensions.texture("Gfx/AlertIcon.png")
	var texture_image: Image = await _capture("texture-override")
	var texture_difference := _difference(model_image,texture_image)
	if texture_difference < 0.00003: failures += 1; push_error("Runtime texture replacement produced no GPU difference")
	scene.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	Extensions.clear()
	print("EXTENSION_GPU_CHECKS: " + JSON.stringify({"model_difference":model_difference,"texture_difference":texture_difference,"failures":failures}))
	quit(0 if failures == 0 else 1)
func _pack(id: String,target: String,path: String,kind: String,bytes: PackedByteArray) -> PackedByteArray:
	var manifest := {"version":1,"id":id,"title":"GPU test fixture","authors":["Original OpenSpades contributors; test transformation by Blockfield"],
		"license":"Original licenses apply; see game/assets/openspades/licenses","assets":{target:{"file":path,"type":kind,"sha256":Extensions._sha256(bytes)}}}
	var staged := "user://extension-gpu-fixture.zip"
	var writer := ZIPPacker.new()
	writer.open(staged)
	writer.start_file("blockfield-pack.json")
	writer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	writer.close_file()
	writer.start_file(path)
	writer.write_file(bytes)
	writer.close_file()
	writer.close()
	var packed := FileAccess.get_file_as_bytes(staged)
	DirAccess.remove_absolute(staged)
	return packed
func _capture(name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(name+".png"))
	return image
func _difference(a: Image,b: Image) -> float:
	var total := 0.0
	for y in range(0,a.get_height(),3):
		for x in range(0,a.get_width(),3):
			var first := a.get_pixel(x,y)
			var second := b.get_pixel(x,y)
			total += absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)
	return total/float(ceili(a.get_width()/3.0)*ceili(a.get_height()/3.0)*3)
