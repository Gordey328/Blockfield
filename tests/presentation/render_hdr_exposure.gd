extends SceneTree
## Real GPU readback: float scene, reduction, temporal gain, native tone, switch.
const HDR = preload("res://presentation/hdr_exposure.gd")
const SCENE = preload("res://presentation/hdr_scene_viewport.gd")
const BLOOM = preload("res://presentation/hdr_bloom.gd")
var checks: int = 0
var failures: int = 0
var output: String = ""
var metrics: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HDR GPU: "+message)

func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual-expected) < tolerance,message+" actual="+str(actual)+" expected="+str(expected))

func settle() -> void:
	for frame: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw

func target(size: Vector2i, hdr: bool) -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func color_array(color: Color) -> Array:
	return [color.r,color.g,color.b]

func read_float(texture: Texture2D, value_range: float) -> Color:
	if not OS.has_feature("web"):
		var direct: Image = texture.get_image()
		return direct.get_pixel(direct.get_width()/2,direct.get_height()/2)
	# Web get_image() can tag the image RGBAF yet clip its values like RGBA8. Encode
	# known test ranges on GPU before readback; CPU-side clamping cannot fake
	# a preserved highlight in this pass. Error is at most range/255 per channel.
	var probe: SubViewport = target(Vector2i(2,2),false)
	probe.disable_3d = true
	var shader: Shader = Shader.new()
	shader.code = "shader_type canvas_item;render_mode unshaded;uniform sampler2D value_texture:filter_nearest;uniform float value_range=1.0;void fragment(){COLOR=vec4(texture(value_texture,vec2(0.5)).rgb/value_range,1.0);}"
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("value_texture",texture)
	material.set_shader_parameter("value_range",value_range)
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(2,2)
	rect.material = material
	probe.add_child(rect)
	await settle()
	var encoded: Color = probe.get_texture().get_image().get_pixel(1,1)
	probe.queue_free()
	return Color(encoded.r*value_range,encoded.g*value_range,encoded.b*value_range,1.0)

func tolerance(desktop: float, value_range: float) -> float:
	return desktop+value_range/255.0 if OS.has_feature("web") else desktop

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HDR GPU test requires a real graphics context")
		quit(1)
		return
	output = OS.get_cache_dir().path_join("blockfield-hdr")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var source: SubViewport = target(Vector2i(32,32),true)
	source.disable_3d = true
	var source_shader: Shader = Shader.new()
	source_shader.code = "shader_type canvas_item;render_mode unshaded;uniform vec3 radiance=vec3(4.0,2.0,0.5);uniform bool split=false;uniform bool hotspot=false;void fragment(){vec3 value=split?(UV.x<0.5?vec3(0.1):vec3(1.0)):radiance;if(hotspot&&any(greaterThan(abs(UV-vec2(0.5)),vec2(0.03125)))){value=vec3(0.05);}COLOR=vec4(value,1.0);}"
	var source_material: ShaderMaterial = ShaderMaterial.new()
	source_material.shader = source_shader
	var source_rect: ColorRect = ColorRect.new()
	source_rect.size = Vector2(32,32)
	source_rect.material = source_material
	source.add_child(source_rect)
	var exposure: Node = HDR.new()
	root.add_child(exposure)
	exposure.automatic_update = false
	exposure.set_options({"bloom":false})
	exposure.setup(source.get_texture())
	exposure.set_enabled(true)
	var presented: SubViewport = target(Vector2i(128,128),false)
	presented.disable_3d = true
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(128,128)
	rect.material = exposure.get_present_material()
	presented.add_child(rect)
	await settle()
	var image: Image = source.get_texture().get_image()
	var radiance: Color = await read_float(source.get_texture(),8.0)
	check(radiance.r > 1.0 and radiance.g > 1.0 if OS.has_feature("web") else image.get_format() == Image.FORMAT_RGBAF,"encoded web GPU range or native desktop RGBAF proves HDR independently of raw readback metadata")
	near(radiance.r,4.0,tolerance(0.01,8.0),"red radiance above one survives scene buffer")
	near(radiance.g,2.0,tolerance(0.01,8.0),"green radiance above one survives scene buffer")
	var last_level: SubViewport = exposure._levels[-1]
	var brightness: float = (await read_float(last_level.get_texture(),4.0)).r
	near(brightness,2.8561,tolerance(0.01,4.0),"float brightness pyramid preserves fourth power above one")
	exposure.advance(0.5)
	await settle()
	var gain1: float = (await read_float(exposure.get_gain_texture(),2.0)).r
	near(gain1,0.5153846153846,tolerance(0.003,2.0),"GPU adaptation follows native 0.9 rate from gain one")
	var toned: Image = presented.get_texture().get_image()
	toned.save_png(output.path_join("01-hdr-tone.png"))
	var display: Color = toned.get_pixel(64,64)
	var expected: Color = HDR.present_color(Color(4,2,0.5),gain1)
	for channel: int in range(3):
		near(display[channel],expected[channel],tolerance(0.008,2.0),"native pre-LDR tone channel"+str(channel))
	check(display.r < 0.99 and display.g < 0.97 and display.r-display.g > 0.03,"different overbright channels remain distinct after tone mapping")
	var native_present: ShaderMaterial = exposure.get_present_material()
	native_present.set_shader_parameter("tint",Vector3(0.8,1.1,0.9))
	native_present.set_shader_parameter("exposure",1.2)
	native_present.set_shader_parameter("saturation",0.6)
	native_present.set_shader_parameter("enhancement",0.1)
	await settle()
	var corrected: Color = presented.get_texture().get_image().get_pixel(64,64)
	# Independent source-formula golden fixture, computed with initial gain
	# .5153846153846. Correcting already-toned LDR cannot match these channels.
	near(corrected.r,0.9241936194755784,0.008,"native tint/manual exposure/saturation precede HDR tone mapping")
	near(corrected.b,0.791124993880472,0.008,"native enhancement follows pre-tone color correction")
	native_present.set_shader_parameter("tint",Vector3.ONE)
	native_present.set_shader_parameter("exposure",1.0)
	native_present.set_shader_parameter("saturation",1.0)
	native_present.set_shader_parameter("enhancement",0.0)
	exposure.advance(0.5)
	await settle()
	var gain2: float = (await read_float(exposure.get_gain_texture(),2.0)).r
	near(gain2,lerpf(gain1,0.6/1.3,0.9),tolerance(0.003,2.0),"ping-pong gain retains previous frame instead of resetting")
	source_material.set_shader_parameter("split",true)
	await settle()
	var split_power: float = (await read_float(last_level.get_texture(),4.0)).r
	near(split_power,0.50005,tolerance(0.003,4.0),"native pyramid averages fourth powers across bright and dark areas")
	source_material.set_shader_parameter("split",false)
	source_material.set_shader_parameter("radiance",Vector3(0.05,0.05,0.05))
	await settle()
	exposure.advance(1.0)
	await settle()
	var dark_gain: float = (await read_float(exposure.get_gain_texture(),2.0)).r
	near(dark_gain,lerpf(gain2,sqrt(2.0),0.99),tolerance(0.004,2.0),"dark transition moves toward original maxEV gain")
	exposure.set_options({"speed":0.0})
	exposure.advance(10.0)
	await settle()
	near((await read_float(exposure.get_gain_texture(),2.0)).r,dark_gain,tolerance(0.001,2.0),"GPU zero-speed mode holds temporal exposure")
	source_material.set_shader_parameter("radiance",Vector3(4,2,0.5))
	exposure.set_enabled(false)
	await settle()
	var disabled: Image = presented.get_texture().get_image()
	disabled.save_png(output.path_join("02-ldr-clipped.png"))
	var clipped: Color = disabled.get_pixel(64,64)
	near(clipped.r,1.0,0.004,"disabled path exposes actual LDR red clipping")
	near(clipped.g,1.0,0.004,"disabled path exposes actual LDR green clipping")
	near(clipped.b,0.5,0.004,"disabled path preserves sub-one blue")
	# Native HDR LensDust bloom must retain highlight energy, enter the meter,
	# and spread into dark pixels before any gamma/tone/RGBA8 conversion.
	var dust_image: Image = Image.create(2,2,false,Image.FORMAT_RGBAF)
	dust_image.fill(Color(0.5,0.5,0.5))
	exposure.set_bloom_dust_texture(ImageTexture.create_from_image(dust_image))
	exposure.get_present_material().set_shader_parameter("grain_enabled",false)
	exposure._levels[0].get_child(0).material.set_shader_parameter("grain_enabled",false)
	exposure.set_options({"bloom":true,"speed":1.0})
	exposure.set_enabled(true)
	await settle()
	var constant_blur: Color = await read_float(exposure._bloom.get_blur_texture(),8.0)
	near(constant_blur.r,4.0,tolerance(0.015,8.0),"source Gaussian hierarchy preserves float highlight above one")
	near(constant_blur.g,2.0,tolerance(0.015,8.0),"source Gaussian hierarchy preserves constant green radiance")
	var bloom_display: Color = presented.get_texture().get_image().get_pixel(64,64)
	var bloom_expected: Color = HDR.present_color(BLOOM.compose(Color(4,2,0.5),Color(4,2,0.5),Color(0.5,0.5,0.5)),1.0)
	near(bloom_display.b,bloom_expected.b,0.008,"native HDR LensDust compose occurs before gamma/ACES")
	source_material.set_shader_parameter("radiance",Vector3(0.6,0.3,0.15))
	await settle()
	var bloom_power: float = (await read_float(last_level.get_texture(),4.0)).r
	near(bloom_power,pow(0.87,4),tolerance(0.004,4.0),"auto-exposure meter sees pre-tone native bloom composite")
	exposure.advance(0.5)
	await settle()
	var bloom_gain: float = (await read_float(exposure.get_gain_texture(),2.0)).r
	near(bloom_gain,lerpf(1.0,0.6/0.87,0.9),tolerance(0.005,2.0),"native bloom feeds actual temporal exposure rather than a later LDR overlay")
	exposure.set_options({"speed":0.0,"bloom":false})
	source_material.set_shader_parameter("hotspot",true)
	source_material.set_shader_parameter("radiance",Vector3(8,4,1))
	await settle()
	var without_bloom: Image = presented.get_texture().get_image()
	without_bloom.save_png(output.path_join("03-highlight-no-bloom.png"))
	var halo_off: Color = without_bloom.get_pixel(84,64)
	exposure.set_options({"bloom":true})
	await settle()
	var with_bloom: Image = presented.get_texture().get_image()
	with_bloom.save_png(output.path_join("04-highlight-hdr-bloom.png"))
	var halo_high: Color = with_bloom.get_pixel(84,64)
	check(halo_high.r > halo_off.r+0.02,"HDR bloom spreads native float highlight energy into dark neighbouring pixels")
	source_material.set_shader_parameter("radiance",Vector3(2,1,0.25))
	await settle()
	var halo_low: Color = presented.get_texture().get_image().get_pixel(84,64)
	check(halo_high.r > halo_low.r+0.015,"eight-unit highlight yields a stronger halo than two-unit highlight despite both clipping in LDR")
	exposure.set_options({"bloom":false})
	await settle()
	var restored_halo: Color = presented.get_texture().get_image().get_pixel(84,64)
	near(restored_halo.r,halo_off.r,0.004,"HDR bloom toggle restores exact halo-free presentation")
	# Shared-world 3D adapter: scene is rendered once through a cloned camera.
	var host: SubViewport = target(Vector2i(96,64),false)
	host.own_world_3d = true
	var camera: Camera3D = Camera3D.new()
	host.add_child(camera)
	camera.current = true
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(4,4)
	var spatial: Shader = Shader.new()
	# Authored ALBEDO is not radiance: Compatibility applies its sRGB polynomial
	# before shading. ALBEDO4 implies 30.5 linear units, outside the native meter
	# valid range <=16. This fixture's linear units are (2.584077,1,.214967).
	spatial.code = "shader_type spatial;render_mode unshaded;void fragment(){ALBEDO=vec3(1.5,1.0,0.5);}"
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = spatial
	quad.material = material
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position.z = -2.0
	host.add_child(mesh)
	var scene: Node = SCENE.new()
	host.add_child(scene)
	scene.setup(camera,host)
	scene.exposure.automatic_update = false
	scene.exposure.set_options({"bloom":false})
	scene.set_enabled(true)
	await settle()
	var scene_image: Image = scene.scene_viewport.get_texture().get_image()
	var scene_encoded: Color = await read_float(scene.scene_viewport.get_texture(),8.0)
	var scene_radiance: Color = await read_float(scene.exposure.get_linear_texture(),4.0)
	near(scene_radiance.r,2.584077103875,tolerance(.02,4.0),"shared-world boundary reconstructs overbright linear scene radiance")
	near(scene_radiance.b,.214967468125,tolerance(.004,4.0),"shared-world boundary reconstructs sub-one linear scene radiance")
	check(scene.exposure.get_stats().input_encoding == "compatibility_encoded","3D adapter explicitly identifies encoded input")
	check(host.disable_3d and not camera.current and scene.scene_camera.current,"original render is disabled while cloned capture owns 3D")
	scene.exposure.advance(0.5)
	await settle()
	var captured_hdr: Color = host.get_texture().get_image().get_pixel(48,32)
	check(captured_hdr.r > captured_hdr.g+0.03 and captured_hdr.g < 0.97,"adapter presents source tone before its host becomes LDR")
	scene.set_enabled(false)
	await settle()
	var ordinary: Color = host.get_texture().get_image().get_pixel(48,32)
	check(camera.current and not host.disable_3d and ordinary.r == 1.0 and ordinary.g >= .996,"turning adapter off restores normal camera and LDR framebuffer")
	metrics = {"renderer":RenderingServer.get_video_adapter_name(),"assertions":checks,"failures":failures,"raw_cpu_format":image.get_format(),"readback_mode":"gpu-range-encoded-rgba8" if OS.has_feature("web") else "direct-rgbaf","scene_radiance":color_array(radiance),"brightness_power":brightness,"gain_0_5s":gain1,"gain_1s":gain2,"dark_gain":dark_gain,"split_power":split_power,"hdr_display":color_array(display),"corrected_display":color_array(corrected),"ldr_display":color_array(clipped),"actual_3d_radiance":color_array(scene_radiance),"adapter_display":color_array(captured_hdr),"bloom_power":bloom_power,"bloom_gain":bloom_gain,"bloom_blur":color_array(constant_blur),"halo_off":color_array(halo_off),"halo_high":color_array(halo_high),"halo_low":color_array(halo_low),"budget":exposure.get_stats()}
	metrics.actual_3d_encoded = color_array(scene_encoded)
	FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	print("HDR GPU TESTS: %d assertions, %d failures; %s" % [checks,failures,output])
	print(JSON.stringify(metrics))
	scene.set_enabled(false)
	for node: Node in [source,presented,exposure,host]:
		node.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
