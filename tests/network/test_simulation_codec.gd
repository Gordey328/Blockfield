extends SceneTree
const CODEC = preload("res://network/simulation_codec.gd")
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const DATA = preload("res://world/voxel_data.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const GRENADE = preload("res://simulation/grenade_state.gd")
const GRENADES = preload("res://simulation/grenade_rules.gd")
const OBJECTIVES = preload("res://simulation/match_objectives.gd")
const PREDICTION = preload("res://network/client_prediction.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SIMULATION CODEC: " + message)

func map_data() -> DATA:
	var data := DATA.new()
	data.clear(Vector3i(64,32,64),7)
	data.seed_box(Vector3i(0,1,0),Vector3i(64,4,64),0x01557799)
	return data

func actor(id: int = 5, weapon: int = 1, now: int = 500) -> STATE:
	var result := STATE.new(id,"Owner" if id == 5 else "Other",7,"0.75",98765)
	RULES.spawn(result,0,Vector3(20.5+id,4.01,20.5),0 if id == 5 else 1,weapon)
	result.tool_raise = 1
	result.last_tick = now
	result.motion.grounded = true
	return result

func projectile(id: int = 1, now: int = 500) -> GRENADE:
	return GRENADES.create(id,5,1,7,now,Vector3(22,8,23),Vector3(1,2,3),1.2345,31)

func objectives(mode: String = "sandbox") -> Dictionary:
	var source := OBJECTIVES.new()
	source.configure(7,mode,[Vector3(10,4,10),Vector3(50,4,50)],[Vector3(20,4,30),Vector3(32,4,30),Vector3(44,4,30)])
	return source.snapshot().duplicate(true)

func snapshot(owner: STATE, others: Array = [], projectiles: Array = [], mode: String = "sandbox") -> Dictionary:
	var actors: Array = [owner]
	actors.append_array(others)
	var teams := {}
	for value: GRENADE in projectiles: teams[value.grenade_id] = 0
	return {"epoch":7,"tick":owner.last_tick,"map_sequence":12,"dimensions":Vector3i(64,32,64),"event_sequence":93,"profile":owner.profile,"mode":mode,"owner_state":owner,"actors":actors,"grenades":projectiles,"grenade_teams":teams,"objectives":objectives(mode),"owner_id":owner.player_id,"block_health":{"debug":"ignored"},"line_start":{"debug":"ignored"},"secondary":{"debug":"ignored"}}

func payload(owner: STATE = null) -> Dictionary:
	var projected := CODEC.from_snapshot(snapshot(owner if owner != null else actor(),[actor(6)],[projectile()]))
	check(projected.ok,"trusted fixture projected: " + projected.error)
	return projected.get("payload",{})

func owned_clone(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.owner_state = source.owner_state.copy()
	return result

func reject_payload(value: Dictionary, message: String) -> void:
	var result := CODEC.encode(value)
	check(not result.ok and not result.error.is_empty() and result.bytes.is_empty() and result.payload.is_empty(),message)

func reject_bytes(bytes: PackedByteArray, message: String) -> void:
	var result := CODEC.decode(bytes)
	check(not result.ok and not result.error.is_empty() and result.payload.is_empty(),message)

func same_owner(actual: STATE, expected: STATE, label: String) -> void:
	for property: Dictionary in expected.get_script().get_script_property_list():
		var key: String = property.name
		if key in ["motion","shot_rng"]: continue
		check(actual.get(key) == expected.get(key),label + " owner " + key)
	for property: Dictionary in expected.motion.get_script().get_script_property_list():
		var key: String = property.name
		check(actual.motion.get(key) == expected.motion.get(key),label + " motion " + key)

func basic() -> void:
	for mode: String in ["sandbox","ctf","tc"]:
		var simulation := MATCH.new()
		check(simulation.configure(map_data(),"0.76",mode).ok,"real coordinator configured")
		var id: int = simulation.add_actor("Игрок",0).actor_id
		simulation.add_actor("Observer")
		check(not CODEC.from_snapshot(simulation.snapshot_for(id)).ok,"pre-step last_tick -1 is not a replay checkpoint")
		simulation.step_fixed()
		var projected := CODEC.from_snapshot(simulation.snapshot_for(id))
		check(projected.ok,"real after-tick coordinator snapshot " + mode + ": " + projected.error)
		if not projected.ok: continue
		var encoded := CODEC.encode(projected.payload)
		var decoded := CODEC.decode(encoded.bytes)
		check(decoded.ok,"real snapshot round trip " + mode + ": " + decoded.error)
		if not decoded.ok: continue
		same_owner(decoded.payload.owner_state,simulation.get_actor(id),mode)
		check(decoded.payload.objectives == projected.payload.objectives,"typed objectives round trip " + mode)
		check(decoded.payload.actors == projected.payload.actors,"full public poses round trip " + mode)
		var remotes := PREDICTION.RemotePoseBuffer.new()
		check(remotes.push(decoded.payload.actors[1],7,0).ok,"public actor feeds existing interpolation contract")
	var value := payload()
	var encoded := CODEC.encode(value)
	check(encoded.bytes.slice(0,26) == PackedByteArray([0,1,0,0,0,7,0,0,1,244,0,0,0,12,0,64,0,32,0,64,0,0,0,93,0,0]),"fixed-order big endian version/header fixture")
	var decoded := CODEC.decode(encoded.bytes)
	check(decoded.ok and decoded.payload.grenades == value.grenades,"live grenade vectors, quaternion and fractional fuse")
	value.owner_state.motion.feet_position = Vector3(-8,250,70)
	value.owner_state.motion.eye_position = Vector3(-8,251,70)
	value.actors[0] = CODEC._public_actor(value.owner_state)
	check(CODEC.encode(value).ok,"above ground and source boundary movement permitted within sanity margin")

func exact_fields_and_privacy() -> void:
	var source := actor()
	source.player_name = "Локальный игрок"
	source.pending_weapon = 2
	source.tool = 3
	source.displayed_tool = 1
	source.displayed_weapon = 0
	source.tool_raise = .375
	source.sprint_state = .125
	source.aim_down_state = .625
	source.aiming = true
	source.sprinting = true
	source.sneaking = true
	source.yaw = .123456789123
	source.pitch = -.543210987321
	source.health = 83
	source.magazine = 17
	source.reserve = 61
	source.blocks = 29
	source.grenades = 2
	source.kills = 23
	source.deaths = 12
	source.score = 123456
	source.consumed_input_sequence = 999
	source.input_move = Vector2(.3,.4)
	source.input_buttons = 127
	source.previous_buttons = 127
	source.trigger_held = true
	source.dry_fire_held = true
	source.next_shot_tick = 515.2000000000003
	source.last_shot_tick = 499
	source.reload_started_tick = 321.123456789
	source.reload_deadline_tick = 444.999999999
	source.grenade_deadline_tick = 520.5
	source.block_deadline_tick = 513.2
	source.spade_deadline_tick = 513.01
	source.dig_deadline_tick = 570.4
	source.digging = true
	source.first_dig = false
	source.cooking = true
	source.cook_started_tick = 494
	source.cook_action_sequence = 998
	source.release_pending = true
	source.death_tick = 21
	source.respawn_tick = 201
	source.event_sequence = 4433
	source.walk_distance = 2.3456789123
	source.walk_steps = 887
	source.motion.feet_position = Vector3(20.123,7.45,35.321)
	source.motion.native_velocity = Vector3(-.345,.123,.432)
	source.motion.eye_position = Vector3(20.123,9.999,35.321)
	source.motion.front = source.front()
	source.motion.crouch = true
	source.motion.sprint = true
	source.motion.grounded = false
	source.motion.wading = true
	source.motion.last_climb_time = 7.777777777
	source.motion.climbed = true
	source.motion.vertical_collision = true
	source.motion.landed = true
	source.motion.fall_hurt = true
	# The source landing sample retains signed vertical speed during a jump.
	source.motion.fall_speed = -.29420524835587
	var trusted := snapshot(source,[actor(6)],[projectile()])
	var first := CODEC.from_snapshot(trusted)
	check(first.ok,"all replay fields projected: " + first.error)
	if not first.ok: return
	var bytes: PackedByteArray = CODEC.encode(first.payload).bytes
	var decoded := CODEC.decode(bytes)
	check(decoded.ok,"all replay fields decoded: " + decoded.error)
	if not decoded.ok: return
	same_owner(decoded.payload.owner_state,source,"complete checkpoint")
	check(decoded.payload.owner_state != source and decoded.payload.owner_state.motion != source.motion,"decoded mutable owner and motion independently owned")
	check(decoded.payload.owner_state.shot_rng.seed == 1 and source.shot_rng.seed != 1,"decoded owner has only local default RNG")
	source.shot_rng.seed = 0x1234567890abcdef
	source.shot_rng.randf()
	var remote: STATE = trusted.actors[1]
	remote.shot_rng.seed = 0x7987654321
	remote.health = 1
	remote.magazine = 1
	remote.reserve = 3
	remote.blocks = 4
	remote.grenades = 1
	remote.input_buttons = 127
	remote.previous_buttons = 65
	remote.consumed_input_sequence = 600000
	remote.next_shot_tick = 12345.678
	trusted.block_health = {"huge_debug":"must never encode"}
	var changed := CODEC.from_snapshot(trusted)
	check(changed.ok and CODEC.encode(changed.payload).bytes == bytes,"server RNG/private remote controls/resources/debug fields never change wire bytes")
	decoded.payload.owner_state.motion.feet_position = Vector3.ZERO
	check(source.motion.feet_position != Vector3.ZERO,"decode does not mutate trusted authority")

func replay() -> void:
	var query := map_data()
	for scenario: int in range(4):
		var authority := actor(5,1 if scenario == 0 else 2,0)
		var snap_tick := 19
		for tick: int in range(1,161):
			var input := RULES.Command.new()
			input.sequence = tick
			input.spawn_generation = authority.spawn_generation
			input.yaw = .0123456789123
			input.pitch = .123456789123
			if scenario == 0: input.buttons = RULES.Buttons.PRIMARY
			elif scenario == 1:
				if tick == 1: authority.magazine = 2
				input.buttons = RULES.Buttons.RELOAD if tick == 1 else 0
			elif scenario == 2:
				input.tool = 3
				input.buttons = RULES.Buttons.PRIMARY if tick < 26 else 0
			else:
				input.buttons = RULES.Buttons.SPRINT if tick < 30 else (RULES.Buttons.CROUCH if tick > 50 else 0)
				input.move = Vector2(.6,-.8)
			RULES.step_fixed(authority,tick,input,query)
			if tick != snap_tick: continue
			var baseline := CODEC.from_snapshot(snapshot(authority))
			check(baseline.ok,"active source checkpoint %d: %s" % [scenario,baseline.error])
			if not baseline.ok: break
			var decoded := CODEC.decode(CODEC.encode(baseline.payload).bytes)
			check(decoded.ok,"source checkpoint decoded")
			if not decoded.ok: break
			var restored: STATE = decoded.payload.owner_state
			same_owner(restored,authority,"before replay%d" % scenario)
			var shot_ticks_a: Array[int] = []
			var shot_ticks_b: Array[int] = []
			for future: int in range(tick+1,161):
				var command := RULES.Command.new()
				command.sequence = future
				command.spawn_generation = authority.spawn_generation
				command.yaw = input.yaw
				command.pitch = input.pitch
				if scenario == 0: command.buttons = RULES.Buttons.PRIMARY
				elif scenario == 2:
					command.tool = 3
					command.buttons = RULES.Buttons.PRIMARY if future < 26 else 0
				elif scenario == 3:
					command.buttons = RULES.Buttons.SPRINT if future < 30 else (RULES.Buttons.CROUCH if future > 50 else 0)
					command.move = Vector2(.6,-.8)
				var a: Array[Dictionary] = RULES.step_fixed(authority,future,command,query)
				var b: Array[Dictionary] = RULES.step_fixed(restored,future,command,query)
				for event: Dictionary in a:
					if event.type == "shot": shot_ticks_a.append(future)
				for event: Dictionary in b:
					if event.type == "shot": shot_ticks_b.append(future)
				check(authority.next_shot_tick == restored.next_shot_tick and authority.reload_deadline_tick == restored.reload_deadline_tick and authority.grenade_deadline_tick == restored.grenade_deadline_tick,"fractional cadence replay %d/%d" % [scenario,future])
			same_owner(restored,authority,"after replay%d" % scenario)
			check(shot_ticks_a == shot_ticks_b,"shot event ticks identical after fractional deadline restore")
			break

func maximum() -> void:
	var owner := actor()
	owner.player_name = "Я".repeat(32)
	var others: Array = []
	for i: int in range(31):
		var other := actor(i+10)
		other.player_name = "Я".repeat(32)
		others.append(other)
	var grenades: Array = []
	for i: int in range(256): grenades.append(projectile(i+1))
	var trusted := snapshot(owner,others,grenades,"tc")
	trusted.objectives.territories.clear()
	for i: int in range(16): trusted.objectives.territories.append({"position":Vector3(20+i,4,30),"owner":i%3,"capturing_team":i%2,"progress":.123456789123,"contested":i%2==0})
	var projected := CODEC.from_snapshot(trusted)
	check(projected.ok,"maximum bounded source snapshot")
	if not projected.ok: return
	var bytes: PackedByteArray = CODEC.encode(projected.payload).bytes
	check(bytes.size() == 24748 and bytes.size() <= CODEC.MAX_BODY,"actual maximum body 24748 bytes")
	var decoded := CODEC.decode(bytes)
	check(decoded.ok and decoded.payload.actors.size() == 32 and decoded.payload.grenades.size() == 256 and decoded.payload.objectives.territories.size() == 16,"maximum decoded without truncation/count loss")
	var p := owned_clone(projected.payload)
	p.actors.append(p.actors[0].duplicate(true))
	reject_payload(p,"actor count checked before serialization")
	p = owned_clone(projected.payload)
	p.grenades.append(p.grenades[0].duplicate(true))
	reject_payload(p,"grenade count checked before serialization")
	p = owned_clone(projected.payload)
	p.objectives.territories.append(p.objectives.territories[0].duplicate(true))
	reject_payload(p,"territory count checked before serialization")

func bad_local() -> void:
	var valid := payload()
	for key: String in CODEC.PAYLOAD_KEYS:
		var p := owned_clone(valid)
		p.erase(key)
		reject_payload(p,"missing allowlist field " + key)
	var p := owned_clone(valid)
	p.opaque = {"fallback":"forbidden"}
	reject_payload(p,"no opaque top-level dictionary fallback")
	for pair: Array in [["epoch",0],["epoch",7.0],["tick",-1],["map_sequence",-1],["event_sequence",0x100000000],["dimensions",Vector3i(513,32,64)],["dimensions",Vector3i(64,65,64)],["dimensions",Vector3.ZERO],["profile","unknown"],["mode","unknown"]]:
		p = owned_clone(valid);p[pair[0]] = pair[1]
		reject_payload(p,"invalid top field " + pair[0])
	for pair: Array in [["spawn_generation",0],["health",101],["magazine",31],["reserve",151],["blocks",51],["grenades",4],["previous_buttons",128],["pending_weapon",3],["input_move",Vector2(1,1)],["yaw",NAN],["next_shot_tick",INF],["spade_deadline_tick",-2.0],["tool_raise",1.1],["last_tick",499],["match_epoch",8],["respawn_tick",681]]:
		p = owned_clone(valid);p.owner_state.set(pair[0],pair[1])
		reject_payload(p,"invalid owner field " + pair[0])
	p = owned_clone(valid);p.owner_state.motion = null
	reject_payload(p,"missing motion does not cause script exception")
	for pair: Array in [["id",0],["spawn_generation",0],["team",3],["flags",256],["flags",{}],["alive",2],["weapon",3],["feet",Vector3(INF,0,0)],["feet",Vector3(2000,0,0)],["pitch",2.0],["name",""],["name","a".repeat(65)],["name","\ncontrol"],["name","x\u0085y"],["score",-1],["kills",1.0]]:
		p = owned_clone(valid);p.actors[1][pair[0]] = pair[1]
		reject_payload(p,"invalid public actor field " + pair[0])
	p = owned_clone(valid);p.actors[1].health = 100
	reject_payload(p,"hidden remote resources rejected by exact allowlist")
	p = owned_clone(valid);p.actors[1].id = 5
	reject_payload(p,"duplicate public ID")
	p = owned_clone(valid);p.actors[0].score += 1
	reject_payload(p,"owner/public views cannot disagree")
	for pair: Array in [["id",0],["owner_generation",0],["team",3],["position",Vector3(5000,4,0)],["velocity",Vector3(INF,0,0)],["orientation",Quaternion(0,0,0,0)],["orientation",Vector3.ZERO],["created_tick","bad"],["last_tick",400],["fuse_deadline_tick",1000.0],["finished",true],["finished",2]]:
		p = owned_clone(valid);p.grenades[0][pair[0]] = pair[1]
		reject_payload(p,"invalid grenade field " + pair[0])
	p = owned_clone(valid);p.grenades.append(p.grenades[0].duplicate(true))
	reject_payload(p,"duplicate grenade ID")
	for pair: Array in [["capture_limit",0],["winning_team",2],["winning_team",-1.0],["epoch",8],["epoch",7.0],["scores",[1]],["bases",[Vector3.ZERO]],["flags",[]],["mode","ctf"]]:
		p = owned_clone(valid);p.objectives[pair[0]] = pair[1]
		reject_payload(p,"invalid objective field " + pair[0])
	for pair: Array in [["team",1],["carrier",0],["carrier",5],["position",Vector3(20,4,30)],["at_base",2]]:
		p = owned_clone(valid);p.objectives.flags[0][pair[0]] = pair[1]
		reject_payload(p,"invalid flag field " + pair[0])
	p = owned_clone(valid);p.objectives.flags[1].carrier = 5;p.objectives.flags[1].at_base = false
	check(CODEC.encode(p).ok,"living enemy carrier valid")
	p.actors[0].connected = false;p.actors[0].flags &= ~32;p.owner_state.connected = false
	reject_payload(p,"disconnected carrier invalid")
	for pair: Array in [["owner",3],["capturing_team",2],["capturing_team",-1.0],["progress",NAN],["progress",1.1],["contested",1]]:
		p = owned_clone(valid);p.objectives.territories[0][pair[0]] = pair[1]
		reject_payload(p,"invalid territory field " + pair[0])
	var trusted := snapshot(actor(),[actor(6)],[projectile()])
	trusted.actors[1].match_epoch = 8
	check(not CODEC.from_snapshot(trusted).ok,"trusted actor stale epoch rejected before projection")
	trusted.actors[1].match_epoch = 7;trusted.actors[1].last_tick = 499
	check(not CODEC.from_snapshot(trusted).ok,"trusted actor wrong checkpoint tick rejected")
	trusted.actors[1].last_tick = 500;trusted.grenades[0].match_epoch = 8
	check(not CODEC.from_snapshot(trusted).ok,"trusted projectile stale epoch rejected")
	trusted.objectives = "wrong"
	check(not CODEC.from_snapshot(trusted).ok,"trusted objectives wrong type safely rejected")

func changed(bytes: PackedByteArray, offset: int, values: PackedByteArray) -> PackedByteArray:
	var result := bytes.duplicate()
	for i: int in range(values.size()): result[offset+i] = values[i]
	return result

func bad_wire() -> void:
	var p := payload()
	var bytes: PackedByteArray = CODEC.encode(p).bytes
	for length: int in range(bytes.size()): reject_bytes(bytes.slice(0,length),"all truncation prefixes " + str(length))
	reject_bytes(bytes+PackedByteArray([0]),"trailing data")
	reject_bytes(bytes+bytes,"concatenated bodies cannot bypass framing")
	var oversized := PackedByteArray();oversized.resize(CODEC.MAX_BODY+1)
	reject_bytes(oversized,"outer body size checked before reader allocation")
	# Owner starts at byte26, fixed bytes279 plus name bytes. Offsets are
	# independent wire fixtures rather than values derived from codec helpers.
	var owner_name_len := 5
	var actor_count_offset := 26+279+owner_name_len
	var first_actor_size := 92+5
	var second_actor_size := 92+5
	var gren_count_offset := actor_count_offset+1+first_actor_size+second_actor_size
	var grenade_offset := gren_count_offset+2
	var obj_offset := grenade_offset+74
	for entry: Array in [[0,[0,2]],[2,[0,0,0,0]],[14,[2,1]],[18,[2,1]],[24,[2]],[25,[3]],[34,[2]],[35,[0,0]],[35,[0,65]],[37,[0xc0,0x80]],[37,[0xed,0xa0,0x80]],[37,[0xf4,0x90,0x80,0x80]],[37,[0xc2,0x85]],[42,[3]],[52,[128]],[116,[2]],[150,[0x7f,0xf8,0,0,0,0,0,0]],[174,[0x7f,0xf0,0,0,0,0,0,0]],[238,[0x7f,0xc0,0,0]],[actor_count_offset,[33]],[gren_count_offset,[1,1]],[grenade_offset+73,[2]],[obj_offset+2,[2]],[obj_offset+71,[17]]]:
		reject_bytes(changed(bytes,entry[0],PackedByteArray(entry[1])),"malformed fixed byte at " + str(entry[0]))
	# Two actor records with same ID, and strict encoded bool mismatch in flags.
	var second_actor_offset := actor_count_offset+1+first_actor_size
	reject_bytes(changed(bytes,second_actor_offset,PackedByteArray([0,0,0,5])),"duplicate actor ID in untrusted body")
	# All maximum-count headers are rejected while remaining data is too short.
	reject_bytes(changed(bytes,actor_count_offset,PackedByteArray([32])).slice(0,actor_count_offset+1+93),"actor minimum record bytes bounded before loop")
	# A valid owner quaternion cannot contain a NaN either.
	reject_bytes(changed(bytes,grenade_offset+41,PackedByteArray([0x7f,0xc0,0,0])),"untrusted grenade orientation NaN")

func run() -> void:
	basic()
	exact_fields_and_privacy()
	replay()
	maximum()
	bad_local()
	bad_wire()
	print("SIMULATION CODEC: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
