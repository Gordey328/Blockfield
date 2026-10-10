extends SceneTree
## Two real native clients, one slow receiver, no Main/preferences/rendering.
const BASE = preload("res://../tests/network/test_server_runtime.gd")
const RUNTIME = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const P = preload("res://network/protocol.gd")
const TRANSPORT = preload("res://network/ws_transport.gd")
const COMPAT = preload("res://network/compatibility.gd")
const REPLICA = preload("res://network/client_replica.gd")
var assertions := 0
var failures := 0
var server: RUNTIME
var fast := BASE.TestClient.new()
var slow := BASE.TestClient.new()
var authority_errors := 0
var peak_outstanding := 0
var observed_window_violation := false
var started_us := 0
var steps := 0
var last_tick := -1

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions+=1
	if not value:
		failures+=1
		push_error("MAP BACKPRESSURE: "+message)

func window(client: BASE.TestClient) -> Dictionary:
	if client.welcome==null: return {}
	for entry: Dictionary in server.get_stats().bulk_windows:
		if entry.actor_id==client.welcome.payload.actor_id: return entry
	return {}

func pump(poll_slow: bool = true) -> void:
	server.poll()
	fast.poll()
	if poll_slow: slow.poll()
	var due := int((Time.get_ticks_usec()-started_us)*60/1000000)
	var work := 0
	while steps<due and work<8:
		if not server.step_once(): authority_errors+=1
		steps+=1; work+=1
	server.poll()
	for entry: Dictionary in server.get_stats().bulk_windows:
		peak_outstanding=maxi(peak_outstanding,int(entry.outstanding_chunks))
		if entry.outstanding_chunks>8: observed_window_violation=true
	await process_frame

func wait_for(predicate: Callable, message: String, poll_slow: bool = true) -> bool:
	var deadline := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and not predicate.call(): await pump(poll_slow)
	check(predicate.call(),message)
	return predicate.call()

func start_client(client: BASE.TestClient, endpoints: Dictionary) -> void:
	client.build_hash=COMPAT.build_hash(); client.rules_hash=COMPAT.rules_hash()
	client.map_port=endpoints.map_port
	var opened := client.game.start_client("ws://127.0.0.1:%d/play" % endpoints.game_port)
	check(opened.ok,"real separate client game socket starts")
	if opened.ok: client.game_id=opened.connection_id

func run() -> void:
	Engine.max_fps=180
	var data := DATA.new()
	check(data.clear(Vector3i(64,16,64),311)==OK,"bounded canonical map exceeds two receive windows")
	data.seed_box(Vector3i.ZERO,Vector3i(64,4,64),0x01407060)
	var match_sim := MATCH.new()
	check(match_sim.configure(data,"0.75","sandbox").ok,"source match fixture configured")
	server=RUNTIME.new()
	check(server.configure(match_sim,COMPAT.build_hash(),COMPAT.rules_hash()),"actual current compatibility")
	var endpoints := server.start()
	check(endpoints.ok,"exact-owned game/map listeners start")
	if not endpoints.ok: finish(); return
	started_us=Time.get_ticks_usec()
	slow.defer_final_ack=true
	start_client(fast,endpoints); start_client(slow,endpoints)
	if not await wait_for(func() -> bool: return not window(slow).is_empty() and window(slow).sent_chunks>0,"slow owner authenticated before receive pause"): finish(); return
	var cell := Vector3i(10,4,10)
	var metadata := {"tick":server.simulation.tick+1}
	var edited := true
	# Trusted fixture edits use the Match receipt queue, just like existing
	# authority-adversarial tests; clients never submit map changes.
	for color in [0x01504030,0x01607080,0]:
		var transaction := data.set_block(cell,color,metadata)
		edited=edited and transaction.ok and transaction.changed
		server.simulation._commit(transaction)
	check(edited,"trusted create/repaint/remove receipts commit during the paused baseline")
	var pause_until := Time.get_ticks_msec()+600
	while Time.get_ticks_msec()<pause_until: await pump(false)
	var paused := window(slow)
	check(not paused.is_empty() and paused.outstanding_chunks==8 and paused.sent_chunks-paused.acked_chunks==8,"600ms receiver pause reaches exactly the8-chunk credit ceiling")
	check(server.get_stats().totals.closed==0 and slow.errors.is_empty(),"pause does not masquerade as protocol or capacity failure")
	check(fast.ready_sent and not fast.closed and fast.ready_data.blocks==server.simulation.data.blocks,"independent healthy client completes its larger-than-window baseline")
	if not await wait_for(func() -> bool: return slow.ready_sent and window(slow).get("phase","")=="live","slow receiver resumes and installs exact final barrier"): finish(); return
	check(slow.ready_data.blocks==server.simulation.data.blocks and fast.ready_data.blocks==slow.ready_data.blocks and slow.ready_data.map_sequence==3 and fast.ready_data.map_sequence==3,"both actual replicas match ordered edited terrain and final barrier after slow receive")
	check(slow.errors.is_empty() and fast.errors.is_empty() and not slow.closed and authority_errors==0,"all source/transfer steps remain valid")
	var final_pending := window(slow)
	check(final_pending.outstanding_chunks==1 and final_pending.acked_chunks+1==final_pending.chunk_count,"game MAP_READY can precede final bulk ACK without a deadlock")
	var final_ack: P.Packet = slow.transfer.get_chunk_ack().packet
	check(slow.bulk.send(slow.bulk_id,final_ack).ok and slow.bulk.send(slow.bulk_id,final_ack).ok,"actual delayed and duplicate final ACKs enter the owned bulk channel")
	if not await wait_for(func() -> bool: return window(slow).get("outstanding_chunks",-1)==0,"live owner accepts late cumulative bulk progress"): finish(); return
	check(not slow.closed and server.get_stats().totals.closed==0,"valid duplicate ACK never detaches an actor")
	# An admitted socket must not credit another owner's snapshot, even when
	# its packet is a valid codec frame with a genuine identity/hash context.
	var foreign: P.Packet = fast.transfer.get_chunk_ack().packet
	check(foreign.payload.snapshot_id!=final_ack.payload.snapshot_id,"independent transfer identities differ")
	check(slow.bulk.send(slow.bulk_id,foreign).ok,"wrong-owner snapshot sent through actual second socket")
	if not await wait_for(func() -> bool: return slow.closed,"wrong-owner bulk credit fails closed"): finish(); return
	check(not fast.closed and server.simulation.get_actor(fast.welcome.payload.actor_id).connected,"forged credit cannot disconnect or advance the unrelated owner")
	check(server.get_stats().totals.input_rejections==0,"map ACK validation does not change input admission")
	check(not observed_window_violation and peak_outstanding==8,"every observed owner remains within fixed receive credit")
	check(server.game_transport.get_stats().totals.timeouts==0 and server.map_transport.get_stats().totals.timeouts==0,"short receiver pause requires no shortened heartbeat policy")
	await actual_replica_phase()
	finish()

func actual_replica_phase() -> void:
	fast.stop(); slow.stop(); server.stop()
	var data := DATA.new()
	check(data.clear(Vector3i(64,16,64),312)==OK,"actual Replica phase has a separate17-chunk epoch")
	data.seed_box(Vector3i.ZERO,Vector3i(64,4,64),0x01407060)
	var simulation := MATCH.new()
	check(simulation.configure(data,"0.75","sandbox").ok,"actual Replica source match configures")
	server=RUNTIME.new()
	check(server.configure(simulation,COMPAT.build_hash(),COMPAT.rules_hash()),"actual Replica uses production compatibility")
	var endpoints := server.start()
	check(endpoints.ok,"actual Replica phase owns fresh listeners")
	if not endpoints.ok: return
	started_us=Time.get_ticks_usec(); steps=0
	var first := REPLICA.new()
	var second := REPLICA.new()
	var game_url := "ws://127.0.0.1:%d/play" % endpoints.game_port
	var map_url := "ws://127.0.0.1:%d/map" % endpoints.map_port
	check(first.connect_to(game_url,map_url,"Window first").ok and second.connect_to(game_url,map_url,"Window second").ok,"two real production Replicas connect")
	var deadline := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await pump(false); first.poll(); second.poll()
		if second.status=="loading" and second.actor_id>0 and server.registry.session_view(second.actor_id).bulk!=0: break
	check(second.status=="loading" and first.status in ["loading","live"],"production clients enter independent authentic map joins")
	var pause_until := Time.get_ticks_msec()+600
	while Time.get_ticks_msec()<pause_until:
		await pump(false); first.poll()
	var bounded := false
	for entry: Dictionary in server.get_stats().bulk_windows:
		if entry.actor_id==second.actor_id: bounded=entry.outstanding_chunks==8
	check(bounded and first.status=="live" and second.status=="loading","production slow Replica stops exactlyat8 while first finishes")
	deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and (first.status!="live" or second.status!="live"):
		await pump(false); first.poll(); second.poll()
	check(first.status=="live" and second.status=="live" and first.last_error.is_empty() and second.last_error.is_empty(),"both actual production Replicas complete after receive pause")
	check(first.data!=null and second.data!=null and first.data.blocks==data.blocks and second.data.blocks==data.blocks,"production ACK integration preserves both canonical maps")
	if first.status=="live" and second.status=="live":
		check(first.actor_id!=second.actor_id and first.get_owner_state().is_alive() and second.get_owner_state().is_alive(),"fresh joined production owners have separate spawned identities")
		var all_acked := false
		deadline=Time.get_ticks_msec()+1000
		while Time.get_ticks_msec()<deadline and not all_acked:
			await pump(false); first.poll(); second.poll()
			all_acked=true
			for entry: Dictionary in server.get_stats().bulk_windows:
				if entry.outstanding_chunks!=0: all_acked=false
		check(all_acked,"coalesced final Replica ACKs converge after game readiness")
	check(server.get_stats().totals.input_rejections==0 and server.get_stats().totals.closed==0 and not observed_window_violation,"production join flow control changes no input limits or ownership")
	first.close(); second.close()
	check(first.game.get_stats().connections==0 and first.bulk.get_stats().connections==0 and second.game.get_stats().connections==0 and second.bulk.get_stats().connections==0,"all actual Replica sockets release without preference or scene state")

func finish() -> void:
	if failures>0:
		print("MAP BACKPRESSURE DIAGNOSTIC: "+JSON.stringify({"fast_errors":fast.errors,"slow_errors":slow.errors,"fast_transfer":fast.transfer.get_stats(),"slow_transfer":slow.transfer.get_stats(),"fast_closed":fast.closed,"slow_closed":slow.closed,"fast_window":window(fast),"slow_window":window(slow)}))
	fast.stop(); slow.stop()
	if server!=null: server.stop()
	check(fast.game.get_stats().connections==0 and fast.bulk.get_stats().connections==0 and slow.game.get_stats().connections==0 and slow.bulk.get_stats().connections==0 and (server==null or (server.game_transport.get_stats().connections==0 and server.map_transport.get_stats().connections==0)),"all exact-owned socket state is released")
	print("MAP BACKPRESSURE: %d assertions, %d failures; peak outstanding=%d steps=%d" % [assertions,failures,peak_outstanding,steps])
	quit(0 if failures==0 else 1)
