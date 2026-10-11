extends SceneTree
## Opt-in same-current-code cache A/B and isolated player churn. Not an FPS or PCM proof.
const AUDIO = preload("res://audio/openspades_audio.gd")
var shots: int = 300
var repeats: int = 3
var output_name: String = "audio-optimization.json"
var checks: int = 0
var failures: int = 0
var host: Node3D
var world: VoxelWorld
var camera: Camera3D
var audio: OpenSpadesAudio
var report: Dictionary = {}
var _reference_checksums: Dictionary[String, float] = {}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AUDIO_BENCHMARK: " + label)

func _summary(samples: Array[int]) -> Dictionary:
	if samples.is_empty():return {"count":0}
	var ordered: Array[int] = samples.duplicate()
	ordered.sort()
	var total: int = 0
	for sample: int in samples:total += sample
	return {"count":samples.size(), "mean_us":float(total)/samples.size(), "p50_us":ordered[floori((ordered.size()-1)*.5)],
		"p95_us":ordered[floori((ordered.size()-1)*.95)], "p99_us":ordered[floori((ordered.size()-1)*.99)], "max_us":ordered[-1], "total_us":total}

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):shots = clampi(int(argument.trim_prefix("--shots=")), 30, 3000)
		elif argument.begins_with("--repeats="):repeats = clampi(int(argument.trim_prefix("--repeats=")), 1, 10)
		elif argument.begins_with("--output-name="):
			var requested: String = argument.trim_prefix("--output-name=")
			if requested == requested.get_file() and requested.ends_with(".json"):output_name = requested
	host = Node3D.new()
	root.add_child(host)
	camera = Camera3D.new()
	host.add_child(camera)
	world = VoxelWorld.new()
	world.data.clear(Vector3i(96,32,96), 51)
	world.data.seed_box(Vector3i.ZERO, Vector3i(96,3,96), 0x01706644)
	# Room, wall and open portions share one deterministic bounded arena.
	world.data.seed_box(Vector3i(20,3,20), Vector3i(21,24,50), 0x01a0a0a0)
	world.data.seed_box(Vector3i(49,3,20), Vector3i(50,24,50), 0x01a0a0a0)
	world.data.seed_box(Vector3i(20,3,20), Vector3i(50,24,21), 0x01a0a0a0)
	world.data.seed_box(Vector3i(20,3,49), Vector3i(50,24,50), 0x01a0a0a0)
	world.data.seed_box(Vector3i(20,23,20), Vector3i(50,24,50), 0x01a0a0a0)
	audio = AUDIO.new()
	host.add_child(audio)
	audio.set_process(false)
	audio.setup(world, camera)
	audio.set_workload_timing_enabled(true)
	report = {"engine":Engine.get_version_info(), "os":OS.get_name(), "shots":shots, "repeats":repeats,
		"timing_opt_in":true, "map":"96x32x96 deterministic acoustic arena", "rendered_fps_proof":false,
		"hashes":{"audio":FileAccess.get_sha256("res://audio/openspades_audio.gd"), "environment":FileAccess.get_sha256("res://audio/audio_environment.gd")},
		"ambience":[], "voice_churn":[]}
	for repeat: int in range(repeats):
		# Alternate order to reduce first-run bias without different implementations.
		for enabled: bool in ([false,true] if repeat % 2 == 0 else [true,false]):
			for scenario: String in ["stationary", "moving", "editing"]:
				var result: Dictionary = _ambience_scenario(scenario, enabled, repeat)
				report.ambience.append(result)
				print("AUDIO_BENCHMARK ambience: " + JSON.stringify(result))
		await process_frame
	# Node creation/release cost is isolated from sound loading and actual PCM mixing.
	var baseline_buses: int = AudioServer.get_bus_count()
	AudioServer.add_bus()
	var bus_index: int = AudioServer.get_bus_count()-1
	var silent_bus: StringName = &"AudioBenchmarkSilent"
	AudioServer.set_bus_name(bus_index, silent_bus)
	AudioServer.set_bus_mute(bus_index, true)
	audio.set_output_bus(silent_bus)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var silence: PackedByteArray = PackedByteArray()
	silence.resize(44100*2*4)
	stream.data = silence
	for repeat: int in range(repeats):
		for enabled: bool in [false,true]:
			var churn: Dictionary = await _voice_scenario(stream, enabled, repeat)
			report.voice_churn.append(churn)
			print("AUDIO_BENCHMARK voice_churn: " + JSON.stringify(churn))
	audio.stop()
	audio.world = null
	world.free()
	host.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2).timeout
	AudioServer.remove_bus(AudioServer.get_bus_index(silent_bus))
	check(AudioServer.get_bus_count() == baseline_buses, "benchmark restores audio buses")
	report.checks = checks
	report.failures = failures
	report.pool_gate = "Pool only if player construction/release remains material in the real Web sustained-fire CPU profile after cache gains; isolated churn excludes decoding, mixing and frame scheduling."
	var output: String = ProjectSettings.globalize_path("res://../.cache/previews/audio-optimization/" + output_name)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		check(false, "open benchmark JSON output")
	else:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("AUDIO_BENCHMARK: %d checks, %d failures; %s" % [checks, failures, output])
	quit(1 if failures else 0)

func _ambience_scenario(scenario: String, enabled: bool, repeat: int) -> Dictionary:
	audio.ambience_cache_enabled = enabled
	audio.clear_ambience_cache()
	# Every A/B begins with identical topology, including odd edit counts.
	world.data.set_block(Vector3i(20,8,35), 0x01a0a0a0)
	# Warm both direct legacy rays and script paths, then clear so first query is measured.
	for _index: int in range(10):audio.compute_ambience(Vector3(35,8,35))
	audio.clear_ambience_cache()
	audio.reset_workload_counters()
	var samples: Array[int] = []
	var output_sum: float = 0.0
	for index: int in range(shots):
		var eye: Vector3 = Vector3(35,8,35)
		if scenario == "moving":eye += Vector3(float(index)*.001,0,0)
		if scenario == "editing" and index % 10 == 0:
			var changed: Dictionary = world.data.set_block(Vector3i(20,8,35), 0x01a0a0a0 if world.data.get_block(Vector3i(20,8,35)) == 0 else 0)
			check(bool(changed.ok), "benchmark terrain transaction accepted")
		var started: int = Time.get_ticks_usec()
		var ambience: Dictionary = audio.compute_ambience(eye)
		samples.append(Time.get_ticks_usec()-started)
		output_sum += float(ambience.room) + float(ambience.size)
	var counts: Dictionary = audio.debug_workload()
	check(counts.ambience_calls == shots, "scenario counts every ambience query")
	check(counts.ambience_cache_entries <= AUDIO.MAX_AMBIENCE_CACHE, "scenario cache remains bounded")
	if enabled and scenario == "stationary":check(counts.ambience_cache_hits == shots-1, "stationary cache reuses all unchanged shots after first")
	if enabled and scenario == "moving":check(counts.ambience_cache_hits == 0, "moving exact keys are never quantized")
	if _reference_checksums.has(scenario):
		check(output_sum == _reference_checksums[scenario], "same-input cache A/B retains exact output checksum")
	else:
		_reference_checksums[scenario] = output_sum
	return {"scenario":scenario, "cache":enabled, "repeat":repeat, "query":_summary(samples), "workload":counts, "output_checksum":output_sum}

func _voice_scenario(stream: AudioStreamWAV, enabled: bool, repeat: int) -> Dictionary:
	audio.stop()
	audio.setup(null, camera)
	audio.efx_enabled = enabled
	audio.get_output_bus()
	audio.reset_workload_counters()
	var samples: Array[int] = []
	var synchronous_usec: int = 0
	# Retire batches before awaiting the mixer; no cap ambiguity or live audible output.
	for batch: int in range(6):
		var started: int = Time.get_ticks_usec()
		for _index: int in range(32):
			var one_started: int = Time.get_ticks_usec()
			audio._start_voice(stream, "benchmark_silence", 1.0, Vector3(.4,-.3,.5), true, 1.0)
			samples.append(Time.get_ticks_usec()-one_started)
		audio._process(1.0/60.0)
		synchronous_usec += Time.get_ticks_usec()-started
		await create_timer(.025).timeout
		started = Time.get_ticks_usec()
		for voice: Node in audio._voices.duplicate():audio._release(voice)
		synchronous_usec += Time.get_ticks_usec()-started
		await process_frame
	var counts: Dictionary = audio.debug_workload()
	check(counts.dry_players_created == 192 and counts.wet_players_created == (384 if enabled else 0), "churn counts all physical player allocations")
	check(counts.active_players == 0 and counts.players_released == counts.dry_players_created + counts.wet_players_created, "churn retires every allocated player")
	var allocation_usec: int = int(counts.player_create_usec) + int(counts.player_release_usec)
	var result: Dictionary = {"efx":enabled, "repeat":repeat, "voice_start":_summary(samples), "synchronous_usec":synchronous_usec,
		"allocation_release_usec":allocation_usec, "allocation_release_fraction":float(allocation_usec)/maxi(1,synchronous_usec), "workload":counts,
		"limitations":"zero PCM; excludes stream decode/mixer cost, awaited frames and delayed engine frees; not real-game FPS"}
	audio.stop()
	await create_timer(.2).timeout
	return result
