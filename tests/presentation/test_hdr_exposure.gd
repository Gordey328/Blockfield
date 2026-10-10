extends SceneTree
const HDR = preload("res://presentation/hdr_exposure.gd")
const SCENE = preload("res://presentation/hdr_scene_viewport.gd")
const BLOOM = preload("res://presentation/hdr_bloom.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HDR: "+message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual-expected) < 0.00001,message+" actual="+str(actual))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Original AutoExposurePreprocess.fs and AutoExposure.fs golden fixtures.
	near(HDR.preprocess_brightness(Color(0.3,0.6,0.4)),0.1296,"native max-RGB fourth power")
	near(HDR.preprocess_brightness(Color.BLACK),0.00000625,"native lower brightness clamp")
	near(HDR.preprocess_brightness(Color(4,2,0.5)),2.8561,"native upper brightness clamp")
	near(HDR.preprocess_brightness(Color(17,0,0)),0.00000625,"native invalid >16 reset")
	near(HDR.preprocess_brightness(Color(-1,-2,-3)),0.00000625,"native negative reset")
	near(HDR.preprocess_brightness(Color(INF,1,0)),0.00000625,"native infinity reset")
	near(HDR.target_gain(0.1296),1.0,"native grey target brightness0.6")
	near(HDR.target_gain(2.8561),0.461538461538,"native unclipped HDR target")
	near(HDR.target_gain(0.00000625),sqrt(2.0),"native max EV +0.5")
	near(HDR.target_gain(pow(8.0,4.0)),pow(2.0,-1.5),"native min EV -1.5")
	near(HDR.adaptation_rate(0.5),0.9,"native dt0.5 blend")
	near(HDR.adaptation_rate(1.0),0.99,"native dt1 blend")
	near(HDR.adaptation_rate(0.2,-1.0),0.0,"negative native speed stops adaptation")
	near(HDR.adaptation_rate(-1.0),0.0,"negative dt cannot extrapolate")
	var tone: Color = HDR.present_color(Color(4,2,0.5),0.461538461538)
	near(tone.r,0.9304409661384333,"native nonlinearize then square/ACES/sqrt red")
	near(tone.g,0.8565384254917561,"native nonlinearize then square/ACES/sqrt green")
	near(tone.b,0.5628017898669923,"native nonlinearize then square/ACES/sqrt blue")
	var exposure: Node = HDR.new()
	root.add_child(exposure)
	exposure.automatic_update = false
	exposure.set_options({"bloom":false})
	check(not exposure.enabled,"HDR defaults off")
	var image: Image = Image.create(256,128,false,Image.FORMAT_RGBAF)
	image.fill(Color(4,2,0.5))
	exposure.setup(ImageTexture.create_from_image(image))
	check(exposure.get_stats().logical_levels == [Vector2i(128,64),Vector2i(64,32),Vector2i(32,16),Vector2i(16,8),Vector2i(8,4),Vector2i(4,2),Vector2i(2,1),Vector2i.ONE],"native ceil-half pyramid under meter budget")
	check(exposure.get_stats().gain_targets == 2,"separate temporal HDR gain targets")
	exposure.set_source_texture(ImageTexture.create_from_image(Image.create(7,5,false,Image.FORMAT_RGBAF)))
	check(exposure.get_stats().logical_levels == [Vector2i(4,3),Vector2i(2,2),Vector2i.ONE],"odd dimensions preserve source ceil-half")
	check(exposure.get_stats().levels[-1] == Vector2i(2,2),"Godot physical two-pixel minimum is explicit")
	check(not exposure.set_options({"gamma":NAN}).ok,"invalid options rejected")
	check(not exposure.set_options({"not_an_option":1}).ok,"unknown options rejected")
	exposure.set_options({"min_ev":-99,"max_ev":99,"speed":-2,"gamma":2.2})
	check(exposure.get_stats().options == {"min_ev":-10.0,"max_ev":10.0,"speed":0.0,"gamma":2.2,"bloom":false},"native EV and speed bounds")
	check(not exposure.set_options({"bloom":1}).ok,"HDR bloom requires boolean")
	var weight_sum: float = 0.0
	for weight: float in BLOOM.GAUSS_WEIGHTS:
		weight_sum += weight
	near(weight_sum,1.0,"native Gaussian preserves constant radiance")
	var glow: Color = BLOOM.compose(Color(4,2,0.5),Color(1,0.5,0.25),Color(0.5,0.5,0.5))
	near(glow.r,4.3,"native LensDust linear red composition")
	near(glow.g,2.15,"native LensDust linear green composition")
	near(glow.b,0.6,"native LensDust linear blue composition")
	exposure.set_enabled(true)
	exposure.advance(1.0)
	check(exposure.get_stats().updates == 1,"enabled meter advances")
	exposure.set_enabled(false)
	exposure.advance(1.0)
	check(exposure.get_stats().updates == 1,"disabled meter consumes no new passes")
	var source_camera: Camera3D = Camera3D.new()
	root.add_child(source_camera)
	root.msaa_3d = Viewport.MSAA_2X
	source_camera.current = true
	source_camera.fov = 79.0
	source_camera.cull_mask = 17
	source_camera.global_position = Vector3(2,3,4)
	var scene: Node = SCENE.new()
	root.add_child(scene)
	scene.setup(source_camera)
	check(scene.get_stats().shared_world,"scene capture shares geometry world")
	check(scene.scene_camera.fov == 79 and scene.scene_camera.cull_mask == 17 and scene.scene_camera.global_position == Vector3(2,3,4),"camera projection/mask/transform synchronized")
	check(scene.scene_viewport.msaa_3d == Viewport.MSAA_2X,"HDR capture retains requested antialiasing")
	scene.set_enabled(true)
	check(root.disable_3d and not source_camera.current and scene.scene_camera.current and scene.presentation.visible,"enabled HDR owns the only 3D render")
	scene.set_enabled(false)
	check(not root.disable_3d and source_camera.current and not scene.presentation.visible,"disabled HDR restores normal source render")
	scene.queue_free()
	exposure.queue_free()
	source_camera.queue_free()
	await process_frame
	await process_frame
	print("HDR EXPOSURE TESTS: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
