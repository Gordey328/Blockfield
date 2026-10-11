extends SceneTree
## Opt-in CPU/allocation baseline. It does not establish exported-browser FPS.
const READER = preload("res://world/vxl_reader.gd")
const DATA = preload("res://world/voxel_data.gd")
var max_columns: int = 1024
var max_usec: int = 2000
var failures: int = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--columns="):
			max_columns = maxi(1, int(argument.trim_prefix("--columns=")))
		elif argument.begins_with("--usec="):
			max_usec = maxi(1, int(argument.trim_prefix("--usec=")))
	call_deferred("_run")

func _percentile(values: Array[int], fraction: float) -> int:
	if values.is_empty():
		return 0
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)]

func _drive(job: RefCounted, kind: String, memory_before: int) -> Dictionary:
	var batches: Array[int] = []
	var started: int = Time.get_ticks_usec()
	var work_usec: int = 0
	var memory_peak: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var cap_ok: bool = true
	var first_progress_usec: int = 0
	while not bool(job.get("done")):
		var stats: Dictionary = job.call("advance", max_columns, max_usec)
		batches.append(int(stats.elapsed_usec))
		work_usec += int(stats.elapsed_usec)
		if first_progress_usec == 0:
			first_progress_usec = Time.get_ticks_usec() - started
		cap_ok = cap_ok and int(stats.processed_columns) <= max_columns
		memory_peak = maxi(memory_peak, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		if not bool(job.get("done")):
			await process_frame
	var wall_usec: int = Time.get_ticks_usec() - started
	batches.sort()
	var final_stats: Dictionary = job.call("advance", 0, 0)
	if int(job.get("error")) != OK or not cap_ok:
		failures += 1
	return {"kind": kind, "error": job.get("error"), "setup_usec": job.get("setup_usec"),
		"wall_usec_including_frame_waits": wall_usec, "column_work_usec": work_usec,
		"first_batch_usec": first_progress_usec, "batches": batches.size(),
		"p50_batch_usec": _percentile(batches, 0.5), "p95_batch_usec": _percentile(batches, 0.95),
		"p99_batch_usec": _percentile(batches, 0.99), "max_batch_usec": _percentile(batches, 1.0),
		"column_cap": max_columns, "time_target_usec": max_usec, "hard_column_cap_ok": cap_ok,
		"native_static_memory_before": memory_before, "native_static_memory_peak": memory_peak,
		"native_static_memory_after": int(Performance.get_monitor(Performance.MEMORY_STATIC)), "final": final_stats}

func _run() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/openspades/maps/Title.vxl")
	var sync_started: int = Time.get_ticks_usec()
	var sync_decoded: Dictionary = READER.decode(bytes)
	var sync_decode_usec: int = Time.get_ticks_usec()-sync_started
	sync_decoded.clear()
	var memory_before: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var decode: READER.DecodeJob = READER.begin_decode(bytes)
	var decode_report: Dictionary = await _drive(decode, "native_decode", memory_before)
	if decode.error != OK:
		push_error("Native incremental decode failed")
		quit(1)
		return
	var data: VoxelData = DATA.new()
	data.dimensions = decode.result_data.size
	data.blocks = decode.result_data.blocks
	decode = null
	sync_started = Time.get_ticks_usec()
	var native_expected: PackedByteArray = READER.encode(data.blocks, data.dimensions)
	var sync_native_encode_usec: int = Time.get_ticks_usec()-sync_started
	memory_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var encode: READER.EncodeJob = READER.begin_encode(data)
	var encode_report: Dictionary = await _drive(encode, "native_encode", memory_before)
	encode_report["byte_equal_to_sync"] = encode.result_bytes == native_expected
	encode_report["result_bytes"] = encode.result_bytes.size()
	encode_report["snapshot_bytes"] = encode.snapshot_bytes
	if not bool(encode_report.byte_equal_to_sync):
		failures += 1
	encode = null
	data = null
	native_expected = PackedByteArray()
	bytes = PackedByteArray()
	await process_frame
	var lab: VoxelData = DATA.new()
	lab.generate_lab()
	sync_started = Time.get_ticks_usec()
	var lab_expected: PackedByteArray = READER.encode(lab.blocks, lab.dimensions)
	var sync_lab_encode_usec: int = Time.get_ticks_usec()-sync_started
	memory_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	encode = READER.begin_encode(lab)
	var lab_report: Dictionary = await _drive(encode, "lab_encode_virtual_padding", memory_before)
	lab_report["byte_equal_to_sync"] = encode.result_bytes == lab_expected
	lab_report["result_bytes"] = encode.result_bytes.size()
	lab_report["snapshot_bytes"] = encode.snapshot_bytes
	lab_report["full_native_padding_bytes"] = 0
	if not bool(lab_report.byte_equal_to_sync):
		failures += 1
	encode = null
	lab = null
	lab_expected = PackedByteArray()
	await process_frame
	print("VXL JOB BENCHMARK: ", JSON.stringify({"engine": Engine.get_version_info(),
		"unchanged_sync_cpu_usec":{"decode":sync_decode_usec,"native_encode":sync_native_encode_usec,"lab_encode":sync_lab_encode_usec},
		"native_static_memory_only": true, "unavoidable_decode_allocation_bytes": 67108864,
		"decode": decode_report, "native_encode": encode_report, "lab_encode": lab_report,
		"native_static_memory_after_release": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"failures": failures}))
	quit(1 if failures else 0)
