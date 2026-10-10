extends SceneTree
const SERVER = preload("res://network/server_runtime.gd")
const CLIENT = preload("res://network/client_replica.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const P = preload("res://network/protocol.gd")
const COMPAT = preload("res://network/compatibility.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
var assertions := 0
var failures := 0
var server: SERVER
var endpoints := {}
var clients: Array[ObservedClient] = []
var event_logs: Dictionary[int,Array] = {}
var max_loading := 0
var polls := 0

class ObservedBulk extends TRANSPORT:
	var close_log: Array[Dictionary] = []
	func drain_events(max_count: int = 64) -> Array[Dictionary]:
		var result := super.drain_events(max_count)
		for event: Dictionary in result:
			if event.type == "closed": close_log.append({"connection":event.connection_id,"code":event.code,"reason":event.reason})
		return result

class ObservedClient extends CLIENT:
	var paused := false
	var halt_on_begin := false
	var welcome_log: Array[Dictionary] = []
	var preparing_log: Array[Dictionary] = []
	var begin_log: Array[Dictionary] = []
	var barrier_log: Array[Dictionary] = []
	var install_log: Array[Dictionary] = []
	var snapshot_log: Array[Dictionary] = []
	func _init() -> void: bulk = ObservedBulk.new()
	func poll() -> void:
		if not paused: super.poll()
	func _game_packet(packet: P.Packet) -> void:
		var before_status := status
		var before_epoch := epoch
		super._game_packet(packet)
		if packet.kind == P.Kind.MATCH_PREPARING and status != "failed":
			preparing_log.append({"epoch":epoch,"before_status":before_status,"before_epoch":before_epoch,"id":actor_id})
		elif packet.kind == P.Kind.WELCOME and status != "failed":
			var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(packet.payload.bulk_token)
			welcome_log.append({"epoch":epoch,"id":actor_id,"before_epoch":before_epoch,"before_status":before_status,
				"data_cleared":data == null,"prediction_cleared":not prediction.get_status().ready,
				"remote_count":get_stats().remote_count,"input_sequence":prediction.get_status().last_submitted,
				"chat":_chat_intent,"request":_request_sequence,"cursor":_event_cursor,
				"predicted_effects":_predicted_effects.size(),"profile":packet.payload.profile,
				"bulk_digest":digest.finish()})
		elif packet.kind == P.Kind.MAP_BEGIN:
			begin_log.append({"epoch":packet.epoch,"dimensions":packet.payload.dimensions,"sequence":packet.payload.map_sequence,"snapshot_id":packet.payload.snapshot_id})
			if halt_on_begin: paused = true
		elif packet.kind == P.Kind.MAP_END:
			barrier_log.append({"epoch":packet.epoch,"sequence":packet.payload.map_sequence,"hash":packet.payload.hash.duplicate(),"snapshot_id":packet.payload.snapshot_id,"tick":packet.tick})
		elif packet.kind == P.Kind.MATCH_STATE and status == "live":
			snapshot_log.append({"epoch":packet.epoch,"tick":packet.tick,"sequence":packet.payload.map_sequence,"generation":packet.sequence,"id":packet.payload.owner_state.player_id})
	func install(map_data: DATA) -> bool:
		install_log.append({"epoch":map_data.epoch,"dimensions":map_data.dimensions,"sequence":map_data.map_sequence,"tick":map_data.last_tick})
		return true
	func apply_map(transaction: Dictionary) -> bool:
		return data != null and data.apply_transaction(transaction).ok

class TraceServer extends SERVER:
	var close_log: Array[Dictionary] = []
	func _close_game(connection: int,reason: String,now: int) -> void:
		close_log.append({"connection":connection,"reason":reason})
		super._close_game(connection,reason,now)

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("RUNTIME EPOCH: "+message)

func make_map(epoch: int,dimensions: Vector3i = Vector3i(32,16,32),color: int = 0x01608070) -> DATA:
	var map := DATA.new()
	check(map.clear(dimensions,epoch) == OK,"new writable map epoch")
	map.seed_box(Vector3i.ZERO,Vector3i(dimensions.x,4,dimensions.z),color)
	map.seed_box(Vector3i(12,4,12),Vector3i(14,7,14),color^0x00003322)
	return map

func connect_client(name: String,role: bool = false,token: PackedByteArray = PackedByteArray()) -> ObservedClient:
	var client := ObservedClient.new()
	client.set_map_callbacks(client.install,client.apply_map)
	check(client.connect_to("ws://127.0.0.1:%d/play" % endpoints.game_port,"ws://127.0.0.1:%d/map" % endpoints.map_port,name,role,token).ok,"actual replica socket connection")
	clients.append(client);event_logs[client.get_instance_id()] = []
	return client

func pump() -> void:
	server.poll()
	for client: ObservedClient in clients:
		client.poll()
		for event: Dictionary in client.drain_events():
			var log: Array = event_logs[client.get_instance_id()]
			if log.size() < 512: log.append(event)
	check(server.step_once(),"actual authority fixed step")
	var loading: int = server.get_stats().loading
	max_loading = maxi(max_loading,loading)
	check(loading <= SERVER.MAX_JOINS,"active reset/join preparation stays bounded to two")
	polls += 1
	await process_frame

func wait_until(predicate: Callable,message: String,allowed_failed: Array = []) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec() < deadline:
		for client: ObservedClient in clients:
			if client.status == "failed" and client not in allowed_failed:
				check(false,"%s; replica %s failed: %s; welcome=%s; begins=%s; closes=%s; bulk_closes=%s" % [message,client._name,client.last_error,client.welcome_log,client.begin_log,(server as TraceServer).close_log,(client.bulk as ObservedBulk).close_log]);return
		if predicate.call(): check(true,message);return
		await pump()
	check(false,message+" timed out")

func all_live(targets: Array,epoch: int) -> bool:
	for client: ObservedClient in targets:
		if client.status != "live" or client.epoch != epoch: return false
	return true

func has_retired_owner(owner_id: int) -> bool:
	for entry: Dictionary in server._retired_bulks.values():
		if entry.owner == owner_id: return true
	return false

func finish_old_bulk_hello(client: ObservedClient) -> void:
	# Keep the game stream paused while completing its already started old bulk
	# handshake. New WELCOME may be queued, but cannot be consumed by this client.
	var deadline := Time.get_ticks_msec()+5000
	var packets := 0
	while Time.get_ticks_msec() < deadline and not has_retired_owner(client.actor_id):
		await pump()
		client.bulk.poll()
		for event: Dictionary in client.bulk.drain_events():
			if event.type == "connected": check(client.bulk.send(client._bulk_id,client._hello(true)).ok,"late old bulk HELLO sent on actual connecting socket")
			elif event.type == "packet": packets += 1
			elif event.type in ["closed","timeout","protocol_error","overflow"]: check(false,"late compatible old bulk HELLO unexpectedly terminated")
	check(has_retired_owner(client.actor_id),"compatible old in-flight capability gets an idle retired socket")
	check(packets == 0 and server.registry.session_view(client.actor_id).bulk == 0,"retired old capability grants no Registry binding or map packet")
	for i: int in range(3):
		await pump();client.bulk.poll()
		for event: Dictionary in client.bulk.drain_events():
			if event.type == "packet": packets += 1
	check(packets == 0,"idle retired channel never receives new epoch map contents")

func reject_bulk_token(token: PackedByteArray,message: String) -> void:
	var probe := TRANSPORT.new()
	var started := probe.start_client("ws://127.0.0.1:%d/map" % endpoints.map_port)
	check(started.ok,message+" opens actual probe socket")
	if not started.ok: return
	var deadline := Time.get_ticks_msec()+5000
	var closed := false
	var received := 0
	while Time.get_ticks_msec() < deadline and not closed:
		await pump();probe.poll()
		for event: Dictionary in probe.drain_events():
			match event.type:
				"connected":
					var hello := P.make_packet(P.Kind.HELLO,{"role":2,"name":"Bulk retirement probe","build_hash":COMPAT.build_hash(),"rules_hash":COMPAT.rules_hash(),"resume_token":PackedByteArray(),"bulk_token":token})
					check(probe.send(started.connection_id,hello).ok,message+" sends compatible typed HELLO")
				"packet": received += 1
				"closed": closed = true;check(event.code == 1008,message+" rejected with policy close")
	check(closed and received == 0,message+" cannot access map or remain idle admitted")
	probe.stop(true)

func invalid_reset(first: ObservedClient) -> void:
	var authority := server.simulation
	var tick := authority.tick
	var actor := authority.get_actor(first.actor_id)
	var token := first.resume_token()
	var registry := server.registry.get_stats()
	var events := authority.event_sequence
	var cases: Array[Dictionary] = []
	cases.append({"map":make_map(authority.epoch),"profile":"","mode":""})
	cases.append({"map":make_map(authority.epoch-1),"profile":"","mode":""})
	cases.append({"map":make_map(authority.epoch+1),"profile":"bad","mode":""})
	cases.append({"map":make_map(authority.epoch+1),"profile":"","mode":"bad"})
	cases.append({"map":make_map(authority.epoch+1).frozen_copy(),"profile":"","mode":""})
	var no_spawn := DATA.new();no_spawn.clear(Vector3i(32,16,32),authority.epoch+1)
	cases.append({"map":no_spawn,"profile":"","mode":""})
	for entry: Dictionary in cases:
		check(not server.reset_match(entry.map,entry.profile,entry.mode).ok,"invalid reset rejected before replacement")
		check(server.simulation == authority and authority.tick == tick and authority.get_actor(first.actor_id) == actor and authority.event_sequence == events,"invalid reset preserves active simulation/actor/clock/events")
		check(server.registry.get_stats() == registry and first.resume_token() == token,"invalid reset preserves registry/credentials")

func stale_packets(client: ObservedClient,old_epoch: int,old_tick: int,old_generation: int) -> void:
	var input := P.make_packet(P.Kind.INPUT_BATCH,{"records":[{"input_sequence":999,"input_tick":old_tick,"buttons":127,"tool":3,"weapon":1,"move_x":1.0,"move_z":0.0,"yaw":0.0,"pitch":0.0}]},old_epoch,old_tick,old_generation)
	var request := P.make_packet(P.Kind.PLAYER_REQUEST,{"action":1,"value":0x01abcdef,"request_sequence":999},old_epoch,old_tick,old_generation)
	check(client.game.send(client._game_id,input).ok and client.game.send(client._game_id,request).ok,"old-epoch input/request injected on preserved actual socket")
	var actor := server.simulation.get_actor(client.actor_id)
	var before := {"health":actor.health,"magazine":actor.magazine,"reserve":actor.reserve,"grenades":actor.grenades,"blocks":actor.blocks,"team":actor.team,"weapon":actor.weapon,"ack":actor.consumed_input_sequence,"color":server.simulation.snapshot_for(actor.player_id).block_colors[actor.player_id]}
	var map_sequence := server.simulation.data.map_sequence
	for i: int in range(5): await pump()
	check(client.status == "live","old-epoch TCP frames do not disconnect current live owner")
	check(actor.health == before.health and actor.magazine == before.magazine and actor.reserve == before.reserve and actor.grenades == before.grenades and actor.blocks == before.blocks and actor.team == before.team and actor.weapon == before.weapon and actor.consumed_input_sequence == before.ack,"old epoch commands cannot mutate new source actor controls/resources/class")
	check(server.simulation.data.map_sequence == map_sequence and server.simulation.snapshot_for(actor.player_id).block_colors[actor.player_id] == before.color,"old epoch request cannot edit new terrain/palette")

func verify_epoch(targets: Array,epoch: int,map: DATA,ids: Array[int],old_tokens: Array[PackedByteArray],expected_teams: Array[int]) -> void:
	for index: int in range(targets.size()):
		var client: ObservedClient = targets[index]
		check(client.actor_id == ids[index] and client.epoch == epoch and client.status == "live","stable sparse actor ID across actual epoch replacement")
		check(client.resume_token() != old_tokens[index] and client.resume_token().size() == 32,"new epoch rotates actual resume capability")
		check(client.data != null and client.data.epoch == epoch and client.data.dimensions == map.dimensions and client.data.blocks == map.blocks and client.data.map_sequence == map.map_sequence,"new baseline plus authority changes installed exactly")
		var owner := client.get_owner_state()
		check(owner.match_epoch == epoch and owner.player_id == ids[index] and owner.team == expected_teams[index] and owner.profile == server.simulation.profile,"complete owner snapshot agrees with new match identity/team/profile")
		check(owner.kills == 0 and owner.deaths == 0 and owner.score == 0 and owner.consumed_input_sequence == 0,"new epoch resets authority counters/input cursor")
		check(owner.spawn_generation == (1 if owner.team == 2 else 2) and owner.health == (0 if owner.team == 2 else 100),"new map readiness controls inactive/playing life generation")
		check(not client.install_log.is_empty() and client.install_log.back().epoch == epoch and client.install_log.back().dimensions == map.dimensions,"trusted presentation callback installs new epoch map")
		var welcome: Dictionary = client.welcome_log.back()
		check(welcome.data_cleared and welcome.prediction_cleared and welcome.remote_count == 0 and welcome.input_sequence == 0 and welcome.predicted_effects == 0 and welcome.cursor == 0 and welcome.chat == 0 and welcome.request == 0,"replacement WELCOME clears all old client data/history/effects/cursors")
		check(welcome.before_epoch == welcome.epoch and welcome.before_status == "preparing" and welcome.id == ids[index] and welcome.profile == (0 if owner.profile == "0.75" else 1),"WELCOME exactly matches announced epoch and preserved socket owner")
		var begin: Dictionary = client.begin_log.back()
		var barrier: Dictionary = client.barrier_log.back()
		check(begin.epoch == epoch and barrier.epoch == epoch and begin.snapshot_id == barrier.snapshot_id and barrier.sequence <= client.data.map_sequence,"new baseline/barrier identity precedes matching snapshots")
		check(not client.snapshot_log.is_empty() and client.snapshot_log.back().epoch == epoch and client.snapshot_log.back().sequence == map.map_sequence,"actual MATCH_STATE is synchronized with installed map")
		check(client.prediction.get_status().pending == 0 and client.prediction.get_status().server_tick >= 0 and not client.prediction.get_status().needs_rebase,"new prediction starts on closed new-epoch tick")
		var saw_reset := false
		for event: Dictionary in event_logs[client.get_instance_id()]:
			if event.get("type","") == "epoch_reset" and event.epoch == epoch: saw_reset = true
		check(saw_reset,"real replica emits epoch reset after clearing old presentation state")
	check(server.hit_history.get_stats().epoch == epoch and server.hit_history.get_stats().status == "recording","authoritative hit/terrain history rebuilt in new epoch")

func run() -> void:
	var map := make_map(61)
	var sim := MATCH.new();check(sim.configure(map,"0.75","ctf").ok,"old source match")
	server = TraceServer.new();check(server.configure(sim,COMPAT.build_hash(),COMPAT.rules_hash()),"actual runtime compatibility")
	endpoints = server.start();check(endpoints.ok,"actual paired listeners")
	var first := connect_client("First")
	await wait_until(func():return all_live([first],61),"first baseline barrier before deterministic gap")
	var grace := connect_client("Grace gap")
	await wait_until(func():return all_live([first,grace],61),"first two baseline barriers")
	if not all_live([first,grace],61): finish();return
	var grace_id := grace.actor_id
	var grace_token := grace.resume_token()
	grace.close()
	await wait_until(func():return not sim.get_actor(grace_id).connected,"disconnected grace identity retained before reset")
	var second := connect_client("Second")
	await wait_until(func():return all_live([first,second],61),"second playing actor after deterministic gap")
	var spectator := connect_client("Observer",true)
	await wait_until(func():return all_live([first,second,spectator],61),"three connected owners before reset")
	if not all_live([first,second,spectator],61): finish();return
	var ids: Array[int] = [first.actor_id,second.actor_id,spectator.actor_id]
	var teams: Array[int] = [sim.get_actor(ids[0]).team,sim.get_actor(ids[1]).team,2]
	check(ids[0] < grace_id and grace_id < ids[1] and ids[1] < ids[2],"connected stable identities contain disconnected gap")
	var old_tokens: Array[PackedByteArray] = [first.resume_token(),second.resume_token(),spectator.resume_token()]
	var old_bulk := [first.welcome_log.back().bulk_digest,second.welcome_log.back().bulk_digest,spectator.welcome_log.back().bulk_digest]
	var old_actor := sim.get_actor(first.actor_id)
	old_actor.health = 70;old_actor.magazine = 1;old_actor.reserve = 2;old_actor.score = 9;old_actor.kills = 3
	RULES.request_class(old_actor,2,sim.tick)
	var smg := sim.get_actor(second.actor_id)
	smg.weapon = 1;smg.displayed_weapon = 1;smg.magazine = 29;smg.reserve = 119;smg.score = 8
	sim.objectives.scores.assign([3,2]);sim.objectives.winning_team = 0
	check(first.submit_input(0,Vector2.ZERO,.1,.05).ok,"old prediction input cursor")
	check(first.send_chat("old epoch chat") and first.request_block_color(0x01112233),"old chat/request cursors used")
	await wait_until(func():return first.get_owner_state().score == 9 and first.prediction.get_status().input_ack == 1,"old full state and input acknowledgment")
	invalid_reset(first)
	var old_tick := sim.tick
	var old_generation := old_actor.spawn_generation
	first.paused = true;second.paused = true
	var replacement := make_map(72,Vector3i(48,24,40),0x01664299)
	var reset := server.reset_match(replacement,"0.76","tc")
	check(reset.ok and reset.epoch == 72 and reset.actors == 3,"trusted runtime resets connected owners into greater epoch")
	check(server.simulation != sim and server.registry.epoch == 72 and server.simulation.profile == "0.76" and server.simulation.mode == "tc","authority/registry/profile/mode replaced together")
	check(server.simulation.get_actor(grace_id) == null and server.registry.session_view(grace_id).is_empty(),"old disconnected grace identity invalidated")
	check(server.simulation.objectives.scores == [0,0] and server.simulation.objectives.winning_team == -1,"reset clears old winner/scores/objectives")
	for i: int in range(8): await pump()
	check(server.get_stats().loading == 2 and server._streams[ids[2]].phase == "queued","three connected reset streams queue third behind two active jobs")
	check(server.simulation.get_actor(ids[0]).team == 2 and server.simulation.get_actor(ids[1]).team == 2 and not server.registry.session_view(ids[0]).ready,"paused owners remain inactive before new barriers")
	# Trusted authority fixture changes the live map after the first two frozen
	# baselines, exercising ordered deltas rather than a second copy of the map.
	var edit := replacement.set_block(Vector3i(20,4,20),0x01cc7744,{"tick":server.simulation.tick,"actor_id":ids[0],"action_id":1})
	check(edit.ok and edit.changed and replacement.map_sequence == 1,"authority edits new epoch after initial frozen reset baselines")
	server.simulation._commit(edit)
	await pump()
	first.paused = false
	await wait_until(func():return first.status == "live" and first.epoch == 72 and spectator.status == "live" and spectator.epoch == 72,"first completed barrier releases queued third reset join")
	if first.status == "failed" or spectator.status == "failed": finish();return
	second.paused = false
	await wait_until(func():return all_live([first,second,spectator],72),"all three new map/profile/barriers complete")
	if not all_live([first,second,spectator],72): finish();return
	await wait_until(func():return server._retired_bulks.is_empty(),"old idle bulk sockets retire after clients accept greater WELCOME")
	verify_epoch([first,second,spectator],72,replacement,ids,old_tokens,teams)
	check(first.begin_log.back().sequence == 0 and second.begin_log.back().sequence == 0 and first.barrier_log.back().sequence == 1 and second.barrier_log.back().sequence == 1,"frozen reset baseline0 catches up through ordered transaction1")
	check(spectator.begin_log.back().sequence == 1 and spectator.data.get_block(Vector3i(20,4,20)) == 0x01cc7744,"queued third baseline includes the later committed authority edit")
	for i: int in range(3): check([first,second,spectator][i].welcome_log.back().bulk_digest != old_bulk[i],"new epoch rotates bulk capability")
	check(first.get_owner_state().weapon == 2 and first.get_owner_state().magazine == 8 and first.get_owner_state().reserve == 48,"restored pending shotgun applies source0.76 refill after readiness")
	check(second.get_owner_state().weapon == 1 and second.get_owner_state().magazine == 30 and second.get_owner_state().reserve == 150,"restored SMG uses new source profile inventory")
	await stale_packets(first,61,old_tick,old_generation)
	check(first.submit_input(0,Vector2(.25,0),.2,.1).sequence == 1,"new source input timeline starts at sequence1")
	check(first.send_chat("new epoch chat") and first.request_block_color(0x01445566),"chat/request cursors restart after epoch replacement")
	await wait_until(func():return first.prediction.get_status().input_ack == 1 and server.simulation.snapshot_for(first.actor_id).block_colors[first.actor_id] == 0x01445566,"new epoch input/request accepted by actual authority")
	var id := first.actor_id
	var rotated := first.resume_token()
	first.close()
	await wait_until(func():return not server.simulation.get_actor(id).connected,"new epoch disconnect opens resume grace")
	var rejected := connect_client("Old epoch token",false,old_tokens[0])
	await wait_until(func():return rejected.status == "failed","old connected-owner token fails actual resume",[rejected])
	check(server.simulation.get_actor(id) != null and not server.simulation.get_actor(id).connected,"old credential rejection does not rebind stable actor")
	var rejected_grace := connect_client("Old grace token",false,grace_token)
	await wait_until(func():return rejected_grace.status == "failed","old disconnected grace token fails actual resume",[rejected,rejected_grace])
	check(server.simulation.get_actor(grace_id) == null,"invalid grace token cannot resurrect removed actor")
	# Reuse the same actual Replica whose previous game handshake failed. This
	# catches intentionally stopped transport close events surviving connect_to.
	var resumed := rejected
	check(resumed.connect_to("ws://127.0.0.1:%d/play" % endpoints.game_port,"ws://127.0.0.1:%d/map" % endpoints.map_port,"Fresh epoch token",false,rotated).ok,"failed actual Replica can restart with fresh rotated capability")
	resumed.halt_on_begin = true
	await wait_until(func():return resumed.status == "loading" and resumed.paused,"fresh rotated token rebinds actual owner and pauses mid-join",[rejected_grace])
	if resumed.status != "loading" or not resumed.paused: finish();return
	check(resumed.actor_id == id and resumed.epoch == 72,"fresh resume keeps stable owner/current epoch")
	var prior_tokens: Array[PackedByteArray] = [resumed.resume_token(),second.resume_token(),spectator.resume_token()]
	var prior_bulk_token: PackedByteArray = resumed._welcome.payload.bulk_token.duplicate()
	var newer := make_map(83,Vector3i(36,20,44),0x01114466)
	check(server.reset_match(newer,"","ctf").ok,"reset also succeeds with a connected mid-join replica")
	await finish_old_bulk_hello(resumed)
	await reject_bulk_token(prior_bulk_token,"one-use old capability replay")
	var unknown := prior_bulk_token.duplicate();unknown[0] = unknown[0]^0xff
	await reject_bulk_token(unknown,"unknown retired capability")
	resumed.halt_on_begin = false;resumed.paused = false
	await wait_until(func():return all_live([resumed,second,spectator],83),"live and mid-join owners all install latest reset barrier",[rejected_grace])
	if not all_live([resumed,second,spectator],83): finish();return
	await wait_until(func():return server._retired_bulks.is_empty(),"mid-join reset retires superseded bulk channels after latest WELCOME",[rejected_grace])
	verify_epoch([resumed,second,spectator],83,newer,ids,prior_tokens,teams)
	check(resumed.preparing_log.back().before_status == "loading" and resumed.welcome_log.back().before_status == "preparing","announcement replaces unfinished baseline before compatible WELCOME")
	check(server.simulation.profile == "0.76" and server.simulation.mode == "ctf","empty profile reset option preserves negotiated profile")
	check(spectator.get_owner_state().team == 2 and not spectator.get_owner_state().is_alive(),"explicit spectator role remains spectator through repeated reset")
	finish()

func finish() -> void:
	for client: ObservedClient in clients: client.close()
	if server != null: server.stop()
	print("RUNTIME EPOCH: %d assertions, %d failures; polls=%d, max_loading=%d" % [assertions,failures,polls,max_loading])
	quit(0 if failures == 0 else 1)
