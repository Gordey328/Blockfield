extends SceneTree
## Opt-in native memory lifecycle diagnostic; no Main, preferences, audio or effects.
const MODELS = preload("res://presentation/openspades_models.gd")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const DATA = preload("res://world/voxel_data.gd")
const VXL = preload("res://world/vxl_reader.gd")
const TITLE := "res://assets/openspades/maps/Title.vxl"
const COMPACT_SIZE := Vector3i(128, 32, 128)
var cycles: int = 20
var full_vxl: bool = false
var vxl_cycles: int = 1
var output_name: String = "optimization-memory.json"
var checks: int = 0
var failures: int = 0
var errors: Array[String] = []
var points: Array[Dictionary] = []
var color_cycles: Array[Dictionary] = []
var frozen_cycles: Array[Dictionary] = []
var vxl_runs: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if errors.size() < 32: errors.append(message)
		push_error("OPTIMIZATION_MEMORY: " + message)

func _point(label: String, canonical_bytes: int = 0, frozen_bytes: int = 0) -> void:
	points.append({"label":label, "static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_max_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"canonical_bytes":canonical_bytes, "frozen_bytes":frozen_bytes, "models":MODELS.get_cache_stats()})

func _fixture(first_person: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "TeamColor"
	var mesh := BoxMesh.new()
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	MODELS._prepare(node, first_person)
	return node

func _colors(cycle: int) -> void:
	var started := Time.get_ticks_usec()
	var world := _fixture(false)
	var view := _fixture(true)
	for index: int in range(512):
		var rgb := cycle * 512 + index + 1
		var color := Color(float((rgb >> 16) & 255) / 255.0, float((rgb >> 8) & 255) / 255.0, float(rgb & 255) / 255.0)
		MODELS.set_tint(world, color)
		MODELS.set_tint(view, color)
	var stats := MODELS.get_cache_stats()
	_check(stats.world_tints <= MODELS.MAX_TINT_MATERIALS_PER_VIEW and stats.view_tints <= MODELS.MAX_TINT_MATERIALS_PER_VIEW,
		"Arbitrary RGB lifecycle remains bounded")
	color_cycles.append({"cycle":cycle, "colors_per_view":512, "elapsed_usec":Time.get_ticks_usec() - started, "cache":stats})
	world.free()
	view.free()

func _freeze(data: VoxelData, cycle: int, label: String) -> void:
	var size_bytes: int = data.blocks.size() * 4
	_point(label + "-before-freeze-%d" % cycle, size_bytes)
	var started := Time.get_ticks_usec()
	var frozen: VoxelData = data.frozen_copy() as VoxelData
	var elapsed: int = Time.get_ticks_usec() - started
	_point(label + "-frozen-%d" % cycle, size_bytes, frozen.blocks.size() * 4)
	var cell := Vector3i(1, 2, 1)
	var offset: int = data.index(cell)
	var before: int = data.blocks[offset]
	# Packed storage can defer its physical copy until the first live write.
	# Sample both versions while they differ, before restoring or releasing one.
	started = Time.get_ticks_usec()
	data.blocks[offset] = 0x01010203 if before != 0x01010203 else 0x01020304
	var first_write_usec: int = Time.get_ticks_usec() - started
	_point(label + "-after-live-edit-%d" % cycle, size_bytes, frozen.blocks.size() * 4)
	_check(frozen.read_only and frozen.blocks[offset] == before, "Frozen copy retains an independent canonical version")
	data.blocks[offset] = before
	frozen_cycles.append({"cycle":cycle, "label":label, "copy_usec":elapsed, "first_write_usec":first_write_usec,
		"canonical_bytes":size_bytes, "frozen_bytes":frozen.blocks.size() * 4})
	frozen = null
	_point(label + "-released-%d" % cycle, size_bytes)

func _drive(job: RefCounted, label: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var advances: int = 0
	var maximum: int = 0
	var max_retained_work: int = 0
	var max_retained_output: int = 0
	while not job.done and Time.get_ticks_usec() - started < 60000000:
		var metrics: Dictionary = job.advance(1024, 2000)
		advances += 1
		maximum = maxi(maximum, metrics.elapsed_usec)
		max_retained_work = maxi(max_retained_work, int(metrics.get("retained_work_bytes", metrics.get("retained_snapshot_bytes", 0))))
		max_retained_output = maxi(max_retained_output, int(metrics.get("retained_output_bytes", 0)))
		if advances % 32 == 0:
			_point(label + "-advance-%d" % advances)
			await process_frame
	_check(job.done and job.error == OK, label + " completes inside the work deadline")
	if not job.done: job.cancel()
	return {"elapsed_usec":Time.get_ticks_usec() - started, "setup_usec":job.setup_usec,
		"advances":advances, "max_advance_usec":maximum, "max_retained_work_bytes":max_retained_work,
		"max_retained_output_bytes":max_retained_output, "error":job.error}

func _native_vxl() -> void:
	var input := FileAccess.get_file_as_bytes(TITLE)
	_check(not input.is_empty(), "Bundled Title VXL is available")
	if input.is_empty(): return
	for cycle: int in range(vxl_cycles):
		_point("vxl-start-%d" % cycle)
		var decode := VXL.begin_decode(input)
		var decode_metrics: Dictionary = await _drive(decode, "title-decode-%d" % cycle)
		if decode.error != OK: return
		var data := DATA.new()
		data.dimensions = decode.result_data.size
		data.blocks = decode.result_data.blocks
		decode = null
		_point("title-decoded-%d" % cycle, data.blocks.size() * 4)
		_freeze(data, cycle, "title")
		var encode := VXL.begin_encode(data)
		_point("title-encode-snapshot-%d" % cycle, data.blocks.size() * 4, encode.snapshot_bytes)
		var offset: int = data.index(Vector3i(1, 2, 1))
		var before: int = data.blocks[offset]
		var edit_started: int = Time.get_ticks_usec()
		data.blocks[offset] = 0x01010203 if before != 0x01010203 else 0x01020304
		var first_write_usec: int = Time.get_ticks_usec() - edit_started
		_point("title-encode-after-live-edit-%d" % cycle, data.blocks.size() * 4, encode.snapshot_bytes)
		data.blocks[offset] = before
		var encode_metrics: Dictionary = await _drive(encode, "title-encode-%d" % cycle)
		encode_metrics.first_write_usec = first_write_usec
		if encode.error != OK: return
		var encoded_bytes: int = encode.result_bytes.size()
		_check(encoded_bytes > 0, "Successful Title encoding retains its explicit output")
		vxl_runs.append({"cycle":cycle, "input_bytes":input.size(), "canonical_bytes":data.blocks.size() * 4,
			"output_bytes":encoded_bytes, "decode":decode_metrics, "encode":encode_metrics})
		encode = null
		data = null
		await process_frame
		_point("title-released-%d" % cycle)
	input = PackedByteArray()
	var cancel_input := PackedByteArray([0, 62, 62, 0, 40, 64, 103, 0])
	var cancelled_decode := VXL.begin_decode(cancel_input)
	cancelled_decode.cancel()
	var cancelled_metrics: Dictionary = cancelled_decode.advance(1, 2000)
	_check(cancelled_decode.error == ERR_SKIP and cancelled_metrics.retained_input_bytes == 0 and cancelled_metrics.retained_work_bytes == 0,
		"Cancelled decode releases input and native staging storage")
	cancelled_decode = null
	var compact := DATA.new()
	_check(compact.clear(COMPACT_SIZE, 1) == OK, "Cancellation fixture allocation")
	var cancelled_encode := VXL.begin_encode(compact)
	cancelled_encode.cancel()
	cancelled_metrics = cancelled_encode.advance(1, 2000)
	_check(cancelled_encode.error == ERR_SKIP and cancelled_metrics.retained_snapshot_bytes == 0 and cancelled_metrics.retained_output_bytes == 0,
		"Cancelled encode releases frozen snapshot and output storage")
	cancelled_encode = null
	compact = null
	_point("vxl-cancelled-released")

func _run() -> void:
	var started := Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--full-vxl": full_vxl = true
		elif argument.begins_with("--cycles="):
			var raw := argument.trim_prefix("--cycles=")
			cycles = raw.to_int() if raw.is_valid_int() else 0
		elif argument.begins_with("--vxl-cycles="):
			var raw := argument.trim_prefix("--vxl-cycles=")
			vxl_cycles = raw.to_int() if raw.is_valid_int() else 0
		elif argument.begins_with("--output-name="): output_name = argument.trim_prefix("--output-name=")
		else: _check(false, "Unknown benchmark option")
	_check(cycles >= 1 and cycles <= 20 and vxl_cycles >= 1 and vxl_cycles <= 3, "Lifecycle counts stay bounded")
	_check(output_name.ends_with(".json") and output_name.get_file() == output_name and not output_name.contains(":") and not output_name.contains("\\"), "Report filename stays inside the benchmark directory")
	if failures > 0: quit(1); return
	EXTENSIONS.clear()
	MODELS.clear_cache()
	_point("initial")
	var compact := DATA.new()
	_check(compact.clear(COMPACT_SIZE, 1) == OK, "Compact canonical map allocation")
	compact.seed_box(Vector3i.ZERO, Vector3i(128, 4, 128), 0x01608070)
	for cycle: int in range(cycles):
		# Real create() observes the changed extension generation and clears old
		# base/tint caches. No resource packs, settings or preferences are written.
		EXTENSIONS.clear()
		var model := MODELS.create("Player/Head")
		model.free()
		_colors(cycle)
		_point("colors-retained-%d" % cycle, compact.blocks.size() * 4)
		_freeze(compact, cycle, "compact")
		MODELS.clear_cache()
		await process_frame
		_point("cycle-released-%d" % cycle, compact.blocks.size() * 4)
		_check(MODELS.get_cache_stats().retained_materials == 0 and MODELS.get_cache_stats().scenes == 0,
			"Explicit model lifecycle cleanup releases all cache references")
	compact = null
	_point("compact-released")
	if full_vxl: await _native_vxl()
	MODELS.clear_cache()
	EXTENSIONS.clear()
	await process_frame
	await process_frame
	_point("final")
	var report := {"engine":Engine.get_version_info().string, "os":OS.get_name(), "cycles":cycles,
		"full_vxl":full_vxl, "vxl_cycles":vxl_cycles if full_vxl else 0, "elapsed_usec":Time.get_ticks_usec() - started,
		"checks":checks, "failures":failures, "errors":errors, "points":points, "color_cycles":color_cycles,
		"frozen_cycles":frozen_cycles, "vxl_runs":vxl_runs,
		"source_hashes":{"models":FileAccess.get_file_as_string("res://presentation/openspades_models.gd").sha256_text(),
			"voxel_data":FileAccess.get_file_as_string("res://world/voxel_data.gd").sha256_text(),
			"vxl_reader":FileAccess.get_file_as_string("res://world/vxl_reader.gd").sha256_text()},
		"persistent_pools":{"audio":"not instantiated", "effects":"not instantiated", "models":"cache references reported separately at each point"},
		"snapshot_storage":"Canonical and frozen byte counts describe logical retained versions; first live writes are timed and sampled before restore to expose deferred copies.",
		"limits":"Engine static-memory monitors and checkpoint samples, not process RSS, GPU memory or a continuous peak sampler; no renderer/Main/Web acceptance."}
	var directory := ProjectSettings.globalize_path("res://../.cache/benchmarks").simplify_path()
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Benchmark output directory is available")
	var file := FileAccess.open(directory.path_join(output_name), FileAccess.WRITE)
	_check(file != null, "Benchmark report file is writable")
	report.checks = checks
	report.failures = failures
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("OPTIMIZATION_MEMORY: %d checks, %d failures; %s" % [checks, failures, directory.path_join(output_name)])
	quit(0 if failures == 0 else 1)
