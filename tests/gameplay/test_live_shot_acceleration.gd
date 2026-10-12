extends SceneTree
## Independent pre-cache live-ray references plus real lab/shared salvo commits.
## Exercises synchronous pose/life changes without graphics, settings or sockets.
const PLAYER = preload("res://gameplay/player_controller.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const HITS = preload("res://gameplay/lab_hit_volumes.gd")
const CACHE = preload("res://gameplay/shot_hit_pose_cache.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")

class LegacyPlayer extends PLAYER:
	func raycast_targets(origin: Vector3, direction: Vector3, max_distance: float = 500.0, _shot_poses: CACHE = null) -> Dictionary:
		var result: Dictionary = {}
		var closest: float = INF
		for target: Dictionary in session.targets:
			if not bool(target.alive) or int(target.team) >= 2: continue
			var hit: Dictionary = HITS.cast_ray(origin,direction,target.position,float(target.get("yaw",0.0)),str(target.state)=="crouching",float(target.get("pitch",0.0)),max_distance)
			if hit.hit:
				var distance: float = Vector2(hit.position.x-origin.x,hit.position.z-origin.z).length()
				if distance < closest:
					closest = distance
					result = hit
					result.target_id = int(target.id)
		return result

class LegacyMatch extends MATCH:
	func raycast_actors(owner_id: int, origin: Vector3, direction: Vector3, _shot_poses: CACHE = null) -> Dictionary:
		var result: Dictionary = {}
		var closest: float = INF
		for target: SharedPlayerState in _ordered():
			if target.player_id == owner_id or not RULES.can_act(target): continue
			var hit: Dictionary = HITS.cast_ray(origin,direction,target.feet(),target.yaw,target.motion.crouch,target.pitch,500)
			if hit.hit:
				var distance: float = Vector2(hit.position.x-origin.x,hit.position.z-origin.z).length()
				if distance < closest:
					closest = distance
					result = hit
					result.actor_id = target.player_id
		return result

class EmptyWorld extends VoxelWorld:
	func cast_source_ray(origin: Vector3, direction: Vector3, distance: int = 500) -> Dictionary:
		return {"hit":false,"position":origin+direction*distance}

var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("LIVE_SHOT_ACCELERATION: " + message)

func _run() -> void:
	_test_profile_scalar()
	_test_exact_keys()
	_test_lab_queries()
	_test_shared_queries()
	for scenario: String in ["death", "pose_mutation", "spectator_mutation"]:
		_test_lab_shot(scenario)
	for scenario: String in ["death", "cover", "friendly", "range"]:
		_test_shared_shot(scenario)
	print("LIVE_SHOT_ACCELERATION: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _test_profile_scalar() -> void:
	for profile: String in ["0.75","0.76"]:
		for weapon: int in range(3):
			var copied: Dictionary = PROFILES.get_info(profile,weapon)
			var expected: int = int(copied.clip_size)
			var expected_slow: bool = bool(copied.slow_reload)
			check(PROFILES.clip_size(profile,weapon) == expected,"AI scalar retains original profile/weapon clip size")
			check(PROFILES.is_slow_reload(profile,weapon) == expected_slow,"shared scalar retains original profile/weapon slow reload flag")
			copied.clip_size = -999
			copied.slow_reload = not expected_slow
			check(PROFILES.clip_size(profile,weapon) == expected and PROFILES.get_info(profile,weapon).clip_size == expected,"AI scalar and mutable profile copies preserve caller isolation")
			check(PROFILES.is_slow_reload(profile,weapon) == expected_slow and PROFILES.get_info(profile,weapon).slow_reload == expected_slow,"shared slow reload scalar preserves caller copy isolation")
	check(PROFILES.clip_size("",0) == 0 and PROFILES.clip_size("0.99",0) == 0,"unknown AI scalar profile yields zero")
	check(PROFILES.clip_size("0.75",-1) == 0 and PROFILES.clip_size("0.76",3) == 0,"out-of-range AI scalar weapon yields zero")
	check(not PROFILES.is_slow_reload("",0) and not PROFILES.is_slow_reload("0.99",0),"unknown slow reload profile yields false")
	check(not PROFILES.is_slow_reload("0.75",-1) and not PROFILES.is_slow_reload("0.76",3),"out-of-range slow reload weapon yields false")

func _test_exact_keys() -> void:
	var cache: CACHE = CACHE.new()
	var feet: Vector3 = Vector3(12.5,4,15.5)
	var first: HITS.PreparedPose = cache.prepare(7,feet,0,false,0,3,4,1)
	check(cache.prepare(7,feet,0,false,0,3,4,1) == first,"identical exact keys reuse source matrices")
	var changes: Array[Array] = [
		[8,feet,0.0,false,0.0,3,4,1], [7,feet+Vector3(.0001,0,0),0.0,false,0.0,3,4,1],
		[7,feet,.0000001,false,0.0,3,4,1], [7,feet,0.0,true,0.0,3,4,1],
		[7,feet,0.0,false,.0000001,3,4,1], [7,feet,0.0,false,0.0,4,4,1],
		[7,feet,0.0,false,0.0,3,5,1], [7,feet,0.0,false,0.0,3,4,0]]
	for keys: Array in changes:
		var isolated: CACHE = CACHE.new()
		var original: HITS.PreparedPose = isolated.prepare(7,feet,0,false,0,3,4,1)
		check(isolated.prepare(keys[0],keys[1],keys[2],keys[3],keys[4],keys[5],keys[6],keys[7]) != original,"identity/pose/epoch/generation/team change invalidates exact keys")
	var another: CACHE = CACHE.new()
	check(another.prepare(7,feet,0,false,0,3,4,1) != first,"shot-scoped caches never borrow another shot's entry")

func _test_lab_queries() -> void:
	var player: BlockfieldPlayer = PLAYER.new()
	var reference: LegacyPlayer = LegacyPlayer.new()
	var session: LocalSession = LocalSession.new()
	player.session = session
	reference.session = session
	var id: int = session.add_target(Vector3(12.5,4,15.5))
	var rear: int = session.add_target(Vector3(12.5,4,12.5))
	var target: Dictionary = session.get_target(id)
	var cache: CACHE = CACHE.new()
	var origin: Vector3 = Vector3(12.5,6.35,25.5)
	for index: int in range(160):
		target.position = Vector3(12.5+(index%3)*.15,4,15.5)
		target.yaw = (index%5)*.12
		target.pitch = (index%7-3)*.08
		target.state = "crouching" if index%2 == 0 else "standing"
		target.alive = index%11 != 0
		target.team = 2 if index%13 == 0 else 1
		target.deaths = index >> 3
		var direction: Vector3 = Vector3((index%9-4)*.012,(index%7-3)*.007,-1).normalized()
		var distance: float = [0.0,5.0,500.0][index%3]
		check(player.raycast_targets(origin,direction,distance,cache) == reference.raycast_targets(origin,direction,distance),"live lab cached query retains source result across pose/life/range changes")
	# Exact coincident hit ties keep current target iteration order.
	target.position = session.get_target(rear).position
	target.yaw = 0.0; target.pitch = 0.0; target.state = "standing"
	target.alive = true; target.team = 1
	check(player.raycast_targets(origin,Vector3.FORWARD,500,cache).target_id == id,"lab first exact tie retains insertion order")
	session.targets.reverse()
	check(player.raycast_targets(origin,Vector3.FORWARD,500,cache).target_id == rear,"cached lab tie observes a changed current array order")
	check(player.raycast_targets(origin,Vector3.ZERO,500,cache) == reference.raycast_targets(origin,Vector3.ZERO),"zero-direction live lab query remains empty")
	player.free(); reference.free(); session.free()

func _fixture(reference: bool = false) -> MatchSimulation:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(32,16,160),7)
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,160),0x01608040)
	var simulation: MatchSimulation = LegacyMatch.new() if reference else MATCH.new()
	check(simulation.configure(data).ok,"live shared fixture configures")
	for index: int in range(3):
		var added: Dictionary = simulation.add_actor("Actor%d" % index)
		check(added.ok,"live shared actor admitted")
		check(simulation.spawn_actor(added.actor_id,0 if index == 0 else 1,2,Vector3(12.5,4.01,25.5-index*5)).ok,"live shared safe actor spawn")
		simulation.get_actor(added.actor_id).tool_raise = 1.0
	return simulation

func _test_shared_queries() -> void:
	var simulation: MatchSimulation = _fixture()
	var reference: MatchSimulation = _fixture(true)
	var cache: CACHE = CACHE.new()
	for index: int in range(160):
		for current: MatchSimulation in [simulation,reference]:
			var target: SharedPlayerState = current.get_actor(2)
			target.motion.feet_position = Vector3(12.5+(index%3)*.15,4.01,20.5)
			target.yaw = (index%5)*.12
			target.pitch = (index%7-3)*.08
			target.motion.crouch = index%2 == 0
			target.health = 0 if index%11 == 0 else 100
			target.connected = index%13 != 0
			target.team = 2 if index%17 == 0 else 1
			target.spawn_generation = 2+(index >> 3)
		var origin: Vector3 = simulation.get_actor(1).motion.physics_eye()
		var direction: Vector3 = Vector3((index%9-4)*.012,(index%7-3)*.007,-1).normalized()
		check(simulation.raycast_actors(1,origin,direction,cache) == reference.raycast_actors(1,origin,direction),"live shared cached query retains source result across pose/life/connectivity changes")
	# _ordered still consults current actors, rather than a frozen salvo roster.
	for current: MatchSimulation in [simulation,reference]:
		var target: SharedPlayerState = current.get_actor(2)
		target.motion.feet_position = current.get_actor(3).feet()
		target.health = 100; target.connected = true; target.team = 1
		target.yaw = 0; target.pitch = 0; target.motion.crouch = false
	var origin: Vector3 = simulation.get_actor(1).motion.physics_eye()
	check(simulation.raycast_actors(1,origin,Vector3.FORWARD,cache).actor_id == 2,"shared coincident hit tie keeps ascending actor ID")
	simulation.actors.erase(2); reference.actors.erase(2)
	check(simulation.raycast_actors(1,origin,Vector3.FORWARD,cache) == reference.raycast_actors(1,origin,Vector3.FORWARD),"removing cached actor observes current roster")

func _lab_player(reference: bool, scenario: String) -> Dictionary:
	var player: BlockfieldPlayer = LegacyPlayer.new() if reference else PLAYER.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var head: Node3D = Node3D.new(); head.name = "Head"
	var camera: Camera3D = Camera3D.new(); camera.name = "Camera3D"
	var weapon: Node3D = Node3D.new(); weapon.name = "WeaponRoot"
	var collision: CollisionShape3D = CollisionShape3D.new(); collision.name = "CollisionShape3D"
	camera.add_child(weapon); head.add_child(camera); player.add_child(head); player.add_child(collision)
	var session: LocalSession = LocalSession.new()
	session.select_weapon(2)
	player.session = session; player.world = EmptyWorld.new()
	root.add_child(player)
	player.position = Vector3(12.5,4.01,25.5); head.position.y = 2.35
	var first: int = session.add_target(Vector3(12.5,4.01,20.5))
	session.add_target(Vector3(12.5,4.01,15.5))
	var target: Dictionary = session.get_target(first)
	target.health = 1 if scenario == "death" else 1000
	if scenario != "death":
		session.changed.connect(func() -> void:
			if session.hits_landed != 1: return
			if scenario == "pose_mutation":
				target.position.x += 2.0
				target.yaw = .3; target.pitch = -.2; target.state = "crouching"
				target.deaths = 7
			else: target.team = 2)
	var feedback: Array[Dictionary] = []
	player.hit_confirmed.connect(func(part: String, amount: float, friendly: bool) -> void:
		feedback.append({"part":part,"damage":amount,"friendly":friendly}))
	seed(312719)
	player._shoot()
	var result: Dictionary = {"targets":session.targets.duplicate(true),"magazine":session.magazine,
		"shots":session.shots_fired,"hits":session.hits_landed,"score":session.score,
		"log":session.event_log.duplicate(true),"feedback":feedback,
		"yaw":player.rotation.y,"pitch":head.rotation.x,"rng_next":randf()}
	player.world.free(); player.free(); session.free()
	return result

func _test_lab_shot(scenario: String) -> void:
	var reference: Dictionary = _lab_player(true,scenario)
	var candidate: Dictionary = _lab_player(false,scenario)
	check(candidate == reference,"actual lab shotgun preserves damage/events/recoil/RNG with " + scenario)
	check(candidate.shots == 1 and candidate.magazine == 5 and candidate.hits >= 2,"actual lab salvo exercises multiple pellets with " + scenario)
	if scenario == "death": check(not candidate.targets[0].alive and candidate.feedback.size() >= 2,"later lab pellets pass a target killed by an earlier pellet")

func _test_shared_shot(scenario: String) -> void:
	var simulation: MatchSimulation = _fixture()
	var reference: MatchSimulation = _fixture(true)
	for current: MatchSimulation in [simulation,reference]:
		current.tick = 0
		current.get_actor(2).health = 1
		if scenario == "cover": current.data.seed_box(Vector3i(12,4,22),Vector3i(13,8,23),0x01aaaaaa)
		elif scenario == "friendly":
			current.friendly_fire = false
			current.get_actor(2).team = 0
		elif scenario == "range": current.get_actor(2).motion.feet_position.z = -103
	var directions: Array[Vector3] = [Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,
		Vector3(.0000007,0,-1).normalized(),Vector3(0,.003,-1).normalized(),Vector3.FORWARD,
		Vector3.FORWARD,Vector3.FORWARD]
	var shot: Dictionary = RULES.event(simulation.get_actor(1),0,"shot",{"weapon":2,
		"origin":simulation.get_actor(1).motion.physics_eye()+Vector3.FORWARD*.01,"directions":directions})
	var reference_shot: Dictionary = RULES.event(reference.get_actor(1),0,"shot",{"weapon":2,
		"origin":reference.get_actor(1).motion.physics_eye()+Vector3.FORWARD*.01,"directions":directions})
	var expected: Array[Dictionary] = reference._resolve_shot(reference.get_actor(1),reference_shot.duplicate(true))
	var actual: Array[Dictionary] = simulation._resolve_shot(simulation.get_actor(1),shot.duplicate(true))
	check(actual == expected,"actual shared shotgun commits exact source events with " + scenario)
	check(simulation.data.blocks == reference.data.blocks and simulation.drain_transactions() == reference.drain_transactions(),"actual shared terrain transactions remain identical with " + scenario)
	check(_plain_values(simulation.snapshot_for(1)) == _plain_values(reference.snapshot_for(1)),"actual shared private/public authority snapshot remains identical with " + scenario)
	check(MATCH.events_of(actual,"tracer").size() == 8,"all source salvo pellets publish in original order with " + scenario)
	if scenario == "death": check(simulation.get_actor(2).health == 0 and simulation.get_actor(3).health == 0,"later shared pellets pass dead nearer target and hit rear actor")

func _plain_values(value: Variant) -> Variant:
	if value is RandomNumberGenerator: return value.state
	if value is RefCounted:
		var fields: Dictionary = {}
		for property: Dictionary in value.get_script().get_script_property_list():
			fields[property.name] = _plain_values(value.get(property.name))
		return fields
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[key] = _plain_values(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_plain_values(item))
		return result
	return value
