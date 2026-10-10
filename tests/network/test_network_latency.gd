extends SceneTree
## Real Runtime/Replica via externally owned bounded loopback TCP shaping relays.
const SERVER = preload("res://network/server_runtime.gd")
const CLIENT = preload("res://network/client_replica.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const COMPAT = preload("res://network/compatibility.gd")
const P = preload("res://network/protocol.gd")
const RULES = preload("res://simulation/player_rules.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
var assertions := 0
var failures := 0
var server: SERVER
var clients: Array[CLIENT] = []
var logs: Dictionary[int,Array] = {}
var seen: Dictionary[int,Dictionary] = {}
var task_dir := ""
var control := {}
var request_sequence := 0
var next_tick_us := 0
var steps := 0
var peak_prediction := 0
var peak_queue_frames := 0
var peak_queue_bytes := 0
var step_times: Array[float] = []
var inputs_on := false
var shot_step := -1
var short_stall_ms := 0
var timeout_ms := 0
var backlog_failure_ms := 0
var proxy_first_connection := 1
var real_ticks_started_us := 0
var failed_messages: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1; failed_messages.append(message)
		push_error("NETWORK LATENCY: " + message)
func write_json(name: String, value: Dictionary) -> void:
	var path := task_dir.path_join(name)
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: check(false,"owned control file writable"); return
	file.store_string(JSON.stringify(value)); file.close()
	# Windows rename cannot replace the previous task-local control file.
	# Readers retry a missing/partial file, so a remove+rename is safe here.
	if FileAccess.file_exists(path):
		if DirAccess.remove_absolute(path) != OK: check(false,"owned control file replace"); return
	var publish_error := DirAccess.rename_absolute(path+".tmp",path)
	if name != "result.json" or publish_error != OK:
		check(publish_error == OK,"owned control file publish")
func read_control() -> Dictionary:
	var path := task_dir.path_join("control.json")
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func make_map() -> DATA:
	var data := DATA.new(); data.clear(Vector3i(24,16,24),5)
	data.seed_box(Vector3i.ZERO,Vector3i(24,4,24),0x0155796b)
	return data
func events_for(client: CLIENT, type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in logs[client.get_instance_id()]:
		if event.get("type","") == type: result.append(event)
	return result
func collect(client: CLIENT) -> void:
	for event: Dictionary in client.drain_events():
		var key := client.get_instance_id()
		if event.has("event_id"):
			check(not seen[key].has(event.event_id),"confirmed event identity appears once despite delayed/stalled TCP")
			seen[key][event.event_id] = true
		if logs[key].size() < 256: logs[key].append(event)
	for transport in [client.game,client.bulk,server.game_transport,server.map_transport]:
		for peer: Dictionary in transport.get_stats().peers:
			peak_queue_frames = maxi(peak_queue_frames,peer.queued_frames)
			peak_queue_bytes = maxi(peak_queue_bytes,peer.queued_bytes+peer.socket_buffered_bytes)
	peak_prediction = maxi(peak_prediction,client.prediction.get_status().pending)
func pump() -> void:
	server.poll()
	for client: CLIENT in clients: client.poll(); collect(client)
	var now := Time.get_ticks_usec()
	var catchup := 0
	while now >= next_tick_us and catchup < 4:
		var started := Time.get_ticks_usec()
		check(server.step_once(),"real authority fixed step")
		if step_times.size() < 4096: step_times.append((Time.get_ticks_usec()-started)/1000.0)
		steps += 1; catchup += 1; next_tick_us += 16667
		if inputs_on:
			for index in range(clients.size()):
				var client := clients[index]
				if client.status != "live": continue
				var result := client.submit_input(RULES.Buttons.PRIMARY if index == 0 and steps == shot_step else 0,Vector2.ZERO,0,-.15,2,0)
				if not result.ok and result.error not in ["client state not ready","waiting for matching terrain state"]:
					check(false,"unexpected prediction/admission failure: "+result.error)
	await process_frame
func wait_until(predicate: Callable, message: String, timeout: int = 5000, allow_failed: bool = false) -> bool:
	var deadline := Time.get_ticks_msec()+timeout
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): check(true,message); return true
		if not allow_failed:
			for client: CLIENT in clients:
				if client.status == "failed": check(false,message+": "+client.last_error); return false
		await pump()
	check(false,message+" timeout"); return false
func run_for(milliseconds: int, allow_failed: bool = false) -> void:
	var deadline := Time.get_ticks_msec()+milliseconds
	while Time.get_ticks_msec() < deadline:
		await pump()
		if not allow_failed:
			for client: CLIENT in clients:
				if client.status == "failed": check(false,"unexpected delayed client failure: "+client.last_error); return
func request_stall(milliseconds: int) -> bool:
	request_sequence += 1
	write_json("request.json",{"sequence":request_sequence,"action":"stall","channel":"game","connection":proxy_first_connection,"duration_ms":milliseconds})
	return await wait_until(func():return int(read_control().get("ack",0)) == request_sequence,"owned relay applies bounded stall",1000)
func map_equal() -> bool:
	for client: CLIENT in clients:
		if client.data == null or client.data.map_sequence != server.simulation.data.map_sequence or client.data.blocks != server.simulation.data.blocks: return false
	return true
func edit(cell: Vector3i, color: int) -> void:
	var transaction := server.simulation.data.set_block(cell,color,{"tick":server.simulation.tick,"actor_id":0,"action_id":1})
	check(transaction.ok and transaction.changed,"trusted ordered authority terrain edit")
	server.simulation._commit(transaction)
func all_live() -> bool:
	for client: CLIENT in clients:
		if client.status != "live": return false
	return true
func connect_client(name: String) -> CLIENT:
	var client := CLIENT.new()
	if clients.is_empty():
		check(client.game.configure({"ping_interval_ms":100,"ping_timeout_ms":650,"idle_timeout_ms":1200,"close_timeout_ms":100}).ok,"shortened heartbeat fixture configured before transport starts")
	check(client.connect_to("ws://127.0.0.1:%d/play" % control.game_port,"ws://127.0.0.1:%d/map" % control.map_port,name).ok,"actual client connects through raw TCP relay")
	clients.append(client); logs[client.get_instance_id()] = []; seen[client.get_instance_id()] = {}
	return client
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--latency-dir="): task_dir = argument.trim_prefix("--latency-dir=")
	if task_dir.is_empty(): push_error("Use tools/latency_proxy.py owned runner"); quit(2); return
	Engine.max_fps = 240
	var simulation := MATCH.new(); check(simulation.configure(make_map(),"0.75","sandbox").ok,"source0.75 authoritative fixture")
	server = SERVER.new(); check(server.configure(simulation,COMPAT.build_hash(),COMPAT.rules_hash()),"strict network compatibility")
	var endpoints := server.start(); check(endpoints.ok,"actual paired loopback listeners")
	next_tick_us = Time.get_ticks_usec(); real_ticks_started_us = next_tick_us
	write_json("status.json",{"phase":"ready","game_port":endpoints.game_port,"map_port":endpoints.map_port})
	if not await wait_until(func():control = read_control();return control.has("game_port"),"loopback relay handshake",3000): finish(); return
	var first := connect_client("Delayed shooter")
	if not await wait_until(all_live,"first delayed baseline/state barrier"): finish(); return
	var second := connect_client("Delayed observer")
	if not await wait_until(all_live,"second delayed baseline/state barrier"): finish(); return
	check(map_equal(),"both delayed join hashes and canonical map bytes converge")
	var first_id := first.actor_id
	var actor := simulation.get_actor(first_id); var victim := simulation.get_actor(second.actor_id)
	actor.motion = MOTION.create_state(Vector3(8.5,4.01,12.5)); actor.tool_raise = 1
	victim.motion = MOTION.create_state(Vector3(8.5,4.01,8.5)); victim.tool_raise = 1
	if not await wait_until(func():return first.get_owner_state().feet().distance_to(actor.feet()) < .02 and second.get_owner_state().feet().distance_to(victim.feet()) < .02,"delayed source poses reconciled before shot"): finish(); return
	inputs_on = true; shot_step = steps+2
	if not await wait_until(func():return not events_for(first,"hit_confirmed").is_empty(),"authenticated delayed shot produces owner-private hit feedback"): finish(); return
	await run_for(200)
	check(events_for(second,"hit_confirmed").is_empty() and not events_for(second,"hurt").is_empty() and events_for(first,"hurt").is_empty(),"hit/hurt private routing survives delayed event transport")
	var confirmed_shots := events_for(first,"shot")
	check(confirmed_shots.size() == 1 and confirmed_shots[0].get("predicted_already_played",false),"predicted local shot is confirmed once and flagged for effect deduplication")
	for public_actor: Dictionary in second.get_public_state().actors: check(not public_actor.has("health") and not public_actor.has("magazine") and not public_actor.has("reserve"),"remote public state carries no private inventory/health")
	check(first.send_chat("Delayed ordered chat"),"delayed typed chat submitted")
	edit(Vector3i(18,4,18),0x01dd6644); edit(Vector3i(18,4,18),0x017744dd)
	if not await wait_until(func():return map_equal() and not events_for(second,"chat").is_empty(),"ordered edits/chat cross delayed sockets exactly"): finish(); return
	check(await request_stall(75),"short stall acknowledged")
	var short_started := Time.get_ticks_msec()
	edit(Vector3i(18,4,18),0); edit(Vector3i(19,4,18),0x014499bb)
	await run_for(600); short_stall_ms = Time.get_ticks_msec()-short_started
	check(all_live() and map_equal(),"short TCP stall recovers ordered deltas without dropping peers")
	check(peak_prediction > 0 and peak_prediction < first.prediction.MAX_HISTORY and peak_queue_frames <= TRANSPORT.MAX_QUEUE_FRAMES and peak_queue_bytes <= TRANSPORT.MAX_OUTBOUND_BYTES,"pending prediction and transport queues stay within their real bounds")
	# A 350 ms held input backlog exceeds the authority's 15-tick late-input
	# admission window. This is expected rejection, not a recovery guarantee.
	var backlog_resume_token := first.resume_token()
	if not await request_stall(350): finish(); return
	var backlog_started := Time.get_ticks_msec()
	if not await wait_until(func():return first.status == "failed","350 ms input backlog explicitly rejects stale commands",1500,true): finish(); return
	backlog_failure_ms = Time.get_ticks_msec()-backlog_started
	check(server.get_stats().totals.input_rejections == 1 and first.game.get_stats().totals.timeouts == 0,"backlog failure is admitted-lateness rejection before heartbeat timeout")
	check(second.status == "live","late-input owner failure preserves healthy peer")
	inputs_on = false
	await run_for(650,true)
	check(not simulation.get_actor(first_id).connected,"rejected old game socket released before resume")
	check(first.connect_to("ws://127.0.0.1:%d/play" % control.game_port,"ws://127.0.0.1:%d/map" % control.map_port,"Backlog resume",false,backlog_resume_token).ok,"same replica resumes after admitted-lateness rejection")
	backlog_resume_token.clear()
	proxy_first_connection = 3
	if not await wait_until(all_live,"late-input resume completes fresh terrain and state barrier"): finish(); return
	check(first.actor_id == first_id and map_equal() and first.prediction.get_status().pending == 0,"backlog resume preserves identity and clears stale prediction")
	# Explicit fixture timeout, shorter than production defaults; no live settings.
	inputs_on = false
	await run_for(250)
	var resume_token := first.resume_token()
	if not await request_stall(1500): finish(); return
	var timeout_started := Time.get_ticks_msec()
	if not await wait_until(func():return first.status == "failed","long stall explicitly fails shortened heartbeat",2500,true): finish(); return
	timeout_ms = Time.get_ticks_msec()-timeout_started
	check(first.game.get_stats().totals.timeouts == 1,"long-stall terminal failure is an actual heartbeat timeout")
	check(second.status == "live" and server.simulation.epoch == 5,"stalled owner cannot take healthy peer or authority down")
	inputs_on = false
	await run_for(1700,true)
	check(not server.simulation.get_actor(first_id).connected,"old actual game socket closes before resume")
	check(first.game.configure({"ping_interval_ms":2000,"ping_timeout_ms":5000,"idle_timeout_ms":10000,"close_timeout_ms":500}).ok,"production heartbeat defaults restored on discarded test transport")
	check(first.connect_to("ws://127.0.0.1:%d/play" % control.game_port,"ws://127.0.0.1:%d/map" % control.map_port,"Delayed resume",false,resume_token).ok,"same replica resumes through new shaped game/bulk sockets")
	resume_token.clear()
	if not await wait_until(all_live,"delayed resume completes fresh map/state barrier"): finish(); return
	check(first.actor_id == first_id and map_equal() and first.get_owner_state().profile == "0.75","stable identity and exact edited terrain survive real timeout/reconnect")
	check(server.get_stats().totals.input_rejections == 1 and first.prediction.get_status().pending == 0,"exactly the expected backlog rejection and no stale prediction survive reconnect")
	await run_for(150)
	finish()
func finish() -> void:
	var wall := (Time.get_ticks_usec()-real_ticks_started_us)/1000000.0
	var server_stats := server.get_stats() if server != null else {}
	for client: CLIENT in clients: client.close()
	if server != null:
		server.stop()
		check(server.game_transport.get_stats().connections == 0 and server.map_transport.get_stats().connections == 0,"owned client/server sockets all cleaned")
	var ordered := step_times.duplicate(); ordered.sort()
	var sum := 0.0
	for value: float in ordered: sum += value
	var result := {"assertions":assertions,"failures":failures,"errors":failed_messages,"wall_seconds":wall,"steps":steps,
		"fixed_hz":60,"peak_pending_prediction":peak_prediction,"peak_transport_queue_frames":peak_queue_frames,"peak_transport_queue_bytes":peak_queue_bytes,
		"source_profile":"0.75","clients":2,"short_stall_observation_ms":short_stall_ms,"timeout_observation_ms":timeout_ms,
		"backlog_failure_ms":backlog_failure_ms,"expected_input_rejections":1,"backlog_stall_ms":350,"short_stall_ms":75,"heartbeat_stall_ms":1500,
		"server_step_mean_ms":sum/maxi(1,ordered.size()),"server_step_p95_ms":ordered[int((ordered.size()-1)*.95)] if not ordered.is_empty() else 0,
		"server_step_max_ms":ordered.back() if not ordered.is_empty() else 0,"server_totals":server_stats.get("totals",{})}
	write_json("result.json",result)
	clients.clear(); server = null
	print("NETWORK LATENCY: %d assertions, %d failures; steps=%d peak_prediction=%d" % [assertions,failures,steps,peak_prediction])
	quit(0 if failures == 0 else 1)
