extends Node
## Rendered isolated-effects fixture sharing the native deterministic workload.
## It excludes Main/AI/audio/terrain editing and cannot establish gameplay FPS.
const BENCHMARK = preload("res://__probe/benchmark_particle_budget.gd")
var scenario: BENCHMARK.Scenario
var running: bool = false
var preparing: bool = false
var label: Label
var render_frames_ms: Array = []
var started_usec: int = 0
var peak_draw_calls: int = 0

func _ready() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -20.0, 0.0)
	add_child(light)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.24, 0.34)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.6
	environment_node.environment = environment
	add_child(environment_node)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(12.0, 12.0)
	panel.custom_minimum_size = Vector2(420.0, 160.0)
	overlay.add_child(panel)
	for kind: String in ["public_sustained", "equal50_no_collision"]:
		var button: Button = Button.new()
		button.text = "Run public impacts/grenades + expiry" if kind == "public_sustained" else "Run identical fifty IGNORE particles"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_start.bind(kind))
		panel.add_child(button)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420.0, 100.0)
	panel.add_child(label)
	scenario = BENCHMARK.Scenario.new()
	scenario.prepare(self, "public_sustained")
	label.text = "Ready — prewarmed effects, capacity %d. Timings cover only event/update script work." % scenario.effects.max_particles
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.particleBudgetProbeReady=true", true)

func _start(kind: String) -> void:
	if running or preparing:
		return
	preparing = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.particleBudgetProbeResult=null;var p=document.getElementById('particle-budget-result');if(p){p.remove()}", true)
	scenario.dispose()
	await get_tree().process_frame
	scenario = BENCHMARK.Scenario.new()
	scenario.prepare(self, kind)
	await get_tree().process_frame
	scenario.begin()
	render_frames_ms.clear()
	peak_draw_calls = 0
	started_usec = Time.get_ticks_usec()
	preparing = false
	running = true

func _process(delta: float) -> void:
	if not running:
		return
	scenario.step()
	render_frames_ms.append(delta * 1000.0)
	peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if scenario.frame % 30 == 0:
		label.text = "%s — simulation %.1f / %.1f s\nActive %d, peak %d / cap %d\nEffects nodes %d, draw calls %d" % [
			scenario.workload, float(scenario.frame) / 60.0, float(scenario.live_frames + scenario.tail_frames) / 60.0,
			scenario.particle_count(), scenario.peak_particles, scenario.effects.max_particles,
			scenario.peak_nodes, peak_draw_calls]
	if not scenario.done:
		return
	running = false
	var result: Dictionary = scenario.report()
	result.engine = Engine.get_version_info().string
	result.renderer = RenderingServer.get_video_adapter_name()
	result.wall_seconds = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var intervals: Dictionary = BENCHMARK.Scenario.sample(render_frames_ms)
	result.rendered_frame_interval_ms = {"count": intervals.count, "total_ms": intervals.total_usec,
		"p50_ms": intervals.p50_usec, "p95_ms": intervals.p95_usec, "max_ms": intervals.max_usec}
	result.peak_draw_calls = peak_draw_calls
	result.checks = {"positive_emission": result.first_emission_observed,
		"bounded_particles": result.peak_particles <= result.configured_capacity,
		"bounded_nodes": result.peak_effect_nodes == result.initial_effect_nodes,
		"expired": result.final_particles == 0}
	result.method = "Rendered isolated-effects fixed60Hz simulation. Wall-frame deltas are browser scheduling, separate from particle CPU; no whole-game FPS claim."
	label.text = "Complete: peak %d particles, %d effects nodes. All expired: %s.\nLive update self CPU %.3f ms; p95 %.3f ms. Results available in window.particleBudgetProbeResult." % [
		result.peak_particles, result.peak_effect_nodes, str(result.final_particles == 0),
		result.phases.live.update.total_usec / 1000.0, result.phases.live.update.p95_usec / 1000.0]
	print("PARTICLE_BUDGET_RENDERED: " + JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.particleBudgetProbeResult=" + JSON.stringify(result)
			+ ";var p=document.getElementById('particle-budget-result');if(!p){p=document.createElement('pre');p.id='particle-budget-result';p.style='position:absolute;bottom:0;left:0;max-width:100%;max-height:45%;overflow:auto;background:#000c;color:white;z-index:10000;font-size:12px';document.body.appendChild(p)}p.textContent=JSON.stringify(window.particleBudgetProbeResult,null,2)", true)
