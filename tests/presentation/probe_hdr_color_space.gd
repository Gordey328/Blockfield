extends SceneTree
## Diagnostic only: real Compatibility 3D capture versus linear canvas HDR.
## Does not instantiate Main or read/write user preferences.
const HDR = preload("res://presentation/hdr_exposure.gd")
const SIZE := Vector2i(384, 64)
const SWATCHES: Array[Color] = [Color(.05,.2,.8), Color(.4,.7,.1), Color(.18,.18,.18), Color(.03,.06,.12), Color(1,.5,.05), Color(4,2,.5)]
const PICK_CODE := "vec3 pick(float x){if(x<1.0/6.0)return vec3(.05,.2,.8);if(x<2.0/6.0)return vec3(.4,.7,.1);if(x<3.0/6.0)return vec3(.18);if(x<4.0/6.0)return vec3(.03,.06,.12);if(x<5.0/6.0)return vec3(1,.5,.05);return vec3(4,2,.5);}\n"
var checks: int = 0
var failures: int = 0
var output: String
var nodes: Array[Node] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HDR_COLOR_SPACE: " + message)

func settle() -> void:
	for _i: int in range(4):
		await process_frame
		await RenderingServer.frame_post_draw

func viewport(hdr: bool) -> SubViewport:
	var result := SubViewport.new()
	result.size = SIZE
	result.use_hdr_2d = hdr
	result.disable_3d = true
	result.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(result)
	nodes.append(result)
	return result

func shader_rect(target: SubViewport, code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE)
	rect.material = material
	target.add_child(rect)
	return material

func gpu_sample(texture: Texture2D, value_range: float = 1.0) -> Array[Color]:
	if not OS.has_feature("web"):
		var direct := texture.get_image()
		var samples: Array[Color] = []
		for i: int in range(6):
			# Meter targets can be only 2 pixels wide; sample relative positions.
			var x := mini(direct.get_width()-1,int((float(i)+.5)*direct.get_width()/6.0))
			samples.append(direct.get_pixel(x,direct.get_height()/2))
		return samples
	# Encode known range on GPU to avoid Web float readback clipping.
	var readback := viewport(false)
	var material := shader_rect(readback,"shader_type canvas_item;render_mode unshaded;uniform sampler2D tex:filter_nearest;uniform float value_range;void fragment(){COLOR=vec4(texture(tex,UV).rgb/value_range,1.0);}")
	material.set_shader_parameter("tex", texture)
	material.set_shader_parameter("value_range", value_range)
	await settle()
	var image := readback.get_texture().get_image()
	var result: Array[Color] = []
	for i: int in range(6):
		var color: Color = image.get_pixel(i*64+32,32)
		result.append(Color(color.r*value_range,color.g*value_range,color.b*value_range))
	readback.queue_free()
	nodes.erase(readback)
	return result

func cpu_linear(color: Color) -> Color:
	var result := Color.BLACK
	for i: int in range(3):
		var x: float = color[i]
		# Godot 4.7.2 scene.glsl uses this polynomial on authored ALBEDO.
		result[i] = x*(x*(x*.305306011+.682171111)+.012522878)
	return result

func cpu_encode(color: Color) -> Color:
	var result := Color.BLACK
	for i: int in range(3):
		result[i] = maxf(1.055*pow(color[i],1.0/2.4)-.055,0.0)
	return result

func values(colors: Array[Color]) -> Array:
	var result: Array = []
	for color: Color in colors:
		result.append([color.r,color.g,color.b])
	return result

func presentation(source: Texture2D, encoded: bool = false) -> Dictionary:
	var exposure := HDR.new()
	root.add_child(exposure)
	nodes.append(exposure)
	exposure.automatic_update = false
	exposure.set_options({"bloom":false,"speed":0.0})
	exposure.setup(source,encoded)
	exposure.set_enabled(true)
	var target := viewport(false)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE)
	rect.material = exposure.get_present_material()
	target.add_child(rect)
	return {"target":target,"exposure":exposure}

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HDR color-space probe requires a graphics context")
		quit(1)
		return
	output = ProjectSettings.globalize_path("res://../.cache/previews/hdr-color-space")
	DirAccess.make_dir_recursive_absolute(output)
	var scene := viewport(true)
	scene.disable_3d = false
	scene.own_world_3d = true
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	camera.environment = environment
	scene.add_child(camera)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(12,2)
	mesh.mesh = quad
	mesh.position.z = -2.0
	var spatial_shader := Shader.new()
	spatial_shader.code = "shader_type spatial;render_mode unshaded,fog_disabled;" + PICK_CODE + "void fragment(){ALBEDO=pick(UV.x);}"
	var spatial_material := ShaderMaterial.new()
	spatial_material.shader = spatial_shader
	mesh.material_override = spatial_material
	scene.add_child(mesh)
	var canvas := viewport(true)
	shader_rect(canvas, "shader_type canvas_item;render_mode unshaded;" + PICK_CODE + "void fragment(){COLOR=vec4(pick(UV.x),1.0);}")
	var wrong := presentation(scene.get_texture())
	var corrected := presentation(scene.get_texture(),true)
	await settle()
	var raw_values: Array[Color] = await gpu_sample(scene.get_texture(),8.0)
	var canvas_values: Array[Color] = await gpu_sample(canvas.get_texture(),8.0)
	var linear_texture: Texture2D = corrected.exposure.get_linear_texture()
	var decoded_values: Array[Color] = await gpu_sample(linear_texture,32.0)
	var wrong_values: Array[Color] = await gpu_sample(wrong.target.get_texture())
	var corrected_values: Array[Color] = await gpu_sample(corrected.target.get_texture())
	var expected_encoded: Array[Color] = []
	var expected_linear: Array[Color] = []
	var expected_present: Array[Color] = []
	for i: int in range(6):
		var linear := cpu_linear(SWATCHES[i])
		var encoded := cpu_encode(linear)
		var present: Color = HDR.present_color(linear,1.0)
		expected_encoded.append(encoded)
		expected_linear.append(linear)
		expected_present.append(present)
		for channel: int in range(3):
			check(absf(raw_values[i][channel]-encoded[channel])<8.0/255+.015,"3D sample follows Compatibility OETF swatch %d channel %d"%[i,channel])
			check(absf(canvas_values[i][channel]-SWATCHES[i][channel])<8.0/255+.008,"canvas sample stays linear swatch %d channel %d"%[i,channel])
			check(absf(decoded_values[i][channel]-linear[channel])<32.0/255+.03,"decoded sample recovers pre-OETF radiance swatch %d channel %d"%[i,channel])
			check(absf(corrected_values[i][channel]-present[channel])<.014,"corrected tone follows native linear-input reference swatch %d channel %d"%[i,channel])
	check(wrong_values[2].r-corrected_values[2].r>.20,"duplicate transfer visibly lifts neutral .18 swatch")
	check((corrected_values[0].b-corrected_values[0].r)>(wrong_values[0].b-wrong_values[0].r)+.06,"decode recovers chroma on blue swatch")
	check(corrected.exposure.get_present_material().get_shader_parameter("scene_texture") == linear_texture,"presentation consumes shared normalized radiance")
	check(corrected.exposure._levels[0].get_child(0).material.get_shader_parameter("source_texture") == linear_texture,"meter consumes same shared normalized radiance")
	check(corrected.exposure._bloom._source == linear_texture,"bloom consumes same shared normalized radiance")
	check(wrong.exposure.get_linear_texture() == scene.get_texture() and wrong.exposure.get_stats().normalization_color_bytes == 0,"linear default bypasses normalization without allocation")
	check(corrected.exposure.get_stats().normalization_color_bytes == SIZE.x*SIZE.y*8,"single normalization target memory is accounted")
	var wrong_power: float = (await gpu_sample(wrong.exposure._levels[-1].get_texture(),4.0))[0].r
	var corrected_power: float = (await gpu_sample(corrected.exposure._levels[-1].get_texture(),4.0))[0].r
	wrong.target.get_texture().get_image().save_png(output.path_join("01-current-encoded-input.png"))
	corrected.target.get_texture().get_image().save_png(output.path_join("02-decoded-linear-input.png"))
	var metrics: Dictionary = {"renderer":RenderingServer.get_video_adapter_name(),"assertions":checks,"failures":failures,"authored_albedo":values(SWATCHES),"raw_3d":values(raw_values),"linear_canvas":values(canvas_values),"decoded_scene":values(decoded_values),"expected_encoded":values(expected_encoded),"expected_linear":values(expected_linear),"expected_corrected":values(expected_present),"current_display":values(wrong_values),"corrected_display":values(corrected_values),"current_meter_power":wrong_power,"corrected_meter_power":corrected_power,"gain":1.0,"bloom":false,"preferences":"untouched"}
	FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	print("HDR COLOR SPACE PROBE: %d assertions, %d failures"%[checks,failures])
	print(JSON.stringify(metrics))
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
