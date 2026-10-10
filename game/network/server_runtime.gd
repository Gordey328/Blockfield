class_name BlockfieldServerRuntime
extends RefCounted
## Native authority: two sockets, owned commands and ordered joining map streams.
const P = preload("res://network/protocol.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const REGISTRY = preload("res://network/session_registry.gd")
const INPUTS = preload("res://network/input_queue.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const CODEC = preload("res://network/simulation_codec.gd")
const EVENTS = preload("res://network/events_codec.gd")
const HIT_HISTORY = preload("res://network/hit_history.gd")
var hit_history := HIT_HISTORY.new()
var _shot_ticks: Dictionary[int,int] = {}
var _spawn_teams: Dictionary[int,int] = {}
var _retired_bulks: Dictionary[int,Dictionary] = {}
var _retired_bulk_capabilities: Array[Dictionary] = []
const MAX_RETIRED_CAPABILITIES := 64
const MAX_EVENT_FRAMES := 16
const MAX_EVENT_BYTES := 262144
const MAX_JOINS := 2
const JOIN_TIMEOUT_MS := 240000
# At most32 retained owners, two active joins, each active deadline240s:
# last FIFO admission waits at most15 waves; one extra wave is scheduling slack.
const MAX_QUEUE_WAIT_MS := ((P.MAX_ACTORS + MAX_JOINS - 1) / MAX_JOINS) * JOIN_TIMEOUT_MS
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
var _request_intents: Dictionary[int,int] = {}
var _request_times: Dictionary[int,Array] = {}
var _totals := {"steps":0,"admissions":0,"resumes":0,"input_rejections":0,"stale_inputs":0,"closed":0,"map_resyncs":0,"snapshots":0,"chat":0}

func configure(match_simulation: MatchSimulation, build_hash: PackedByteArray, rules_hash: PackedByteArray) -> bool:
	if running or match_simulation == null or not _supported_map_water(match_simulation.data): return false
	if not registry.configure(match_simulation.epoch,build_hash,rules_hash,0 if match_simulation.profile == "0.75" else 1): return false
	simulation = match_simulation
	hit_history.cancel("runtime configured")
	simulation.set_rewind_query_factory(_rewind_query)
	_shot_ticks.clear()
	_spawn_teams.clear()
	_retired_bulks.clear()
	_retired_bulk_capabilities.clear()
	_inputs.clear()
	_streams.clear()
	_pending_game.clear()
	_pending_bulk.clear()
	_chat_times.clear()
	_chat_intents.clear()
	_request_intents.clear()
	_request_times.clear()
	_next_snapshot_id = 1
	_chat_sequence = 0
	return true

func set_snapshot_factory(factory: Callable) -> void:
	_snapshot_factory = factory

static func _supported_map_water(map_data: VoxelData) -> bool:
	# Canonical map bytes do not carry physical water metadata. Network maps
	# must agree with the receiver's native defaults; offline queries may differ.
	return map_data != null and is_finite(map_data.water_level) and is_finite(map_data.wade_origin_level) \
		and map_data.water_level == 1.0 and map_data.wade_origin_level == 2.0

func reset_match(map_data: VoxelData, match_profile: String = "", game_mode: String = "") -> Dictionary:
	# Trusted native coordinator only; clients have no reset/map authority.
	if not running or simulation == null or map_data == null or map_data.epoch <= simulation.epoch:
		return {"ok":false,"error":"reset requires a newer map epoch"}
	if not _supported_map_water(map_data):
		return {"ok":false,"error":"network maps require native water levels1/2"}
	var replacement := SIMULATION.new()
	var configured := replacement.configure(map_data,simulation.profile if match_profile.is_empty() else match_profile,simulation.mode if game_mode.is_empty() else game_mode)
	if not configured.ok: return configured
	var teams: Dictionary[int,int] = {}
	var retired: Dictionary[int,int] = {}
	var old_capabilities := registry.unused_bulk_capabilities()
	for id: int in _streams:
		var actor := simulation.get_actor(id)
		var view := registry.session_view(id)
		if actor == null or view.is_empty() or view.game == 0: continue
		if view.bulk != 0: retired[view.bulk] = id
		var restored := replacement.add_actor(actor.player_name,2,id*7919+17,Vector3.INF,id)
		if not restored.ok: return {"ok":false,"error":"reset identity allocation failed"}
		var next_actor := replacement.get_actor(id)
		next_actor.weapon = actor.weapon
		next_actor.displayed_weapon = actor.weapon
		next_actor.pending_weapon = actor.pending_weapon
		teams[id] = actor.team if view.role == 0 else 2
	var changed: Dictionary = registry.advance_epoch(replacement.epoch,0 if replacement.profile == "0.75" else 1,Time.get_ticks_msec())
	if not changed.ok: return changed
	for capability: Dictionary in old_capabilities:
		# Only a capability already delivered in WELCOME could be in flight.
		if _streams.has(capability.owner) and _streams[capability.owner].welcome == null:
			_retired_bulk_capabilities.append(capability)
	while _retired_bulk_capabilities.size() > MAX_RETIRED_CAPABILITIES: _retired_bulk_capabilities.pop_front()
	# Independent sockets cannot order a forced bulk close after WELCOME.
	# Stop its sender/binding now; the client closes its old channel after it
	# receives WELCOME. Unread peers still have a bounded retirement deadline.
	for connection: int in changed.close_bulk:
		_retired_bulks[connection] = {"owner":retired[connection],"expires":Time.get_ticks_msec()+JOIN_TIMEOUT_MS}
	for stream: Dictionary in _streams.values(): _release_stream(stream)
	_streams.clear()
	_inputs.clear()
	_chat_times.clear()
	_chat_intents.clear()
	_request_intents.clear()
	_request_times.clear()
	_chat_sequence = 0
	_shot_ticks.clear()
	_spawn_teams = teams
	hit_history.cancel("new match epoch")
	simulation.set_rewind_query_factory(Callable())
	simulation = replacement
	simulation.set_rewind_query_factory(_rewind_query)
	# A closed baseline tick precedes every reset transfer and owner checkpoint.
	if not step_once(): return {"ok":false,"error":"reset baseline step failed"}
	for welcome: P.Packet in changed.welcomes:
		var id: int = welcome.payload.actor_id
		var actor := simulation.get_actor(id)
		var queue := INPUTS.new()
		queue.reset(simulation.epoch,actor.spawn_generation,simulation.tick,0)
		_inputs[id] = queue
		_request_intents[id] = 0
		_streams[id] = _new_stream(null,welcome,"queued")
		var announcement := P.make_packet(P.Kind.MATCH_PREPARING,{"actor_id":id,"spawn_generation":1,"profile":welcome.payload.profile},simulation.epoch,simulation.tick,1)
		if not game_transport.send(registry.session_view(id).game,announcement).ok:
			_close_game(registry.session_view(id).game,"match preparation announcement backpressure",Time.get_ticks_msec())
	return {"ok":true,"error":"","epoch":simulation.epoch,"actors":teams.size()}

func _new_stream(job: RefCounted, welcome: P.Packet, phase: String = "prepare") -> Dictionary:
	return {"phase":phase,"started":Time.get_ticks_msec(),"queued_at":Time.get_ticks_msec(),"job":job,"sender":null,"end_job":null,
		"welcome":welcome,"pending":[],"changes":0,"bytes":0,"delta_sender":null,"delta_packet":null,
		"map_sequence":simulation.data.map_sequence,"barrier_sequence":-1,"end_packet":null,"bulk_packet":null,"latest_snapshot":null,
		"event_packets":[],"event_bytes":0,"bulk_window":TRANSFER.BulkWindow.new()}

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
	_shot_ticks.clear()
	_spawn_teams.clear()
	_retired_bulks.clear()
	_retired_bulk_capabilities.clear()
	hit_history.cancel("runtime stopped")
	if simulation != null: simulation.set_rewind_query_factory(Callable())
	running = false

func poll() -> void:
	if not running: return
	var now := Time.get_ticks_msec()
	game_transport.poll()
	map_transport.poll()
	_handle_events(game_transport.drain_events(),false,now)
	_handle_events(map_transport.drain_events(),true,now)
	for connection: int in _retired_bulks.keys():
		if now >= _retired_bulks[connection].expires:
			map_transport.close(connection,1000,"retired map channel timeout")
			_retired_bulks.erase(connection)
	for index in range(_retired_bulk_capabilities.size()-1,-1,-1):
		if now >= _retired_bulk_capabilities[index].expires or registry.session_view(_retired_bulk_capabilities[index].owner).is_empty():
			_retired_bulk_capabilities.remove_at(index)
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
		_request_intents.erase(id)
		_request_times.erase(id)
		_shot_ticks.erase(id)
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
					_retired_bulks.erase(connection)
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
		if not _pending_game.has(connection) or packet.kind != P.Kind.HELLO or _loading_count() >= MAX_JOINS or _queued_count() > 0:
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
		_request_intents[id] = 0
		var actor := simulation.get_actor(id)
		registry.set_generation(id,actor.spawn_generation)
		admitted.welcome.payload.spawn_generation = actor.spawn_generation
		var queue := INPUTS.new()
		queue.reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
		_inputs[id] = queue
		_shot_ticks.erase(id)
		simulation.clear_controls(id)
		var prepared := TRANSFER.prepare_sender(simulation.data,_next_snapshot_id)
		_next_snapshot_id += 1
		if not prepared.ok:
			_close_game(connection,"map preparation failed",now)
			return
		_streams[id] = _new_stream(prepared.job,admitted.welcome)
		return
	# Ordered old-epoch frames can still be in TCP when a trusted reset starts.
	if packet.epoch < simulation.epoch:
		if packet.kind in [P.Kind.INPUT_BATCH,P.Kind.PLAYER_REQUEST,P.Kind.MAP_READY,P.Kind.CHAT]: return
		_close_game(connection,"invalid client packet direction",now)
		return
	if packet.kind == P.Kind.MAP_READY:
		if not _streams.has(id) or _streams[id].phase != "waiting" or not registry.accept_ready(connection,packet):
			_close_game(connection,"invalid map readiness",now)
			return
		var actor := simulation.get_actor(id)
		if registry.session_view(id).role == 0 and actor.team == 2 and _spawn_teams.get(id,-1) != 2:
			var counts := [0,0]
			for other: SharedPlayerState in simulation.actors.values():
				if other.connected and other.team < 2: counts[other.team] += 1
			var preferred: int = _spawn_teams.get(id,-1)
			var spawned := simulation.spawn_actor(id,preferred if preferred in [0,1] else (0 if counts[0] <= counts[1] else 1))
			if not spawned.ok:
				_close_game(connection,"spawn unavailable",now)
				return
		registry.set_generation(id,actor.spawn_generation)
		_inputs[id].reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
		_streams[id].phase = "live"
		_spawn_teams.erase(id)
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
		P.Kind.PLAYER_REQUEST: _player_request(id,packet,now)
		_: _close_game(connection,"invalid client packet direction",now)

func _bulk_packet(connection: int, packet: BlockfieldProtocol.Packet, now: int) -> void:
	var owner: int = registry.owner_of_bulk(connection)
	if owner != 0:
		# ACK body carries no actor ID. Authenticated socket ownership selects
		# exactly one active snapshot; another owner's credit cannot be changed.
		if packet.kind!=P.Kind.MAP_CHUNK_ACK or not _streams.has(owner) or _streams[owner].phase not in ["baseline","barrier","waiting","live"]:
			_close_game(registry.session_view(owner).game,"invalid map acknowledgment",now)
			return
		var acknowledged: Dictionary = _streams[owner].bulk_window.acknowledge(packet)
		if not acknowledged.ok: _close_game(registry.session_view(owner).game,"invalid map acknowledgment",now)
		return
	if not _pending_bulk.has(connection) or packet.kind != P.Kind.HELLO:
		map_transport.close(connection,1008,"bulk HELLO required")
		return
	var admitted := registry.admit_bulk(connection,packet,now)
	_pending_bulk.erase(connection)
	if not admitted.ok and not _retire_bulk_hello(connection,packet,now): map_transport.close(connection,1008,"bulk HELLO rejected")

func _retire_bulk_hello(connection: int, packet: P.Packet, now: int) -> bool:
	var digest := registry.validated_bulk_digest(packet)
	if digest.size() != 32: return false
	var crypto := Crypto.new()
	for index in _retired_bulk_capabilities.size():
		var capability: Dictionary = _retired_bulk_capabilities[index]
		if now >= capability.expires or not crypto.constant_time_compare(digest,capability.digest): continue
		var view := registry.session_view(capability.owner)
		if view.is_empty() or view.game == 0: return false
		_retired_bulk_capabilities.remove_at(index) # One-use idle retirement, no map access.
		_retired_bulks[connection] = {"owner":capability.owner,"expires":now+JOIN_TIMEOUT_MS}
		return true
	return false

func _loading_count() -> int:
	var count := 0
	for stream: Dictionary in _streams.values():
		if stream.phase not in ["live","queued"]: count += 1
	return count

func _queued_count() -> int:
	var count := 0
	for stream: Dictionary in _streams.values():
		if stream.phase == "queued": count += 1
	return count

func _release_stream(stream: Dictionary) -> void:
	for key in ["job","sender","end_job","delta_sender","bulk_window"]:
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
		_shot_ticks.erase(id)
		_spawn_teams.erase(id)
		for bulk_id: int in _retired_bulks.keys():
			if _retired_bulks[bulk_id].owner == id:
				map_transport.close(bulk_id,1000,"retired owner disconnected")
				_retired_bulks.erase(bulk_id)
		if _streams.has(id):
			_release_stream(_streams[id])
			_streams.erase(id)
		_totals.closed += 1
	game_transport.close(connection,1008,reason)

func _poll_stream(id: int, now: int) -> void:
	var s: Dictionary = _streams[id]
	var view := registry.session_view(id)
	if view.is_empty() or view.game == 0: return
	if s.phase == "queued" and now-s.queued_at >= MAX_QUEUE_WAIT_MS:
		_close_game(view.game,"map preparation queue timeout",now)
		return
	if s.phase not in ["live","queued"] and now-s.started >= JOIN_TIMEOUT_MS:
		_close_game(view.game,"map join timeout",now)
		return
	if s.phase == "queued":
		if _loading_count() >= MAX_JOINS: return
		s.started = now
		var prepared := TRANSFER.prepare_sender(simulation.data,_next_snapshot_id)
		_next_snapshot_id += 1
		if not prepared.ok:
			_close_game(view.game,"reset map preparation failed",now)
			return
		s.job = prepared.job
		s.phase = "prepare"
		s.map_sequence = simulation.data.map_sequence
	if s.phase == "prepare":
		var progress: Dictionary = s.job.advance(2)
		if not progress.ok:
			_close_game(view.game,"map hash failed",now)
			return
		if not progress.done: return
		s.sender = s.job.take_sender().sender
		s.job = null
		if not s.bulk_window.reset(s.sender.begin_packet()).ok:
			_close_game(view.game,"map receive window initialization failed",now)
			return
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
				var credit: Dictionary = s.bulk_window.get_stats()
				# Still allow the once-only end-of-sender probe after the final
				# queued chunk, even when its cumulative ACK is on the other socket.
				if credit.sent_chunks<credit.chunk_count and not s.bulk_window.can_send(): break
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
			if not s.bulk_window.mark_sent(s.bulk_packet).ok:
				_close_game(view.game,"map receive window invariant failed",now)
				return
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
	if s.phase == "live" and s.pending.is_empty() and s.delta_sender == null:
		for work in range(2):
			if s.event_packets.is_empty(): break
			var queued: Dictionary = s.event_packets[0]
			if not game_transport.send_prepared(view.game,queued.frame).ok: break
			s.event_packets.pop_front()
			s.event_bytes -= queued.bytes
		if s.event_packets.is_empty() and s.latest_snapshot != null:
			var sent: Dictionary = game_transport.send_prepared(view.game,s.latest_snapshot) if s.latest_snapshot is P.FrozenFrame else game_transport.send(view.game,s.latest_snapshot)
			if sent.ok: s.latest_snapshot = null

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
		# Authored server policy: ready playing actors respawn after the 180-tick
		# death delay. A loading/disconnected/spectator owner cannot spawn here.
		if actor.connected and actor.team < 2 and actor.health <= 0 and actor.respawn_tick >= 0 \
				and next_tick >= actor.respawn_tick and _streams.has(id) and _streams[id].phase == "live":
			simulation.spawn_actor(id,actor.team)
		if actor.spawn_generation != _inputs[id].generation:
			registry.set_generation(id,actor.spawn_generation)
			_request_intents[id] = 0
			_shot_ticks.erase(id)
			_inputs[id].reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
		var taken: Dictionary = _inputs[id].take(next_tick)
		if not taken.ok:
			_close_game(registry.session_view(id).game,"input clock needs resync",now)
			continue
		if taken.clear_controls:
			simulation.clear_controls(id)
			_shot_ticks.erase(id)
		if taken.discarded > 0:
			# These exact authenticated sequence IDs were retired, never simulated.
			# The owner snapshot removes them from replay without refilling anything.
			actor.consumed_input_sequence = maxi(actor.consumed_input_sequence,taken.retired_ack)
			_totals.stale_inputs += taken.discarded
		if taken.command != null:
			commands[id] = taken.command
			_shot_ticks[id] = mini(taken.input_tick,simulation.tick)
	simulation.step_fixed(commands,_shot_ticks)
	if simulation.tick != next_tick: return false
	simulation.data.last_tick = simulation.tick
	for id: int in _inputs:
		var actor := simulation.get_actor(id)
		if actor != null and actor.spawn_generation != _inputs[id].generation:
			registry.set_generation(id,actor.spawn_generation)
			_request_intents[id] = 0
			_shot_ticks.erase(id)
			_inputs[id].reset(simulation.epoch,actor.spawn_generation,simulation.tick,actor.consumed_input_sequence)
	_totals.steps += 1
	var committed := simulation.drain_transactions()
	var history_receipts: Array[Dictionary] = []
	var history_reset := false
	for transaction: Dictionary in committed:
		if transaction.get("resync_required",false):
			history_reset = true
			for id: int in _streams.keys(): _close_game(registry.session_view(id).game,"map journal requires baseline",now)
			_totals.map_resyncs += 1
			if simulation.has_method("acknowledge_map_resync"): simulation.acknowledge_map_resync()
			break
		history_receipts.append(transaction)
		for id: int in _streams.keys():
			var s: Dictionary = _streams[id]
			if s.phase == "queued": continue # Its immutable baseline has not started yet.
			if transaction.map_sequence <= s.map_sequence: continue
			var bytes := _transaction_bytes(transaction)
			if s.pending.size() >= TRANSFER.MAX_TRANSACTIONS or s.changes+transaction.changes.size() > TRANSFER.MAX_BUFFERED_CHANGES or s.bytes+bytes > TRANSFER.MAX_BUFFERED_BYTES:
				_close_game(registry.session_view(id).game,"map queue requires baseline",now)
				continue
			s.pending.append(transaction)
			s.changes += transaction.changes.size()
			s.bytes += bytes
	_record_hit_frame(history_receipts,history_reset)
	_route_events(simulation.drain_events(),now)
	if simulation.tick%3 == 0:
		var shared: CODEC.SharedFrame = null
		if not _snapshot_factory.is_valid():
			for id: int in _streams:
				if _streams[id].phase != "live": continue
				var prepared := CODEC.prepare_shared(simulation.snapshot_for(id))
				if prepared.ok: shared = prepared.frame
				break
		for id: int in _streams.keys():
			if _streams[id].phase != "live": continue
			var packet: Variant = null
			if _snapshot_factory.is_valid(): packet = _snapshot_factory.call(simulation.snapshot_for(id))
			else:
				var prepared := P.prepare_state(shared,simulation.get_actor(id))
				if prepared.ok: packet = prepared.frame
				else: _close_game(registry.session_view(id).game,"state serialization failed",now)
			if (packet is P.Packet or packet is P.FrozenFrame) and _streams.has(id):
				_streams[id].latest_snapshot = packet # Only unsent state is replaceable.
				_totals.snapshots += 1
	return true

func _rewind_query(request_tick: int, closed_tick: int) -> Dictionary:
	return hit_history.query_at(request_tick,closed_tick)

func _record_hit_frame(receipts: Array[Dictionary], reset_required: bool) -> void:
	var actors: Array[SharedPlayerState] = []
	actors.assign(simulation.actors.values())
	if reset_required or hit_history.get_stats().status != "recording":
		if not hit_history.reset(simulation.epoch,simulation.data).ok: return
		hit_history.record_frame(simulation.tick,simulation.data,actors,[])
	elif not hit_history.record_frame(simulation.tick,simulation.data,actors,receipts).ok:
		# The old window is invalid. A fresh baseline authorizes only its own tick.
		if hit_history.reset(simulation.epoch,simulation.data).ok: hit_history.record_frame(simulation.tick,simulation.data,actors,[])

func _route_events(events: Array[Dictionary], now: int) -> void:
	for event: Dictionary in events:
		if event.get("resync_required",false):
			for id: int in _streams.keys(): _close_game(registry.session_view(id).game,"event journal requires baseline",now)
			return
	if events.is_empty(): return
	var common := EVENTS.prepare_shared(simulation.epoch,events)
	if not common.ok:
		for id: int in _streams.keys(): _close_game(registry.session_view(id).game,"event serialization failed",now)
		return
	for id: int in _streams.keys():
		var s: Dictionary = _streams[id]
		if s.phase != "live": continue
		var prepared := P.prepare_events(common.events,id)
		if not prepared.ok:
			_close_game(registry.session_view(id).game,"event serialization failed",now)
			continue
		for frame: P.FrozenFrame in prepared.frames:
			var bytes: int = frame.bytes().size()
			if s.event_packets.size() >= MAX_EVENT_FRAMES or s.event_bytes+bytes > MAX_EVENT_BYTES:
				_close_game(registry.session_view(id).game,"event queue requires baseline",now)
				break
			s.event_packets.append({"frame":frame,"bytes":bytes})
			s.event_bytes += bytes

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

func _player_request(id: int, packet: BlockfieldProtocol.Packet, now: int) -> void:
	var actor := simulation.get_actor(id)
	if packet.epoch == simulation.epoch and packet.sequence < actor.spawn_generation: return
	if packet.epoch != simulation.epoch or packet.sequence != actor.spawn_generation or packet.tick > simulation.tick+INPUTS.MAX_FUTURE_TICKS \
			or packet.tick < maxi(0,simulation.tick-INPUTS.MAX_LATE_TICKS) or packet.payload.request_sequence != int(_request_intents.get(id,0))+1:
		_close_game(registry.session_view(id).game,"invalid player request ownership",now)
		return
	var times: Array = _request_times.get(id,[])
	while not times.is_empty() and now-int(times[0]) >= 5000: times.pop_front()
	if times.size() >= 16:
		_close_game(registry.session_view(id).game,"player request rate exceeded",now)
		return
	times.append(now)
	_request_times[id] = times
	_request_intents[id] = packet.payload.request_sequence
	if packet.payload.action == 0:
		if registry.session_view(id).role == 1 and packet.payload.value < 2: return
		simulation.set_team(id,packet.payload.value)
		if actor.team < 2 and actor.health <= 0 and actor.respawn_tick < 0: simulation.spawn_actor(id,actor.team)
	else: simulation.set_block_color(id,packet.payload.value)

func get_stats() -> Dictionary:
	var bulk_windows: Array[Dictionary] = []
	for id: int in _streams:
		var credit: Dictionary = _streams[id].bulk_window.get_stats()
		credit["actor_id"]=id; credit["phase"]=_streams[id].phase
		bulk_windows.append(credit)
	return {"running":running,"tick":simulation.tick if simulation != null else -1,"registry":registry.get_stats(),"loading":_loading_count(),"queued":_queued_count(),
		"streams":_streams.size(),"bulk_windows":bulk_windows,"totals":_totals.duplicate(),"game":game_transport.get_stats(),"map":map_transport.get_stats()}
