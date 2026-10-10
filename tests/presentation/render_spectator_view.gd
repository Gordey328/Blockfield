extends SceneTree
## Real GPU observed first-person equipment and invalid/dead target visibility.
const Observer = preload("res://presentation/spectator_view.gd")
const Models = preload("res://presentation/openspades_models.gd")
var output := "user://spectator-view-checks"
var checks := 0
var failures := 0
class Snapshots extends Node:
	var profile_version := "0.75"
	var targets := {
		1:{"position":Vector3.ZERO,"team":0,"weapon":0,"tool":2,"alive":true},
		2:{"position":Vector3.ZERO,"team":1,"weapon":1,"tool":2,"alive":true},
		3:{"position":Vector3.ZERO,"team":0,"weapon":2,"tool":2,"alive":true},
		4:{"position":Vector3.ZERO,"team":1,"weapon":0,"tool":3,"alive":true,"ready_state":1.5},
		5:{"position":Vector3.ZERO,"team":0,"weapon":0,"tool":0,"alive":true,"action_type":1,"action_progress":0.35}}
	func get_target(id: int) -> Dictionary: return targets.get(id,{})
	func get_team_info(team: int) -> Dictionary:
		return {"color":Color(0.18,0.42,0.86) if team==0 else Color(0.22,0.66,0.26)}
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
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
	var session := Snapshots.new()
	stage.add_child(session)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 75
	camera.near = 0.025
	stage.add_child(camera)
	var observer := Observer.new()
	camera.add_child(observer)
	observer.setup(camera,session)
	var blank := await _capture("disabled.png")
	for id in range(1,4):
		observer.show_target(id,true)
		observer.update_view(0.0)
		var hip := await _capture("target%d-hip.png"%id)
		_check(_difference(blank,hip)>0.01,"Observed original gun and arms are actually visible")
		session.targets[id].aiming = true
		observer.update_view(0.125)
		var ads := await _capture("target%d-ads.png"%id)
		_check(_difference(hip,ads)>0.01,"Observed ADS snapshot visibly centers original sights")
	observer.show_target(4,true)
	var grenade := await _capture("target4-grenade.png")
	var held_region := Rect2i(grenade.get_width()/2,grenade.get_height()/2,grenade.get_width()/2,grenade.get_height()/2)
	_check(_difference(blank.get_region(held_region),grenade.get_region(held_region))>0.01,"Observed original grenade and hand occupy their camera holding region")
	session.targets[4].cook_time = 0.125
	observer.update_view(0.0)
	var pin := await _capture("target4-pin.png")
	_check(_difference(grenade,pin)>0.005,"Observed pin snapshot drives original hand movement")
	observer.show_target(5,true)
	var spade := await _capture("target5-bash.png")
	_check(_difference(blank,spade)>0.01,"Observed spade action uses its original view skin")
	session.targets[5].alive = false
	observer.update_view(0.1)
	var dead := await _capture("target5-dead.png")
	_check(_difference(blank,dead)<0.00001,"Dead observed target leaves no visible first-person models")
	observer.show_target(99,true)
	var invalid := await _capture("target-missing.png")
	_check(_difference(blank,invalid)<0.00001,"Missing observed target leaves no visible first-person models")
	stage.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	print("SPECTATOR_VIEW_GPU_CHECKS: %d assertions, %d failures; %s"%[checks,failures,output])
	quit(0 if failures==0 else 1)
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
	var sum := 0.0
	var count := 0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var ac := a.get_pixel(x,y); var bc := b.get_pixel(x,y)
			sum += absf(ac.r-bc.r)+absf(ac.g-bc.g)+absf(ac.b-bc.b)
			count += 3
	return sum/float(count)
func _check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
