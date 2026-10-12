extends SceneTree
## Explicit production static mode: original prone mesh, one-time placement,
## frozen presentation, retained visibility/resource/lifecycle contracts.
const CORPSE = preload("res://presentation/corpse.gd")
const MODELS = preload("res://presentation/openspades_models.gd")
const CHARACTER = preload("res://presentation/character_view.gd")
var assertions: int = 0
var failures: int = 0
var gpu: bool = false
var output: String = ""

class CountedWorld extends Node3D:
	var dimensions := Vector3i(32,32,32)
	var water_level: float = -10.0
	var queries: int = 0
	var floor_enabled: bool = true
	var blocks: Dictionary[Vector3i,int] = {}
	func get_block(cell: Vector3i) -> int:
		queries += 1
		return 1 if floor_enabled and cell.y == 3 else int(blocks.get(cell,0))
	func clip_box(point: Vector3) -> bool:
		queries += 1
		return floor_enabled and point.y < 4.0

class CountedCorpse extends OpenSpadesCorpse:
	var solver_calls: int = 0
	var model_updates: int = 0
	func _substep(dt: float) -> void:
		solver_calls += 1
		super._substep(dt)
	func _update_models() -> void:
		model_updates += 1
		super._update_models()

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--gpu":gpu = true
		elif argument.begins_with("--output="):output = argument.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	var world := CountedWorld.new()
	var corpse := CountedCorpse.new()
	root.add_child(world)
	root.add_child(corpse)
	var feet := Vector3(8,9,8)
	var state: Dictionary = {"feet_position":feet,"yaw":0.0,"team":1,"player_id":7,"color":Color(.8,.3,.2),"velocity":Vector3(20,30,40),"impulse":Vector3(-40,30,-20)}
	corpse.setup_static(world,state)
	_check(corpse.is_static() and corpse._active and corpse._parts.size() == 1 and corpse._parts.has("Dead"), "Explicit static setup creates the original prone Dead model")
	_check(corpse.player_id == 7 and corpse.team == 1, "Static mode retains player/team metadata")
	_check(corpse.positions.is_empty() and corpse.velocities.is_empty() and corpse.last_positions.is_empty() and corpse.last_forces.is_empty(), "Static mode allocates no nine-point solver state")
	_check(corpse.solver_calls == 0 and corpse.model_updates == 0 and world.queries > 0 and world.queries <= 130, "Setup only performs bounded one-time floor placement")
	var dead: Node3D = corpse._parts.Dead
	var local_bounds: AABB = corpse._static_model_bounds(dead,Transform3D.IDENTITY)
	var placed_bounds: AABB = dead.transform*local_bounds
	_check(local_bounds == AABB(Vector3(-11.5,-2.5,-12),Vector3(23,6,25)), "Actual imported Dead GLB source bounds match audited asset")
	_check(placed_bounds.size.is_equal_approx(Vector3(2.3,.6,2.5)), "Static corpse is immediately horizontal rather than frozen standing")
	_check(is_equal_approx(placed_bounds.position.y,4.01), "Airborne death projects the bottom onto the floor once")
	_check(corpse.get_center().is_equal_approx(dead.transform*local_bounds.get_center()) and corpse._static_points.size() == 9, "Death camera and visibility samples follow the rendered body")
	_check(_tint(dead).is_equal_approx(state.color), "Original Dead model receives authority team color")
	var native_basis: Basis = CHARACTER.source_transform(Basis.IDENTITY.scaled(Vector3.ONE*.1),Vector3.ZERO).basis
	_check(dead.basis == native_basis, "Unrotated static mesh uses existing Character Dead mapped axes")
	var original_pose: Transform3D = dead.transform
	var original_center: Vector3 = corpse.get_center()
	var original_points: PackedVector3Array = corpse._static_points.duplicate()
	var queries: int = world.queries
	world.floor_enabled = false
	for frame: int in range(1000):
		corpse.step(.1)
		corpse.add_impulse(Vector3(10,20,30))
	_check(corpse.solver_calls == 0 and corpse.model_updates == 0 and world.queries == queries, "Repeated step/impulses perform zero solver, model or terrain work")
	_check(dead.transform == original_pose and corpse.get_center() == original_center and corpse._static_points == original_points and corpse.simulation_time == 0, "Static mode remains frozen after support removal and elapsed time")
	corpse.refresh_resources()
	_check(corpse._parts.size() == 1 and (corpse._parts.Dead as Node3D).transform == original_pose and corpse.get_center() == original_center and world.queries == queries, "Resource refresh preserves pose/center without terrain placement")
	_check(corpse.is_visible_from(Vector3(8,8,12)), "Static body supports existing visible soft-pruning")
	_check(not corpse.is_visible_from(corpse.get_center()+Vector3(0,0,151)), "Static mode retains source150-unit distance visibility limit")
	for x: int in range(32):
		for y: int in range(16):world.blocks[Vector3i(x,y,10)] = 1
	_check(not corpse.is_visible_from(Vector3(8,8,12)), "Opaque voxel wall occludes all static visibility samples")
	world.blocks.clear()
	world.floor_enabled = true
	state.feet_position = Vector3(8,4,8)
	state.yaw = PI*.5
	corpse.setup_static(world,state)
	dead = corpse._parts.Dead
	_check(dead.basis.is_equal_approx(Basis(Vector3.UP,PI*.5)*native_basis), "Static prone mesh respects captured yaw")
	var rotated_bounds: AABB = dead.transform*local_bounds
	_check(rotated_bounds.size.is_equal_approx(Vector3(2.5,.6,2.3)) and is_equal_approx(rotated_bounds.position.y,4.01), "Yaw keeps the body lying on its placement surface")
	corpse.clear()
	_check(not corpse.is_static() and not corpse._active and corpse._parts.is_empty() and corpse._static_points.is_empty(), "Clear releases static presentation and resets mode")
	corpse.setup(world,state)
	corpse.step(1.0/60.0)
	_check(not corpse.is_static() and corpse.positions.size() == 9 and corpse._parts.size() == 6 and corpse.solver_calls == 4, "Explicit legacy setup retains independent source solver and six models")
	corpse.clear()
	world.floor_enabled = false
	world.dimensions = Vector3i.ZERO # No finite world dimensions: no supporting map.
	state.feet_position = Vector3(8,4,8)
	# A separate missing query adapter proves the captured-position fallback.
	var empty := Node3D.new()
	corpse.setup_static(empty,state)
	_check(corpse._static_anchor == state.feet_position, "Missing terrain adapter retains captured feet placement")
	corpse.clear()
	state.feet_position = Vector3.INF
	corpse.setup_static(world,state)
	_check(not corpse._active and not corpse.is_static() and corpse._parts.is_empty(), "Invalid static pose fails closed without render/solver state")
	empty.free()
	corpse.free()
	world.free()
	await process_frame
	await process_frame
	if gpu:await _gpu_capture()
	MODELS.clear_cache()
	print("STATIC CORPSE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _gpu_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false,"Static GPU capture requires a real Compatibility renderer")
		return
	if output.is_empty():output = ProjectSettings.globalize_path("res://../.cache/previews/static-corpse")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1024,640)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := CountedWorld.new()
	stage.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.08,.1,.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24,24)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(12,4,12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.25,.3,.34)
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 55
	camera.position = Vector3(15,10,3)
	stage.add_child(camera)
	camera.look_at(Vector3(10,4.3,10))
	var empty: Image = await _capture("empty")
	var bodies: Array[OpenSpadesCorpse] = []
	for team: int in range(2):
		var corpse := CORPSE.new()
		stage.add_child(corpse)
		corpse.setup_static(world,{"feet_position":Vector3(8+team*4,7,10),"yaw":float(team)*.9,"team":team})
		bodies.append(corpse)
	var prone: Image = await _capture("prone-blue-green")
	var unchanged: Image = await _capture("prone-unchanged")
	_check(empty.get_data() != prone.get_data(),"Native GPU displays both original static Dead team bodies")
	_check(prone.get_data() == unchanged.get_data(),"Static body produces an identical later GPU frame without updates")
	for corpse: OpenSpadesCorpse in bodies:corpse.refresh_resources()
	var refreshed: Image = await _capture("prone-refreshed")
	_check(prone.get_data() == refreshed.get_data(),"Static resource refresh preserves actual GPU appearance")
	stage.free()
	await process_frame
	await process_frame

func _capture(name_value: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	rendered.save_png(output.path_join(name_value+".png"))
	return rendered

func _tint(node: Node) -> Color:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_surface_override_material(surface)
			if material is StandardMaterial3D and material.resource_name == "TeamColor":return (material as StandardMaterial3D).albedo_color
	for child: Node in node.get_children():
		var tint: Color = _tint(child)
		if tint.r >= 0:return tint
	return Color(-1,-1,-1,1)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)
