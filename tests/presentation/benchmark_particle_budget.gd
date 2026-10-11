extends SceneTree
## Opt-in particle CPU experiment. Run against an immutable baseline/candidate
## project. Resource loading, world meshing, diagnostics and assertions are never
## inside the measured emission/update interval. This is not a whole-game FPS test.
const EFFECTS = preload("res://presentation/openspades_effects.gd")
const WORLD = preload("res://world/voxel_world.gd")
const STEP: float = 1.0 / 60.0
var label: String = "unlabelled"
var report_path: String = ""
var assertions: int = 0
var failures: int = 0

class Scenario extends RefCounted:
	var world: VoxelWorld
	var camera: Camera3D
	var effects: OpenSpadesEffects
	var workload: String = ""
	var frame: int = 0
	var live_frames: int = 480
	var tail_frames: int = 720
	var peak_particles: int = 0
	var peak_nodes: int = 0
	var initial_nodes: int = 0
	var final_particles: int = 0
	var initial_stats: Dictionary = {}
	var requested_events_with_active_particles: int = 0
	var first_emission_observed: bool = false
	var requested_events: int = 0
	var requested_particles: int = 0
	var update_calls: int = 0
	var done: bool = false
	var has_count_api: bool = false
	var phases: Dictionary = {}
	var origin: Vector3 = Vector3(16.5, 6.5, 15.01)
	var subset_positions: Array[Vector3] = []
	var subset_velocities: Array[Vector3] = []
	var subset_options: Array[Dictionary] = []

	func prepare(owner: Node, kind: String) -> void:
		workload = kind
		world = WORLD.new()
		world.clear_world(Vector3i(32, 16, 32))
		world.water_enabled = false
		world.visual_effects_enabled = false
		world.irradiance_enabled = false
		world.data.seed_box(Vector3i.ZERO, Vector3i(32, 4, 32), 0x01608070)
		world.data.seed_box(Vector3i(4, 4, 1), Vector3i(28, 12, 15), 0x01bf8050)
		owner.add_child(world)
		world.set_process(false)
		world._mark_all_chunks()
		world.rebuild_now()
		camera = Camera3D.new()
		owner.add_child(camera)
		camera.position = Vector3(16.5, 8.0, 23.0)
		camera.look_at(Vector3(16.5, 6.5, 15.0))
		camera.current = true
		effects = EFFECTS.new()
		# The equal-count case changes only the baseline's configurable budget.
		# Fifty explicit IGNORE particles avoid both cap policy and collision cost.
		if kind == "equal50_no_collision":
			effects.max_particles = 50
			live_frames = 180
			tail_frames = 180
		effects.max_casings = 0
		effects.max_tracers = 0
		effects.max_lights = 0
		effects.audio_enabled = false
		effects.shake_level = 0
		owner.add_child(effects)
		effects.setup(world, camera)
		effects.set_process(false)
		has_count_api = effects.has_method("particle_count")
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 1389961
		for index: int in range(50):
			subset_positions.append(origin + Vector3(random.randf_range(-1.0, 1.0), random.randf(), random.randf_range(-1.0, 1.0)))
			subset_velocities.append(Vector3(random.randf_range(-3.0, 3.0), random.randf_range(0.0, 6.0), random.randf_range(-3.0, 3.0)))
			subset_options.append({"collision": EFFECTS.IGNORE, "gravity": 0.9, "damping": 0.8,
				"smoke": 1 if index >= 40 else 0, "fps": 40.0, "growth": 0.1, "fade_out": 0.4})
		# Exercise every public emitter/resource before the measured run.
		effects.rng.seed = 7341
		effects.block_hit(origin, Vector3.BACK, Color(0.75, 0.5, 0.3))
		effects.blood(origin + Vector3.UP)
		effects.grenade_explosion(origin + Vector3.UP)
		effects.grenade_explosion(origin + Vector3.UP, true)
		for index: int in range(60):
			effects.update_effects(STEP)
		effects.clear()

	func begin() -> void:
		effects.clear()
		effects.rng.seed = 7341
		initial_stats = effects.stats()
		initial_nodes = node_count(effects)
		peak_nodes = initial_nodes
		phases = {"live": new_samples(), "tail": new_samples()}

	func new_samples() -> Dictionary:
		return {"emission_usec": [], "update_usec": [], "frame_self_usec": [], "active_sum": 0,
			"frames_with_particles": 0, "peak_particles": 0}

	func particle_count() -> int:
		# One allocation-free public read on candidate; historical baseline has
		# only stats(). Neither diagnostics path is inside the timed interval.
		return int(effects.call("particle_count")) if has_count_api else int(effects.stats().particles)

	func step() -> void:
		if done:
			return
		var phase: String = "live" if frame < live_frames else "tail"
		var samples: Dictionary = phases[phase]
		var before: int = particle_count()
		var event_count: int = 0
		var requested: int = 0
		var hit_due: bool = workload == "public_sustained" and frame < live_frames and frame % 4 == 0
		var blood_due: bool = workload == "public_sustained" and frame < live_frames and frame % 30 == 0
		var grenade_due: bool = workload == "public_sustained" and frame < live_frames and frame % 120 == 0
		var subset_due: bool = workload == "equal50_no_collision" and frame == 0
		if hit_due:
			event_count += 1
			requested += 25
		if blood_due:
			event_count += 1
			requested += 13
		if grenade_due:
			event_count += 1
			requested += 73 if frame % 240 == 120 else 58
		if subset_due:
			event_count = 1
			requested = 50
		var started: int = Time.get_ticks_usec()
		if hit_due:
			effects.block_hit(origin, Vector3.BACK, Color(0.75, 0.5, 0.3))
		if blood_due:
			effects.blood(origin + Vector3.UP)
		if grenade_due:
			effects.grenade_explosion(origin + Vector3.UP, frame % 240 == 120)
		if subset_due:
			for index: int in range(50):
				effects._spawn(subset_positions[index], subset_velocities[index], Color(0.7, 0.4, 0.2, 0.8), 0.2, 2.5, subset_options[index])
		var emitted: int = Time.get_ticks_usec()
		effects.update_effects(STEP)
		var finished: int = Time.get_ticks_usec()
		# All counters, arrays, diagnostics and node enumeration below are outside
		# the interval. frame_self reports just effect event+update script work.
		samples.emission_usec.append(float(emitted - started))
		samples.update_usec.append(float(finished - emitted))
		samples.frame_self_usec.append(float(finished - started))
		update_calls += 1
		requested_events += event_count
		requested_particles += requested
		var active: int = particle_count()
		if event_count > 0 and active > 0:
			requested_events_with_active_particles += event_count
		if frame == 0 and event_count > 0 and before == 0 and active > 0:
			first_emission_observed = true
		peak_particles = maxi(peak_particles, active)
		samples.peak_particles = maxi(int(samples.peak_particles), active)
		samples.active_sum += active
		if active > 0:
			samples.frames_with_particles += 1
		peak_nodes = maxi(peak_nodes, node_count(effects))
		frame += 1
		done = frame >= live_frames + tail_frames
		if done:
			final_particles = active

	func report() -> Dictionary:
		var measured: Dictionary = {}
		for phase: String in phases:
			var source: Dictionary = phases[phase]
			measured[phase] = {"emission": sample(source.emission_usec), "update": sample(source.update_usec),
				"frame_self": sample(source.frame_self_usec), "active_particle_frames": source.active_sum,
				"frames_with_particles": source.frames_with_particles, "peak_particles": source.peak_particles}
		return {"workload": workload, "fixed_delta": STEP, "live_frames": live_frames, "tail_frames": tail_frames,
			"simulated_seconds": float(live_frames + tail_frames) * STEP,
			"configured_capacity": effects.max_particles, "requested_particles": requested_particles,
			"requested_events": requested_events, "requested_events_with_active_particles": requested_events_with_active_particles,
			"first_emission_observed": first_emission_observed,
			"peak_particles": peak_particles, "initial_effect_nodes": initial_nodes, "peak_effect_nodes": peak_nodes,
			"final_effect_nodes": node_count(effects), "final_particles": final_particles,
			"update_calls": update_calls, "initial_stats": initial_stats, "final_stats": effects.stats(), "phases": measured}

	func dispose() -> void:
		effects.queue_free()
		world.queue_free()
		camera.queue_free()

	static func node_count(node: Node) -> int:
		var count: int = 1
		for child: Node in node.get_children():
			count += node_count(child)
		return count

	static func sample(source: Array) -> Dictionary:
		var values: Array[float] = []
		var total: float = 0.0
		for value: float in source:
			values.append(value)
			total += value
		values.sort()
		if values.is_empty():
			return {"count": 0, "total_usec": 0.0, "p50_usec": 0.0, "p95_usec": 0.0, "max_usec": 0.0}
		return {"count": values.size(), "total_usec": total, "p50_usec": values[int((values.size() - 1) * 0.5)],
			"p95_usec": values[int((values.size() - 1) * 0.95)], "max_usec": values[-1]}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("PARTICLE BUDGET BENCHMARK: " + message)

func run() -> void:
	var reports: Array[Dictionary] = []
	for workload: String in ["public_sustained", "equal50_no_collision"]:
		var scenario: Scenario = Scenario.new()
		scenario.prepare(root, workload)
		await process_frame
		scenario.begin()
		while not scenario.done:
			scenario.step()
		var result: Dictionary = scenario.report()
		check(result.first_emission_observed and result.peak_particles > 0, workload + " emits active visible data")
		check(result.peak_particles <= result.configured_capacity, workload + " respects configured particle capacity")
		check(result.peak_effect_nodes == result.initial_effect_nodes, workload + " never creates an effects node after prewarm")
		check(result.final_particles == 0, workload + " expires every particle during tail")
		check(result.phases.live.update.total_usec > 0.0, workload + " captures positive update CPU")
		if workload == "equal50_no_collision":
			check(result.peak_particles == 50, "equal-count IGNORE case begins with fifty particles")
		reports.append(result)
		scenario.dispose()
		await process_frame
		await process_frame
	var report: Dictionary = {"label": label, "engine": Engine.get_version_info().string,
		"display_server": DisplayServer.get_name(), "renderer": RenderingServer.get_video_adapter_name(),
		"method": "Deterministic compact-wall 60 Hz particle-only script CPU. Public block hit every four frames, blood every thirty, alternating land/water grenade every120; eight-second live plus twelve-second expiry tail. Separate fifty explicit IGNORE fragments/smoke for cap-independent implementation comparison. Resources, terrain meshing, counts, snapshots and assertions outside timing. No whole-game FPS or GPU claim.",
		"assertions": assertions, "failures": failures, "scenarios": reports}
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "requested report file opens")
		report.assertions = assertions
		report.failures = failures
		if file != null:
			file.store_string(JSON.stringify(report, "  ") + "\n")
			file.close()
	print("PARTICLE_BUDGET_BENCHMARK: " + JSON.stringify(report))
	print("PARTICLE BUDGET BENCHMARK: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
