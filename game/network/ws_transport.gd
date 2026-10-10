class_name BlockfieldWSTransport
extends RefCounted
## Poll-driven WebSocket transport. IDs identify connections, never actors.
const PROTOCOL = preload("res://network/protocol.gd")
const MAX_CONNECTIONS: int = 32
const MAX_QUEUE_FRAMES: int = 32
const MAX_OUTBOUND_BYTES: int = 131072
const MAX_EVENTS: int = 256
const MAX_EVENT_BYTES: int = 524288
const MAX_READ_PER_PEER: int = 16
const MAX_READ_PER_POLL: int = 64
const MAX_ACCEPT_PER_POLL: int = 4
const ENGINE_BUFFER_BYTES: int = 262144
const ENGINE_QUEUE_PACKETS: int = 64
const MAX_REASON_BYTES: int = 122

class PendingFrame extends RefCounted:
	var bytes: PackedByteArray
	var ping_nonce: int = 0

class Connection extends RefCounted:
	var id: int = 0
	var socket: WebSocketPeer
	var opened: bool = false
	var created_us: int = 0
	var last_receive_us: int = 0
	var last_ping_us: int = 0
	var close_started_us: int = 0
	var close_code: int = 1000
	var close_reason: String = "closed"
	var closing: bool = false
	var queue: Array[PendingFrame] = []
	var queue_bytes: int = 0
	var pending_nonce: int = 0
	var ping_started_us: int = 0
	var ping_sent_us: int = 0
	var rtt_ms: float = -1.0
	var rx_frames: int = 0
	var tx_frames: int = 0

var _mode: String = "idle"
var _server: TCPServer
var _connections: Dictionary[int, Connection] = {}
var _next_id: int = 1
var _next_nonce: int = 1
var _events: Array[Dictionary] = []
var _event_bytes: int = 0
var _read_rotation: int = 0
var _stopping: bool = false
var _config: Dictionary = {"connection_limit":32,"handshake_timeout_ms":5000,"idle_timeout_ms":10000,"close_timeout_ms":500,"ping_interval_ms":2000,"ping_timeout_ms":5000}
var _totals: Dictionary = {"accepted":0,"rejected":0,"closed":0,"rx_frames":0,"tx_frames":0,"rx_bytes":0,"tx_bytes":0,"protocol_errors":0,"timeouts":0,"backpressure":0,"event_overflows":0,"unmatched_pongs":0}

func configure(options: Dictionary) -> Dictionary:
	if _mode != "idle" or not _connections.is_empty(): return _result(false,"transport is active")
	var limits: Dictionary = {"connection_limit":Vector2i(1,MAX_CONNECTIONS),"handshake_timeout_ms":Vector2i(100,60000),"idle_timeout_ms":Vector2i(50,120000),"close_timeout_ms":Vector2i(50,5000),"ping_interval_ms":Vector2i(0,60000),"ping_timeout_ms":Vector2i(50,60000)}
	for key: Variant in options:
		if not limits.has(key) or typeof(options[key]) != TYPE_INT: return _result(false,"invalid configuration")
		var bounds: Vector2i = limits[key]
		if options[key] < bounds.x or options[key] > bounds.y: return _result(false,"configuration out of range")
	for key: Variant in options: _config[key] = options[key]
	return _result(true)

func start_client(url: String) -> Dictionary:
	if _mode != "idle" or not _connections.is_empty(): return _result(false,"transport is active")
	if url.length() > 2048 or url.contains("#") or not (url.begins_with("ws://") or url.begins_with("wss://")) or not PROTOCOL.valid_text_bytes(url.to_utf8_buffer()): return _result(false,"invalid WebSocket URL")
	var authority: String = url.get_slice("/",2)
	if authority.is_empty() or authority.contains("@"): return _result(false,"invalid URL authority")
	var connection: Connection = _new_connection()
	var error: Error = connection.socket.connect_to_url(url)
	if error != OK: connection.socket.close(-1); return _result(false,"connect failed",error)
	_mode = "client"; _stopping = false
	_connections[connection.id] = connection
	var result: Dictionary = _result(true); result["connection_id"] = connection.id
	return result

func start_server(port: int = 0, bind_address: String = "127.0.0.1") -> Dictionary:
	if OS.has_feature("web"): return _result(false,"native server unavailable in Web export")
	if _mode != "idle" or not _connections.is_empty(): return _result(false,"transport is active")
	if port < 0 or port > 65535 or bind_address.is_empty() or bind_address.length() > 128: return _result(false,"invalid bind address or port")
	_server = TCPServer.new()
	var error: Error = _server.listen(port,bind_address)
	if error != OK: _server = null; return _result(false,"listen failed",error)
	_mode = "server"; _stopping = false
	var local_port: int = _server.get_local_port()
	if not _emit({"type":"listening","connection_id":0,"port":local_port}): return _result(false,"event queue full")
	var result: Dictionary = _result(true); result["port"] = local_port
	return result

func _new_connection() -> Connection:
	var connection: Connection = Connection.new()
	connection.id = _next_id; _next_id += 1
	connection.socket = WebSocketPeer.new()
	connection.socket.inbound_buffer_size = ENGINE_BUFFER_BYTES
	connection.socket.outbound_buffer_size = ENGINE_BUFFER_BYTES
	connection.socket.max_queued_packets = ENGINE_QUEUE_PACKETS
	connection.created_us = Time.get_ticks_usec(); connection.last_receive_us = connection.created_us
	connection.last_ping_us = connection.created_us
	return connection

func send(connection_id: int, packet: PROTOCOL.Packet) -> Dictionary:
	var encoded: PROTOCOL.Result = PROTOCOL.encode(packet)
	if not encoded.ok: return _result(false,encoded.error)
	return _enqueue_frame(connection_id,encoded.bytes)

func send_prepared(connection_id: int, prepared: PROTOCOL.FrozenFrame) -> Dictionary:
	if prepared == null or not prepared.valid(): return _result(false,"invalid prepared frame")
	return _enqueue_frame(connection_id,prepared.bytes())

func _enqueue_frame(connection_id: int, bytes: PackedByteArray) -> Dictionary:
	if not _connections.has(connection_id): return _result(false,"unknown connection")
	var connection: Connection = _connections[connection_id]
	if connection.closing or not connection.opened or connection.socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return _result(false,"connection is not open")
	if connection.queue.size() >= MAX_QUEUE_FRAMES: _totals.backpressure += 1; return _result(false,"outbound backpressure")
	if connection.queue_bytes + connection.socket.get_current_outbound_buffered_amount() + bytes.size() > MAX_OUTBOUND_BYTES:
		_totals.backpressure += 1; return _result(false,"outbound backpressure")
	var frame: PendingFrame = PendingFrame.new(); frame.bytes = bytes
	connection.queue.append(frame); connection.queue_bytes += frame.bytes.size()
	return _result(true)

func request_ping(connection_id: int) -> Dictionary:
	if not _connections.has(connection_id): return _result(false,"unknown connection")
	var connection: Connection = _connections[connection_id]
	if connection.pending_nonce != 0: return _result(false,"ping already outstanding")
	var nonce: int = _next_nonce
	_next_nonce = 1 if _next_nonce >= PROTOCOL.U32_MAX else _next_nonce + 1
	var packet: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.PING,{"nonce":nonce,"client_time_ms":_clock_ms()})
	var result: Dictionary = send(connection_id,packet)
	if not result.ok: return result
	connection.queue[-1].ping_nonce = nonce
	connection.pending_nonce = nonce; connection.ping_started_us = Time.get_ticks_usec()
	connection.last_ping_us = connection.ping_started_us
	return result

func poll() -> void:
	if _server != null and not _stopping: _accept()
	var ids: Array[int] = []
	ids.assign(_connections.keys())
	if not ids.is_empty():
		var remaining: int = MAX_READ_PER_POLL
		for offset: int in range(ids.size()):
			var id: int = ids[(_read_rotation + offset) % ids.size()]
			if _connections.has(id): remaining -= _poll_connection(_connections[id],remaining)
		_read_rotation = (_read_rotation + 1) % ids.size()
	if _connections.is_empty() and (_mode == "client" or _stopping):
		_mode = "idle"; _stopping = false

func _accept() -> void:
	var accepted_this_poll: int = 0
	while _server != null and _server.is_connection_available() and accepted_this_poll < MAX_ACCEPT_PER_POLL:
		accepted_this_poll += 1
		var stream: StreamPeerTCP = _server.take_connection()
		if stream == null: break
		if _connections.size() >= int(_config.connection_limit):
			stream.disconnect_from_host(); _totals.rejected += 1; continue
		stream.set_no_delay(true)
		var connection: Connection = _new_connection()
		var error: Error = connection.socket.accept_stream(stream)
		if error != OK: stream.disconnect_from_host(); connection.socket.close(-1); _totals.rejected += 1; continue
		_connections[connection.id] = connection; _totals.accepted += 1

func _poll_connection(connection: Connection, budget: int) -> int:
	connection.socket.poll()
	var state: WebSocketPeer.State = connection.socket.get_ready_state()
	var now: int = Time.get_ticks_usec()
	if state == WebSocketPeer.STATE_CLOSED:
		_finish_close(connection); return 0
	if connection.closing or state == WebSocketPeer.STATE_CLOSING:
		if not connection.closing:
			connection.closing = true; connection.close_started_us = now
			connection.queue.clear(); connection.queue_bytes = 0
		if now - connection.close_started_us >= int(_config.close_timeout_ms) * 1000:
			connection.socket.close(-1); _finish_close(connection,true)
		return 0
	if state == WebSocketPeer.STATE_CONNECTING:
		if now - connection.created_us >= int(_config.handshake_timeout_ms) * 1000:
			_timeout(connection,"handshake timeout")
		return 0
	if not connection.opened:
		connection.opened = true; connection.last_receive_us = now; connection.last_ping_us = now
		if not _emit({"type":"connected","connection_id":connection.id}): return 0
	var read: int = 0
	while _connections.has(connection.id) and not connection.closing and connection.socket.get_available_packet_count() > 0 and read < mini(MAX_READ_PER_PEER,budget):
		var data: PackedByteArray = connection.socket.get_packet()
		read += 1; _totals.rx_frames += 1; _totals.rx_bytes += data.size(); connection.rx_frames += 1
		if connection.socket.was_string_packet(): _protocol_error(connection,"binary frames required"); break
		var decoded: PROTOCOL.Result = PROTOCOL.decode(data)
		if not decoded.ok: _protocol_error(connection,decoded.error); break
		connection.last_receive_us = now
		if not _receive(connection,decoded.packet,data.size()): break
	if not _connections.has(connection.id) or connection.closing: return read
	if connection.pending_nonce != 0 and now - connection.ping_started_us >= int(_config.ping_timeout_ms) * 1000:
		_timeout(connection,"ping timeout"); return read
	if now - connection.last_receive_us >= int(_config.idle_timeout_ms) * 1000:
		_timeout(connection,"idle timeout"); return read
	if int(_config.ping_interval_ms) > 0 and connection.pending_nonce == 0 and now - connection.last_ping_us >= int(_config.ping_interval_ms) * 1000:
		request_ping(connection.id)
	_flush(connection,now)
	return read

func _receive(connection: Connection, packet: PROTOCOL.Packet, frame_size: int) -> bool:
	if packet.kind == PROTOCOL.Kind.PING:
		var pong: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.PONG,{"nonce":packet.payload.nonce,"client_time_ms":packet.payload.client_time_ms,"server_time_ms":_clock_ms()})
		var result: Dictionary = send(connection.id,pong)
		if not result.ok: _timeout(connection,"heartbeat backpressure"); return false
		return true
	if packet.kind == PROTOCOL.Kind.PONG:
		if connection.pending_nonce == 0 or packet.payload.nonce != connection.pending_nonce or connection.ping_sent_us == 0:
			_totals.unmatched_pongs += 1; return true
		connection.rtt_ms = float(Time.get_ticks_usec() - connection.ping_sent_us) / 1000.0
		connection.pending_nonce = 0; connection.ping_sent_us = 0
		return _emit({"type":"rtt","connection_id":connection.id,"rtt_ms":connection.rtt_ms})
	return _emit({"type":"packet","connection_id":connection.id,"packet":packet},frame_size)

func _flush(connection: Connection, now: int) -> void:
	while not connection.queue.is_empty() and connection.socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var frame: PendingFrame = connection.queue[0]
		if connection.socket.get_current_outbound_buffered_amount() + frame.bytes.size() > MAX_OUTBOUND_BYTES: return
		var error: Error = connection.socket.send(frame.bytes,WebSocketPeer.WRITE_MODE_BINARY)
		if error == ERR_OUT_OF_MEMORY or error == ERR_BUSY: return
		if error != OK: close(connection.id,1011,"socket send failed"); return
		connection.queue.pop_front(); connection.queue_bytes -= frame.bytes.size()
		connection.tx_frames += 1; _totals.tx_frames += 1; _totals.tx_bytes += frame.bytes.size()
		if frame.ping_nonce != 0: connection.ping_sent_us = now

func close(connection_id: int, code: int = 1000, reason: String = "closed") -> Dictionary:
	if not _connections.has(connection_id): return _result(false,"unknown connection")
	if not _valid_close_code(code) or reason.length() > MAX_REASON_BYTES or reason.to_utf8_buffer().size() > MAX_REASON_BYTES or not PROTOCOL.valid_text_bytes(reason.to_utf8_buffer()): return _result(false,"invalid close code or reason")
	var connection: Connection = _connections[connection_id]
	if connection.closing: return _result(true)
	connection.closing = true; connection.close_started_us = Time.get_ticks_usec()
	# Browser WebSocket.close only accepts 1000 and application codes 3000..4999.
	# Keep native status codes on the server; map client statuses into our 400x range.
	var wire_code: int = _wire_close_code(code,OS.has_feature("web"))
	connection.close_code = wire_code; connection.close_reason = reason
	connection.queue.clear(); connection.queue_bytes = 0
	if connection.socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		connection.socket.close(-1); _finish_close(connection,true)
	else: connection.socket.close(wire_code,reason)
	var result: Dictionary = _result(true); result["close_code"] = wire_code
	return result

func stop(force: bool = false) -> void:
	if _server != null: _server.stop(); _server = null
	_stopping = true
	for id: int in _connections.keys():
		if not _connections.has(id): continue
		var connection: Connection = _connections[id]
		if force:
			connection.close_code = 1001; connection.close_reason = "transport stopped"
			connection.socket.close(-1); _finish_close(connection,true)
		else: close(id,1001,"transport stopped")
	if _connections.is_empty(): _mode = "idle"; _stopping = false

func _timeout(connection: Connection, reason: String) -> void:
	_totals.timeouts += 1
	_emit({"type":"timeout","connection_id":connection.id,"reason":reason})
	close(connection.id,1001,reason)

func _protocol_error(connection: Connection, reason: String) -> void:
	_totals.protocol_errors += 1
	_emit({"type":"protocol_error","connection_id":connection.id,"reason":reason})
	close(connection.id,1002,"invalid protocol frame")

func _finish_close(connection: Connection, forced: bool = false) -> void:
	if not _connections.has(connection.id): return
	var code: int = connection.close_code if forced else connection.socket.get_close_code()
	var reason: String = connection.close_reason if forced else connection.socket.get_close_reason()
	_connections.erase(connection.id); connection.queue.clear(); connection.queue_bytes = 0
	_totals.closed += 1
	_emit({"type":"closed","connection_id":connection.id,"code":code,"reason":reason,"clean":not forced and code >= 0})

func drain_events(max_count: int = 64) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(clampi(max_count,0,MAX_EVENTS)):
		if _events.is_empty(): break
		var event: Dictionary = _events.pop_front()
		_event_bytes -= int(event.get("_wire_bytes",0)); event.erase("_wire_bytes")
		result.append(event)
	return result

func _emit(event: Dictionary, wire_bytes: int = 0) -> bool:
	if _events.size() >= MAX_EVENTS or _event_bytes + wire_bytes > MAX_EVENT_BYTES:
		# A consumer that stops draining cannot keep an incomplete message stream.
		# Abort all connections and expose one explicit terminal overflow event.
		_totals.event_overflows += 1
		_events.clear(); _event_bytes = 0
		if _server != null: _server.stop(); _server = null
		for connection: Connection in _connections.values(): connection.socket.close(-1)
		_totals.closed += _connections.size(); _connections.clear()
		_mode = "idle"; _stopping = false
		_events.append({"type":"overflow","connection_id":0,"reason":"event queue full"})
		return false
	event["_wire_bytes"] = wire_bytes
	_events.append(event); _event_bytes += wire_bytes
	return true

func get_stats() -> Dictionary:
	var peers: Array[Dictionary] = []
	for connection: Connection in _connections.values():
		peers.append({"connection_id":connection.id,"state":"closing" if connection.closing else ("open" if connection.opened else "connecting"),"queued_frames":connection.queue.size(),"queued_bytes":connection.queue_bytes,"socket_buffered_bytes":connection.socket.get_current_outbound_buffered_amount(),"rx_frames":connection.rx_frames,"tx_frames":connection.tx_frames,"rtt_ms":connection.rtt_ms,"ping_outstanding":connection.pending_nonce!=0})
	return {"mode":_mode,"port":_server.get_local_port() if _server!=null else 0,"connections":_connections.size(),"event_count":_events.size(),"event_wire_bytes":_event_bytes,"peers":peers,"totals":_totals.duplicate()}

static func _valid_close_code(code: int) -> bool:
	return (code >= 1000 and code <= 1014 and code not in [1004,1005,1006]) or (code >= 3000 and code <= 4999)

static func _wire_close_code(code: int, web: bool) -> int:
	return 4000 + code - 1000 if web and code != 1000 and code < 3000 else code

static func _clock_ms() -> int:
	return (Time.get_ticks_usec() / 1000) & PROTOCOL.U32_MAX

static func _result(ok: bool, error: String = "", code: int = OK) -> Dictionary:
	return {"ok":ok,"error":error,"code":code}

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _server != null: _server.stop()
		for connection: Connection in _connections.values(): connection.socket.close(-1)
		_connections.clear()
