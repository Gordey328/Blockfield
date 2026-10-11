extends SceneTree
## Render and exercise a supplied native map in the actual Compatibility scene.
const MAIN = preload("res://scenes/main.tscn")
var app: Node3D
var output: String
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LOCAL MAP: "+label)

func frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame

func action(name: String, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func capture(filename: String) -> void:
	for frame: int in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK,"save "+filename)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.size() != 2:
		push_error("Usage: Godot --path game --script tools/render_local_map.gd -- MAP.bfmap OUTPUT_DIRECTORY; requires a graphics context")
		quit(1)
		return
	output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	app = MAIN.instantiate()
	root.add_child(app)
	await frames(3)
	app.world.render_radius = 12
	app._upload_kind = "map"
	await app._apply_upload(FileAccess.get_file_as_bytes(args[0]),args[0].get_file())
	check(not app._map_metadata.is_empty(),"actual Main adopts the supplied native map")
	if app._map_metadata.is_empty(): quit(1); return
	app.session.select_team(0)
	app.session.select_weapon(0)
	app.hud.set_menu_visible(false)
	app.world.rebuild_now()
	app.world.get_topdown_image()
	await frames(240)
	await capture("voxel-first-person.png")
	var start: Vector3 = app.player.global_position
	action("forward",true)
	await frames(60)
	action("forward",false)
	check(app.player.global_position.distance_to(start) > 0.5,"normal player input moves through source spawn lane")
	app.player.head.rotation.x = -0.9
	var sequence: int = app.world.data.map_sequence
	action("primary",true)
	await frames(100)
	action("primary",false)
	check(app.world.data.map_sequence > sequence,"normal rifle input destroys imported terrain")
	await app.reset_match()
	check(app.world.data.map_sequence == 0,"reset restores complete imported voxel baseline")
	app.world.rebuild_now()
	await frames(20)
	app.player.set_process(false)
	app.player.set_physics_process(false)
	app.hud.visible = false
	app.world_environment.environment.fog_enabled = false
	app.player._weapon_view.visible = false
	var center: Vector3 = Vector3(app.world.dimensions)*0.5
	app.player.camera.global_position = center+Vector3(140,155,145)
	app.player.camera.look_at(center-Vector3(0,12,0))
	app.player.camera.fov = 55
	app.player.camera.far = 700
	app.world.set_draw_distance(160)
	app.world.set_view_position(center)
	app.world.rebuild_now()
	# Inspector camera sits beyond the gameplay chunk fade distance. Disable
	# only the inspection scene's distance culling after all chunks are built.
	for mesh: Node in app.world.find_children("*","MeshInstance3D",true,false):
		mesh.visibility_range_begin = 0.0
		mesh.visibility_range_end = 0.0
	await capture("voxel-overview.png")
	print("LOCAL MAP GPU: %d checks, %d failures; map=%s spawn=%s" % [checks,failures,app.world.map_name,start])
	app.stop_audio()
	app.queue_free()
	await frames(3)
	quit(1 if failures else 0)
