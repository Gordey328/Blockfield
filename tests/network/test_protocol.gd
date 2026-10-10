extends SceneTree
## Pure wire goldens and hostile frames; never starts main or writes preferences.
const PROTOCOL = preload("res://network/protocol.gd")

var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures += 1; push_error("PROTOCOL: " + message)

func _bytes(count: int, value: int = 0x5a) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray(); result.resize(count); result.fill(value)
	return result

func _input(sequence: int = 1, tick: int = 70) -> Dictionary:
	return {"input_sequence":sequence,"input_tick":tick,"buttons":0x51,"tool":255,"weapon":255,"move_x":0.5,"move_z":-0.5,"yaw":1.0,"pitch":-0.25}

func _actor(id: int = 7) -> Dictionary:
	return {"id":id,"spawn_generation":2,"team":1,"flags":0x31,"tool":2,"weapon":0,"name":"Солдат 🧱","feet":Vector3(16.5,4.0,48.5),"native_velocity":Vector3(-.125,.25,0),"yaw":1.0,"pitch":-.25}

func _snapshot() -> Dictionary:
	return {"map_sequence":19,"event_sequence":27,"input_ack":31,"profile":0,"owner_id":7,
		"owner_state":{"health":100,"magazine":8,"reserve":40,"grenades":3,"blocks":50,"fire_tick":70,"reload_tick":0,"cook_tick":0,"respawn_tick":0},"actors":[_actor()]}

func _delta() -> Dictionary:
	return {"map_sequence":20,"transaction_id":1,"actor_id":7,"action_id":42,"dimensions":Vector3i(512,64,512),"fragment_index":0,"fragment_count":1,"total_changes":2,"changes":[
		{"cell":Vector3i(0,0,0),"before":0x01020304,"after":0,"flags":1},
		{"cell":Vector3i(511,63,511),"before":0,"after":0x01ffffff,"flags":0}]}

func _fixtures() -> Array[Dictionary]:
	return [
		{"kind":PROTOCOL.Kind.HELLO,"payload":{"role":0,"name":"Gordey","build_hash":_bytes(32),"rules_hash":_bytes(32,0x61),"resume_token":_bytes(0),"bulk_token":_bytes(0)}},
		{"kind":PROTOCOL.Kind.WELCOME,"payload":{"actor_id":7,"spawn_generation":2,"server_hz":60,"snapshot_hz":20,"profile":1,"resume_token":_bytes(32,0x62),"bulk_token":_bytes(32,0x63),"build_hash":_bytes(32),"rules_hash":_bytes(32,0x61)}},
		{"kind":PROTOCOL.Kind.REJECT,"payload":{"code":3,"message":"Version mismatch"}},
		{"kind":PROTOCOL.Kind.INPUT_BATCH,"payload":{"records":[_input(),_input(2,71)]}},
		{"kind":PROTOCOL.Kind.CHAT,"payload":{"channel":1,"sender_id":7,"message_id":11,"text":"Привет 世界 🧱"}},
		{"kind":PROTOCOL.Kind.PING,"payload":{"nonce":0x12345678,"client_time_ms":0xffffffff}},
		{"kind":PROTOCOL.Kind.PONG,"payload":{"nonce":0x12345678,"client_time_ms":0xffffffff,"server_time_ms":0x01020304}},
		{"kind":PROTOCOL.Kind.MAP_BEGIN,"payload":{"snapshot_id":3,"dimensions":Vector3i(512,64,512),"compression":1,"compressed_size":PROTOCOL.CHUNK_BYTES+3,"uncompressed_size":67108864,"chunk_count":2,"map_sequence":19,"hash":_bytes(32)}},
		{"kind":PROTOCOL.Kind.MAP_CHUNK,"payload":{"snapshot_id":3,"index":1,"total_size":PROTOCOL.CHUNK_BYTES+3,"data":PackedByteArray([0,128,255])}},
		{"kind":PROTOCOL.Kind.MAP_END,"payload":{"snapshot_id":3,"map_sequence":19,"hash":_bytes(32)}},
		{"kind":PROTOCOL.Kind.MAP_DELTA,"payload":_delta()},
		{"kind":PROTOCOL.Kind.MAP_READY,"payload":{"snapshot_id":3,"map_sequence":19,"hash":_bytes(32)}},
		{"kind":PROTOCOL.Kind.SNAPSHOT,"payload":_snapshot()}
	]

func _run() -> void:
	_test_goldens_and_roundtrip()
	_test_envelope_and_truncation()
	_test_inputs()
	_test_text()
	_test_maps()
	_test_snapshots()
	_test_hostile_mutations()
	_test_preparing()
	print("PROTOCOL: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _test_preparing() -> void:
	var payload := {"actor_id":43,"spawn_generation":1,"profile":1}
	var packet := PROTOCOL.make_packet(PROTOCOL.Kind.MATCH_PREPARING,payload,0x01020304,70,1)
	var encoded := PROTOCOL.encode(packet)
	var golden := PackedByteArray([0x42,0x46,0x4e,0x57,0,1,17,0,0,0,0,9,1,2,3,4,0,0,0,70,0,0,0,1,0,0,0,43,0,0,0,1,1])
	check(encoded.ok and encoded.bytes == golden,"MATCH_PREPARING independent33-byte BE golden contains no capabilities")
	var decoded := PROTOCOL.decode(golden)
	check(decoded.ok and decoded.packet.payload == payload,"preparing roundtrip preserves exact metadata")
	for size in range(golden.size()): _reject_frame(golden.slice(0,size),"truncated preparing at%d" % size)
	for change in [{"actor_id":0},{"spawn_generation":0},{"spawn_generation":2},{"profile":2},{"profile":1.0},{"bulk_token":_bytes(32)}]:
		var changed: Dictionary = payload.duplicate(true)
		changed.merge(change,true)
		var rejected := PROTOCOL.encode(PROTOCOL.make_packet(PROTOCOL.Kind.MATCH_PREPARING,changed,1,0,1))
		check(not rejected.ok and rejected.bytes.is_empty(),"invalid preparing fields/types with a valid envelope")
	for offset in [12,20,28]:
		var changed := golden.duplicate(); _put_u32(changed,offset,0)
		_reject_frame(changed,"zero preparing epoch/generation")
	var wrong_sequence := golden.duplicate(); _put_u32(wrong_sequence,20,2)
	_reject_frame(wrong_sequence,"preparing envelope generation mismatch")
	var bad_profile := golden.duplicate(); bad_profile[32] = 2
	_reject_frame(bad_profile,"unknown preparing profile")
	packet.epoch = 0; check(not PROTOCOL.encode(packet).ok,"preparing epoch is positive")
	packet.epoch = 1; packet.sequence = 2; check(not PROTOCOL.encode(packet).ok,"preparing sequence matches generation1")

func _encode(kind: int, payload: Dictionary) -> PROTOCOL.Result:
	return PROTOCOL.encode(PROTOCOL.make_packet(kind,payload,0x01020304,0xa0b0c0d0,0xffffffff))

func _reject_encode(kind: int, payload: Dictionary, message: String) -> void:
	var result: PROTOCOL.Result = _encode(kind,payload)
	check(not result.ok and not result.error.is_empty() and result.bytes.is_empty(),message)

func _reject_frame(frame: PackedByteArray, message: String) -> void:
	var result: PROTOCOL.Result = PROTOCOL.decode(frame)
	check(not result.ok and not result.error.is_empty() and result.packet == null,message)

func _put_u32(data: PackedByteArray, offset: int, value: int) -> void:
	for index: int in range(4): data[offset+index] = (value >> (24-index*8)) & 255

func _with_length(data: PackedByteArray) -> PackedByteArray:
	_put_u32(data,8,data.size()-PROTOCOL.HEADER_SIZE)
	return data

func _test_goldens_and_roundtrip() -> void:
	var ping: PROTOCOL.Result = _encode(PROTOCOL.Kind.PING,{"nonce":0x12345678,"client_time_ms":0xffffffff})
	var golden: PackedByteArray = PackedByteArray([0x42,0x46,0x4e,0x57,0,1,6,0,0,0,0,8,1,2,3,4,0xa0,0xb0,0xc0,0xd0,255,255,255,255,0x12,0x34,0x56,0x78,255,255,255,255])
	check(ping.ok and ping.bytes == golden,"independent big-endian header/u32 golden")
	for fixture: Dictionary in _fixtures():
		var encoded: PROTOCOL.Result = _encode(fixture.kind,fixture.payload)
		check(encoded.ok,"encode kind %d"%fixture.kind)
		if not encoded.ok: continue
		var decoded: PROTOCOL.Result = PROTOCOL.decode(encoded.bytes)
		check(decoded.ok,"decode kind %d: %s"%[fixture.kind,decoded.error])
		if not decoded.ok: continue
		check(decoded.packet.kind==fixture.kind and decoded.packet.epoch==0x01020304 and decoded.packet.tick==0xa0b0c0d0 and decoded.packet.sequence==0xffffffff,"unsigned header roundtrip kind %d"%fixture.kind)
		var repeated: PROTOCOL.Result = PROTOCOL.encode(decoded.packet)
		check(repeated.ok and repeated.bytes==encoded.bytes,"canonical byte roundtrip kind %d"%fixture.kind)
	var input: PROTOCOL.Result = _encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[_input()]})
	check(input.bytes.slice(37,41)==PackedByteArray([0x3f,0,0,0]),"float32 move_x .5 independent endian golden")
	check(input.bytes.slice(41,45)==PackedByteArray([0xbf,0,0,0]),"float32 move_z -.5 independent endian golden")
	var hello: Dictionary = _fixtures()[0].payload.duplicate(true)
	hello.role=2; hello.name=""; hello.bulk_token=_bytes(32)
	check(_encode(PROTOCOL.Kind.HELLO,hello).ok,"bulk HELLO with opaque token and empty name")

func _test_envelope_and_truncation() -> void:
	for fixture: Dictionary in _fixtures():
		var encoded: PROTOCOL.Result = _encode(fixture.kind,fixture.payload)
		if not encoded.ok: continue
		for count: int in range(encoded.bytes.size()):
			_reject_frame(encoded.bytes.slice(0,count),"truncated kind %d at %d"%[fixture.kind,count])
	var frame: PackedByteArray = _encode(PROTOCOL.Kind.PING,{"nonce":1,"client_time_ms":2}).bytes
	var invalid: PackedByteArray = frame.duplicate(); invalid[0]=0; _reject_frame(invalid,"wrong magic")
	invalid=frame.duplicate(); invalid[5]=2; _reject_frame(invalid,"unknown protocol version")
	invalid=frame.duplicate(); invalid[6]=255; _reject_frame(invalid,"unknown family")
	invalid=frame.duplicate(); invalid[7]=1; _reject_frame(invalid,"reserved flag rejected")
	invalid=frame.duplicate(); _put_u32(invalid,8,0xffffffff); _reject_frame(invalid,"huge claimed length never allocates payload")
	invalid=frame.duplicate(); invalid.append(0); _reject_frame(invalid,"extra frame bytes")
	invalid=_with_length(invalid); _reject_frame(invalid,"trailing payload despite adjusted frame length")
	_reject_frame(_bytes(PROTOCOL.MAX_FRAME+1),"ordinary oversize frame")
	check(not PROTOCOL.encode(null).ok,"null packet rejected")
	var packet: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.PING,{"nonce":1,"client_time_ms":2},-1)
	check(not PROTOCOL.encode(packet).ok,"negative epoch")
	packet.epoch=PROTOCOL.U32_MAX+1; check(not PROTOCOL.encode(packet).ok,"overflow epoch")
	packet.epoch=0; packet.kind=99; check(not PROTOCOL.encode(packet).ok,"unsupported outbound kind")

func _test_inputs() -> void:
	var records: Array[Dictionary] = []
	for index: int in range(8): records.append(_input(index+1,index+70))
	check(_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":records}).ok,"eight bounded input records")
	records.append(_input(9,78)); _reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":records},"ninth input rejected")
	_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[]},"empty input batch")
	_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[_input(),_input()]},"duplicate input sequences/ticks")
	_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[_input(),_input(3,71)]},"sequence gap")
	_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[_input(),_input(2,70)]},"repeated input tick")
	for field: String in ["position","damage","player_id","velocity"]:
		var extra: Dictionary = _input(); extra[field]=1
		_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[extra]},"authoritative/extra input field rejected: "+field)
	for field: String in ["move_x","move_z","yaw","pitch"]:
		for value: float in [INF,-INF,NAN]:
			var record: Dictionary = _input(); record[field]=value
			_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[record]},"nonfinite "+field)
	var record: Dictionary = _input(); record.move_x=1.0; record.move_z=1.0
	_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[record]},"diagonal input cannot exceed normalized source speed")
	record=_input(); record.move_x=1.0; record.move_z=.001
	_reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[record]},"float32 rounding is validated before emitting unreadable movement boundary")
	for item: Dictionary in [{"key":"tool","value":4},{"key":"weapon","value":3},{"key":"buttons","value":128},{"key":"pitch","value":2.0},{"key":"yaw","value":4.0},{"key":"input_sequence","value":0},{"key":"move_x","value":true}]:
		record=_input(); record[item.key]=item.value; _reject_encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[record]},"invalid input "+item.key)
	var frame: PackedByteArray = _encode(PROTOCOL.Kind.INPUT_BATCH,{"records":[_input()]}).bytes
	var invalid: PackedByteArray = frame.duplicate(); invalid[24]=255; _reject_frame(invalid,"oversized input count before record allocation")
	for bits: int in [0x7f800000,0xff800000,0x7fc00000]:
		invalid=frame.duplicate(); _put_u32(invalid,37,bits); _reject_frame(invalid,"wire nonfinite float")
	invalid=frame.duplicate(); invalid[35]=4; _reject_frame(invalid,"wire invalid tool")
	invalid=frame.duplicate(); invalid[24]=2; _reject_frame(invalid,"claimed input count disagrees with available record bytes")

func _test_text() -> void:
	var base: Dictionary = {"channel":0,"sender_id":0,"message_id":3,"text":"Привет"}
	check(_encode(PROTOCOL.Kind.CHAT,base).ok,"client request uses sender0; identity binding remains service responsibility")
	for text: String in ["","bad\nline","del"+String.chr(127),"C1"+String.chr(0x85),"я".repeat(257),"x".repeat(513)]:
		var invalid: Dictionary=base.duplicate(); invalid.text=text; _reject_encode(PROTOCOL.Kind.CHAT,invalid,"empty/control/byte-oversize chat")
	var limit: Dictionary=base.duplicate(); limit.text="я".repeat(256)
	check(_encode(PROTOCOL.Kind.CHAT,limit).ok,"512 UTF8 bytes accepted exactly")
	for bytes: PackedByteArray in [PackedByteArray([0]),PackedByteArray([0xc2,0x85]),PackedByteArray([0xc0,0x80]),PackedByteArray([0xed,0xa0,0x80]),PackedByteArray([0xf4,0x90,0x80,0x80]),PackedByteArray([0x80]),PackedByteArray([0xe2,0x82]),PackedByteArray([0xe0,0x80,0x80]),PackedByteArray([0xf0,0x80,0x80,0x80]),PackedByteArray([0xf5,0x80,0x80,0x80])]:
		check(not PROTOCOL.valid_text_bytes(bytes),"malformed/overlong/surrogate/out-of-Unicode UTF8")
		var frame: PackedByteArray = _encode(PROTOCOL.Kind.CHAT,base).bytes.slice(0,33)
		frame.append((bytes.size()>>8)&255); frame.append(bytes.size()&255); frame.append_array(bytes)
		_reject_frame(_with_length(frame),"badUTF8 rejected without Godot conversion errors")
	var frame: PackedByteArray = _encode(PROTOCOL.Kind.CHAT,base).bytes
	frame[33]=255; frame[34]=255; _reject_frame(frame,"claimed UTF8 length rejected before allocation")
	var hello: Dictionary=_fixtures()[0].payload.duplicate(true); hello.name="я".repeat(33)
	_reject_encode(PROTOCOL.Kind.HELLO,hello,"username UTF8 byte cap")
	hello=_fixtures()[0].payload.duplicate(true); hello.resume_token=_bytes(31)
	_reject_encode(PROTOCOL.Kind.HELLO,hello,"resume token must be opaque fixed32")
	hello=_fixtures()[0].payload.duplicate(true); hello.bulk_token=_bytes(32)
	_reject_encode(PROTOCOL.Kind.HELLO,hello,"bulk token requires bulk role")
	var reject: Dictionary={"code":0,"message":"x"}; _reject_encode(PROTOCOL.Kind.REJECT,reject,"zero rejection code")
	var welcome: Dictionary=_fixtures()[1].payload.duplicate(true); welcome.snapshot_hz=61
	_reject_encode(PROTOCOL.Kind.WELCOME,welcome,"snapshot frequency cannot exceed server rate")
	welcome=_fixtures()[1].payload.duplicate(true); welcome.actor_id=0
	_reject_encode(PROTOCOL.Kind.WELCOME,welcome,"welcome stable actor ID positive")
	var invalid_channel: Dictionary=base.duplicate(); invalid_channel.channel=2
	_reject_encode(PROTOCOL.Kind.CHAT,invalid_channel,"invalid channel enum")

func _test_maps() -> void:
	var begin: Dictionary=_fixtures()[7].payload.duplicate(true)
	for change: Dictionary in [{"key":"uncompressed_size","value":67108865},{"key":"uncompressed_size","value":4},{"key":"compressed_size","value":0},{"key":"chunk_count","value":1},{"key":"dimensions","value":Vector3i(513,64,512)},{"key":"dimensions","value":Vector3i(512,65,512)},{"key":"dimensions","value":Vector3i(0,64,512)},{"key":"compression","value":2}]:
		var invalid: Dictionary=begin.duplicate(true); invalid[change.key]=change.value
		_reject_encode(PROTOCOL.Kind.MAP_BEGIN,invalid,"invalid map descriptor "+change.key)
	var raw: Dictionary=begin.duplicate(true); raw.compression=0
	_reject_encode(PROTOCOL.Kind.MAP_BEGIN,raw,"raw byte count must match cell volume")
	raw.dimensions=Vector3i(2,3,4); raw.compressed_size=96; raw.uncompressed_size=96; raw.chunk_count=1
	check(_encode(PROTOCOL.Kind.MAP_BEGIN,raw).ok,"Godot x/y/z unequal dimension volume")
	var full: Dictionary={"snapshot_id":3,"index":0,"total_size":PROTOCOL.CHUNK_BYTES,"data":_bytes(PROTOCOL.CHUNK_BYTES)}
	var frame: PackedByteArray=_encode(PROTOCOL.Kind.MAP_CHUNK,full).bytes
	check(frame.size()==16384 and PROTOCOL.decode(frame).ok,"exact16KiB bulk frame allowed")
	var invalid_chunk: Dictionary=full.duplicate(true); invalid_chunk.data=_bytes(PROTOCOL.CHUNK_BYTES+1)
	_reject_encode(PROTOCOL.Kind.MAP_CHUNK,invalid_chunk,"oversize chunk data")
	invalid_chunk=full.duplicate(true); invalid_chunk.index=1
	_reject_encode(PROTOCOL.Kind.MAP_CHUNK,invalid_chunk,"chunk index beyond transfer")
	invalid_chunk=full.duplicate(true); invalid_chunk.total_size=67108865
	_reject_encode(PROTOCOL.Kind.MAP_CHUNK,invalid_chunk,"bulk transfer compressed size cap")
	frame.append(0); _reject_frame(_with_length(frame),"bulk16KiB total cap enforced")
	var delta: Dictionary=_delta()
	for cell: Vector3i in [Vector3i(-1,0,0),Vector3i(512,0,0),Vector3i(0,64,0),Vector3i(0,0,512)]:
		var invalid: Dictionary=delta.duplicate(true); invalid.changes[0].cell=cell
		_reject_encode(PROTOCOL.Kind.MAP_DELTA,invalid,"cell boundary "+str(cell))
	for item: Dictionary in [{"key":"fragment_count","value":2},{"key":"fragment_index","value":1},{"key":"total_changes","value":1},{"key":"total_changes","value":16777217}]:
		var invalid: Dictionary=delta.duplicate(true); invalid[item.key]=item.value
		_reject_encode(PROTOCOL.Kind.MAP_DELTA,invalid,"inconsistent delta fragment "+item.key)
	var duplicate: Dictionary=delta.duplicate(true); duplicate.changes[1].cell=Vector3i.ZERO
	_reject_encode(PROTOCOL.Kind.MAP_DELTA,duplicate,"duplicate cells inside fragment")
	var invalid_color: Dictionary=delta.duplicate(true); invalid_color.changes[0].before=0xff000000
	_reject_encode(PROTOCOL.Kind.MAP_DELTA,invalid_color,"packed solid marker exactly0x01")
	var invalid_flags: Dictionary=delta.duplicate(true); invalid_flags.changes[0].flags=2
	_reject_encode(PROTOCOL.Kind.MAP_DELTA,invalid_flags,"unknown collapse flags")
	var large: Dictionary=delta.duplicate(true); large.changes=[]; large.total_changes=2049; large.fragment_count=2
	for index: int in range(2048): large.changes.append({"cell":Vector3i(index%512,2,index/512),"before":0,"after":0x01000000,"flags":0})
	var encoded: PROTOCOL.Result=_encode(PROTOCOL.Kind.MAP_DELTA,large)
	check(encoded.ok and encoded.bytes.size()<=32768 and PROTOCOL.decode(encoded.bytes).ok,"2048-change fragment bounded roundtrip")
	large.fragment_index=1; large.changes=[{"cell":Vector3i(1,2,5),"before":0,"after":0x01000000,"flags":0}]
	check(_encode(PROTOCOL.Kind.MAP_DELTA,large).ok,"last short fragment count is exact")
	var delta_frame: PackedByteArray=_encode(PROTOCOL.Kind.MAP_DELTA,delta).bytes
	delta_frame[54]=255; delta_frame[55]=255; _reject_frame(delta_frame,"hostile delta count before allocation")
	delta_frame=_encode(PROTOCOL.Kind.MAP_DELTA,delta).bytes; delta_frame[56]=2; delta_frame[57]=0
	_reject_frame(delta_frame,"wire cell512 rejected")
	var descriptor: PackedByteArray=_encode(PROTOCOL.Kind.MAP_BEGIN,begin).bytes
	_put_u32(descriptor,39,0xffffffff); _reject_frame(descriptor,"wire uncompressed cap before map allocation")

func _test_snapshots() -> void:
	var snapshot: Dictionary=_snapshot()
	for field: String in ["feet","native_velocity"]:
		var invalid: Dictionary=snapshot.duplicate(true); invalid.actors[0][field]=Vector3(INF,0,0)
		_reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"nonfinite actor "+field)
	var invalid: Dictionary=snapshot.duplicate(true); invalid.actors[0].pitch=2.0
	_reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"actor pitch bounded")
	invalid=snapshot.duplicate(true); invalid.actors[0].team=2
	_reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"spectator cannot carry alive flag")
	invalid=snapshot.duplicate(true); invalid.actors.append(_actor())
	_reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"duplicate stable actor ID")
	invalid=snapshot.duplicate(true); invalid.owner_id=8
	_reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"owner missing from actor registry")
	for field: String in ["health","magazine","grenades","blocks"]:
		invalid=snapshot.duplicate(true); invalid.owner_state[field]=65536
		_reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"owner resource field bound "+field)
	invalid=snapshot.duplicate(true); invalid.actors=[]
	for index: int in range(32): invalid.actors.append(_actor(index+1))
	check(_encode(PROTOCOL.Kind.SNAPSHOT,invalid).ok,"32 actors allowed independently of network peer IDs")
	invalid.actors.append(_actor(33)); _reject_encode(PROTOCOL.Kind.SNAPSHOT,invalid,"33rd actor rejected")
	var frame: PackedByteArray=_encode(PROTOCOL.Kind.SNAPSHOT,snapshot).bytes
	frame[65]=255; _reject_frame(frame,"claimed actor count cap")
	frame=_encode(PROTOCOL.Kind.SNAPSHOT,snapshot).bytes; frame[65]=2
	_reject_frame(frame,"actor count/available bytes mismatch")
	frame=_encode(PROTOCOL.Kind.SNAPSHOT,snapshot).bytes
	# header24 + fixed snapshot42 + actor prefix13 + name prefix2 + UTF8 bytes.
	var first_float: int=24+42+15+str(snapshot.actors[0].name).to_utf8_buffer().size()
	_put_u32(frame,first_float,0x7fc00000); _reject_frame(frame,"wire NaN actor position")
	invalid=snapshot.duplicate(true); invalid.owner_id=0; invalid.actors=[]
	check(_encode(PROTOCOL.Kind.SNAPSHOT,invalid).ok,"loading replica can have no actor owner")

func _test_hostile_mutations() -> void:
	var node: Node = Node.new()
	_reject_encode(PROTOCOL.Kind.CHAT,{"channel":0,"sender_id":0,"message_id":1,"text":node},"Godot objects never encoded")
	node.free()
	_reject_encode(PROTOCOL.Kind.PING,{"nonce":1,"client_time_ms":2,"extra":3},"unknown fields cannot be silently ignored")
	_reject_encode(PROTOCOL.Kind.PING,{"nonce":true,"client_time_ms":2},"bool is not wire integer")
	# Deterministic fuzzing of header/payload scalar bytes; a surviving valid
	# mutation must remain canonical, not crash or expose partial failed state.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new(); rng.seed=0x42464e57
	for fixture: Dictionary in _fixtures():
		var original: PackedByteArray=_encode(fixture.kind,fixture.payload).bytes
		for attempt: int in range(32):
			var changed: PackedByteArray=original.duplicate()
			changed[rng.randi_range(0,changed.size()-1)]=rng.randi_range(0,255)
			var result: PROTOCOL.Result=PROTOCOL.decode(changed)
			if result.ok:
				var encoded: PROTOCOL.Result=PROTOCOL.encode(result.packet)
				check(encoded.ok and encoded.bytes==changed,"surviving hostile mutation canonical")
			else: check(result.packet==null and not result.error.is_empty(),"hostile mutation rejected cleanly")
