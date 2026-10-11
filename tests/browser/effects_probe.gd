extends Node
## Separate actual-Main rendered stress fixture; never the production entry scene.
const MAIN = preload("res://scenes/main.tscn")
var app: Node3D
var label: Label
var running := false
var elapsed := 0.0
var frames: Array[float] = []
var started_usec := 0
var peak_particles := 0
var peak_casings: int = 0
var peak_nodes := 0
var peak_draws := 0
var cap_violations: int = 0
var casing_contacts: int = 0
var baseline_stats: Dictionary = {}
var result: Dictionary = {}
var collapse_camera: Camera3D

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	app.hud.set_menu_visible(false)
	InputMap.action_erase_events("primary")
	app.session.invulnerable = true
	app.session.unlimited_ammo = true
	app.session.select_weapon(1)
	app.effects.casing_contact.connect(func(_position: Vector3, _water: bool, _weapon: int): casing_contacts += 1)
	for target: Node3D in app._target_nodes: target.queue_free()
	app._target_nodes.clear()
	app.session.targets.clear()
	# A thick wall keeps the held SMG hitting nearby terrain throughout the run.
	app.world.clear_world(Vector3i(32,16,32))
	app.world.water_enabled = false
	app.world.data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	app.world.data.seed_box(Vector3i(4,4,1),Vector3i(28,12,15),0x01bf8050)
	app.world._mark_all_chunks()
	app.world.rebuild_now()
	app.player.respawn_at(Vector3(16.5,4.01,20.5))
	var overlay := CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	var panel := VBoxContainer.new()
	panel.position = Vector2(12,110)
	panel.custom_minimum_size = Vector2(340,140)
	overlay.add_child(panel)
	for spec in [["SMG into wall: 12 seconds",_start],["Grenade at 5 m",_grenade.bind(5.0)],["Grenade at 80 m",_grenade.bind(80.0)],["Grenade beyond cutoff: 180 m",_grenade.bind(180.0)],
		["Collapse: inspect quarter-second pose",_collapse],["Collapse: finish and verify cleanup",_finish_collapse]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		panel.add_child(button)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(340,100)
	panel.add_child(label)
	label.text = "Ready — actual Main, source SMG, audio and terrain edits enabled"
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.effectsProbeReady=true",true)

func _start() -> void:
	if running: return
	app.effects.clear()
	frames.clear()
	started_usec = Time.get_ticks_usec()
	elapsed = 0.0
	peak_particles = 0
	peak_casings = 0
	peak_nodes = 0
	peak_draws = 0
	cap_violations = 0
	casing_contacts = 0
	baseline_stats = app.effects.stats()
	running = true
	Input.action_press("primary")

func _physics_process(_delta: float) -> void:
	if running:
		# Compensate recoil so the sustained shot scenario continues into terrain.
		app.player.rotation.y = 0.0
		app.player.head.rotation.x = 0.0

func _process(delta: float) -> void:
	if not running: return
	elapsed += delta
	frames.append(delta*1000.0)
	var effect_stats: Dictionary = app.effects.stats()
	peak_particles = maxi(peak_particles,int(effect_stats.particles))
	peak_casings = maxi(peak_casings,int(effect_stats.casings))
	if int(effect_stats.particles) > 50 or int(effect_stats.casings) > 16:
		cap_violations += 1
	peak_nodes = maxi(peak_nodes,app.effects.get_child_count())
	peak_draws = maxi(peak_draws,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	label.text = "SMG wall: %.1f / 12 s\nParticles %d/50, casings %d/16\nEffect nodes %d / draw calls %d"%[elapsed,peak_particles,peak_casings,peak_nodes,peak_draws]
	if elapsed < 12.0: return
	Input.action_release("primary")
	running = false
	frames.sort()
	var final_stats: Dictionary = app.effects.stats()
	var checks: Dictionary = {"particles_emitted":peak_particles > 0,
		"casings_emitted":peak_casings > 0, "hard_caps":cap_violations == 0,
		"no_new_nodes":final_stats.created_nodes == baseline_stats.created_nodes,
		"no_new_particle_states":final_stats.particle_state_allocations == baseline_stats.particle_state_allocations,
		"no_new_casing_states":final_stats.casing_state_allocations == baseline_stats.casing_state_allocations,
		"no_casing_contacts":casing_contacts == 0}
	var failed_checks: int = 0
	for passed: bool in checks.values():
		failed_checks += int(not passed)
	result = {"seconds":elapsed,"frames":frames.size(),"fps":frames.size()/elapsed,
		"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"p50_ms":frames[int(frames.size()*.5)],"p95_ms":frames[mini(frames.size()-1,int(frames.size()*.95))],
		"peak_particles":peak_particles,"peak_casings":peak_casings,"peak_effect_nodes":peak_nodes,"peak_draw_calls":peak_draws,
		"cap_violations":cap_violations,"casing_contacts":casing_contacts,"checks":checks,"failed_checks":failed_checks,
		"baseline_stats":baseline_stats,"stats":final_stats,"renderer":RenderingServer.get_video_adapter_name()}
	label.text = JSON.stringify(result,"  ")
	print("EFFECTS_RENDERED_STRESS: "+JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.effectsProbeResult="+JSON.stringify(result)+";var p=document.getElementById('effects-probe-result');if(!p){p=document.createElement('pre');p.id='effects-probe-result';p.style='position:absolute;bottom:0;left:0;max-width:100%;max-height:45%;overflow:auto;background:#000c;color:white;z-index:10000;font-size:12px';document.body.appendChild(p)}p.textContent=JSON.stringify(window.effectsProbeResult,null,2)",true)

func _grenade(distance: float) -> void:
	if running: return
	app.effects.clear()
	var position: Vector3 = app.player.camera.global_position+Vector3.FORWARD*distance
	app.effects.grenade_explosion(position)
	label.text = "Grenade %.0f m: %d/50 particles\nFast %.6f / slow %.6f"%[distance,app.effects.particle_count(),app.effects._fast_shake,app.effects._slow_shake]
	if OS.has_feature("web"):
		var snapshot: Dictionary = {"distance":distance,"fast":app.effects._fast_shake,"slow":app.effects._slow_shake,"stats":app.effects.stats()}
		JavaScriptBridge.eval("window.effectsProbeGrenade="+JSON.stringify(snapshot),true)

func _exit_tree() -> void:
	Input.action_release("primary")

func _collapse() -> void:
	if running or not app.world._falling_clusters.is_empty(): return
	app.effects.clear()
	app.world.data.seed_box(Vector3i(8, 4, 18), Vector3i(9, 8, 19), 0x01808080)
	app.world.data.seed_box(Vector3i(6, 8, 17), Vector3i(26, 10, 27), 0x01bf8050)
	app.world._mark_all_chunks()
	app.world.rebuild_now()
	app.player.respawn_at(Vector3(16.5, 4.01, 30.0))
	app.player.rotation.y = 0.0
	app.player.head.rotation.x = -0.3
	app.world.set_block(Vector3i(8, 7, 18), 0)
	if collapse_camera == null:
		collapse_camera = Camera3D.new()
		add_child(collapse_camera)
	collapse_camera.position = Vector3(16.5, 15.0, 33.0)
	collapse_camera.look_at(Vector3(16.5, 8.5, 22.0))
	collapse_camera.current = true
	var entries: Array[Dictionary] = []
	for cluster: FallingVoxelCluster in app.world._falling_clusters:
		cluster.set_process(false)
		cluster.step(0.25)
		entries.append(cluster.get_effect_stats())
	var snapshot: Dictionary = {"quarter_second": entries,
		"authoritative_roof_removed": app.world.get_block(Vector3i(16, 8, 22)) == 0}
	label.text = JSON.stringify(snapshot, "  ")
	_publish_collapse(snapshot)

func _finish_collapse() -> void:
	if running: return
	var groups: Array[Node3D] = app.world._falling_clusters.duplicate()
	for cluster: FallingVoxelCluster in groups:
		cluster.step(0.75)
	await get_tree().process_frame
	var snapshot: Dictionary = {"complete": app.world.get_effect_stats(),
		"authoritative_roof_removed": app.world.get_block(Vector3i(16, 8, 22)) == 0}
	label.text = JSON.stringify(snapshot, "  ")
	_publish_collapse(snapshot)

func _publish_collapse(snapshot: Dictionary) -> void:
	print("EFFECTS_COLLAPSE_PROBE: " + JSON.stringify(snapshot))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var p=document.getElementById('effects-collapse-result');if(!p){p=document.createElement('pre');p.id='effects-collapse-result';p.style='position:absolute;bottom:0;right:0;max-width:45%;max-height:45%;overflow:auto;background:#000c;color:white;z-index:10000;font-size:12px';document.body.appendChild(p)}p.textContent=" + JSON.stringify(JSON.stringify(snapshot,"  ")),true)
