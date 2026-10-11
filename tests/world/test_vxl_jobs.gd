extends SceneTree
## Incremental VXL equivalence, ownership, hard work caps and atomic lifecycle.
const READER = preload("res://world/vxl_reader.gd")
const DATA = preload("res://world/voxel_data.gd")
const WORLD = preload("res://world/voxel_world.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("VXL JOBS: " + message)

func _complete(job: RefCounted) -> Dictionary:
	var batches: int = 0
	var valid_cap: bool = true
	var previous: int = int(job.get("columns_done"))
	var last: Dictionary = {}
	while not bool(job.get("done")) and batches < 300000:
		last = job.call("advance", 4096, 1000000)
		valid_cap = valid_cap and int(last.processed_columns) <= 4096 and int(last.columns_done) >= previous
		previous = int(last.columns_done)
		batches += 1
	check(valid_cap and bool(job.get("done")), "job completes with monotonic progress and hard per-advance column cap")
	return last

func _small_map() -> VoxelData:
	var value: VoxelData = DATA.new()
	value.clear(Vector3i(8, 8, 8), 31)
	value.seed_box(Vector3i.ZERO, Vector3i(8, 2, 8), 0x01665544)
	value.seed_box(Vector3i(2, 2, 2), Vector3i(3, 3, 3), 0x01000000)
	value.seed_box(Vector3i(4, 4, 4), Vector3i(5, 5, 5), 0x01123456)
	return value

func _malformed() -> void:
	var cases: Array[PackedByteArray] = [
		PackedByteArray([1, 2, 3]),
		PackedByteArray([0, 63, 61, 0, 1, 2, 3, 4]),
		PackedByteArray([0, 0, 63, 0]),
		PackedByteArray([2, 10, 10, 0, 1, 2, 3, 255]),
		PackedByteArray([2, 10, 10, 0, 1, 2, 3, 255, 0, 62, 62, 5, 1, 2, 3, 255])]
	for bytes: PackedByteArray in cases:
		var expected: Dictionary = READER.decode(bytes)
		var job: READER.DecodeJob = READER.begin_decode(bytes)
		var stats: Dictionary = _complete(job)
		check(job.error == expected.error and job.result_data == expected, "incremental malformed rejection matches synchronous error/message/offset")
		check(stats.retained_input_bytes == 0 and stats.retained_work_bytes == 0, "failed decode releases private input and partial terrain")
	var source: VoxelData = _small_map()
	source.blocks[0] = 0
	var invalid: READER.EncodeJob = READER.begin_encode(source)
	_complete(invalid)
	check(invalid.error == ERR_INVALID_DATA and invalid.result_bytes.is_empty() and READER.encode(source.blocks, source.dimensions).is_empty(), "invalid immutable floor is rejected without partial output")
	check(invalid.advance(0, 0).retained_snapshot_bytes == 0, "failed encode releases captured terrain")
	var empty: READER.EncodeJob = READER.begin_encode(null)
	check(empty.done and empty.error == ERR_INVALID_PARAMETER, "null encode input is rejected before snapshot allocation")

func _ownership_and_padding() -> PackedByteArray:
	var source: VoxelData = _small_map()
	var expected: PackedByteArray = READER.encode(source.blocks, source.dimensions)
	var job: READER.EncodeJob = READER.begin_encode(source)
	check(job.snapshot_bytes == 8 * 8 * 8 * 4, "small-map snapshot has no full-native padding allocation")
	check(job.advance(0, 2000).processed_columns == 0 and job.advance(1, 0).processed_columns == 0 and job.columns_done == 0, "zero encode budgets do no column work")
	var first: Dictionary = job.advance(3, 1000000)
	check(first.processed_columns == 3 and job.columns_done == 3 and not job.done, "encode honors exact requested column count")
	source.seed_box(Vector3i(2, 2, 2), Vector3i(3, 3, 3), 0x01ffffff)
	source.seed_box(Vector3i(7, 7, 7), Vector3i(8, 8, 8), 0x01ff0000)
	var complete: Dictionary = _complete(job)
	check(job.error == OK and job.result_bytes == expected and job.progress == 1.0, "save uses the version captured before live recolor/placement")
	check(complete.retained_snapshot_bytes == 0 and complete.retained_output_bytes == 0, "successful encode releases snapshot and transfers output")
	var restored: Dictionary = READER.decode(job.result_bytes)
	var restored_blocks: PackedInt32Array = restored.blocks
	check(restored_blocks[64 * (2 + 512 * 2) + 2] == 0x01000000 and restored_blocks[64 * (4 + 512 * 4) + 4] == 0x01123456, "padded save preserves solid black and detached surface colors")
	check(restored_blocks[64 * (400 + 512 * 400)] != 0 and restored_blocks[64 * (400 + 512 * 400) + 1] != 0 and restored_blocks[64 * (400 + 512 * 400) + 2] == 0, "virtual padding preserves exactly two safe floor layers outside small map")
	restored = {}
	restored_blocks = PackedInt32Array()
	var bytes: PackedByteArray = expected.duplicate()
	var decode: READER.DecodeJob = READER.begin_decode(bytes)
	bytes[0] = 255
	check(decode.advance(1, 0).processed_columns == 0 and decode.advance(0, 2000).processed_columns == 0, "zero decode budgets do no column work")
	first = decode.advance(7, 1000000)
	check(first.processed_columns == 7 and decode.result_data.is_empty(), "partial decode remains private and honors requested column count")
	complete = _complete(decode)
	var sync: Dictionary = READER.decode(expected)
	check(decode.error == OK and decode.result_data == sync, "decode is independent of later caller byte mutation and matches full synchronous data")
	check(complete.retained_input_bytes == 0 and complete.retained_work_bytes == 0, "successful decode releases temporary ownership after output transfer")
	decode = null
	sync = {}
	var cancelled_decode: READER.DecodeJob = READER.begin_decode(expected)
	cancelled_decode.advance(1, 1)
	cancelled_decode.cancel()
	var cancelled: Dictionary = cancelled_decode.advance(10, 1000000)
	check(cancelled_decode.done and cancelled_decode.error == ERR_SKIP and not cancelled_decode.result_data.has("blocks"), "cancelled decode exposes no partial map")
	check(cancelled.retained_input_bytes == 0 and cancelled.retained_work_bytes == 0 and cancelled.processed_columns == 0, "cancelled decode remains inert and releases terrain/input")
	var cancelled_encode: READER.EncodeJob = READER.begin_encode(source)
	cancelled_encode.advance(1, 1)
	cancelled_encode.cancel()
	cancelled = cancelled_encode.advance(10, 1000000)
	check(cancelled_encode.error == ERR_SKIP and cancelled_encode.result_bytes.is_empty() and cancelled.retained_snapshot_bytes == 0 and cancelled.retained_output_bytes == 0, "cancelled encode releases snapshot/output and cannot resume")
	return expected

func _native() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/openspades/maps/Title.vxl")
	check(not bytes.is_empty(), "committed original Title fixture is available")
	var expected: Dictionary = READER.decode(bytes)
	var decode: READER.DecodeJob = READER.begin_decode(bytes)
	_complete(decode)
	check(decode.error == OK and decode.result_data == expected, "all native Title occupancy/color cells and consumed byte count match synchronous decode")
	decode = null
	var source: VoxelData = DATA.new()
	source.dimensions = expected.size
	source.blocks = expected.blocks
	expected = {}
	var encoded: PackedByteArray = READER.encode(source.blocks, source.dimensions)
	var job: READER.EncodeJob = READER.begin_encode(source)
	check(job.snapshot_bytes == 67108864, "native save explicitly owns one 64 MiB terrain snapshot")
	_complete(job)
	check(job.error == OK and job.result_bytes == encoded, "native incremental encoding is byte-identical to existing synchronous encoding")
	check(job.advance(0, 0).retained_snapshot_bytes == 0, "native encode completion releases all snapshot terrain")

func _padding_fast_paths() -> void:
	var dimensions: Array[Vector3i] = [Vector3i(2, 1, 2), Vector3i(3, 4, 2), Vector3i(512, 1, 512)]
	for size: Vector3i in dimensions:
		var source: VoxelData = DATA.new()
		source.clear(size)
		source.seed_box(Vector3i.ZERO, Vector3i(size.x, mini(size.y, 2), size.z), 0x01000000)
		if size.y > 2:
			# Right/back boundary surfaces meet virtual air above the padded floor.
			source.seed_box(Vector3i(size.x - 1, 2, size.z - 1), Vector3i(size.x, size.y, size.z), 0x01abc123)
		var expected: PackedByteArray = READER.encode(source.blocks, source.dimensions)
		var job: READER.EncodeJob = READER.begin_encode(source)
		_complete(job)
		check(job.error == OK and job.result_bytes == expected, "padding fast path matches synchronous bytes at source borders and height=%d, x=%d, z=%d" % [size.y, size.x, size.z])
	var invalid: VoxelData = DATA.new()
	invalid.clear(Vector3i(2, 1, 2))
	invalid.seed_box(Vector3i.ZERO, Vector3i(2, 1, 2), 0x01112233)
	invalid.blocks[3] = 0 # Last real column, after a whole row of fast padding.
	var failed: READER.EncodeJob = READER.begin_encode(invalid)
	_complete(failed)
	check(failed.error == ERR_INVALID_DATA and failed.result_bytes.is_empty() and READER.encode(invalid.blocks, invalid.dimensions).is_empty(), "missing boundary floor discards fast padded prefixes instead of exposing a partial save")
	var released: Dictionary = failed.advance(0, 0)
	check(released.retained_snapshot_bytes == 0 and released.retained_output_bytes == 0, "late invalid floor releases padded output and snapshot")

func _collect_load(world: VoxelWorld, bytes: PackedByteArray, title: String, results: Array) -> void:
	results.append(await world.load_vxl_bytes_incremental(bytes, title, 1, 1000000))

func _collect_save(world: VoxelWorld, results: Array) -> void:
	results.append(await world.encode_vxl_incremental(1, 1000000))

func _world_lifecycle(bytes: PackedByteArray) -> void:
	var world: VoxelWorld = WORLD.new()
	world.clear_world(Vector3i(8, 8, 8))
	root.add_child(world)
	world._fill_box(Vector3i.ZERO, Vector3i(8, 2, 8), 0x01665544)
	var original: VoxelData = world.data
	var previous_epoch: int = original.epoch
	var loaded: Array[String] = []
	world.map_loaded.connect(func(title: String) -> void: loaded.append(title))
	var results: Array = []
	_collect_load(world, bytes, "Cancelled", results)
	check(world.get_vxl_job_stats().active and world.get_vxl_job_stats().kind == "load" and world.data == original and loaded.is_empty(), "load progresses privately without early adoption or map-loaded signal")
	world.set_block(Vector3i(3, 2, 3), 0x01123456)
	await process_frame
	check(world.get_vxl_job_stats().active and world.data == original and world.get_block(Vector3i(3, 2, 3)) == 0x01123456, "same-map live edit does not cancel private decode")
	world.clear_world(Vector3i(8, 8, 8))
	await process_frame
	check(results == [ERR_SKIP] and loaded.is_empty() and world.data.epoch == previous_epoch + 1, "reset cancels private load and blocks stale adoption")
	world._fill_box(Vector3i.ZERO, Vector3i(8, 2, 8), 0x01665544)
	results.clear()
	_collect_load(world, bytes, "Superseded", results)
	var saved: Array = []
	_collect_save(world, saved)
	check(world.get_vxl_job_stats().kind == "save", "save supersedes an active load through the exclusive operation token")
	await process_frame
	check(results == [ERR_SKIP], "superseded load returns cancellation without installing its map")
	world.cancel_vxl_jobs()
	await process_frame
	check(saved.size() == 1 and saved[0].is_empty() and not world.get_vxl_job_stats().active and world.get_vxl_job_stats().cancelled, "explicit cancellation prevents stale save output and releases snapshot")
	results.clear()
	_collect_load(world, bytes, "Detached", results)
	root.remove_child(world)
	await process_frame
	check(results == [ERR_SKIP] and not world.get_vxl_job_stats().active, "tree exit safely cancels and drains an awaited map load")
	root.add_child(world)
	var invalid_epoch: int = world.data.epoch
	var invalid_data: VoxelData = world.data
	var failure: Error = await world.load_vxl_bytes_incremental(PackedByteArray([1, 2, 3]), "Invalid")
	check(failure == ERR_FILE_CORRUPT and world.data == invalid_data and world.data.epoch == invalid_epoch and loaded.is_empty(), "malformed async load preserves previous data/epoch and emits no map-loaded signal")
	world.data.water_level = 1.5
	world.data.wade_origin_level = 2.5
	var success: Error = await world.load_vxl_bytes_incremental(bytes, "Complete", 8192, 1000000)
	check(success == OK and world.data != invalid_data and world.data.epoch == invalid_epoch + 1 and loaded == ["Complete"], "complete decode installs one new Data version and emits exactly one map-loaded signal")
	check(world.data.water_level == 1.5 and world.data.wade_origin_level == 2.5 and world.data.map_sequence == 0 and world.data.last_tick == 0 and world.get_stats().chunks == 0, "atomic async adoption preserves water metadata and resets map counters with deferred geometry")
	var sync: PackedByteArray = world.encode_vxl()
	var async_bytes: PackedByteArray = await world.encode_vxl_incremental(8192, 1000000)
	check(async_bytes == sync and world.get_vxl_job_stats().progress == 1.0 and not world.get_vxl_job_stats().active, "awaited World save returns coherent byte-identical output and final progress")
	world.free()

func _run() -> void:
	_malformed()
	var bytes: PackedByteArray = _ownership_and_padding()
	_padding_fast_paths()
	_native()
	await _world_lifecycle(bytes)
	print("VXL JOB TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
