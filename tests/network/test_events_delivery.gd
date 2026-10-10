extends SceneTree
const CLIENT = preload("res://network/client_replica.gd")
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPAT = preload("res://network/compatibility.gd")
const P = preload("res://network/protocol.gd")
var assertions := 0
var failures := 0
var server := SERVER.new()
var clients: Array[CLIENT] = []
var captured: Array[Array] = [[],[]]
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error("EVENT DELIVERY: "+message)
func pump(count: int = 1) -> void:
	for frame in count:
		server.poll()
		for i in clients.size():
			clients[i].poll()
			captured[i].append_array(clients[i].drain_events())
		check(server.step_once(),"real fixed authority step")
		await process_frame
func wait_for(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await pump()
	check(predicate.call(),message)
func _run() -> void:
	var data := DATA.new()
	data.clear(Vector3i(32,16,32),31)
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	var simulation := MATCH.new()
	check(simulation.configure(data).ok,"configured pure map")
	check(server.configure(simulation,COMPAT.build_hash(),COMPAT.rules_hash()),"compatible runtime")
	var ports := server.start()
	check(ports.ok,"two actual socket listeners")
	for i in 2:
		var replica := CLIENT.new()
		check(replica.connect_to("ws://127.0.0.1:%d/play"%ports.game_port,"ws://127.0.0.1:%d/map"%ports.map_port,"Guest%d"%i).ok,"actual client")
		clients.append(replica)
	await wait_for(func():return clients[0].status == "live" and clients[1].status == "live","real clients pass full map/state barrier")
	if clients[0].status != "live" or clients[1].status != "live": finish(); return
	await pump(25)
	for i in 2: captured[i].clear()
	check(clients[0].submit_input(16,Vector2.ZERO,0,.3).ok,"predicted discharge command")
	await pump(8)
	check(clients[0].submit_input(0,Vector2.ZERO,0,.3).ok,"release owned trigger")
	await wait_for(func():return clients[0].prediction.get_status().input_ack == 2,"authority acknowledges discharge/release")
	var predicted := 0
	var confirmed := 0
	var remote := 0
	for event: Dictionary in captured[0]:
		if event.get("predicted",false) and event.get("kind") == "shot": predicted += 1
		if event.get("type") == "shot":
			confirmed += 1
			check(event.predicted_already_played,"confirmed own shot suppresses repeated cosmetic")
	for event: Dictionary in captured[1]:
		if event.get("type") == "shot": remote += 1; check(not event.predicted_already_played,"remote confirmed shot is new cosmetic")
	check(predicted == 1 and confirmed == 1 and remote == 1,"one prediction, one own confirmation and one remote discharge")
	check(simulation.get_actor(clients[0].actor_id).magazine == 9,"authority consumes one round")
	for i in 2: captured[i].clear()
	simulation.damage_actor(clients[1].actor_id,7,0,"fall")
	await pump(6)
	var own_hurt := 0
	for event: Dictionary in captured[1]:
		if event.get("type") == "hurt": own_hurt += 1; check(event.owner_id == clients[1].actor_id and event.amount == 7,"victim owns exact private damage")
	for event: Dictionary in captured[0]: check(event.get("type") != "hurt","other client cannot receive victim HP loss")
	check(own_hurt == 1 and clients[1].get_owner_state().health == 93,"private event and full owner state agree")
	check(clients[0].request_block_color(0x01123456),"typed owned color request")
	await pump(2)
	check(simulation.snapshot_for(clients[0].actor_id).block_colors[clients[0].actor_id] == 0x01123456,"server applies authenticated color")
	check(not clients[0].request_block_color(0xffffff) and not clients[0].request_team(3),"invalid requests rejected before send")
	var saved_health := simulation.get_actor(clients[1].actor_id).health
	check(clients[0].request_team(2),"request spectator transition")
	await wait_for(func():return clients[0].get_owner_state().team == 2,"server confirms spectator transition")
	check(simulation.get_actor(clients[1].actor_id).health == saved_health,"team request cannot mutate another actor")
	check(clients[0].request_team(0),"request playable team")
	await wait_for(func():return clients[0].get_owner_state().team == 0,"server confirms playable team")
	var events: Array[Dictionary] = [{"type":"jump","epoch":31,"tick":4,"owner_id":1,"spawn_generation":1,"action_sequence":2,"match_sequence":9,"actor_event_sequence":3,"event_id":"31:1:1:3"}]
	var payload := P.EVENTS_CODEC.from_events(31,events)
	check(payload.ok,"typed test event body")
	var packet := P.make_packet(P.Kind.GAME_EVENTS,payload.payload,31,4,9)
	var encoded := P.encode(packet)
	check(encoded.ok and P.decode(encoded.bytes).ok,"strict event envelope round trip")
	if not encoded.ok: finish(); return
	for offset in [15,19,23]:
		var hostile := encoded.bytes.duplicate()
		hostile[offset] ^= 1
		check(not P.decode(hostile).ok,"event envelope identity tamper rejected")
	finish()
func finish() -> void:
	for replica: CLIENT in clients: replica.close()
	server.stop()
	print("EVENT DELIVERY: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures == 0 else 1)
