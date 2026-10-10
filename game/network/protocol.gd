class_name BlockfieldProtocol
extends RefCounted
## Bounded, big-endian wire schema. No transport or multiplayer authority.
const SIMULATION_CODEC = preload("res://network/simulation_codec.gd")

const MAGIC: int = 0x42464e57 # BFNW
const VERSION: int = 1
const HEADER_SIZE: int = 24
const MAX_FRAME: int = 32768
const MAX_BULK_FRAME: int = 16384
const CHUNK_BYTES: int = MAX_BULK_FRAME - HEADER_SIZE - 14
const MAX_MAP_BYTES: int = 67108864
const MAX_INPUTS: int = 8
const MAX_ACTORS: int = 32
const MAX_CHANGES: int = 2048
const U32_MAX: int = 0xffffffff
const FLOAT_MAX: float = 3.4028234663852886e38
const PI_WIRE: float = 3.1415927410125732
const HALF_PI_WIRE: float = 1.5707963705062866
const INPUT_BUTTON_MASK: int = 0x7f # jump,crouch,sprint,sneak,primary,secondary,reload
const ACTOR_FLAG_MASK: int = 0xff # alive,crouch,sprint,wade,ground,connected,reload,cook

enum Kind { HELLO = 1, WELCOME, REJECT, INPUT_BATCH, CHAT, PING, PONG,
	MAP_BEGIN, MAP_CHUNK, MAP_END, MAP_DELTA, MAP_READY, SNAPSHOT, MATCH_STATE }

class Packet extends RefCounted:
	var kind: int = 0
	var epoch: int = 0
	var tick: int = 0
	var sequence: int = 0
	var payload: Dictionary = {}

class Result extends RefCounted:
	var ok: bool = false
	var error: String = ""
	var packet: Packet
	var bytes: PackedByteArray = PackedByteArray()

class Writer extends RefCounted:
	var stream: StreamPeerBuffer = StreamPeerBuffer.new()
	var error: String = ""
	func _init() -> void: stream.big_endian = true
	func fail(message: String) -> void:
		if error.is_empty(): error = message
	func integer(value: Variant, width: int, minimum: int = 0, maximum: int = U32_MAX) -> void:
		if typeof(value) != TYPE_INT or value < minimum or value > maximum:
			fail("integer out of range or wrong type"); return
		match width:
			1: stream.put_u8(value)
			2: stream.put_u16(value)
			4: stream.put_u32(value)
	func number(value: Variant, minimum: float = -FLOAT_MAX, maximum: float = FLOAT_MAX) -> float:
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < minimum or float(value) > maximum:
			fail("nonfinite, out of range or wrong numeric type"); return 0.0
		var offset: int = stream.get_position()
		stream.put_float(float(value))
		stream.seek(offset)
		var rounded: float = stream.get_float()
		if not is_finite(rounded) or rounded < minimum or rounded > maximum: fail("float32 rounds outside range")
		return rounded
	func raw(value: Variant, length: int) -> void:
		if typeof(value) != TYPE_PACKED_BYTE_ARRAY or value.size() != length:
			fail("wrong byte array length or type"); return
		stream.put_data(value)
	func token(value: Variant) -> void:
		if typeof(value) != TYPE_PACKED_BYTE_ARRAY or value.size() not in [0, 32]:
			fail("token must contain zero or 32 bytes"); return
		integer(value.size(), 1, 0, 32); stream.put_data(value)
	func text(value: Variant, limit: int, empty: bool = false) -> void:
		if typeof(value) != TYPE_STRING or value.length() > limit or (not empty and value.is_empty()):
			fail("invalid text type or length"); return
		var data: PackedByteArray = value.to_utf8_buffer()
		if data.size() > limit or not UTF8.valid(data):
			fail("invalid UTF-8, text control or byte length"); return
		integer(data.size(), 2, 0, limit); stream.put_data(data)
	func point(value: Variant) -> void:
		if typeof(value) != TYPE_VECTOR3: fail("expected Vector3"); return
		number(value.x); number(value.y); number(value.z)
	func dimensions(value: Variant) -> void:
		if typeof(value) != TYPE_VECTOR3I: fail("expected Vector3i dimensions"); return
		integer(value.x, 2, 1, 512); integer(value.y, 2, 1, 64); integer(value.z, 2, 1, 512)

class Reader extends RefCounted:
	var stream: StreamPeerBuffer = StreamPeerBuffer.new()
	var error: String = ""
	func _init(data: PackedByteArray) -> void:
		stream.big_endian = true; stream.data_array = data
	func fail(message: String) -> void:
		if error.is_empty(): error = message
	func has(count: int) -> bool:
		if not error.is_empty(): return false
		if count < 0 or count > stream.get_available_bytes(): fail("truncated payload"); return false
		return true
	func integer(width: int) -> int:
		if not has(width): return 0
		match width:
			1: return stream.get_u8()
			2: return stream.get_u16()
			4: return stream.get_u32()
		fail("invalid scalar width"); return 0
	func number() -> float:
		if not has(4): return 0.0
		var value: float = stream.get_float()
		if not is_finite(value): fail("nonfinite float")
		return value
	func raw(count: int) -> PackedByteArray:
		if not has(count): return PackedByteArray()
		return stream.get_data(count)[1]
	func token() -> PackedByteArray:
		var count: int = integer(1)
		if count not in [0, 32]: fail("invalid token length"); return PackedByteArray()
		return raw(count)
	func text(limit: int) -> String:
		var count: int = integer(2)
		if count > limit: fail("text exceeds byte limit"); return ""
		var data: PackedByteArray = raw(count)
		if not error.is_empty(): return ""
		if not UTF8.valid(data): fail("invalid UTF-8 or text control"); return ""
		return data.get_string_from_utf8()
	func point() -> Vector3: return Vector3(number(), number(), number())
	func dimensions() -> Vector3i: return Vector3i(integer(2), integer(2), integer(2))

static func make_packet(kind: int, payload: Dictionary, epoch: int = 0, tick: int = 0, sequence: int = 0) -> Packet:
	var packet: Packet = Packet.new()
	packet.kind = kind; packet.payload = payload
	packet.epoch = epoch; packet.tick = tick; packet.sequence = sequence
	return packet

static func _failure(message: String) -> Result:
	var result: Result = Result.new(); result.error = message
	return result

static func encode(packet: Packet) -> Result:
	if packet == null: return _failure("null packet")
	if packet.kind < Kind.HELLO or packet.kind > Kind.MATCH_STATE: return _failure("unsupported kind")
	for value: int in [packet.epoch, packet.tick, packet.sequence]:
		if value < 0 or value > U32_MAX: return _failure("header value out of range")
	var payload_writer: Writer = Writer.new()
	_write_payload(packet.kind, packet.payload, payload_writer)
	if not payload_writer.error.is_empty(): return _failure(payload_writer.error)
	if packet.kind == Kind.MATCH_STATE and (packet.epoch != packet.payload.epoch or packet.tick != packet.payload.tick or packet.sequence != packet.payload.owner_state.spawn_generation):
		return _failure("state header/body identity mismatch")
	var data: PackedByteArray = payload_writer.stream.data_array
	var limit: int = MAX_BULK_FRAME if packet.kind == Kind.MAP_CHUNK else MAX_FRAME
	if data.size() > limit - HEADER_SIZE: return _failure("frame exceeds limit")
	var writer: Writer = Writer.new()
	writer.integer(MAGIC, 4); writer.integer(VERSION, 2); writer.integer(packet.kind, 1)
	writer.integer(0, 1); writer.integer(data.size(), 4)
	writer.integer(packet.epoch, 4); writer.integer(packet.tick, 4); writer.integer(packet.sequence, 4)
	writer.stream.put_data(data)
	var result: Result = Result.new()
	result.ok = true; result.packet = packet; result.bytes = writer.stream.data_array
	return result

static func _header_u32(data: PackedByteArray, offset: int) -> int:
	return (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) | (int(data[offset + 2]) << 8) | int(data[offset + 3])

static func decode(data: PackedByteArray) -> Result:
	# Check the envelope before allocating a payload reader or any counted array.
	if data.size() < HEADER_SIZE: return _failure("truncated header")
	if data.size() > MAX_FRAME: return _failure("frame exceeds limit")
	if _header_u32(data, 0) != MAGIC: return _failure("wrong magic")
	if (int(data[4]) << 8 | int(data[5])) != VERSION: return _failure("unsupported version")
	var kind: int = data[6]
	if kind < Kind.HELLO or kind > Kind.MATCH_STATE: return _failure("unsupported kind")
	if data[7] != 0: return _failure("reserved flags must be zero")
	if kind == Kind.MAP_CHUNK and data.size() > MAX_BULK_FRAME: return _failure("bulk frame exceeds limit")
	if _header_u32(data, 8) != data.size() - HEADER_SIZE: return _failure("payload length mismatch")
	var reader: Reader = Reader.new(data.slice(HEADER_SIZE))
	var payload: Dictionary = _read_payload(kind, reader)
	if not reader.error.is_empty(): return _failure(reader.error)
	if reader.stream.get_available_bytes() != 0: return _failure("trailing payload bytes")
	# The same strict schema validates decoded scalars, enums and relationships.
	var validation: Writer = Writer.new()
	_write_payload(kind, payload, validation)
	if not validation.error.is_empty(): return _failure(validation.error)
	if kind == Kind.MATCH_STATE and (_header_u32(data,12) != payload.epoch or _header_u32(data,16) != payload.tick or _header_u32(data,20) != payload.owner_state.spawn_generation):
		return _failure("state header/body identity mismatch")
	var result: Result = Result.new()
	result.ok = true
	result.packet = make_packet(kind, payload, _header_u32(data, 12), _header_u32(data, 16), _header_u32(data, 20))
	return result

static func _keys(value: Variant, names: Array, writer: Writer) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != names.size():
		writer.fail("wrong payload fields or type"); return false
	for key: Variant in value:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not names.has(key): writer.fail("unknown payload field"); return false
	return true

static func _array(value: Variant, maximum: int, writer: Writer, minimum: int = 0) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() < minimum or value.size() > maximum:
		writer.fail("array count out of range or wrong type"); return false
	return true

static func _write_payload(kind: int, p: Dictionary, w: Writer) -> void:
	match kind:
		Kind.HELLO:
			if not _keys(p, ["role", "name", "build_hash", "rules_hash", "resume_token", "bulk_token"], w): return
			w.integer(p.role, 1, 0, 2); w.text(p.name, 64, p.role == 2)
			w.raw(p.build_hash, 32); w.raw(p.rules_hash, 32); w.token(p.resume_token); w.token(p.bulk_token)
			if typeof(p.bulk_token) == TYPE_PACKED_BYTE_ARRAY and ((p.role == 2 and p.bulk_token.size() != 32) or (p.role != 2 and p.bulk_token.size() != 0)): w.fail("bulk token/role mismatch")
		Kind.WELCOME:
			if not _keys(p, ["actor_id", "spawn_generation", "server_hz", "snapshot_hz", "profile", "resume_token", "bulk_token", "build_hash", "rules_hash"], w): return
			w.integer(p.actor_id, 4, 1); w.integer(p.spawn_generation, 4)
			w.integer(p.server_hz, 2, 1, 240); w.integer(p.snapshot_hz, 2, 1, 240); w.integer(p.profile, 1, 0, 1)
			if typeof(p.server_hz) == TYPE_INT and typeof(p.snapshot_hz) == TYPE_INT and p.snapshot_hz > p.server_hz: w.fail("snapshot rate exceeds simulation rate")
			for key: String in ["resume_token", "bulk_token", "build_hash", "rules_hash"]: w.raw(p[key], 32)
		Kind.REJECT:
			if not _keys(p, ["code", "message"], w): return
			w.integer(p.code, 2, 1, 65535); w.text(p.message, 256)
		Kind.INPUT_BATCH: _write_inputs(p, w)
		Kind.CHAT:
			if not _keys(p, ["channel", "sender_id", "message_id", "text"], w): return
			w.integer(p.channel, 1, 0, 1); w.integer(p.sender_id, 4); w.integer(p.message_id, 4); w.text(p.text, 512)
		Kind.PING, Kind.PONG:
			var names: Array = ["nonce", "client_time_ms"] if kind == Kind.PING else ["nonce", "client_time_ms", "server_time_ms"]
			if not _keys(p, names, w): return
			for key: String in names: w.integer(p[key], 4)
		Kind.MAP_BEGIN:
			if not _keys(p, ["snapshot_id", "dimensions", "compression", "compressed_size", "uncompressed_size", "chunk_count", "map_sequence", "hash"], w): return
			w.integer(p.snapshot_id, 4, 1); w.dimensions(p.dimensions); w.integer(p.compression, 1, 0, 1)
			w.integer(p.compressed_size, 4, 1, MAX_MAP_BYTES); w.integer(p.uncompressed_size, 4, 4, MAX_MAP_BYTES)
			w.integer(p.chunk_count, 4, 1, _chunk_count(MAX_MAP_BYTES)); w.integer(p.map_sequence, 4); w.raw(p.hash, 32)
			if not w.error.is_empty(): return
			if p.uncompressed_size != p.dimensions.x * p.dimensions.y * p.dimensions.z * 4: w.fail("map size/dimensions mismatch")
			if p.chunk_count != _chunk_count(p.compressed_size): w.fail("map chunk count mismatch")
			if p.compression == 0 and p.compressed_size != p.uncompressed_size: w.fail("raw map size mismatch")
		Kind.MAP_CHUNK:
			if not _keys(p, ["snapshot_id", "index", "total_size", "data"], w): return
			w.integer(p.snapshot_id, 4, 1); w.integer(p.index, 4, 0, _chunk_count(MAX_MAP_BYTES) - 1); w.integer(p.total_size, 4, 1, MAX_MAP_BYTES)
			if not w.error.is_empty(): return
			if p.index >= _chunk_count(p.total_size): w.fail("chunk index exceeds transfer"); return
			var expected: int = mini(CHUNK_BYTES, p.total_size - p.index * CHUNK_BYTES)
			w.integer(expected, 2, 1, CHUNK_BYTES); w.raw(p.data, expected)
		Kind.MAP_END, Kind.MAP_READY:
			if not _keys(p, ["snapshot_id", "map_sequence", "hash"], w): return
			w.integer(p.snapshot_id, 4, 1); w.integer(p.map_sequence, 4); w.raw(p.hash, 32)
		Kind.MAP_DELTA: _write_delta(p, w)
		Kind.SNAPSHOT: _write_snapshot(p, w)
		Kind.MATCH_STATE:
			var encoded: Dictionary = SIMULATION_CODEC.encode(p)
			if not encoded.ok: w.fail(encoded.error)
			else: w.stream.put_data(encoded.bytes)

static func _write_inputs(p: Dictionary, w: Writer) -> void:
	if not _keys(p, ["records"], w) or not _array(p.records, MAX_INPUTS, w, 1): return
	w.integer(p.records.size(), 1, 1, MAX_INPUTS)
	var previous_sequence: int = -1
	var previous_tick: int = -1
	for record: Variant in p.records:
		if not _keys(record, ["input_sequence", "input_tick", "buttons", "tool", "weapon", "move_x", "move_z", "yaw", "pitch"], w): return
		w.integer(record.input_sequence, 4, 1); w.integer(record.input_tick, 4)
		w.integer(record.buttons, 2, 0, INPUT_BUTTON_MASK)
		w.integer(record.tool, 1, 0, 255); w.integer(record.weapon, 1, 0, 255)
		if typeof(record.tool) == TYPE_INT and record.tool not in [0, 1, 2, 3, 255]: w.fail("invalid tool intent")
		if typeof(record.weapon) == TYPE_INT and record.weapon not in [0, 1, 2, 255]: w.fail("invalid weapon intent")
		var move_x: float = w.number(record.move_x, -1.0, 1.0)
		var move_z: float = w.number(record.move_z, -1.0, 1.0)
		w.number(record.yaw, -PI_WIRE, PI_WIRE); w.number(record.pitch, -HALF_PI_WIRE, HALF_PI_WIRE)
		if not w.error.is_empty(): return
		if move_x * move_x + move_z * move_z > 1.000001: w.fail("movement vector exceeds unit length")
		if previous_sequence >= 0 and (record.input_sequence != previous_sequence + 1 or record.input_tick != previous_tick + 1): w.fail("noncontiguous or duplicate input records")
		previous_sequence = record.input_sequence; previous_tick = record.input_tick

static func _write_delta(p: Dictionary, w: Writer) -> void:
	if not _keys(p, ["map_sequence", "transaction_id", "actor_id", "action_id", "dimensions", "fragment_index", "fragment_count", "total_changes", "changes"], w): return
	for key: String in ["map_sequence", "transaction_id"]: w.integer(p[key], 4, 1)
	for key: String in ["actor_id", "action_id"]: w.integer(p[key], 4)
	w.dimensions(p.dimensions)
	w.integer(p.fragment_index, 2, 0, 8191); w.integer(p.fragment_count, 2, 1, 8192)
	w.integer(p.total_changes, 4, 1, 16777216)
	if not _array(p.changes, MAX_CHANGES, w, 1) or not w.error.is_empty(): return
	var cell_count: int = p.dimensions.x * p.dimensions.y * p.dimensions.z
	if p.total_changes > cell_count or p.fragment_count != ceili(float(p.total_changes) / MAX_CHANGES) or p.fragment_index >= p.fragment_count:
		w.fail("delta fragment/count/dimensions mismatch"); return
	var expected: int = mini(MAX_CHANGES, p.total_changes - p.fragment_index * MAX_CHANGES)
	if p.changes.size() != expected: w.fail("delta fragment length mismatch"); return
	w.integer(expected, 2, 1, MAX_CHANGES)
	var seen: Dictionary[Vector3i, bool] = {}
	for change: Variant in p.changes:
		if not _keys(change, ["cell", "before", "after", "flags"], w): return
		if typeof(change.cell) != TYPE_VECTOR3I: w.fail("expected cell Vector3i"); return
		var cell: Vector3i = change.cell
		if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= p.dimensions.x or cell.y >= p.dimensions.y or cell.z >= p.dimensions.z or seen.has(cell):
			w.fail("duplicate or out of bounds cell"); return
		seen[cell] = true
		w.integer(cell.x, 2, 0, 511); w.integer(cell.y, 2, 0, 63); w.integer(cell.z, 2, 0, 511)
		for key: String in ["before", "after"]:
			w.integer(change[key], 4)
			if typeof(change[key]) == TYPE_INT and change[key] != 0 and (change[key] < 0x01000000 or change[key] > 0x01ffffff): w.fail("invalid packed block color")
		w.integer(change.flags, 1, 0, 1)

static func _write_snapshot(p: Dictionary, w: Writer) -> void:
	if not _keys(p, ["map_sequence", "event_sequence", "input_ack", "profile", "owner_id", "owner_state", "actors"], w): return
	for key: String in ["map_sequence", "event_sequence", "input_ack"]: w.integer(p[key], 4)
	w.integer(p.profile, 1, 0, 1); w.integer(p.owner_id, 4)
	if not _keys(p.owner_state, ["health", "magazine", "reserve", "grenades", "blocks", "fire_tick", "reload_tick", "cook_tick", "respawn_tick"], w): return
	w.integer(p.owner_state.health, 1, 0, 100); w.integer(p.owner_state.magazine, 2, 0, 30)
	w.integer(p.owner_state.reserve, 2, 0, 150); w.integer(p.owner_state.grenades, 1, 0, 3); w.integer(p.owner_state.blocks, 2, 0, 50)
	for key: String in ["fire_tick", "reload_tick", "cook_tick", "respawn_tick"]: w.integer(p.owner_state[key], 4)
	if not _array(p.actors, MAX_ACTORS, w): return
	w.integer(p.actors.size(), 1, 0, MAX_ACTORS)
	var seen: Dictionary[int, bool] = {}
	for actor: Variant in p.actors:
		if not _keys(actor, ["id", "spawn_generation", "team", "flags", "tool", "weapon", "name", "feet", "native_velocity", "yaw", "pitch"], w): return
		w.integer(actor.id, 4, 1); w.integer(actor.spawn_generation, 4, 1)
		w.integer(actor.team, 1, 0, 2); w.integer(actor.flags, 2, 0, ACTOR_FLAG_MASK)
		w.integer(actor.tool, 1, 0, 3); w.integer(actor.weapon, 1, 0, 2); w.text(actor.name, 64)
		w.point(actor.feet); w.point(actor.native_velocity)
		w.number(actor.yaw, -PI_WIRE, PI_WIRE); w.number(actor.pitch, -HALF_PI_WIRE, HALF_PI_WIRE)
		if not w.error.is_empty(): return
		if seen.has(actor.id): w.fail("duplicate actor id"); return
		if actor.team == 2 and (actor.flags & 1) != 0: w.fail("spectator cannot be alive actor"); return
		seen[actor.id] = true
	if not w.error.is_empty(): return
	if p.owner_id != 0 and not seen.has(p.owner_id): w.fail("owner missing from actor snapshot")

static func _read_payload(kind: int, r: Reader) -> Dictionary:
	match kind:
		Kind.HELLO: return {"role":r.integer(1), "name":r.text(64), "build_hash":r.raw(32), "rules_hash":r.raw(32), "resume_token":r.token(), "bulk_token":r.token()}
		Kind.WELCOME: return {"actor_id":r.integer(4), "spawn_generation":r.integer(4), "server_hz":r.integer(2), "snapshot_hz":r.integer(2), "profile":r.integer(1), "resume_token":r.raw(32), "bulk_token":r.raw(32), "build_hash":r.raw(32), "rules_hash":r.raw(32)}
		Kind.REJECT: return {"code":r.integer(2), "message":r.text(256)}
		Kind.INPUT_BATCH:
			var count: int = r.integer(1)
			if count < 1 or count > MAX_INPUTS: r.fail("input count exceeds limit"); return {}
			if not r.has(count * 28): return {}
			var records: Array[Dictionary] = []
			for index: int in range(count):
				records.append({"input_sequence":r.integer(4), "input_tick":r.integer(4), "buttons":r.integer(2), "tool":r.integer(1), "weapon":r.integer(1), "move_x":r.number(), "move_z":r.number(), "yaw":r.number(), "pitch":r.number()})
			return {"records":records}
		Kind.CHAT: return {"channel":r.integer(1), "sender_id":r.integer(4), "message_id":r.integer(4), "text":r.text(512)}
		Kind.PING: return {"nonce":r.integer(4), "client_time_ms":r.integer(4)}
		Kind.PONG: return {"nonce":r.integer(4), "client_time_ms":r.integer(4), "server_time_ms":r.integer(4)}
		Kind.MAP_BEGIN: return {"snapshot_id":r.integer(4), "dimensions":r.dimensions(), "compression":r.integer(1), "compressed_size":r.integer(4), "uncompressed_size":r.integer(4), "chunk_count":r.integer(4), "map_sequence":r.integer(4), "hash":r.raw(32)}
		Kind.MAP_CHUNK:
			var snapshot_id: int = r.integer(4)
			var index: int = r.integer(4)
			var total_size: int = r.integer(4)
			var count: int = r.integer(2)
			if count < 1 or count > CHUNK_BYTES: r.fail("bulk chunk byte count exceeds limit"); return {}
			if total_size < 1 or total_size > MAX_MAP_BYTES or index >= _chunk_count(total_size): r.fail("invalid bulk transfer metadata"); return {}
			if count != mini(CHUNK_BYTES, total_size - index * CHUNK_BYTES): r.fail("bulk chunk length mismatch"); return {}
			return {"snapshot_id":snapshot_id, "index":index, "total_size":total_size, "data":r.raw(count)}
		Kind.MAP_END, Kind.MAP_READY: return {"snapshot_id":r.integer(4), "map_sequence":r.integer(4), "hash":r.raw(32)}
		Kind.MAP_DELTA: return _read_delta(r)
		Kind.SNAPSHOT: return _read_snapshot(r)
		Kind.MATCH_STATE:
			var decoded: Dictionary = SIMULATION_CODEC.decode(r.raw(r.stream.get_available_bytes()))
			if not decoded.ok: r.fail(decoded.error); return {}
			return decoded.payload
	return {}

static func _read_delta(r: Reader) -> Dictionary:
	var p: Dictionary = {"map_sequence":r.integer(4), "transaction_id":r.integer(4), "actor_id":r.integer(4), "action_id":r.integer(4), "dimensions":r.dimensions(), "fragment_index":r.integer(2), "fragment_count":r.integer(2), "total_changes":r.integer(4)}
	var count: int = r.integer(2)
	if count < 1 or count > MAX_CHANGES: r.fail("delta count exceeds limit"); return {}
	var size: Vector3i = p.dimensions
	if size.x < 1 or size.x > 512 or size.y < 1 or size.y > 64 or size.z < 1 or size.z > 512: r.fail("invalid delta dimensions"); return {}
	if p.total_changes < 1 or p.total_changes > size.x * size.y * size.z or p.fragment_count != ceili(float(p.total_changes) / MAX_CHANGES) or p.fragment_index >= p.fragment_count:
		r.fail("delta fragment/count/dimensions mismatch"); return {}
	if count != mini(MAX_CHANGES, p.total_changes - p.fragment_index * MAX_CHANGES): r.fail("delta fragment length mismatch"); return {}
	if not r.has(count * 15): return {}
	var changes: Array[Dictionary] = []
	for index: int in range(count):
		changes.append({"cell":r.dimensions(), "before":r.integer(4), "after":r.integer(4), "flags":r.integer(1)})
	p["changes"] = changes
	return p

static func _read_snapshot(r: Reader) -> Dictionary:
	var p: Dictionary = {"map_sequence":r.integer(4), "event_sequence":r.integer(4), "input_ack":r.integer(4), "profile":r.integer(1), "owner_id":r.integer(4)}
	p["owner_state"] = {"health":r.integer(1), "magazine":r.integer(2), "reserve":r.integer(2), "grenades":r.integer(1), "blocks":r.integer(2), "fire_tick":r.integer(4), "reload_tick":r.integer(4), "cook_tick":r.integer(4), "respawn_tick":r.integer(4)}
	var count: int = r.integer(1)
	if count > MAX_ACTORS: r.fail("actor count exceeds limit"); return {}
	if not r.has(count * 47): return {}
	var actors: Array[Dictionary] = []
	for index: int in range(count):
		actors.append({"id":r.integer(4), "spawn_generation":r.integer(4), "team":r.integer(1), "flags":r.integer(2), "tool":r.integer(1), "weapon":r.integer(1), "name":r.text(64), "feet":r.point(), "native_velocity":r.point(), "yaw":r.number(), "pitch":r.number()})
	p["actors"] = actors
	return p

static func _chunk_count(size: int) -> int:
	return ceili(float(size) / CHUNK_BYTES)

static func valid_text_bytes(data: PackedByteArray) -> bool:
	return UTF8.valid(data)

class UTF8 extends RefCounted:
	static func valid(data: PackedByteArray) -> bool:
		# Reject malformed/overlong UTF-8 and surrogate code points before decoding,
		# so Godot's string conversion never emits errors or replacement characters.
		var index: int = 0
		while index < data.size():
			var first: int = data[index]
			if first < 0x80:
				if first < 0x20 or first == 0x7f: return false
				index += 1; continue
			var count: int = 0
			var lower: int = 0x80
			var upper: int = 0xbf
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
			if index + count > data.size() or data[index + 1] < lower or data[index + 1] > upper: return false
			if first == 0xc2 and data[index + 1] <= 0x9f: return false # Unicode C1 controls
			for extra: int in range(2, count):
				if data[index + extra] < 0x80 or data[index + extra] > 0xbf: return false
			index += count
		return true
