extends SceneTree
## Actual diagnostic-node authority/mesh lifecycle. Headless does not accept GPU pixels.
const BENCH = preload("res://../tests/gameplay/arsenal_web_benchmark.gd")
var checks: int = 0
var failures: int = 0
var bench: BENCH

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ARSENAL WEB BENCH NODE: " + label)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout

func wait_ready(label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 35000
	while (not bench._mesh_ready() or not bench._effects_ready) and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(bench._mesh_ready() and bench._effects_ready, label + " completes real deferred map/resource preparation")
	await frames(8)
	return bench._mesh_ready() and bench._effects_ready

func exercise() -> void:
	if not await wait_ready("initial benchmark"): return
	check(not bench._start_button.disabled and bench.data.get_block(Vector3i(60,12,60)) != 0, "real ready button exposes a supported roof before any canonical edits")
	bench._saturation_box.button_pressed = true
	bench._start_button.pressed.emit()
	check(bench._running and bench.terrain.has_pending(), "actual manual Start accepts one bounded source support cut")
	if not bench._running: return
	await frames(3)
	bench._pause_button.pressed.emit()
	var tick: int = bench._tick
	var sequence: int = bench.data.map_sequence
	var roof: int = bench._roof_removed
	var frame_count: int = bench._frames
	var particle: Dictionary = bench.effects.particle_snapshot(0)
	check(bench._paused and not bench.effects.is_processing(), "actual Pause disables terrain/effects clocks")
	await frames(8)
	check(bench._tick == tick and bench.data.map_sequence == sequence and bench._roof_removed == roof, "eight real scene frames cannot advance paused canonical edits/work")
	check(bench._frames > frame_count and bench.effects.particle_snapshot(0) == particle, "render callbacks continue while paused particle age/position remain frozen")
	bench._pause_button.pressed.emit()
	check(not bench._paused and bench.effects.is_processing(), "actual Resume reopens the same measurement without reset")
	var deadline: int = Time.get_ticks_msec() + 35000
	while not bench._render_complete and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(bench._authority_complete and bench._render_complete and not bench._running and not bench.terrain.has_pending(), "both canonical authority and actual deferred mesh publication fully drain")
	check(bench._mesh_ready() and not bench.world.get_rebuild_stats().active_build, "completion waits the real world-work API rather than a decorative timer")
	var report: Dictionary = bench.report()
	check(report.failures.is_empty() and report.roof_removed == 24576 and report.total_removed == 24580, "every detached roof/pillar cell is actually committed once")
	check(report.fixed_ticks == 145 and report.helper.max_work <= 512 and report.helper.max_changes <= 256 and report.helper.jobs == 0 and report.helper.guard_cells == 0, "large native diagnostic reaches finite completion with actual hard cell/job/watch bounds")
	check(report.max_particles == 50 and report.max_view_states == 64 and report.max_view_events == 12, "actual existing particle/view pools saturate at their independent declared non-growing capacities")
	check(report.effects.particle_slot_capacity == 50 and report.effects.particle_hard_cap == 50 and report.view.particle_count == 0, "decorative stress uses one50particle pool and no extra particles from ArsenalView")
	check(report.step_samples.size() == 145 and report.frame_samples.size() <= 1200 and report.pause_samples.size() == 2, "bounded raw samples preserve each authority step and both user pause edges")
	var total: int = 0
	var maximum: int = 0
	var paused_frames: int = 0
	for row: Dictionary in report.step_samples:
		total += int(row.authority_usec)
		maximum = maxi(maximum,int(row.authority_usec))
		check(int(row.work_cells) <= 512 and int(row.changed_cells) <= 256, "raw fixed-step observation retains the real work/change budget")
	for row: Dictionary in report.frame_samples:
		if row.paused: paused_frames += 1
	check(total == report.authority_cpu_total_usec and maximum == report.authority_cpu_max_usec, "reported CPU total/max are calculated from measured steps, not amortized render FPS")
	check(paused_frames >= 8 and report.callback_rate_includes_pauses and not report.step_samples_truncated, "pause render frames are explicitly flagged and excluded from a false active-FPS interpretation")
	check(not report.web and report.physics_hz == 60 and report.rendering_method == "gl_compatibility", "native diagnostic reports exact execution profile without a browser/GPU claim")
	var previous_data: VoxelData = bench.data
	var previous_helper: RefCounted = bench.terrain
	var previous_epoch: int = bench._epoch
	var allocations: int = int(bench.effects.stats().particle_state_allocations)
	bench.reset_fixture()
	check(bench._epoch > previous_epoch and bench.data != previous_data and bench.terrain != previous_helper, "actual Reset installs a new fixture epoch/data/helper")
	check(not previous_data.cells_committed.is_connected(Callable(previous_helper,"_on_cells_committed")) and not previous_helper.has_pending(), "reset disposes the old helper observer and all retained jobs")
	check(not bench.terrain.has_pending() and bench._tick == 0 and bench._roof_removed == 0 and bench.data.get_block(Vector3i(60,12,60)) != 0, "explicit reset restores roof without executing old delayed work")
	check(bench.effects.particle_count() == 0 and bench.effects.stats().particle_state_allocations == allocations and bench.view.get_display_state().state_count == 0, "reset clears visible saturation while retaining bounded reusable allocations")
	check(bench._last_report.authority_complete and bench._last_report.mesh_complete, "reset retains a downloadable immutable completed measurement")
	if not await wait_ready("reset benchmark"): return
	bench._start_button.pressed.emit()
	await frames(2)
	check(bench.terrain.has_pending(), "second real measurement is active before mid-job Reset")
	previous_epoch = bench._epoch
	previous_helper = bench.terrain
	bench.reset_fixture()
	await frames(3)
	check(bench._epoch > previous_epoch and not previous_helper.has_pending() and not bench.terrain.has_pending() and bench.data.get_block(Vector3i(40,4,40)) != 0, "mid-job reset cancels remaining old support/collapse work at a new epoch")
	check(not bench._last_report.authority_complete and bench._last_report.fixed_ticks > 0, "aborted measurement is retained honestly as incomplete")
	print("ARSENAL WEB BENCH NODE METRICS: roof=%d ticks=%d helper_total_usec=%d helper_max_usec=%d render_callbacks=%d pause_frames=%d" % [report.roof_removed,report.fixed_ticks,report.authority_cpu_total_usec,report.authority_cpu_max_usec,report.rendered_callbacks,paused_frames])

func run() -> void:
	var previous_hz: int = Engine.physics_ticks_per_second
	bench = BENCH.new()
	bench.source_hint = "Native fixture only; source revision recorded by release coordinator"
	root.add_child(bench)
	await exercise()
	bench.queue_free()
	await frames(3)
	Engine.physics_ticks_per_second = previous_hz
	print("ARSENAL WEB BENCH NODE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
