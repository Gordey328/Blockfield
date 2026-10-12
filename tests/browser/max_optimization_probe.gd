extends Node
## Same wrappers/workload for both sources. CPU timings include diagnostic cost.
const MAIN = preload("res://scenes/main.tscn")
const TDM = preload("res://scenes/offline_tdm.tscn")
const RECORDER = preload("res://__probe/recorder.gd")
var app: Node3D
var busy: bool = false
var status: Label
var frames: Array[float] = []
var measuring: bool = false
var peak_draws: int = 0
var callback: JavaScriptObject

func _ready() -> void:
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.layer = 30
	add_child(overlay)
	status = Label.new()
	status.position = Vector2(12,100)
	status.add_theme_color_override("font_color",Color.WHITE)
	status.add_theme_color_override("font_outline_color",Color.BLACK)
	status.add_theme_constant_override("outline_size",5)
	overlay.add_child(status)
	_set_status("Ready: identical Main, unchanged graphics, 3 × 10s measured samples")
	if OS.has_feature("web"):
		callback = JavaScriptBridge.create_callback(_web_run)
		JavaScriptBridge.get_interface("window").maxoptRun = callback
		JavaScriptBridge.eval("""
		const p=document.createElement('section');p.style='position:absolute;top:4px;left:4px;z-index:10000;background:#111d;color:white;padding:8px';
		for(const name of ['lab','tdm','title']){const b=document.createElement('button');b.textContent='Measure '+name;b.onclick=()=>window.maxoptRun(name);p.appendChild(b)}
		const s=document.createElement('span');s.id='maxopt-status';p.appendChild(s);document.body.appendChild(p);window.maxoptReady=true;
		""",true)

func _web_run(args: Array) -> void:
	if not busy and not args.is_empty(): run(str(args[0]))

func _set_status(value: String) -> void:
	status.text = value
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var s=document.getElementById('maxopt-status');if(s)s.textContent="+JSON.stringify(value),true)

func _process(delta: float) -> void:
	if not measuring: return
	frames.append(delta*1000.0)
	peak_draws = maxi(peak_draws,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

func run(kind: String) -> void:
	if kind not in ["lab","tdm","title"]: return
	busy = true
	RECORDER.enabled = false
	if is_instance_valid(app):
		app.queue_free()
		await get_tree().process_frame
	seed(1389961)
	app = (TDM if kind=="tdm" else MAIN).instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	app.hud.set_menu_visible(true)
	if kind=="title": await app.load_original_map()
	app.hud.set_menu_visible(false)
	app.hud._focused = true
	app.hud._sync_controls()
	app.session.invulnerable = true
	app.session.unlimited_ammo = true
	_set_status("Preparing "+kind+"; terrain and materials warm outside timings")
	var deadline: int = Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if app.world._dirty.is_empty() and app.world._active_chunk==null and bool(app.world.get_visual_preparation_stats().ready): break
	if not app.world._dirty.is_empty() or app.world._active_chunk!=null:
		_set_status("Preparation failed")
		busy = false
		return
	await get_tree().create_timer(5.0).timeout
	var rows: Array[Dictionary] = []
	for repeat: int in 3:
		frames.clear()
		peak_draws = 0
		_set_status("Measuring "+kind+" sample "+str(repeat+1)+" / 3")
		RECORDER.reset()
		measuring = true
		var started: int = Time.get_ticks_usec()
		await get_tree().create_timer(10.0).timeout
		measuring = false
		RECORDER.enabled = false
		frames.sort()
		rows.append({"wall_usec":Time.get_ticks_usec()-started,"frames":frames.size(),
			"p50_frame_ms":frames[int((frames.size()-1)*.5)],"p95_frame_ms":frames[int((frames.size()-1)*.95)],
			"p99_frame_ms":frames[int((frames.size()-1)*.99)],"max_frame_ms":frames[-1],
			"peak_draw_calls":peak_draws,"cpu":RECORDER.snapshot(),"memory_static":Performance.get_monitor(Performance.MEMORY_STATIC)})
		rows[-1]["corpses"] = app._corpses.size()
	var result: Dictionary = {"scenario":kind,"engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_video_adapter_name(),"graphics":app.get_graphics_options(),"samples":rows,
		"actors":app.session.targets.size(),"network_client_created":app.network_client!=null,
		"method":"Actual Main rendered Web, same diagnostic wrappers, 5s warmup then three10s samples; no physical-phone or universal FPS acceptance"}
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.maxoptResult="+JSON.stringify(result),true)
	print("MAXOPT_WEB: "+JSON.stringify(result))
	_set_status("Complete "+kind+"; result in window.maxoptResult")
	app.hud.set_menu_visible(true)
	busy = false
