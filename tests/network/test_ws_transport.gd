extends SceneTree
## Real local sockets; never starts main, writes preferences, or runs a service.
const TRANSPORT = preload("res://network/ws_transport.gd")
const PROTOCOL = preload("res://network/protocol.gd")

var assertions: int = 0
var failures: int = 0
var _transports: Array[TRANSPORT] = []
var _events: Dictionary[int, Array] = {}
var _raw_sockets: Array[WebSocketPeer] = []

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures += 1; push_error("WS_TRANSPORT: " + message)

func _run() -> void:
	_test_configuration()
	await _test_two_clients()
	await _test_malformed_frames()
	await _test_timeouts()
	await _test_automatic_ping()
	await _test_event_overflow(false)
	await _test_event_overflow(true)
	await _cleanup()
	print("WS_TRANSPORT: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _new(options: Dictionary = {}) -> TRANSPORT:
	var transport: TRANSPORT = TRANSPORT.new()
	var config: Dictionary = {"ping_interval_ms":0,"idle_timeout_ms":10000,"close_timeout_ms":100}
	config.merge(options,true)
	check(transport.configure(config).ok,"valid bounded configuration")
	_transports.append(transport); _events[_transports.size()-1] = []
	return transport

func _index(transport: TRANSPORT) -> int: return _transports.find(transport)

func _captured(transport: TRANSPORT, event_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in _events[_index(transport)]:
		if event.type == event_type: result.append(event)
	return result

func _clear_events() -> void:
	for index: int in _events: _events[index].clear()

func _poll_all(collect: bool = true) -> void:
	for transport: TRANSPORT in _transports: transport.poll()
	for socket: WebSocketPeer in _raw_sockets: socket.poll()
	if collect:
		for index: int in range(_transports.size()):
			_events[index].append_array(_transports[index].drain_events(TRANSPORT.MAX_EVENTS))

func _until(condition: Callable, timeout_ms: int = 2500, collect: bool = true) -> bool:
	var deadline: int = Time.get_ticks_usec() + timeout_ms * 1000
	while Time.get_ticks_usec() < deadline:
		_poll_all(collect)
		if condition.call(): return true
		await create_timer(.002).timeout
	_poll_all(collect)
	return condition.call()

func _open_count(transport: TRANSPORT) -> int:
	var count: int = 0
	for peer: Dictionary in transport.get_stats().peers:
		if peer.state == "open": count += 1
	return count

func _chat(text: String, sequence: int = 1) -> PROTOCOL.Packet:
	return PROTOCOL.make_packet(PROTOCOL.Kind.CHAT,{"channel":0,"sender_id":123,"message_id":sequence,"text":text},7,11,sequence)

func _bulk() -> PROTOCOL.Packet:
	var bytes: PackedByteArray = PackedByteArray(); bytes.resize(PROTOCOL.CHUNK_BYTES); bytes.fill(0x62)
	return PROTOCOL.make_packet(PROTOCOL.Kind.MAP_CHUNK,{"snapshot_id":1,"index":0,"total_size":PROTOCOL.CHUNK_BYTES,"data":bytes})

func _test_configuration() -> void:
	var transport: TRANSPORT = TRANSPORT.new()
	for invalid: Dictionary in [{"connection_limit":0},{"connection_limit":33},{"idle_timeout_ms":49},{"ping_timeout_ms":false},{"unknown":1}]:
		check(not transport.configure(invalid).ok,"invalid config rejected before startup")
	for url: String in ["https://localhost/","ws:///","ws://user:secret@localhost/","ws://localhost/\n","ws://localhost/#fragment"]:
		check(not transport.start_client(url).ok,"invalid URL shape rejected without a socket")
	check(not transport.start_server(-1).ok and not transport.start_server(65536).ok,"invalid port rejected")
	check(not transport.send(99,_chat("unknown")).ok,"send requires an owned connection")
	check(not transport.close(99).ok,"close requires an owned connection")
	check(transport.drain_events(-1).is_empty(),"negative drain is harmless")
	check(transport.get_stats().connections == 0 and transport.get_stats().mode == "idle","validation has no socket side effects")
	for code: int in [1000,1001,1002,1003,1007,1008,1009,1010,1011,1012,1013,1014,3000,4999]:
		check(TRANSPORT._wire_close_code(code,false)==code,"native close status preserved")
		var browser_code: int = TRANSPORT._wire_close_code(code,true)
		check(browser_code==1000 or (browser_code>=3000 and browser_code<=4999),"browser close status obeys WebSocket API")
	check(TRANSPORT._wire_close_code(1001,true)==4001 and TRANSPORT._wire_close_code(1002,true)==4002,"browser timeout/protocol statuses have documented mapping")
	transport.stop(true)
	var admitted: bool = true
	for index: int in range(TRANSPORT.MAX_EVENTS):
		admitted = admitted and transport.start_server().ok
		transport.stop(true)
	check(admitted,"undrained status-event fixture fills only its bounded queue")
	check(not transport.start_server().ok and transport.get_stats().port==0,"startup never reports a listener discarded by status-event overflow")
	var terminal: Array[Dictionary] = transport.drain_events(TRANSPORT.MAX_EVENTS)
	check(terminal.size()==1 and terminal[0].type=="overflow","status-event overflow remains an explicit terminal failure")
	transport.stop(true)

func _test_two_clients() -> void:
	var server: TRANSPORT = _new({"connection_limit":2})
	var started: Dictionary = server.start_server()
	check(started.ok and started.port > 0 and server.get_stats().port == started.port,"port zero selects a real ephemeral port")
	if not started.ok: return
	var url: String = "ws://127.0.0.1:%d/play" % started.port
	var a: TRANSPORT = _new(); var b: TRANSPORT = _new()
	var a_start: Dictionary = a.start_client(url); var b_start: Dictionary = b.start_client(url)
	check(a_start.ok and b_start.ok,"two actual WebSocket clients started")
	if not a_start.ok or not b_start.ok: return
	var a_id: int = a_start.connection_id; var b_id: int = b_start.connection_id
	check(not a.send(a_id,_chat("early")).ok,"cannot send before handshake")
	check(await _until(func() -> bool: return _open_count(server)==2 and _open_count(a)==1 and _open_count(b)==1),"two actual handshakes complete")
	check(_captured(server,"connected").size()==2,"server announces each connection exactly once")
	check(not server.start_server().ok and not a.configure({"connection_limit":1}).ok,"active transports cannot be reconfigured or restarted")
	_clear_events()
	check(a.send(a_id,_chat("owner-a")).ok and b.send(b_id,_chat("owner-b")).ok,"clients queue distinct packets")
	check(await _until(func() -> bool: return _captured(server,"packet").size()==2),"server receives both packets")
	var server_a: int = 0; var server_b: int = 0
	for event: Dictionary in _captured(server,"packet"):
		if event.packet.payload.text == "owner-a": server_a = event.connection_id
		if event.packet.payload.text == "owner-b": server_b = event.connection_id
		check(event.packet.payload.sender_id==123 and event.packet.epoch==7 and event.packet.tick==11,"transport preserves schema but does not authorize actor claims")
	check(server_a>0 and server_b>0 and server_a!=server_b,"routing uses independent server connection IDs")
	_clear_events()
	check(server.send(server_a,_chat("only-a")).ok,"coordinator can address one connection")
	check(await _until(func() -> bool: return _captured(a,"packet").size()==1),"addressed response reaches A")
	check(_captured(b,"packet").is_empty(),"B does not receive A's private response")
	check(_captured(a,"packet")[0].connection_id==a_id,"client event uses its local connection ID")
	_clear_events()
	for sequence: int in range(1,33): check(a.send(a_id,_chat("ordered",sequence)).ok,"bounded queue accepts frame %d" % sequence)
	check(not a.send(a_id,_chat("overflow",33)).ok,"frame-count backpressure rejects 33rd queued frame")
	var a_peer: Dictionary = a.get_stats().peers[0]
	check(a_peer.queued_frames==32 and a_peer.queued_bytes<=TRANSPORT.MAX_OUTBOUND_BYTES,"frame queue remains bounded")
	check(await _until(func() -> bool: return _captured(server,"packet").size()==32),"all accepted ordered frames arrive")
	for index: int in range(_captured(server,"packet").size()):
		check(_captured(server,"packet")[index].packet.sequence==index+1,"TCP preserves packet order")
	_clear_events()
	for index: int in range(8): check(a.send(a_id,_bulk()).ok,"byte budget accepts full bulk frame")
	check(not a.send(a_id,_bulk()).ok,"byte budget rejects ninth 16KiB frame")
	check(a.get_stats().peers[0].queued_bytes==TRANSPORT.MAX_OUTBOUND_BYTES,"byte limit includes actual encoded frame bytes")
	check(await _until(func() -> bool: return _captured(server,"packet").size()==8),"bounded bulk queue drains without dropping accepted packets")
	_clear_events()
	var invalid: PROTOCOL.Packet = _chat("invalid"); invalid.payload.sender_id = -1
	check(not a.send(a_id,invalid).ok and a.get_stats().peers[0].queued_frames==0,"codec rejects invalid outgoing payload before queueing")
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	check(tcp.connect_to_host("127.0.0.1",started.port)==OK,"third TCP connection attempts admission")
	check(await _until(func() -> bool: tcp.poll(); return server.get_stats().totals.rejected==1),"connection cap rejects before WebSocket allocation")
	check(server.get_stats().connections==2,"rejection leaves existing clients connected")
	tcp.disconnect_from_host()
	check(a.request_ping(a_id).ok and not a.request_ping(a_id).ok,"at most one application ping outstanding")
	check(await _until(func() -> bool: return not _captured(a,"rtt").is_empty()),"matched application PONG measures RTT")
	check(a.get_stats().peers[0].rtt_ms>=0 and not a.get_stats().peers[0].ping_outstanding,"matched PONG clears outstanding nonce")
	check(_captured(server,"packet").is_empty() and _captured(a,"packet").is_empty(),"maintenance heartbeat is not gameplay input")
	var unsolicited: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.PONG,{"nonce":999,"client_time_ms":0,"server_time_ms":0})
	check(server.send(server_a,unsolicited).ok,"unsolicited PONG sent through real wire")
	check(await _until(func() -> bool: return a.get_stats().totals.unmatched_pongs==1),"unmatched PONG does not satisfy a nonce")
	for code: int in [-1,999,1004,1005,1006,1015,2999,5000]: check(not a.close(a_id,code,"bad").ok,"reserved close code rejected")
	check(not a.close(a_id,1000,"x".repeat(123)).ok and not a.close(a_id,1000,"я".repeat(62)).ok,"close reason limit uses UTF-8 bytes")
	check(not a.close(a_id,1000,"line\nbreak").ok,"close reason rejects controls")
	check(a.close(a_id,3001,"готово").ok,"application close code and valid Unicode reason accepted")
	check(await _until(func() -> bool: return a.get_stats().connections==0 and server.get_stats().connections==1),"graceful close completes by polling both peers")
	var closed: Array[Dictionary] = _captured(server,"closed")
	check(closed.size()==1 and closed[0].connection_id==server_a and closed[0].code==3001 and closed[0].reason=="готово" and closed[0].clean,"server sees actual close code and reason")
	check(not a.send(a_id,_chat("stale")).ok,"stale connection cannot send after close")
	_clear_events()
	var reconnect: Dictionary = a.start_client(url)
	check(reconnect.ok and reconnect.connection_id>a_id,"reconnect gets a new monotonic local ID")
	check(await _until(func() -> bool: return _open_count(server)==2 and _open_count(a)==1),"reconnect performs a new real handshake")
	check(_captured(server,"connected").size()==1 and _captured(server,"connected")[0].connection_id>maxi(server_a,server_b),"server does not reuse former routing ID")
	check(not a.send(a_id,_chat("old-id")).ok,"old ID stays invalid across reconnect")
	var stats_text: String = str(a.get_stats())
	check(not stats_text.contains(url) and not stats_text.contains("owner-a") and not stats_text.contains("resume_token"),"stats expose no URL or payload secrets")
	server.stop(); a.stop(); b.stop()
	check(await _until(func() -> bool: return server.get_stats().connections==0 and a.get_stats().connections==0 and b.get_stats().connections==0),"graceful stop closes real peers")
	check(server.get_stats().port==0 and server.get_stats().mode=="idle","stop releases listener")
	var probe: TCPServer = TCPServer.new()
	check(probe.listen(started.port,"127.0.0.1")==OK,"released listening port can be rebound")
	probe.stop()

func _test_malformed_frames() -> void:
	var server: TRANSPORT = _new()
	var started: Dictionary = server.start_server()
	check(started.ok,"malformed-frame server starts")
	if not started.ok: return
	var url: String = "ws://127.0.0.1:%d/" % started.port
	var healthy: TRANSPORT = _new(); var client: Dictionary = healthy.start_client(url)
	check(client.ok,"healthy peer starts beside hostile peer")
	check(await _until(func() -> bool: return _open_count(healthy)==1),"healthy peer connected")
	for attack: int in range(3):
		var raw: WebSocketPeer = WebSocketPeer.new(); _raw_sockets.append(raw)
		check(raw.connect_to_url(url)==OK,"direct test-only socket opens")
		check(await _until(func() -> bool: return raw.get_ready_state()==WebSocketPeer.STATE_OPEN and _open_count(server)==2),"hostile socket completes real handshake")
		_clear_events()
		var frame: PackedByteArray = PackedByteArray([0,1,2,3])
		if attack==1: frame = PROTOCOL.encode(_chat("valid bytes in wrong frame kind")).bytes
		if attack==2: frame.resize(PROTOCOL.MAX_FRAME+1)
		check(raw.send(frame,WebSocketPeer.WRITE_MODE_TEXT if attack==1 else WebSocketPeer.WRITE_MODE_BINARY)==OK,"raw malformed frame reaches socket")
		check(await _until(func() -> bool: return not _captured(server,"protocol_error").is_empty() and server.get_stats().connections==1),"malformed frame closes only its connection")
		check(_captured(server,"packet").is_empty(),"malformed frame never becomes an application packet")
		check(_captured(server,"closed").size()==1 and _captured(server,"closed")[0].code==1002,"protocol violation has explicit close status")
		check(_open_count(healthy)==1,"healthy peer survives other connection's violation")
		raw.close(-1); _raw_sockets.erase(raw)
	server.stop(true); healthy.stop(true)

func _test_timeouts() -> void:
	var handshake: TRANSPORT = _new({"handshake_timeout_ms":100})
	var started: Dictionary = handshake.start_server()
	check(started.ok,"handshake timeout listener starts")
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	check(tcp.connect_to_host("127.0.0.1",started.port)==OK,"raw TCP omits WebSocket handshake")
	_clear_events()
	check(await _until(func() -> bool: tcp.poll(); return handshake.get_stats().totals.timeouts==1 and handshake.get_stats().connections==0),"unfinished handshake has a bounded deadline")
	check(_captured(handshake,"timeout").size()==1 and _captured(handshake,"timeout")[0].reason=="handshake timeout","handshake timeout is explicit")
	tcp.disconnect_from_host(); handshake.stop(true)
	for ping_timeout: bool in [false,true]:
		var server: TRANSPORT = _new({"idle_timeout_ms":10000 if ping_timeout else 100,"ping_timeout_ms":100})
		var listen: Dictionary = server.start_server()
		var raw: WebSocketPeer = WebSocketPeer.new(); _raw_sockets.append(raw)
		check(raw.connect_to_url("ws://127.0.0.1:%d/" % listen.port)==OK,"timeout peer starts")
		check(await _until(func() -> bool: return _open_count(server)==1 and raw.get_ready_state()==WebSocketPeer.STATE_OPEN),"timeout peer handshakes")
		_clear_events()
		if ping_timeout: check(server.request_ping(server.get_stats().peers[0].connection_id).ok,"ping sent to peer that never answers")
		check(await _until(func() -> bool: return server.get_stats().totals.timeouts==1 and server.get_stats().connections==0),"silent peer closes at explicit deadline")
		var expected: String = "ping timeout" if ping_timeout else "idle timeout"
		check(_captured(server,"timeout").size()==1 and _captured(server,"timeout")[0].reason==expected,"timeout distinguishes heartbeat from idle")
		raw.close(-1); _raw_sockets.erase(raw); server.stop(true)

func _test_event_overflow(by_bytes: bool) -> void:
	var server: TRANSPORT = _new(); var client: TRANSPORT = _new()
	var started: Dictionary = server.start_server()
	var connected: Dictionary = client.start_client("ws://127.0.0.1:%d/" % started.port)
	check(connected.ok,"overflow client starts")
	check(await _until(func() -> bool: return _open_count(server)==1 and _open_count(client)==1),"overflow fixture performs real handshake")
	_clear_events()
	var sent: int = 0
	var target: int = 33 if by_bytes else 257
	while sent < target and server.get_stats().connections > 0:
		var batch: int = mini(8,target-sent)
		for index: int in range(batch):
			check(client.send(connected.connection_id,_bulk() if by_bytes else _chat("undrained",sent+index+1)).ok,"overflow fixture queues bounded batch")
		sent += batch
		check(await _until(func() -> bool: return server.get_stats().totals.rx_frames>=sent or server.get_stats().connections==0,2500,false),"overflow fixture reads real batch without draining application events")
		var stats: Dictionary = server.get_stats()
		check(stats.event_count<=TRANSPORT.MAX_EVENTS and stats.event_wire_bytes<=TRANSPORT.MAX_EVENT_BYTES,"undrained event queue remains bounded")
	check(server.get_stats().totals.event_overflows==1 and server.get_stats().connections==0 and server.get_stats().port==0,"event overflow atomically terminates incomplete streams and listener")
	var terminal: Array[Dictionary] = server.drain_events(TRANSPORT.MAX_EVENTS)
	check(terminal.size()==1 and terminal[0].type=="overflow" and terminal[0].connection_id==0,"consumer sees one explicit terminal overflow event")
	client.stop(true); server.stop(true)

func _test_automatic_ping() -> void:
	var server: TRANSPORT = _new({"ping_interval_ms":50,"idle_timeout_ms":200,"ping_timeout_ms":150})
	var client: TRANSPORT = _new({"idle_timeout_ms":200})
	var started: Dictionary = server.start_server()
	check(client.start_client("ws://127.0.0.1:%d/" % started.port).ok,"automatic heartbeat client starts")
	check(await _until(func() -> bool: return _open_count(server)==1 and _open_count(client)==1),"automatic heartbeat fixture connects")
	_clear_events()
	check(await _until(func() -> bool: return _captured(server,"rtt").size()>=5),"automatic application heartbeat survives beyond the idle window")
	check(server.get_stats().totals.timeouts==0 and client.get_stats().totals.timeouts==0,"answered automatic pings preserve both connections")
	check(_captured(server,"packet").is_empty() and _captured(client,"packet").is_empty(),"automatic heartbeats remain outside coordinator events")
	server.stop(true); client.stop(true)

func _cleanup() -> void:
	for transport: TRANSPORT in _transports: transport.stop(true); transport.drain_events(TRANSPORT.MAX_EVENTS)
	for socket: WebSocketPeer in _raw_sockets: socket.close(-1)
	_raw_sockets.clear(); _events.clear(); _transports.clear()
	for index: int in range(4): await process_frame
