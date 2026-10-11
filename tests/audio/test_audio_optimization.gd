extends SceneTree
## Exact-origin cache and workload counters, independent of preferences/Main.
const AUDIO = preload("res://audio/openspades_audio.gd")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
var checks: int = 0
var failures: int = 0

class CountingData extends VoxelData:
	var ray_calls: int = 0
	var all_hit: bool = false
	func cast_source_ray_legacy(origin: Vector3, _direction: Vector3, _length: float = 256.0) -> Dictionary:
		ray_calls += 1
		return {"hit": all_hit, "valid": true, "cell": Vector3i(origin.floor()) + Vector3i(7,-1,0)}

class UnversionedWorld extends VoxelWorld:
	var ray_calls: int = 0
	func cast_voxel(_origin: Vector3, _direction: Vector3, _max_dist: float = 128.0) -> Dictionary:
		ray_calls += 1
		return {"hit": false, "valid": true, "cell": Vector3i.ZERO}

class SilentAudio extends OpenSpadesAudio:
	func _play(_path: String, _gain: float, _point: Vector3, _local: bool, _reference_distance: float, _blast_falloff: bool = false) -> Node:
		return null

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var host: Node3D = Node3D.new()
	root.add_child(host)
	var camera: Camera3D = Camera3D.new()
	host.add_child(camera)
	var audio: OpenSpadesAudio = SilentAudio.new()
	host.add_child(audio)
	audio.set_process(false)
	var world: VoxelWorld = VoxelWorld.new()
	var data: CountingData = CountingData.new()
	data.clear(Vector3i(32,32,32), 7)
	world.data = data
	audio.setup(world, camera)
	var eye: Vector3 = Vector3(8,8,8)
	audio.ambience_cache_enabled = false
	audio.reset_workload_counters()
	var uncached: Dictionary = audio.compute_ambience(eye)
	check(uncached == {"room":0.0,"size":1.0}, "independent open-air skin ambience golden")
	check(audio.compute_ambience(eye) == uncached and data.ray_calls == 48, "uncached A/B performs24 rays every query")
	check(audio.debug_workload().ambience_bypasses == 2 and audio.debug_workload().ambience_cache_entries == 0, "disabled cache retains no origins")
	audio.ambience_cache_enabled = true
	audio.reset_workload_counters()
	data.ray_calls = 0
	var first: Dictionary = audio.compute_ambience(eye)
	check(first == uncached and data.ray_calls == 24, "cache miss retains source open-air result")
	first.room = 999
	var cached: Dictionary = audio.compute_ambience(eye)
	check(cached == uncached and data.ray_calls == 24, "caller cannot poison miss result stored in cache")
	cached.size = 999
	check(audio.compute_ambience(eye) == uncached and data.ray_calls == 24, "caller cannot poison cache hit result")
	var counts: Dictionary = audio.debug_workload()
	check(counts.ambience_calls == 3 and counts.ambience_cache_misses == 1 and counts.ambience_cache_hits == 2 and counts.ambience_rays == 24, "cache counters distinguish calls/hits/misses/rays")
	counts.ambience_calls = -1
	check(audio.debug_workload().ambience_calls == 3, "workload snapshot cannot mutate counters")
	check(audio.debug_workload().ambience_usec == 0 and audio.debug_workload().environment_trace_usec == 0, "timers remain disabled in ordinary gameplay")
	var adjacent: Vector3 = eye + Vector3(.0001,0,0)
	audio.compute_ambience(adjacent)
	check(data.ray_calls == 48 and audio.debug_workload().ambience_cache_entries == 2, "nearby finite origins are exact independent keys")
	data.all_hit = true
	check(data.set_block(Vector3i(0,1,0), 0x01ffffff).changed, "fixture advances real transaction sequence")
	var closed: Dictionary = audio.compute_ambience(eye)
	var expected_size: float = 7.0 / 15.0
	var expected_room: float = (1.0 - expected_size * .3)
	check(is_equal_approx(float(closed.size), expected_size) and is_equal_approx(float(closed.room), expected_room), "independent48-ray enclosed room golden")
	check(data.ray_calls == 96 and audio.debug_workload().ambience_cache_entries == 1, "real Data transaction sequence invalidates every old origin")
	check(audio.compute_ambience(eye) == closed and data.ray_calls == 96, "enclosed48-ray query is cached without altered output")
	data.clear(Vector3i(32,32,32), 8)
	audio.compute_ambience(eye)
	check(data.ray_calls == 144, "new epoch invalidates even same exact eye")
	data.map_sequence = 4
	audio.compute_ambience(eye)
	data.map_sequence = 0
	audio.compute_ambience(eye)
	check(data.ray_calls == 240, "forward sequence and baseline rewind invalidate")
	var replacement: CountingData = CountingData.new()
	replacement.clear(Vector3i(32,32,32), data.epoch)
	world.data = replacement
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 24, "same-version Data replacement invalidates by identity")
	var other_world: VoxelWorld = VoxelWorld.new()
	other_world.data = replacement
	audio.world = other_world
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 48, "world identity also belongs to cache scope")
	audio.setup(world, camera)
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 72, "setup clears scoped cache")
	audio.reset_environment()
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 96, "same-version in-place reset clears cache")
	audio.reload_resources()
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 120, "explicit resource reload clears cache")
	var generation_before: int = EXTENSIONS.get_generation()
	EXTENSIONS.clear()
	check(EXTENSIONS.get_generation() > generation_before, "fixture uses real resource generation transition")
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 144, "automatic resource generation invalidation works without Main callback")
	audio.environmental = false
	check(audio.compute_ambience(eye) == {"room":0.0,"size":0.0} and audio.debug_workload().ambience_cache_entries == 0, "environmental off returns native disabled result and clears origins")
	audio.environmental = true
	audio.compute_ambience(eye)
	check(replacement.ray_calls == 168, "re-enabled ambience starts from a fresh query")
	audio.clear_ambience_cache()
	for index: int in range(AUDIO.MAX_AMBIENCE_CACHE + 1):
		audio.compute_ambience(Vector3(index,8,8))
	check(audio.debug_workload().ambience_cache_entries == AUDIO.MAX_AMBIENCE_CACHE, "exact-origin FIFO cache is bounded128")
	var rays_before: int = replacement.ray_calls
	audio.compute_ambience(Vector3(128,8,8))
	check(replacement.ray_calls == rays_before, "newest bounded entry is reusable")
	audio.compute_ambience(Vector3(0,8,8))
	check(replacement.ray_calls == rays_before + 24, "oldest entry is evicted and recomputed")
	var unversioned: UnversionedWorld = UnversionedWorld.new()
	unversioned.data = null
	audio.setup(unversioned, camera)
	audio.compute_ambience(eye)
	audio.compute_ambience(eye)
	check(unversioned.ray_calls == 48 and audio.debug_workload().ambience_cache_entries == 0, "world doubles without a versioned Data query never reuse answers")
	audio.setup(world, camera)
	audio.reset_workload_counters()
	audio.compute_ambience(eye)
	audio._environment.seed_random(328)
	audio._environment.begin_turn(1.0, 128, 0)
	audio._environment.sample_room(eye)
	audio._environment.trace_obstruction(eye, Vector3(10,8,8))
	counts = audio.debug_workload()
	check(counts.ambience_rays == 24 and counts.room_rays == 4 and counts.obstruction_rays == 1 and counts.audio_rays_total == 29, "full audio ray count includes unbudgeted ambience and both environment families")
	check(audio.debug_environment().rays == 5 and audio.debug_environment().workload.audio_rays_total == 29, "existing per-turn budget counter stays separate from full audio workload")
	audio.explosion(eye, false)
	check(audio.debug_workload().ground_rays == 1 and audio.debug_workload().audio_rays_total == 30, "land explosion debris ray is included in full service workload")
	audio.explosion(eye, true)
	check(audio.debug_workload().ground_rays == 1, "water explosion has no invented ground query")
	audio.set_workload_timing_enabled(true)
	audio.clear_ambience_cache()
	audio.compute_ambience(eye)
	check(audio.debug_workload().timing_enabled and audio._environment.workload_timing_enabled, "opt-in timing covers service and environment")
	audio.set_workload_timing_enabled(false)
	# Real native rays, not merely a counting double, match the same-current-code A/B.
	var actual: VoxelData = VoxelData.new()
	actual.clear(Vector3i(32,32,32), 11)
	actual.seed_box(Vector3i(0,0,0), Vector3i(32,2,32), 0x01705533)
	actual.seed_box(Vector3i(12,2,0), Vector3i(13,24,32), 0x01ffffff)
	world.data = actual
	audio.ambience_cache_enabled = false
	var actual_reference: Dictionary = audio.compute_ambience(eye)
	audio.ambience_cache_enabled = true
	check(audio.compute_ambience(eye) == actual_reference and audio.compute_ambience(eye) == actual_reference, "real source fixed-point ray outputs match uncached and cached")
	await _check_voice_counters(audio, camera)
	audio.stop()
	check(audio.debug_workload().active_players == 0 and audio.debug_workload().ambience_cache_entries == 0, "stop releases active players and cached origins")
	audio.reset_workload_counters()
	check(audio.debug_workload().audio_rays_total == 0 and audio.debug_workload().dry_players_created == 0, "explicit counters reset preserves no old workload")
	audio.world = null
	world.free()
	other_world.free()
	unversioned.free()
	host.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2).timeout
	print("AUDIO OPTIMIZATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_voice_counters(audio: OpenSpadesAudio, camera: Camera3D) -> void:
	var baseline: int = AudioServer.get_bus_count()
	AudioServer.add_bus()
	var index: int = AudioServer.get_bus_count() - 1
	var bus: StringName = &"AudioOptimizationSilent"
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_mute(index, true)
	audio.stop()
	audio.set_output_bus(bus)
	audio.setup(null, camera)
	audio.reset_workload_counters()
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var silence: PackedByteArray = PackedByteArray()
	silence.resize(44100 * 2 * 2)
	stream.data = silence
	var voice: Node = audio._start_voice(stream, "optimization_fixture", 1.0, Vector3(.4,-.3,.5), true, 1.0)
	var counts: Dictionary = audio.debug_workload()
	check(counts.dry_players_created == 1 and counts.wet_players_created == 2 and counts.spatial_players_created == 3 and counts.active_players == 3, "dry plus synchronized wet players are counted")
	check(voice.playback_type == AudioServer.PLAYBACK_TYPE_STREAM and voice.get_meta("copies").size() == 2, "instrumentation preserves STREAM and wet routing")
	await create_timer(.05).timeout
	audio.efx_enabled = false
	audio._process(0.0)
	check(audio.debug_workload().active_players == 1 and audio.debug_workload().players_released == 2, "EFX toggle counts removal of both wet copies")
	audio.efx_enabled = true
	audio._process(0.0)
	check(audio.debug_workload().active_players == 3 and audio.debug_workload().wet_players_created == 4, "EFX re-enable counts newly synchronized sends")
	audio._release(voice)
	check(audio.debug_workload().active_players == 0 and audio.debug_workload().players_released == 5, "logical release counts dry and both wet players")
	audio.reset_workload_counters()
	for _index: int in range(129):
		audio._start_voice(stream, "cap_fixture", 1.0, Vector3(.4,-.3,.5), true, 1.0)
	counts = audio.debug_workload()
	check(audio._voices.size() == 128 and counts.active_players == 384 and counts.players_released == 3, "existing logical cap retires oldest complete dry/wet voice")
	check(counts.peak_active_players == 387, "allocation peak includes transient incoming voice before oldest retirement")
	await create_timer(.1).timeout
	audio.stop()
	check(audio.debug_workload().active_players == 0, "cap teardown returns active physical players to zero")
	await process_frame
	await create_timer(.2).timeout
	AudioServer.remove_bus(AudioServer.get_bus_index(bus))
	check(AudioServer.get_bus_count() == baseline, "silent fixture restores all owned audio buses")
