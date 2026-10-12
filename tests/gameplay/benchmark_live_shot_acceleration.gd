extends SceneTree
## Paired complete live salvo queries; includes per-shot cache creation/builds.
## No whole-frame, GPU or browser speed claim. Uses current original single-ray
## entry points as the uncached baseline, with identical actor/ray/order checksums.
const PLAYER = preload("res://gameplay/player_controller.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const CACHE = preload("res://gameplay/shot_hit_pose_cache.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const BATCHES: int = 64
const SAMPLES: int = 5
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func _lab(count: int) -> BlockfieldPlayer:
	var player: BlockfieldPlayer = PLAYER.new()
	player.session = LocalSession.new()
	for index: int in range(count):
		var id: int = player.session.add_target(Vector3(12.5 if index == 0 else 20+index*1.1,4,15.5-index*.4))
		var target: Dictionary = player.session.get_target(id)
		target.yaw = index*.21; target.pitch = sin(index)*.4
		target.state = "crouching" if index%2 else "standing"
	return player

func _shared(count: int) -> MatchSimulation:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(96,16,96),7)
	data.seed_box(Vector3i.ZERO,Vector3i(96,4,96),0x01608040)
	var simulation: MatchSimulation = MATCH.new()
	simulation.configure(data)
	for index: int in range(count):
		var added: Dictionary = simulation.add_actor("Actor%d" % index)
		var actor: SharedPlayerState = simulation.get_actor(added.actor_id)
		# CPU queries only; independent live actors need no spawn overlap checks.
		actor.spawn_generation = 1; actor.health = 100; actor.team = 1
		actor.motion.feet_position = Vector3(12.5 if index == 0 else 20+index*1.1,4,15.5-index*.4)
		actor.yaw = index*.21; actor.pitch = sin(index)*.4; actor.motion.crouch = bool(index%2)
	return simulation

func _measure(player: BlockfieldPlayer, simulation: MatchSimulation, rays: Array[Vector3], cached: bool, batches: int) -> Dictionary:
	var hits: int = 0
	var checksum: float = 0.0
	var origin: Vector3 = Vector3(12.5,6.35,30.5)
	var started: int = Time.get_ticks_usec()
	for batch: int in range(batches):
		var cache: CACHE = CACHE.new() if cached else null
		for ray: Vector3 in rays:
			var result: Dictionary = player.raycast_targets(origin,ray,500,cache) if player != null else simulation.raycast_actors(0,origin,ray,cache)
			if not result.is_empty():
				hits += 1
				checksum += result.distance
	return {"elapsed_us":Time.get_ticks_usec()-started,"hits":hits,"distance_checksum":checksum}

func _measure_scalars(scalar_mode: bool, reads: int) -> Dictionary:
	var checksum: int = 0
	var started: int = Time.get_ticks_usec()
	for index: int in range(reads):
		var profile: String = "0.75" if index%2 == 0 else "0.76"
		var weapon: int = index%3
		if scalar_mode:
			checksum += PROFILES.clip_size(profile,weapon) + (10 if PROFILES.is_slow_reload(profile,weapon) else 0)
		else:
			var copied: Dictionary = PROFILES.get_info(profile,weapon)
			checksum += int(copied.clip_size) + (10 if bool(copied.slow_reload) else 0)
	return {"elapsed_us":Time.get_ticks_usec()-started,"checksum":checksum}

func _scalar_report() -> Dictionary:
	const READS: int = 20000
	_measure_scalars(false,200); _measure_scalars(true,200)
	var samples: Array[Dictionary] = []
	var baseline_times: Array[int] = []; var candidate_times: Array[int] = []
	for sample: int in range(SAMPLES):
		var baseline: Dictionary; var candidate: Dictionary
		if sample%2 == 0:
			baseline = _measure_scalars(false,READS); candidate = _measure_scalars(true,READS)
		else:
			candidate = _measure_scalars(true,READS); baseline = _measure_scalars(false,READS)
		if baseline.checksum != candidate.checksum: failures += 1
		baseline_times.append(baseline.elapsed_us); candidate_times.append(candidate.elapsed_us)
		samples.append({"baseline_us":baseline.elapsed_us,"candidate_us":candidate.elapsed_us,"checksum":baseline.checksum})
	baseline_times.sort(); candidate_times.sort()
	var result: Dictionary = {"reads_per_sample":READS,"samples":samples,"baseline_median_us":baseline_times[SAMPLES >> 1],"candidate_median_us":candidate_times[SAMPLES >> 1]}
	result.speedup = float(result.baseline_median_us)/result.candidate_median_us
	print("LIVE_SHOT_BENCHMARK scalar provider: %.2fx for%d paired clip/slow-reload reads" % [result.speedup,READS])
	return result

func _run() -> void:
	var rays: Array[Vector3] = []
	for index: int in range(8): rays.append(Vector3((index-3.5)*.0015,(index%3-1)*.002,-1).normalized())
	var reports: Array[Dictionary] = []
	for count: int in [5,32]:
		for adapter: String in ["lab","shared"]:
			var player: BlockfieldPlayer = _lab(count) if adapter == "lab" else null
			var simulation: MatchSimulation = _shared(count) if adapter == "shared" else null
			_measure(player,simulation,rays,false,4); _measure(player,simulation,rays,true,4)
			var samples: Array[Dictionary] = []
			var baseline_times: Array[int] = []; var candidate_times: Array[int] = []
			for sample: int in range(SAMPLES):
				var baseline: Dictionary; var candidate: Dictionary
				if sample%2 == 0:
					baseline = _measure(player,simulation,rays,false,BATCHES)
					candidate = _measure(player,simulation,rays,true,BATCHES)
				else:
					candidate = _measure(player,simulation,rays,true,BATCHES)
					baseline = _measure(player,simulation,rays,false,BATCHES)
				if baseline.hits != candidate.hits or baseline.distance_checksum != candidate.distance_checksum:
					failures += 1; push_error("LIVE_SHOT_BENCHMARK: exact result checksum mismatch")
				baseline_times.append(baseline.elapsed_us); candidate_times.append(candidate.elapsed_us)
				samples.append({"baseline_us":baseline.elapsed_us,"candidate_us":candidate.elapsed_us,
					"hits":baseline.hits,"distance_checksum":baseline.distance_checksum})
			baseline_times.sort(); candidate_times.sort()
			var report: Dictionary = {"adapter":adapter,"targets":count,"pellets":8,"salvos_per_sample":BATCHES,
				"baseline_median_us":baseline_times[SAMPLES >> 1],"candidate_median_us":candidate_times[SAMPLES >> 1],
				"samples":samples,"includes_per_shot_preparation":true}
			report.speedup = float(report.baseline_median_us)/report.candidate_median_us
			reports.append(report)
			print("LIVE_SHOT_BENCHMARK %s/%d: %.2fx; %.3fms -> %.3fms per 8-pellet salvo" % [adapter,count,report.speedup,float(report.baseline_median_us)/BATCHES/1000,float(report.candidate_median_us)/BATCHES/1000])
			if player != null:
				player.session.free(); player.free()
	var output: Dictionary = {"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),
		"samples_per_workload":SAMPLES,"workloads":reports,"profile_scalar_reads":_scalar_report(),"failures":failures,
		"scope":"complete live actor-query salvos only; no terrain, damage, frames, graphics or transport"}
	var path: String = ProjectSettings.globalize_path("res://../.cache/benchmarks/live-shot-acceleration.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file == null: failures += 1
	else: file.store_string(JSON.stringify(output,"\t")); file.close()
	quit(0 if failures == 0 else 1)
