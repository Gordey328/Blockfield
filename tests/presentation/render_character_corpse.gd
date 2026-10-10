extends SceneTree
## Original third-person actions and source spring bodies with a real GPU renderer.
## Images are review evidence in ignored output, never golden files in distribution.
const Character = preload("res://presentation/character_view.gd")
const Corpse = preload("res://presentation/corpse.gd")
const Models = preload("res://presentation/openspades_models.gd")

class TestWorld extends Node3D:
	var dimensions := Vector3i(64,64,64)
	var water_level := -10.0
	var floor_enabled := true
	func clip_box(point: Vector3) -> bool: return floor_enabled and point.y < 1.0
	func get_block(cell: Vector3i) -> int: return 1 if floor_enabled and cell.y == 0 else 0

var output := "user://character-corpse-checks"
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1024,640)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := TestWorld.new()
	stage.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15,0.20,0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20,20)
	floor_mesh.mesh = plane
	floor_mesh.position.y = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.40,0.45,0.48)
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 60
	camera.position = Vector3(6,6,-10)
	stage.add_child(camera)
	camera.look_at(Vector3(0,2.0,0))
	var baseline := await _capture("empty.png")
	var bodies: Array[Node3D] = []
	for index in range(4):
		var corpse := Corpse.new()
		stage.add_child(corpse)
		corpse.setup(world,{"feet_position":Vector3(float(index)*2.0-3.0,1,0),
			"crouch":index==1,"yaw":PI*0.25 if index==2 else 0.0,
			"team":index%2,"seed":40+index,"impulse":Vector3(3.5,0,0) if index==2 else (Vector3(-6,0,0) if index==3 else Vector3.ZERO)})
		bodies.append(corpse)
	var initial := await _capture("corpse-initial.png")
	_check(_difference(baseline,initial)>0.005,"Six original body meshes render in standing/crouching source pose")
	for frame in range(12):
		for corpse in bodies: corpse.step(1.0/60.0)
	var falling := await _capture("corpse-falling.png")
	_check(_difference(initial,falling)>0.003,"Source death impulse and springs visibly change body pose")
	for frame in range(168):
		for corpse in bodies: corpse.step(1.0/60.0)
	var settled := await _capture("corpse-settled.png")
	_check(_difference(baseline,settled)>0.003,"Settled source corpse meshes remain visible on voxel floor")
	_check(_difference(falling,settled)>0.003,"Gravity and voxel contact visibly settle bodies")
	for corpse in bodies: corpse.clear(); corpse.queue_free()
	await process_frame
	bodies.clear()
	var character := Character.new()
	stage.add_child(character)
	character.position = Vector3(0,1,0)
	character.set_team(0)
	character.set_weapon(0,0)
	camera.position = Vector3(4,4,-6)
	camera.look_at(Vector3(0,2,0))
	var idle := await _capture("spade-idle.png")
	character.set_tool_action(Character.ToolAction.BASH,0.0)
	var bash := await _capture("spade-bash.png")
	_check(_difference(idle,bash)>0.001,"Original spade .7 pitch bias visibly moves hands and held tool")
	character.set_tool_action(Character.ToolAction.IDLE)
	character.set_motion_state(6,0,0.25)
	var forward := await _capture("walk-forward.png")
	character.set_motion_state(0,8,0.25)
	var strafe := await _capture("walk-strafe.png")
	_check(_difference(forward,strafe)>0.0005,"Forward and strafe inputs produce distinct source leg rotations")
	character.set_motion_state(0,0,0)
	character.set_weapon(0,1)
	character.set_block_color(Color(0.95,0.2,0.15))
	var red_block := await _capture("block-red.png")
	character.set_block_color(Color(0.15,0.8,0.95))
	var cyan_block := await _capture("block-cyan.png")
	_check(_difference(red_block,cyan_block)>0.0005,"Held block uses independent selected color")
	character.set_pose(true,false,false)
	character.set_intel_carrier(true)
	await _capture("crouch-intel.png")
	character.queue_free()
	await process_frame
	stage.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	print("CHARACTER_CORPSE_GPU_CHECKS: %d assertions, %d failures; %s" % [checks,failures,output])
	quit(0 if failures==0 else 1)

func _capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty(),"Real rendering backend required")
	assert(image.save_png(output.path_join(name))==OK)
	return image

func _difference(a: Image,b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var ac := a.get_pixel(x,y)
			var bc := b.get_pixel(x,y)
			total += absf(ac.r-bc.r)+absf(ac.g-bc.g)+absf(ac.b-bc.b)
			count += 3
	return total/float(count)

func _check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
