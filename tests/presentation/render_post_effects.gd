extends SceneTree
## Real GPU image-difference checks; run with Compatibility, never --headless.
const Post = preload("res://presentation/openspades_post_effects.gd")
var failures := 0
var differences: Dictionary = {}
var output: String
var post: OpenSpadesPostEffects
var camera: Camera3D
var environment: WorldEnvironment
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	output = OS.get_cache_dir().path_join("blockfield-post-preview")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(960,540)
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16,0.2,0.28)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-30,0)
	root.add_child(light)
	_box(Vector3(0,-0.4,0),Vector3(20,0.5,20),Color(0.4,0.42,0.44))
	for index in range(12):
		var node := _box(Vector3(float(index)-6,1,-2),Vector3(0.45,2,0.45),Color(0.95,0.9,0.65) if index % 2 == 0 else Color(0.05,0.1,0.25))
		node.rotation.z = 0.35
	_box(Vector3(-2,0.65,2),Vector3(1.2,1.2,1.2),Color(0.8,0.12,0.09))
	_box(Vector3(-0.8,1,0),Vector3(0.7,2,2),Color(0.6,0.6,0.6))
	_box(Vector3(0.5,0.45,-0.6),Vector3(2,0.8,0.5),Color(0.6,0.6,0.6))
	camera = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,3.4,8)
	camera.look_at(Vector3(0,0.7,0))
	camera.current = true
	post = Post.new()
	root.add_child(post)
	post.setup(camera,environment)
	for effect in ["fxaa","bloom","lens","lens_flare","color_correction","tone_map","camera_blur","radial_blur","dof","ssao","ambient_energy","msaa","damage","manual_focus"]:
		_off()
		post.update_state(0,100,0.1 if effect == "camera_blur" else 10,false,0.0,10)
		var before: Image = await _capture(effect+"-off")
		if effect == "damage":
			post.set_hurt_overlay_enabled(true)
			post.damage(50,0.5)
			post.update_state(0,50,0.05,false,0.0)
		elif effect == "ambient_energy":
			post.set_options({"ambient_energy":0.1})
		elif effect == "msaa":
			post.set_options({"msaa":4})
		elif effect == "manual_focus":
			post.set_options({"dof":true,"manual_focus":true})
			post.update_state(0,100,10,false,0.0,3)
		elif effect == "radial_blur":
			post.set_options({"camera_blur":true})
			post.update_state(0,100,10,false,0.0,10,.15)
		else:
			post.set_options({effect:true})
			post.set_flare_sources([{"position":Vector3(3,2,-2),"energy":1.0,"radius":0.1}])
			post.update_state(0,100,0.1 if effect == "camera_blur" else 10,false,1.0 if effect == "dof" else 0.0,15)
		var after: Image = await _capture(effect+"-on")
		var difference := _difference(before,after)
		differences[effect] = difference
		if difference <= 0.000003:
			failures += 1
			push_error("No visible GPU difference for " + effect)
	_off()
	post.set_options({"ssao":true,"dof":true})
	post.update_state(0,100,10,false,1.0,15)
	camera.near = 0.025
	var weapon: Node3D = load("res://presentation/weapon_view.gd").new()
	camera.add_child(weapon)
	weapon.update_pose(0.5,false,false,false,0)
	weapon.hide()
	var without_weapon: Image = await _capture("depth-without-weapon")
	weapon.show()
	var with_weapon: Image = await _capture("depth-with-weapon")
	differences["depth_weapon_visible"] = _difference(without_weapon,with_weapon)
	if differences.depth_weapon_visible <= 0.000003:
		failures += 1
		push_error("Depth effects erased first-person equipment")
	weapon.queue_free()
	post.queue_free()
	await process_frame
	await process_frame
	print("POST_GPU_CHECKS: " + JSON.stringify({"differences":differences,"failures":failures}))
	quit(0 if failures == 0 else 1)
func _off() -> void:
	post.set_hurt_overlay_enabled(false)
	post.set_options({"fxaa":false,"bloom":false,"lens":false,"lens_flare":false,
		"color_correction":false,"tone_map":false,"camera_blur":false,"dof":false,
		"ssao":false,"ambient_energy":0.65,"msaa":0,"quality":2,"exposure":0.0,"manual_focus":false})
	post.reset()
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
func _box(position: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	root.add_child(node)
	node.position = position
	return node
