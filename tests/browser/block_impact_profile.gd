extends Node
## Warmed actual Main CPU/frame diagnostic; kept separate from the frozen old probe.
const MAIN = preload("res://scenes/main.tscn")
const RECORDER = preload("res://__probe/recorder.gd")
const SEED := 1389961
const IDLE_SECONDS := 2.0
const SHOOT_SECONDS := 8.0
const TAIL_LIMIT_SECONDS := 12.0
var app: Node3D
var manual := false
var busy := false
var phase := ""
var label: Label
var _web_callback: JavaScriptObject
var result: Dictionary = {}
var preparation: Dictionary = {}
var terrain: Dictionary = {}
var rows: Array[Dictionary] = []
var fixed_position := Vector3.ZERO
var fixed_yaw := 0.0
var fixed_pitch := 0.0
var phase_started := 0
var last_frame_usec := 0
var phase_frames: Array[float] = []
var start_shots := 0
var total_shots := 0
var removed := 0
var collapsed := 0
var start_removed := 0
var start_collapsed := 0
var starting_work: Dictionary = {}
var starting_audio: Dictionary = {}
var starting_effects: Dictionary = {}
var starting_uploads := 0
var peak_pending := 0
var peak_draws := 0
var peak_particles := 0
var phase_fixed_frames := 0
var phase_events: Array[Dictionary] = []

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	app.hud.set_menu_visible(false)
	app.world.blocks_changed.connect(on_blocks)
	app.session.shot_fired.connect(seed_weapon_shot)
	app.audio.set_workload_timing_enabled(true)
	if manual:
		return
	var overlay := CanvasLayer.new()
	overlay.layer = 30
	add_child(overlay)
	label = Label.new()
	label.position = Vector2(12,100)
	label.custom_minimum_size = Vector2(420,130)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(label)
	status("Ready: warmed Title / wall profile")
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(web_run)
		JavaScriptBridge.get_interface("window").blockImpactProfileRun = _web_callback
		JavaScriptBridge.eval("""
		const panel=document.createElement('section');panel.id='block-impact-profile-controls';
		panel.style='position:absolute;top:6px;left:6px;z-index:10000;background:#111d;color:white;padding:8px;font:13px sans-serif';
		const activation=document.createElement('div');activation.id='block-impact-profile-activation';
		activation.dataset.trustedCanvasPresses='0';
		activation.textContent='1. Click the game canvas to activate audio. 2. Press Esc to release the pointer. 3. Choose a profile.';
		panel.appendChild(activation);
		for(const spec of [['Profile warmed Title','title'],['Profile warmed wall','wall']]){
		 const b=document.createElement('button');b.id='block-impact-profile-'+spec[1];b.textContent=spec[0];
		 b.disabled=true;
		 b.onclick=()=>window.blockImpactProfileRun(spec[1]);panel.appendChild(b);
		}
		document.querySelector('canvas').addEventListener('mousedown',event=>{
		 if(!event.isTrusted)return;
		 activation.dataset.trustedCanvasPresses=String(Number(activation.dataset.trustedCanvasPresses)+1);
		 activation.textContent='Trusted game canvas input received. Press Esc to release the pointer, then choose a profile.';
		 for(const button of panel.querySelectorAll('button'))button.disabled=false;
		});
		const s=document.createElement('span');s.id='block-impact-profile-status';s.textContent=' Ready';panel.appendChild(s);
		const p=document.createElement('pre');p.id='block-impact-profile-result';
		p.style='position:absolute;bottom:0;left:0;z-index:10000;background:#000d;color:white;margin:0;padding:6px;max-width:100%;max-height:30%;overflow:auto;font:11px monospace';
		p.textContent='Ready';document.body.append(panel,p);window.blockImpactProfileReady=true;
		""",true)

func status(text: String) -> void:
	if label!=null:
		label.text = text
	if OS.has_feature("web"):
		JavaScriptBridge.eval("const s=document.getElementById('block-impact-profile-status');if(s)s.textContent="+JSON.stringify(text),true)

func web_run(args: Array) -> void:
	if busy or args.is_empty():
		return
	run_scenario(str(args[0]))

func work() -> Dictionary:
	return app.world.get_rebuild_stats()

func visual() -> Dictionary:
	return app.world.get_visual_preparation_stats()

func uploads() -> int:
	return app.hud._map.get_terrain_upload_count()

func activation_snapshot() -> Dictionary:
	if not OS.has_feature("web"):
		return {"required":false,"trusted_canvas_presses":0}
	var presses := int(JavaScriptBridge.eval("Number(document.getElementById('block-impact-profile-activation').dataset.trustedCanvasPresses)",true))
	return {"required":true,"trusted_canvas_presses":presses,
		"scope":"trusted canvas mousedown; Godot input callback resumes audio; mixer lifetime counters remain separate"}

func audio_workload() -> Dictionary:
	var snapshot: Dictionary = app.audio.debug_workload()
	snapshot.logical_voices = app.audio._voices.size()
	return snapshot

func settled() -> bool:
	# Queue/active state is scalar; cache-size reporting scans all324chunks.
	return app.world._dirty.is_empty() and app.world._active_chunk==null and bool(visual().ready)

func effects_finished() -> bool:
	var stats: Dictionary = app.effects.stats()
	return int(stats.particles)+int(stats.casings)+int(stats.tracers)+int(stats.lights)==0 and int(app.world.get_effect_stats().clusters)==0

func remove_targets() -> void:
	for target: Node3D in app._target_nodes:
		target.queue_free()
	app._target_nodes.clear()
	app.session.targets.clear()

func top_y(x: int,z: int) -> int:
	for y: int in range(app.world.dimensions.y-1,1,-1):
		if app.world.get_block(Vector3i(x,y,z))!=0:
			return y
	return 1

func choose_title_cliff() -> Dictionary:
	# Find an exposed side of original terrain with eight inward solid cells.
	# This original Title cliff was located from its VXL occupancy spans. Validate
	# it against the loaded map; the fallback also supports another original map.
	var preferred := cliff_at(Vector3i(386,13,387),Vector3i.FORWARD)
	if not preferred.is_empty():
		return preferred
	# Scan outside measured phases in a fixed order; camera/streaming then move.
	var spawn: Vector3 = app.world.get_spawn_position()
	var center := Vector2i(int(spawn.x),int(spawn.z))
	for radius: int in [32,64,96,128,192,256]:
		for z: int in range(maxi(4,center.y-radius),mini(508,center.y+radius)):
			for x: int in range(maxi(4,center.x-radius),mini(508,center.x+radius)):
				var height := top_y(x,z)
				for y: int in range(height,1,-1):
					for direction: Vector3i in [Vector3i.FORWARD,Vector3i.BACK,Vector3i.LEFT,Vector3i.RIGHT]:
						var candidate := cliff_at(Vector3i(x,y,z),direction)
						if not candidate.is_empty():
							return candidate
			# Keep the fallback map scan cancellable and allow DOM progress.
			await get_tree().process_frame
	return {}

func cliff_at(cell: Vector3i,direction: Vector3i) -> Dictionary:
	if cell.y<=1:
		return {}
	for distance: int in 8:
		if app.world.get_block(cell-direction*distance)==0:
			return {}
	for distance: int in range(1,4):
		if app.world.get_block(cell+direction*distance)!=0:
			return {}
	var eye := Vector3(cell)+Vector3.ONE*0.5+Vector3(direction)*3.0
	return {"cell":cell,"normal":direction,"solid_inward_depth":8,"eye":eye,"source":"original Title.vxl exposed cliff"}

func configure_player() -> void:
	app.session.invulnerable = true
	app.session.unlimited_ammo = true
	app.session.select_team(0)
	app.session.select_weapon(1)
	app.session.select_tool(2)
	app.hud._focused = true
	app.hud._sync_controls()
	app.player.controls_enabled = true

func tether() -> void:
	app.player.controls_enabled = true
	app.player.global_position = fixed_position
	app.player.velocity = Vector3.ZERO
	app.player._native_velocity = Vector3.ZERO
	app.player.rotation.y = fixed_yaw
	app.player.head.rotation.x = fixed_pitch

func prepare_scenario(name: String) -> bool:
	busy = true
	phase = ""
	Input.action_release("primary")
	RECORDER.enabled = false
	status("Preparing "+name+" original scene, terrain and materials…")
	app.effects.clear()
	if name=="title":
		app.world.water_enabled = true
		app.hud.set_menu_visible(true)
		await app.load_original_map()
		app.hud.set_menu_visible(false)
		remove_targets()
		terrain = await choose_title_cliff()
		if terrain.is_empty():
			status("Failed: no editable original cliff with eight inward cells")
			busy = false
			return false
		configure_player()
		var eye: Vector3 = terrain.eye
		# Respawn establishes the source head offset; adjust by the measured offset.
		app.player.respawn_at(eye-Vector3.UP*2.2)
		fixed_position = app.player.global_position+(eye-app.player.get_aim_origin())
		var direction: Vector3 = -Vector3(terrain.normal)
		fixed_yaw = atan2(-direction.x,-direction.z)
		fixed_pitch = 0.0
	else:
		app.world.clear_world(Vector3i(32,16,32))
		app.world.water_enabled = false
		app.world.data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
		app.world.data.seed_box(Vector3i(4,4,1),Vector3i(28,12,15),0x01bf8051)
		app.world._mark_all_chunks()
		app.session.reset_lab()
		remove_targets()
		configure_player()
		app.player.respawn_at(Vector3(16.5,4.01,20.5))
		fixed_position = app.player.global_position
		fixed_yaw = 0.0
		fixed_pitch = 0.0
		terrain = {"source":"grounded lab wall","solid_inward_depth":14}
	tether()
	app.world.set_view_position(fixed_position)
	app.world.get_topdown_image_progressive()
	var deadline := Time.get_ticks_msec()+120000
	var callbacks := 0
	var stable_uploads := 0
	var last_upload := -1
	while Time.get_ticks_msec()<deadline:
		tether()
		await get_tree().process_frame
		callbacks += 1
		if not settled():
			stable_uploads = 0
			continue
		var count := uploads()
		stable_uploads = stable_uploads+1 if count==last_upload else 0
		last_upload = count
		if stable_uploads>=60 and app.player.can_use_tool():
			break
	if not settled() or stable_uploads<60:
		busy = false
		status("Failed: visual preparation/minimap did not settle")
		return false
	# Warm hit particles/materials against protected floor, then let them expire;
	# no fixture-created cliff or baseline terrain edit is introduced.
	app.effects.block_hit(app.player.get_aim_origin()+Vector3.FORWARD*2.0,Vector3.UP,Color(0.5,0.4,0.3),false)
	app.effects.muzzle_fire(app.player.get_aim_origin(),Vector3.FORWARD,1,true)
	for warm_frame: int in 180:
		tether()
		await get_tree().process_frame
	app.effects.clear()
	app.audio.stop()
	app.audio.reset_workload_counters()
	var ray: Dictionary = app.world.cast_voxel(app.player.get_aim_origin(),app.player.get_aim_direction(),64.0)
	preparation = {"settled":settled(),"visual":visual(),"world":work(),"minimap_uploads":uploads(),
		"stable_minimap_callbacks":stable_uploads,"settling_callbacks":callbacks,"effect_shader_warmup_callbacks":180,
		"initial_ray":ray,"terrain":terrain,"player_position":fixed_position,"yaw":fixed_yaw,"pitch":fixed_pitch,
		"graphics":app.get_graphics_options(),"effects_quality":app.effects.quality,
		"positional_audio":app.positional_audio,"environmental_audio":app.environmental_audio,"activation":activation_snapshot()}
	rows.clear()
	removed = 0
	collapsed = 0
	total_shots = app.session.shots_fired
	return bool(ray.hit) and ray.cell.y>1 and settled()

func run_scenario(name: String) -> void:
	var prepared: bool = await prepare_scenario(name)
	if not prepared:
		publish_failure(name)
		return
	result = {"scenario":name,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),
		"preparation":preparation,"mode":"production callbacks/budgets; diagnostic wrappers identical across sources","seed":SEED}
	start_phase("idle")

func seed_weapon_shot() -> void:
	# Weapon RNG is independent of the number of prior render callbacks.
	seed(SEED+app.session.shots_fired*104729)
	if not phase.is_empty() and phase_events.size()<512:
		phase_events.append({"type":"shot","frame":phase_fixed_frames,"relative_usec":Time.get_ticks_usec()-phase_started,"shot":app.session.shots_fired})

func on_blocks(changes: Array) -> void:
	if phase.is_empty():
		return
	var count := 0
	for change: Dictionary in changes:
		if int(change.before)!=0 and int(change.after)==0:
			removed += 1
			count += 1
			if bool(change.collapsed):
				collapsed += 1
	if count>0 and phase_events.size()<512:
		phase_events.append({"type":"remove","frame":phase_fixed_frames,"relative_usec":Time.get_ticks_usec()-phase_started,"cells":count,
			"first_cell":changes[0].cell,"map_sequence":app.world.data.map_sequence})

func start_phase(name: String) -> void:
	phase = name
	phase_started = Time.get_ticks_usec()
	last_frame_usec = phase_started
	phase_frames.clear()
	phase_fixed_frames = 0
	phase_events.clear()
	peak_pending = 0
	peak_draws = 0
	peak_particles = 0
	start_shots = app.session.shots_fired
	start_removed = removed
	start_collapsed = collapsed
	starting_work = work()
	starting_audio = audio_workload()
	starting_effects = app.effects.stats()
	starting_uploads = uploads()
	RECORDER.reset()
	status("Measuring "+str(result.get("scenario","native"))+" / "+name)
	if name=="shoot":
		app.effects.rng.seed = SEED
		Input.action_press("primary")
	else:
		Input.action_release("primary")

func numeric_delta(before: Dictionary,after: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for key: String in after:
		if before.has(key) and (after[key] is int or after[key] is float):
			delta[key] = after[key]-before[key]
	return delta

func distribution(samples: Array[float]) -> Dictionary:
	var ordered: Array[float] = samples.duplicate()
	ordered.sort()
	if ordered.is_empty():
		return {"samples":0}
	var total := 0.0
	for sample: float in ordered:
		total += sample
	return {"samples":ordered.size(),"total_ms":total,"p50_ms":ordered[int((ordered.size()-1)*0.5)],
		"p95_ms":ordered[int((ordered.size()-1)*0.95)],"p99_ms":ordered[int((ordered.size()-1)*0.99)],"max_ms":ordered[-1]}

func finish_phase() -> Dictionary:
	RECORDER.enabled = false
	var cpu: Dictionary = RECORDER.snapshot()
	var exclusive_total := 0
	for function: String in cpu:
		exclusive_total += int(cpu[function].exclusive_usec)
	var shots: int = app.session.shots_fired-start_shots
	var row := {"phase":phase,"wall_seconds":float(Time.get_ticks_usec()-phase_started)/1000000.0,
		"frames":distribution(phase_frames),"fixed_frames":phase_fixed_frames,"shots":shots,
		"removed":removed-start_removed,"collapsed":collapsed-start_collapsed,"peak_pending_chunks":peak_pending,
		"peak_draw_calls":peak_draws,"peak_particles":peak_particles,"cpu_functions":cpu,"events":phase_events.duplicate(true),
		"instrumented_exclusive_total_usec":exclusive_total,"instrumented_exclusive_usec_per_shot":float(exclusive_total)/shots if shots>0 else 0.0,
		"work_delta":numeric_delta(starting_work,work()),"final_work":work(),"final_visual":visual(),
		"audio_delta":numeric_delta(starting_audio,audio_workload()),"starting_audio":starting_audio,"final_audio":audio_workload(),
		"effects_delta":numeric_delta(starting_effects,app.effects.stats()),
		"minimap_uploads":uploads()-starting_uploads}
	rows.append(row)
	return row

func sample_frame(milliseconds: float) -> void:
	phase_frames.append(milliseconds)
	phase_fixed_frames += 1
	# Avoid324-chunk cache-size scans in every callback; queue length is scalar.
	peak_pending = maxi(peak_pending,app.world._dirty.size())
	peak_particles = maxi(peak_particles,int(app.effects.stats().particles))
	peak_draws = maxi(peak_draws,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

func _physics_process(_delta: float) -> void:
	if manual or phase.is_empty():
		return
	tether()
	if phase=="shoot":
		Input.action_press("primary")

func _process(_delta: float) -> void:
	if manual or phase.is_empty():
		return
	var now := Time.get_ticks_usec()
	sample_frame(float(now-last_frame_usec)/1000.0)
	last_frame_usec = now
	var elapsed: float = float(now-phase_started)/1000000.0
	if phase=="idle" and elapsed>=IDLE_SECONDS:
		finish_phase()
		start_phase("shoot")
	elif phase=="shoot" and elapsed>=SHOOT_SECONDS:
		Input.action_release("primary")
		finish_phase()
		start_phase("tail")
	elif phase=="tail" and ((elapsed>=2.0 and settled() and effects_finished()) or elapsed>=TAIL_LIMIT_SECONDS):
		finish_phase()
		finish_scenario()

func finish_scenario() -> void:
	phase = ""
	busy = false
	Input.action_release("primary")
	result.phases = rows
	result.shots = app.session.shots_fired-total_shots
	result.removed = removed
	result.collapsed = collapsed
	result.drained = settled() and effects_finished()
	var shoot_tail_cpu := 0
	for row: Dictionary in rows:
		if row.phase in ["shoot","tail"]:
			shoot_tail_cpu += int(row.instrumented_exclusive_total_usec)
	result.shoot_plus_tail_exclusive_usec = shoot_tail_cpu
	result.shoot_plus_tail_exclusive_usec_per_shot = float(shoot_tail_cpu)/int(result.shots) if int(result.shots)>0 else 0.0
	result.valid = bool(preparation.settled) and int(result.shots)>0 and removed>0 and bool(result.drained)
	result.limits = "Diagnostic CPU wrappers add identical timing overhead; browser callback intervals include GPU/host; initial weapon RNG resets per shot, effects remain real elapsed; native fixed-delta throughput differs from production4ms scheduling and engine audio voices use wall time, so compare native module CPU separately from differing voice-update workload"
	status("Completed: "+str(result.shots)+" shots / "+str(removed)+" cells; valid="+str(result.valid))
	print("BLOCK_IMPACT_PROFILE: "+JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.blockImpactProfileResult="+JSON.stringify(result)+";document.getElementById('block-impact-profile-result').textContent=JSON.stringify(window.blockImpactProfileResult,null,2)",true)

func publish_failure(name: String) -> void:
	busy = false
	phase = ""
	result = {"scenario":name,"valid":false,"preparation":preparation,"error":"preparation or editable original terrain failed"}
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.blockImpactProfileResult="+JSON.stringify(result)+";document.getElementById('block-impact-profile-result').textContent=JSON.stringify(window.blockImpactProfileResult,null,2)",true)

func _exit_tree() -> void:
	Input.action_release("primary")
