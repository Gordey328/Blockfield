extends SceneTree
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const CODEC = preload("res://network/simulation_codec.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("MATCH RESET: "+message)

func map_data(epoch: int) -> VoxelData:
	var data := DATA.new()
	check(data.clear(Vector3i(32,16,32),epoch) == OK,"fresh epoch packed map")
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01607080)
	return data

func fixture(epoch: int = 7,profile: String = "0.75",mode: String = "sandbox") -> MatchSimulation:
	var sim := MATCH.new()
	check(sim.configure(map_data(epoch),profile,mode).ok,"new authority match")
	return sim

func identities() -> void:
	var sim := fixture()
	var first := sim.add_actor("Automatic default")
	check(first.ok and first.actor_id == 1,"existing default API admits actor1")
	var restored := sim.add_actor("Restored gap",2,123,Vector3.INF,91)
	check(restored.ok and restored.actor_id == 91,"trusted positive explicit ID preserves gap")
	var actor := sim.get_actor(91)
	check(actor.player_id == 91 and actor.player_name == "Restored gap" and actor.match_epoch == 7 and actor.profile == "0.75","constructor receives exact restored identity/new match fields")
	check(actor.spawn_generation == 1 and actor.team == 2 and not actor.is_alive() and actor.health == 0 and actor.magazine == 0 and actor.last_tick == -1,"restored default spectator remains inactive without source refills")
	var expected := RandomNumberGenerator.new();expected.seed = 123
	check(actor.shot_rng.state == expected.state,"trusted seed initializes only private actor RNG")
	var lower := sim.add_actor("Unordered lower gap",2,1,Vector3.INF,8)
	check(lower.ok and lower.actor_id == 8,"restoration order need not be ascending")
	check(sim.add_actor("Automatic successor").actor_id == 92,"automatic IDs advance past highest explicit ID")
	var before := sim.drain_events()
	check(before.size() == 4 and before[1].owner_id == 91 and before[1].epoch == 7,"join event uses restored identity/new epoch")
	var cursor := sim.event_sequence
	for id: int in [-1,1,8,91,RULES.MAX_UINT32+1]:
		check(not sim.add_actor("Rejected",2,1,Vector3.INF,id).ok,"invalid/duplicate ID rejected: %s" % id)
	check(sim.actors.size() == 4 and sim.event_sequence == cursor and sim.drain_events().is_empty(),"failed identity admissions do not write actors/events")
	check(sim.remove_actor(91).ok,"trusted removal of old actor")
	check(not sim.add_actor("Removed life reuse",2,1,Vector3.INF,91).ok,"removed ID is still reserved within epoch")
	check(sim.add_actor("Next after removal").actor_id == 93,"automatic IDs never reuse removed identity")
	sim.step_fixed()
	check(sim.add_actor("Trusted late gap",2,1,Vector3.INF,50).ok,"trusted unique ID allowed at a later match tick")
	check(sim.get_actor(50).last_tick == sim.tick,"late restored identity aligns with current authority clock")
	check(sim.add_actor("Automatic late").actor_id == 94,"lower late explicit ID cannot rewind high-water mark")

func limits() -> void:
	var sim := fixture()
	check(sim.add_actor("Before maximum",2,1,Vector3.INF,RULES.MAX_UINT32-1).ok,"u32 penultimate ID admitted")
	var maximum := sim.add_actor("Maximum automatic")
	check(maximum.ok and maximum.actor_id == RULES.MAX_UINT32,"automatic ID reaches u32 maximum exactly")
	check(not sim.add_actor("No wrapped zero").ok,"automatic exhaustion rejects rather than wrapping actor0")
	check(sim._next_actor_id == RULES.MAX_UINT32+1 and not sim.actors.has(0),"signed64 high-water sentinel preserves u32 boundary")
	check(not sim.add_actor("Maximum duplicate",2,1,Vector3.INF,RULES.MAX_UINT32).ok,"maximum duplicate rejected")
	check(sim.add_actor("Unused gap after exhaustion",2,1,Vector3.INF,3).ok,"trusted lower unused ID remains available after automatic exhaustion")
	check(not sim.add_actor("Still exhausted").ok,"lower explicit gap does not reset exhaustion")
	check(sim.remove_actor(RULES.MAX_UINT32).ok and not sim.add_actor("Removed maximum",2,1,Vector3.INF,RULES.MAX_UINT32).ok,"removed maximum remains reserved")
	sim.step_fixed()
	check(CODEC.from_snapshot(sim.snapshot_for(3)).ok,"full source snapshot handles maximum-u32 public actor identities")
	var capacity := fixture()
	for i: int in range(MATCH.MAX_ACTORS):
		check(capacity.add_actor("Actor %s" % i,2,1,Vector3.INF,100+i*3).ok,"bounded sparse registry admission")
	check(not capacity.add_actor("Over capacity",2,1,Vector3.INF,999).ok and capacity.actors.size() == MATCH.MAX_ACTORS,"explicit IDs do not bypass active actor limit")
	check(capacity.remove_actor(100).ok and capacity.add_actor("Fresh capacity slot",2,1,Vector3.INF,999).ok,"free registry slot permits distinct fresh identity")
	check(not capacity.add_actor("Removed capacity identity",2,1,Vector3.INF,100).ok,"capacity release never grants identity reuse")

func spawning() -> void:
	var sim := fixture(10,"0.76")
	var feet := Vector3(10.5,4.01,10.5)
	var admitted := sim.add_actor("Trusted playing position",0,456,feet,17)
	check(admitted.ok,"optional authored ID/location still uses source spawn")
	var actor := sim.get_actor(17)
	check(actor.is_alive() and actor.team == 0 and actor.spawn_generation == 2 and actor.feet() == feet,"playing admission performs source generation increment at safe supplied feet")
	check(actor.profile == "0.76" and actor.magazine == 8 and actor.reserve == 48 and actor.grenades == 3 and actor.blocks == 50,"changed constructor profile supplies source0.76 rifle resources")
	check(actor.tool == 2 and actor.displayed_tool == 2 and actor.tool_raise == 0 and actor.next_shot_tick == 0,"source readiness/deadline defaults retained")
	var events := sim.drain_events()
	check(events.size() == 2 and events[0].type == "actor_joined" and events[1].type == "spawn" and events[1].owner_id == 17,"admission/spawn events retain explicit owner ID")
	var cursor := sim.event_sequence
	for point: Vector3 in [Vector3(10.5,4.01,10.5),Vector3(-1,4,4),Vector3(10,2,10),Vector3(NAN,4,4),Vector3(INF,4,4)]:
		check(not sim.add_actor("Bad authored feet",1,1,point,19).ok,"occupied/invalid supplied spawn rejected")
	check(sim.get_actor(19) == null and sim.event_sequence == cursor,"unsafe position rejection leaves identity/events available")
	check(sim.add_actor("Safe after rejected position",1,1,Vector3(20.5,4.01,20.5),19).ok,"rejected position does not consume explicit identity")
	check(sim.add_actor("Placed spectator",2,1,Vector3(16.5,4.01,16.5),5).ok,"trusted optional spectator position")
	check(sim.get_actor(5).feet() == Vector3(16.5,4.01,16.5) and not sim.get_actor(5).is_alive() and sim.get_actor(5).magazine == 0,"spectator position initializes motion without combat/spawn inventory")
	sim.step_fixed()
	check(CODEC.from_snapshot(sim.snapshot_for(17)).ok,"explicit identity with changed profile supports complete wire snapshot")

func new_epoch() -> void:
	var sim := fixture(21,"0.75","ctf")
	check(sim.add_actor("Old first",0,11,Vector3(8.5,4.01,8.5),2).ok,"old match sparse actor2")
	check(sim.add_actor("Old removed",2,22,Vector3.INF,7).ok,"old match actor7")
	check(sim.add_actor("Old surviving",1,33,Vector3(24.5,4.01,24.5),41).ok,"old match sparse actor41")
	var old := sim.get_actor(2)
	old.kills = 12;old.deaths = 3;old.score = 99;old.magazine = 1;old.reserve = 2
	RULES.request_class(old,2,0)
	sim.objectives.scores.assign([5,3]);sim.objectives.winning_team = 0
	check(sim.remove_actor(7).ok,"old removed identity creates restore gap")
	sim.step_fixed()
	var old_snapshot := sim.snapshot_for(2)
	check(not sim.configure(sim.data,"0.76","tc").ok and sim.get_actor(2) == old,"same epoch reset rejects without mutating old authority")
	check(sim.configure(map_data(22),"0.76","tc").ok,"new epoch config resets match state")
	check(sim.epoch == 22 and sim.profile == "0.76" and sim.mode == "tc" and sim.tick == -1,"new epoch/profile/mode and source fixed clock applied")
	check(sim.actors.is_empty() and sim.grenades.is_empty() and sim.event_sequence == 0 and sim.drain_events().is_empty() and sim.drain_transactions().is_empty(),"new match clears actors/projectiles/events/transactions")
	check(sim.objectives.scores == [0,0] and sim.objectives.winning_team == -1,"round scores/win/objectives reset by configuration")
	check(sim.add_actor("Old surviving",2,33,Vector3.INF,41).ok and sim.add_actor("Old first",2,11,Vector3.INF,2).ok,"connected identities restore unsorted into new epoch")
	var restored := sim.get_actor(2)
	check(restored != old and restored.match_epoch == 22 and restored.profile == "0.76" and restored.player_id == 2,"identity stable across epoch while actual actor state is replaced")
	check(restored.health == 0 and restored.magazine == 0 and restored.kills == 0 and restored.deaths == 0 and restored.score == 0 and restored.pending_weapon == -1,"new inactive state cannot retain previous authority resources/scores/class implicitly")
	check(old_snapshot.epoch == 21 and old_snapshot.owner_state.match_epoch == 21 and old_snapshot.owner_state.score == 99,"owned old snapshot remains in old epoch unchanged")
	# Runtime restores allowed class preferences explicitly, then waits for the
	# new map/state readiness barrier before source spawn.
	check(not RULES.request_class(restored,2,0).is_empty() and sim.spawn_actor(2,0).ok,"trusted pending class applies on new ready spawn")
	check(restored.weapon == 2 and restored.magazine == 8 and restored.reserve == 48 and restored.kills == 0 and restored.score == 0,"new profile/class refill uses0.76 shotgun while counters reset")
	check(sim.add_actor("Next new guest").actor_id == 42,"automatic allocation avoids restored sparse stable IDs")
	check(sim.add_actor("New epoch unused removed old ID",2,1,Vector3.INF,7).ok,"issued identity reservation resets only with new epoch")
	sim.step_fixed()
	var converted := CODEC.from_snapshot(sim.snapshot_for(2))
	check(converted.ok and converted.payload.owner_state.match_epoch == 22 and converted.payload.owner_state.player_id == 2 and converted.payload.profile == "0.76","new epoch full replay codec agrees with restored owner identity/profile")

func run() -> void:
	identities();limits();spawning();new_epoch()
	print("MATCH RESET: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
