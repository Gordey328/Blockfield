extends SceneTree
## Actual native sockets with separate authority and client frame clocks.
## Optional tools/latency_proxy.py runner supplies raw 40ms TCP forwarding.
const CLIENT = preload("res://network/client_replica.gd")
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPAT = preload("res://network/compatibility.gd")
const RULES = preload("res://simulation/player_rules.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const SERVER_HZ := 60
const CLIENT_HZ := 24
const MAX_RUN_US := 40000000
var assertions := 0
var failures := 0
var errors: Array[String] = []
var server: SERVER
var first := CLIENT.new()
var observer := CLIENT.new()
var game_url := ""
var map_url := ""
var relay_dir := ""
var report_path := ""
var stream_seconds := 6
var run_started_us := 0
var authority_started_us := 0
var authority_steps := 0
var authority_errors := 0
var client_frames := 0
var submitted := 0
var dropped_client_steps := 0
var catchup_bursts := 0
var submit_errors := 0
var peak_pending := 0
var peak_queue_frames := 0
var peak_queue_bytes := 0
var maximum_authority_lateness_us := 0
var maximum_client_lateness_us := 0
var minimum_input_lead := 2147483647
var maximum_input_lead := -2147483648
var maximum_replay_clock_lead := -2147483648
var last_sequence := 0
var last_stream_error := ""
var seen_events: Dictionary[int, Dictionary] = {}
var duplicate_events := 0
var confirmed_shot_ticks: Array[int] = []
var trajectory: Array[Dictionary] = []
var source_hashes: Dictionary[String, String] = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		errors.append(message)
		push_error("CLIENT SCHEDULE: " + message)

func _authority() -> void:
	server.poll()
	var elapsed := Time.get_ticks_usec() - authority_started_us
	var due := int(elapsed * SERVER_HZ / 1000000)
	maximum_authority_lateness_us = maxi(maximum_authority_lateness_us, elapsed - int(authority_steps * 1000000 / SERVER_HZ))
	var work := 0
	while authority_steps < due and work < 8:
		if not server.step_once(): authority_errors += 1
		authority_steps += 1
		work += 1
	server.poll()

func _collect(client: CLIENT) -> void:
	var id := client.get_instance_id()
	if not seen_events.has(id): seen_events[id] = {}
	for event: Dictionary in client.drain_events():
		if event.has("event_id"):
			if seen_events[id].has(event.event_id): duplicate_events += 1
			seen_events[id][event.event_id] = true
			if seen_events[id].size() > 2048: seen_events[id].erase(seen_events[id].keys()[0])
		if client == first and event.get("type", "") == "shot" and event.get("owner_id", 0) == first.actor_id:
			confirmed_shot_ticks.append(int(event.tick))
	peak_pending = maxi(peak_pending, int(client.prediction.get_status().pending))
	for transport in [client.game, client.bulk]:
		for peer: Dictionary in transport.get_stats().peers:
			peak_queue_frames = maxi(peak_queue_frames, int(peer.queued_frames))
			peak_queue_bytes = maxi(peak_queue_bytes, int(peer.queued_bytes + peer.socket_buffered_bytes))

func _poll_client(client: CLIENT) -> void:
	client.poll()
	_collect(client)

func _pump() -> void:
	_authority()
	_poll_client(observer)
	await process_frame

func _wait(predicate: Callable, message: String, timeout_ms: int = 5000, allow_failed: bool = false) -> bool:
	var deadline := mini(Time.get_ticks_usec() + timeout_ms * 1000, run_started_us + MAX_RUN_US)
	while Time.get_ticks_usec() < deadline:
		_authority()
		_poll_client(first)
		_poll_client(observer)
		if predicate.call(): check(true, message); return true
		if not allow_failed and first.status == "failed": break
		await process_frame
	check(false, message + " (" + first.status + ")")
	return false

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value))
	file.close()
	return true

func _read_control() -> Dictionary:
	var path := relay_dir.path_join("control.json")
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	var text := file.get_as_text()
	file.close()
	if text.is_empty(): return {}
	var decoder := JSON.new()
	if decoder.parse(text) != OK: return {}
	return decoder.data if decoder.data is Dictionary else {}

func _hash_source(path: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes(path))
	return hashing.finish().hex_encode()

func _snapshot_trajectory(started_us: int) -> void:
	var stats := first.prediction.get_status()
	trajectory.append({"elapsed_ms":int((Time.get_ticks_usec()-started_us)/1000), "authority_tick":server.simulation.tick,
		"snapshot_tick":stats.server_tick, "predicted_tick":stats.predicted_tick, "pending":stats.pending,
		"ack":stats.input_ack, "submitted":stats.last_submitted, "wire_input_tick":first._last_input_tick,"status":first.status})

func _stream() -> void:
	var started_us := Time.get_ticks_usec()
	var deadline := started_us + stream_seconds * 1000000
	var next_client_us := started_us
	var next_sample_us := started_us
	var budgeted_client_steps := 0
	while Time.get_ticks_usec() < deadline and Time.get_ticks_usec() < run_started_us + MAX_RUN_US:
		_authority()
		_poll_client(observer)
		var now := Time.get_ticks_usec()
		if now >= next_client_us:
			maximum_client_lateness_us = maxi(maximum_client_lateness_us, now-next_client_us)
			# Poll/adopt a fresh server snapshot BEFORE this rendered frame's burst.
			_poll_client(first)
			if first.status != "live": break
			# Normal24Hz frames produce alternating2/3 physics steps. A delayed
			# frame catches up at most8, matching the engine's default ceiling;
			# discard excess time instead of inventing an unlimited input burst.
			var scheduled_frame := int((now-started_us)*CLIENT_HZ/1000000)
			var due_steps := int((scheduled_frame+1)*SERVER_HZ/CLIENT_HZ)
			var count := clampi(due_steps-budgeted_client_steps, 0, 8)
			if count > 3: catchup_bursts += 1
			dropped_client_steps += maxi(0, due_steps-budgeted_client_steps-count)
			budgeted_client_steps = due_steps
			for _step in range(count):
				var owner := first.get_owner_state()
				if owner == null: submit_errors += 1; break
				maximum_replay_clock_lead = maxi(maximum_replay_clock_lead, owner.last_tick+1-server.simulation.tick)
				var buttons := RULES.Buttons.PRIMARY if now-started_us < 3000000 else 0
				var move := Vector2(.4, 0) if now-started_us < 1500000 else Vector2(-.4, 0) if now-started_us < 3000000 else Vector2.ZERO
				var result := first.submit_input(buttons, move, 0, 0)
				if not result.ok: submit_errors += 1; break
				var lead: int = first._last_input_tick-server.simulation.tick
				minimum_input_lead = mini(minimum_input_lead, lead)
				maximum_input_lead = maxi(maximum_input_lead, lead)
				submitted += 1
				last_sequence = int(result.sequence)
				_collect(first)
			client_frames += 1
			# Resume from this callback's real time: never replay skipped render
			# callbacks immediately after a host pause.
			next_client_us = now + int(1000000/CLIENT_HZ)
		if now >= next_sample_us:
			_snapshot_trajectory(started_us)
			next_sample_us += 250000
		await process_frame
	_snapshot_trajectory(started_us)
	last_stream_error = first.last_error
	check(first.status == "live" and observer.status == "live", "independent clocks preserve both actual connections")
	check(submit_errors == 0, "every ordinary24Hz input burst is accepted locally")
	check(authority_errors == 0, "real-clock authority never rejects its fixed steps")
	check(server.get_stats().totals.input_rejections == 0, "ordinary bursts stay inside authoritative admission window")
	check(server.game_transport.get_stats().totals.backpressure == 0 and server.game_transport.get_stats().totals.timeouts == 0, "ordinary schedule has no authority transport pressure or timeout")
	check(submitted+dropped_client_steps >= stream_seconds*SERVER_HZ-5, "24Hz scheduling accounts for60 physics ticks per second with explicit dropped time")
	check(peak_pending < 256 and peak_queue_frames < TRANSPORT.MAX_QUEUE_FRAMES and peak_queue_bytes < TRANSPORT.MAX_OUTBOUND_BYTES, "ordinary prediction and native outbound queues remain bounded")
	if first.status != "live": return
	if not await _wait(func() -> bool: return int(first.prediction.get_status().input_ack) == last_sequence, "all scheduled commands acknowledged and drained"): return
	check(first.prediction.get_status().pending == 0, "drained source replay retains no unacknowledged inputs")
	check(first.data.blocks == server.simulation.data.blocks and first.data.map_sequence == server.simulation.data.map_sequence, "scheduled replica preserves canonical terrain barrier")
	var actor := server.simulation.get_actor(first.actor_id)
	check(first.get_owner_state().feet().distance_to(actor.feet()) < .02, "neutral drain converges predicted and authority motion")
	check(not confirmed_shot_ticks.is_empty() and confirmed_shot_ticks.size() == 10-actor.magazine, "confirmed source shots match authoritative inventory consumption")
	var cadence_ok := true
	for index in range(1, confirmed_shot_ticks.size()):
		if confirmed_shot_ticks[index]-confirmed_shot_ticks[index-1] < 30: cadence_ok = false
	check(cadence_ok, "source0.75 rifle never fires faster than30-tick cadence across24Hz frames")
	check(duplicate_events == 0, "confirmed event identities remain unique across delayed frame polling")

func _resume(token: PackedByteArray, stable_id: int) -> bool:
	if not await _wait(func() -> bool: return not server.simulation.get_actor(stable_id).connected, "failed socket detached from authority", 3000, true): return false
	check(first.connect_to(game_url, map_url, "Scheduled owner", false, token).ok, "same Replica begins authenticated resume")
	if not await _wait(func() -> bool: return first.status == "live", "resume crosses fresh baseline/state barrier"): return false
	check(first.actor_id == stable_id and first.data.blocks == server.simulation.data.blocks, "resume preserves stable owner and canonical map")
	return true

func _terminal_cases() -> void:
	check(CLIENT.terminal_error("game", {"type":"timeout","reason":"ping timeout"}) == "game timeout: ping timeout", "application heartbeat diagnosis preserved")
	check(CLIENT.terminal_error("map", {"type":"overflow"}) == "map event queue overflow", "bulk overflow diagnosis distinct from socket loss")
	var sanitized := CLIENT.terminal_error("game", {"type":"closed","code":1008,"reason":"opaque-peer-private-value"})
	check(sanitized == "game closed (1008): remote close" and not sanitized.contains("private"), "untrusted peer reason never leaks into diagnostics")
	if first.status != "live": return
	var stable_id := first.actor_id
	var token := first.resume_token() # Memory only: never serialized or printed.
	var connection: int = server.registry.session_view(stable_id).game
	check(server.game_transport.close(connection, 1008, "invalid input stream").ok, "actual peer emits known close reason")
	if not await _wait(func() -> bool: return first.status == "failed", "actual close reaches Replica", 3000, true): return
	check(first.last_error == "game closed (1008): invalid input stream", "actual terminal event preserves reason and wire status")
	if not await _resume(token, stable_id): return
	token = first.resume_token()
	check(first.game.close(first._game_id).ok, "actual local socket enters closing before polling")
	var closed_send := first.submit_input(0, Vector2.ZERO, 0, 0)
	check(not closed_send.ok and closed_send.error == "input send failed: connection is not open", "send against closed socket is not mislabeled as capacity pressure")
	if not await _resume(token, stable_id): return
	token = first.resume_token()
	var accepted := 0
	# Do not poll or flush this burst: assert the real admission bound, then the
	# terminal path drops every unsent frame rather than sending future intents.
	for _frame in range(TRANSPORT.MAX_QUEUE_FRAMES):
		if first.submit_input(0, Vector2.ZERO, 0, 0).ok: accepted += 1
	check(accepted == TRANSPORT.MAX_QUEUE_FRAMES, "actual outgoing application queue admits exactly its32-frame bound")
	var pressured_send := first.submit_input(0, Vector2.ZERO, 0, 0)
	check(not pressured_send.ok and pressured_send.error == "input send failed: outbound backpressure", "true queue pressure remains distinguishable from closed socket")
	check(first.status == "failed" and first.prediction.get_status().pending == 0, "terminal pressure clears old prediction and unsent stream")
	if not await _resume(token, stable_id): return
	check(observer.status == "live" and server.get_stats().totals.input_rejections == 0, "other peer remains healthy and unsent capacity fixture reaches no authority")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--latency-dir="): relay_dir = argument.trim_prefix("--latency-dir=")
		elif argument.begins_with("--schedule-report="): report_path = argument.trim_prefix("--schedule-report=")
		elif argument.begins_with("--seconds="): stream_seconds = clampi(int(argument.trim_prefix("--seconds=")), 3, 32)
	if not relay_dir.is_empty(): stream_seconds = 20
	Engine.max_fps = 240
	run_started_us = Time.get_ticks_usec()
	for path: String in ["res://network/client_replica.gd","res://network/client_prediction.gd","res://network/input_queue.gd","res://network/ws_transport.gd"]:
		source_hashes[path] = _hash_source(path)
	var data := DATA.new()
	check(data.clear(Vector3i(32,16,32), 207) == OK, "bounded real canonical terrain")
	data.seed_box(Vector3i.ZERO, Vector3i(32,4,32), 0x01608070)
	var simulation := MATCH.new()
	check(simulation.configure(data, "0.75", "sandbox").ok, "pure source0.75 authoritative match")
	server = SERVER.new()
	check(server.configure(simulation, COMPAT.build_hash(), COMPAT.rules_hash()), "current production compatibility")
	var endpoints := server.start()
	check(endpoints.ok, "owned actual loopback game/map listeners")
	if not endpoints.ok: finish(); return
	authority_started_us = Time.get_ticks_usec()
	game_url = "ws://127.0.0.1:%d/play" % endpoints.game_port
	map_url = "ws://127.0.0.1:%d/map" % endpoints.map_port
	if not relay_dir.is_empty():
		check(_write_json(relay_dir.path_join("status.json"), {"phase":"ready","game_port":endpoints.game_port,"map_port":endpoints.map_port}), "owned runner status excludes capabilities")
		var deadline := Time.get_ticks_msec()+3000
		var control := _read_control()
		while not control.has("game_port") and Time.get_ticks_msec() < deadline:
			await _pump()
			control = _read_control()
		check(control.has("game_port"), "bounded rawTCP relay setup")
		if not control.has("game_port"): finish(); return
		game_url = "ws://127.0.0.1:%d/play" % control.game_port
		map_url = "ws://127.0.0.1:%d/map" % control.map_port
	check(first.connect_to(game_url, map_url, "Scheduled owner").ok, "real scheduled client starts")
	check(observer.connect_to(game_url, map_url, "Schedule observer", true).ok, "real independent observer starts")
	if not await _wait(func() -> bool: return first.status == "live" and observer.status == "live", "both genuine baseline/state joins complete"): finish(); return
	check(first.get_owner_state().is_alive() and observer.get_owner_state().team == 2 and first.actor_id != observer.actor_id, "server owns distinct playing/spectator identities")
	await _stream()
	await _terminal_cases()
	finish()

func finish() -> void:
	var totals: Dictionary = server.get_stats().totals.duplicate() if server != null else {}
	first.close()
	observer.close()
	if server != null: server.stop()
	check(first.game.get_stats().connections == 0 and observer.game.get_stats().connections == 0 and (server == null or (server.game_transport.get_stats().connections == 0 and server.map_transport.get_stats().connections == 0)), "all exact-owned client/server sockets released")
	var result := {"assertions":assertions,"failures":failures,"errors":errors,"wall_seconds":(Time.get_ticks_usec()-run_started_us)/1000000.0,
		"source_hashes":source_hashes,"shaped_tcp":not relay_dir.is_empty(),"source_profile":"0.75","server_hz":SERVER_HZ,"client_hz":CLIENT_HZ,
		"stream_seconds":stream_seconds,"authority_steps":authority_steps,"client_frames":client_frames,"submitted":submitted,
		"dropped_client_steps":dropped_client_steps,"catchup_bursts":catchup_bursts,
		"peak_pending":peak_pending,"peak_queue_frames":peak_queue_frames,"peak_queue_bytes":peak_queue_bytes,
		"minimum_input_lead":minimum_input_lead,"maximum_input_lead":maximum_input_lead,
		"maximum_replay_clock_lead":maximum_replay_clock_lead,
		"maximum_authority_lateness_ms":maximum_authority_lateness_us/1000.0,"maximum_client_lateness_ms":maximum_client_lateness_us/1000.0,
		"confirmed_shots":confirmed_shot_ticks.size(),"trajectory":trajectory,"server_totals":totals}
	result["last_stream_error"] = last_stream_error
	if not relay_dir.is_empty():
		if not _write_json(relay_dir.path_join("result.json"), result): check(false, "owned runner result writable")
	if not report_path.is_empty():
		if not _write_json(report_path, result): check(false, "explicit metrics report writable")
	print("CLIENT SCHEDULE: %d assertions, %d failures; frames=%d inputs=%d lead=%d..%d pending=%d wall=%.3fs" % [assertions, failures, client_frames, submitted, minimum_input_lead, maximum_input_lead, peak_pending, result.wall_seconds])
	quit(0 if failures == 0 else 1)
