extends SceneTree
## Actual Compatibility camera-pose/FOV demo. Radial shader belongs to the owner.
const CAMERA = preload("res://presentation/source_camera_effects.gd")
var checks: int = 0
var failures: int = 0
var output: String = ""
var viewport: SubViewport
var view_camera: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SOURCE CAMERA GPU: " + message)

func capture(label: String) -> Image:
	for frame: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.save_png(output.path_join(label + ".png"))
	return image

func difference(a: Image, b: Image) -> float:
	var total: float = 0.0
	for y: int in range(a.get_height()):
		for x: int in range(a.get_width()):
			var ca: Color = a.get_pixel(x,y)
			var cb: Color = b.get_pixel(x,y)
			total += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
	return total / float(a.get_width()*a.get_height()*3)

func red_centroid(image: Image) -> Vector3:
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x,y)
			if color.r > 0.75 and color.g < 0.25 and color.b < 0.25:
				centroid += Vector2(x+0.5,y+0.5)
				count += 1
	if count > 0:
		centroid /= float(count)
	return Vector3(centroid.x,centroid.y,count)

func apply_sample(sample: Dictionary, owner_basis: Basis, zoomed_fov: float) -> void:
	view_camera.basis = owner_basis * sample.basis_delta
	view_camera.fov = CAMERA.apply_fov_degrees(zoomed_fov,float(sample.fov_scale))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Camera GPU demo requires a real graphics context")
		quit(1)
		return
	output = OS.get_cache_dir().path_join("blockfield-camera-effects")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(384,288)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04,0.06,0.08)
	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.environment = environment
	viewport.add_child(env_node)
	var positions: Array[Vector3] = [Vector3(-1.5,0.5,-8),Vector3(1.5,-0.5,-10),Vector3(0,0,-12)]
	var colors: Array[Color] = [Color(1,0.02,0.02),Color(0.02,1,0.02),Color(0.8,0.8,0.8)]
	for index: int in range(3):
		var marker: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(1.0,1.0) if index < 2 else Vector2(2.0,2.0)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colors[index]
		quad.material = material
		marker.mesh = quad
		marker.position = positions[index]
		viewport.add_child(marker)
	view_camera = Camera3D.new()
	view_camera.current = true
	view_camera.near = 0.025
	viewport.add_child(view_camera)
	var helper: RefCounted = CAMERA.new(7341)
	var owner_basis: Basis = Basis.from_euler(Vector3(0.08,0.14,-0.04))
	var neutral: Dictionary = helper.sample({"shake_level":0},10.0)
	apply_sample(neutral,owner_basis,68.0)
	var baseline: Image = await capture("01-neutral")
	var baseline_marker: Vector3 = red_centroid(baseline)
	check(baseline_marker.z > 100, "native fixture must render a visible red reference marker")
	var baseline_projection: Vector2 = view_camera.unproject_position(positions[0])
	check(Vector2(baseline_marker.x,baseline_marker.y).distance_to(baseline_projection) < 2.0, "real neutral framebuffer marker must agree with Camera3D projection")
	var widened: Dictionary = {"basis_delta":Basis.IDENTITY,"fov_scale":1.08}
	apply_sample(widened,owner_basis,68.0)
	var fov_only: Image = await capture("02-tangent-fov")
	var fov_marker: Vector3 = red_centroid(fov_only)
	check(difference(baseline,fov_only) > 0.001, "native tangent FOV modulation must visibly change the camera image")
	check(fov_marker.z < baseline_marker.z*0.92 and fov_marker.z > baseline_marker.z*0.78, "eight-percent tangent widening must reduce visible marker area by its expected perspective ratio")
	var grenade_input: Dictionary = {"first_person":false,"shake_level":1,"grenade_fast":0.4,"random_values":[0.9,0.1,0.7,0.4,0.6,0.2,0.1,0.9]}
	var grenade: Dictionary = helper.sample(grenade_input,10.0)
	apply_sample(grenade,owner_basis,68.0)
	var shaken: Image = await capture("03-native-grenade-pose")
	var shaken_marker: Vector3 = red_centroid(shaken)
	var shaken_projection: Vector2 = view_camera.unproject_position(positions[0])
	check(shaken_marker.z > 100 and Vector2(shaken_marker.x,shaken_marker.y).distance_to(shaken_projection) < 2.0, "canonical native local matrix must produce the expected rendered marker position")
	check(difference(fov_only,shaken) > 0.001 and Vector2(shaken_marker.x,shaken_marker.y).distance_to(Vector2(fov_marker.x,fov_marker.y)) > 3.0, "native angular shake must move rendered geometry independently of FOV widening")
	grenade_input.shake_level = 0
	apply_sample(helper.sample(grenade_input,10.0),owner_basis,68.0)
	var disabled: Image = await capture("04-shake-disabled")
	check(difference(baseline,disabled) == 0.0, "shake-level0 must restore the exact owner's image without accumulated camera drift")
	var metrics: Dictionary = {
		"renderer":RenderingServer.get_video_adapter_name(),"assertions":checks,"failures":failures,
		"fov_difference":difference(baseline,fov_only),"angular_difference":difference(fov_only,shaken),
		"baseline_marker":[baseline_marker.x,baseline_marker.y,baseline_marker.z],
		"fov_marker":[fov_marker.x,fov_marker.y,fov_marker.z],
		"shaken_marker":[shaken_marker.x,shaken_marker.y,shaken_marker.z],
		"projected_shaken":[shaken_projection.x,shaken_projection.y]
	}
	FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	print("SOURCE CAMERA GPU TESTS: %d assertions, %d failures; %s" % [checks,failures,output])
	print(JSON.stringify(metrics))
	viewport.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
