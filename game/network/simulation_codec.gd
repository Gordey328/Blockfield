class_name SimulationCodec
extends RefCounted
## Explicit full-state body for a future protocol envelope. No generic Variant
## serialization, network objects, renderer or server pellet RNG on the wire.

const STATE = preload("res://simulation/player_state.gd")
const GRENADE = preload("res://simulation/grenade_state.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const VERSION := 1
const MAX_BODY := 32744
const MAX_ACTORS := 32
const MAX_GRENADES := 256
const MAX_TERRITORIES := 16
const U32_MAX := 0xffffffff
const FUTURE_TICK_MAX := float(U32_MAX) + 600.0
const MODES := ["sandbox","ctf","tc"]
const VERSIONS := ["0.75","0.76"]
const PAYLOAD_KEYS := ["epoch","tick","map_sequence","dimensions","event_sequence","profile","mode","owner_state","actors","grenades","objectives"]
const ACTOR_KEYS := ["id","spawn_generation","name","team","flags","connected","alive","crouch","sprinting","grounded","wading","reloading","cooking","feet","native_velocity","yaw","pitch","tool","weapon","displayed_tool","displayed_weapon","tool_raise","sprint_state","aim_down_state","kills","deaths","score"]
const GRENADE_KEYS := ["id","owner_id","owner_generation","action_sequence","team","position","velocity","orientation","created_tick","last_tick","fuse_deadline_tick","finished"]
const OBJECTIVE_KEYS := ["epoch","mode","capture_limit","winning_team","scores","bases","flags","territories"]
# Names below are compile-time allowlists, never property names from bytes.
const OWNER_U8 := ["team","weapon","tool","displayed_tool","displayed_weapon","health","magazine","blocks","grenades","input_buttons","previous_buttons"]
const OWNER_U32 := ["kills","deaths","score","consumed_input_sequence","cook_action_sequence","event_sequence","walk_steps"]
const OWNER_I64 := ["last_shot_tick","cook_started_tick","death_tick","respawn_tick"]
const OWNER_BOOL := ["aiming","sprinting","sneaking","trigger_held","dry_fire_held","reloading","digging","first_dig","cooking","release_pending"]
const OWNER_UNIT := ["tool_raise","sprint_state","aim_down_state"]
const OWNER_DEADLINES := ["next_shot_tick","reload_started_tick","reload_deadline_tick","grenade_deadline_tick","block_deadline_tick","spade_deadline_tick","dig_deadline_tick"]
const MOTION_BOOL := ["crouch","sprint","grounded","wading","climbed","vertical_collision","landed","fall_hurt"]

class SharedFrame extends RefCounted:
	# Native publication scratch space, never constructed from network bytes.
	# Common records are validated once; each owner's private record is still
	# validated independently and must match the captured public pose.
	var _context: Dictionary = {}
	var _actors: Dictionary = {}
	var _header := PackedByteArray()
	var _tail := PackedByteArray()
	func encode_owner(owner: STATE) -> Dictionary:
		if _header.size() != 26 or owner == null or not _actors.has(owner.player_id): return SimulationCodec._failure("uncaptured snapshot owner")
		var w := Writer.new()
		SimulationCodec._write_owner(owner,_context,w)
		if not w.error.is_empty(): return SimulationCodec._failure(w.error)
		if SimulationCodec._public_actor(owner) != _actors[owner.player_id]: return SimulationCodec._failure("owner/public actor mismatch")
		var bytes := _header + w.stream.data_array + _tail
		if bytes.size() > MAX_BODY: return SimulationCodec._failure("simulation body exceeds limit")
		return {"ok":true,"error":"","bytes":bytes,"epoch":_context.epoch,"tick":_context.tick,"generation":owner.spawn_generation}

static func prepare_shared(snapshot: Dictionary) -> Dictionary:
	var converted := from_snapshot(snapshot)
	if not converted.ok: return converted
	var p: Dictionary = converted.payload
	var owner_writer := Writer.new()
	_write_owner(p.owner_state,p,owner_writer)
	if not owner_writer.error.is_empty(): return _failure(owner_writer.error)
	var frame := SharedFrame.new()
	frame._context = {"epoch":p.epoch,"tick":p.tick,"profile":p.profile,"dimensions":p.dimensions}
	frame._context.make_read_only()
	for actor: Dictionary in p.actors:
		var captured := actor.duplicate(true)
		captured.make_read_only()
		frame._actors[actor.id] = captured
	frame._actors.make_read_only()
	frame._header = converted.bytes.slice(0,26)
	frame._tail = converted.bytes.slice(26+owner_writer.stream.get_size())
	return {"ok":true,"error":"","frame":frame}

class UTF8 extends RefCounted:
	static func valid(data: PackedByteArray) -> bool:
		var offset := 0
		while offset < data.size():
			var first: int = data[offset]
			if first < 0x80:
				if first < 32 or first == 127: return false
				offset += 1
				continue
			var count := 0
			var lower := 0x80
			var upper := 0xbf
			if first >= 0xc2 and first <= 0xdf: count = 2
			elif first >= 0xe0 and first <= 0xef:
				count = 3
				if first == 0xe0: lower = 0xa0
				if first == 0xed: upper = 0x9f
			elif first >= 0xf0 and first <= 0xf4:
				count = 4
				if first == 0xf0: lower = 0x90
				if first == 0xf4: upper = 0x8f
			else: return false
			if offset + count > data.size() or data[offset+1] < lower or data[offset+1] > upper: return false
			if first == 0xc2 and data[offset+1] <= 0x9f: return false
			for i: int in range(2,count):
				if data[offset+i] < 0x80 or data[offset+i] > 0xbf: return false
			offset += count
		return true

class Writer extends RefCounted:
	var stream := StreamPeerBuffer.new()
	var error := ""
	func _init() -> void: stream.big_endian = true
	func fail(message: String) -> void:
		if error.is_empty(): error = message
	func room(count: int) -> bool:
		if not error.is_empty(): return false
		if stream.get_size() + count > MAX_BODY: fail("simulation body exceeds limit"); return false
		return true
	func integer(value: Variant, bytes: int, minimum: int = 0, maximum: int = U32_MAX) -> void:
		if typeof(value) != TYPE_INT or value < minimum or value > maximum: fail("integer type/range"); return
		if not room(bytes): return
		match bytes:
			1: stream.put_u8(value)
			2: stream.put_u16(value)
			4: stream.put_u32(value)
			8: stream.put_64(value)
	func boolean(value: Variant) -> void:
		if typeof(value) != TYPE_BOOL: fail("boolean type"); return
		integer(1 if value else 0,1,0,1)
	func number(value: Variant, minimum: float, maximum: float, double: bool = true) -> void:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value < minimum or value > maximum: fail("nonfinite/out-of-range number"); return
		if not room(8 if double else 4): return
		if double: stream.put_double(value)
		else: stream.put_float(value)
	func vector(value: Variant, minimum: Vector3, maximum: Vector3) -> void:
		if typeof(value) != TYPE_VECTOR3 or not value.is_finite(): fail("vector type/finite"); return
		for axis: int in range(3): number(value[axis],minimum[axis],maximum[axis],false)
	func text(value: Variant) -> void:
		if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 64: fail("name type/length"); return
		var bytes: PackedByteArray = value.to_utf8_buffer()
		if bytes.size() > 64 or not UTF8.valid(bytes): fail("name bytes/UTF8"); return
		integer(bytes.size(),2,1,64)
		if room(bytes.size()): stream.put_data(bytes)

class Reader extends RefCounted:
	var stream := StreamPeerBuffer.new()
	var error := ""
	func _init(bytes: PackedByteArray) -> void:
		stream.big_endian = true
		stream.data_array = bytes
	func fail(message: String) -> void:
		if error.is_empty(): error = message
	func has(count: int) -> bool:
		if not error.is_empty(): return false
		if count < 0 or stream.get_available_bytes() < count: fail("truncated simulation body"); return false
		return true
	func integer(bytes: int) -> int:
		if not has(bytes): return 0
		match bytes:
			1: return stream.get_u8()
			2: return stream.get_u16()
			4: return stream.get_u32()
			8: return stream.get_64()
		return 0
	func boolean() -> bool:
		var value := integer(1)
		if value > 1: fail("invalid boolean")
		return value == 1
	func number(double: bool = true) -> float:
		if not has(8 if double else 4): return 0
		var value := stream.get_double() if double else stream.get_float()
		if not is_finite(value): fail("nonfinite number")
		return value
	func vector() -> Vector3:
		return Vector3(number(false),number(false),number(false))
	func text() -> String:
		var count := integer(2)
		if count < 1 or count > 64: fail("invalid name byte length"); return ""
		if not has(count): return ""
		var bytes: PackedByteArray = stream.get_data(count)[1]
		if not UTF8.valid(bytes): fail("invalid name UTF8"); return ""
		return bytes.get_string_from_utf8()
	func count(maximum: int, minimum_record_bytes: int, width: int = 1) -> int:
		var value := integer(width)
		if value > maximum: fail("count exceeds limit"); return 0
		if not has(value*minimum_record_bytes): return 0
		return value

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"bytes":PackedByteArray(),"payload":{}}

static func _keys(value: Variant, names: Array, w: Writer) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != names.size(): w.fail("wrong schema fields/type"); return false
	for key: Variant in value:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or key not in names: w.fail("unknown schema field"); return false
	return true

static func _array(value: Variant, maximum: int, w: Writer, exact: int = -1) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() > maximum or (exact >= 0 and value.size() != exact): w.fail("array count/type"); return false
	return true

static func _bounds(size: Vector3i, margin: float = 16.0) -> Array[Vector3]:
	return [Vector3(-margin,-256,-margin),Vector3(size.x+margin,size.y+256,size.z+margin)]

static func _flags(actor: STATE) -> int:
	return (1 if actor.is_alive() else 0) | (2 if actor.motion.crouch else 0) | (4 if actor.sprinting else 0) | (8 if actor.motion.wading else 0) | (16 if actor.motion.grounded else 0) | (32 if actor.connected else 0) | (64 if actor.reloading else 0) | (128 if actor.cooking else 0)

static func _public_actor(actor: STATE) -> Dictionary:
	return {"id":actor.player_id,"spawn_generation":actor.spawn_generation,"name":actor.player_name,"team":actor.team,"flags":_flags(actor),"connected":actor.connected,"alive":actor.is_alive(),"crouch":actor.motion.crouch,"sprinting":actor.sprinting,"grounded":actor.motion.grounded,"wading":actor.motion.wading,"reloading":actor.reloading,"cooking":actor.cooking,"feet":actor.feet(),"native_velocity":actor.motion.native_velocity,"yaw":actor.yaw,"pitch":actor.pitch,"tool":actor.tool,"weapon":actor.weapon,"displayed_tool":actor.displayed_tool,"displayed_weapon":actor.displayed_weapon,"tool_raise":actor.tool_raise,"sprint_state":actor.sprint_state,"aim_down_state":actor.aim_down_state,"kills":actor.kills,"deaths":actor.deaths,"score":actor.score}

static func _public_grenade(projectile: GRENADE, team: int) -> Dictionary:
	return {"id":projectile.grenade_id,"owner_id":projectile.owner_id,"owner_generation":projectile.owner_generation,"action_sequence":projectile.action_sequence,"team":team,"position":projectile.position,"velocity":projectile.velocity,"orientation":projectile.orientation,"created_tick":projectile.created_tick,"last_tick":projectile.last_tick,"fuse_deadline_tick":projectile.fuse_deadline_tick,"finished":projectile.finished}

static func _copy_owner(source: STATE) -> STATE:
	# Explicit approved fields only; never inspect/copy source.shot_rng.
	var target := STATE.new(source.player_id,source.player_name,source.match_epoch,source.profile,1)
	target.spawn_generation = source.spawn_generation
	target.connected = source.connected
	target.last_tick = source.last_tick
	target.reserve = source.reserve
	target.pending_weapon = source.pending_weapon
	target.yaw = source.yaw
	target.pitch = source.pitch
	target.input_move = source.input_move
	target.walk_distance = source.walk_distance
	for key: String in OWNER_U8 + OWNER_U32 + OWNER_I64 + OWNER_BOOL + OWNER_UNIT + OWNER_DEADLINES: target.set(key,source.get(key))
	target.motion = source.motion.copy()
	return target

static func from_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot.get("owner_state") is STATE or not snapshot.get("actors") is Array or not snapshot.get("grenades") is Array: return _failure("trusted snapshot objects missing")
	if snapshot.actors.size() > MAX_ACTORS or snapshot.grenades.size() > MAX_GRENADES: return _failure("trusted snapshot count exceeds limit")
	var owner: STATE = snapshot.owner_state
	if owner.motion == null: return _failure("trusted owner motion missing")
	var payload: Dictionary = {}
	for key: String in ["epoch","tick","map_sequence","dimensions","event_sequence","profile","mode","objectives"]:
		if not snapshot.has(key): return _failure("trusted snapshot field missing")
		if key == "objectives" and typeof(snapshot[key]) != TYPE_DICTIONARY: return _failure("trusted objective type")
		payload[key] = snapshot[key].duplicate(true) if key == "objectives" else snapshot[key]
	payload.owner_state = _copy_owner(owner)
	payload.actors = []
	for actor: Variant in snapshot.actors:
		if not actor is STATE or actor.motion == null: return _failure("trusted actor type/motion")
		if actor.match_epoch != payload.epoch or actor.profile != payload.profile or actor.last_tick != payload.tick: return _failure("trusted actor epoch/profile/tick mismatch")
		payload.actors.append(_public_actor(actor))
	payload.grenades = []
	var teams: Variant = snapshot.get("grenade_teams",{})
	if typeof(teams) != TYPE_DICTIONARY: return _failure("trusted grenade teams type")
	for projectile: Variant in snapshot.grenades:
		if not projectile is GRENADE: return _failure("trusted grenade type")
		if projectile.match_epoch != payload.epoch: return _failure("trusted grenade epoch mismatch")
		var team: Variant = teams.get(projectile.grenade_id,2)
		if typeof(team) != TYPE_INT: return _failure("trusted grenade team type")
		payload.grenades.append(_public_grenade(projectile,team))
	var encoded := encode(payload)
	if not encoded.ok: return encoded
	return {"ok":true,"error":"","payload":payload,"bytes":encoded.bytes}

static func encode(payload: Dictionary) -> Dictionary:
	var w := Writer.new()
	_write(payload,w)
	if not w.error.is_empty(): return _failure(w.error)
	return {"ok":true,"error":"","bytes":w.stream.data_array}

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 26 or bytes.size() > MAX_BODY: return _failure("simulation body size")
	var r := Reader.new(bytes)
	var version := r.integer(2)
	if version != VERSION: return _failure("unsupported simulation body version")
	var p := {"epoch":r.integer(4),"tick":r.integer(4),"map_sequence":r.integer(4),"dimensions":Vector3i(r.integer(2),r.integer(2),r.integer(2)),"event_sequence":r.integer(4)}
	var profile := r.integer(1)
	var mode := r.integer(1)
	if profile >= VERSIONS.size() or mode >= MODES.size(): return _failure("profile/mode enum")
	p.profile = VERSIONS[profile]
	p.mode = MODES[mode]
	p.owner_state = _read_owner(r,p)
	p.actors = []
	var count := r.count(MAX_ACTORS,93)
	for i: int in range(count):
		if not r.error.is_empty(): break
		p.actors.append(_read_actor(r))
	p.grenades = []
	count = r.count(MAX_GRENADES,74,2)
	for i: int in range(count):
		if not r.error.is_empty(): break
		p.grenades.append(_read_grenade(r))
	p.objectives = _read_objectives(r,p)
	if not r.error.is_empty(): return _failure(r.error)
	if r.stream.get_available_bytes() != 0: return _failure("trailing simulation bytes")
	var valid := encode(p) # Same explicit validation for local and decoded fields.
	if not valid.ok: return _failure(valid.error)
	return {"ok":true,"error":"","payload":p}

static func _write(p: Dictionary, w: Writer) -> void:
	if not _keys(p,PAYLOAD_KEYS,w): return
	w.integer(VERSION,2)
	w.integer(p.epoch,4,1)
	w.integer(p.tick,4)
	w.integer(p.map_sequence,4)
	if typeof(p.dimensions) != TYPE_VECTOR3I: w.fail("dimensions type"); return
	w.integer(p.dimensions.x,2,1,512)
	w.integer(p.dimensions.y,2,1,64)
	w.integer(p.dimensions.z,2,1,512)
	w.integer(p.event_sequence,4)
	if typeof(p.profile) != TYPE_STRING or typeof(p.mode) != TYPE_STRING or p.profile not in VERSIONS or p.mode not in MODES: w.fail("profile/mode enum"); return
	w.integer(VERSIONS.find(p.profile),1,0,1)
	w.integer(MODES.find(p.mode),1,0,2)
	if not w.error.is_empty(): return
	if not p.owner_state is STATE: w.fail("owner state type"); return
	_write_owner(p.owner_state,p,w)
	if not w.error.is_empty(): return
	if not _array(p.actors,MAX_ACTORS,w) or p.actors.is_empty(): w.fail("owner public actor missing"); return
	w.integer(p.actors.size(),1,1,MAX_ACTORS)
	var actor_ids: Dictionary = {}
	var owner_public: Dictionary = {}
	for actor: Variant in p.actors:
		if not _keys(actor,ACTOR_KEYS,w): return
		_write_actor(actor,p.dimensions,w)
		if not w.error.is_empty(): return
		if actor_ids.has(actor.id): w.fail("duplicate actor ID"); return
		actor_ids[actor.id] = actor
		if actor.id == p.owner_state.player_id: owner_public = actor
	if owner_public.is_empty() or owner_public != _public_actor(p.owner_state): w.fail("owner/public actor mismatch"); return
	if not _array(p.grenades,MAX_GRENADES,w): return
	w.integer(p.grenades.size(),2,0,MAX_GRENADES)
	var grenade_ids: Dictionary = {}
	for projectile: Variant in p.grenades:
		if not _keys(projectile,GRENADE_KEYS,w): return
		_write_grenade(projectile,p,w)
		if not w.error.is_empty(): return
		if grenade_ids.has(projectile.id): w.fail("duplicate grenade ID"); return
		grenade_ids[projectile.id] = true
	_write_objectives(p.objectives,p,actor_ids,w)

static func _write_owner(owner: STATE, p: Dictionary, w: Writer) -> void:
	if owner.motion == null or owner.match_epoch != p.epoch or owner.profile != p.profile or owner.last_tick != p.tick: w.fail("owner epoch/profile/tick mismatch"); return
	w.integer(owner.player_id,4,1)
	w.integer(owner.spawn_generation,4,1)
	w.boolean(owner.connected)
	w.text(owner.player_name)
	for key: String in OWNER_U8:
		var maximum := 3
		match key:
			"team": maximum = 2
			"weapon","displayed_weapon": maximum = 2
			"health": maximum = 100
			"magazine": maximum = int(PROFILES.get_info(owner.profile,owner.weapon).get("clip_size",0))
			"blocks": maximum = 50
			"input_buttons","previous_buttons": maximum = 127
		w.integer(owner.get(key),1,0,maximum)
	w.integer(owner.pending_weapon if owner.pending_weapon >= 0 else 255,1,0,255)
	if owner.pending_weapon not in [-1,0,1,2]: w.fail("pending weapon enum")
	w.integer(owner.reserve,2,0,int(PROFILES.get_info(owner.profile,owner.weapon).get("max_stock",0)))
	for key: String in OWNER_U32: w.integer(owner.get(key),4)
	for key: String in OWNER_I64: w.integer(owner.get(key),8,-1,int(p.tick)+180 if key == "respawn_tick" else p.tick)
	for key: String in OWNER_BOOL: w.boolean(owner.get(key))
	for key: String in OWNER_UNIT: w.number(owner.get(key),0,1)
	w.number(owner.yaw,-PI-0.000001,PI+0.000001)
	w.number(owner.pitch,-PI*0.5-0.000001,PI*0.5+0.000001)
	if not owner.input_move.is_finite() or owner.input_move.length_squared() > 1.000001: w.fail("owner input move")
	w.number(owner.input_move.x,-1,1,false)
	w.number(owner.input_move.y,-1,1,false)
	for key: String in OWNER_DEADLINES: w.number(owner.get(key),-1 if key in ["spade_deadline_tick","dig_deadline_tick"] else 0,FUTURE_TICK_MAX)
	w.number(owner.walk_distance,0,64)
	var bound := _bounds(p.dimensions)
	w.vector(owner.motion.feet_position,bound[0],bound[1])
	w.vector(owner.motion.native_velocity,Vector3.ONE*-128,Vector3.ONE*128)
	w.vector(owner.motion.eye_position,bound[0],bound[1]+Vector3.UP*4)
	w.vector(owner.motion.front,Vector3.ONE*-1.000001,Vector3.ONE*1.000001)
	for key: String in MOTION_BOOL: w.boolean(owner.motion.get(key))
	w.number(owner.motion.last_climb_time,-100000,float(p.tick)/60+1)
	w.number(owner.motion.fall_speed,-128,128)
	if owner.team == 2 and owner.health > 0: w.fail("spectator owner health")
	if owner.cooking and (owner.cook_started_tick < 0 or owner.grenades == 0 or owner.tool != 3): w.fail("owner cook relationship")
	if owner.reloading and (owner.tool != 2 or owner.reload_deadline_tick < owner.reload_started_tick): w.fail("owner reload relationship")

static func _read_owner(r: Reader, p: Dictionary) -> STATE:
	var owner := STATE.new(r.integer(4),"Pending",p.epoch,p.profile,1)
	owner.spawn_generation = r.integer(4)
	owner.connected = r.boolean()
	owner.player_name = r.text()
	owner.last_tick = p.tick
	for key: String in OWNER_U8: owner.set(key,r.integer(1))
	owner.pending_weapon = r.integer(1)
	if owner.pending_weapon == 255: owner.pending_weapon = -1
	owner.reserve = r.integer(2)
	for key: String in OWNER_U32: owner.set(key,r.integer(4))
	for key: String in OWNER_I64: owner.set(key,r.integer(8))
	for key: String in OWNER_BOOL: owner.set(key,r.boolean())
	for key: String in OWNER_UNIT: owner.set(key,r.number())
	owner.yaw = r.number()
	owner.pitch = r.number()
	owner.input_move = Vector2(r.number(false),r.number(false))
	for key: String in OWNER_DEADLINES: owner.set(key,r.number())
	owner.walk_distance = r.number()
	owner.motion.feet_position = r.vector()
	owner.motion.native_velocity = r.vector()
	owner.motion.eye_position = r.vector()
	owner.motion.front = r.vector()
	for key: String in MOTION_BOOL: owner.motion.set(key,r.boolean())
	owner.motion.last_climb_time = r.number()
	owner.motion.fall_speed = r.number()
	return owner

static func _write_actor(actor: Dictionary, size: Vector3i, w: Writer) -> void:
	w.integer(actor.id,4,1)
	w.integer(actor.spawn_generation,4,1)
	w.text(actor.name)
	w.integer(actor.team,1,0,2)
	w.integer(actor.flags,1,0,255)
	if not w.error.is_empty(): return
	for pair: Array in [["alive",1],["crouch",2],["sprinting",4],["wading",8],["grounded",16],["connected",32],["reloading",64],["cooking",128]]:
		if typeof(actor[pair[0]]) != TYPE_BOOL or actor[pair[0]] != ((int(actor.flags)&int(pair[1])) != 0): w.fail("public actor boolean flags mismatch")
	if not w.error.is_empty(): return
	if actor.alive and actor.team == 2: w.fail("alive spectator")
	var bound := _bounds(size)
	w.vector(actor.feet,bound[0],bound[1])
	w.vector(actor.native_velocity,Vector3.ONE*-128,Vector3.ONE*128)
	w.number(actor.yaw,-PI-0.000001,PI+0.000001)
	w.number(actor.pitch,-PI*0.5-0.000001,PI*0.5+0.000001)
	for key: String in ["tool","weapon","displayed_tool","displayed_weapon"]: w.integer(actor[key],1,0,3 if key in ["tool","displayed_tool"] else 2)
	for key: String in ["tool_raise","sprint_state","aim_down_state"]: w.number(actor[key],0,1)
	for key: String in ["kills","deaths","score"]: w.integer(actor[key],4)

static func _read_actor(r: Reader) -> Dictionary:
	var actor := {"id":r.integer(4),"spawn_generation":r.integer(4),"name":r.text(),"team":r.integer(1),"flags":r.integer(1)}
	for pair: Array in [["alive",1],["crouch",2],["sprinting",4],["wading",8],["grounded",16],["connected",32],["reloading",64],["cooking",128]]: actor[pair[0]] = (actor.flags&pair[1]) != 0
	actor.feet = r.vector()
	actor.native_velocity = r.vector()
	actor.yaw = r.number()
	actor.pitch = r.number()
	for key: String in ["tool","weapon","displayed_tool","displayed_weapon"]: actor[key] = r.integer(1)
	for key: String in ["tool_raise","sprint_state","aim_down_state"]: actor[key] = r.number()
	for key: String in ["kills","deaths","score"]: actor[key] = r.integer(4)
	return actor

static func _write_grenade(projectile: Dictionary, p: Dictionary, w: Writer) -> void:
	for key: String in ["id","owner_id","owner_generation","action_sequence"]: w.integer(projectile[key],4,0 if key == "action_sequence" else 1)
	w.integer(projectile.team,1,0,2)
	var bound := _bounds(p.dimensions,1024)
	w.vector(projectile.position,bound[0],bound[1])
	w.vector(projectile.velocity,Vector3.ONE*-4096,Vector3.ONE*4096)
	if typeof(projectile.orientation) != TYPE_QUATERNION or not projectile.orientation.is_finite(): w.fail("grenade orientation type/finite"); return
	if absf(projectile.orientation.length_squared()-1.0) > 0.001: w.fail("grenade quaternion not normalized")
	for value: float in [projectile.orientation.x,projectile.orientation.y,projectile.orientation.z,projectile.orientation.w]: w.number(value,-1.000001,1.000001,false)
	w.integer(projectile.created_tick,4,0,mini(U32_MAX,p.tick+1))
	if not w.error.is_empty(): return
	w.integer(projectile.last_tick,4,projectile.created_tick,mini(U32_MAX,p.tick+1))
	w.number(projectile.fuse_deadline_tick,float(projectile.created_tick),float(projectile.created_tick)+180.000001)
	w.boolean(projectile.finished)
	if projectile.finished: w.fail("finished grenade in live snapshot")

static func _read_grenade(r: Reader) -> Dictionary:
	var result := {"id":r.integer(4),"owner_id":r.integer(4),"owner_generation":r.integer(4),"action_sequence":r.integer(4),"team":r.integer(1),"position":r.vector(),"velocity":r.vector()}
	result.orientation = Quaternion(r.number(false),r.number(false),r.number(false),r.number(false))
	result.created_tick = r.integer(4)
	result.last_tick = r.integer(4)
	result.fuse_deadline_tick = r.number()
	result.finished = r.boolean()
	return result

static func _write_objectives(o: Variant, p: Dictionary, actors: Dictionary, w: Writer) -> void:
	if not _keys(o,OBJECTIVE_KEYS,w): return
	if typeof(o.epoch) != TYPE_INT or typeof(o.mode) != TYPE_STRING or o.epoch != p.epoch or o.mode != p.mode: w.fail("objective epoch/mode mismatch"); return
	w.integer(o.capture_limit,2,1,65535)
	if typeof(o.winning_team) != TYPE_INT or o.winning_team not in [-1,0,1]: w.fail("winner enum"); return
	w.integer(255 if o.winning_team == -1 else o.winning_team,1,0,255)
	if not _array(o.scores,2,w,2) or not _array(o.bases,2,w,2) or not _array(o.flags,2,w,2) or not _array(o.territories,MAX_TERRITORIES,w): return
	for score: Variant in o.scores: w.integer(score,4)
	var bound := _bounds(p.dimensions)
	for base: Variant in o.bases: w.vector(base,bound[0],bound[1])
	for team: int in range(2):
		var flag: Variant = o.flags[team]
		if not _keys(flag,["team","position","carrier","at_base"],w): return
		if typeof(flag.team) != TYPE_INT or flag.team != team: w.fail("flag team order"); return
		w.integer(flag.team,1,0,1)
		w.vector(flag.position,bound[0],bound[1])
		if typeof(flag.carrier) != TYPE_INT or (flag.carrier != -1 and (flag.carrier <= 0 or flag.carrier > U32_MAX)): w.fail("flag carrier ID"); return
		w.integer(0 if flag.carrier == -1 else flag.carrier,4)
		w.boolean(flag.at_base)
		if not w.error.is_empty(): return
		if flag.at_base and (flag.carrier != -1 or flag.position != o.bases[team]): w.fail("at-base flag relationship")
		if flag.carrier != -1 and (not actors.has(flag.carrier) or not actors[flag.carrier].alive or not actors[flag.carrier].connected or actors[flag.carrier].team == team): w.fail("flag carrier actor relationship")
	w.integer(o.territories.size(),1,0,MAX_TERRITORIES)
	for territory: Variant in o.territories:
		if not _keys(territory,["position","owner","capturing_team","progress","contested"],w): return
		w.vector(territory.position,bound[0],bound[1])
		w.integer(territory.owner,1,0,2)
		if typeof(territory.capturing_team) != TYPE_INT or territory.capturing_team not in [-1,0,1]: w.fail("capturing team enum"); return
		w.integer(255 if territory.capturing_team == -1 else territory.capturing_team,1,0,255)
		w.number(territory.progress,0,1)
		w.boolean(territory.contested)

static func _read_objectives(r: Reader, p: Dictionary) -> Dictionary:
	var o := {"epoch":p.epoch,"mode":p.mode,"capture_limit":r.integer(2),"winning_team":r.integer(1),"scores":[r.integer(4),r.integer(4)],"bases":[r.vector(),r.vector()],"flags":[],"territories":[]}
	if o.winning_team == 255: o.winning_team = -1
	for i: int in range(2):
		var flag := {"team":r.integer(1),"position":r.vector(),"carrier":r.integer(4),"at_base":r.boolean()}
		if flag.carrier == 0: flag.carrier = -1
		o.flags.append(flag)
	var count := r.count(MAX_TERRITORIES,23)
	for i: int in range(count):
		if not r.error.is_empty(): break
		var territory := {"position":r.vector(),"owner":r.integer(1),"capturing_team":r.integer(1),"progress":r.number(),"contested":r.boolean()}
		if territory.capturing_team == 255: territory.capturing_team = -1
		o.territories.append(territory)
	return o
