extends Node3D
## Private diagnostic scene. Real terrain/mesh work; decorative saturation is
## explicitly separate from weapon authority and ordinary-game acceptance.
const DATA = preload("res://world/voxel_data.gd")
const TERRAIN = preload("res://world/arsenal_terrain.gd")
const WORLD = preload("res://world/voxel_world.gd")
const VIEW = preload("res://presentation/arsenal_view.gd")
const EFFECTS = preload("res://presentation/openspades_effects.gd")
const ROOF_CELLS: int = 24576
const MAX_STEP_SAMPLES: int = 512
const MAX_FRAME_SAMPLES: int = 1200
const MAX_PAUSE_SAMPLES: int = 32
const UPSTREAM: String = "dcf449c845d509bbde9d79239b32d201c1389961"
@export var source_hint: String = "Record source revision separately"
var world: VoxelWorld
var data: VoxelData
var terrain: RefCounted
var camera: Camera3D
var view: ArsenalView
var effects: OpenSpadesEffects
var _label: Label
var _status: Label
var _start_button: Button
var _pause_button: Button
var _download_button: Button
var _saturation_box: CheckBox
var _epoch: int = 0
var _tick: int = 0
var _running: bool = false
var _paused: bool = false
var _authority_complete: bool = false
var _render_complete: bool = false
var _effects_ready: bool = false
var _began_us: int = 0
var _authority_done_us: int = 0
var _ended_us: int = 0
var _authority_total_us: int = 0
var _authority_max_us: int = 0
var _presentation_total_us: int = 0
var _presentation_max_us: int = 0
var _frames: int = 0
var _last_frame_us: int = 0
var _roof_removed: int = 0
var _total_removed: int = 0
var _max_particles: int = 0
var _max_view_states: int = 0
var _max_view_events: int = 0
var _saturation: bool = false
var _step_rows: Array[Dictionary] = []
var _frame_rows: Array[Dictionary] = []
var _pause_rows: Array[Dictionary] = []
var _failures: Array[String] = []
var _decorations: Array[Dictionary] = []
var _last_report: Dictionary = {}
var _ui_age: float = 0.0

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	_build_scene()
	_build_ui()
	reset_fixture()
	_warm_effects.call_deferred()

func _build_scene() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("172332")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c4d4e3")
	environment.environment.ambient_light_energy = .7
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = false
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(108, 62, 108)
	camera.far = 300
	camera.fov = 58
	add_child(camera)
	camera.look_at(Vector3(40, 7, 40))
	camera.current = true
	world = WORLD.new()
	world.bootstrap_lab = false
	add_child(world)
	world.set_water_enabled(false)
	world.set_draw_distance(160)
	view = VIEW.new()
	add_child(view)
	view.configure(camera)
	effects = EFFECTS.new()
	add_child(effects)
	effects.setup(world, camera, true)
	effects.quality = 1
	effects.max_particles = 50
	effects.set_process(false)

func _warm_effects() -> void:
	await effects.prewarm_async()
	if not is_inside_tree(): return
	effects.rng.seed = 7341
	_effects_ready = true
	_refresh_ui()

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size.x = 560
	layer.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading: Label = Label.new()
	heading.text = "Private Web benchmark · real 24,576-cell collapse"
	heading.add_theme_font_size_override("font_size", 19)
	column.add_child(heading)
	var note: Label = Label.new()
	note.text = "CPU steps are measured separately from rendered frame intervals.\nPause freezes helper/effects; already queued terrain meshes may finish.\nDecorative saturation exercises real bounded view/one particle pool."
	note.add_theme_font_size_override("font_size", 13)
	column.add_child(note)
	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	_start_button = _button(buttons, "Start benchmark", start_benchmark)
	_pause_button = _button(buttons, "Pause", toggle_pause)
	_button(buttons, "Reset", reset_fixture)
	_download_button = _button(buttons, "Download JSON", download_report)
	_saturation_box = CheckBox.new()
	_saturation_box.text = "Also saturate decorative presentation (64 states / 12 events / 50 particles)"
	column.add_child(_saturation_box)
	_status = Label.new()
	column.add_child(_status)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_label)

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.custom_minimum_size.y = 44
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func reset_fixture() -> void:
	if _began_us > 0: _last_report = report()
	_running = false
	_paused = false
	_authority_complete = false
	_render_complete = false
	if terrain != null: terrain.dispose()
	effects.clear()
	effects.set_process(false)
	view.clear()
	_epoch += 1
	data = DATA.new()
	data.clear(Vector3i(80,20,80), _epoch)
	data.seed_box(Vector3i.ZERO, Vector3i(80,2,80), 0x0174694e)
	data.seed_box(Vector3i(40,2,40), Vector3i(41,8,41), 0x01dd9944)
	data.seed_box(Vector3i(8,8,8), Vector3i(72,14,72), 0x0188b7df)
	terrain = TERRAIN.new()
	terrain.configure(data)
	world.set_map_data(data, "24,576-cell supported roof", true, Vector3(40.5,2.01,40.5))
	world.set_view_position(camera.global_position)
	_tick = 0
	_began_us = 0
	_authority_done_us = 0
	_ended_us = 0
	_authority_total_us = 0
	_authority_max_us = 0
	_presentation_total_us = 0
	_presentation_max_us = 0
	_frames = 0
	_last_frame_us = 0
	_roof_removed = 0
	_total_removed = 0
	_max_particles = 0
	_max_view_states = 0
	_max_view_events = 0
	_step_rows.clear()
	_frame_rows.clear()
	_pause_rows.clear()
	_failures.clear()
	_decorations.clear()
	_refresh_ui()

func _mesh_ready() -> bool:
	var rebuild: Dictionary = world.get_rebuild_stats()
	return bool(world.get_visual_preparation_stats().ready) and int(rebuild.pending_chunks) == 0 and not bool(rebuild.active_build)

func start_benchmark() -> void:
	if _running or _began_us > 0 or not _mesh_ready() or not _effects_ready: return
	var cut: Array[Vector3i] = [Vector3i(40,4,40)]
	var accepted: Dictionary = terrain.queue_remove(cut, {"tick":0,"actor_id":1,"action_id":1})
	if not accepted.ok:
		_failure("Start rejected: " + str(accepted.error))
		return
	_saturation = _saturation_box.button_pressed
	_running = true
	_began_us = Time.get_ticks_usec()
	_last_frame_us = _began_us
	if _saturation:
		for index: int in 96:
			_decorations.append({"id":"decoration_%03d" % index,"item":"x%02d" % (index%20+1),"kind":"warning","warning":true,"position":Vector3(10+index%12*5,15,10+index/12*6),"direction":Vector3.DOWN,"radius":1.0,"remaining":5.0,"seconds":5.0,"progress":0.0})
		effects.set_process(true)
	_refresh_ui()

func toggle_pause() -> void:
	if not _running: return
	_paused = not _paused
	effects.set_process(_saturation and not _paused)
	if _pause_rows.size() < MAX_PAUSE_SAMPLES:
		_pause_rows.append({"tick":_tick,"frame":_frames,"paused":_paused,"roof_removed":_roof_removed,"wall_usec":Time.get_ticks_usec()-_began_us})
	_refresh_ui()

func _physics_process(_delta: float) -> void:
	if not _running or _paused or _authority_complete: return
	_tick += 1
	var before: int = Time.get_ticks_usec()
	terrain.step(_tick)
	var authority_us: int = Time.get_ticks_usec() - before
	_authority_total_us += authority_us
	_authority_max_us = maxi(_authority_max_us, authority_us)
	var changes: int = 0
	before = Time.get_ticks_usec()
	for receipt: Dictionary in terrain.drain_transactions():
		changes += receipt.changes.size()
		for change: Dictionary in receipt.changes:
			if int(change.after) == 0:
				_total_removed += 1
				var cell: Vector3i = change.cell
				if cell.y >= 8 and cell.y < 14 and cell.x >= 8 and cell.x < 72 and cell.z >= 8 and cell.z < 72: _roof_removed += 1
		world._present_transaction(receipt)
	var presentation_us: int = Time.get_ticks_usec() - before
	_presentation_total_us += presentation_us
	_presentation_max_us = maxi(_presentation_max_us, presentation_us)
	var diagnostics: Dictionary = terrain.get_diagnostics()
	if int(diagnostics.last_work) > 512 or changes > 256: _failure("Fixed-step cell budget exceeded")
	if not str(diagnostics.error).is_empty(): _failure(str(diagnostics.error))
	if _step_rows.size() < MAX_STEP_SAMPLES:
		_step_rows.append({"tick":_tick,"frame":_frames,"wall_usec":Time.get_ticks_usec()-_began_us,"work_cells":int(diagnostics.last_work),"changed_cells":changes,"roof_removed":_roof_removed,"authority_usec":authority_us,"receipt_presentation_usec":presentation_us,"phase":str(diagnostics.phase),"jobs":int(diagnostics.jobs),"guard_cells":int(diagnostics.guard_cells)})
	if not terrain.has_pending():
		_authority_complete = true
		_authority_done_us = Time.get_ticks_usec()
		if _roof_removed != ROOF_CELLS or _total_removed != ROOF_CELLS+4 or data.get_block(Vector3i(60,12,60)) != 0 or data.get_block(Vector3i(40,3,40)) == 0:
			_failure("Canonical collapse completion differs from the native fixture")

func _process(delta: float) -> void:
	if _running:
		var now: int = Time.get_ticks_usec()
		var interval: int = now - _last_frame_us
		_last_frame_us = now
		_frames += 1
		if _saturation and not _paused:
			var events: Array[Dictionary] = []
			if _frames % 8 == 1:
				for index: int in 32:
					events.append({"id":"burst_%d_%d" % [_frames,index],"item":"x16","type":"explosion","position":Vector3(12+index%8*7,16,12+index/8*10),"radius":1.4,"remaining":.1})
				for index: int in 8: effects.grenade_explosion(Vector3(15+index*6,16,40))
			view.present(events,_decorations)
			view.update_readout({"selected_item":"source","enabled":true},delta)
		var view_stats: Dictionary = view.get_display_state()
		var pool_stats: Dictionary = effects.stats()
		_max_particles = maxi(_max_particles,int(pool_stats.particles))
		_max_view_states = maxi(_max_view_states,int(view_stats.state_count))
		_max_view_events = maxi(_max_view_events,int(view_stats.event_count))
		if int(pool_stats.particles)>50 or int(view_stats.state_count)>64 or int(view_stats.event_count)>12: _failure("Decorative pool cap exceeded")
		if _frame_rows.size() < MAX_FRAME_SAMPLES:
			var rebuild: Dictionary = world.get_rebuild_stats()
			_frame_rows.append({"frame":_frames,"tick":_tick,"wall_usec":now-_began_us,"frame_interval_usec":interval,"godot_delta_seconds":delta,"paused":_paused,"particles":int(pool_stats.particles),"view_states":int(view_stats.state_count),"view_events":int(view_stats.event_count),"pending_chunks":int(rebuild.pending_chunks),"active_build":bool(rebuild.active_build),"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))})
		if _authority_complete and _mesh_ready():
			_render_complete = true
			_ended_us = Time.get_ticks_usec()
			_running = false
			effects.set_process(false)
	_ui_age += delta
	if _ui_age >= .1:
		_ui_age = 0
		_refresh_ui()

func _failure(message: String) -> void:
	if _failures.size() < 16 and not _failures.has(message): _failures.append(message)

func _refresh_ui() -> void:
	if _label == null: return
	var ready: bool = _mesh_ready() and _effects_ready
	_start_button.disabled = not ready or _running or _began_us>0
	_pause_button.disabled = not _running
	_pause_button.text = "Resume" if _paused else "Pause"
	_saturation_box.disabled = _running or _began_us>0
	_download_button.disabled = _began_us==0 and _last_report.is_empty()
	var state: String = "Warming actual terrain/resources" if not ready and _began_us==0 else "Ready: roof supported"
	if _began_us>0:
		state = "Complete: authority AND actual mesh publication drained" if _render_complete else ("Paused" if _paused else ("Authority complete; draining real mesh work" if _authority_complete else "Running real cooperative collapse"))
	_status.text = state + (" · FAIL: " + "; ".join(_failures) if not _failures.is_empty() else "")
	var wall_us: int = (Time.get_ticks_usec() if _ended_us==0 else _ended_us)-_began_us if _began_us>0 else 0
	var frame_rate: float = float(_frames)*1000000.0/float(wall_us) if wall_us>0 else 0.0
	var diagnostics: Dictionary = terrain.get_diagnostics()
	_label.text = "Roof cells removed: %d / %d · total canonical removals: %d\nFixed authority ticks: %d · last work/change: %d / %d\nActual helper CPU: mean %.3f ms / max %.3f ms\nReceipt/presentation CPU: mean %.3f ms / max %.3f ms\nRendered callbacks: %d in %.3f s · observed average %.1f / s\nCallback rate includes pauses; inspect raw pause flags for active timing.\nPool peaks: %d particles / %d view states / %d view events\nRemaining jobs/guards/foam: %d / %d / %d\nRaw samples: %d steps / %d frames (bounded512/1200)\nSource: %s" % [_roof_removed,ROOF_CELLS,_total_removed,_tick,int(diagnostics.last_work),int(diagnostics.last_changes),float(_authority_total_us)/maxi(1,_tick)/1000.0,float(_authority_max_us)/1000.0,float(_presentation_total_us)/maxi(1,_tick)/1000.0,float(_presentation_max_us)/1000.0,_frames,float(wall_us)/1000000.0,frame_rate,_max_particles,_max_view_states,_max_view_events,int(diagnostics.jobs),int(diagnostics.guard_cells),int(diagnostics.foam_cells),_step_rows.size(),_frame_rows.size(),source_hint]

func report() -> Dictionary:
	var endpoint: int = _ended_us if _ended_us>0 else Time.get_ticks_usec()
	var result: Dictionary = {"schema":"arsenal_web_benchmark_v1","source_hint":source_hint,"upstream":UPSTREAM,"engine":Engine.get_version_info(),"web":OS.has_feature("web"),"rendering_method":ProjectSettings.get_setting("rendering/renderer/rendering_method","unknown"),"viewport":str(get_viewport().get_visible_rect().size),"physics_hz":Engine.physics_ticks_per_second,"epoch":_epoch,"authority_complete":_authority_complete,"mesh_complete":_render_complete,"paused":_paused,"failures":_failures.duplicate(),"expected_roof_cells":ROOF_CELLS,"roof_removed":_roof_removed,"total_removed":_total_removed,"fixed_ticks":_tick,"wall_usec":maxi(0,endpoint-_began_us) if _began_us>0 else 0,"authority_wall_usec":maxi(0,_authority_done_us-_began_us) if _authority_done_us>0 else 0,"authority_cpu_total_usec":_authority_total_us,"authority_cpu_max_usec":_authority_max_us,"receipt_presentation_cpu_total_usec":_presentation_total_us,"receipt_presentation_cpu_max_usec":_presentation_max_us,"rendered_callbacks":_frames,"decorative_saturation":_saturation,"decorative_requested_states":96 if _saturation else 0,"decorative_requested_events_per_burst":32 if _saturation else 0,"max_particles":_max_particles,"max_view_states":_max_view_states,"max_view_events":_max_view_events,"helper":terrain.get_diagnostics(),"world":world.get_rebuild_stats(),"effects":effects.stats(),"view":view.get_display_state(),"step_samples":_step_rows.duplicate(true),"frame_samples":_frame_rows.duplicate(true),"pause_samples":_pause_rows.duplicate(true),"limits":{"step_samples":MAX_STEP_SAMPLES,"frame_samples":MAX_FRAME_SAMPLES,"pause_samples":MAX_PAUSE_SAMPLES},"scope":"Real large terrain authority and mesh publication. Saturation is decorative only; ordinary weapon/AI/mobile acceptance is separate."}
	result.callback_rate_includes_pauses = true
	result.step_samples_truncated = _tick > MAX_STEP_SAMPLES
	result.frame_samples_truncated = _frames > MAX_FRAME_SAMPLES
	return result

func download_report() -> void:
	var value: Dictionary = report() if _began_us>0 else _last_report
	var payload: String = JSON.stringify(value,"\t")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(() => {const b=new Blob(["+JSON.stringify(payload)+"],{type:'application/json'});const u=URL.createObjectURL(b);const a=document.createElement('a');a.href=u;a.download='arsenal-web-benchmark.json';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),1000);})()")
	else:
		var file: FileAccess = FileAccess.open("user://arsenal-web-benchmark.json",FileAccess.WRITE)
		if file != null:
			file.store_string(payload)
			file.close()

func _exit_tree() -> void:
	if terrain != null: terrain.dispose()
