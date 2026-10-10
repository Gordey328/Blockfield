extends SceneTree
## Pure registry and real replica components over bounded fake transports.
## Runtime/Main/socket reset integration belongs to test_runtime_epoch.gd.
const REGISTRY=preload("res://network/session_registry.gd")
const CLIENT=preload("res://network/client_replica.gd")
const P=preload("res://network/protocol.gd")
const COMPAT=preload("res://network/compatibility.gd")
const TRANSFER=preload("res://network/map_transfer.gd")
const DATA=preload("res://world/voxel_data.gd")
const STATE=preload("res://simulation/player_state.gd")
const RULES=preload("res://simulation/player_rules.gd")
const CODEC=preload("res://network/simulation_codec.gd")
var assertions:=0
var failures:=0
var next_actor:=43

class TokenRegistry extends BlockfieldSessionRegistry:
	var counter:=0
	var fail_at:=-1
	var repeated:=PackedByteArray()
	func _new_token() -> PackedByteArray:
		counter+=1
		if counter==fail_at:return PackedByteArray()
		if not repeated.is_empty():return repeated.duplicate()
		var value:=PackedByteArray();value.resize(32);value.fill(0x42)
		value.encode_u32(0,counter)
		return value

class FakeTransport extends BlockfieldWSTransport:
	var stops:=0
	var sent: Array[BlockfieldProtocol.Packet]=[]
	var pending: Array[Dictionary]=[]
	var started: Array[String]=[]
	var next_connection:=900
	func stop(_force: bool=false) -> void:
		# Native forced stop retains pending packets and emits a terminal close.
		stops+=1;pending.append({"type":"closed","connection_id":next_connection})
	func start_client(url: String) -> Dictionary:
		started.append(url);next_connection+=1
		return {"ok":true,"error":"","connection_id":next_connection}
	func send(_id: int,packet: BlockfieldProtocol.Packet) -> Dictionary:
		var encoded:=P.encode(packet)
		if not encoded.ok:return {"ok":false,"error":encoded.error}
		sent.append(packet);return {"ok":true,"error":""}
	func poll() -> void:pass
	func drain_events(max_count: int=64) -> Array[Dictionary]:
		var result: Array[Dictionary]=[]
		for _index in range(mini(maxi(max_count,0),pending.size())):result.append(pending.pop_front())
		return result

func _initialize() -> void:call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value:failures+=1;push_error("EPOCH RESET CONTRACT: "+message)
func _allocate(_name: String,_role: int) -> Dictionary:
	var id:=next_actor;next_actor+=56
	return {"ok":true,"actor_id":id}
func _hello(role: int=0,resume: PackedByteArray=PackedByteArray(),bulk: PackedByteArray=PackedByteArray()) -> P.Packet:
	return P.make_packet(P.Kind.HELLO,{"role":role,"name":"Guest","build_hash":COMPAT.build_hash(),"rules_hash":COMPAT.rules_hash(),"resume_token":resume,"bulk_token":bulk})
func _welcome(epoch: int=17,id: int=43,generation: int=1,profile: int=0) -> P.Packet:
	var resume:=PackedByteArray();resume.resize(32);resume.fill(epoch)
	var bulk:=PackedByteArray();bulk.resize(32);bulk.fill(epoch+1)
	return P.make_packet(P.Kind.WELCOME,{"actor_id":id,"spawn_generation":generation,"server_hz":60,"snapshot_hz":20,"profile":profile,"resume_token":resume,"bulk_token":bulk,"build_hash":COMPAT.build_hash(),"rules_hash":COMPAT.rules_hash()},epoch)
func _wire(packet: P.Packet) -> P.Packet:
	var encoded:=P.encode(packet);check(encoded.ok,"fixture produces an explicit valid protocol frame")
	if not encoded.ok:return null
	var decoded:=P.decode(encoded.bytes);check(decoded.ok,"fixture survives actual protocol byte decode")
	return decoded.packet if decoded.ok else null
func _run() -> void:
	_test_registry_atomicity()
	_test_registry_capacity()
	_test_replica_reset()
	_test_reused_replica()
	_test_rejected_welcomes()
	print("EPOCH RESET CONTRACT: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)

func _test_registry_atomicity() -> void:
	next_actor=43
	var registry:=TokenRegistry.new()
	check(registry.configure(17,COMPAT.build_hash(),COMPAT.rules_hash()),"configured registry")
	var first:=registry.admit_game(101,_hello(),1,_allocate)
	var second:=registry.admit_game(102,_hello(1),2,_allocate)
	var grace:=registry.admit_game(103,_hello(),3,_allocate)
	check(first.ok and second.ok and grace.ok,"connected player, spectator and grace fixtures admitted")
	check(registry.admit_bulk(201,_hello(2,PackedByteArray(),first.welcome.payload.bulk_token),4).ok,"player old bulk bound")
	check(registry.admit_bulk(202,_hello(2,PackedByteArray(),second.welcome.payload.bulk_token),5).ok,"spectator old bulk bound")
	check(registry.disconnect_game(103,6).ok,"third identity enters unexpired reconnect grace")
	registry.set_generation(first.actor_id,7);registry.set_generation(second.actor_id,9)
	var barrier:=P.make_packet(P.Kind.MAP_END,{"snapshot_id":1,"map_sequence":0,"hash":"old map".sha256_buffer()},17,20,0)
	check(registry.set_barrier(first.actor_id,barrier) and registry.accept_ready(101,P.make_packet(P.Kind.MAP_READY,barrier.payload.duplicate(true),17,20,0)),"old playable barrier installed")
	var before_sessions:=registry._sessions.duplicate(true)
	var before_games:=registry._games.duplicate(true)
	var before_bulks:=registry._bulks.duplicate(true)
	for args in [[17,1,1000],[16,1,1000],[P.U32_MAX+1,1,1000],[18,-1,1000],[18,2,1000],[18,1,-1],[18,1,5],[18,1,REGISTRY.MAX_CLOCK_MS+1]]:
		var result:=registry.advance_epoch(args[0],args[1],args[2])
		check(not result.ok and result.welcomes.is_empty() and result.close_bulk.is_empty() and result.expired_actor_ids.is_empty(),"invalid transition returns no partial publication")
		check(registry.epoch==17 and registry.profile==0 and registry._last_time==6 and registry._sessions==before_sessions and registry._games==before_games and registry._bulks==before_bulks,"invalid transition leaves epoch, credentials, clock and bindings unchanged")
	registry.fail_at=registry.counter+3
	check(not registry.advance_epoch(18,1,1000).ok,"entropy failure after preparing first actor rejects entire reset")
	check(registry._sessions==before_sessions and registry._bulks==before_bulks and registry._last_time==6 and registry.epoch==17,"partial credential allocation never mutates first actor or clock")
	registry.fail_at=-1;registry.repeated=first.welcome.payload.resume_token.duplicate()
	check(not registry.advance_epoch(18,1,1000).ok and registry._sessions==before_sessions,"reused old resume credential fails atomically")
	registry.repeated=PackedByteArray()
	var reset:=registry.advance_epoch(18,1,20)
	check(reset.ok and reset.welcomes.size()==2 and reset.close_bulk==[201,202] and reset.expired_actor_ids==[grace.actor_id],"reset publishes one welcome per live owner, old bulks and discarded grace identity")
	check(registry.epoch==18 and registry.profile==1 and registry._last_time==20 and registry._games==before_games,"new epoch/profile commit keeps exactly the existing game bindings")
	check(registry.get_stats().actors==2 and registry.get_stats().bulk_connections==0 and registry.session_view(grace.actor_id).is_empty(),"old grace and bulk capabilities are removed")
	for packet: P.Packet in reset.welcomes:
		check(packet.epoch==18 and packet.payload.profile==1 and packet.payload.spawn_generation==1 and P.encode(packet).ok,"replacement welcome has new epoch/profile/generation and strict byte schema")
		var view:=registry.session_view(packet.payload.actor_id)
		check(not view.ready and view.generation==1 and view.bulk==0 and registry.owner_of_game(view.game)==0 and registry.owner_of_game(view.game,false)==packet.payload.actor_id,"live owner stays bound but cannot act before the fresh barrier")
		check(view.role==(0 if packet.payload.actor_id==first.actor_id else 1),"player/spectator admission role survives reset")
		check(packet.payload.build_hash==COMPAT.build_hash() and packet.payload.rules_hash==COMPAT.rules_hash(),"replacement welcome retains approved compatibility identity")
	check(reset.welcomes[0].payload.resume_token!=first.welcome.payload.resume_token and reset.welcomes[1].payload.resume_token!=second.welcome.payload.resume_token,"every live resume token rotates")
	check(not registry.accept_ready(101,P.make_packet(P.Kind.MAP_READY,barrier.payload.duplicate(true),17,20,0)),"old ready packet cannot reopen new epoch owner")
	check(not registry.admit_bulk(203,_hello(2,PackedByteArray(),first.welcome.payload.bulk_token),21).ok,"old bulk capability rejected after reset")
	check(registry.admit_bulk(203,_hello(2,PackedByteArray(),reset.welcomes[0].payload.bulk_token),22).ok,"fresh bulk capability binds retained actor")
	check(not registry.admit_bulk(204,_hello(2,PackedByteArray(),reset.welcomes[0].payload.bulk_token),23).ok,"fresh bulk token remains single use")
	check(not registry.admit_game(104,_hello(0,grace.welcome.payload.resume_token),24,_allocate).ok,"discarded grace credential cannot resume into the new match")
	check(registry.disconnect_game(101,25).ok,"retained actor can enter new-epoch grace")
	check(not registry.admit_game(104,_hello(0,first.welcome.payload.resume_token),26,_allocate).ok,"old resume token remains invalid after retained game disconnects")
	var resumed:=registry.admit_game(104,_hello(0,reset.welcomes[0].payload.resume_token),27,_allocate)
	check(resumed.ok and resumed.actor_id==first.actor_id and resumed.resumed and resumed.welcome.payload.spawn_generation==1,"new resume capability retains identity/generation without allocation")
	var next:=registry.advance_epoch(19,0,28)
	check(next.ok and registry.profile==0 and registry.epoch==19,"a second monotonic reset rotates again without losing live identities")

func _test_registry_capacity() -> void:
	var registry:=TokenRegistry.new();registry.configure(1,COMPAT.build_hash(),COMPAT.rules_hash())
	for index in range(REGISTRY.MAX_ACTORS):check(registry.admit_game(index+1,_hello(index%2),index,_allocate).ok,"bounded full population admission")
	var reset:=registry.advance_epoch(P.U32_MAX,1,32)
	check(reset.ok and reset.welcomes.size()==32 and registry.get_stats().actors==32,"u32 maximum epoch reset remains bounded to32 live identities")
	var seen: Dictionary[String,bool]={}
	for packet: P.Packet in reset.welcomes:
		for token: PackedByteArray in [packet.payload.resume_token,packet.payload.bulk_token]:
			check(token.size()==32 and not seen.has(token.hex_encode()),"all64 new capabilities are separate and fixed length")
			seen[token.hex_encode()]=true
	check(not registry.advance_epoch(P.U32_MAX,0,33).ok and registry.epoch==P.U32_MAX,"epoch never repeats or wraps at u32 maximum")
	var empty:=REGISTRY.new();empty.configure(3,COMPAT.build_hash(),COMPAT.rules_hash())
	check(empty.advance_epoch(4,0,0).ok and empty.get_stats().actors==0,"empty configured registry advances without manufacturing actors")

func _map(epoch: int,color: int=0x01447766) -> DATA:
	var value:=DATA.new();value.clear(Vector3i(8,8,8),epoch)
	value.seed_box(Vector3i.ZERO,Vector3i(8,2,8),color)
	return value
func _actor(epoch: int,tick: int,id: int=43,profile: String="0.75") -> STATE:
	var value:=STATE.new(id,"Guest",epoch,profile,1)
	RULES.spawn(value,tick,Vector3(4,2.01,4),0,0)
	value.last_tick=tick;value.tool_raise=1
	return value
func _snapshot(owner: STATE,map: DATA,remote: STATE=null) -> P.Packet:
	var actors: Array[STATE]=[owner]
	if remote!=null:actors.append(remote)
	var bases: Array[Vector3]=[Vector3(2,2,2),Vector3(6,2,6)]
	var objectives: Dictionary={"epoch":map.epoch,"mode":"sandbox","capture_limit":3,"winning_team":-1,"scores":[0,0],"bases":bases,"flags":[{"team":0,"position":bases[0],"carrier":-1,"at_base":true},{"team":1,"position":bases[1],"carrier":-1,"at_base":true}],"territories":[]}
	var body:=CODEC.from_snapshot({"epoch":map.epoch,"tick":owner.last_tick,"map_sequence":map.map_sequence,"dimensions":map.dimensions,"event_sequence":0,"profile":owner.profile,"mode":"sandbox","objectives":objectives,"owner_state":owner,"actors":actors,"grenades":[]})
	check(body.ok,"explicit source-state fixture validates through simulation codec")
	return _wire(P.make_packet(P.Kind.MATCH_STATE,body.payload,map.epoch,owner.last_tick,owner.spawn_generation)) if body.ok else null
func _replica() -> CLIENT:
	var replica:=CLIENT.new();replica.game=FakeTransport.new();replica.bulk=FakeTransport.new()
	replica._game_id=501;replica._bulk_id=601;replica._map_url="wss://example.test/map";replica._name="Guest";replica._role=0
	replica.status="joining";replica._game_packet(_wire(_welcome()))
	var data:=_map(17);replica.data=data;replica.assembler.reset(17,0,data.dimensions,0)
	replica.status="synchronizing";replica._game_packet(_snapshot(_actor(17,20),data,_actor(17,20,99)))
	check(replica.status=="live" and replica.sample_remote(99).id==99,"old match fixture has actual owner prediction and remote interpolation")
	check(replica.submit_input(1,Vector2.ZERO,0,0).ok and replica.prediction.get_status().pending==1,"old timeline contains predicted command and cosmetic fire")
	replica._chat_intent=7;replica._chat_sequence=88;replica._request_sequence=9;replica._event_cursor=100
	replica._snapshot_time_ms=1234
	# Populate actual partial transfer buffers, as a reset can interrupt loading.
	var sender: TRANSFER.BaselineSender=TRANSFER.make_sender(data,3).sender
	replica.transfer.reset(17);replica.transfer.consume(_wire(sender.begin_packet()))
	var chunk:=sender.next_chunk();replica.transfer.consume(_wire(chunk.packet))
	for _index in range(70):(replica.bulk as FakeTransport).pending.append({"type":"packet","packet":chunk.packet})
	(replica.bulk as FakeTransport).pending.append({"type":"timeout"})
	return replica

func _test_replica_reset() -> void:
	for status in ["joining","loading","synchronizing","live"]:
		var replica:=_replica();replica.status=status
		var game: FakeTransport=replica.game;var bulk: FakeTransport=replica.bulk
		var old_prediction:=replica.prediction;var old_resume:=replica.resume_token()
		var packet:=_wire(_welcome(18,43,1,1))
		replica._game_packet(packet)
		check(replica.status=="joining" and replica.epoch==18 and replica.actor_id==43,"replacement accepted from %s without changing canonical owner"%status)
		check(replica.game==game and game.stops==0 and replica._game_id==501,"game socket binding survives replacement")
		check(replica.bulk==bulk and bulk.stops==1 and bulk.pending.is_empty() and replica._bulk_id==0,"old bulk pending frames/timeouts discarded before new stream")
		check(replica._map_url=="wss://example.test/map" and replica._name=="Guest" and replica._role==0,"endpoints/name/admission role survive replacement")
		check(replica.data==null and replica.get_public_state().is_empty() and replica.get_owner_state()==null and replica.prediction!=old_prediction,"old map, confirmed state and prediction are unreachable through replica")
		check(replica._remote.is_empty() and replica.sample_remote(99).is_empty() and replica._predicted_effects.is_empty() and replica._predicted_order.is_empty(),"remote pose and predicted effect dedupe histories reset")
		check(replica._chat_intent==0 and replica._chat_sequence==0 and replica._request_sequence==0 and replica._event_cursor==0 and replica._last_snapshot_tick==-1 and replica._snapshot_time_ms==0,"epoch-local chat/request/event/input snapshot cursors reset")
		check(replica.transfer.get_stats().status=="idle" and replica.transfer.get_stats().expected_epoch==18 and replica.transfer.get_stats().baseline_bytes==0 and replica.transfer.get_stats().staged_map_bytes==0,"partial old baseline storage is released and transfer expects new epoch")
		check(not replica.assembler.get_stats().armed and replica.prediction.get_status().pending==0,"old map assembler and prediction command queue are cancelled")
		check(replica.drain_events()==[{"type":"epoch_reset","epoch":18}],"reset event replaces every old pending presentation event")
		check(replica.resume_token()!=old_resume and replica.resume_token()==packet.payload.resume_token,"new reconnect credential replaces old capability")
		packet.payload.bulk_token[0]^=1
		check(replica._welcome.payload.bulk_token!=packet.payload.bulk_token,"accepted welcome owns an independent credential copy")
		replica.poll();check(replica.status=="joining","discarded bulk events cannot abort new join")
		if status=="live":_complete_new_join(replica)
		replica.close()

func _complete_new_join(replica: CLIENT) -> void:
	var fresh:=_map(18,0x01664477)
	var sender: TRANSFER.BaselineSender=TRANSFER.make_sender(fresh,4).sender
	replica._game_packet(_wire(sender.begin_packet()))
	check(replica.status=="loading" and (replica.bulk as FakeTransport).started==["wss://example.test/map"],"replacement starts a fresh bounded map stream through saved endpoint")
	var bulk: FakeTransport=replica.bulk
	bulk.pending.append({"type":"connected"});replica.poll()
	check(bulk.sent.size()==1 and bulk.sent[0].payload.bulk_token==replica._welcome.payload.bulk_token and bulk.sent[0].payload.resume_token.is_empty(),"new bulk HELLO uses only the new one-time capability")
	while true:
		var chunk:=sender.next_chunk()
		if chunk.done:break
		bulk.pending.append({"type":"packet","packet":_wire(chunk.packet)})
	replica._game_packet(_wire(sender.end_packet(fresh).packet))
	for _step in range(20):
		replica.poll()
		if replica.status!="loading":break
	check(replica.status=="synchronizing" and replica.data.blocks==fresh.blocks and replica.data.epoch==18,"actual new baseline verifies, installs and waits for state")
	var game: FakeTransport=replica.game
	check(game.sent.back().kind==P.Kind.MAP_READY and game.sent.back().epoch==18 and game.sent.back().payload.snapshot_id==4,"new readiness barrier uses new snapshot and epoch")
	check(not replica.submit_input(0,Vector2.ZERO,0,0).ok,"new map installation cannot act before owner-state barrier")
	replica._game_packet(_snapshot(_actor(18,0,43,"0.76"),fresh))
	check(replica.status=="live" and replica.get_owner_state().profile=="0.76" and replica.get_owner_state().last_tick==0,"lower tick in new epoch installs changed source profile rather than stale-filtering")
	check(replica.submit_input(0,Vector2.ZERO,0,0).sequence==1,"new input sequence restarts at1 after explicit epoch reset")
	check(replica.send_chat("new epoch chat") and game.sent.back().payload.message_id==1,"chat intent counter restarts independently")
	check(replica.request_team(1) and game.sent.back().payload.request_sequence==1,"new request generation starts at1")
	replica._game_packet(_wire(P.make_packet(P.Kind.CHAT,{"channel":0,"sender_id":43,"message_id":1,"text":"new epoch chat"},18,0,1)))
	var found:=false
	for event: Dictionary in replica.drain_events():
		if event.type=="chat" and event.message_id==1:found=true
	check(found and replica.status=="live","new confirmed chat cursor is independent of old message88")

func _test_reused_replica() -> void:
	var replica:=_replica()
	var game: FakeTransport=replica.game
	var bulk: FakeTransport=replica.bulk
	for _index in range(70):game.pending.append({"type":"timeout"})
	replica.close()
	check(game.pending.is_empty() and bulk.pending.is_empty(),"intentional close discards every bounded event including native terminal close")
	var started:=replica.connect_to("wss://example.test/play","wss://example.test/map","Guest",false,_welcome().payload.resume_token)
	check(started.ok and replica.game==game and replica.bulk==bulk,"same replica/transports restart after close")
	game.pending.append({"type":"connected"});replica.poll()
	check(replica.status=="joining" and game.sent.back().kind==P.Kind.HELLO,"old game close cannot terminate reused replica's new join")
	game.pending.append({"type":"packet","packet":_wire(_welcome(17,43,7,0))});replica.poll()
	check(replica.status=="joining" and replica._welcome.payload.spawn_generation==7,"reused replica accepts fresh initial resumed welcome")
	var fresh:=_map(18)
	var sender: TRANSFER.BaselineSender=TRANSFER.make_sender(fresh,8).sender
	# WELCOME and MAP_BEGIN can be in one game drain. Old forced bulk close must
	# be consumed intentionally before that same poll reaches new loading state.
	game.pending.append({"type":"packet","packet":_wire(_welcome(18,43,1,1))})
	game.pending.append({"type":"packet","packet":_wire(sender.begin_packet())})
	replica.poll()
	check(replica.status=="loading" and bulk.pending.is_empty() and replica.epoch==18,"same-poll epoch welcome plus baseline ignores only intentionally discarded bulk close")
	bulk.pending.append({"type":"closed"});replica.poll()
	check(replica.status=="failed","a genuine new bulk close still terminates loading; cleanup does not weaken failures")
	replica.close()

func _test_rejected_welcomes() -> void:
	for label in ["stale","repeat","identity","generation","build","rules","hz","profile","short_token","status"]:
		var replica:=_replica();var packet:=_welcome(18,43,1,1)
		match label:
			"stale":packet.epoch=16
			"repeat":packet.epoch=17
			"identity":packet.payload.actor_id=99
			"generation":packet.payload.spawn_generation=2
			"build":packet.payload.build_hash[0]^=1
			"rules":packet.payload.rules_hash[0]^=1
			"hz":packet.payload.server_hz=120
			"profile":packet.payload.profile=2
			"short_token":packet.payload.resume_token.resize(31)
			"status":replica.status="connecting"
		replica._game_packet(packet)
		check(replica.status=="failed" and replica.data==null and replica.drain_events().is_empty(),"%s replacement fails closed without exposing an epoch reset"%label)
		replica.close()
	var first:=CLIENT.new();first.game=FakeTransport.new();first.bulk=FakeTransport.new();first.status="joining"
	first._game_packet(_wire(_welcome(17,99,7,0)))
	check(first.status=="joining" and first.actor_id==99 and first._welcome.payload.spawn_generation==7 and first.drain_events().is_empty(),"first welcome still accepts assigned identity/resumed generation without reset event")
	first._game_packet(_wire(_welcome(17,99,7,0)))
	check(first.status=="failed","same welcome repeated after initial acceptance remains fatal")
	first.close()
