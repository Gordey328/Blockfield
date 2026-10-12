extends SceneTree
## Independent original reflective copy oracle. Discover every script property;
## the test intentionally has no hand-maintained list of actor scalar fields.
## --benchmark measures complete owned copies, including motion/RNG construction.
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const DATA = preload("res://world/voxel_data.gd")

class ExtendedState extends STATE:
	var extra_reads: int = 0
	var extension_value: int:
		get:
			extra_reads += 1
			return 71317

var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("PLAYER_STATE_COPY: " + message)

static func legacy_copy(source: SharedPlayerState) -> SharedPlayerState:
	var result: SharedPlayerState = STATE.new(source.player_id,source.player_name,source.match_epoch,source.profile)
	for property: Dictionary in source.get_script().get_script_property_list():
		var key: String = property.name
		if key in ["motion","shot_rng"]: continue
		result.set(key,source.get(key))
	result.motion = source.motion.copy()
	result.shot_rng.state = source.shot_rng.state
	return result

func _equal_values(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if typeof(a) == TYPE_FLOAT and is_nan(a) and is_nan(b): return true
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _equal_values(a[key],b[key]): return false
		return true
	return a == b

func _snapshot(source: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in source.get_script().get_script_property_list():
		var value: Variant = source.get(property.name)
		if value is RandomNumberGenerator: value = {"seed":value.seed,"state":value.state}
		elif value is RefCounted: value = _snapshot(value)
		result[property.name] = value
	return result

func _fill(source: SharedPlayerState, sample: int) -> void:
	var index: int = 0
	for property: Dictionary in source.get_script().get_script_property_list():
		var key: String = property.name
		match int(property.type):
			TYPE_INT: source.set(key,[0,1,-1,0xffffffff,0x7fffffff,sample*97+index][sample%6])
			TYPE_BOOL: source.set(key,(sample+index)%2 == 0)
			TYPE_FLOAT: source.set(key,[-.125-index*.013,0.0,sample+index*.007,INF,NAN][sample%5])
			TYPE_STRING: source.set(key,("0.75" if sample%2 == 0 else "0.76") if key == "profile" else "Игрок%d · %d" % [sample,index])
			TYPE_VECTOR2: source.set(key,Vector2(sample*.013,-index*.017))
		index += 1
	index = 0
	for property: Dictionary in source.motion.get_script().get_script_property_list():
		match int(property.type):
			TYPE_VECTOR3: source.motion.set(property.name,Vector3(sample*.25,index*-.031,(sample-index)*.17))
			TYPE_BOOL: source.motion.set(property.name,(sample+index)%2 == 0)
			TYPE_FLOAT: source.motion.set(property.name,sample*.125-index*.031)
		index += 1
	source.shot_rng.seed = 312719+sample*97
	for draw: int in range(sample%5): source.shot_rng.randf()

func _run() -> void:
	for sample: int in range(30):
		var source: SharedPlayerState = STATE.new()
		_fill(source,sample)
		var before: Dictionary = _snapshot(source)
		var expected: SharedPlayerState = legacy_copy(source)
		var actual: SharedPlayerState = source.copy()
		var actual_fields: Dictionary = _snapshot(actual)
		var expected_fields: Dictionary = _snapshot(expected)
		for property: Dictionary in source.get_script().get_script_property_list():
			var key: String = property.name
			check(_equal_values(actual_fields[key],expected_fields[key]),"all reflective actor fields retain original values: " + key)
		check(actual.motion != source.motion and actual.motion != expected.motion,"owned motion is independent of source and oracle")
		check(actual.shot_rng != source.shot_rng and actual.shot_rng != expected.shot_rng,"owned RNG is independent of source and oracle")
		for draw: int in range(8): check(actual.shot_rng.randf() == expected.shot_rng.randf(),"full isolated RNG sequence remains exact")
		_fill(actual,sample+13)
		actual.motion.feet_position += Vector3(7,2,3)
		actual.shot_rng.randf()
		check(_equal_values(before,_snapshot(source)),"mutating copy scalar/motion/RNG cannot change source")
	var extension: ExtendedState = ExtendedState.new()
	extension.health = 37; extension.motion.feet_position = Vector3(3,7,13)
	extension.shot_rng.seed = 19177
	var original_extension: SharedPlayerState = legacy_copy(extension)
	extension.extra_reads = 0
	var copied_extension: SharedPlayerState = extension.copy()
	check(extension.extra_reads == 1,"extension fallback still visits additional script getter properties")
	check(_equal_values(_snapshot(original_extension),_snapshot(copied_extension)),"extension copy keeps exact original reflective fallback semantics")
	_replay()
	if "--benchmark" in OS.get_cmdline_user_args(): _benchmark()
	print("PLAYER_STATE_COPY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _replay() -> void:
	var source: SharedPlayerState = STATE.new(1,"Replay",7,"0.75",31917)
	check(not RULES.spawn(source,0,Vector3(12.5,4.01,12.5),0,2).is_empty(),"source replay life is valid")
	source.tool_raise = 1.0
	var actual: SharedPlayerState = source.copy()
	var expected: SharedPlayerState = legacy_copy(source)
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(32,16,32),7)
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608040)
	for tick: int in range(240):
		var input: PlayerRules.Command = RULES.Command.new()
		input.sequence = tick+1; input.spawn_generation = source.spawn_generation
		input.buttons = RULES.Buttons.PRIMARY if tick%120 < 60 else RULES.Buttons.RELOAD
		if tick%80 < 20: input.buttons |= RULES.Buttons.CROUCH
		if tick%97 == 0: input.buttons |= RULES.Buttons.JUMP
		input.move = Vector2(.2,-.5) if tick%100 < 50 else Vector2.ZERO
		input.yaw = sin(tick*.031)*.4; input.pitch = cos(tick*.021)*.1
		var actual_events: Array[Dictionary] = RULES.step_fixed(actual,tick,input,data)
		var expected_events: Array[Dictionary] = RULES.step_fixed(expected,tick,input,data)
		check(actual_events == expected_events and _equal_values(_snapshot(actual),_snapshot(expected)),"typed copy retains fixed movement/shoot/reload/crouch/jump replay")
	check(source.magazine == 6 and source.shot_rng.state != actual.shot_rng.state,"replay copies consume ammo/RNG independently of original state")

func _measure(source: SharedPlayerState, legacy: bool, copies: int) -> Dictionary:
	var checksum: int = 0
	var started: int = Time.get_ticks_usec()
	for index: int in range(copies):
		var copied: SharedPlayerState = legacy_copy(source) if legacy else source.copy()
		checksum += copied.player_id+copied.magazine+copied.reserve+copied.walk_steps
	return {"elapsed_us":Time.get_ticks_usec()-started,"checksum":checksum}

func _benchmark() -> void:
	const COPIES: int = 4000
	var source: SharedPlayerState = STATE.new(1,"Bench",7,"0.75",31917)
	RULES.spawn(source,0,Vector3(12.5,4.01,12.5),0,2)
	source.tool_raise = 1.0; source.walk_steps = 71
	_measure(source,true,100); _measure(source,false,100)
	var samples: Array[Dictionary] = []
	var baseline_times: Array[int] = []; var candidate_times: Array[int] = []
	for index: int in range(5):
		var baseline: Dictionary; var candidate: Dictionary
		if index%2 == 0:
			baseline = _measure(source,true,COPIES); candidate = _measure(source,false,COPIES)
		else:
			candidate = _measure(source,false,COPIES); baseline = _measure(source,true,COPIES)
		check(baseline.checksum == candidate.checksum,"paired complete-copy benchmark retains scalar checksum")
		baseline_times.append(baseline.elapsed_us); candidate_times.append(candidate.elapsed_us)
		samples.append({"baseline_us":baseline.elapsed_us,"candidate_us":candidate.elapsed_us,"checksum":baseline.checksum})
	baseline_times.sort(); candidate_times.sort()
	var output: Dictionary = {"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),
		"copies_per_sample":COPIES,"samples":samples,"baseline_median_us":baseline_times[2],"candidate_median_us":candidate_times[2],
		"includes_owned_motion_rng":true,"scope":"complete owned actor copies only; no frame/GPU/browser claim"}
	output.speedup = float(output.baseline_median_us)/output.candidate_median_us
	var path: String = ProjectSettings.globalize_path("res://../.cache/benchmarks/player-state-copy-optimization.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"owned-copy benchmark writes")
	if file != null: file.store_string(JSON.stringify(output,"\t")); file.close()
	print("PLAYER_STATE_COPY_BENCHMARK: %.2fx; %.3fus -> %.3fus per complete owned copy" % [output.speedup,float(baseline_times[2])/COPIES,float(candidate_times[2])/COPIES])
