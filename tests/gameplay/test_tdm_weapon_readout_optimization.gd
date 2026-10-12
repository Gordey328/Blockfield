extends SceneTree
## Frozen original getter for exact scalar/readout parity and caller ownership.
## --benchmark compares the complete getters, including returned profile copies.
const SESSION = preload("res://gameplay/offline_tdm_session.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const ARENA = preload("res://ai/tdm_arena.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const PLAYER_STATE = preload("res://simulation/player_state.gd")
const SOURCE_MOTION = preload("res://gameplay/source_player_motion.gd")

class CustomSession extends SESSION:
	var owner_calls: int = 0
	func get_owner_state() -> SharedPlayerState:
		owner_calls += 1
		var owner: SharedPlayerState = PLAYER_STATE.new(1,"Custom",7,"0.76")
		owner.weapon = 2; owner.magazine = 7; owner.reserve = 19
		return owner

class CustomActor extends PLAYER_STATE:
	var copy_calls: int = 0
	func copy() -> SharedPlayerState:
		copy_calls += 1
		var owner: SharedPlayerState = PLAYER_STATE.new(1,"Copied",7,"0.76")
		owner.weapon = 1; owner.magazine = 17; owner.reserve = 87
		return owner

class CustomMotion extends SOURCE_MOTION.State:
	var owner: SharedPlayerState
	var copy_calls: int = 0
	func copy() -> SourcePlayerMotion.State:
		copy_calls += 1
		owner.magazine += 1
		return SOURCE_MOTION.create_state(feet_position)
var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("TDM_WEAPON_READOUT: " + message)

static func legacy_info(session: OfflineTDMSession) -> Dictionary:
	var owner: SharedPlayerState = session.get_owner_state()
	var version: String = owner.profile if owner != null else "0.75"
	var weapon: int = owner.weapon if owner != null else LocalSession.Weapon.RIFLE
	var info: Dictionary = PROFILES.get_info(version,weapon)
	info.weapon_index = weapon
	info.profile = version
	info.magazine = owner.magazine if owner != null else 0
	info.reserve = owner.reserve if owner != null else 0
	return info

func _run() -> void:
	var session: OfflineTDMSession = SESSION.new()
	check(session.get_weapon_info() == legacy_info(session),"absent simulation retains original default profile/weapon/ammo")
	session.simulation = MATCH.new()
	check(session.get_weapon_info() == legacy_info(session),"absent owner actor retains original fallback")
	check(session.configure_match(ARENA.build(),ARENA.metadata(),"Readout").ok,"real3x3 fixture configures")
	var owner: SharedPlayerState = session.simulation.get_actor(SESSION.OWNER_ID)
	for profile: String in ["0.75","0.76"]:
		for weapon: int in range(3):
			for ammo: int in [0,1,29]:
				owner.profile = profile; owner.weapon = weapon
				owner.magazine = ammo; owner.reserve = ammo*4
				var actual: Dictionary = session.get_weapon_info()
				check(actual == legacy_info(session),"all weapon/profile/ammo fields match the original owned-copy getter")
				check(actual.magazine == ammo and actual.reserve == ammo*4 and actual.weapon_index == weapon and actual.profile == profile,"readout sees authority changes immediately while adapter mirror is unchanged")
				actual.magazine = -999; actual.reserve = -999
				actual.name = "Modified by caller"; actual.clip_size = -999
				check(session.get_weapon_info() == legacy_info(session) and owner.magazine == ammo and owner.reserve == ammo*4,"caller mutation cannot change actor or shared weapon profiles")
	for profile: String in ["","invalid"]:
		owner.profile = profile
		check(session.get_weapon_info() == legacy_info(session),"invalid authority profile preserves original metadata-only result")
	owner.profile = "0.75"
	for weapon: int in [-1,3]:
		owner.weapon = weapon
		check(session.get_weapon_info() == legacy_info(session),"invalid authority weapon preserves original metadata-only result")
	owner.weapon = 2; owner.magazine = 6; owner.reserve = 48
	var original_feet: Vector3 = owner.feet()
	var original_rng: int = owner.shot_rng.state
	var copied_owner: SharedPlayerState = session.get_owner_state()
	copied_owner.motion.feet_position += Vector3(5,2,3)
	copied_owner.magazine = -100; copied_owner.reserve = -100
	copied_owner.shot_rng.randf()
	check(owner.feet() == original_feet and owner.magazine == 6 and owner.reserve == 48 and owner.shot_rng.state == original_rng,"public get_owner_state continues to own independent motion/RNG/scalars")
	var info: Dictionary = session.get_weapon_info()
	check(info.magazine == 6 and info.reserve == 48 and owner.feet() == original_feet and owner.shot_rng.state == original_rng,"readout leaves authoritative pose and RNG intact")
	session.simulation.actors.erase(SESSION.OWNER_ID)
	check(session.get_weapon_info() == legacy_info(session),"owner removal immediately restores original fallback")
	# A new match/life must be read through the new simulation, not a retained view.
	check(session.configure_match(ARENA.build(),ARENA.metadata(),"Next life").ok,"new simulation configures after owner removal")
	owner = session.simulation.get_actor(SESSION.OWNER_ID)
	owner.weapon = 1; owner.magazine = 17; owner.reserve = 87
	check(session.get_weapon_info() == legacy_info(session),"simulation replacement and new life preserve fresh original values")
	_extension_hooks()
	if "--benchmark" in OS.get_cmdline_user_args(): _benchmark(session)
	session.free()
	print("TDM_WEAPON_READOUT: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _extension_hooks() -> void:
	var custom_session: CustomSession = CustomSession.new()
	check(custom_session.get_weapon_info() == legacy_info(custom_session),"session override keeps original owner dispatch and transformed weapon/ammo")
	check(custom_session.owner_calls == 2,"session snapshot override is invoked once per getter")
	custom_session.free()
	var base_session: OfflineTDMSession = SESSION.new()
	base_session.simulation = MATCH.new()
	var custom_actor: CustomActor = CustomActor.new()
	base_session.simulation.actors[SESSION.OWNER_ID] = custom_actor
	check(base_session.get_weapon_info() == legacy_info(base_session),"actor copy override keeps original transformed weapon/ammo snapshot")
	check(custom_actor.copy_calls == 2,"custom actor copy dispatch is invoked once per getter")
	var owner: SharedPlayerState = PLAYER_STATE.new()
	owner.weapon = 2; owner.magazine = 6; owner.reserve = 48
	var motion: CustomMotion = CustomMotion.new()
	motion.owner = owner; owner.motion = motion
	base_session.simulation.actors[SESSION.OWNER_ID] = owner
	var expected: Dictionary = legacy_info(base_session)
	check(expected.magazine == 6 and owner.magazine == 7 and motion.copy_calls == 1,"original nested motion hook changes authority after scalar snapshot")
	owner.magazine = 6; motion.copy_calls = 0
	check(base_session.get_weapon_info() == expected and owner.magazine == 7 and motion.copy_calls == 1,"nested motion copy hook retains original values/effects/timing")
	motion.owner = null
	base_session.free()

func _measure(session: OfflineTDMSession, legacy: bool, reads: int) -> Dictionary:
	var checksum: int = 0
	var started: int = Time.get_ticks_usec()
	for index: int in range(reads):
		var info: Dictionary = legacy_info(session) if legacy else session.get_weapon_info()
		checksum += int(info.clip_size)+int(info.magazine)+int(info.reserve)+int(info.weapon_index)
	return {"elapsed_us":Time.get_ticks_usec()-started,"checksum":checksum}

func _benchmark(session: OfflineTDMSession) -> void:
	const READS: int = 4000
	_measure(session,true,100); _measure(session,false,100)
	var samples: Array[Dictionary] = []
	var baseline_times: Array[int] = []; var candidate_times: Array[int] = []
	for index: int in range(5):
		var baseline: Dictionary; var candidate: Dictionary
		if index%2 == 0:
			baseline = _measure(session,true,READS); candidate = _measure(session,false,READS)
		else:
			candidate = _measure(session,false,READS); baseline = _measure(session,true,READS)
		check(baseline.checksum == candidate.checksum,"paired complete-getter benchmark retains exact values")
		baseline_times.append(baseline.elapsed_us); candidate_times.append(candidate.elapsed_us)
		samples.append({"baseline_us":baseline.elapsed_us,"candidate_us":candidate.elapsed_us,"checksum":baseline.checksum})
	baseline_times.sort(); candidate_times.sort()
	var output: Dictionary = {"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),
		"reads_per_sample":READS,"samples":samples,"baseline_median_us":baseline_times[2],"candidate_median_us":candidate_times[2],
		"includes_mutable_profile_copy":true,"scope":"complete scalar weapon getter only; no frame/GPU/browser claim"}
	output.speedup = float(output.baseline_median_us)/output.candidate_median_us
	var path: String = ProjectSettings.globalize_path("res://../.cache/benchmarks/tdm-weapon-readout-optimization.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"complete-getter benchmark output writes")
	if file != null: file.store_string(JSON.stringify(output,"\t")); file.close()
	print("TDM_WEAPON_READOUT_BENCHMARK: %.2fx; %.3fus -> %.3fus per owned mutable readout" % [output.speedup,float(baseline_times[2])/READS,float(candidate_times[2])/READS])
