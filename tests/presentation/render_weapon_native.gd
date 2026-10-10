extends SceneTree
## Real GPU first-person native matrix/action/reload previews.
const Weapon = preload("res://presentation/weapon_view.gd")
const Models = preload("res://presentation/openspades_models.gd")
var output := "user://weapon-native-checks"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output=" ): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1024,640)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16,0.21,0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 75
	camera.near = 0.025
	stage.add_child(camera)
	var view := Weapon.new()
	camera.add_child(view)
	# Share fixed native fixture setup without instantiating another SceneTree.
	for gun in range(3):
		_neutral(view,2,gun)
		view._update_gun(Vector3.ZERO)
		view._update_view_arms()
		var hip := await _capture("gun%d-hip.png"%gun)
		_check(_dark_centroid(hip)>0.52,"Native hip gun %d occupies the right side of camera"%gun)
		view._aim = 1.0
		view._update_gun(Vector3.ZERO)
		view._update_view_arms()
		var ads := await _capture("gun%d-ads.png"%gun)
		_check(_difference(hip,ads)>0.01,"Original hip and aligned sights produce distinct visible poses")
		_neutral(view,2,gun)
		view._reloading = true
		for progress in [0.05,0.24,0.42,0.65,0.82,0.95]:
			view._reload_progress = progress
			view._ready_state = 1.5
			view.set_ammo(5,6)
			view._update_gun(Vector3.ZERO)
			view._update_view_arms()
			await _capture("gun%d-reload-%02d.png"%[gun,roundi(progress*100)])
	_neutral(view,2,2)
	view._ready_state = 0.65
	view._update_gun(Vector3.ZERO)
	view._update_view_arms()
	await _capture("shotgun-pump.png")
	_neutral(view,0,0)
	view.set_tool_action(Weapon.ToolAction.DIG_START,0.25)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var first := await _capture("spade-dig-start.png")
	view.set_tool_action(Weapon.ToolAction.DIG,0.25)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var repeated := await _capture("spade-dig-repeat.png")
	_check(_difference(first,repeated)>0.01,"First and repeated source dig stages visibly differ")
	_neutral(view,1,0)
	view.set_block_color(Color(0.8,0.2,0.7))
	view.set_tool_action(0,0,1.0)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var block := await _capture("block-ready.png")
	view.set_tool_action(0,0,0.0)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var empty := await _capture("block-unready.png")
	_check(_difference(block,empty)>0.01,"Unready block disappears while original hands rest")
	_neutral(view,3,0)
	view.set_tool_action(0,0,1.5)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var grenade := await _capture("grenade-ready.png")
	view.set_grenade_cook(0.125)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var pin := await _capture("grenade-pin.png")
	_check(_difference(grenade,pin)>0.005,"Original grenade pin pull visibly moves left hand")
	view.set_tool_action(0,0,0.2)
	view._update_tool(Vector3.ZERO)
	view._update_view_arms()
	var throwing := await _capture("grenade-throw.png")
	_check(_difference(pin,throwing)>0.01,"Source grenade throw hides model and animates throwing hand")
	view.set_team(1,Color(0.85,0.30,0.10))
	_neutral(view,2,0)
	view._update_gun(Vector3.ZERO)
	view._update_view_arms()
	await _capture("custom-team-arms.png")
	stage.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	print("WEAPON_NATIVE_GPU_CHECKS: %d assertions, %d failures; %s"%[checks,failures,output])
	quit(0 if failures==0 else 1)

func _neutral(view: Node3D,tool: int,gun: int) -> void:
	# Fixed input fixture excludes pulse/inertia while inspecting source skin stages.
	view._tool=tool; view._weapon=gun
	view._requested_tool=tool; view._requested_weapon=gun
	view._raise_raw=1.0; view._raise=1.0; view._sprint_state=0.0; view._sprint=0.0
	view._aim=0.0; view._time=0.0; view._vibration=0.0; view._view_offset=Vector3.ZERO
	view._fire_elapsed=1000.0; view._reloading=false; view._reload_progress=0.0
	view._post_reload_elapsed=-1.0; view._source_ready=false; view._source_action=false
	view._cook_time=0.0; view._ready_state=1.0
	view.set_motion_state(Vector3.ZERO,0)
	view._rebuild_parts()
func _capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty())
	assert(image.save_png(output.path_join(name))==OK)
	return image
func _difference(a: Image,b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var ac:=a.get_pixel(x,y); var bc:=b.get_pixel(x,y)
			total+=absf(ac.r-bc.r)+absf(ac.g-bc.g)+absf(ac.b-bc.b); count+=3
	return total/float(count)
func _dark_centroid(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			var color := image.get_pixel(x,y)
			if color.r<0.20 and color.g<0.20 and color.b<0.20: total+=x; count+=1
	return total/float(maxi(count,1))/float(image.get_width())
func _check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(message)
