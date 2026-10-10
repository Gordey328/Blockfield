class_name EventsCodec
extends RefCounted
## Explicit GAME_EVENTS body. No Variant serialization or simulation dependency.
const VERSION := 1
const MAX_BODY := 32744
const MAX_EVENTS := 64
const U32_MAX := 0xffffffff
const MAX_ID_BYTES := 96
const COMMON := ["type","epoch","tick","owner_id","spawn_generation","action_sequence","match_sequence","event_id"]
const PAYLOAD := ["epoch","first_sequence","last_sequence","events"]
const CAUSES := ["weapon","melee","grenade","fall","team_change"]
const PARTS := ["head","torso","arms","legs","melee"]
const PROFILES := ["0.75","0.76"]
const MODES := ["sandbox","ctf","tc"]
const REASONS := ["line has no support","invalid line start","invalid placement"]
const PRIVATE_TYPES := ["hurt","hit_confirmed","class_pending","dry_fire","build_error","blocks_used","block_recovered","restock"]
const OBJECTIVE_TYPES := ["intel_drop","intel_pickup","intel_capture","intel_return","territory_capture","round_won"]
const GRENADE_TYPES := ["grenade_exploded","grenade_water","grenade_bounced"]
const MAX_SOURCE_EVENTS := 2048

class SharedEvents extends RefCounted:
	# Trusted native capture. Only validated record bytes and routing metadata
	# survive; mutable authority dictionaries are never retained.
	var _epoch := 0
	var _records: Array[Dictionary] = []
	func for_owner(owner_id: int) -> Dictionary:
		if _epoch <= 0 or owner_id <= 0 or owner_id > U32_MAX: return EventsCodec._failure("invalid prepared event owner/context")
		var selected: Array[Dictionary] = []
		for record: Dictionary in _records:
			if record.scope == "public" or (record.scope == "owner" and record.owner == owner_id): selected.append(record)
		var bodies: Array[Dictionary] = []
		for offset in range(0,selected.size(),MAX_EVENTS):
			var count := mini(MAX_EVENTS,selected.size()-offset)
			var w := Writer.new()
			w.integer(VERSION,1); w.integer(_epoch,4,1)
			w.integer(selected[offset].sequence,4); w.integer(selected[offset+count-1].sequence,4)
			w.integer(count,1,1,MAX_EVENTS)
			var tick := 0
			for index in range(offset,offset+count):
				var record: Dictionary = selected[index]
				if w.room(record.bytes.size()): w.stream.put_data(record.bytes)
				tick = maxi(tick,record.tick)
			if not w.error.is_empty(): return EventsCodec._failure(w.error)
			bodies.append({"bytes":w.stream.data_array,"epoch":_epoch,"tick":tick,"sequence":selected[offset+count-1].sequence})
		return {"ok":true,"error":"","bodies":bodies}

static func prepare_shared(epoch: int, events: Array[Dictionary]) -> Dictionary:
	if epoch <= 0 or epoch > U32_MAX or events.size() > MAX_SOURCE_EVENTS: return _failure("prepared event context/count")
	var shared := SharedEvents.new()
	shared._epoch = epoch
	var previous := 0
	var seen := {}
	for offset in range(0,events.size(),MAX_EVENTS):
		var batch: Array[Dictionary] = []
		batch.assign(events.slice(offset,mini(offset+MAX_EVENTS,events.size())))
		var converted := from_events(epoch,batch)
		if not converted.ok: return converted
		var bytes: PackedByteArray = converted.bytes
		var position := 14
		for event: Dictionary in converted.payload.events:
			if event.match_sequence <= previous or seen.has(event.event_id): return _failure("duplicate/unordered prepared event identity")
			previous = event.match_sequence
			seen[event.event_id] = true
			var length: int = (int(bytes[position+1])<<8)|int(bytes[position+2])
			var record := {"owner":event.owner_id,"sequence":event.match_sequence,"tick":event.tick,"scope":visibility(event.type),"bytes":bytes.slice(position,position+3+length)}
			record.make_read_only()
			shared._records.append(record)
			position += 3+length
	shared._records.make_read_only()
	return {"ok":true,"error":"","events":shared}
# Order is the v1 type enum. Field descriptors are compile-time schemas only.
const SCHEMAS := {
	"spawn":[["feet","point"],["team","team"],["weapon","weapon"]],
	"actor_joined":[], "actor_disconnected":[], "actor_reconnected":[], "actor_removed":[],
	"team_changed":[["team","team"]], "class_pending":[["weapon","weapon"]],
	"tool_selected":[["tool","tool"]], "tool_swapped":[["tool","tool"],["weapon","weapon"]],
	"reload_started":[["weapon","weapon"]], "reload_cancelled":[], "shell_loaded":[], "reload_completed":[], "dry_fire":[],
	"restock":[], "blocks_used":[["count","blocks"]], "block_recovered":[], "grenade_pin":[],
	"grenade_thrown":[["position","point"],["native_velocity","velocity"],["fuse","fuse"],["cook_time","cook"],["drop","bool"],["team","team"],["cook_action_sequence","u32"],["automatic","bool"]],
	"hurt":[["amount","damage"],["attacker_id","u32"],["cause","cause"],["action_id","reference"]],
	"death":[["attacker_id","u32"],["cause","cause"],["action_id","reference"]],
	"shot":[["weapon","weapon"],["profile","profile"],["origin","point"],["directions","rays"]],
	"jump":[], "land":[["hurt","bool"]], "footstep":[["wade","bool"]], "spade_bash":[], "spade_dig":[],
	"kill_credit":[["victim_id","id"],["victim_generation","id"],["cause","cause"],["source_event_id","reference"]],
	"hit_confirmed":[["victim_id","id"],["part","part"],["damage","damage"],["position","point"],["friendly","bool"],["source_event_id","reference"],["pellet","pellet"]],
	"block_hit":[["cell","cell"],["position","point"],["normal","normal"],["source_event_id","reference"],["pellet","pellet"]],
	"tracer":[["origin","point"],["position","point"],["weapon","weapon"],["source_event_id","reference"],["pellet","pellet"]],
	"spade_miss":[["source_event_id","reference"]],
	"spade_block_hit":[["cell","cell"],["position","point"],["normal","normal"],["dig","bool"],["source_event_id","reference"]],
	"build_error":[["reason","reason"]], "blocks_built":[["cells","cells"],["line","bool"],["color","color"]],
	"grenade_exploded":[["grenade_id","id"],["position","point"]],
	"grenade_water":[["grenade_id","id"],["position","point"]],
	"grenade_bounced":[["grenade_id","id"],["position","point"]],
	"intel_drop":[["team","team"],["flag_team","playing_team"],["position","point"]],
	"intel_pickup":[["team","playing_team"],["flag_team","playing_team"]],
	"intel_capture":[["team","playing_team"],["flag_team","playing_team"],["score","u32"]],
	"intel_return":[["team","playing_team"],["flag_team","playing_team"]],
	"territory_capture":[["team","playing_team"],["territory","territory"],["position","point"]],
	"round_won":[["team","team"],["winning_team","playing_team"],["mode","mode"]],
	"events_resync_required":[["resync_required","true"]]
}

class Writer extends RefCounted:
	var stream := StreamPeerBuffer.new()
	var error := ""
	func _init() -> void: stream.big_endian = true
	func fail(message: String) -> void:
		if error.is_empty(): error = message
	func room(count: int) -> bool:
		if not error.is_empty(): return false
		if stream.get_size()+count > MAX_BODY: fail("events body exceeds limit");return false
		return true
	func integer(value: Variant,width: int,low: int = 0,high: int = U32_MAX) -> void:
		if typeof(value) != TYPE_INT or value < low or value > high: fail("integer type/range");return
		if not room(width): return
		match width:
			1: stream.put_u8(value)
			2: stream.put_u16(value)
			4: stream.put_u32(value)
	func number(value: Variant,low: float,high: float) -> void:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value < low or value > high: fail("number type/range/finite");return
		var rounded := Vector3(value,0,0).x
		if not is_finite(rounded) or rounded < low or rounded > high: fail("f32 number exceeds range");return
		if room(4): stream.put_float(rounded)
	func text(value: Variant,allow_empty: bool = false) -> void:
		if typeof(value) != TYPE_STRING or not Text.valid_text(value,allow_empty): fail("ID UTF8/length/control");return
		var bytes: PackedByteArray = value.to_utf8_buffer()
		integer(bytes.size(),1,0 if allow_empty else 1,MAX_ID_BYTES)
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
		if count < 0 or stream.get_available_bytes() < count: fail("truncated events body");return false
		return true
	func integer(width: int) -> int:
		if not has(width): return 0
		match width:
			1: return stream.get_u8()
			2: return stream.get_u16()
			4: return stream.get_u32()
		return 0
	func number() -> float:
		if not has(4): return 0
		var value := stream.get_float()
		if not is_finite(value): fail("nonfinite float")
		return value
	func text() -> String:
		var length := integer(1)
		if length > MAX_ID_BYTES: fail("ID byte length");return ""
		if not has(length): return ""
		var bytes: PackedByteArray = stream.get_data(length)[1]
		if not Text.valid_utf8(bytes): fail("invalid UTF8/control");return ""
		var value := bytes.get_string_from_utf8()
		if value.to_utf8_buffer() != bytes or not Text.valid_text(value,true): fail("invalid UTF8/control")
		return value

class Text extends RefCounted:
	static func valid_utf8(bytes: PackedByteArray) -> bool:
		var offset := 0
		while offset < bytes.size():
			var first: int = bytes[offset]
			if first < 0x80:
				if first < 32 or first == 127: return false
				offset += 1
				continue
			var count := 0
			var low := 0x80
			var high := 0xbf
			if first >= 0xc2 and first <= 0xdf: count=2
			elif first >= 0xe0 and first <= 0xef:
				count=3
				if first == 0xe0: low=0xa0
				if first == 0xed: high=0x9f
			elif first >= 0xf0 and first <= 0xf4:
				count=4
				if first == 0xf0: low=0x90
				if first == 0xf4: high=0x8f
			else: return false
			if offset+count > bytes.size() or bytes[offset+1] < low or bytes[offset+1] > high: return false
			if first == 0xc2 and bytes[offset+1] <= 0x9f: return false
			for i in range(2,count):
				if bytes[offset+i] < 0x80 or bytes[offset+i] > 0xbf: return false
			offset += count
		return true

	static func valid_text(value: String,allow_empty: bool = false) -> bool:
		if (value.is_empty() and not allow_empty) or value.length() > MAX_ID_BYTES or value.to_utf8_buffer().size() > MAX_ID_BYTES: return false
		for i: int in range(value.length()):
			var code := value.unicode_at(i)
			if code < 32 or (code >= 127 and code < 160): return false
		return true

static func valid_text(value: String,allow_empty: bool = false) -> bool:
	return Text.valid_text(value,allow_empty)

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"bytes":PackedByteArray(),"payload":{}}

static func _keys(value: Variant,allowed: Array,w: Writer) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != allowed.size(): w.fail("schema keys/type");return false
	for key: Variant in value:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or key not in allowed: w.fail("unknown field");return false
	return true

static func _decimal(value: String,positive: bool = true) -> bool:
	if value.is_empty() or value.length() > 10 or not value.is_valid_int(): return false
	var number := value.to_int()
	return number >= (1 if positive else 0) and number <= U32_MAX and str(number) == value

static func _id_parts(value: String,epoch: int) -> PackedStringArray:
	var parts := value.split(":",true)
	if parts.size() < 3 or not _decimal(parts[0]) or parts[0].to_int() != epoch: return PackedStringArray()
	if parts[1] in ["o","m"]:
		if parts.size() == 3 and _decimal(parts[2]): return parts
	elif parts[1] == "g":
		if parts.size() == 4 and _decimal(parts[2]) and _decimal(parts[3]): return parts
	elif parts.size() == 4 and _decimal(parts[1]) and _decimal(parts[2]) and _decimal(parts[3]): return parts
	return PackedStringArray()

static func _reference(value: Variant,epoch: int) -> bool:
	if typeof(value) != TYPE_STRING or not valid_text(value,true): return false
	# Empty is environmental/no linked action. Trusted external IDs are colon-free.
	return ":" not in value or not _id_parts(value,epoch).is_empty()

static func _identity(e: Dictionary,w: Writer) -> void:
	if typeof(e.event_id) != TYPE_STRING or not valid_text(e.event_id): w.fail("event ID type/text");return
	var parts := _id_parts(e.event_id,e.epoch)
	if parts.is_empty(): w.fail("noncanonical/ambiguous event ID");return
	if e.type == "events_resync_required":
		if e.owner_id != 0 or e.spawn_generation != 0 or e.action_sequence != 0 or parts.size() != 3 or parts[1] != "m" or parts[2].to_int() != e.match_sequence: w.fail("system identity mismatch")
	elif e.type in OBJECTIVE_TYPES:
		if parts.size() != 3 or parts[1] != "o" or e.action_sequence != 0 or (e.owner_id == 0) != (e.spawn_generation == 0): w.fail("objective identity mismatch")
		if e.type in ["intel_pickup","intel_capture","intel_return"] and e.owner_id == 0: w.fail("objective needs actor")
		if e.type == "territory_capture" and e.owner_id != 0: w.fail("territory has no owner actor")
	elif e.type in GRENADE_TYPES:
		if e.owner_id == 0 or e.spawn_generation == 0 or parts.size() != 4 or parts[1] != "g" or parts[2].to_int() != e.grenade_id: w.fail("grenade identity mismatch")
	else:
		if e.owner_id == 0 or e.spawn_generation == 0 or parts.size() != 4 or not _decimal(parts[1]) or parts[1].to_int() != e.owner_id or parts[2].to_int() != e.spawn_generation: w.fail("actor identity mismatch")

static func visibility(event_type: String) -> String:
	if not SCHEMAS.has(event_type): return "invalid"
	return "owner" if event_type in PRIVATE_TYPES else "public"

static func _enum(name: String) -> Array:
	match name:
		"cause": return CAUSES
		"part": return PARTS
		"profile": return PROFILES
		"mode": return MODES
		"reason": return REASONS
	return []

static func _write_value(value: Variant,kind: String,w: Writer,e: Dictionary) -> void:
	var enumeration := _enum(kind)
	if not enumeration.is_empty():
		if typeof(value) != TYPE_STRING or value not in enumeration: w.fail("unknown enum " + kind);return
		w.integer(enumeration.find(value),1,0,enumeration.size()-1)
		return
	match kind:
		"u32": w.integer(value,4)
		"id": w.integer(value,4,1)
		"team": w.integer(value,1,0,2)
		"playing_team": w.integer(value,1,0,1)
		"tool": w.integer(value,1,0,3)
		"weapon": w.integer(value,1,0,2)
		"territory": w.integer(value,1,0,15)
		"pellet": w.integer(value,1,0,7)
		"blocks": w.integer(value,1,1,50)
		"damage": w.integer(value,1,1,100)
		"color": w.integer(value,4,0x01000000,0x01ffffff)
		"bool","true":
			if typeof(value) != TYPE_BOOL or (kind == "true" and not value): w.fail("boolean value");return
			w.integer(1 if value else 0,1,0,1)
		"fuse": w.number(value,0,3)
		"cook": w.number(value,0,float(U32_MAX)/60)
		"point","velocity","ray":
			if typeof(value) != TYPE_VECTOR3 or not value.is_finite(): w.fail("vector type/finite");return
			if kind == "ray" and absf(value.length_squared()-1) > .001: w.fail("direction not normalized");return
			for axis in range(3): w.number(value[axis],-4096,4096)
		"cell","normal":
			if typeof(value) != TYPE_VECTOR3I: w.fail("cell/normal type");return
			if kind == "normal":
				if absi(value.x)+absi(value.y)+absi(value.z) > 1: w.fail("nonaxis normal");return
				for axis in range(3): w.integer(value[axis]+1,1,0,2)
			else:
				w.integer(value.x,2,0,511);w.integer(value.y,1,0,63);w.integer(value.z,2,0,511)
		"reference":
			if not _reference(value,e.epoch): w.fail("linked ID canonical/epoch");return
			w.text(value,true)
		"rays","cells":
			var maximum := 8 if kind == "rays" else 50
			if typeof(value) != TYPE_ARRAY or value.is_empty() or value.size() > maximum: w.fail("array count/type");return
			if kind == "rays" and value.size() != (8 if e.weapon == 2 else 1): w.fail("profile pellet count");return
			w.integer(value.size(),1,1,maximum)
			var seen := {}
			for item: Variant in value:
				_write_value(item,"ray" if kind == "rays" else "cell",w,e)
				if not w.error.is_empty(): return
				if kind == "cells":
					if typeof(item) == TYPE_VECTOR3I and seen.has(item): w.fail("duplicate block cell")
					seen[item] = true
		_: w.fail("unknown descriptor")

static func _read_value(kind: String,r: Reader) -> Variant:
	var enumeration := _enum(kind)
	if not enumeration.is_empty():
		var index := r.integer(1)
		if index >= enumeration.size(): r.fail("unknown enum " + kind);return ""
		return enumeration[index]
	match kind:
		"u32","id","color": return r.integer(4)
		"team","playing_team","tool","weapon","territory","pellet","blocks","damage": return r.integer(1)
		"bool","true":
			var value := r.integer(1)
			if value > 1: r.fail("invalid boolean")
			return value == 1
		"fuse","cook": return r.number()
		"point","velocity","ray": return Vector3(r.number(),r.number(),r.number())
		"cell": return Vector3i(r.integer(2),r.integer(1),r.integer(2))
		"normal": return Vector3i(r.integer(1)-1,r.integer(1)-1,r.integer(1)-1)
		"reference": return r.text()
		"rays","cells":
			var count := r.integer(1)
			var maximum := 8 if kind == "rays" else 50
			if count < 1 or count > maximum: r.fail("array count limit");return []
			if not r.has(count*(12 if kind == "rays" else 5)): return []
			var result: Array = []
			for i in range(count): result.append(_read_value("ray" if kind == "rays" else "cell",r))
			return result
	return null

static func _write_event(e: Variant,epoch: int,w: Writer) -> void:
	if typeof(e) != TYPE_DICTIONARY or typeof(e.get("type")) != TYPE_STRING or not SCHEMAS.has(e.type): w.fail("unknown event type");return
	var fields: Array = COMMON.duplicate()
	for field: Array in SCHEMAS[e.type]: fields.append(field[0])
	if not _keys(e,fields,w): return
	if typeof(e.epoch) != TYPE_INT or e.epoch != epoch: w.fail("event epoch mismatch");return
	var record := Writer.new()
	for key: String in ["tick","owner_id","spawn_generation","action_sequence","match_sequence"]: record.integer(e[key],4,1 if key == "match_sequence" else 0)
	if not record.error.is_empty(): w.fail(record.error);return
	_identity(e,record)
	record.text(e.event_id)
	for field: Array in SCHEMAS[e.type]: _write_value(e[field[0]],field[1],record,e)
	if not record.error.is_empty(): w.fail(record.error);return
	if e.type == "spawn" and e.team == 2: record.fail("spectator cannot spawn")
	if e.type == "hit_confirmed" and ((e.part == "melee" and e.pellet != 0) or e.source_event_id.is_empty()): record.fail("hit attribution")
	if e.type in ["block_hit","tracer","spade_miss","spade_block_hit"] and e.source_event_id.is_empty(): record.fail("missing source action")
	if e.type in ["hit_confirmed","block_hit","tracer","spade_miss","spade_block_hit"]:
		var source := _id_parts(e.source_event_id,e.epoch)
		if source.size() != 4 or not _decimal(source[1]) or source[1].to_int() != e.owner_id or source[2].to_int() != e.spawn_generation: record.fail("source action owner/generation mismatch")
	if e.type == "grenade_thrown" and (absf(e.fuse-maxf(0,3-e.cook_time)) > .00001 or (e.drop and e.automatic)): record.fail("grenade release timing/flags")
	if e.type in ["intel_pickup","intel_capture"] and e.team == e.flag_team: record.fail("enemy flag relationship")
	if e.type == "intel_return" and e.team != e.flag_team: record.fail("own flag relationship")
	if e.type == "round_won" and e.owner_id != 0 and e.team != e.winning_team: record.fail("winning actor team mismatch")
	if not record.error.is_empty(): w.fail(record.error);return
	w.integer(SCHEMAS.keys().find(e.type)+1,1,1,SCHEMAS.size())
	w.integer(record.stream.get_size(),2,1,MAX_BODY)
	if w.room(record.stream.get_size()): w.stream.put_data(record.stream.data_array)

static func encode(payload: Dictionary) -> Dictionary:
	var w := Writer.new()
	if not _keys(payload,PAYLOAD,w): return _failure(w.error)
	w.integer(VERSION,1)
	w.integer(payload.epoch,4,1)
	w.integer(payload.first_sequence,4)
	w.integer(payload.last_sequence,4)
	if typeof(payload.events) != TYPE_ARRAY or payload.events.size() > MAX_EVENTS: return _failure("event count/type")
	w.integer(payload.events.size(),1,0,MAX_EVENTS)
	if not w.error.is_empty(): return _failure(w.error)
	var previous := 0
	var seen := {}
	for event: Variant in payload.events:
		_write_event(event,payload.epoch,w)
		if not w.error.is_empty(): return _failure(w.error)
		if event.match_sequence <= previous or seen.has(event.event_id): return _failure("duplicate/unordered event identity")
		previous = event.match_sequence
		seen[event.event_id] = true
	if payload.events.is_empty():
		if payload.first_sequence != 0 or payload.last_sequence != 0: return _failure("empty frame sequence bounds")
	elif payload.first_sequence != payload.events[0].match_sequence or payload.last_sequence != payload.events[-1].match_sequence: return _failure("frame sequence bounds mismatch")
	return {"ok":true,"error":"","bytes":w.stream.data_array}

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 14 or bytes.size() > MAX_BODY: return _failure("events body length")
	var r := Reader.new(bytes)
	if r.integer(1) != VERSION: return _failure("events version")
	var p := {"epoch":r.integer(4),"first_sequence":r.integer(4),"last_sequence":r.integer(4),"events":[]}
	var count := r.integer(1)
	# 3-byte descriptor + 21-byte common record + shortest canonical ID (5).
	if count > MAX_EVENTS or not r.has(count*29): return _failure("event count/minimum record length")
	for i in range(count):
		var type_index := r.integer(1)-1
		var length := r.integer(2)
		if type_index < 0 or type_index >= SCHEMAS.size() or length < 26 or not r.has(length): return _failure("event type/record length")
		var sub := Reader.new(r.stream.get_data(length)[1])
		var e := {"type":SCHEMAS.keys()[type_index],"epoch":p.epoch}
		for key: String in ["tick","owner_id","spawn_generation","action_sequence","match_sequence"]: e[key] = sub.integer(4)
		e.event_id = sub.text()
		for field: Array in SCHEMAS[e.type]: e[field[0]] = _read_value(field[1],sub)
		if not sub.error.is_empty() or sub.stream.get_available_bytes() != 0: return _failure("event record: " + sub.error if not sub.error.is_empty() else "event record trailing bytes")
		p.events.append(e)
	if not r.error.is_empty() or r.stream.get_available_bytes() != 0: return _failure("events trailing/truncated bytes")
	# Shared validation also verifies semantic relationships after f32 decoding.
	var validated := encode(p)
	if not validated.ok: return _failure(validated.error)
	_freeze(p)
	return {"ok":true,"error":"","payload":p}

static func from_events(epoch: int,events: Array[Dictionary]) -> Dictionary:
	if events.size() > MAX_EVENTS: return _failure("event count limit; split at runtime")
	var normalized: Array[Dictionary] = []
	for source: Dictionary in events:
		if typeof(source.get("type")) != TYPE_STRING or not SCHEMAS.has(source.type): return _failure("unsupported source event")
		var fields: Array = COMMON.duplicate()
		for field: Array in SCHEMAS[source.type]: fields.append(field[0])
		var allowed := fields.duplicate()
		if source.type in OBJECTIVE_TYPES: allowed.erase("action_sequence")
		elif source.type == "events_resync_required":
			allowed.erase("action_sequence")
			if source.has("event_sequence"): allowed.append("event_sequence")
		elif source.type not in GRENADE_TYPES: allowed.append("actor_event_sequence")
		if source.type == "shot": allowed.append("recoil_direction")
		if source.type == "hit_confirmed" and source.get("part") == "melee": allowed.erase("pellet")
		var validation := Writer.new()
		if not _keys(source,allowed,validation): return _failure("source " + validation.error)
		var event := {}
		for field: String in fields:
			if source.has(field): event[field] = source[field]
			elif field in ["action_sequence","pellet"]: event[field] = 0
		if source.has("actor_event_sequence"):
			var parts := _id_parts(str(source.get("event_id","")),epoch)
			if typeof(source.actor_event_sequence) != TYPE_INT or parts.size() != 4 or parts[3].to_int() != source.actor_event_sequence: return _failure("source actor ordinal mismatch")
		if source.type == "shot":
			_write_value(source.recoil_direction,"ray",validation,event)
			if not validation.error.is_empty(): return _failure("source recoil " + validation.error)
		if source.has("event_sequence") and (typeof(source.event_sequence) != TYPE_INT or source.event_sequence != source.get("match_sequence")): return _failure("source resync cursor mismatch")
		normalized.append(event)
	var payload := {"epoch":epoch,"first_sequence":normalized[0].get("match_sequence",0) if not normalized.is_empty() else 0,"last_sequence":normalized[-1].get("match_sequence",0) if not normalized.is_empty() else 0,"events":normalized}
	var encoded := encode(payload)
	if not encoded.ok: return _failure(encoded.error)
	# Copy only after explicit schemas have bounded and typed every child.
	payload = payload.duplicate(true)
	_freeze(payload)
	return {"ok":true,"error":"","payload":payload,"bytes":encoded.bytes}

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()
