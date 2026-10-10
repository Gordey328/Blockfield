class_name BlockfieldSessionRegistry
extends RefCounted
## Guest connection ownership. Account authentication and simulation are external.
const PROTOCOL = preload("res://network/protocol.gd")
const MAX_ACTORS := 32
const GRACE_MS := 30000
const BULK_TOKEN_MS := 15000
const MAX_CLOCK_MS := 0x7fffffffffffffff - GRACE_MS
var epoch: int = 0
var profile: int = 0
var _build_hash: PackedByteArray
var _rules_hash: PackedByteArray
var _sessions: Dictionary[int,Dictionary] = {}
var _games: Dictionary[int,int] = {}
var _bulks: Dictionary[int,int] = {}
var _last_time: int = -1
var _crypto := Crypto.new()

func configure(match_epoch: int, build_hash: PackedByteArray, rules_hash: PackedByteArray, match_profile: int = 0) -> bool:
	if match_epoch <= 0 or match_epoch > PROTOCOL.U32_MAX or build_hash.size() != 32 or rules_hash.size() != 32 or match_profile not in [0,1]: return false
	epoch = match_epoch
	profile = match_profile
	_build_hash = build_hash.duplicate()
	_rules_hash = rules_hash.duplicate()
	_sessions.clear()
	_games.clear()
	_bulks.clear()
	_last_time = -1
	return true

func _clock(now_ms: int) -> bool:
	if now_ms < 0 or now_ms < _last_time: return false
	_last_time = now_ms
	return true

func _hello(packet: BlockfieldProtocol.Packet) -> bool:
	return packet != null and packet.kind == PROTOCOL.Kind.HELLO and packet.epoch == 0 and packet.tick == 0 and packet.sequence == 0 and PROTOCOL.encode(packet).ok \
		and packet.payload.build_hash == _build_hash and packet.payload.rules_hash == _rules_hash

func _hash(token: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(token)
	return context.finish()

func _equal(first: PackedByteArray, second: PackedByteArray) -> bool:
	return first.size() == 32 and second.size() == 32 and _crypto.constant_time_compare(first,second)

func _new_token() -> PackedByteArray:
	return _crypto.generate_random_bytes(32)

func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func _epoch_failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"welcomes":[],"close_bulk":[],"expired_actor_ids":[]}

func advance_epoch(new_epoch: int, new_profile: int, now_ms: int) -> Dictionary:
	# Trusted match replacement preserves the live game binding. Prepare every
	# credential and wire packet before committing any epoch/session/clock state.
	if epoch==0 or new_epoch<=epoch or new_epoch>PROTOCOL.U32_MAX or new_profile not in [0,1] \
			or now_ms<0 or now_ms>MAX_CLOCK_MS or now_ms<_last_time:
		return _epoch_failure("invalid epoch, profile or clock")
	var ids: Array[int]=[]
	ids.assign(_sessions.keys());ids.sort()
	var credentials: Dictionary[int,Dictionary]={}
	var used: Dictionary[String,bool]={}
	for id: int in ids:
		for digest: PackedByteArray in [_sessions[id].resume_hash,_sessions[id].bulk_hash]:
			if digest.size()==32:used[digest.hex_encode()]=true
	var welcomes: Array[PROTOCOL.Packet]=[]
	var close_bulk: Array[int]=[]
	var expired_actor_ids: Array[int]=[]
	for id: int in ids:
		var session: Dictionary=_sessions[id]
		if session.game==0:
			expired_actor_ids.append(id)
			continue
		var resume_token:=_new_token()
		var bulk_token:=_new_token()
		if resume_token.size()!=32 or bulk_token.size()!=32:return _epoch_failure("credential generation unavailable")
		var resume_hash:=_hash(resume_token)
		var bulk_hash:=_hash(bulk_token)
		if used.has(resume_hash.hex_encode()) or used.has(bulk_hash.hex_encode()) or resume_hash==bulk_hash:
			return _epoch_failure("fresh credentials unavailable")
		used[resume_hash.hex_encode()]=true;used[bulk_hash.hex_encode()]=true
		credentials[id]={"resume_hash":resume_hash,"bulk_hash":bulk_hash}
		var welcome:=PROTOCOL.make_packet(PROTOCOL.Kind.WELCOME,{"actor_id":id,"spawn_generation":1,
			"server_hz":60,"snapshot_hz":20,"profile":new_profile,"resume_token":resume_token,"bulk_token":bulk_token,
			"build_hash":_build_hash.duplicate(),"rules_hash":_rules_hash.duplicate()},new_epoch)
		if not PROTOCOL.encode(welcome).ok:return _epoch_failure("replacement WELCOME unavailable")
		welcomes.append(welcome)
		if session.bulk!=0:close_bulk.append(int(session.bulk))
	# Nothing above changes an admitted binding or the monotonic clock.
	for id: int in expired_actor_ids:_sessions.erase(id)
	for id: int in credentials:
		_sessions[id].merge({"generation":1,"bulk":0,"ready":false,"barrier":{},"expires":0,
			"resume_hash":credentials[id].resume_hash,"bulk_hash":credentials[id].bulk_hash,
			"bulk_expires":now_ms+BULK_TOKEN_MS},true)
	_bulks.clear()
	epoch=new_epoch;profile=new_profile;_last_time=now_ms
	close_bulk.sort()
	return {"ok":true,"error":"","welcomes":welcomes,"close_bulk":close_bulk,"expired_actor_ids":expired_actor_ids}

func admit_game(connection_id: int, packet: BlockfieldProtocol.Packet, now_ms: int, allocate_actor: Callable) -> Dictionary:
	if epoch == 0 or connection_id <= 0 or _games.has(connection_id) or not _clock(now_ms) or not _hello(packet) or packet.payload.role == 2:
		return _failure("invalid game admission or compatibility")
	var p: Dictionary = packet.payload
	var id := 0
	var resumed := false
	if p.resume_token.size() == 32:
		var digest := _hash(p.resume_token)
		for actor_id: int in _sessions:
			if _equal(digest,_sessions[actor_id].resume_hash): id = actor_id
		if id == 0: return _failure("invalid resume token")
		var old: Dictionary = _sessions[id]
		if old.game != 0 or now_ms >= old.expires or old.role != p.role: return _failure("resume unavailable")
		resumed = true
	else:
		if _sessions.size() >= MAX_ACTORS or not allocate_actor.is_valid(): return _failure("actor capacity or allocator unavailable")
		# Generate credentials before allocating a simulation actor.
	var resume_token := _new_token()
	var bulk_token := _new_token()
	if resume_token.size() != 32 or bulk_token.size() != 32: return _failure("credential generation unavailable")
	if not resumed:
		var allocation: Variant = allocate_actor.call(p.name,p.role)
		if not allocation is Dictionary or not allocation.get("ok",false): return _failure("actor allocation rejected")
		id = int(allocation.get("actor_id",0))
		if id <= 0 or id > PROTOCOL.U32_MAX or _sessions.has(id): return _failure("invalid allocated identity")
		_sessions[id] = {"role":p.role,"generation":1}
	var session: Dictionary = _sessions[id]
	session.merge({"game":connection_id,"bulk":0,"ready":false,"resume_hash":_hash(resume_token),
		"bulk_hash":_hash(bulk_token),"bulk_expires":now_ms+BULK_TOKEN_MS,"expires":0,"barrier":{}},true)
	_games[connection_id] = id
	var welcome := PROTOCOL.make_packet(PROTOCOL.Kind.WELCOME,{"actor_id":id,"spawn_generation":session.generation,
		"server_hz":60,"snapshot_hz":20,"profile":profile,"resume_token":resume_token,"bulk_token":bulk_token,
		"build_hash":_build_hash.duplicate(),"rules_hash":_rules_hash.duplicate()},epoch)
	return {"ok":true,"error":"","actor_id":id,"resumed":resumed,"welcome":welcome}

func admit_bulk(connection_id: int, packet: BlockfieldProtocol.Packet, now_ms: int) -> Dictionary:
	if epoch == 0 or connection_id <= 0 or _bulks.has(connection_id) or not _clock(now_ms) or not _hello(packet) \
			or packet.payload.role != 2 or not packet.payload.resume_token.is_empty(): return _failure("invalid bulk admission")
	var digest := _hash(packet.payload.bulk_token)
	var id := 0
	for actor_id: int in _sessions:
		if _equal(digest,_sessions[actor_id].bulk_hash): id = actor_id
	if id == 0: return _failure("invalid bulk token")
	var session: Dictionary = _sessions[id]
	if session.game == 0 or session.bulk != 0 or now_ms >= session.bulk_expires: return _failure("bulk token unavailable")
	session.bulk = connection_id
	session.bulk_hash = PackedByteArray() # One-time use, even if the bulk socket closes.
	_bulks[connection_id] = id
	return {"ok":true,"error":"","actor_id":id}

func owner_of_game(connection_id: int, require_ready: bool = true) -> int:
	var id: int = _games.get(connection_id,0)
	if id == 0 or (require_ready and not _sessions[id].ready): return 0
	return id

func unused_bulk_capabilities() -> Array[Dictionary]:
	# Trusted native reset coordination only. Digests are never sent to clients.
	var result: Array[Dictionary] = []
	for id: int in _sessions:
		var session: Dictionary = _sessions[id]
		if session.game != 0 and session.bulk_hash.size() == 32:
			result.append({"owner":id,"digest":session.bulk_hash.duplicate(),"expires":session.bulk_expires})
	return result

func validated_bulk_digest(packet: BlockfieldProtocol.Packet) -> PackedByteArray:
	if not _hello(packet) or packet.payload.role != 2 or not packet.payload.resume_token.is_empty(): return PackedByteArray()
	return _hash(packet.payload.bulk_token)

func owner_of_bulk(connection_id: int) -> int:
	return _bulks.get(connection_id,0)

func refresh_bulk_token(actor_id: int, now_ms: int) -> Dictionary:
	# Baseline preparation may outlast the original capability lifetime.
	if not _clock(now_ms) or not _sessions.has(actor_id) or _sessions[actor_id].game == 0 or _sessions[actor_id].bulk != 0:
		return _failure("bulk renewal unavailable")
	var token := _new_token()
	if token.size() != 32: return _failure("credential generation unavailable")
	_sessions[actor_id].bulk_hash = _hash(token)
	_sessions[actor_id].bulk_expires = now_ms+BULK_TOKEN_MS
	return {"ok":true,"error":"","token":token}

func set_generation(actor_id: int, generation: int) -> bool:
	if not _sessions.has(actor_id) or generation <= 0 or generation > PROTOCOL.U32_MAX: return false
	_sessions[actor_id].generation = generation
	return true

func set_barrier(actor_id: int, packet: BlockfieldProtocol.Packet) -> bool:
	if not _sessions.has(actor_id) or _sessions[actor_id].game == 0 or packet == null or packet.kind != PROTOCOL.Kind.MAP_END \
			or packet.epoch != epoch or packet.sequence != packet.payload.get("map_sequence",-1) or not PROTOCOL.encode(packet).ok: return false
	_sessions[actor_id].ready = false
	_sessions[actor_id].barrier = {"tick":packet.tick,"sequence":packet.sequence,"payload":packet.payload.duplicate(true)}
	return true

func accept_ready(connection_id: int, packet: BlockfieldProtocol.Packet) -> bool:
	var id := owner_of_game(connection_id,false)
	if id == 0 or packet == null or packet.kind != PROTOCOL.Kind.MAP_READY or packet.epoch != epoch or not PROTOCOL.encode(packet).ok: return false
	var barrier: Dictionary = _sessions[id].barrier
	if barrier.is_empty() or _sessions[id].ready or packet.tick != barrier.tick or packet.sequence != barrier.sequence \
			or packet.payload.snapshot_id != barrier.payload.snapshot_id or packet.payload.map_sequence != barrier.payload.map_sequence \
			or not _equal(packet.payload.hash,barrier.payload.hash): return false
	_sessions[id].ready = true
	_sessions[id].barrier = {}
	return true

func disconnect_game(connection_id: int, now_ms: int) -> Dictionary:
	if not _clock(now_ms): return _failure("invalid clock")
	var id := owner_of_game(connection_id,false)
	if id == 0: return _failure("unknown game connection")
	var session: Dictionary = _sessions[id]
	var bulk_id: int = session.bulk
	_games.erase(connection_id)
	if bulk_id != 0: _bulks.erase(bulk_id)
	session.game = 0
	session.bulk = 0
	session.ready = false
	session.bulk_hash = PackedByteArray()
	session.barrier = {}
	session.expires = now_ms+GRACE_MS
	return {"ok":true,"error":"","actor_id":id,"close_bulk":bulk_id}

func disconnect_bulk(connection_id: int) -> int:
	var id := owner_of_bulk(connection_id)
	if id == 0: return 0
	_bulks.erase(connection_id)
	_sessions[id].bulk = 0
	return id

func expire(now_ms: int) -> Array[int]:
	var expired: Array[int] = []
	if not _clock(now_ms): return expired
	for id: int in _sessions:
		if _sessions[id].game == 0 and now_ms >= _sessions[id].expires: expired.append(id)
	for id: int in expired: _sessions.erase(id)
	return expired

func session_view(actor_id: int) -> Dictionary:
	if not _sessions.has(actor_id): return {}
	var s: Dictionary = _sessions[actor_id]
	return {"actor_id":actor_id,"game":s.game,"bulk":s.bulk,"role":s.role,"ready":s.ready,"generation":s.generation}

func get_stats() -> Dictionary:
	return {"actors":_sessions.size(),"game_connections":_games.size(),"bulk_connections":_bulks.size(),"epoch":epoch}
