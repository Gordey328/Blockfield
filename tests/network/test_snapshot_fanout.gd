extends SceneTree
const CODEC = preload("res://network/simulation_codec.gd")
const P = preload("res://network/protocol.gd")
const WS = preload("res://network/ws_transport.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const EVENTS = preload("res://network/events_codec.gd")
const STATE = preload("res://simulation/player_state.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures += 1; push_error("SNAPSHOT FANOUT: "+message)
func run() -> void:
	for profile: String in ["0.75","0.76"]:
		for mode: String in ["sandbox","ctf","tc"]:
			var data := DATA.new()
			data.clear(Vector3i(128,16,128),39)
			data.seed_box(Vector3i.ZERO,Vector3i(128,2,128),0x01708090)
			var sim := MATCH.new()
			check(sim.configure(data,profile,mode).ok,"configured "+profile+mode)
			var count := 32 if profile=="0.76" and mode=="tc" else 4
			for i in range(count):
				var added := sim.add_actor("Игрок%d"%i,2,i+1701)
				check(added.ok,"canonical owner allocation")
				var actor := sim.get_actor(added.actor_id)
				RULES.spawn(actor,0,Vector3(6+(i%8)*10,2.01,6+(i/8)*10),i%2,i%3)
				actor.health = 70+i%30
				actor.reserve = i%12
				actor.blocks = i%50
				actor.grenades = i%4
				sim.set_block_color(actor.player_id,0x01000000+i*173)
			sim.step_fixed()
			var captured := sim.snapshot_for(1)
			var common := CODEC.prepare_shared(captured)
			check(common.ok,"common strict schema accepted")
			if not common.ok: continue
			# Preparation owns all public bytes even after the caller changes its copy.
			captured.actors[0].yaw = 1.25
			captured.objectives = {}
			for id: int in sim.actors:
				var source := sim.get_actor(id)
				var rng_before := source.shot_rng.state
				var old := CODEC.from_snapshot(sim.snapshot_for(id))
				var expected := P.encode(P.make_packet(P.Kind.MATCH_STATE,old.payload,sim.epoch,sim.tick,source.spawn_generation))
				var fast := P.prepare_state(common.frame,source)
				check(fast.ok and expected.ok,"both paths accept owner%d"%id)
				if not fast.ok or not expected.ok: continue
				check(fast.frame.bytes()==expected.bytes,"byte exact full strict wire owner%d"%id)
				var decoded := P.decode(fast.frame.bytes())
				check(decoded.ok and decoded.packet.payload.owner_state.player_id==id,"ordinary strict decoder accepts")
				check(decoded.ok and decoded.packet.payload.owner_state.health==source.health and decoded.packet.payload.owner_state.reserve==source.reserve,"only this owner's private inventory")
				check(source.shot_rng.state==rng_before,"publication never consumes server RNG")
				var returned: PackedByteArray = fast.frame.bytes()
				returned[0]=0
				check(fast.frame.bytes()[0]==0x42,"returned bytes cannot mutate prepared output")
			var owner := sim.get_actor(1)
			var bad := owner.copy()
			bad.yaw = .5
			check(not P.prepare_state(common.frame,bad).ok,"changed public pose cannot use old common tail")
			bad = owner.copy(); bad.health = 101
			check(not P.prepare_state(common.frame,bad).ok,"private range checked for every owner")
			bad = owner.copy(); bad.match_epoch += 1
			check(not P.prepare_state(common.frame,bad).ok,"new epoch invalidates old common context")
			bad = owner.copy(); bad.last_tick += 1
			check(not P.prepare_state(common.frame,bad).ok,"new tick invalidates old common context")
			bad = owner.copy(); bad.spawn_generation += 1
			check(not P.prepare_state(common.frame,bad).ok,"new life cannot use old public pose")
			var fresh := sim.snapshot_for(1)
			fresh.actors[2].yaw = NAN
			check(not CODEC.prepare_shared(fresh).ok,"all remote public scalars strictly checked once")
			fresh = sim.snapshot_for(1); fresh.objectives={}
			check(not CODEC.prepare_shared(fresh).ok,"objective schema still checked")
	check(not P.prepare_state(null,null).ok,"null common frame denied")
	check(not P.prepare_state(CODEC.SharedFrame.new(),null).ok,"unprepared common frame denied")
	var transport := WS.new()
	check(not transport.send_prepared(1,P.FrozenFrame.new()).ok,"empty prepared output cannot be queued")
	events_fanout()
	print("Snapshot fanout: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)

func events_fanout() -> void:
	var source: Array[Dictionary] = []
	var owners := {}
	for index in range(160):
		var id := index%32+1
		if not owners.has(id): owners[id] = STATE.new(id,"Owner",39,"0.75",91)
		var owner: SharedPlayerState = owners[id]
		owner.spawn_generation = 1
		var event: Dictionary
		if index%3==0:
			event = RULES.event(owner,30+index/64,"hurt",{"amount":3,"attacker_id":0,"cause":"fall","action_id":""}).duplicate(true)
		else:
			event = RULES.event(owner,30+index/64,"shot",{"weapon":2,"profile":"0.75","origin":Vector3(20,6,40),"directions":[Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD],"recoil_direction":Vector3.FORWARD}).duplicate(true)
		event.match_sequence = index+1
		source.append(event)
	var common := EVENTS.prepare_shared(39,source)
	check(common.ok,"mixed public/private source over 64 records captured: "+common.error)
	if not common.ok: return
	for id in range(1,33):
		var selected: Array[Dictionary] = []
		for event: Dictionary in source:
			if EVENTS.visibility(event.type)=="public" or event.owner_id==id: selected.append(event)
		var prepared := P.prepare_events(common.events,id)
		check(prepared.ok,"prepared events for owner%d"%id)
		if not prepared.ok: continue
		check(prepared.frames.size()==ceili(float(selected.size())/64),"same owner batch boundaries")
		for offset in range(0,selected.size(),64):
			var batch: Array[Dictionary] = []
			batch.assign(selected.slice(offset,mini(offset+64,selected.size())))
			var slow := EVENTS.from_events(39,batch)
			var tick := 0
			for event: Dictionary in slow.payload.events: tick=maxi(tick,event.tick)
			var expected := P.encode(P.make_packet(P.Kind.GAME_EVENTS,slow.payload,39,tick,slow.payload.last_sequence))
			var frame: P.FrozenFrame = prepared.frames[offset/64]
			check(expected.ok and frame.bytes()==expected.bytes,"byte exact owner event filtering/batches")
			var decoded := P.decode(frame.bytes())
			check(decoded.ok,"strict event decoder accepts prepared frame")
			if decoded.ok:
				for event: Dictionary in decoded.packet.payload.events:
					check(EVENTS.visibility(event.type)=="public" or event.owner_id==id,"private hurt never enters another player's frame")
	var before: PackedByteArray = P.prepare_events(common.events,1).frames[0].bytes()
	source[0].amount=100
	check(P.prepare_events(common.events,1).frames[0].bytes()==before,"capture owns data after authority dictionaries change")
	var malformed: Array[Dictionary] = source.duplicate(true)
	malformed[70].match_sequence=1
	check(not EVENTS.prepare_shared(39,malformed).ok,"cross-batch stale sequence rejected")
	malformed=source.duplicate(true);malformed[70]=source[1].duplicate(true);malformed[70].match_sequence=71
	check(not EVENTS.prepare_shared(39,malformed).ok,"cross-batch duplicate event ID rejected")
	check(not P.prepare_events(EVENTS.SharedEvents.new(),1).ok,"unprepared event context denied")
	check(not P.prepare_events(common.events,0).ok,"canonical owner required")
