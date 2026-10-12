extends SceneTree
## Exact batched-vs-immediate skin adoption and cache contracts. The opt-in
## component benchmark measures script work only, never whole-game FPS/GPU.
const CHARACTER = preload("res://presentation/character_view.gd")
const MODELS = preload("res://presentation/openspades_models.gd")
const HOTTRACK = preload("res://presentation/hottracked_player.gd")
const PALETTE = preload("res://ui/lab_palette.gd")
const PLAYER = preload("res://gameplay/player_controller.gd")
const MAP = preload("res://ui/lab_map.gd")
const SESSION = preload("res://gameplay/local_session.gd")
const WORLD = preload("res://world/voxel_world.gd")
var assertions: int = 0
var failures: int = 0
var benchmark: bool = false
var report_path: String = ""

class CountedCharacter extends CharacterView:
	var pose_publications: int = 0
	func _apply_pose() -> void:
		if _built and _pose_update_depth == 0:pose_publications += 1
		super._apply_pose()

class RecordedMap extends LabMap:
	var icon_points: Array[Vector2] = []
	func _draw() -> void:
		icon_points.clear()
		super._draw()
	func _draw_icon(_kind: String, point: Vector2, _color: Color, _yaw: float=0, _width: float=14) -> void:
		icon_points.append(point)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--benchmark":benchmark = true
		elif argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
	call_deferred("_run")

func _run() -> void:
	var immediate := CountedCharacter.new()
	var batched := CountedCharacter.new()
	root.add_child(immediate)
	root.add_child(batched)
	for frame: int in range(96):
		_adopt(immediate,frame,false)
		_adopt(batched,frame,true)
		_check(_snapshot(immediate) == _snapshot(batched), "Batched final transforms/visibility exactly match immediate frame %d" % frame)
	var before: int = batched.pose_publications
	var previous: Transform3D = batched._head.transform
	batched.begin_pose_update()
	batched.begin_pose_update()
	batched.set_aim(.74)
	batched.set_pose(false,false,false)
	batched.end_pose_update()
	_check(batched.pose_publications == before and batched._head.transform == previous, "Nested update publishes no intermediate pose")
	batched.end_pose_update()
	_check(batched.pose_publications == before+1 and batched._head.transform != previous, "Outermost end publishes the final pose once")
	batched.end_pose_update()
	_check(batched.pose_publications == before+1, "Unmatched end leaves immediate setter contract usable")
	batched.set_aim(.71)
	_check(batched.pose_publications == before+2, "Standalone setter still publishes immediately")
	batched.set_pose(true,true,false)
	batched.set_ragdoll_enabled(false)
	batched.position += Vector3(3,2,1)
	batched.begin_pose_update()
	batched.set_pose(true,true,false)
	batched.end_pose_update()
	_check(batched._corpse.global_position.is_equal_approx(batched.global_position+Vector3.DOWN*.3), "Repeated dead pose updates top-level corpse after global movement")
	batched.refresh_resources()
	_check(batched._pose_update_depth == 0 and is_instance_valid(batched._intel), "Resource refresh preserves completed transaction and carried intel")
	await _check_palette()
	await _check_minimap()
	var report: Dictionary = {"assertions":assertions,"failures":failures}
	if benchmark:
		# Stable resources/tool/team; all dynamic source animation inputs still
		# change each frame. Both modes use these exact same candidate setters.
		# Reset the separately exercised corpse/resource lifecycle checks first.
		_adopt(immediate,105,false)
		_adopt(batched,105,true)
		immediate.set_weapon(0,0)
		batched.set_weapon(0,0)
		# Let every replaced test mesh leave the tree before timing publication.
		await process_frame
		await process_frame
		for frame: int in range(200):
			_adopt_dynamic(immediate,frame,false)
			_adopt_dynamic(batched,frame,true)
		var samples: Array[Dictionary] = []
		for repeat: int in range(4):
			var first: CharacterView = immediate if repeat%2 == 0 else batched
			var second: CharacterView = batched if repeat%2 == 0 else immediate
			var start: int = Time.get_ticks_usec()
			for frame: int in range(3000):_adopt_dynamic(first,frame,first == batched)
			var middle: int = Time.get_ticks_usec()
			for frame: int in range(3000):_adopt_dynamic(second,frame,second == batched)
			var end: int = Time.get_ticks_usec()
			samples.append({"immediate_usec":middle-start if first == immediate else end-middle,
				"batched_usec":middle-start if first == batched else end-middle})
		report["character"] = {"frames_per_sample":3000,"samples":samples,"pose_matches":_snapshot(immediate) == _snapshot(batched)}
		var outline := HOTTRACK.new()
		root.add_child(outline)
		var parts: Array[String] = ["head","torso"]
		outline.show_pose(Vector3.ZERO,.2,false,.1,parts,Color(.1,.3,.8))
		var cached_start: int = Time.get_ticks_usec()
		for frame: int in range(10000):outline.show_pose(Vector3.ZERO,.2,false,.1,parts,Color(.1,.3,.8))
		var cached_end: int = Time.get_ticks_usec()
		var cached_uploads: int = outline.get_geometry_upload_count()
		var rebuild_start: int = Time.get_ticks_usec()
		for frame: int in range(10000):
			outline._pose_cache_valid = false
			outline.show_pose(Vector3.ZERO,.2,false,.1,parts,Color(.1,.3,.8))
		var rebuild_end: int = Time.get_ticks_usec()
		report["hottrack"] = {"frames":10000,"cached_usec":cached_end-cached_start,"rebuild_usec":rebuild_end-rebuild_start,
			"cached_uploads":cached_uploads,"total_uploads":outline.get_geometry_upload_count()}
		outline.free()
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report,"\t"))
			file.close()
	print("PRESENTATION OPTIMIZATION: %d assertions, %d failures" % [assertions,failures])
	if benchmark:print("PRESENTATION COMPONENT BENCHMARK: "+JSON.stringify(report))
	immediate.free()
	batched.free()
	await process_frame
	MODELS.clear_cache()
	quit(0 if failures == 0 else 1)

func _adopt(view: CharacterView, frame: int, batch: bool) -> void:
	view.position = Vector3(5+float(frame)*.031,.4,8)
	view.rotation = Vector3(.1,float(frame)*.021,.2)
	if batch:view.begin_pose_update()
	view.set_team(frame%2,Color(.2+float(frame%3)*.1,.4,.8))
	view.set_pose(frame%3 == 0,frame%5 == 0,frame%7 == 0)
	view.set_weapon(frame%3,frame%4)
	view.set_motion_state(float(frame%9)-4,float(frame%7)-3,float(frame)*.019)
	view.set_aim(sin(float(frame))*.8)
	view.set_ragdoll_enabled(frame%10 == 0)
	view.set_block_color(Color(.8,.1+float(frame%4)*.1,.3))
	view.set_tool_action(frame%4,float(frame%8)/7.0,float(frame%5),.7,.6)
	view.set_intel_carrier(frame%4 != 0,Color(.8,.3,.2))
	if batch:view.end_pose_update()

func _adopt_dynamic(view: CharacterView, frame: int, batch: bool) -> void:
	if batch:view.begin_pose_update()
	view.set_pose(frame%20 < 4,false,frame%30 < 8)
	view.set_motion_state(6,2,float(frame)*.019)
	view.set_aim(sin(float(frame)*.01)*.8)
	view.set_ragdoll_enabled(false)
	view.set_tool_action(frame%4,float(frame%8)/7.0,0,1,1)
	view.set_intel_carrier(false)
	if batch:view.end_pose_update()

func _snapshot(view: CharacterView) -> Array:
	# Immediate setters may move an invisible dead fallback before ragdoll is
	# enabled in the same frame. Only its final visible world pose is observable.
	var result: Array = [view._rig.position,view.visible,view._corpse.visible,
		view._corpse.global_transform if view._corpse.visible else Transform3D.IDENTITY]
	var nodes: Array[Node3D] = [view._torso,view._crouch_torso,view._head,view._arms,view._equipment]
	nodes.append_array(view._legs)
	nodes.append_array(view._crouch_legs)
	if is_instance_valid(view._intel):nodes.append(view._intel)
	for node: Node3D in nodes:
		result.append(node.transform)
		result.append(node.visible)
	return result

func _check_palette() -> void:
	var palette := PALETTE.new()
	var player := PLAYER.new()
	palette.player = player
	var colors: Array[Color] = PALETTE.palette_colors()
	for index: int in range(64):
		player.block_color = colors[index]
		_check(palette.get_selected_index() == index, "Cached native palette exact selected color %d" % index)
		_check(palette.get_selected_index() == index, "Unchanged native palette keeps selected color %d" % index)
	colors[0] = Color.WHITE
	_check(PALETTE.palette_colors()[0] != Color.WHITE and palette._colors[0] != Color.WHITE, "Public palette results remain independently owned")
	player.block_color = Color(.123,.234,.345)
	_check(palette.get_selected_index() == -1, "Non-palette block color preserves no-selection state")
	palette.move_selection(1)
	_check(palette.get_selected_index() == 4, "Unknown color retains source fallback stepping")
	var draw_count: Array[int] = [0]
	palette.draw.connect(func():draw_count[0] += 1)
	palette.size = Vector2(96,96)
	root.add_child(palette)
	palette.set_process(false)
	await process_frame
	await process_frame
	var before_draw: int = draw_count[0]
	_check(before_draw > 0 and palette._drawn_selected_index == 4, "Initial real CanvasItem draw adopts palette selection")
	for frame: int in range(12):
		palette._process(1.0/60.0)
		await process_frame
	_check(draw_count[0] == before_draw, "Unchanged palette retains drawing commands across render updates")
	player.block_color = palette._colors[17]
	palette._process(1.0/60.0)
	await process_frame
	await process_frame
	_check(draw_count[0] == before_draw+1 and palette._drawn_selected_index == 17, "Changed selection redraws on the next render boundary")
	palette.reload_resources()
	await process_frame
	await process_frame
	_check(draw_count[0] == before_draw+2, "Resource refresh explicitly redraws unchanged selection")
	palette.free()
	player.free()

func _check_minimap() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(32,8,32))
	var session := SESSION.new()
	session.health = 0
	for team: int in range(3):
		for alive: bool in [false,true]:
			var id: int = session.targets.size()
			session.targets.append({"id":id,"team":team,"alive":alive,"position":Vector3(3+id,4,8+id),"weapon":id%3,"yaw":float(id)*.1})
	var player := PLAYER.new()
	player.set_process(false)
	player.set_physics_process(false)
	var head := Node3D.new()
	head.name = "Head"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	var weapon := Node3D.new()
	weapon.name = "WeaponRoot"
	camera.add_child(weapon)
	head.add_child(camera)
	player.add_child(head)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	player.add_child(shape)
	root.add_child(player)
	player.position = Vector3(10,4,10)
	var map := RecordedMap.new()
	map.world = world
	map.player = player
	map.session = session
	map.size = Vector2(128,128)
	root.add_child(map)
	map.set_process(false)
	for team: int in range(3):
		session.team = team
		map.queue_redraw()
		await process_frame
		await process_frame
		var ids: Array[int] = map.get_visible_target_ids()
		_check(map.icon_points.size() == ids.size()+1, "Actual map icon eligibility matches public visible IDs for team %d" % team)
		for index: int in range(ids.size()):
			var point: Vector3 = session.targets[ids[index]].position
			_check(map.icon_points[index] == map.map_point(point), "Draw-local view mapping equals public mapping for target %d/team %d" % [ids[index],team])
	map.free()
	player.free()
	session.free()
	world.free()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)
