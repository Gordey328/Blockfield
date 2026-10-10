extends SceneTree
const SERVER = preload("res://network/server_runtime.gd")
const CLIENT = preload("res://network/client_replica.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const RULES = preload("res://simulation/player_rules.gd")
const WS = preload("res://network/ws_transport.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
const COMPAT = preload("res://network/compatibility.gd")
const P = preload("res://network/protocol.gd")
var assertions: int = 0
var failures: int = 0
var server: SERVER
var endpoints: Dictionary = {}
var probes: Array[Probe] = []
var replicas: Array[CLIENT] = []
var replica_events: Dictionary[int,Array] = {}
var timings: Dictionary = {}
var poll_count: int = 0
var max_queued_frames: int = 0
var max_queued_bytes: int = 0

class Probe extends RefCounted:
	var game := WS.new()
	var bulk := WS.new()
	var transfer := TRANSFER.new()
	var assembler := TRANSFER.TransactionAssembler.new()
	var welcome: P.Packet
	var begin: P.Packet
	var barrier: P.Packet
	var snapshot: P.Packet
	var ready: Dictionary = {}
	var data: VoxelData
	var role: int = 0
	var token: PackedByteArray = PackedByteArray()
	var game_id: int = 0
	var bulk_id: int = 0
	var map_port: int = 0
	var allow_game: bool = true
	var allow_bulk: bool = true
	var allow_decode: bool = true
	var auto_ready: bool = true
	var ready_sent: bool = false
	var closed: bool = false
	var errors: Array[String] = []
	var effects: Array[Dictionary] = []
	var transactions: Array[Dictionary] = []
	var event_packets: Array[P.Packet] = []
	var snapshots: int = 0
	var chat: Array[Dictionary] = []
	func id() -> int: return welcome.payload.actor_id if welcome != null else 0
	func _hello(map_role: bool = false) -> P.Packet:
		return P.make_packet(P.Kind.HELLO,{"role":2 if map_role else role,"name":"Probe","build_hash":COMPAT.build_hash(),"rules_hash":COMPAT.rules_hash(),
			"resume_token":PackedByteArray() if map_role else token,"bulk_token":welcome.payload.bulk_token if map_role else PackedByteArray()})
	func fail(message: String) -> void:
		if errors.size() < 16: errors.append(message)
	func poll() -> void:
		if allow_game:
			game.poll()
			for event: Dictionary in game.drain_events():
				match event.type:
					"connected":
						if not game.send(game_id,_hello()).ok: fail("HELLO send")
					"closed", "timeout", "protocol_error", "overflow": closed = true
					"packet": _packet(event.packet)
		if allow_bulk:
			bulk.poll()
			for event: Dictionary in bulk.drain_events():
				match event.type:
					"connected":
						if not bulk.send(bulk_id,_hello(true)).ok: fail("bulk HELLO")
					"packet":
						var result: Dictionary = transfer.consume(event.packet)
						if not result.ok: fail(result.error)
		if allow_decode and data == null:
			if transfer.get_stats().status in ["receiving","preparing"]:
				var advanced: Dictionary = transfer.poll(-1,2)
				if not advanced.ok: fail(advanced.error)
			if transfer.get_stats().status == "ready":
				ready = transfer.take_ready(); data = ready.data
				assembler.reset(ready.epoch,ready.map_sequence,data.dimensions,ready.tick)
		if auto_ready and data != null and not ready_sent: send_ready()
	func send_ready() -> bool:
		var packet := P.make_packet(P.Kind.MAP_READY,{"snapshot_id":ready.snapshot_id,"map_sequence":ready.map_sequence,"hash":ready.hash},ready.epoch,ready.tick,ready.map_sequence)
		ready_sent = game.send(game_id,packet).ok
		return ready_sent
	func _packet(packet: P.Packet) -> void:
		match packet.kind:
			P.Kind.WELCOME: welcome = packet
			P.Kind.MAP_BEGIN:
				begin = packet
				var accepted: Dictionary = transfer.consume(packet)
				if not accepted.ok: fail(accepted.error)
				var connected: Dictionary = bulk.start_client("ws://127.0.0.1:%d/map" % map_port)
				if connected.ok: bulk_id = connected.connection_id
				else: fail(connected.error)
			P.Kind.MAP_END:
				barrier = packet
				var accepted: Dictionary = transfer.consume(packet)
				if not accepted.ok: fail(accepted.error)
			P.Kind.MAP_DELTA:
				if not ready_sent:
					var accepted: Dictionary = transfer.consume(packet)
					if not accepted.ok: fail(accepted.error)
				else:
					var accepted: Dictionary = assembler.push(packet)
					if not accepted.ok: fail(accepted.error)
					elif accepted.get("complete",false):
						if not data.apply_transaction(accepted.transaction).ok: fail("live map atomic apply")
						if transactions.size() < 128: transactions.append(accepted.transaction)
			P.Kind.MATCH_STATE: snapshot = packet; snapshots += 1
			P.Kind.GAME_EVENTS:
				if event_packets.size() < 128: event_packets.append(packet)
				for effect: Dictionary in packet.payload.events:
					if effects.size() < 1024: effects.append(effect)
			P.Kind.CHAT:
				if chat.size() < 16: chat.append(packet.payload)
			_: fail("unexpected packet")
	func stop() -> void:
		game.stop(true); bulk.stop(true); transfer.cancel(); assembler.cancel()

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures += 1; push_error("NETWORK_ADVERSARIAL: " + message)
func _run() -> void:
	await _scenario("concurrent_map_barriers",_test_concurrent_map_barriers)
	await _scenario("late_shots_and_privacy",_test_late_shots_and_privacy)
	await _scenario("reconnect_and_hostile_direction",_test_reconnect_and_hostile_direction)
	await _scenario("malformed_socket_frame",_test_malformed_socket_frame)
	await _scenario("bounded_stalled_join",_test_bounded_stalled_join)
	await _scenario("no_read_socket_timeout",_test_no_read_socket_timeout)
	print("NETWORK_ADVERSARIAL: %d assertions, %d failures; polls=%d; max_queue=%dframes/%dbytes; timings_ms=%s" % [assertions,failures,poll_count,max_queued_frames,max_queued_bytes,timings])
	quit(0 if failures == 0 else 1)
func _scenario(name: String, task: Callable) -> void:
	var start: int = Time.get_ticks_msec()
	await task.call()
	timings[name] = Time.get_ticks_msec()-start
	print("NETWORK_ADVERSARIAL scenario %s: %dms" % [name,timings[name]])
	_shutdown()
func _boot(short_timeouts: bool = false) -> void:
	var data: DATA = DATA.new()
	check(data.clear(Vector3i(32,16,32),19) == OK,"canonical small arena")
	data.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x01608070)
	data.seed_box(Vector3i(8,2,8),Vector3i(9,7,9),0x01bbccdd)
	var sim: MATCH = MATCH.new()
	check(sim.configure(data).ok,"shared Match authority")
	server = SERVER.new()
	check(server.configure(sim,COMPAT.build_hash(),COMPAT.rules_hash()),"production codec/runtime compatibility")
	if short_timeouts:
		check(server.game_transport.configure({"idle_timeout_ms":600,"ping_interval_ms":100,"ping_timeout_ms":300,"close_timeout_ms":50}).ok,"bounded no-read timeout fixture")
	endpoints = server.start()
	check(endpoints.ok and endpoints.game_port != endpoints.map_port,"real ephemeral TCP listeners")
func _shutdown() -> void:
	for probe: Probe in probes: probe.stop()
	for replica: CLIENT in replicas: replica.close()
	if server != null:
		server.stop()
		check(server.get_stats().game.connections == 0 and server.get_stats().map.connections == 0,"all test sockets/listeners released")
	probes.clear(); replicas.clear(); replica_events.clear(); server = null
func _probe(resume: PackedByteArray = PackedByteArray(), delayed: bool = false) -> Probe:
	var probe := Probe.new()
	probe.token = resume.duplicate(); probe.map_port = endpoints.map_port
	probe.auto_ready = not delayed; probe.allow_bulk = not delayed; probe.allow_decode = not delayed
	var started: Dictionary = probe.game.start_client("ws://127.0.0.1:%d/play" % endpoints.game_port)
	check(started.ok,"actual probe socket connects")
	probe.game_id = started.connection_id
	probes.append(probe)
	return probe
func _replica() -> CLIENT:
	var replica: CLIENT = CLIENT.new()
	check(replica.connect_to("ws://127.0.0.1:%d/play" % endpoints.game_port,"ws://127.0.0.1:%d/map" % endpoints.map_port,"Replica").ok,"actual complete ClientReplica connects")
	replicas.append(replica); replica_events[replica.get_instance_id()] = []
	return replica
func _pump(frames: int = 1) -> void:
	for _frame in range(frames):
		server.poll()
		for probe: Probe in probes: probe.poll()
		for replica: CLIENT in replicas:
			replica.poll()
			var retained: Array = replica_events[replica.get_instance_id()]
			for event: Dictionary in replica.drain_events():
				if retained.size() >= 1024: retained.pop_front()
				retained.append(event)
		if not server.step_once(): check(false,"fixed authority step failed")
		poll_count += 1
		for transport: WS in [server.game_transport,server.map_transport]:
			for peer: Dictionary in transport.get_stats().peers:
				max_queued_frames = maxi(max_queued_frames,peer.queued_frames)
				max_queued_bytes = maxi(max_queued_bytes,peer.queued_bytes+peer.socket_buffered_bytes)
		await process_frame
func _wait(predicate: Callable, message: String, max_ms: int = 5000, max_polls: int = 1500) -> bool:
	var deadline: int = Time.get_ticks_msec()+max_ms
	var start: int = poll_count
	while not predicate.call() and Time.get_ticks_msec() < deadline and poll_count-start < max_polls: await _pump()
	var result: bool = bool(predicate.call())
	check(result,message)
	return result
func _input(probe: Probe, sequence: int, input_tick: int, buttons: int = RULES.Buttons.PRIMARY, generation: int = -1) -> P.Packet:
	var actor: SharedPlayerState = server.simulation.get_actor(probe.id())
	return P.make_packet(P.Kind.INPUT_BATCH,{"records":[{"input_sequence":sequence,"input_tick":input_tick,"buttons":buttons,"tool":255,"weapon":255,"move_x":0.0,"move_z":0.0,"yaw":0.0,"pitch":0.0}]},19,input_tick,actor.spawn_generation if generation < 0 else generation)
func _commit_remove(cell: Vector3i) -> Dictionary:
	var sim: MATCH = server.simulation
	var tx: Dictionary = sim.data.remove_blocks([cell],false,{"tick":sim.tick+1,"actor_id":0,"action_id":sim.data.map_sequence+1})
	check(tx.ok and tx.changed,"trusted authoritative removal receipt")
	sim._commit(tx)
	return tx
func _commit_color(cell: Vector3i, color: int) -> Dictionary:
	var sim: MATCH = server.simulation
	var tx: Dictionary = sim.data.set_block(cell,color,{"tick":sim.tick+1,"actor_id":0,"action_id":sim.data.map_sequence+1})
	check(tx.ok and tx.changed,"trusted authoritative create/repaint receipt")
	sim._commit(tx)
	return tx
func _hash(data: VoxelData) -> PackedByteArray: return TRANSFER.Helpers.hash_map(data).hash
func _effect_count(events: Array, type: String, owner: int = -1) -> int:
	var result: int = 0
	for event: Dictionary in events:
		if event.get("type") == type and (owner < 0 or event.get("owner_id") == owner): result += 1
	return result

func _test_concurrent_map_barriers() -> void:
	_boot()
	var live: CLIENT = _replica()
	if not await _wait(func(): return live.status == "live","initial complete replica live"): return
	var initial_hash: PackedByteArray = _hash(server.simulation.data)
	var slow_a: Probe = _probe(PackedByteArray(),true)
	var slow_b: Probe = _probe(PackedByteArray(),true)
	if not await _wait(func(): return slow_a.begin != null and slow_b.begin != null,"two concurrent baselines frozen before slow bulk joins"): return
	check(server.get_stats().loading == 2 and slow_a.begin.payload.hash == initial_hash and slow_b.begin.payload.hash == initial_hash,"two immutable baseline identities match the pre-edit authority")
	var removal: Dictionary = _commit_remove(Vector3i(8,2,8))
	var collapsed: int = 0
	for change: Dictionary in removal.changes: if change.flags == 1: collapsed += 1
	check(collapsed == 4,"real authority support removal emits its four ordered collapse cells")
	await _pump()
	_commit_color(Vector3i(20,2,20),0x01112233); await _pump()
	_commit_color(Vector3i(20,2,20),0x01445566); await _pump()
	if not await _wait(func(): return live.data.map_sequence == 3,"live replica applies ordered edits during slow joins"): return
	slow_a.allow_bulk = true; slow_b.allow_bulk = true
	if not await _wait(func(): return slow_a.barrier != null and slow_b.barrier != null,"game-channel barriers arrive while client validation is paused"): return
	check(slow_a.barrier.payload.map_sequence == 3 and slow_b.barrier.payload.map_sequence == 3,"both END barriers select the same completed edit sequence")
	var barrier_hash: PackedByteArray = _hash(server.simulation.data)
	check(slow_a.barrier.payload.hash == barrier_hash and slow_b.barrier.payload.hash == barrier_hash,"END hashes reflect baseline plus whole committed edits")
	_commit_color(Vector3i(20,2,20),0x01778899); await _pump(3)
	check(server.get_stats().loading == 2 and slow_a.snapshot == null and slow_b.snapshot == null,"no actor snapshot/spawn before validated READY")
	slow_a.allow_decode = true; slow_b.allow_decode = true
	if not await _wait(func(): return slow_a.data != null and slow_b.data != null,"both private join decoders validate the pinned END"): return
	check(slow_a.ready.map_sequence == 3 and slow_b.ready.map_sequence == 3 and slow_a.ready.hash == barrier_hash and _hash(slow_a.data) == barrier_hash,"installed baseline stays at its exact barrier despite newer authority edits")
	check(slow_a.send_ready() and slow_b.send_ready(),"actual game sockets send matching READY")
	if not await _wait(func(): return slow_a.snapshot != null and slow_b.snapshot != null and slow_a.data.map_sequence == 4 and slow_b.data.map_sequence == 4 and live.data.map_sequence == 4,"post-barrier edit precedes live matching state for both joins"): return
	check(slow_a.snapshot.payload.map_sequence == 4 and slow_b.snapshot.payload.map_sequence == 4,"ready states match post-barrier terrain")
	check(_hash(live.data) == _hash(server.simulation.data) and slow_a.data.blocks == live.data.blocks and slow_b.data.blocks == live.data.blocks,"three socket-driven replicas converge exactly under edits")
	check(slow_a.errors.is_empty() and slow_b.errors.is_empty() and live.status == "live","ordered two-socket join handles END/chunk/decode timing without errors")
	check(slow_a.transactions.size() == 1 and slow_a.transactions[0].map_sequence == 4,"only complete post-barrier transaction reaches live atomic apply")
	var late: CLIENT = _replica()
	if not await _wait(func(): return late.status == "live","new client joins after support destruction and repaints"): return
	check(late.data.blocks == server.simulation.data.blocks and late.data.map_sequence == 4,"late fresh baseline has authoritative collapsed terrain and latest color")

func _test_late_shots_and_privacy() -> void:
	_boot()
	var shooter: Probe = _probe()
	var target: CLIENT = _replica()
	if not await _wait(func(): return shooter.snapshot != null and target.status == "live","late-shot peers complete production joins"): return
	var a: SharedPlayerState = server.simulation.get_actor(shooter.id())
	var b: SharedPlayerState = server.simulation.get_actor(target.actor_id)
	a.motion = MOTION.create_state(Vector3(12.5,2.01,25.5)); b.motion = MOTION.create_state(Vector3(12.5,2.01,15.5))
	a.tool_raise = 1; b.tool_raise = 1
	await _pump(3)
	var old_tick: int = server.simulation.tick
	for _move in range(11):
		check(target.submit_input(0,Vector2.RIGHT,0.0,0.0).ok,"authenticated moving-target command")
		await _pump()
	await _pump()
	check(server.simulation.raycast_actors(a.player_id,a.motion.physics_eye(),Vector3.FORWARD).is_empty(),"current moving target misses the retained old ray")
	var before: int = a.magazine
	check(shooter.game.send(shooter.game_id,_input(shooter,1,old_tick)).ok,"socket submits a late admitted command, never a hit or position")
	if not await _wait(func(): return a.consumed_input_sequence == 1,"late command admitted and consumed",2000,120): return
	check(b.health < 100 and a.magazine == before-1 and server.simulation.get_rewind_stats().applied_player_hits == 1,"real Runtime uses admitted old actor/terrain state for moving-target damage")
	await _pump(5)
	var victim_effects: Array = replica_events[target.get_instance_id()]
	check(_effect_count(shooter.effects,"hit_confirmed",a.player_id) == 1 and _effect_count(victim_effects,"hit_confirmed",a.player_id) == 0,"private hit confirmation reaches its shooter only")
	check(_effect_count(shooter.effects,"hurt",b.player_id) == 0 and _effect_count(victim_effects,"hurt",b.player_id) == 1,"private hurt event reaches its victim only")
	check(_effect_count(shooter.effects,"shot",a.player_id) == 1 and _effect_count(victim_effects,"shot",a.player_id) == 1,"public confirmed shot reaches both authenticated peers")
	check(shooter.snapshot.payload.owner_state.player_id == a.player_id,"full private snapshot belongs to its actual socket owner")
	for public_actor: Dictionary in shooter.snapshot.payload.actors:
		check(not public_actor.has("magazine") and not public_actor.has("reserve") and not public_actor.has("shot_rng") and not public_actor.has("input_buttons"),"public actor projection contains no private resources/RNG/controls")
	var fresh: Dictionary = server.simulation.add_actor("Fresh target",1)
	check(fresh.ok,"trusted fresh target fixture")
	var victim: SharedPlayerState = server.simulation.get_actor(fresh.actor_id)
	victim.motion = MOTION.create_state(Vector3(12.5,2.01,15.5)); victim.tool_raise = 1
	await _pump(2)
	server.hit_history.cancel("adversarial test fresh-window recovery")
	a.next_shot_tick = server.simulation.tick+1
	var denied_before: int = server.simulation.get_rewind_stats().denied_shots
	var stale_tick: int = server.simulation.tick-4
	check(shooter.game.send(shooter.game_id,_input(shooter,2,stale_tick)).ok,"valid late command sent across a history reset")
	if not await _wait(func(): return a.consumed_input_sequence == 2,"post-reset old command still admits through input window",2000,120): return
	check(victim.health == 100 and server.simulation.get_rewind_stats().denied_shots == denied_before+1,"missing old history denies damage with a bounded diagnostic, no current-state fallback")
	check(a.magazine == before-2 and a.connected,"authorized denied shot retains ammo and connection")

func _test_reconnect_and_hostile_direction() -> void:
	_boot()
	var first: Probe = _probe(); var unaffected: CLIENT = _replica()
	if not await _wait(func(): return first.snapshot != null and unaffected.status == "live","reconnect peers live"): return
	var actor: SharedPlayerState = server.simulation.get_actor(first.id())
	var original_id: int = actor.player_id
	var original_generation: int = actor.spawn_generation
	var old_token: PackedByteArray = first.welcome.payload.resume_token.duplicate()
	first.stop()
	if not await _wait(func(): return not actor.connected,"real disconnect relinquishes game/bulk ownership"): return
	var resumed: Probe = _probe(old_token)
	if not await _wait(func(): return resumed.snapshot != null,"resume repeats actual map/hash/state barrier"): return
	check(resumed.id() == original_id and resumed.welcome.payload.resume_token != old_token and server.simulation.actors.size() == 2,"rotated resume preserves stable actor without duplicate allocation")
	var stale_resume: Probe = _probe(old_token)
	if not await _wait(func(): return stale_resume.closed,"rotated old token cannot take over active owner"): return
	check(stale_resume.welcome == null and actor.connected and server.simulation.actors.size() == 2,"rejected capability does not allocate a duplicate actor")
	server.simulation.damage_actor(actor.player_id,100)
	var respawn_deadline: int = actor.respawn_tick
	await _pump(RULES.RESPAWN_TICKS-1)
	check(server.simulation.tick == respawn_deadline-1 and not actor.is_alive() and actor.spawn_generation == original_generation,"network actor remains dead through the tick before its deadline")
	await _pump()
	check(server.simulation.tick == respawn_deadline and actor.is_alive() and actor.spawn_generation == original_generation+1,"Runtime automatically respawns exactly at the authoritative deadline")
	await _pump(3)
	check(actor.spawn_generation > original_generation and actor.health == 100,"authority new life is reflected in network state")
	var stock: int = actor.magazine
	var stale: P.Packet = _input(resumed,100,server.simulation.tick,RULES.Buttons.PRIMARY,original_generation)
	check(resumed.game.send(resumed.game_id,stale).ok,"actual TCP carries delayed old-generation input")
	await _pump(4)
	check(actor.connected and actor.magazine == stock and actor.consumed_input_sequence == 0,"stale old-life command is ignored without damaging/refilling/closing new life")
	var team: int = actor.team
	var old_request: P.Packet = P.make_packet(P.Kind.PLAYER_REQUEST,{"action":0,"value":2,"request_sequence":100},19,server.simulation.tick,original_generation)
	check(resumed.game.send(resumed.game_id,old_request).ok,"actual TCP carries delayed old-generation team request")
	await _pump(3)
	check(actor.team == team and actor.connected,"stale old-life team intent cannot change the new generation")
	check(resumed.game.send(resumed.game_id,_input(resumed,1,server.simulation.tick+1,0)).ok,"new generation starts its owned contiguous stream")
	if not await _wait(func(): return actor.consumed_input_sequence == 1,"current generation input accepted"): return
	var forged: P.Packet = _input(resumed,2,server.simulation.tick+1,0)
	forged.payload.records[0].damage = 1000
	check(not P.encode(forged).ok,"no schema permits a client-supplied damage field")
	if resumed.event_packets.is_empty(): check(false,"actual public event packet available for hostile-direction test"); return
	check(resumed.game.send(resumed.game_id,resumed.event_packets[0]).ok,"attacker returns a valid typed server event on client game channel")
	if not await _wait(func(): return not actor.connected,"wrong-direction event closes only its authenticated sender"): return
	var continued: int = unaffected.get_stats().server_tick
	await _pump(6)
	check(unaffected.status == "live" and unaffected.get_stats().server_tick > continued and server.running,"other replica and authority continue after hostile direction")

func _test_malformed_socket_frame() -> void:
	_boot()
	var attacker: Probe = _probe(); var healthy: CLIENT = _replica()
	if not await _wait(func(): return attacker.snapshot != null and healthy.status == "live","malformed-frame actual peers live"): return
	var actor: SharedPlayerState = server.simulation.get_actor(attacker.id())
	var encoded: P.Result = P.encode(_input(attacker,1,server.simulation.tick+1,0))
	check(encoded.ok,"valid input wire frame before controlled byte corruption")
	var hostile: PackedByteArray = encoded.bytes.duplicate()
	# Header24,count1,sequence4,tick4,buttons2,tool1,weapon1,moveX4,moveZ4.
	var yaw_offset: int = 24+1+4+4+2+1+1+4+4
	hostile[yaw_offset] = 0x7f; hostile[yaw_offset+1] = 0xc0; hostile[yaw_offset+2] = 0; hostile[yaw_offset+3] = 0
	var peer: WebSocketPeer = attacker.game._connections[attacker.game_id].socket
	check(peer.put_packet(hostile) == OK,"real WebSocket transmits an IEEE754NaN aim field")
	if not await _wait(func(): return not actor.connected,"server transport rejects nonfinite direction and disconnects its owner"): return
	check(server.get_stats().game.totals.protocol_errors == 1 and actor.consumed_input_sequence == 0,"malformed frame never reaches authoritative input admission")
	await _pump(6)
	check(healthy.status == "live" and server.simulation.get_actor(healthy.actor_id).connected,"malformed actual socket does not break unrelated healthy replica")

func _test_bounded_stalled_join() -> void:
	_boot()
	var live: CLIENT = _replica()
	if not await _wait(func(): return live.status == "live","queue fixture healthy live replica"): return
	var stalled: Probe = _probe(PackedByteArray(),true)
	stalled.allow_bulk = true
	if not await _wait(func(): return stalled.barrier != null,"delayed client reaches barrier but withholds READY"): return
	var id: int = stalled.id()
	check(server.get_stats().loading == 1,"stalled join retained explicitly")
	var color: int = 0x01000001
	for index in range(TRANSFER.MAX_TRANSACTIONS+1):
		color = 0x01000001+(index%2)
		_commit_color(Vector3i(20,2,20),color)
		await _pump()
		if server._streams.has(id):
			check(server._streams[id].pending.size() <= TRANSFER.MAX_TRANSACTIONS and server._streams[id].changes <= TRANSFER.MAX_BUFFERED_CHANGES and server._streams[id].bytes <= TRANSFER.MAX_BUFFERED_BYTES,"retained stalled stream stays within all map budgets")
	check(not server.simulation.get_actor(id).connected and not server._streams.has(id),"129th pending transaction explicitly closes and releases stalled join")
	if not await _wait(func(): return live.data.map_sequence == server.simulation.data.map_sequence,"healthy replica catches up after slow-peer overflow"): return
	check(live.status == "live" and live.data.blocks == server.simulation.data.blocks and server.get_stats().loading == 0,"slow join overflow does not stop healthy map replication")
	check(max_queued_frames <= WS.MAX_QUEUE_FRAMES and max_queued_bytes <= WS.MAX_OUTBOUND_BYTES,"actual transport queues remain bounded throughout pressure")

func _test_no_read_socket_timeout() -> void:
	_boot(true)
	var stalled: Probe = _probe(); var live: CLIENT = _replica()
	if not await _wait(func(): return stalled.snapshot != null and live.status == "live","no-read fixture real socket peers ready",4000): return
	var id: int = stalled.id()
	stalled.allow_game = false; stalled.allow_bulk = false
	var start: int = Time.get_ticks_msec()
	if not await _wait(func(): return not server.simulation.get_actor(id).connected,"non-polling actual socket fails its heartbeat explicitly",2500,700): return
	var elapsed: int = Time.get_ticks_msec()-start
	check(elapsed < 2000 and server.get_stats().game.totals.timeouts >= 1,"no-read timeout occurs within bounded configured deadline")
	await _pump(4)
	check(live.status == "live" and server.simulation.get_actor(live.actor_id).connected,"polling healthy client survives stalled peer timeout")
	check(not server._streams.has(id) and not server._inputs.has(id),"timeout releases owner queues and map/event stream")
	check(max_queued_frames <= WS.MAX_QUEUE_FRAMES and max_queued_bytes <= WS.MAX_OUTBOUND_BYTES,"actual stalled TCP connection never grows beyond transport budgets")
