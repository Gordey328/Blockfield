class_name BlockfieldServerRuntime
extends RefCounted
## Native authority: two sockets, owned commands and ordered joining map streams.
const P = preload("res://network/protocol.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const REGISTRY = preload("res://network/session_registry.gd")
const INPUTS = preload("res://network/input_queue.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const RULES = preload("res://simulation/player_rules.gd")
const CODEC = preload("res://network/simulation_codec.gd")
const MAX_JOINS := 2
const JOIN_TIMEOUT_MS := 240000
const HELLO_TIMEOUT_MS := 5000
var simulation: MatchSimulation
var game_transport := TRANSPORT.new()
var map_transport := TRANSPORT.new()
var registry := REGISTRY.new()
var running := false
var _inputs: Dictionary[int,INPUTS] = {}
var _streams: Dictionary[int,Dictionary] = {}
var _pending_game: Dictionary[int,int] = {}
var _pending_bulk: Dictionary[int,int] = {}
var _next_snapshot_id := 1
var _snapshot_factory: Callable
var _chat_sequence := 0
var _chat_times: Dictionary[int,Array] = {}
var _chat_intents: Dictionary[int,int] = {}
var _totals := {"steps":0,"admissions":0,"resumes":0,"input_rejections":0,"closed":0,"map_resyncs":0,"snapshots":0,"chat":0}

func configure(match_simulation: MatchSimulation, build_hash: PackedByteArray, rules_hash: PackedByteArray) -> bool:
	if running or match_simulation == null or match_simulation.data == null: return false
	if not registry.configure(match_simulation.epoch,build_hash,rules_hash,0 if match_simulation.profile == "0.75" else 1): return false
	simulation = match_simulation
	_inputs.clear()
	_streams.clear()
	_pending_game.clear()
	_pending_bulk.clear()
	_chat_times.clear()
	_chat_intents.clear()
	_next_snapshot_id = 1
	_chat_sequence = 0
	return true

func set_snapshot_factory(factory: Callable) -> void:
	_snapshot_factory = factory

func start(game_port: int = 0, map_port: int = 0, bind_address: String = "127.0.0.1") -> Dictionary:
	if running or simulation == null: return {"ok":false,"error":"runtime not configured or already active"}
	var game_started := game_transport.start_server(game_port,bind_address)
	if not game_started.ok: return game_started
	var map_started := map_transport.start_server(map_port,bind_address)
	if not map_started.ok:
		game_transport.stop(true)
		return map_started
	running = true
	# Joining actors and codecs require a real current simulation tick.
	if simulation.tick < 0: step_once()
	return {"ok":true,"error":"","game_port":game_started.port,"map_port":map_started.port}

func stop() -> void:
	game_transport.stop(true)
	map_transport.stop(true)
	for id: int in _streams: _release_stream(_streams[id])
	for id: int in _inputs: simulation.disconnect_actor(id)
	_inputs.clear()
	_streams.clear()
	_pending_game.clear()
	_pending_bulk.clear()
	running = false

func poll() -> void:
	if not running: return
	var now := Time.get_ticks_msec()
	game_transport.poll()
	map_transport.poll()
	_handle_events(game_transport.drain_events(),false,now)
	_handle_events(map_transport.drain_events(),true,now)
	for connection: int in _pending_game.keys():
		if now-_pending_game[connection] >= HELLO_TIMEOUT_MS: _close_game(connection,"HELLO timeout",now)
	for connection: int in _pending_bulk.keys():
		if now-_pending_bulk[connection] >= HELLO_TIMEOUT_MS:
			map_transport.close(connection,1008,"HELLO timeout")
			_pending_bulk.erase(connection)
	for id: int in registry.expire(now):
		simulation.remove_actor(id)
		_inputs.erase(id)
		_chat_times.erase(id)
		_chat_intents.erase(id)
	for id: int in _streams.keys():
		if _streams.has(id): _poll_stream(id,now)

func _handle_events(events: Array[Dictionary], bulk: bool, now: int) -> void:
	for event: Dictionary in events:
		var connection: int = event.get("connection_id",0)
		match event.type:
			"connected":
				if bulk: _pending_bulk[connection] = now
				else: _pending_game[connection] = now
			"packet":
				if bulk: _bulk_packet(connection,event.packet,now)
				else: _game_packet(connection,event.packet,now)
			"closed", "timeout", "protocol_error":
				if bulk:
					_pending_bulk.erase(connection)
					var id := registry.disconnect_bulk(connection)
					if id != 0 and _streams.has(id) and _streams[id].phase != "live":
						_close_game(registry.session_view(id).game,"map connection lost",now)
				else: _close_game(connection,"connection lost",now)
			"overflow":
				for id: int in _inputs.keys():
					var view := registry.session_view(id)
					if not view.is_empty() and view.game != 0: _close_game(view.game,"transport event overflow",now)

func _allocate_actor(player_name: String, _role: int) -> Dictionary:
	return simulation.add_actor(player_name,2,_next_snapshot_id*7919+17)

func _game_packet(connection: int, packet: BlockfieldProtocol.Packet, now: int) -> void:
	var id := registry.owner_of_game(connection,false)
	if id == 0:
		if not _pending_game.has(connection) or packet.kind != P.Kind.HELLO or _loading_count() >= MAX_JOINS:
			_close_game(connection,"admission unavailable",now)
			return
		var admitted := registry.admit_game(connection,packet,now,_allocate_actor)
		if not admitted.ok:
			_close_game(connection,"HELLO rejected",now)
			return
		id = admitted.actor_id
		_pending_game.erase(connection)
		if admitted.resumed:
			simulation.reconnect_actor(id)
			_totals.resumes += 1
		else: _totals.admissions += 1
		var actor := simulation.get_actor(id)
		registry.set_generation(id,actor.spawn_generation)
		admitted.welcome.payload.spawn_generation = actor.spawn_generation
		var queue := INPUTS.new()
		queue.reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
		_inputs[id] = queue
		simulation.clear_controls(id)
		var prepared := TRANSFER.prepare_sender(simulation.data,_next_snapshot_id)
		_next_snapshot_id += 1
		if not prepared.ok:
			_close_game(connection,"map preparation failed",now)
			return
		_streams[id] = {"phase":"prepare","started":now,"job":prepared.job,"sender":null,"end_job":null,
			"welcome":admitted.welcome,"pending":[],"changes":0,"bytes":0,"delta_sender":null,"delta_packet":null,
			"map_sequence":simulation.data.map_sequence,"barrier_sequence":-1,"end_packet":null,"bulk_packet":null,"latest_snapshot":null}
		return
	if packet.kind == P.Kind.MAP_READY:
		if not _streams.has(id) or _streams[id].phase != "waiting" or not registry.accept_ready(connection,packet):
			_close_game(connection,"invalid map readiness",now)
			return
		var actor := simulation.get_actor(id)
		if registry.session_view(id).role == 0 and actor.team == 2:
			var counts := [0,0]
			for other: SharedPlayerState in simulation.actors.values():
				if other.connected and other.team < 2: counts[other.team] += 1
			var spawned := simulation.spawn_actor(id,0 if counts[0] <= counts[1] else 1)
			if not spawned.ok:
				_close_game(connection,"spawn unavailable",now)
				return
		registry.set_generation(id,actor.spawn_generation)
		_inputs[id].reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
		_streams[id].phase = "live"
		_streams[id].sender.cancel()
		_streams[id].sender = null
		return
	if registry.owner_of_game(connection) != id or not _streams.has(id) or _streams[id].phase != "live":
		_close_game(connection,"gameplay before map readiness",now)
		return
	match packet.kind:
		P.Kind.INPUT_BATCH:
			# In-flight old-life TCP frames cannot authorize the new generation.
			if packet.epoch == simulation.epoch and packet.sequence < simulation.get_actor(id).spawn_generation: return
			if not _inputs[id].accept(packet,simulation.tick).ok:
				_totals.input_rejections += 1
				_close_game(connection,"invalid input stream",now)
		P.Kind.CHAT: _chat(id,packet,now)
		_: _close_game(connection,"invalid client packet direction",now)

func _bulk_packet(connection: int, packet: BlockfieldProtocol.Packet, now: int) -> void:
	if registry.owner_of_bulk(connection) != 0:
		map_transport.close(connection,1008,"bulk channel is server to client")
		return
	if not _pending_bulk.has(connection) or packet.kind != P.Kind.HELLO:
		map_transport.close(connection,1008,"bulk HELLO required")
		return
	var admitted := registry.admit_bulk(connection,packet,now)
	_pending_bulk.erase(connection)
	if not admitted.ok: map_transport.close(connection,1008,"bulk HELLO rejected")

func _loading_count() -> int:
	var count := 0
	for stream: Dictionary in _streams.values():
		if stream.phase != "live": count += 1
	return count

func _release_stream(stream: Dictionary) -> void:
	for key in ["job","sender","end_job","delta_sender"]:
		if stream.get(key) != null: stream[key].cancel()
	stream.clear()

func _close_game(connection: int, reason: String, now: int) -> void:
	_pending_game.erase(connection)
	var id := registry.owner_of_game(connection,false)
	if id != 0:
		var detached := registry.disconnect_game(connection,now)
		if detached.ok and detached.close_bulk != 0: map_transport.close(detached.close_bulk,1000,"paired owner disconnected")
		simulation.disconnect_actor(id)
		_inputs.erase(id)
		if _streams.has(id):
			_release_stream(_streams[id])
			_streams.erase(id)
		_totals.closed += 1
	game_transport.close(connection,1008,reason)

func _poll_stream(id: int, now: int) -> void:
	var s: Dictionary = _streams[id]
	var view := registry.session_view(id)
	if view.is_empty() or view.game == 0: return
	if s.phase != "live" and now-s.started >= JOIN_TIMEOUT_MS:
		_close_game(view.game,"map join timeout",now)
		return
	if s.phase == "prepare":
		var progress: Dictionary = s.job.advance(2)
		if not progress.ok:
			_close_game(view.game,"map hash failed",now)
			return
		if not progress.done: return
		s.sender = s.job.take_sender().sender
		s.job = null
		var renewed := registry.refresh_bulk_token(id,now)
		if not renewed.ok:
			_close_game(view.game,"bulk capability unavailable",now)
			return
		s.welcome.payload.bulk_token = renewed.token
		if not game_transport.send(view.game,s.welcome).ok or not game_transport.send(view.game,s.sender.begin_packet()).ok:
			_close_game(view.game,"join header backpressure",now)
			return
		s.welcome = null
		s.phase = "baseline"
	if s.phase == "baseline" and view.bulk != 0:
		for work in range(2):
			if s.bulk_packet == null:
				var chunk: Dictionary = s.sender.next_chunk()
				if not chunk.ok:
					_close_game(view.game,"map chunk failed",now)
					return
				if chunk.done:
					var prepared: Dictionary = s.sender.prepare_end(simulation.data)
					if not prepared.ok:
						_close_game(view.game,"map barrier preparation failed",now)
						return
					s.end_job = prepared.job
					s.barrier_sequence = simulation.data.map_sequence
					s.phase = "barrier"
					break
				s.bulk_packet = chunk.packet
			if not map_transport.send(view.bulk,s.bulk_packet).ok: break
			s.bulk_packet = null
	if s.phase == "barrier" and s.end_job != null:
		var progress: Dictionary = s.end_job.advance(2)
		if not progress.ok:
			_close_game(view.game,"map barrier hash failed",now)
			return
		if progress.done:
			s.end_packet = s.end_job.take_packet().packet
			s.end_job = null
	# Deltas beyond an announced barrier wait until READY, preserving two-socket ordering.
	var allowed: int = s.barrier_sequence if s.phase in ["barrier","waiting"] else P.U32_MAX
	if s.phase != "waiting":
		for work in range(2):
			if s.delta_sender == null:
				if s.pending.is_empty() or s.pending[0].map_sequence > allowed: break
				var prepared: Dictionary = TRANSFER.make_delta_sender(s.pending[0])
				if not prepared.ok:
					_close_game(view.game,"map transaction needs baseline",now)
					return
				s.delta_sender = prepared.sender
			if s.delta_packet == null:
				var fragment: Dictionary = s.delta_sender.next_fragment()
				if not fragment.ok:
					_close_game(view.game,"map delta failed",now)
					return
				if fragment.done:
					var transaction: Dictionary = s.pending.pop_front()
					s.map_sequence = transaction.map_sequence
					s.changes -= transaction.changes.size()
					s.bytes -= _transaction_bytes(transaction)
					s.delta_sender.cancel()
					s.delta_sender = null
					continue
				s.delta_packet = fragment.packet
			if not game_transport.send(view.game,s.delta_packet).ok: break
			s.delta_packet = null
	if s.phase == "barrier" and s.end_packet != null and s.map_sequence == s.barrier_sequence and s.delta_sender == null:
		if game_transport.send(view.game,s.end_packet).ok:
			registry.set_barrier(id,s.end_packet)
			s.end_packet = null
			s.phase = "waiting"
	if s.phase == "live" and s.pending.is_empty() and s.delta_sender == null and s.latest_snapshot != null:
		if game_transport.send(view.game,s.latest_snapshot).ok: s.latest_snapshot = null

func _transaction_bytes(transaction: Dictionary) -> int:
	return transaction.changes.size()*15+ceili(float(transaction.changes.size())/P.MAX_CHANGES)*80

func step_once() -> bool:
	if simulation == null: return false
	var commands: Dictionary = {}
	var next_tick := simulation.tick+1
	var now := Time.get_ticks_msec()
	for id: int in _inputs.keys():
		var actor := simulation.get_actor(id)
		if actor == null: continue
		if actor.spawn_generation != _inputs[id].generation:
			registry.set_generation(id,actor.spawn_generation)
			_inputs[id].reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
		var taken: Dictionary = _inputs[id].take(next_tick)
		if not taken.ok:
			_close_game(registry.session_view(id).game,"input clock needs resync",now)
			continue
		if taken.clear_controls: simulation.clear_controls(id)
		if taken.command != null: commands[id] = taken.command
	simulation.step_fixed(commands)
	if simulation.tick != next_tick: return false
	simulation.data.last_tick = simulation.tick
	for id: int in _inputs:
		var actor := simulation.get_actor(id)
		if actor != null and actor.spawn_generation != _inputs[id].generation:
			registry.set_generation(id,actor.spawn_generation)
			_inputs[id].reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
	_totals.steps += 1
	for transaction: Dictionary in simulation.drain_transactions():
		if transaction.get("resync_required",false):
			for id: int in _streams.keys(): _close_game(registry.session_view(id).game,"map journal requires baseline",now)
			_totals.map_resyncs += 1
			if simulation.has_method("acknowledge_map_resync"): simulation.acknowledge_map_resync()
			break
		for id: int in _streams.keys():
			var s: Dictionary = _streams[id]
			if transaction.map_sequence <= s.map_sequence: continue
			var bytes := _transaction_bytes(transaction)
			if s.pending.size() >= TRANSFER.MAX_TRANSACTIONS or s.changes+transaction.changes.size() > TRANSFER.MAX_BUFFERED_CHANGES or s.bytes+bytes > TRANSFER.MAX_BUFFERED_BYTES:
				_close_game(registry.session_view(id).game,"map queue requires baseline",now)
				continue
			s.pending.append(transaction)
			s.changes += transaction.changes.size()
			s.bytes += bytes
	# Authoritative effects will be handled by the explicit event codec/replica.
	simulation.drain_events()
	if simulation.tick%3 == 0:
		for id: int in _streams:
			if _streams[id].phase != "live": continue
			var packet: Variant = _snapshot_factory.call(simulation.snapshot_for(id)) if _snapshot_factory.is_valid() else _full_snapshot(id)
			if packet is P.Packet:
				_streams[id].latest_snapshot = packet # Only unsent state is replaceable.
				_totals.snapshots += 1
	return true

func _full_snapshot(id: int) -> BlockfieldProtocol.Packet:
	var converted := CODEC.from_snapshot(simulation.snapshot_for(id))
	if not converted.ok:
		_close_game(registry.session_view(id).game,"state serialization failed",Time.get_ticks_msec())
		return null
	return P.make_packet(P.Kind.MATCH_STATE,converted.payload,simulation.epoch,simulation.tick,simulation.get_actor(id).spawn_generation)

func _legacy_snapshot(id: int) -> BlockfieldProtocol.Packet:
	# Transitional transport integration fixture; full replay uses MATCH_STATE.
	var owner := simulation.get_actor(id)
	var actors: Array = []
	for actor: SharedPlayerState in simulation.actors.values():
		var flags := int(actor.is_alive())|int(actor.motion.crouch)*2|int(actor.sprinting)*4|int(actor.motion.wading)*8|int(actor.motion.grounded)*16|int(actor.connected)*32|int(actor.reloading)*64|int(actor.cooking)*128
		actors.append({"id":actor.player_id,"spawn_generation":actor.spawn_generation,"team":actor.team,"flags":flags,"tool":actor.tool,"weapon":actor.weapon,
			"name":actor.player_name,"feet":actor.feet(),"native_velocity":actor.motion.native_velocity,"yaw":actor.yaw,"pitch":actor.pitch})
	var resources := {"health":owner.health,"magazine":owner.magazine,"reserve":owner.reserve,"grenades":owner.grenades,"blocks":owner.blocks,
		"fire_tick":RULES.deadline_tick(owner.next_shot_tick),"reload_tick":RULES.deadline_tick(owner.reload_deadline_tick),
		"cook_tick":maxi(0,owner.cook_started_tick),"respawn_tick":maxi(0,owner.respawn_tick)}
	return P.make_packet(P.Kind.SNAPSHOT,{"map_sequence":simulation.data.map_sequence,"event_sequence":simulation.event_sequence,
		"input_ack":owner.consumed_input_sequence,"profile":0 if owner.profile == "0.75" else 1,"owner_id":id,"owner_state":resources,"actors":actors},simulation.epoch,simulation.tick,owner.spawn_generation)

func _chat(id: int, packet: BlockfieldProtocol.Packet, now: int) -> void:
	var actor := simulation.get_actor(id)
	if packet.epoch != simulation.epoch or packet.sequence != actor.spawn_generation or packet.payload.sender_id != 0 \
			or packet.payload.message_id != int(_chat_intents.get(id,0))+1:
		_close_game(registry.session_view(id).game,"invalid chat ownership",now)
		return
	var times: Array = _chat_times.get(id,[])
	while not times.is_empty() and now-int(times[0]) >= 5000: times.pop_front()
	if times.size() >= 4:
		_close_game(registry.session_view(id).game,"chat rate exceeded",now)
		return
	times.append(now)
	_chat_times[id] = times
	_chat_intents[id] = packet.payload.message_id
	_chat_sequence += 1
	var outgoing := P.make_packet(P.Kind.CHAT,{"channel":packet.payload.channel,"sender_id":id,"message_id":_chat_sequence,"text":packet.payload.text},simulation.epoch,simulation.tick,_chat_sequence)
	for recipient: int in _streams.keys():
		if _streams[recipient].phase != "live": continue
		if packet.payload.channel == 1 and simulation.get_actor(recipient).team != actor.team: continue
		if not game_transport.send(registry.session_view(recipient).game,outgoing).ok:
			_close_game(registry.session_view(recipient).game,"chat backpressure",now)
	_totals.chat += 1

func get_stats() -> Dictionary:
	return {"running":running,"tick":simulation.tick if simulation != null else -1,"registry":registry.get_stats(),"loading":_loading_count(),
		"streams":_streams.size(),"totals":_totals.duplicate(),"game":game_transport.get_stats(),"map":map_transport.get_stats()}
