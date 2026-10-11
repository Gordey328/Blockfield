extends SceneTree
## Actual Main lifecycle: private loading, reset cancellation and coherent save UI.
const MAIN = preload("res://scenes/main.tscn")
var checks: int = 0
var failures: int = 0
var app: Node3D
var map_notifications: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("VXL MAIN: " + label)

func frames(count: int) -> void:
	for index: int in count: await process_frame

func wait_idle() -> int:
	var count := 0
	var deadline := Time.get_ticks_msec()+30000
	while bool(app.world.get_vxl_job_stats().get("active",false)) and Time.get_ticks_msec() < deadline:
		await process_frame
		count += 1
	await frames(2)
	check(not bool(app.world.get_vxl_job_stats().get("active",false)),"operation finishes within real-time bound")
	return count

func run() -> void:
	app = MAIN.instantiate()
	root.add_child(app)
	await frames(3)
	app.hud.set_menu_visible(true)
	check(app._vxl_work_budget() == Vector2i(4096,8000),"menu operations use bounded foreground budget")
	app.hud.set_menu_visible(false)
	check(app._vxl_work_budget() == Vector2i(1024,2000),"live gameplay operations retain narrow budget")
	app.hud.set_menu_visible(true)
	var previous: VoxelData = app.world.data
	app.load_original_map()
	check(app.world.data == previous,"Main retains old authority while decode is private")
	check(bool(app.world.get_vxl_job_stats().get("active",false)),"Main starts incremental load")
	app.reset_lab()
	await frames(3)
	check(app.world.dimensions == Vector3i(96,32,96) and app._map_baseline.is_empty(),"reset cancels pending original-map adoption and baseline")
	check(app._vxl_notice_caption.is_empty(),"cancelled load cannot restore progress notice")
	app.world.map_loaded.connect(func(_name: String) -> void: map_notifications += 1)
	var before_epoch: int = app.world.data.epoch
	app.load_original_map()
	app.load_original_map()
	var loading_frames: int = await wait_idle()
	check(loading_frames > 2,"original decode yields multiple UI frames")
	check(app.world.dimensions == VXLReader.SIZE and app._map_baseline_name == "Title.vxl","completed Main load atomically installs original map and reset baseline")
	check(map_notifications == 1 and app.world.data.epoch == before_epoch+1,"superseded Main load has no stale adoption or notification")
	check(app.session.health == 100 and app.session.targets.size() == 6,"completed map load initializes actual offline rules once")
	var installed: VoxelData = app.world.data
	app._upload_kind = "map"
	app._apply_upload(PackedByteArray([0,0,0]),"broken.vxl")
	await wait_idle()
	check(app.world.data == installed and app._map_baseline_name == "Title.vxl","malformed upload keeps installed authority and valid baseline")
	app.save_map()
	check(bool(app.world.get_vxl_job_stats().get("active",false)),"Main starts incremental save")
	app.reset_lab()
	await frames(3)
	check(app._vxl_notice_caption.is_empty() and not app._export_pending,"reset suppresses cancelled save completion/download")
	app.load_original_map()
	check(bool(app.world.get_vxl_job_stats().get("active",false)),"scene exit fixture has a pending actual Main load")
	app.stop_audio()
	app.queue_free()
	await frames(4)
	check(not is_instance_valid(app),"scene exit disposes pending Main without later completion")
	# Playback references drain in real mixer time, independently of fixed-fps.
	var drain := Time.get_ticks_msec()+200
	while Time.get_ticks_msec() < drain:
		OS.delay_msec(1)
		await process_frame
	print("VXL MAIN TESTS: %d checks, %d failures; load_process_frames=%d" % [checks,failures,loading_frames])
	quit(1 if failures else 0)
