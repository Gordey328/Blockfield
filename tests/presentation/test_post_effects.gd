extends SceneTree
const Post = preload("res://presentation/openspades_post_effects.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	root.add_child(environment)
	var post := Post.new()
	root.add_child(post)
	post.setup(camera,environment)
	_check(post.layer < 0, "Scene post-processing precedes HUD")
	for name in ["low","medium","high"]:
		_check(post.preset(name).ok, "Preset applies: " + name)
	_check(not post.preset("ultra").ok, "Unknown preset is rejected")
	for options in [{"hdr":true},{"gi":true},{"unknown":1},{"quality":9},{"msaa":8},{"fxaa":1},{"saturation":NAN}]:
		var before := post.get_options()
		_check(not post.set_options(options).ok, "Invalid/unsupported option rejected")
		_check(post.get_options() == before, "Failed option update is atomic")
	_check(post.set_options({"saturation":9.0,"exposure":-9.0,"ambient_energy":0.8}).ok, "Numeric settings clamp at supported bounds")
	_check(post.get_options().saturation == 2.0 and post.get_options().exposure == -4.0, "Option bounds are enforced")
	_check(is_equal_approx(environment.environment.ambient_light_energy,0.8), "Ambient replacement changes real scene lighting")
	for msaa in [0,2,4]:
		post.set_options({"msaa":msaa})
		_check(camera.get_viewport().msaa_3d == (Viewport.MSAA_DISABLED if msaa == 0 else (Viewport.MSAA_2X if msaa == 2 else Viewport.MSAA_4X)), "MSAA changes real viewport samples")
	post.damage(25.0,0.4)
	post.update_state(0,75,0,false,0.5,8.0)
	_check(post._color_material.get_shader_parameter("hurt_flash") == 0, "Main HUD overlay does not draw twice")
	_check(is_equal_approx(post._depth_material.get_shader_parameter("focus_focal_length"),1.679), "Fractional ADS uses original cubic focal length")
	post.update_state(0,75,0,false,1.0,8.0,.15)
	_check(is_equal_approx(post._color_material.get_shader_parameter("radial_blur"),.15),"Native fire/grenade radial strength reaches shader independently")
	_check(is_equal_approx(post._color_material.get_shader_parameter("hurt_blur"),1.65),"Native hurt vignette remains distinct from radial strength")
	post.set_options({"camera_blur":false})
	post.update_state(0,75,0,false,1.0,8.0,.15)
	_check(post._color_material.get_shader_parameter("radial_blur")==0 and post._color_material.get_shader_parameter("hurt_blur")==0,"Blur toggle disables both scene effects")
	post.set_options({"camera_blur":true})
	post.set_hurt_overlay_enabled(true)
	for step in range(50):
		post.update_state(0.1,75,-1,false,1.0 if step % 2 == 0 else 0.0,8.0)
		_check(is_finite(post._color_material.get_shader_parameter("hurt_flash")), "Hurt decay is finite")
	_check(post._color_material.get_shader_parameter("hurt_flash") == 0, "Source hurt flash expires")
	_check(post._color_material.get_shader_parameter("hurt_direction_fade") == 0, "Source three-second directional indicator expires")
	post.reset()
	post.set_options({"bloom":true,"tone_map":true,"color_correction":true,"saturation":1.0,"exposure":2.0})
	post.set_hdr_active(true)
	_check(not post._color_material.get_shader_parameter("bloom_enabled"),"HDR does not receive a second LDR bloom pass")
	_check(not post._color_material.get_shader_parameter("tone_map_enabled") and not post._color_material.get_shader_parameter("correction_enabled"),"HDR correction and ACES precede display only once")
	var hdr: Dictionary=post.get_hdr_correction()
	_check(is_equal_approx(hdr.exposure,2.0) and is_equal_approx(hdr.saturation,.8) and is_equal_approx(hdr.enhancement,.1),"Source HDR color parameters reach the float presentation pass")
	post.set_hdr_active(false)
	_check(post._color_material.get_shader_parameter("bloom_enabled") and post._color_material.get_shader_parameter("tone_map_enabled"),"Disabling HDR restores requested LDR processing")
	post.queue_free()
	camera.queue_free()
	environment.queue_free()
	await process_frame
	await process_frame
	print("POST_EFFECTS_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
