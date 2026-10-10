extends SceneTree
## Standalone source geometry/lifecycle checks. Add -- --gpu for real GL depth proof.
const Hottrack = preload("res://presentation/hottracked_player.gd")
const HITS = preload("res://gameplay/lab_hit_volumes.gd")
var checks := 0
var failures := 0
var output := ""
var gpu := false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--gpu": gpu = true
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	var parent := Node3D.new()
	parent.position = Vector3(90,80,70)
	parent.rotation = Vector3(.2,.5,.3)
	root.add_child(parent)
	var view := Hottrack.new()
	parent.add_child(view)
	_check(not view.visible and view.get_child_count() == 0, "New helper is hidden and has no empty renderer nodes")
	var feet := Vector3(3,4,5)
	var team := Color(.08,.67,.24,.1)
	_check(view.show_pose(feet,0,false,0,["head","torso"],team), "Standing source pose accepted")
	_check(view.visible and view.get_child_count() == 1, "One bounded renderer node")
	_check(view.global_transform.is_equal_approx(Transform3D.IDENTITY), "World-space hitboxes ignore transformed parent")
	var mesh := view._instance.mesh as ArrayMesh
	var mesh_id := mesh.get_instance_id()
	_check(mesh.get_surface_count() == 1 and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES, "One native line surface")
	_check(view._instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and view._instance.layers == 1, "Debug lines do not cast shadows or use first-person layer")
	_check("depth_test_disabled" not in Hottrack.LINE_SHADER and "depth_draw_opaque" in Hottrack.LINE_SHADER and "ALPHA" not in Hottrack.LINE_SHADER, "Opaque normal depth testing, no xray or alpha blending")
	_check("unshaded" in Hottrack.LINE_SHADER and "fog_disabled" in Hottrack.LINE_SHADER, "Basic source colors are unlit and unfogged")
	var vertices := view.get_line_vertices()
	_check(vertices.size() == 120 and view.get_line_colors().size() == 120, "Five boxes have exactly sixty segments")
	# Independent numeric Player::GetHitBoxes goldens in mapped world axes.
	var standing_bounds: Array[AABB] = [
		AABB(Vector3(-.3,2.05,-.3),Vector3(.6,.6,.6)),
		AABB(Vector3(-.4,1.15,-.15),Vector3(.8,.9,.3)),
		AABB(Vector3(-.4,.05,-.15),Vector3(.3,1,.3)),
		AABB(Vector3(.1,.05,-.15),Vector3(.3,1,.3)),
		AABB(Vector3(-.6,1.15,-.15),Vector3(1.2,.9,.3)),
	]
	_check_bounds(vertices,feet,standing_bounds)
	_check_colors(view.get_line_colors(),[true,true,false,false,false],team)
	_check((vertices[1]-vertices[0]).is_equal_approx(Vector3(.6,0,0)), "First source edge changes native X")
	_check((vertices[9]-vertices[8]).is_equal_approx(Vector3(0,0,.6)), "Fifth source edge changes native Y")
	_check((vertices[17]-vertices[16]).is_equal_approx(Vector3(0,-.6,0)), "Ninth source edge changes native Z-down")
	_check(view.show_pose(feet,0,true,0,["legs","arms"],team), "Crouched pose accepted")
	var crouched_bounds: Array[AABB] = [
		AABB(Vector3(-.3,1.15,-.3),Vector3(.6,.6,.6)),
		AABB(Vector3(-.4,.6,-.15),Vector3(.8,.6,.8)),
		AABB(Vector3(-.4,0,-.15),Vector3(.3,.5,.3)),
		AABB(Vector3(.1,0,-.15),Vector3(.3,.5,.3)),
		AABB(Vector3(-.6,.6,-.15),Vector3(1.2,.6,.3)),
	]
	_check_bounds(view.get_line_vertices(),feet,crouched_bounds)
	_check_colors(view.get_line_colors(),[false,false,true,true,true],team)
	var pitch := .72
	var yaw := -1.13
	view.show_pose(feet,yaw,false,pitch,["head"],team)
	var native_y := cos(pitch)*(-.3)-sin(pitch)*(-.5-.1)
	var native_z := sin(pitch)*(-.3)+cos(pitch)*(-.5-.1)+.1
	var mapped := Vector3(-.3,2.15-native_z,native_y)
	var expected := feet+Vector3(cos(yaw)*mapped.x+sin(yaw)*mapped.z,mapped.y,-sin(yaw)*mapped.x+cos(yaw)*mapped.z)
	_check(view.get_line_vertices()[0].distance_to(expected) < .00001, "Independent source head pivot/pitch/yaw golden")
	for crouching: bool in [false,true]:
		for sample in range(24):
			var angle := float(sample)*TAU/24-PI
			var tilt := sin(float(sample))*.95
			var parts: Array[String] = []
			if sample%2 == 0: parts.assign(["head","legs"])
			else: parts.assign(["arms"])
			view.show_pose(feet,angle,crouching,tilt,parts,team)
			var direct := view.get_line_vertices()
			_check(view.show_prepared(HITS.prepare_pose(feet,angle,crouching,tilt),parts,team), "Prepared pose accepted")
			var prepared := view.get_line_vertices()
			for index in range(120):
				_check(direct[index].distance_to(prepared[index]) < .00001, "Prepared inverse round-trip preserves source endpoints")
	var copied := view.get_line_vertices()
	copied[0] = Vector3.INF
	_check(view.get_line_vertices()[0].is_finite(), "Inspection returns owned geometry copies")
	var copied_colors := view.get_line_colors()
	copied_colors[0] = Color.MAGENTA
	_check(view.get_line_colors()[0] != Color.MAGENTA, "Inspection returns owned color copies")
	for frame in range(200):
		view.show_pose(feet,float(frame)*.01,frame%2 == 0,0,["torso"],team)
	_check(view.get_child_count() == 1 and view._instance.mesh.get_instance_id() == mesh_id and mesh.get_surface_count() == 1, "Repeated frames reuse one node/mesh/surface without growth")
	view.hide_target()
	_check(not view.visible and mesh.get_surface_count() == 1, "Target loss hides retained bounded geometry")
	view.clear()
	_check(not view.visible and mesh.get_surface_count() == 0 and view.get_line_vertices().is_empty(), "Clear releases current geometry")
	_check(not view.show_pose(Vector3.INF,0,false,0,[],team) and not view.visible, "Nonfinite pose fails closed")
	_check(not view.show_pose(feet,NAN,false,0,[],team), "Nonfinite yaw rejected")
	_check(not view.show_pose(feet,0,false,INF,[],team), "Nonfinite pitch rejected")
	_check(not view.show_pose(feet,0,false,0,["unknown"],team), "Unknown hit tags fail closed")
	_check(not view.show_pose(feet,0,false,0,["head","head","head","head","head"],team), "Unbounded hit tags rejected")
	_check(not view.show_pose(feet,0,false,0,[],Color(NAN,0,0)), "Nonfinite team color rejected")
	_check(not view.show_prepared(null,[],team), "Null prepared pose fails closed")
	view.show_pose(feet,0,false,0,[],team)
	var renderer_id := view._instance.get_instance_id()
	parent.remove_child(view)
	_check(not view.visible and view._mesh == null and view._material == null and view._instance.mesh == null, "Tree exit releases renderer resources")
	parent.add_child(view)
	_check(view.show_pose(feet,0,false,0,["legs"],team) and view._instance.get_instance_id() == renderer_id, "Tree re-entry recreates resources without adding nodes")
	view.free()
	mesh = null
	parent.free()
	await process_frame
	if gpu:
		await _gpu_checks()
	print("HOTTRACK_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _check_bounds(vertices: PackedVector3Array, feet: Vector3, goldens: Array[AABB]) -> void:
	for volume in range(5):
		var actual := AABB(vertices[volume*24]-feet,Vector3.ZERO)
		for endpoint in range(24):
			actual = actual.expand(vertices[volume*24+endpoint]-feet)
		_check(actual.position.distance_to(goldens[volume].position) < .00001 and actual.size.distance_to(goldens[volume].size) < .00001, "Independent source bounds for volume %d" % volume)
		var edges: Dictionary = {}
		for edge in range(12):
			var first := vertices[volume*24+edge*2]
			var second := vertices[volume*24+edge*2+1]
			_check(first.distance_to(second) > .00001, "Box edges never degenerate")
			edges[str(first)+":"+str(second)] = true
		_check(edges.size() == 12, "Twelve distinct edges per source box")

func _check_colors(colors: PackedColorArray, white: Array[bool], team: Color) -> void:
	for volume in range(5):
		var expected := Color.WHITE if white[volume] else Color(team.r,team.g,team.b,1)
		for endpoint in range(24):
			_check(colors[volume*24+endpoint].is_equal_approx(expected), "White hit tags/team remaining, always opaque")

func _gpu_checks() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "GPU mode requires a real Compatibility display driver")
		return
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../.cache/previews/hottracked-player")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.03,.04,.05)
	stage.add_child(env)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,1.35,5)
	camera.look_at(Vector3(0,1.35,0))
	camera.current = true
	var view := Hottrack.new()
	stage.add_child(view)
	view.show_pose(Vector3.ZERO,0,false,0,["head"],Color(0,1,0))
	var lines := await _capture(viewport,"standing")
	var line_count := _bright_pixels(lines)
	_check(line_count.green > 100 and line_count.white > 50, "Actual GPU shows team body edges and white head edges")
	view.show_pose(Vector3.ZERO,.63,true,.48,["legs","arms"],Color(.1,.2,1))
	var crouched := await _capture(viewport,"crouch-pitch")
	_check(_different_pixels(lines,crouched) > 150, "Actual crouch/yaw/pitch changes projected source outline")
	view.show_pose(Vector3.ZERO,0,false,0,["head"],Color(0,1,0))
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4,4,.2)
	wall.mesh = box
	wall.position = Vector3(0,1.35,2)
	var wall_material := StandardMaterial3D.new()
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_material.albedo_color = Color(.08,.08,.08)
	wall.material_override = wall_material
	stage.add_child(wall)
	var blocked := await _capture(viewport,"wall-occluded")
	var blocked_count := _bright_pixels(blocked)
	_check(blocked_count.green == 0 and blocked_count.white == 0, "Opaque world geometry depth-occludes every hitbox edge")
	wall.position.z = -2
	var behind := await _capture(viewport,"wall-behind")
	var behind_count := _bright_pixels(behind)
	_check(behind_count.green > 100 and behind_count.white > 50, "A wall behind the actor preserves foreground outlines")
	view.hide_target()
	var hidden := await _capture(viewport,"hidden")
	var hidden_count := _bright_pixels(hidden)
	_check(hidden_count.green == 0 and hidden_count.white == 0, "Hidden target produces no GPU outline")
	var report := {"assertions":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"visible":line_count,"occluded":blocked_count,"foreground":behind_count,"hidden":hidden_count}
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	viewport.free()
	await process_frame
	await process_frame

func _capture(viewport: SubViewport, name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(output.path_join(name+".png"))
	return image

func _bright_pixels(image: Image) -> Dictionary:
	var green := 0
	var white := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x,y)
			if color.g > .75 and color.r < .3 and color.b < .3: green += 1
			if minf(color.r,minf(color.g,color.b)) > .8: white += 1
	return {"green":green,"white":white}

func _different_pixels(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .2: changed += 1
	return changed

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
