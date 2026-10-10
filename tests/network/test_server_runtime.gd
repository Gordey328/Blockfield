extends SceneTree
const RUNTIME = preload("res://network/server_runtime.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
const P = preload("res://network/protocol.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
var assertions := 0
var failures := 0
var server: RUNTIME
var clients: Array = []
var build_hash := "runtime-test-build".sha256_buffer()
var rules_hash := "runtime-test-rules".sha256_buffer()
var game_port := 0
var map_port := 0

class TestClient extends RefCounted:
	var game := TRANSPORT.new()
	var bulk := TRANSPORT.new()
	var transfer := TRANSFER.new()
	var assembler := TRANSFER.TransactionAssembler.new()
	var welcome: P.Packet
	var snapshot: P.Packet
	var ready_data: VoxelData
	var chats: Array[P.Packet] = []
	var errors: Array[String] = []
	var closed := false
	var ready_sent := false
	var ack_enabled := true
	var defer_final_ack := false
	var snapshot_count := 0
	var role := 0
	var resume: PackedByteArray = PackedByteArray()
	var epoch := 0
	var game_id := 0
	var bulk_id := 0
	var map_port := 0
	var build_hash: PackedByteArray
	var rules_hash: PackedByteArray
	func hello(bulk_role: bool = false) -> P.Packet:
		return P.make_packet(P.Kind.HELLO,{"role":2 if bulk_role else role,"name":"Guest",
			"build_hash":build_hash,"rules_hash":rules_hash,"resume_token":PackedByteArray() if bulk_role else resume,
			"bulk_token":welcome.payload.bulk_token if bulk_role else PackedByteArray()})
	func poll() -> void:
		game.poll()
		bulk.poll()
		for event: Dictionary in game.drain_events():
			match event.type:
				"connected": game.send(game_id,hello())
				"closed": closed = true
				"protocol_error", "timeout", "overflow": errors.append(event.type)
				"packet":
					var packet: P.Packet = event.packet
					match packet.kind:
						P.Kind.WELCOME: welcome = packet; epoch = packet.epoch
						P.Kind.MAP_BEGIN:
							var result := transfer.consume(packet)
							if not result.ok: errors.append(result.error)
							var connected := bulk.start_client("ws://127.0.0.1:%d/map" % map_port)
							if connected.ok: bulk_id = connected.connection_id
							else: errors.append(connected.error)
						P.Kind.MAP_END:
							var result := transfer.consume(packet)
							if not result.ok: errors.append(result.error)
						P.Kind.MAP_DELTA:
							if not ready_sent:
								var result := transfer.consume(packet)
								if not result.ok: errors.append(result.error)
							else:
								var result := assembler.push(packet)
								if not result.ok: errors.append(result.error)
								elif result.get("complete",false) and not ready_data.apply_transaction(result.transaction).ok: errors.append("live apply failed")
						P.Kind.SNAPSHOT, P.Kind.MATCH_STATE: snapshot = packet; snapshot_count += 1
						P.Kind.CHAT: chats.append(packet)
		for event: Dictionary in bulk.drain_events():
			match event.type:
				"connected": bulk.send(bulk_id,hello(true))
				"protocol_error", "timeout", "overflow": errors.append(event.type)
				"packet":
					var result := transfer.consume(event.packet)
					if not result.ok: errors.append(result.error)
					elif ack_enabled:
						var acknowledgment := transfer.get_chunk_ack()
						if not acknowledgment.ok: errors.append(acknowledgment.error)
						else:
							if not defer_final_ack or acknowledgment.packet.payload.received_bytes!=event.packet.payload.total_size:
								var sent := bulk.send(bulk_id,acknowledgment.packet)
								if not sent.ok: errors.append(sent.error)
		if not ready_sent:
			var stats := transfer.get_stats()
			if stats.status in ["receiving","preparing"]:
				var result := transfer.poll(-1,2)
				if not result.ok: errors.append(result.error)
			if transfer.get_stats().status == "ready":
				var ready := transfer.take_ready()
				ready_data = ready.data
				assembler.reset(ready.epoch,ready.map_sequence,ready.data.dimensions,ready.tick)
				var packet := P.make_packet(P.Kind.MAP_READY,{"snapshot_id":ready.snapshot_id,"map_sequence":ready.map_sequence,"hash":ready.hash},ready.epoch,ready.tick,ready.map_sequence)
				if game.send(game_id,packet).ok: ready_sent = true
	func stop() -> void:
		game.stop(true)
		bulk.stop(true)
		transfer.cancel()
		assembler.cancel()

func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("SERVER RUNTIME: "+message)
func client(resume: PackedByteArray = PackedByteArray(), role: int = 0) -> TestClient:
	var result := TestClient.new()
	result.build_hash = build_hash.duplicate()
	result.rules_hash = rules_hash.duplicate()
	result.resume = resume.duplicate()
	result.role = role
	result.map_port = map_port
	var connected := result.game.start_client("ws://127.0.0.1:%d/play" % game_port)
	check(connected.ok,"real game socket connects")
	result.game_id = connected.connection_id
	clients.append(result)
	return result
func pump(frames: int = 1) -> void:
	for _frame in range(frames):
		server.poll()
		for c: TestClient in clients: c.poll()
		check(server.step_once(),"canonical server step")
		await process_frame
func wait_until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await pump()
	check(predicate.call(),message)
func input_packet(c: TestClient, sequence: int, buttons: int, move: Vector2 = Vector2.ZERO) -> P.Packet:
	var owner := server.simulation.get_actor(c.welcome.payload.actor_id)
	var tick := server.simulation.tick+1
	return P.make_packet(P.Kind.INPUT_BATCH,{"records":[{"input_sequence":sequence,"input_tick":tick,"buttons":buttons,"tool":255,"weapon":255,
		"move_x":move.x,"move_z":move.y,"yaw":0.0,"pitch":0.0}]},owner.match_epoch,tick,owner.spawn_generation)

func _run() -> void:
	var data := DATA.new()
	data.clear(Vector3i(32,16,32),7)
	for z in range(32):
		for x in range(32):
			for y in range(4): data.blocks[data.index(Vector3i(x,y,z))] = 0x01808080
	var simulation := SIMULATION.new()
	check(simulation.configure(data).ok,"pure authority config")
	server = RUNTIME.new()
	check(server.configure(simulation,build_hash,rules_hash),"runtime config")
	var started := server.start()
	check(started.ok and started.game_port != started.map_port,"two actual native listeners")
	game_port = started.game_port
	map_port = started.map_port
	var first := client()
	var second := client()
	await wait_until(func():return first.snapshot != null and second.snapshot != null,"two clients install maps and receive authority snapshots")
	check(first.errors.is_empty() and second.errors.is_empty(),"two-socket transfer has no protocol errors: %s %s" % [first.errors,second.errors])
	if first.snapshot == null or second.snapshot == null:
		finish()
		return
	var first_id: int = first.welcome.payload.actor_id
	var second_id: int = second.welcome.payload.actor_id
	check(first_id != second_id and first_id > 0 and second_id > 0,"distinct stable actor owners")
	check(first.ready_data.blocks == data.blocks and second.ready_data.blocks == data.blocks,"both baseline hashes yield exact terrain")
	check(first.snapshot.payload.owner_state.player_id == first_id and second.snapshot.payload.owner_state.player_id == second_id,"snapshots routed to owner only")
	check(first.snapshot.payload.actors.size() == 2 and simulation.actors.size() == 2,"bulk sockets cannot create duplicate actors")
	var a := simulation.get_actor(first_id)
	var b := simulation.get_actor(second_id)
	a.motion = MOTION.create_state(Vector3(12.5,4.01,20.5))
	b.motion = MOTION.create_state(Vector3(12.5,4.01,12.5))
	a.tool_raise = 1
	b.tool_raise = 1
	check(first.game.send(first.game_id,input_packet(first,1,16)).ok,"client sends intent, no hits")
	await wait_until(func():return a.consumed_input_sequence == 1,"owner command acknowledged")
	check(a.magazine == 9 and b.magazine == 10,"authority fires only connection owner's weapon")
	check(b.health < 100,"actual source ray/hit volume damages other actor")
	await pump(8)
	check(a.input_buttons == 0 and a.input_move == Vector2.ZERO,"lost input lease neutralizes held controls")
	await pump(100)
	var before_stale := {"feet":a.feet(),"magazine":a.magazine,"reserve":a.reserve,"blocks":a.blocks,"grenades":a.grenades,"weapon":a.weapon,"tool":a.tool,"health":b.health,"map_sequence":data.map_sequence}
	var stale := input_packet(first,2,127,Vector2(0,-1))
	stale.tick = simulation.tick-16
	stale.payload.records[0].input_tick = stale.tick
	stale.payload.records[0].tool = 3
	stale.payload.records[0].weapon = 2
	check(first.game.send(first.game_id,stale).ok,"actual socket delivers validated stale action sequence")
	await wait_until(func():return a.consumed_input_sequence == 2,"retired input acknowledged in authoritative owner state")
	check(a.connected and b.connected and server.get_stats().totals.stale_inputs == 1 and server.get_stats().totals.input_rejections == 0,"stale owner intent is retired without disconnecting either actual peer")
	check(a.feet().distance_to(before_stale.feet) < .001 and a.input_move == Vector2.ZERO and a.input_buttons == 0,"discarded movement/jump/crouch cannot act or remain held")
	check(a.magazine == before_stale.magazine and a.reserve == before_stale.reserve and a.blocks == before_stale.blocks and a.grenades == before_stale.grenades and a.weapon == before_stale.weapon and a.tool == before_stale.tool and a.pending_weapon == -1,"stale fire/reload/build/grenade/class intent consumes or refills no resources")
	check(b.health == before_stale.health and data.map_sequence == before_stale.map_sequence and simulation.grenades.is_empty(),"discarded stale actions produce no hit/terrain/grenade authority")
	check(first.game.send(first.game_id,input_packet(first,3,0,Vector2(.2,0))).ok,"fresh contiguous sequence after stale retirement")
	await wait_until(func():return a.consumed_input_sequence == 3,"fresh post-stall command executes normally")
	check(a.input_move == Vector2(.2,0) and a.magazine == before_stale.magazine,"retired ACK cannot swallow the next fresh command")
	await pump(8)
	check(first.game.send(first.game_id,P.make_packet(P.Kind.CHAT,{"channel":0,"sender_id":0,"message_id":1,"text":"hello"},7,simulation.tick,a.spawn_generation)).ok,"owned chat intent")
	await wait_until(func():return first.chats.size() == 1 and second.chats.size() == 1,"global chat reaches both ready actors")
	check(second.chats[0].payload.sender_id == first_id and second.chats[0].payload.message_id == 1,"authority assigns chat sender/message ID")
	var old_token: PackedByteArray = first.welcome.payload.resume_token.duplicate()
	first.stop()
	await wait_until(func():return not a.connected,"disconnect updates authority")
	check(simulation.actors.size() == 2,"identity retained during grace")
	var resumed := client(old_token)
	await wait_until(func():return resumed.snapshot != null,"real reconnect repeats map barrier")
	check(resumed.errors.is_empty() and resumed.welcome.payload.actor_id == first_id and simulation.actors.size() == 2,"resume retains actor, no duplicate allocation")
	check(resumed.welcome.payload.resume_token != old_token,"real reconnect rotates capability")
	var second_count := second.snapshot_count
	check(resumed.game.send(resumed.game_id,input_packet(resumed,a.consumed_input_sequence+2,16)).ok,"send intentional input gap")
	await wait_until(func():return not a.connected,"malicious gap closes only offending owner")
	await pump(10)
	check(b.connected and second.snapshot_count > second_count and server.get_stats().totals.input_rejections == 1,"other actor/server continue after rejection")
	finish()

func finish() -> void:
	for c: TestClient in clients: c.stop()
	server.stop()
	check(server.get_stats().game.connections == 0 and server.get_stats().map.connections == 0,"listeners/connections released")
	print("SERVER RUNTIME: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
