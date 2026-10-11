extends Node
## Test-only actual Main Web fixture, outside the production export.
const MAIN = preload("res://scenes/main.tscn")
var app: Node3D
var report: Label
var operation: String = ""
var operation_id: int = 0
var callbacks: int = 0
var input_clicks: int = 0
var start_usec: int = 0
var last_frame_usec: int = 0
var frame_ms: Array[float] = []
var result: Dictionary = {}

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.hud.set_menu_visible(true)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(10,80)
	panel.custom_minimum_size = Vector2(350,280)
	layer.add_child(panel)
	for item: Array in [["Load original map",load_map],["Save coherent VXL",save_map],["Reset / cancel",reset_map],["Input responsiveness",touch_button],["Ambience cached / uncached",audio_compare],["Stage original VXL download",stage_download]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		panel.add_child(button)
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report.custom_minimum_size = Vector2(350,180)
	panel.add_child(report)
	report.text = "Actual Main ready; click load/save, then responsiveness while busy"
	if OS.has_feature("web"): JavaScriptBridge.eval("window.optimizationProbeReady=true",true)

func begin(kind: String) -> int:
	operation_id += 1
	operation = kind
	callbacks = 0
	input_clicks = 0
	frame_ms.clear()
	start_usec = Time.get_ticks_usec()
	last_frame_usec = start_usec
	if OS.has_feature("web"): JavaScriptBridge.eval("delete window.optimizationProbeResult",true)
	return operation_id

func load_map() -> void:
	var token: int = begin("load")
	await app.load_original_map()
	finish(token)

func save_map() -> void:
	var token: int = begin("save")
	await app.save_map()
	finish(token)

func reset_map() -> void:
	app.reset_lab()
	if not operation.is_empty(): finish(operation_id)

func stage_download() -> void:
	var token: int = begin("stage")
	var request: int = app._begin_vxl_request("Preparing download…")
	app._vxl_notice_caption = ""
	var bytes := FileAccess.get_file_as_bytes("res://assets/openspades/maps/Title.vxl")
	await app._show_web_export_incremental(bytes,"original-title.vxl","application/octet-stream",request)
	finish(token)

func touch_button() -> void:
	input_clicks += 1
	report.text = "Input processed while %s: %d clicks" % [operation,input_clicks]

func _process(_delta: float) -> void:
	if operation.is_empty(): return
	var now: int = Time.get_ticks_usec()
	callbacks += 1
	frame_ms.append(float(now-last_frame_usec)/1000.0)
	last_frame_usec = now
	var stats: Dictionary = app.world.get_vxl_job_stats()
	report.text = "%s: %.1f%%; UI frames %d; input clicks %d" % [operation,float(stats.get("progress",0.0))*100,callbacks,input_clicks]

func finish(token: int) -> void:
	if token != operation_id or operation.is_empty(): return
	var completion_usec: int = Time.get_ticks_usec()-start_usec
	# Include final adoption/export work and the following rendered callbacks.
	var tree: SceneTree = get_tree()
	for tail_frame: int in 3:
		await tree.process_frame
		if token != operation_id or operation.is_empty(): return
	frame_ms.sort()
	result = {"operation":operation,"operation_id":token,"wall_seconds":float(Time.get_ticks_usec()-start_usec)/1000000,
		"operation_completion_seconds":float(completion_usec)/1000000,"tail_frame_signals":3,
		"ui_frames":callbacks,"input_clicks":input_clicks,"job":app.world.get_vxl_job_stats(),
		"transfer":app._export_transfer_stats.duplicate(),
		"map":app.world.map_name,"memory_static":Performance.get_monitor(Performance.MEMORY_STATIC),
		"p50_frame_ms":frame_ms[int((frame_ms.size()-1)*.5)] if not frame_ms.is_empty() else 0,
		"p95_frame_ms":frame_ms[int((frame_ms.size()-1)*.95)] if not frame_ms.is_empty() else 0,
		"p99_frame_ms":frame_ms[int((frame_ms.size()-1)*.99)] if not frame_ms.is_empty() else 0,
		"max_frame_ms":frame_ms[-1] if not frame_ms.is_empty() else 0}
	operation = ""
	publish()

func audio_compare() -> void:
	if not operation.is_empty(): return
	var rows: Array[Dictionary] = []
	for enabled: bool in [false,true]:
		app.audio.ambience_cache_enabled = enabled
		app.audio.reset_environment()
		app.audio.reset_workload_counters()
		app.audio.set_workload_timing_enabled(true)
		for sample: int in 32: app.audio.compute_ambience(app.player.camera.global_position)
		rows.append(app.audio.debug_workload())
	app.audio.ambience_cache_enabled = true
	app.audio.set_workload_timing_enabled(false)
	result = {"operation":"audio","uncached":rows[0],"cached":rows[1]}
	publish()

func publish() -> void:
	report.text = JSON.stringify(result,"  ")
	print("OPTIMIZATION_WEB: " + JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.optimizationProbeResult="+JSON.stringify(result),true)
