extends SceneTree
## Real sockets with a trusted preparation-work gate; no Main or preferences.
const SERVER = preload("res://network/server_runtime.gd")
const CLIENT = preload("res://network/client_replica.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const P = preload("res://network/protocol.gd")
const COMPAT = preload("res://network/compatibility.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
var assertions := 0
var failures := 0
var server: PausedQueueRuntime
var clients: Array[CLIENT] = []
var endpoints := {}
var gates: Array[JobGate] = []
var polls := 0

class JobGate extends RefCounted:
	var job: RefCounted
	var held := true
	func advance(max_chunks: int = 1) -> Dictionary:
		return {"ok":true,"error":"","done":false} if held else job.advance(max_chunks)
	func take_sender() -> Dictionary: return job.take_sender()
	func cancel() -> void:
		if job != null: job.cancel()
		job = null

class PausedQueueRuntime extends SERVER:
	var pause_queue_admission := false
	func _poll_stream(id: int, now: int) -> void:
		if pause_queue_admission and _streams.has(id) and _streams[id].phase == "queued": return
		super._poll_stream(id,now)

class SilentTransport extends TRANSPORT:
	func stop(_force: bool = false) -> void: pass
	func drain_events(_max_count: int = 64) -> Array[Dictionary]: return []

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error("LONG RESET: " + message)
func make_map(epoch: int) -> DATA:
	var data := DATA.new(); data.clear(Vector3i(64,16,64),epoch)
	data.seed_box(Vector3i.ZERO,Vector3i(64,4,64),0x01557766)
	return data
func welcome(epoch: int = 7, id: int = 43, profile: int = 0) -> P.Packet:
	var token := PackedByteArray(); token.resize(32); token.fill(epoch)
	return P.make_packet(P.Kind.WELCOME,{"actor_id":id,"spawn_generation":1,"profile":profile,"server_hz":60,"snapshot_hz":20,"build_hash":COMPAT.build_hash(),"rules_hash":COMPAT.rules_hash(),"resume_token":token,"bulk_token":token.duplicate()},epoch)
func announcement(epoch: int = 9, id: int = 43, profile: int = 1) -> P.Packet:
	return P.make_packet(P.Kind.MATCH_PREPARING,{"actor_id":id,"spawn_generation":1,"profile":profile},epoch,0,1)
func wire(packet: P.Packet) -> P.Packet:
	var encoded := P.encode(packet)
	check(encoded.ok,"preparation fixture is a valid wire packet")
	var decoded := P.decode(encoded.bytes)
	check(decoded.ok,"preparation fixture survives strict wire decode")
	return decoded.packet
func fake_bound() -> CLIENT:
	var client := CLIENT.new(); client.game = SilentTransport.new(); client.bulk = SilentTransport.new()
	client.status = "joining"; client._game_packet(wire(welcome())); client.status = "live"
	return client
func test_packet_states() -> void:
	for fault in ["stale","duplicate","announce_actor","actor","profile","future_welcome","unannounced","baseline_before_welcome","future_baseline","future_state","state_profile","initial_duplicate","status"]:
		var client := fake_bound()
		if fault != "unannounced": client._game_packet(wire(announcement()))
		check(client.status == ("live" if fault == "unannounced" else "preparing"),"valid greater announcement binds a preparing state")
		match fault:
			"stale": client._game_packet(wire(announcement(7)))
			"duplicate": client._game_packet(wire(announcement()))
			"announce_actor": client._game_packet(wire(announcement(10,99)))
			"actor": client._game_packet(wire(welcome(9,99,1)))
			"profile": client._game_packet(wire(welcome(9,43,0)))
			"future_welcome": client._game_packet(wire(welcome(10,43,1)))
			"unannounced": client._game_packet(wire(welcome(9,43,1)))
			"baseline_before_welcome":
				var sender: TRANSFER.BaselineSender = TRANSFER.make_sender(make_map(9),1).sender
				client._game_packet(wire(sender.begin_packet())); sender.cancel()
			"future_baseline":
				client._game_packet(wire(welcome(9,43,1)))
				var sender: TRANSFER.BaselineSender = TRANSFER.make_sender(make_map(10),1).sender
				client._game_packet(wire(sender.begin_packet())); sender.cancel()
			"future_state", "state_profile":
				client._game_packet(wire(welcome(9,43,1)))
				client.data = make_map(9); client.status = "synchronizing"
				var simulation := MATCH.new()
				var packet_epoch := 10 if fault == "future_state" else 9
				check(simulation.configure(make_map(packet_epoch),"0.75").ok,"explicit mismatched state fixture configures")
				check(simulation.add_actor("Guest",0,1,Vector3.INF,43).ok,"explicit mismatched state fixture owns canonical actor")
				simulation.step_fixed()
				var converted: Dictionary = P.SIMULATION_CODEC.from_snapshot(simulation.snapshot_for(43))
				check(converted.ok,"future/profile-mismatched snapshot has valid complete replay schema")
				client._game_packet(wire(P.make_packet(P.Kind.MATCH_STATE,converted.payload,packet_epoch,simulation.tick,simulation.get_actor(43).spawn_generation)))
			"initial_duplicate":
				client._game_packet(wire(welcome(9,43,1))); client._game_packet(wire(welcome(9,43,1)))
			"status":
				client.status = "connecting"; client._game_packet(wire(announcement(10)))
		check(client.status == "failed" and client.get_owner_state() == null and client.data == null and client._welcome == null,"%s packets fail closed without old state or capabilities" % fault)
		client.close()
	var initial := CLIENT.new(); initial.game = SilentTransport.new(); initial.bulk = SilentTransport.new(); initial.status = "joining"
	initial._game_packet(wire(announcement(99,73,0)))
	check(initial.status == "preparing" and initial.actor_id == 73 and initial.epoch == 99 and initial._welcome == null,"initial admitted connection binds ID before its first delayed WELCOME")
	initial._game_packet(wire(announcement(108,73,1)))
	check(initial.status == "preparing" and initial.epoch == 108,"another reset during preparation supersedes the announced epoch")
	initial._game_packet(wire(welcome(108,73,1)))
	check(initial.status == "joining" and initial._welcome.payload.profile == 1,"only exact most recent announced WELCOME opens joining")
	initial.close()

func bad_water_cases() -> Array[Vector2]:
	return [Vector2(2,2),Vector2(1,3),Vector2(NAN,2),Vector2(INF,2),Vector2(1,NAN),Vector2(1,INF),Vector2(-1,2)]
func test_water_configure() -> void:
	var initial := MATCH.new(); initial.configure(make_map(3))
	var runtime := SERVER.new(); check(runtime.configure(initial,COMPAT.build_hash(),COMPAT.rules_hash()),"default physical water network boundary configures")
	var hello := P.make_packet(P.Kind.HELLO,{"role":0,"name":"Existing registry owner","build_hash":COMPAT.build_hash(),"rules_hash":COMPAT.rules_hash(),"resume_token":PackedByteArray(),"bulk_token":PackedByteArray()})
	check(runtime.registry.admit_game(501,hello,0,runtime._allocate_actor).ok,"configured runtime owns pre-existing registry credentials")
	var sessions := runtime.registry._sessions.duplicate(true)
	var games := runtime.registry._games.duplicate(true)
	runtime._spawn_teams[43] = 1; runtime._chat_sequence = 7
	for levels: Vector2 in bad_water_cases():
		var map := make_map(4); map.water_level = levels.x; map.wade_origin_level = levels.y
		var custom := MATCH.new(); check(custom.configure(map).ok,"standalone Match retains its custom query metadata support")
		check(not runtime.configure(custom,COMPAT.build_hash(),COMPAT.rules_hash()) and runtime.simulation == initial and runtime.registry.epoch == 3 and runtime.registry._sessions == sessions and runtime.registry._games == games and runtime._spawn_teams == {43:1} and runtime._chat_sequence == 7,"invalid/nonfinite water configuration preserves existing registry credentials/bindings and runtime state")
	runtime.stop()
func test_water_reset() -> void:
	var current := server.simulation
	var old_streams := server._streams.duplicate(true)
	var old_sessions := server.registry._sessions.duplicate(true)
	var old_epoch := server.registry.epoch
	var old_tick := current.tick
	var tokens: Array[PackedByteArray] = []
	for client: CLIENT in clients: tokens.append(client.resume_token())
	for levels: Vector2 in bad_water_cases():
		var map := make_map(12); map.water_level = levels.x; map.wade_origin_level = levels.y
		var result := server.reset_match(map)
		check(not result.ok and server.simulation == current and server.simulation.data == current.data and current.tick == old_tick and server.registry.epoch == old_epoch and server.registry._sessions == old_sessions and server._streams == old_streams,"invalid/nonfinite reset water leaves authority/epoch/map/streams/capabilities unchanged")
		for index in range(clients.size()): check(clients[index].status == "live" and clients[index].epoch == old_epoch and clients[index].resume_token() == tokens[index],"rejected water reset leaves client identities/readiness/credentials untouched")

func pump() -> void:
	server.poll()
	for client: CLIENT in clients:
		client.poll(); client.drain_events()
	check(server.step_once(),"authority fixed step continues during preparation")
	check(server.get_stats().loading <= SERVER.MAX_JOINS,"active preparation/join slot count remains bounded")
	polls += 1
	await process_frame
func wait_until(predicate: Callable, label: String, seconds: int = 12) -> bool:
	var deadline := Time.get_ticks_msec() + seconds*1000
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): check(true,label); return true
		for client: CLIENT in clients:
			if client.status == "failed": check(false,label+": "+client.last_error); return false
		await pump()
	check(false,label+" deadline"); return false
func all_live(epoch: int) -> bool:
	for client: CLIENT in clients:
		if client.status != "live" or client.epoch != epoch: return false
	return true
func run() -> void:
	test_packet_states()
	test_water_configure()
	var sim := MATCH.new(); check(sim.configure(make_map(11),"0.75","ctf").ok,"initial actual match")
	server = PausedQueueRuntime.new(); check(server.configure(sim,COMPAT.build_hash(),COMPAT.rules_hash()),"native runtime configured")
	endpoints = server.start(); check(endpoints.ok,"paired actual TCP/WebSocket listeners")
	for index in range(3):
		var client := CLIENT.new()
		check(client.connect_to("ws://127.0.0.1:%d/play" % endpoints.game_port,"ws://127.0.0.1:%d/map" % endpoints.map_port,"Delayed%d" % index).ok,"actual client socket starts")
		clients.append(client)
		if not await wait_until(func(): return all_live(11),"sequential initial map/state barrier"): finish(); return
	var grace := CLIENT.new()
	check(grace.connect_to("ws://127.0.0.1:%d/play" % endpoints.game_port,"ws://127.0.0.1:%d/map" % endpoints.map_port,"Resume candidate").ok,"actual future grace owner connects")
	clients.append(grace)
	if not await wait_until(func(): return all_live(11),"eligible resume owner completes old map barrier"): finish(); return
	var grace_id := grace.actor_id
	test_water_reset()
	var ids: Array[int] = []; var old_tokens: Array[PackedByteArray] = []
	for client: CLIENT in clients.slice(0,3):
		ids.append(client.actor_id); old_tokens.append(client.resume_token())
	check(clients[0].submit_input(0,Vector2(.2,0),0,0).ok,"old timeline contains a genuine predicted command")
	server.pause_queue_admission = true
	check(server.reset_match(make_map(29),"0.76","tc").ok,"greater map epoch reset queues all owners")
	# Trusted fixture keeps a valid new-epoch resume credential without logging
	# or publishing it. Admission must reject even this eligible grace owner.
	var resume_credential: PackedByteArray = server._streams[grace_id].welcome.payload.resume_token.duplicate()
	grace.close(); clients.erase(grace)
	if not await wait_until(func(): return server.registry.session_view(grace_id).game == 0,"actual disconnected owner enters current-epoch grace"): finish(); return
	check(server._queued_count() == 3 and server.get_stats().loading == 0,"retained-owner FIFO guard is tested with available active slots")
	var actor_count := server.simulation.actors.size()
	for resume: PackedByteArray in [PackedByteArray(),resume_credential]:
		var probe := CLIENT.new()
		check(probe.connect_to("ws://127.0.0.1:%d/play" % endpoints.game_port,"ws://127.0.0.1:%d/map" % endpoints.map_port,"No overtaking",false,resume).ok,"fresh/resume admission probe opens actual socket")
		var admission_deadline := Time.get_ticks_msec()+5000
		while probe.status != "failed" and Time.get_ticks_msec() < admission_deadline:
			await pump(); probe.poll(); probe.drain_events()
		check(probe.status == "failed" and server.get_stats().loading == 0 and server._queued_count() == 3 and server.simulation.actors.size() == actor_count and server.registry.session_view(grace_id).game == 0,"new and valid-resume admissions cannot overtake retained owners when slots are free")
		probe.close()
	resume_credential.clear()
	server.pause_queue_admission = false
	# The first poll sends MATCH_PREPARING before bounded hash preparation.
	server.poll()
	for stream: Dictionary in server._streams.values():
		if stream.phase == "prepare":
			var gate := JobGate.new(); gate.job = stream.job; stream.job = gate; gates.append(gate)
	check(gates.size() == 2 and server._streams[ids[2]].phase == "queued","two real preparation jobs gated; third owner waits without a clone")
	if not await wait_until(func():
		for client: CLIENT in clients:
			if client.status != "preparing": return false
		return true,"all reset announcements delivered before delayed WELCOME"): finish(); return
	var now := Time.get_ticks_msec()
	server._streams[ids[2]].started = now-SERVER.JOIN_TIMEOUT_MS-1
	server._streams[ids[2]].queued_at = now-SERVER.JOIN_TIMEOUT_MS-1
	# Tokens may expire while trusted preparation runs; only WELCOME refreshes them.
	for id: int in ids: server.registry._sessions[id].bulk_expires = now-1
	for step in range(320):
		for index in range(clients.size()):
			var client := clients[index]
			check(not client.submit_input(0,Vector2.ONE,.2,.1).ok and not client.send_chat("waiting") and not client.request_team(1),"owner intentions remain paused for more than256 command steps")
			check(client.status == "preparing" and client.actor_id == ids[index] and client.epoch == 29 and client.prediction.get_status().pending == 0 and client._welcome == null and client.data == null,"delay preserves canonical identity without stale prediction/map/capabilities")
		await pump()
	check(server._streams[ids[2]].phase == "queued" and clients[2].status == "preparing","queued owner survives old240s timestamp independently of active timeout")
	for gate: JobGate in gates: gate.held = false
	if not await wait_until(func(): return all_live(29),"delayed and queued owners finish exact new map/state barriers",20): finish(); return
	check(server._streams[ids[2]].started > now,"queued admission starts a fresh active deadline")
	for index in range(clients.size()):
		var client := clients[index]
		check(client.actor_id == ids[index] and client.data.epoch == 29 and client.data.blocks == server.simulation.data.blocks and client.get_owner_state().profile == "0.76","delayed transfer installs correct epoch/profile/map without changing owner")
		check(client.resume_token() != old_tokens[index] and client.submit_input(0,Vector2.ZERO,0,0).sequence == 1,"new credentials and prediction sequence start after readiness")
	check(server.get_stats().totals.input_rejections == 0,"paused delay produces no invalid/overflowed server command stream")
	# A client cannot announce authority epochs; the typed direction remains denied.
	check(clients[0].game.send(clients[0]._game_id,announcement(30,ids[0],1)).ok,"malicious typed client announcement traverses an actual socket")
	var deadline := Time.get_ticks_msec()+5000
	while clients[0].status != "failed" and Time.get_ticks_msec() < deadline: await pump()
	check(clients[0].status == "failed" and server.simulation.epoch == 29 and clients[1].status == "live","client epoch announcement is rejected without changing authority/other owners")
	# Bounded queue waiting is terminal; it does not turn into an infinite grace.
	check(server.reset_match(make_map(40)).ok,"next reset prepares remaining owners")
	var queue_id := ids[2]
	var stream: Dictionary = server._streams[queue_id]
	stream.queued_at = Time.get_ticks_msec()-SERVER.MAX_QUEUE_WAIT_MS
	server._poll_stream(queue_id,Time.get_ticks_msec())
	check(not server._streams.has(queue_id) and server.registry.session_view(queue_id).game == 0,"queue expiry explicitly disconnects and clears its retained stream")
	finish()
func finish() -> void:
	for client: CLIENT in clients: client.close()
	if server != null:
		server.stop()
		check(server.game_transport.get_stats().connections == 0 and server.map_transport.get_stats().connections == 0 and server._streams.is_empty(),"all sockets/jobs/queued streams cleanly stop")
	gates.clear(); clients.clear(); server = null
	print("LONG RESET: %d assertions, %d failures; polls=%d" % [assertions,failures,polls])
	quit(0 if failures == 0 else 1)
