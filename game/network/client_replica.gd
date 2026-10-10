class_name BlockfieldClientReplica
extends RefCounted
## Poll-driven client model. Presentation adopts maps through trusted callbacks.
const P = preload("res://network/protocol.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const TRANSFER = preload("res://network/map_transfer.gd")
const PREDICTION = preload("res://network/client_prediction.gd")
const RULES = preload("res://simulation/player_rules.gd")
const COMPATIBILITY = preload("res://network/compatibility.gd")
const STATE_KIND := 14
const MAX_EVENTS := 512
const CLOSE_REASONS := ["ping timeout","idle timeout","handshake timeout","heartbeat backpressure","transport stopped","socket send failed","invalid protocol frame","invalid input stream","input clock needs resync","connection lost","map connection lost","HELLO rejected","HELLO timeout","admission unavailable","map join timeout","map preparation queue timeout","invalid map readiness","gameplay before map readiness","invalid client packet direction","transport event overflow"]
var game := TRANSPORT.new()
var bulk := TRANSPORT.new()
var transfer := TRANSFER.new()
var assembler := TRANSFER.TransactionAssembler.new()
var prediction := PREDICTION.new()
var data: VoxelData
var status := "idle"
var last_error := ""
var actor_id := 0
var epoch := 0
var _game_id := 0
var _bulk_id := 0
var _map_url := ""
var _name := "Player"
var _role := 0
var _resume := PackedByteArray()
var _welcome: P.Packet
var _preparing: Dictionary = {}
var _confirmed: Dictionary = {}
var _remote: Dictionary[int,PREDICTION.RemotePoseBuffer] = {}
var _events: Array[Dictionary] = []
var _chat_intent := 0
var _chat_sequence := 0
var _request_sequence := 0
var _event_cursor := 0
var _predicted_effects: Dictionary[String,int] = {}
var _predicted_order: Array[String] = []
var _last_snapshot_tick := -1
var _last_input_tick := -1
var _snapshot_time_ms := 0
var _install_map: Callable
var _apply_map: Callable

func set_map_callbacks(install: Callable, apply_transaction: Callable) -> void:
	_install_map = install
	_apply_map = apply_transaction

func connect_to(game_url: String, map_url: String, player_name: String, spectator: bool = false, resume_token: PackedByteArray = PackedByteArray()) -> Dictionary:
	if status not in ["idle","closed","failed"] or player_name.is_empty() or player_name.to_utf8_buffer().size() > 64 \
			or not P.valid_text_bytes(player_name.to_utf8_buffer()) or resume_token.size() not in [0,32]: return {"ok":false,"error":"invalid client start"}
	if not (map_url.begins_with("ws://") or map_url.begins_with("wss://")) or map_url.contains("@") or map_url.contains("#"):
		return {"ok":false,"error":"invalid bulk endpoint"}
	close()
	_name = player_name
	_role = 1 if spectator else 0
	_resume = resume_token.duplicate()
	_map_url = map_url
	var started := game.start_client(game_url)
	if not started.ok: return started
	_game_id = started.connection_id
	status = "connecting"
	last_error = ""
	return {"ok":true,"error":""}

func _hello(map_role: bool = false) -> P.Packet:
	return P.make_packet(P.Kind.HELLO,{"role":2 if map_role else _role,"name":_name,"build_hash":COMPATIBILITY.build_hash(),
		"rules_hash":COMPATIBILITY.rules_hash(),"resume_token":PackedByteArray() if map_role else _resume,
		"bulk_token":_welcome.payload.bulk_token if map_role else PackedByteArray()})

func close() -> void:
	game.stop(true)
	bulk.stop(true)
	# Forced stop emits terminal events. They belong to the discarded stream,
	# including when this same Replica is reused immediately by connect_to().
	game.drain_events(TRANSPORT.MAX_EVENTS)
	bulk.drain_events(TRANSPORT.MAX_EVENTS)
	transfer.reset()
	assembler.cancel()
	for buffer: PREDICTION.RemotePoseBuffer in _remote.values(): buffer.clear()
	_remote.clear()
	_events.clear()
	_confirmed.clear()
	prediction = PREDICTION.new()
	data = null
	actor_id = 0
	epoch = 0
	_welcome = null
	_preparing.clear()
	_chat_intent = 0
	_chat_sequence = 0
	_request_sequence = 0
	_event_cursor = 0
	_predicted_effects.clear()
	_predicted_order.clear()
	_last_snapshot_tick = -1
	_last_input_tick = -1
	status = "closed"

func _fail(message: String) -> void:
	close()
	last_error = message
	status = "failed"

func _emit(event: Dictionary) -> void:
	if _events.size() >= MAX_EVENTS:
		_fail("client event queue requires resync")
		return
	_events.append(event.duplicate(true))

static func terminal_error(channel: String, event: Dictionary) -> String:
	# Peer text is not trusted diagnostics; expose only known constant reasons.
	var reason := str(event.get("reason",""))
	if reason not in CLOSE_REASONS: reason = "remote close"
	match str(event.get("type","")):
		"timeout": return "%s timeout: %s" % [channel,reason]
		"protocol_error": return "%s protocol error" % channel
		"overflow": return "%s event queue overflow" % channel
		_: return "%s closed (%d): %s" % [channel,int(event.get("code",-1)),reason]

func poll() -> void:
	if status in ["idle","closed","failed"]: return
	game.poll()
	bulk.poll()
	for event: Dictionary in game.drain_events():
		if status == "failed": break
		match event.type:
			"connected":
				if not game.send(_game_id,_hello()).ok: _fail("HELLO send failed")
				else: status = "joining"
			"packet": _game_packet(event.packet)
			"closed", "timeout", "protocol_error", "overflow": _fail(terminal_error("game",event))
	for event: Dictionary in bulk.drain_events():
		if status == "failed": break
		match event.type:
			"connected":
				if _welcome == null or not bulk.send(_bulk_id,_hello(true)).ok: _fail("bulk HELLO failed")
			"packet":
				if status != "loading" or event.packet.kind != P.Kind.MAP_CHUNK: _fail("invalid bulk packet direction")
				elif not transfer.consume(event.packet).ok: _fail("map chunk rejected")
			"closed", "timeout", "protocol_error", "overflow":
				if status == "loading": _fail(terminal_error("map",event))
	if status == "loading":
		var progress := transfer.poll(-1,2)
		if not progress.ok:
			_fail(progress.error)
			return
		if transfer.get_stats().status == "ready": _install_ready()
	elif status in ["synchronizing","live"]:
		var progress := assembler.poll()
		if not progress.ok: _fail(progress.error)

func _game_packet(packet: P.Packet) -> void:
	match packet.kind:
		P.Kind.MATCH_PREPARING:
			_accept_preparing(packet)
		P.Kind.WELCOME:
			_accept_welcome(packet)
		P.Kind.MAP_BEGIN:
			if status != "joining" or _welcome == null or packet.epoch != epoch:
				_fail("unexpected map baseline")
				return
			transfer.reset(epoch)
			if not transfer.consume(packet).ok:
				_fail("map baseline rejected")
				return
			status = "loading"
			var started := bulk.start_client(_map_url)
			if not started.ok: _fail(started.error)
			else: _bulk_id = started.connection_id
		P.Kind.MAP_END:
			if status != "loading" or not transfer.consume(packet).ok: _fail("map barrier rejected")
		P.Kind.MAP_DELTA:
			if status == "loading":
				if not transfer.consume(packet).ok: _fail("joining map transaction rejected")
			elif status in ["synchronizing","live"]:
				var assembled := assembler.push(packet)
				if not assembled.ok: _fail(assembled.error)
				elif assembled.get("complete",false):
					var applied: bool = bool(_apply_map.call(assembled.transaction)) if _apply_map.is_valid() else bool(data.apply_transaction(assembled.transaction).ok)
					if not applied or data.map_sequence != assembled.transaction.map_sequence: _fail("live transaction needs baseline")
			else: _fail("unexpected map transaction")
		P.Kind.CHAT:
			if status != "live" or packet.epoch != epoch or packet.payload.sender_id <= 0 or packet.payload.message_id <= _chat_sequence:
				_fail("invalid confirmed chat")
				return
			_chat_sequence = packet.payload.message_id
			_emit({"type":"chat","tick":packet.tick,"sender_id":packet.payload.sender_id,"text":packet.payload.text,"channel":packet.payload.channel,"message_id":packet.payload.message_id})
		STATE_KIND: _apply_snapshot(packet)
		P.Kind.GAME_EVENTS: _apply_events(packet)
		_: _fail("invalid server packet direction")

func _discard_epoch_stream(new_epoch: int) -> void:
	# Keep the authenticated game socket/endpoints, but no old prediction,
	# map/capability or presentation state may survive a reset announcement.
	bulk.stop(true)
	bulk.drain_events(TRANSPORT.MAX_EVENTS)
	_bulk_id = 0
	transfer.reset(new_epoch)
	assembler.cancel()
	for buffer: PREDICTION.RemotePoseBuffer in _remote.values(): buffer.clear()
	_remote.clear(); _events.clear(); _confirmed.clear()
	prediction = PREDICTION.new()
	data = null
	_chat_intent = 0; _chat_sequence = 0; _request_sequence = 0; _event_cursor = 0
	_predicted_effects.clear(); _predicted_order.clear()
	_last_snapshot_tick = -1; _snapshot_time_ms = 0
	_last_input_tick = -1
	_welcome = null
	last_error = ""

func _accept_preparing(packet: P.Packet) -> void:
	if not P.encode(packet).ok or packet.epoch <= epoch \
			or status not in ["joining","loading","synchronizing","live","preparing"] \
			or (actor_id != 0 and packet.payload.actor_id != actor_id) \
			or (actor_id == 0 and (status != "joining" or _welcome != null)):
		_fail("invalid match preparation announcement")
		return
	_discard_epoch_stream(packet.epoch)
	actor_id = packet.payload.actor_id
	epoch = packet.epoch
	_preparing = packet.payload.duplicate(true)
	status = "preparing"
	_emit({"type":"epoch_reset","epoch":epoch})
	_emit({"type":"match_preparing","epoch":epoch,"actor_id":actor_id,"profile":_preparing.profile})

func _accept_welcome(packet: P.Packet) -> void:
	if not P.encode(packet).ok or packet.epoch<=0 or packet.payload.server_hz!=60 \
			or packet.payload.build_hash!=COMPATIBILITY.build_hash() or packet.payload.rules_hash!=COMPATIBILITY.rules_hash():
		_fail("incompatible WELCOME")
		return
	if not _preparing.is_empty():
		if status != "preparing" or packet.epoch != epoch or packet.payload.actor_id != actor_id \
				or packet.payload.spawn_generation != _preparing.spawn_generation or packet.payload.profile != _preparing.profile:
			_fail("WELCOME does not match announced preparation")
			return
	elif status != "joining" or _welcome != null or actor_id != 0:
		_fail("incompatible WELCOME")
		return
	_welcome=P.make_packet(packet.kind,packet.payload.duplicate(true),packet.epoch,packet.tick,packet.sequence)
	actor_id=packet.payload.actor_id
	epoch=packet.epoch
	_resume=packet.payload.resume_token.duplicate()
	_preparing.clear()
	status = "joining"

static func _effect_identity(event: Dictionary, predicted: bool = false) -> String:
	var kind: String = event.get("kind","") if predicted else event.type
	if kind == "grenade_release": kind = "grenade_thrown"
	return "%d:%d:%d:%d:%s" % [event.epoch,event.owner_id,event.spawn_generation,
		event.get("input_sequence",0) if predicted else event.action_sequence,kind]

func _apply_events(packet: P.Packet) -> void:
	if status not in ["synchronizing","live"] or packet.epoch != epoch:
		_fail("events before installed map")
		return
	var p: Dictionary = packet.payload
	if p.last_sequence <= _event_cursor: return
	if p.first_sequence <= _event_cursor:
		_fail("overlapping confirmed event cursor")
		return
	for source: Dictionary in p.events:
		if source.type == "events_resync_required":
			_fail("confirmed effects require new baseline")
			return
		# Privacy is enforced again at the presentation boundary.
		if P.EVENTS_CODEC.visibility(source.type) == "owner" and source.owner_id != actor_id:
			_fail("foreign private event")
			return
		var event := source.duplicate(true)
		var key := _effect_identity(event)
		event.predicted_already_played = _predicted_effects.has(key)
		if event.predicted_already_played:
			_predicted_effects[key] -= 1
			if _predicted_effects[key] <= 0: _predicted_effects.erase(key)
		_emit(event)
		if status == "failed": return
	_event_cursor = p.last_sequence

func _install_ready() -> void:
	var ready := transfer.take_ready()
	if not ready.ok:
		_fail("ready map unavailable")
		return
	data = ready.data
	if _install_map.is_valid() and not bool(_install_map.call(data)):
		_fail("map presentation installation failed")
		return
	if not assembler.reset(ready.epoch,ready.map_sequence,data.dimensions,ready.tick).ok:
		_fail("live map assembler rejected")
		return
	var packet := P.make_packet(P.Kind.MAP_READY,{"snapshot_id":ready.snapshot_id,"map_sequence":ready.map_sequence,"hash":ready.hash},ready.epoch,ready.tick,ready.map_sequence)
	if not game.send(_game_id,packet).ok:
		_fail("MAP_READY send failed")
		return
	status = "synchronizing"
	_emit({"type":"map_installed","epoch":epoch,"map_sequence":data.map_sequence})

func _apply_snapshot(packet: P.Packet) -> void:
	var p: Dictionary = packet.payload
	if status not in ["synchronizing","live"] or data == null or packet.epoch != epoch or p.epoch != epoch \
			or p.owner_state.player_id != actor_id or packet.tick != p.tick or packet.sequence != p.owner_state.spawn_generation \
			or p.dimensions != data.dimensions or p.map_sequence != data.map_sequence or _welcome == null \
			or p.profile != ("0.75" if _welcome.payload.profile == 0 else "0.76"):
		_fail("state does not match installed terrain/owner")
		return
	if packet.tick <= _last_snapshot_tick: return
	var result: Dictionary
	var old_owner := prediction.get_state()
	if old_owner == null or old_owner.spawn_generation != p.owner_state.spawn_generation or status == "synchronizing":
		_last_input_tick = packet.tick
	if old_owner != null and old_owner.spawn_generation != p.owner_state.spawn_generation: _request_sequence = 0
	if status == "synchronizing": result = prediction.reset(p.owner_state,p.tick,p.map_sequence)
	else:
		result = prediction.reconcile(p.owner_state,p.tick,p.map_sequence,data)
		# Explicit terrain rebase: stop input until every old command is acknowledged.
		# The server's lease neutralizes controls; sequence/generation never rewind.
		if not result.ok and prediction.get_status().needs_rebase and p.owner_state.consumed_input_sequence == prediction.get_status().last_submitted:
			result = prediction.reset(p.owner_state,p.tick,p.map_sequence)
	if not result.ok and not prediction.get_status().needs_rebase:
		_fail(result.error)
		return
	_confirmed = p
	_event_cursor = maxi(_event_cursor,p.event_sequence)
	_last_snapshot_tick = packet.tick
	_snapshot_time_ms = Time.get_ticks_msec()
	status = "live"
	var present: Dictionary[int,bool] = {}
	for actor: Dictionary in p.actors:
		if actor.id == actor_id: continue
		present[actor.id] = true
		if not _remote.has(actor.id): _remote[actor.id] = PREDICTION.RemotePoseBuffer.new()
		_remote[actor.id].push(actor,epoch,packet.tick)
	for id: int in _remote.keys():
		if not present.has(id):
			_remote[id].clear()
			_remote.erase(id)

func submit_input(buttons: int, move: Vector2, yaw: float, pitch: float, tool: int = 255, weapon: int = 255) -> Dictionary:
	if status != "live" or prediction.get_status().needs_rebase: return {"ok":false,"error":"client state not ready"}
	if prediction.get_status().map_sequence != data.map_sequence: return {"ok":false,"error":"waiting for matching terrain state"}
	var owner := prediction.get_state()
	var command := RULES.Command.new()
	command.sequence = prediction.get_status().last_submitted+1
	command.spawn_generation = owner.spawn_generation
	command.buttons = buttons
	command.move = move
	command.yaw = yaw
	command.pitch = pitch
	command.tool = tool
	command.weapon = weapon
	# Replay retimes pending commands for local prediction. It must never move
	# the transmitted command clock forward again on every authority snapshot.
	var input_tick := maxi(_last_input_tick+1,_last_snapshot_tick+1)
	var record := {"input_sequence":command.sequence,"input_tick":input_tick,"buttons":buttons,"tool":tool,"weapon":weapon,
		"move_x":move.x,"move_z":move.y,"yaw":yaw,"pitch":pitch}
	var packet := P.make_packet(P.Kind.INPUT_BATCH,{"records":[record]},epoch,record.input_tick,command.spawn_generation)
	if not command.valid() or not P.encode(packet).ok: return {"ok":false,"error":"invalid input"}
	# A send failure ends this stream; never predict a command absent from authority.
	var sent := game.send(_game_id,packet)
	if not sent.ok:
		_fail("input send failed: "+str(sent.error))
		return {"ok":false,"error":last_error}
	_last_input_tick = input_tick
	var result := prediction.predict(command,data)
	if not result.ok:
		_fail(result.error)
		return result
	for effect: Dictionary in result.events:
		var key := _effect_identity(effect,true)
		_predicted_effects[key] = int(_predicted_effects.get(key,0))+1
		_predicted_order.append(key)
		# Cosmetic retention is bounded independently of authority/input history.
		if _predicted_order.size() > 2048:
			var expired: String = _predicted_order.pop_front()
			_predicted_effects.erase(expired)
		_emit(effect)
	return {"ok":true,"error":"","sequence":command.sequence}

func send_chat(text: String, team_only: bool = false) -> bool:
	if status != "live": return false
	var owner := prediction.get_state()
	var packet := P.make_packet(P.Kind.CHAT,{"channel":1 if team_only else 0,"sender_id":0,"message_id":_chat_intent+1,"text":text},epoch,maxi(0,owner.last_tick),owner.spawn_generation)
	if not game.send(_game_id,packet).ok: return false
	_chat_intent += 1
	return true

func request_team(team: int) -> bool:
	return _send_request(0,team)

func request_block_color(color: int) -> bool:
	return _send_request(1,color)

func _send_request(action: int, value: int) -> bool:
	if status != "live": return false
	var owner := prediction.get_state()
	var packet := P.make_packet(P.Kind.PLAYER_REQUEST,{"action":action,"value":value,"request_sequence":_request_sequence+1},epoch,maxi(0,owner.last_tick),owner.spawn_generation)
	if not P.encode(packet).ok or not game.send(_game_id,packet).ok: return false
	_request_sequence += 1
	return true

func resume_token() -> PackedByteArray: return _resume.duplicate()

func get_owner_state() -> SharedPlayerState: return prediction.get_state()

func get_public_state() -> Dictionary:
	if _confirmed.is_empty(): return {}
	return {"epoch":epoch,"tick":_last_snapshot_tick,"actors":_confirmed.actors.duplicate(true),
		"grenades":_confirmed.grenades.duplicate(true),"objectives":_confirmed.objectives.duplicate(true),"map_sequence":data.map_sequence}

func sample_remote(id: int) -> Dictionary:
	if not _remote.has(id): return {}
	var elapsed_ticks := clampf(float(Time.get_ticks_msec()-_snapshot_time_ms)*.06,0,60)
	return _remote[id].sample(_last_snapshot_tick+elapsed_ticks)

func drain_events() -> Array[Dictionary]:
	var events := _events
	_events = []
	return events

func get_stats() -> Dictionary:
	return {"status":status,"error":last_error,"actor_id":actor_id,"epoch":epoch,"server_tick":_last_snapshot_tick,
		"prediction":prediction.get_status(),"map":transfer.get_stats(),"event_count":_events.size(),"remote_count":_remote.size()}
