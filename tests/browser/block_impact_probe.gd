extends Node
## Separate actual-Main Web fixture; exported only by the opt-in probe helper.
const MAIN = preload("res://scenes/main.tscn")
const DURATION_SECONDS := 8.0
var app: Node3D
var report: Label
var busy := false
var running := false
var scenario := ""
var started_usec := 0
var last_frame_usec := 0
var starting_shots := 0
var starting_minimap_uploads := 0
var destroyed := 0
var collapsed := 0
var peak_draws := 0
var peak_dirty := 0
var blocked_physics_frames := 0
var fixed_position := Vector3.ZERO
var fixed_pitch := 0.0
var intervals: Array[float] = []
var starting_work: Dictionary = {}
var result: Dictionary = {}
var _run_callback: JavaScriptObject

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	app.hud.set_menu_visible(false)
	InputMap.action_erase_events("primary")
	app.world.blocks_changed.connect(_blocks_changed)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(12,110)
	panel.custom_minimum_size = Vector2(360,150)
	layer.add_child(panel)
	for item: Array in [["SMG into grounded wall: 8 seconds",run_lab],["SMG into original Title terrain: 8 seconds",run_title]]:
		var button := Button.new()
		button.text = item[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(item[1])
		panel.add_child(button)
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report.custom_minimum_size = Vector2(360,140)
	panel.add_child(report)
	report.text = "Actual Main ready. Terrain, effects and audio remain enabled."
	if OS.has_feature("web"):
		_run_callback = JavaScriptBridge.create_callback(_web_run)
		JavaScriptBridge.get_interface("window").blockImpactRun = _run_callback
		JavaScriptBridge.eval("""
			window.blockImpactProbeReady=true;
			const panel=document.createElement('section');panel.id='block-impact-controls';
			panel.style='position:absolute;top:6px;left:6px;z-index:10000;background:#111d;color:white;padding:8px;font:13px sans-serif';
			for(const spec of [['Run SMG wall','lab'],['Run SMG Title','title']]){
			 const b=document.createElement('button');b.textContent=spec[0];b.id='block-impact-'+spec[1];
			 b.onclick=()=>window.blockImpactRun(spec[1]);panel.appendChild(b);
			}
			const ready=document.createElement('span');ready.id='block-impact-status';ready.textContent=' Ready';panel.appendChild(ready);
			const output=document.createElement('pre');output.id='block-impact-result';
			output.style='position:absolute;bottom:0;left:0;z-index:10000;background:#000d;color:white;margin:0;padding:6px;max-width:100%;max-height:34%;overflow:auto;font:11px monospace';
			output.textContent='Ready: actual Main weapon impacts';document.body.append(panel,output);
		""",true)

func _web_run(args: Array) -> void:
	if args.is_empty():
		return
	if str(args[0]) == "lab":
		run_lab()
	elif str(args[0]) == "title":
		run_title()

func remove_targets() -> void:
	for target: Node3D in app._target_nodes:
		target.queue_free()
	app._target_nodes.clear()
	app.session.targets.clear()

func work() -> Dictionary:
	return app.world.get_rebuild_stats() if app.world.has_method("get_rebuild_stats") else {}

func status(text: String) -> void:
	report.text = text
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.getElementById('block-impact-status').textContent="+JSON.stringify(text),true)

func run_lab() -> void:
	if busy:
		return
	busy = true
	status("Preparing grounded wall…")
	app.effects.clear()
	app.world.clear_world(Vector3i(32,16,32))
	app.world.water_enabled = false
	app.world.data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	app.world.data.seed_box(Vector3i(4,4,1),Vector3i(28,12,15),0x01bf8051)
	app.world._mark_all_chunks()
	app.world.rebuild_now()
	app.session.reset_lab()
	remove_targets()
	app.player.respawn_at(Vector3(16.5,4.01,20.5))
	fixed_pitch = 0.0
	await warmup()
	start("grounded_wall")

func run_title() -> void:
	if busy:
		return
	busy = true
	status("Loading original Title map…")
	app.world.water_enabled = true
	app.hud.set_menu_visible(true)
	await app.load_original_map()
	app.hud.set_menu_visible(false)
	remove_targets()
	if app.world.dimensions != Vector3i(512,64,512):
		busy = false
		status("Title import failed")
		return
	app.world.rebuild_now()
	# Fixed aim into original ground keeps impacts comparable despite recoil.
	fixed_pitch = -0.6
	await warmup()
	start("Title.vxl")

func warmup() -> void:
	app.effects.clear()
	app.session.invulnerable = true
	app.session.unlimited_ammo = true
	app.session.select_weapon(1)
	app.session.select_tool(2)
	app.hud._focused = true
	app.hud._sync_controls()
	app.player.rotation.y = 0.0
	app.player.head.rotation.x = fixed_pitch
	for frame: int in 30:
		await get_tree().process_frame
	var deadline := Time.get_ticks_msec()+10000
	while not app.player.can_use_tool() and Time.get_ticks_msec()<deadline:
		app.player.controls_enabled = true
		await get_tree().process_frame

func start(name: String) -> void:
	scenario = name
	fixed_position = app.player.global_position
	starting_shots = app.session.shots_fired
	starting_minimap_uploads = app.hud._map.get_terrain_upload_count() if app.hud._map.has_method("get_terrain_upload_count") else 0
	starting_work = work()
	destroyed = 0
	collapsed = 0
	peak_draws = 0
	peak_dirty = 0
	blocked_physics_frames = 0
	intervals.clear()
	started_usec = Time.get_ticks_usec()
	last_frame_usec = started_usec
	seed(1389961)
	running = true
	status("Running "+name+" SMG for 8 seconds")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("delete window.blockImpactProbeResult;document.getElementById('block-impact-result').textContent='Running'",true)
	Input.action_press("primary")

func _physics_process(_delta: float) -> void:
	if not running:
		return
	# Tether and compensate recoil; firing still uses the actual controller/rules.
	# HTML controls can move focus away from the Godot canvas. The fixture owns
	# synthetic held input, so focus notifications must not retire that input.
	app.player.controls_enabled = true
	Input.action_press("primary")
	if not app.player.can_use_tool():
		blocked_physics_frames += 1
	app.player.global_position = fixed_position
	app.player.velocity = Vector3.ZERO
	app.player._native_velocity = Vector3.ZERO
	app.player.rotation.y = 0.0
	app.player.head.rotation.x = fixed_pitch

func _blocks_changed(changes: Array) -> void:
	if not running:
		return
	for change: Dictionary in changes:
		if int(change.before) != 0 and int(change.after) == 0:
			destroyed += 1
			if bool(change.collapsed):
				collapsed += 1

func _process(_delta: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	intervals.append(float(now-last_frame_usec)/1000.0)
	last_frame_usec = now
	peak_draws = maxi(peak_draws,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	peak_dirty = maxi(peak_dirty,int(app.world.get_stats().dirty_chunks))
	if float(now-started_usec)/1000000.0 >= DURATION_SECONDS:
		Input.action_release("primary")
		running = false
		finish()

func finish() -> void:
	var elapsed: float = float(Time.get_ticks_usec()-started_usec)/1000000.0
	intervals.sort()
	var final_work := work()
	var delta: Dictionary = {}
	for key: String in ["mesh_builds","collision_builds","color_updates","color_vertices","color_upload_bytes","build_cancellations"]:
		if starting_work.has(key) and final_work.has(key):
			delta[key] = int(final_work[key])-int(starting_work[key])
	result = {"scenario":scenario,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),
		"wall_seconds":elapsed,"frames":intervals.size(),"shots":app.session.shots_fired-starting_shots,
		"p50_frame_ms":intervals[int((intervals.size()-1)*0.5)],"p95_frame_ms":intervals[int((intervals.size()-1)*0.95)],
		"p99_frame_ms":intervals[int((intervals.size()-1)*0.99)],"max_frame_ms":intervals[-1],
		"frames_over_16_7ms":intervals.filter(func(value: float) -> bool:return value>16.7).size(),
		"frames_over_33_3ms":intervals.filter(func(value: float) -> bool:return value>33.3).size(),
		"destroyed_blocks":destroyed,"collapsed_blocks":collapsed,"peak_draw_calls":peak_draws,"peak_dirty_chunks":peak_dirty,
		"valid_impacts":app.session.shots_fired>starting_shots and destroyed>0,"blocked_physics_frames":blocked_physics_frames,
		"final_gate":{"controls":app.player.controls_enabled,"team":app.session.team,"health":app.session.health,"tool":app.session.current_tool,"can_use_tool":app.player.can_use_tool()},
		"minimap_uploads":(app.hud._map.get_terrain_upload_count()-starting_minimap_uploads) if app.hud._map.has_method("get_terrain_upload_count") else -1,
		"work_delta":delta,"final_work":final_work,"world":app.world.get_stats(),"effects":app.effects.stats(),
		"method":"Actual Main SMG, fixture-maintained held Primary and focus, tethered source aim, effects/audio enabled; wall-clock callback intervals, device/browser conditions apply"}
	busy = false
	status("Completed "+scenario+": "+str(result.shots)+" shots")
	report.text = JSON.stringify(result,"  ")
	print("BLOCK_IMPACT_WEB: "+JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.blockImpactProbeResult="+JSON.stringify(result)+";document.getElementById('block-impact-result').textContent=JSON.stringify(window.blockImpactProbeResult,null,2)",true)

func _exit_tree() -> void:
	Input.action_release("primary")
