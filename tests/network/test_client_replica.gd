extends SceneTree
const CLIENT = preload("res://network/client_replica.gd")
const SERVER = preload("res://network/server_runtime.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPATIBILITY = preload("res://network/compatibility.gd")
const P = preload("res://network/protocol.gd")
var assertions := 0
var failures := 0
var server: SERVER
var clients: Array[CLIENT] = []
var started: Dictionary
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("CLIENT REPLICA: "+message)
func connect_client(token: PackedByteArray = PackedByteArray(), spectator: bool = false) -> CLIENT:
	var result := CLIENT.new()
	check(result.connect_to("ws://127.0.0.1:%d/play" % started.game_port,"ws://127.0.0.1:%d/map" % started.map_port,"Guest",spectator,token).ok,"actual replica connect")
	clients.append(result)
	return result
func pump(count: int = 1) -> void:
	for _frame in range(count):
		server.poll()
		for replica: CLIENT in clients: replica.poll()
		check(server.step_once(),"server fixed step")
		await process_frame
func wait_until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await pump()
	check(predicate.call(),message)
func _run() -> void:
	var data := DATA.new()
	data.clear(Vector3i(32,16,32),19)
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	var simulation := SIMULATION.new()
	check(simulation.configure(data).ok,"small shared arena")
	server = SERVER.new()
	check(server.configure(simulation,COMPATIBILITY.build_hash(),COMPATIBILITY.rules_hash()),"paired wire versions")
	started = server.start()
	check(started.ok,"real listeners")
	var first := connect_client()
	var second := connect_client()
	await wait_until(func():return first.status == "live" and second.status == "live","both complete replicas install barriers and full states")
	if first.status != "live" or second.status != "live":
		check(false,"replica errors: %s / %s" % [first.last_error,second.last_error])
		finish()
		return
	check(first.actor_id != second.actor_id and first.epoch == 19,"replica stable identities")
	check(first.data.blocks == data.blocks and second.data.blocks == data.blocks,"exact installed baseline")
	var owner := first.get_owner_state()
	check(owner.last_tick >= 0 and owner.spawn_generation > 0 and owner.is_alive(),"full private owner initialized after server spawn step")
	check(first.get_public_state().actors.size() == 2 and first.get_stats().remote_count == 1,"public remote registry")
	var remote := first.sample_remote(second.actor_id)
	check(not remote.is_empty() and remote.id == second.actor_id,"live remote interpolation buffer")
	var before := first.get_owner_state().feet()
	for index in range(12):
		check(first.submit_input(0,Vector2(1,0),0,0).ok,"fixed predicted movement intent")
		await pump()
	await wait_until(func():return first.prediction.get_status().input_ack == 12,"authoritative snapshot acknowledges all predicted commands")
	check(first.get_owner_state().feet().x > before.x and simulation.get_actor(first.actor_id).feet().x > before.x,"prediction and authority actually move")
	check(first.prediction.get_status().pending == 0 and not first.prediction.get_status().needs_rebase,"reconciliation clears acknowledged history")
	var read_only_view := first.get_public_state()
	read_only_view.actors[0].score = 900
	owner.health = 0
	check(first.get_owner_state().health == 100 and first.get_public_state().actors[0].score != 900,"view copies cannot alter replica")
	check(first.send_chat("real replica chat"),"replica chat intent")
	var confirmed_chat := false
	var deadline := Time.get_ticks_msec()+5000
	while not confirmed_chat and Time.get_ticks_msec() < deadline:
		await pump()
		for event: Dictionary in second.drain_events():
			if event.get("type") == "chat" and event.sender_id == first.actor_id: confirmed_chat = true
	check(confirmed_chat,"replica receives server-owned chat event")
	var saved_id := first.actor_id
	var token := first.resume_token()
	first.close()
	await wait_until(func():return not simulation.get_actor(saved_id).connected,"replica close disconnects actor")
	var resumed := connect_client(token)
	await wait_until(func():return resumed.status == "live","replica resume repeats map/state join")
	check(resumed.actor_id == saved_id and resumed.resume_token() != token,"resume keeps owner and rotates capability")
	check(resumed.get_owner_state().consumed_input_sequence == 12,"resume full snapshot retains acknowledged input cursor")
	check(resumed.submit_input(0,Vector2.ZERO,0,0).sequence == 13,"resume continues input timeline")
	await wait_until(func():return resumed.prediction.get_status().input_ack == 13,"resumed command accepted")
	var spectator := connect_client(PackedByteArray(),true)
	await wait_until(func():return spectator.status == "live","spectator replica joins")
	check(spectator.get_owner_state().team == 2 and not spectator.get_owner_state().is_alive(),"spectator has no playable inventory authority")
	var converted := preload("res://network/simulation_codec.gd").from_snapshot(simulation.snapshot_for(saved_id))
	check(converted.ok,"real full body for envelope test")
	var packet := P.make_packet(P.Kind.MATCH_STATE,converted.payload,19,simulation.tick,simulation.get_actor(saved_id).spawn_generation)
	var encoded := P.encode(packet)
	check(encoded.ok and P.decode(encoded.bytes).ok,"full state envelope roundtrip")
	packet.sequence += 1
	check(not P.encode(packet).ok,"owner generation header/body mismatch rejected")
	var hostile := encoded.bytes.duplicate()
	hostile[15] ^= 1
	check(not P.decode(hostile).ok,"decoder rejects epoch header/body mismatch")
	finish()
func finish() -> void:
	for replica: CLIENT in clients: replica.close()
	server.stop()
	print("CLIENT REPLICA: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
