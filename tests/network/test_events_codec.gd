extends SceneTree
const CODEC = preload("res://network/events_codec.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const STATE = preload("res://simulation/player_state.gd")
const GRENADES = preload("res://simulation/grenade_rules.gd")
const OBJECTIVES = preload("res://simulation/match_objectives.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value: failures += 1;push_error("EVENTS CODEC: " + message)
func _run() -> void:
	for scenario: String in ["all_emitted_schemas","actual_combat_and_build","actual_grenades","actual_objectives_and_lifecycle","identity_and_schema_rejections","wire_hostility","routing_and_replay"]:
		check(call(scenario) == true,"scenario completes: " + scenario)
	print("EVENTS CODEC: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func fixture(mode: String = "sandbox") -> MatchSimulation:
	var data := DATA.new()
	data.clear(Vector3i(64,64,64),7)
	data.seed_box(Vector3i(0,1,0),Vector3i(64,4,64),0x01608040)
	var match_state := MATCH.new()
	check(match_state.configure(data,"0.75",mode).ok,"real pure map/match configured")
	return match_state
func actor(sim: MatchSimulation,name: String,team: int,feet: Vector3,weapon: int = 0) -> SharedPlayerState:
	var joined := sim.add_actor(name)
	check(joined.ok,"stable actor admitted")
	check(sim.spawn_actor(joined.actor_id,team,weapon,feet).ok,"valid source inventory spawn")
	var result := sim.get_actor(joined.actor_id)
	result.tool_raise = 1
	return result
func input(owner: SharedPlayerState,buttons: int,tool: int = 255) -> PlayerRules.Command:
	var command := RULES.Command.new()
	command.sequence=owner.consumed_input_sequence+1
	command.spawn_generation=owner.spawn_generation
	command.buttons=buttons
	command.tool=tool
	return command
func roundtrip(events: Array[Dictionary]) -> Dictionary:
	var normalized := CODEC.from_events(7,events)
	check(normalized.ok,"real event adapters accept: " + str(normalized.get("error")))
	if not normalized.ok: return {}
	var encoded := CODEC.encode(normalized.payload)
	check(encoded.ok and encoded.bytes.size() <= CODEC.MAX_BODY,"bounded typed event serialization")
	if not encoded.ok: return {}
	var decoded := CODEC.decode(encoded.bytes)
	check(decoded.ok,"wire event decoding")
	if not decoded.ok: return {}
	check(CODEC.encode(decoded.payload).bytes == encoded.bytes,"canonical byte roundtrip")
	check(decoded.payload.is_read_only() and decoded.payload.events.is_read_only(),"decoded event frame immutable")
	return decoded.payload
func find_event(payload: Dictionary,type: String) -> Dictionary:
	for event: Dictionary in payload.get("events",[]):
		if event.type == type: return event
	return {}

func all_emitted_schemas() -> bool:
	var owner := STATE.new(3,"Солдат",7,"0.75",91)
	owner.spawn_generation=2
	owner.team=0
	owner.health=100
	owner.consumed_input_sequence=8
	var reference := "7:3:2:1"
	var details := {
		"spawn":{"feet":Vector3(20.5,4.01,40.5),"team":0,"weapon":0},
		"team_changed":{"team":2},"class_pending":{"weapon":1},"tool_selected":{"tool":3},"tool_swapped":{"tool":3,"weapon":0},
		"reload_started":{"weapon":2},"blocks_used":{"count":3},
		"grenade_thrown":{"position":Vector3(20,8,40),"native_velocity":Vector3(0,.1,-1),"fuse":2.75,"cook_time":.25,"drop":false,"team":0,"cook_action_sequence":8,"automatic":false},
		"hurt":{"amount":37,"attacker_id":4,"cause":"weapon","action_id":"7:4:2:3"},
		"death":{"attacker_id":4,"cause":"weapon","action_id":"7:4:2:3"},
		"shot":{"weapon":2,"profile":"0.75","origin":Vector3(20,6,40),"directions":[Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD],"recoil_direction":Vector3.FORWARD},
		"land":{"hurt":true},"footstep":{"wade":true},
		"kill_credit":{"victim_id":4,"victim_generation":2,"cause":"weapon","source_event_id":reference},
		"hit_confirmed":{"victim_id":4,"part":"head","damage":37,"position":Vector3(20,6,30),"friendly":false,"source_event_id":reference,"pellet":7},
		"block_hit":{"cell":Vector3i(20,6,35),"position":Vector3(20.5,6.5,36),"normal":Vector3i.BACK,"source_event_id":reference,"pellet":7},
		"tracer":{"origin":Vector3(20,6,40),"position":Vector3(20,6,30),"weapon":2,"source_event_id":reference,"pellet":7},
		"spade_miss":{"source_event_id":reference},
		"spade_block_hit":{"cell":Vector3i(20,6,39),"position":Vector3(20.5,6.5,40),"normal":Vector3i.BACK,"dig":true,"source_event_id":reference},
		"build_error":{"reason":"invalid placement"},
		"blocks_built":{"cells":[Vector3i(20,4,39),Vector3i(21,4,39)],"line":true,"color":0x014080c0},
		"intel_drop":{"flag_team":1,"position":Vector3(20,4,40)},"intel_pickup":{"flag_team":1},"intel_capture":{"flag_team":1,"score":3},"intel_return":{"flag_team":0},
		"territory_capture":{"team":0,"territory":0,"position":Vector3(20,4,40)},"round_won":{"winning_team":0,"mode":"ctf"}
	}
	var objective := OBJECTIVES.new()
	objective.epoch=7
	var projectile := GRENADES.create(12,3,2,7,0,Vector3(20,8,40),Vector3.FORWARD*32,3,8)
	var events: Array[Dictionary] = []
	for type: String in CODEC.SCHEMAS:
		var event: Dictionary
		if type == "events_resync_required":
			event={"type":type,"epoch":7,"tick":9,"owner_id":0,"spawn_generation":0,"event_id":"7:m:%d" % (events.size()+1),"match_sequence":events.size()+1,"event_sequence":events.size()+1,"resync_required":true}
		elif type in CODEC.OBJECTIVE_TYPES:
			event=objective._event(9,type,null if type == "territory_capture" else owner,details[type]).duplicate(true)
		elif type in CODEC.GRENADE_TYPES:
			event=GRENADES.event(projectile,9,type,{"position":Vector3(20,4,40)}).duplicate(true)
		else: event=RULES.event(owner,9,type,details.get(type,{})).duplicate(true)
		event.match_sequence=events.size()+1
		events.append(event)
	var payload := roundtrip(events)
	check(payload.get("events",[]).size() == CODEC.SCHEMAS.size(),"every currently emitted rule/match/objective type preserved")
	check(not find_event(payload,"shot").has("recoil_direction") and not find_event(payload,"shot").has("actor_event_sequence"),"explicit adapter strips personal recoil and redundant actor ordinal")
	check(find_event(payload,"grenade_thrown").cook_action_sequence == 8 and find_event(payload,"grenade_exploded").grenade_id == 12,"pin input identity and authoritative projectile identity retained")
	check(find_event(payload,"intel_capture").score == 3 and find_event(payload,"kill_credit").victim_generation == 2,"objective score and kill attribution retained")
	return true

func actual_combat_and_build() -> bool:
	var sim := fixture()
	var shooter := actor(sim,"Shooter",0,Vector3(20.5,4.01,40.5))
	var victim := actor(sim,"Victim",1,Vector3(20.5,4.01,30.5))
	sim.step_fixed({shooter.player_id:input(shooter,RULES.Buttons.PRIMARY)})
	var payload := roundtrip(sim.drain_events())
	var shot := find_event(payload,"shot")
	var death := find_event(payload,"death")
	check(not shot.is_empty() and victim.health == 0 and shot.directions.size() == 1,"actual confirmed gun shot carries source direction")
	check(death.owner_id == victim.player_id and death.attacker_id == shooter.player_id and death.action_id == shot.event_id,"victim death tied to actual shot")
	check(find_event(payload,"hit_confirmed").source_event_id == shot.event_id and find_event(payload,"tracer").source_event_id == shot.event_id,"owner feedback/public tracer share fired action ID")
	var cover := fixture()
	var builder := actor(cover,"Builder",0,Vector3(20.5,4.01,40.5))
	cover.data.seed_box(Vector3i(20,4,38),Vector3i(21,8,39),0x01cccccc)
	builder.tool=1;builder.displayed_tool=1
	cover.set_block_color(builder.player_id,0x01020304)
	cover.step_fixed({builder.player_id:input(builder,RULES.Buttons.PRIMARY)})
	var built := roundtrip(cover.drain_events())
	check(find_event(built,"blocks_built").cells == [Vector3i(20,6,39)] and find_event(built,"blocks_built").color == 0x01020304,"real validated colored block outcome serialized")
	check(find_event(built,"blocks_used").count == 1 and builder.blocks == 49,"stock usage remains separate owner event")
	var gun := fixture()
	var behind := actor(gun,"Cover shot",0,Vector3(20.5,4.01,40.5))
	gun.data.seed_box(Vector3i(20,4,35),Vector3i(21,8,36),0x01cccccc)
	gun.step_fixed({behind.player_id:input(behind,RULES.Buttons.PRIMARY)})
	var impact := roundtrip(gun.drain_events())
	check(find_event(impact,"block_hit").cell == Vector3i(20,6,35) and find_event(impact,"block_hit").normal == Vector3i.BACK,"real voxel surface cell and axis normal retained")
	return true

func actual_grenades() -> bool:
	var sim := fixture()
	var thrower := actor(sim,"Thrower",0,Vector3(20.5,4.01,40.5))
	thrower.tool=3;thrower.displayed_tool=3
	sim.step_fixed({thrower.player_id:input(thrower,RULES.Buttons.PRIMARY)})
	var pin := roundtrip(sim.drain_events())
	check(find_event(pin,"grenade_pin").action_sequence == 1,"actual pin bound to accepted owner input")
	for unused in range(9): sim.step_fixed()
	sim.clear_controls(thrower.player_id)
	sim.step_fixed()
	var payload := roundtrip(sim.drain_events())
	var thrown := find_event(payload,"grenade_thrown")
	check(thrown.cook_action_sequence == 1 and thrown.owner_id == thrower.player_id and thrown.spawn_generation == thrower.spawn_generation,"release retains original pin despite later command state")
	check(absf(thrown.fuse-(3.0-10.0/60)) < .00001 and not thrown.drop and thrown.native_velocity.z < -.9,"source release timing and native velocity survive f32 wire")
	var projectile: SharedGrenadeState = sim.grenades.values()[0]
	for unused in range(181): sim.step_fixed()
	var flight := roundtrip(sim.drain_events())
	check(find_event(flight,"grenade_exploded").grenade_id == projectile.grenade_id and find_event(flight,"grenade_exploded").owner_id == thrower.player_id,"real flight explosion attribution survives")
	var dying := fixture()
	var cook := actor(dying,"Death drop",0,Vector3(20.5,4.01,40.5))
	cook.tool=3;cook.displayed_tool=3
	dying.step_fixed({cook.player_id:input(cook,RULES.Buttons.PRIMARY)})
	dying.damage_actor(cook.player_id,100,0,"fall")
	var forced := roundtrip(dying.drain_events())
	check(find_event(forced,"grenade_thrown").drop and not find_event(forced,"grenade_thrown").automatic and find_event(forced,"death").cause == "fall","forced death drop and environmental death explicit")
	return true

func actual_objectives_and_lifecycle() -> bool:
	var sim := fixture("ctf")
	var carrier := actor(sim,"Carrier",0,Vector3(20.5,4.01,40.5))
	var bases: Array[Vector3] = [Vector3(20.5,4.01,40.5),Vector3(20.5,4.01,30.5)]
	sim.objectives.configure(7,"ctf",bases,[],1)
	carrier.motion.feet_position=bases[1]
	sim.step_fixed()
	sim.disconnect_actor(carrier.player_id)
	var dropped := roundtrip(sim.drain_events())
	check(find_event(dropped,"intel_pickup").flag_team == 1 and find_event(dropped,"intel_drop").owner_id == carrier.player_id,"real pickup and disconnect flag drop delivered")
	sim.reconnect_actor(carrier.player_id)
	carrier.motion.feet_position=bases[1]
	sim.step_fixed()
	carrier.motion.feet_position=bases[0]
	sim.step_fixed()
	var captured := roundtrip(sim.drain_events())
	check(find_event(captured,"intel_capture").score == 1 and find_event(captured,"round_won").winning_team == 0,"actual capture and round victory delivered")
	sim.set_team(carrier.player_id,2)
	sim.remove_actor(carrier.player_id)
	var removed := roundtrip(sim.drain_events())
	check(find_event(removed,"team_changed").team == 2 and not find_event(removed,"actor_removed").is_empty(),"team/spectator and registry removal events remain explicit")
	var tc := fixture("tc")
	var capturer := actor(tc,"Territory",0,Vector3(20.5,4.01,40.5))
	var positions: Array[Vector3] = [capturer.feet()]
	tc.objectives.configure(7,"tc",bases,positions)
	tc.objectives.territories[0].progress=.9999
	tc.step_fixed()
	var conquered := roundtrip(tc.drain_events())
	check(find_event(conquered,"territory_capture").owner_id == 0 and find_event(conquered,"territory_capture").territory == 0 and find_event(conquered,"round_won").mode == "tc","team territory outcome carries no fabricated actor attribution")
	return true

func simple_payload() -> Dictionary:
	var sim := fixture()
	actor(sim,"Fixture",0,Vector3(20.5,4.01,40.5))
	return CODEC.from_events(7,sim.drain_events()).payload.duplicate(true)
func reject(payload: Dictionary,message: String) -> void: check(not CODEC.encode(payload).ok,message)
func identity_and_schema_rejections() -> bool:
	var good := simple_payload()
	var cases: Array[Dictionary] = []
	for changed: Dictionary in [{"type":"unknown_event"},{"event_id":"07:1:1:1"},{"event_id":"7:01:1:1"},{"owner_id":2},{"spawn_generation":0},{"epoch":8},{"match_sequence":0},{"tick":-1},{"action_sequence":0x100000000},{"tick":1.0},{"event_id":null},{"actor_rng":17}]:
		var mutated := good.duplicate(true)
		mutated.events[0].merge(changed,true)
		cases.append(mutated)
	for i in range(cases.size()): reject(cases[i],"strict schema/type/identity rejection %d" % i)
	var duplicate := good.duplicate(true)
	duplicate.events[1].event_id=duplicate.events[0].event_id
	reject(duplicate,"same ID cannot denote different generation/type outcome")
	duplicate=good.duplicate(true);duplicate.events.reverse()
	reject(duplicate,"unordered global cursor rejected")
	duplicate=good.duplicate(true);duplicate.last_sequence+=1
	reject(duplicate,"declared range must match transmitted last event")
	duplicate=good.duplicate(true);duplicate.extra="unknown"
	reject(duplicate,"unknown body key rejected")
	var source := STATE.new(1,"Source",7)
	source.spawn_generation=2
	var invalid: Array[Dictionary] = [RULES.event(source,0,"unknown").duplicate(true)]
	invalid[0].match_sequence=1
	check(not CODEC.from_events(7,invalid).ok,"unsupported trusted source is failure, never skip")
	invalid=[RULES.event(source,0,"dry_fire").duplicate(true)];invalid[0].match_sequence=1;invalid[0].shot_rng=RandomNumberGenerator.new()
	check(not CODEC.from_events(7,invalid).ok,"private RNG extra cannot pass adapter")
	invalid[0].erase("shot_rng");invalid[0].actor_event_sequence+=1
	check(not CODEC.from_events(7,invalid).ok,"redundant source ordinal must agree with canonical ID")
	var grenade := RULES.event(source,0,"grenade_thrown",{"position":Vector3(1,2,3),"native_velocity":Vector3.ZERO,"fuse":3.0,"cook_time":0.0,"drop":false,"team":0,"cook_action_sequence":0,"automatic":false}).duplicate(true)
	grenade.match_sequence=1
	var normalized: Dictionary = CODEC.from_events(7,[grenade]).payload.duplicate(true)
	for changed: Dictionary in [{"position":Vector3(NAN,0,0)},{"native_velocity":Vector3(INF,0,0)},{"fuse":4.0},{"fuse":2.0},{"drop":true,"automatic":true},{"team":3},{"cook_action_sequence":-1},{"cook_time":NAN}]:
		var mutated: Dictionary = normalized.duplicate(true);mutated.events[0].merge(changed,true)
		reject(mutated,"invalid grenade point/timing/ownership rejected")
	var feedback := RULES.event(source,0,"hit_confirmed",{"victim_id":2,"part":"melee","damage":100,"position":Vector3.ONE,"friendly":false,"source_event_id":"7:1:2:1"}).duplicate(true)
	feedback.match_sequence=1
	var melee := CODEC.from_events(7,[feedback])
	check(melee.ok and melee.payload.events[0].pellet == 0,"explicit melee adapter supplies sole pellet index")
	var linked: Dictionary = melee.payload.duplicate(true);linked.events[0].source_event_id="8:1:2:1"
	reject(linked,"linked event cannot use another epoch")
	linked=melee.payload.duplicate(true);linked.events[0].source_event_id="7:01:2:1"
	reject(linked,"ambiguous linked event numeric ID rejected")
	linked=melee.payload.duplicate(true);linked.events[0].damage=101
	reject(linked,"damage is actual bounded dealt health")
	linked=melee.payload.duplicate(true);linked.events[0].part="unknown"
	reject(linked,"unknown hit-zone enum rejected")
	linked=melee.payload.duplicate(true);linked.events[0].source_event_id="7:2:2:1"
	reject(linked,"confirmed effect cannot impersonate another actor action")
	linked=melee.payload.duplicate(true);linked.events[0].source_event_id="7:1:3:1"
	reject(linked,"confirmed effect cannot impersonate another generation action")
	var external := RULES.event(source,0,"hurt",{"amount":1,"attacker_id":0,"cause":"fall","action_id":"внешний 🧱"}).duplicate(true)
	external.match_sequence=1
	var localized := CODEC.from_events(7,[external])
	check(localized.ok and CODEC.decode(CODEC.encode(localized.payload).bytes).payload.events[0].action_id == "внешний 🧱","bounded external reference preserves valid multibyte UTF8")
	external.action_id="я".repeat(49)
	check(not CODEC.from_events(7,[external]).ok,"UTF8 reference byte limit measured before writing")
	external.action_id="external\ncontrol"
	check(not CODEC.from_events(7,[external]).ok,"control in external reference rejected")
	var original_rays: Array[Vector3] = [Vector3.FORWARD]
	var source_shot := RULES.event(source,0,"shot",{"weapon":0,"profile":"0.75","origin":Vector3.ONE,"directions":original_rays,"recoil_direction":Vector3.FORWARD}).duplicate(true)
	source_shot.match_sequence=1
	var copied := CODEC.from_events(7,[source_shot])
	check(copied.ok and not source_shot.directions.is_read_only() and copied.payload.events[0].directions.is_read_only(),"normalization freezes only bounded owned copies")
	source_shot.directions[0]=Vector3.RIGHT
	check(copied.payload.events[0].directions[0] == Vector3.FORWARD,"source mutation cannot change accepted confirmed rays")
	return true

func wire_hostility() -> bool:
	var good := simple_payload()
	var bytes: PackedByteArray = CODEC.encode(good).bytes
	check(bytes[0] == 1 and bytes.slice(1,5) == PackedByteArray([0,0,0,7]),"big-endian v1/epoch golden")
	var one := {"epoch":7,"first_sequence":1,"last_sequence":1,"events":[good.events[0]]}
	check(CODEC.encode(one).bytes.hex_encode() == "010000000700000001000000010102001c000000000000000100000001000000000000000107373a313a313a31","single join event exact independent wire golden")
	var rejected := 0
	for length in range(bytes.size()):
		if not CODEC.decode(bytes.slice(0,length)).ok: rejected+=1
	check(rejected == bytes.size(),"every truncated prefix rejected before result installation")
	var over := PackedByteArray();over.resize(CODEC.MAX_BODY+1)
	check(not CODEC.decode(over).ok,"oversized byte body rejected")
	for replacement: Array in [[0,2],[13,65],[14,255],[15,255],[16,255],[37,255]]:
		var mutated := bytes.duplicate();mutated[replacement[0]]=replacement[1]
		check(not CODEC.decode(mutated).ok,"version/count/type/length/text attack rejected")
	var trailing := bytes.duplicate();trailing.append(0)
	check(not CODEC.decode(trailing).ok,"trailing body byte rejected")
	var rng := RandomNumberGenerator.new();rng.seed=9367
	var iterations := 0
	for i in range(500):
		var fuzz := bytes.duplicate()
		for j in range(rng.randi_range(1,5)): fuzz[rng.randi_range(0,fuzz.size()-1)] = rng.randi_range(0,255)
		var outcome := CODEC.decode(fuzz)
		if outcome.ok: check(CODEC.encode(outcome.payload).bytes == fuzz,"accepted mutation remains canonical, not unchecked Variant")
		iterations+=1
	check(iterations == 500,"bounded deterministic random byte mutations completed")
	var noise_rejected := 0
	for i in range(250):
		var noise := PackedByteArray();noise.resize(rng.randi_range(0,400))
		for j in range(noise.size()): noise[j]=rng.randi_range(0,255)
		if not CODEC.decode(noise).ok: noise_rejected+=1
	check(noise_rejected == 250,"arbitrary bounded noise rejected without parser faults")
	var invalid_utf8 := bytes.duplicate();invalid_utf8[38]=0xff
	check(not CODEC.decode(invalid_utf8).ok,"invalid UTF8 rejected without engine decode warnings")
	for invalid: PackedByteArray in [PackedByteArray([0xc0,0x80]),PackedByteArray([0xed,0xa0,0x80]),PackedByteArray([0xf4,0x90,0x80,0x80]),PackedByteArray([0xc2,0x80])]:
		var malformed := bytes.duplicate()
		for j in range(invalid.size()): malformed[38+j]=invalid[j]
		check(not CODEC.decode(malformed).ok,"overlong/surrogate/out-of-range/C1 UTF8 rejected")
	var actor_state := STATE.new(1,"Array limits",7);actor_state.spawn_generation=2
	var source := RULES.event(actor_state,0,"shot",{"weapon":0,"profile":"0.75","origin":Vector3.ONE,"directions":[Vector3.FORWARD],"recoil_direction":Vector3.FORWARD}).duplicate(true)
	source.match_sequence=1
	var payload: Dictionary = CODEC.from_events(7,[source]).payload.duplicate(true)
	for rays: Array in [[],[Vector3.ZERO],[Vector3(NAN,0,0)],[Vector3.FORWARD,Vector3.FORWARD]]:
		var mutated: Dictionary = payload.duplicate(true);mutated.events[0].directions=rays
		reject(mutated,"invalid/nonfinite/mismatched pellet arrays rejected")
	var ray_bytes: PackedByteArray = CODEC.encode(payload).bytes
	var base: int = 17+21+payload.events[0].event_id.to_utf8_buffer().size()
	var nan_ray := ray_bytes.duplicate()
	# weapon/profile(2) + origin(12) + count(1), then first ray f32.
	for i in range(4): nan_ray[base+15+i]=[0x7f,0xc0,0,0][i]
	check(not CODEC.decode(nan_ray).ok,"wire NaN pellet coordinate rejected")
	var huge_count := ray_bytes.duplicate();huge_count[base+14]=255
	check(not CODEC.decode(huge_count).ok,"nested pellet count checked before ray allocation")
	var block_source := RULES.event(actor_state,0,"blocks_built",{"cells":[Vector3i(1,4,1)],"line":false,"color":0x01ffffff}).duplicate(true)
	block_source.match_sequence=1
	var block_payload: Dictionary = CODEC.from_events(7,[block_source]).payload.duplicate(true)
	for changed: Dictionary in [{"cells":[]},{"cells":[Vector3i(1,4,1),Vector3i(1,4,1)]},{"cells":[Vector3i(-1,4,1)]},{"cells":[Vector3i(512,4,1)]},{"cells":[Vector3i(1,64,1)]},{"cells":[Vector3.ONE]},{"color":0x02ffffff},{"line":1}]:
		var invalid_block := block_payload.duplicate(true);invalid_block.events[0].merge(changed,true)
		reject(invalid_block,"block type/count/duplicate/cell bounds/color rejected")
	var fifty: Array[Vector3i] = []
	for i in range(50): fifty.append(Vector3i(i,4,1))
	block_payload.events[0].cells=fifty
	check(CODEC.encode(block_payload).ok,"source maximum50 unique build cells accepted")
	fifty.append(Vector3i(50,4,1))
	reject(block_payload,"51 build cells rejected before writing")
	var many := good.duplicate(true)
	many.events.clear()
	for i in range(65):
		var event: Dictionary = good.events[0].duplicate(true);event.event_id="7:1:1:%d" % (i+1);event.match_sequence=i+1;many.events.append(event)
	many.first_sequence=1;many.last_sequence=65
	reject(many,"65 records rejected before serialization")
	many.events.pop_back();many.last_sequence=64
	check(CODEC.encode(many).ok,"exact64 event boundary supported")
	check(not CODEC.encode({"epoch":7,"first_sequence":1,"last_sequence":1,"events":[]}).ok,"empty batch cannot claim consumed cursor")
	check(CODEC.decode(CODEC.encode({"epoch":7,"first_sequence":0,"last_sequence":0,"events":[]}).bytes).ok,"empty frame canonical")
	return true

func routing_and_replay() -> bool:
	var sim := fixture()
	var owner := actor(sim,"Owner",0,Vector3(20.5,4.01,40.5))
	actor(sim,"Victim",1,Vector3(20.5,4.01,30.5))
	sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	var all := sim.drain_events()
	var public: Array[Dictionary] = []
	var personal: Array[Dictionary] = []
	for event: Dictionary in all:
		if CODEC.visibility(event.type) == "public": public.append(event)
		elif event.owner_id == owner.player_id: personal.append(event)
	var routed := roundtrip(public)
	var owner_feedback := roundtrip(personal)
	check(find_event(routed,"hurt").is_empty() and find_event(routed,"hit_confirmed").is_empty() and not find_event(routed,"death").is_empty(),"public route excludes private hurt/confirmation while preserving kill feed")
	check(not find_event(owner_feedback,"hit_confirmed").is_empty() and find_event(owner_feedback,"hurt").is_empty(),"owner only gets its own confirmation, no enemy personal hurt")
	var seen := {}
	var played := 0
	for repeat in range(2):
		for event: Dictionary in routed.events:
			if seen.has(event.event_id): continue
			seen[event.event_id]=event.match_sequence;played+=1
	check(played == routed.events.size() and routed.first_sequence < routed.last_sequence,"replayed frame stable IDs deduplicate exactly once despite private cursor gaps")
	check(CODEC.visibility("unknown") == "invalid","routing unknown types cannot default to public")
	var overflow := fixture()
	var source := actor(overflow,"Overflow",0,Vector3(20.5,4.01,40.5))
	var large: Array[Dictionary] = []
	for i in range(2049): large.append(RULES.event(source,0,"dry_fire"))
	overflow._record_events(large)
	var marker := roundtrip(overflow.drain_events())
	check(marker.events.size() == 1 and marker.events[0].resync_required and marker.first_sequence == overflow.event_sequence,"loss marker announces current global cursor, no invented missing events")
	return true
