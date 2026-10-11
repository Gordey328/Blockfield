extends SceneTree
## Opt-in CPU experiment: production per-instance setters versus one documented
## row-major 16-float buffer. Not part of normal correctness/performance gates.
## Run native/headless; omit --headless for actual Compatibility readback.
const EFFECTS = preload("res://presentation/openspades_effects.gd")
const WORLD = preload("res://world/voxel_world.gd")
var assertions: int = 0
var failures: int = 0
var report_path: String = ""

class TimedEffects extends OpenSpadesEffects:
	var particle_usec: int = 0
	var batch_usec: int = 0
	func _update_particles(delta: float, lifetime_delta: float, frame_elapsed: float) -> void:
		var started: int = Time.get_ticks_usec()
		super._update_particles(delta, lifetime_delta, frame_elapsed)
		particle_usec += Time.get_ticks_usec() - started
	func _sync_fragment_batch() -> void:
		var started: int = Time.get_ticks_usec()
		super._sync_fragment_batch()
		batch_usec += Time.get_ticks_usec() - started

class BulkEffects extends TimedEffects:
	var packed_buffer: PackedFloat32Array = PackedFloat32Array()
	var bulk_uploads: int = 0
	func _sync_fragment_batch() -> void:
		if packed_buffer.size() != maxi(0, max_particles) * 16:
			packed_buffer.resize(maxi(0, max_particles) * 16)
		super._sync_fragment_batch()
		if _fragment_count > 0:
			var started: int = Time.get_ticks_usec()
			_fragment_multimesh.buffer = packed_buffer
			batch_usec += Time.get_ticks_usec() - started
			bulk_uploads += 1
	func _write_fragment(index: int, entry: Dictionary, billboard: Basis, to_local: Transform3D) -> void:
		var node: Sprite3D = entry.node
		var facing: Basis = billboard * Basis(Vector3.BACK, node.rotation.z) * Basis.from_scale(node.global_basis.get_scale())
		var local_pose: Transform3D = to_local * Transform3D(facing, node.global_position)
		var offset: int = index * 16
		# RenderingServer.multimesh_set_buffer: row-major Transform3D12+RGBA4.
		packed_buffer[offset] = local_pose.basis.x.x
		packed_buffer[offset + 1] = local_pose.basis.y.x
		packed_buffer[offset + 2] = local_pose.basis.z.x
		packed_buffer[offset + 3] = local_pose.origin.x
		packed_buffer[offset + 4] = local_pose.basis.x.y
		packed_buffer[offset + 5] = local_pose.basis.y.y
		packed_buffer[offset + 6] = local_pose.basis.z.y
		packed_buffer[offset + 7] = local_pose.origin.y
		packed_buffer[offset + 8] = local_pose.basis.x.z
		packed_buffer[offset + 9] = local_pose.basis.y.z
		packed_buffer[offset + 10] = local_pose.basis.z.z
		packed_buffer[offset + 11] = local_pose.origin.z
		var color: Color = node.modulate
		packed_buffer[offset + 12] = color.r
		packed_buffer[offset + 13] = color.g
		packed_buffer[offset + 14] = color.b
		packed_buffer[offset + 15] = color.a

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("IMPACT EFFECTS BENCHMARK: " + message)

func sample(values: Array[float]) -> Dictionary:
	var total: float = 0.0
	for value: float in values:
		total += value
	values.sort()
	return {"count": values.size(), "median_usec": values[(values.size() - 1) / 2],
		"p95_usec": values[int((values.size() - 1) * 0.95)], "max_usec": values[-1], "total_usec": total}

func setup_effects(effects: TimedEffects, world: VoxelWorld, camera: Camera3D, origin: Vector3) -> void:
	effects.max_casings = 0
	effects.max_tracers = 0
	effects.max_lights = 0
	root.add_child(effects)
	effects.setup(world, camera)
	effects.set_process(false)
	effects.shake_level = 0
	effects.audio_enabled = false
	effects.rng.seed = 7341
	var rng := RandomNumberGenerator.new()
	rng.seed = 1389961
	for index: int in range(400):
		var position := origin + Vector3(rng.randf_range(-2, 2), rng.randf(), rng.randf_range(-2, 2))
		var velocity := Vector3(rng.randf_range(-3, 3), rng.randf_range(0, 6), rng.randf_range(-3, 3))
		effects._spawn(position, velocity, Color(0.7, 0.4, 0.2), 0.2, 2.0,
			{"gravity": 0.9, "collision": EFFECTS.BOUNCE})
	effects.update_effects(0.0)

func run() -> void:
	var world := WORLD.new()
	world.clear_world(Vector3i(8, 8, 8))
	world.water_enabled = false
	world.visual_effects_enabled = false
	root.add_child(world)
	world.set_process(false)
	print("IMPACT_EFFECTS_PROGRESS: load original Title")
	check(world.load_vxl("res://assets/openspades/maps/Title.vxl", true) == OK, "benchmark uses original Title terrain queries")
	var camera := Camera3D.new()
	root.add_child(camera)
	var origin: Vector3 = world.get_spawn_position() + Vector3.UP * 3.0
	camera.position = origin + Vector3(0, 0, 5)
	var normal := TimedEffects.new()
	var bulk := BulkEffects.new()
	print("IMPACT_EFFECTS_PROGRESS: warm normal and bulk effects")
	setup_effects(normal, world, camera, origin)
	setup_effects(bulk, world, camera, origin)
	check(normal._particles.size() == 400 and bulk._particles.size() == 400, "both variants begin with identical 400 fragments and source budgets")
	check(bulk.packed_buffer.size() == 512 * 16, "experimental buffer retains production fixed capacity and documented stride")
	var phases: Dictionary = {}
	for phase: String in ["dense", "tail"]:
		print("IMPACT_EFFECTS_PROGRESS: sample " + phase)
		var times: Dictionary = {"normal": [], "bulk": [], "normal_particles": [], "bulk_particles": [], "normal_batch": [], "bulk_batch": []}
		for frame: int in range(90):
			# Alternate order to reduce systematic cache/order bias.
			var order: Array[TimedEffects] = []
			order.append(normal if frame % 2 == 0 else bulk)
			order.append(bulk if frame % 2 == 0 else normal)
			for effects: TimedEffects in order:
				var label: String = "bulk" if effects == bulk else "normal"
				var old_particles: int = effects.particle_usec
				var old_batch: int = effects.batch_usec
				var started: int = Time.get_ticks_usec()
				effects.update_effects(1.0 / 60.0)
				times[label].append(float(Time.get_ticks_usec() - started))
				times[label + "_particles"].append(float(effects.particle_usec - old_particles))
				times[label + "_batch"].append(float(effects.batch_usec - old_batch))
			check(normal._particles.size() == bulk._particles.size() and normal._fragment_count == bulk._fragment_count, "bulk publication does not change source lifetimes/counts")
			if phase == "dense" and frame == 0:
				verify_pose(normal, bulk)
		var measured: Dictionary = {}
		for key: String in times:
			var values: Array[float] = []
			values.assign(times[key])
			measured[key] = sample(values)
		phases[phase] = measured
	check(normal.stats().particles == 0 and bulk.stats().particles == 0, "source two-second lifetime drains both variants during tail")
	var result: Dictionary = {"engine": Engine.get_version_info().string, "renderer": DisplayServer.get_name(),
		"assertions": assertions, "failures": failures, "origin": origin, "phases": phases,
		"normal_stats": normal.stats(), "bulk_stats": bulk.stats(), "bulk_uploads": bulk.bulk_uploads,
		"bulk_retained_bytes": bulk.packed_buffer.size() * 4,
		"method": "Native opt-in 400 Title fragments, exact deterministic source 1/60 integration, alternating variant order; dense 90 frames and tail 90 frames; CPU only, no FPS claim"}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "requested benchmark report opens")
		result.assertions = assertions
		result.failures = failures
		if file != null:
			file.store_string(JSON.stringify(result, "  ") + "\n")
			file.close()
	print("IMPACT_EFFECTS_BENCHMARK: " + JSON.stringify(result))
	print("IMPACT EFFECTS BENCHMARK: %d assertions, %d failures" % [assertions, failures])
	normal.queue_free()
	bulk.queue_free()
	world.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

func verify_pose(normal: TimedEffects, bulk: BulkEffects) -> void:
	var entry: Dictionary = bulk._particles[0]
	var node: Sprite3D = entry.node
	var billboard: Basis = bulk.camera.global_basis.orthonormalized()
	var to_local: Transform3D = bulk._fragment_batch.global_transform.affine_inverse()
	var expected: Transform3D = to_local * Transform3D(billboard * Basis(Vector3.BACK, node.rotation.z) * Basis.from_scale(node.global_basis.get_scale()), node.global_position)
	check(Vector3(bulk.packed_buffer[0], bulk.packed_buffer[4], bulk.packed_buffer[8]).is_equal_approx(expected.basis.x)
		and Vector3(bulk.packed_buffer[3], bulk.packed_buffer[7], bulk.packed_buffer[11]).is_equal_approx(expected.origin), "CPU buffer stores documented row-major basis and origin")
	check(is_equal_approx(bulk.packed_buffer[15], node.modulate.a), "CPU buffer retains intrinsic color and source fade alpha")
	if DisplayServer.get_name() == "headless":
		print("IMPACT_EFFECTS_GPU_SKIPPED: Compatibility MultiMesh transform/color readback")
		return
	for index: int in range(normal._fragment_count):
		check(normal._fragment_multimesh.get_instance_transform(index).is_equal_approx(bulk._fragment_multimesh.get_instance_transform(index)), "actual Compatibility bulk transform matches per-instance setter")
		check(normal._fragment_multimesh.get_instance_color(index).is_equal_approx(bulk._fragment_multimesh.get_instance_color(index)), "actual Compatibility bulk color/alpha matches per-instance setter")
