extends SceneTree
## Opt-in native measurement. No Main, preferences or public listener.
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const CODEC = preload("res://network/simulation_codec.gd")
const EVENTS = preload("res://network/events_codec.gd")
const P = preload("res://network/protocol.gd")
const HISTORY = preload("res://network/hit_history.gd")
const CLIENT = preload("res://network/client_replica.gd")
const COMPAT = preload("res://network/compatibility.gd")
const TICKS := 300
var checks: int = 0
var failures: int = 0
var results: Dictionary = {}
var errors: Array[String] = []
var total_started: int
var output: String
var publication: String = "legacy"
var socket_clients: int = 2
const SOCKET_BUDGET_MS := 60000

class MeasuredRuntime extends SERVER:
	var observed_events: Array[Dictionary] = []
	func _route_events(events: Array[Dictionary], now: int) -> void:
		observed_events = events
		super._route_events(events,now)

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if errors.size()<32: errors.append(message)
		push_error("SERVER_CAPACITY: "+message)

func summary(samples: Array[int]) -> Dictionary:
	if samples.is_empty(): return {"count":0}
	var ordered: Array[int] = samples.duplicate()
	ordered.sort()
	var sum: int = 0
	for sample: int in samples: sum += sample
	return {"count":samples.size(),"mean_us":float(sum)/samples.size(),"p95_us":ordered[floori((ordered.size()-1)*.95)],"max_us":ordered[-1],"total_us":sum}

func map_data() -> DATA:
	var data := DATA.new()
	check(data.clear(Vector3i(128,16,64),51)==OK,"bounded canonical arena")
	data.seed_box(Vector3i.ZERO,Vector3i(128,2,64),0x01608070)
	return data

func authority(count: int) -> MATCH:
	var sim := MATCH.new()
	check(sim.configure(map_data()).ok,"production Match configure")
	sim.friendly_fire = false
	for i: int in range(count):
		var feet := Vector3(6+(i%8)*8,2.01,8+(i/8)*8)
		var added: Dictionary = sim.add_actor("Bench%d"%i,2,i+1,feet)
		check(added.ok,"trusted isolated actor admission")
		if not added.ok: break
		var actor: SharedPlayerState = sim.get_actor(added.actor_id)
		check(not RULES.spawn(actor,0,feet,0,i%3).is_empty(),"source inventory spawn")
	return sim

func encode_snapshots(sim: MATCH) -> Dictionary:
	if publication=="prepared": return encode_prepared_snapshots(sim)
	var bytes: int = 0
	for id: int in sim.actors:
		var converted: Dictionary = CODEC.from_snapshot(sim.snapshot_for(id))
		if not converted.ok: return {"ok":false,"error":converted.error}
		var encoded: P.Result = P.encode(P.make_packet(P.Kind.MATCH_STATE,converted.payload,sim.epoch,sim.tick,sim.get_actor(id).spawn_generation))
		if not encoded.ok: return {"ok":false,"error":encoded.error}
		bytes += encoded.bytes.size()
	return {"ok":true,"bytes":bytes}

func encode_prepared_snapshots(sim: MATCH) -> Dictionary:
	if sim.actors.is_empty(): return {"ok":true,"bytes":0}
	var owners: Array = sim.actors.keys()
	var shared := CODEC.prepare_shared(sim.snapshot_for(owners[0]))
	if not shared.ok: return {"ok":false,"error":shared.error}
	var bytes: int = 0
	for id: int in owners:
		var prepared := P.prepare_state(shared.frame,sim.get_actor(id))
		if not prepared.ok: return {"ok":false,"error":prepared.error}
		var frame: P.FrozenFrame = prepared.frame
		bytes+=frame.bytes().size()
	return {"ok":true,"bytes":bytes}

func encode_events(sim: MATCH, source: Array[Dictionary]) -> Dictionary:
	if publication=="prepared": return encode_prepared_events(sim,source)
	var bytes: int = 0
	for id: int in sim.actors:
		var selected: Array[Dictionary] = []
		for event: Dictionary in source:
			var scope := EVENTS.visibility(event.type)
			if scope=="public" or (scope=="owner" and int(event.get("owner_id",0))==id): selected.append(event)
		for offset: int in range(0,selected.size(),EVENTS.MAX_EVENTS):
			var batch: Array[Dictionary] = []
			batch.assign(selected.slice(offset,mini(offset+EVENTS.MAX_EVENTS,selected.size())))
			var converted: Dictionary = EVENTS.from_events(sim.epoch,batch)
			if not converted.ok: return {"ok":false,"error":converted.error}
			var last_tick: int = 0
			for event: Dictionary in converted.payload.events: last_tick = maxi(last_tick,event.tick)
			var encoded: P.Result = P.encode(P.make_packet(P.Kind.GAME_EVENTS,converted.payload,sim.epoch,last_tick,converted.payload.last_sequence))
			if not encoded.ok: return {"ok":false,"error":encoded.error}
			bytes += encoded.bytes.size()
	return {"ok":true,"bytes":bytes}

func encode_prepared_events(sim: MATCH, source: Array[Dictionary]) -> Dictionary:
	var shared := EVENTS.prepare_shared(sim.epoch,source)
	if not shared.ok: return {"ok":false,"error":shared.error}
	var bytes: int = 0
	for id: int in sim.actors:
		var prepared := P.prepare_events(shared.events,id)
		if not prepared.ok: return {"ok":false,"error":prepared.error}
		for frame: P.FrozenFrame in prepared.frames: bytes+=frame.bytes().size()
	return {"ok":true,"bytes":bytes}

func pure_case(count: int) -> void:
	var started := Time.get_ticks_msec()
	var sim := authority(count)
	var runtime := MeasuredRuntime.new()
	check(runtime.configure(sim,COMPAT.build_hash(),COMPAT.rules_hash()),"production Runtime configure")
	for _warm: int in range(60): runtime.step_once()
	for actor: SharedPlayerState in sim.actors.values():
		actor.input_buttons = RULES.Buttons.PRIMARY
		actor.input_move = Vector2(.1,0)
	var tick_samples: Array[int] = []
	var snapshot_samples: Array[int] = []
	var event_samples: Array[int] = []
	var combined_samples: Array[int] = []
	var sample_events: Array[Dictionary] = []
	var shot_ticks: Dictionary[int,Array] = {}
	var snapshot_bytes: int = 0
	var event_bytes: int = 0
	for measured: int in range(TICKS):
		for id: int in sim.actors: runtime._shot_ticks[id] = maxi(0,sim.tick-8)
		var began := Time.get_ticks_usec()
		var stepped := runtime.step_once()
		var elapsed := Time.get_ticks_usec()-began
		if not stepped: check(false,"Runtime fixed step failed"); break
		tick_samples.append(elapsed)
		if runtime.observed_events.size()>sample_events.size(): sample_events=runtime.observed_events
		for event: Dictionary in runtime.observed_events:
			if event.type=="shot":
				if not shot_ticks.has(event.owner_id): shot_ticks[event.owner_id] = []
				shot_ticks[event.owner_id].append(sim.tick)
		if measured%30==29: await process_frame
	# Measure production per-owner codec/fanout separately. Five samples bound
	# slow debug-build work; this is the cost of a 20Hz publication, not proof
	# that 100 such publications were sustained during these 300 fixed steps.
	for _sample: int in range(5):
		var overall := Time.get_ticks_usec()
		var began := Time.get_ticks_usec()
		var encoded := encode_snapshots(sim)
		var snapshot_us := Time.get_ticks_usec()-began
		if not encoded.ok: check(false,"snapshot encoding: "+encoded.error);break
		snapshot_samples.append(snapshot_us); snapshot_bytes += encoded.bytes
		began=Time.get_ticks_usec()
		var encoded_events:=encode_events(sim,sample_events)
		var event_us:=Time.get_ticks_usec()-began
		if not encoded_events.ok:check(false,"event encoding: "+encoded_events.error);break
		event_samples.append(event_us);event_bytes+=encoded_events.bytes
		combined_samples.append(Time.get_ticks_usec()-overall)
		await process_frame
	var weapons: Array = []
	for id: int in sim.actors:
		var actor := sim.get_actor(id)
		var info := PROFILES.get_info(sim.profile,actor.weapon)
		var times: Array = shot_ticks.get(id,[])
		var expected := mini(info.clip_size,ceili(float(TICKS)/(info.delay*60.0)))
		check(tick_samples.size()==TICKS and times.size()==expected,"300 ticks source cadence with natural magazine depletion actor%d"%id)
		weapons.append({"id":id,"weapon":actor.weapon,"shots":times.size(),"expected":expected,"magazine":actor.magazine,"shot_ticks":times})
	results["pure_%d"%count] = {"actors":count,"publication":publication,"ticks":tick_samples.size(),"runtime_step":summary(tick_samples),"snapshot_20hz_batch":summary(snapshot_samples),"event_burst_fanout":summary(event_samples),"snapshot_plus_burst_encoding":summary(combined_samples),"snapshot_bytes":snapshot_bytes,"event_bytes":event_bytes,"burst_events":sample_events.size(),"history":runtime.hit_history.get_stats(),"rewind":sim.get_rewind_stats(),"weapons":weapons,"wall_ms":Time.get_ticks_msec()-started,"last_error":sim.last_error,"sockets":0}
	runtime.stop()
	print("SERVER_CAPACITY pure %d: %s"%[count,JSON.stringify(results["pure_%d"%count])])

func history_case() -> void:
	var sim := authority(32)
	sim.step_fixed()
	sim.data.last_tick = sim.tick
	var actors: Array[SharedPlayerState] = []
	actors.assign(sim.actors.values())
	var history := HISTORY.new()
	check(history.reset(sim.epoch,sim.data).ok and history.record_frame(sim.tick,sim.data,actors,[]).ok,"bounded history initial frame")
	var changes: Array[Dictionary] = []
	for z: int in range(64):
		for x: int in range(64,128):
			for y: int in range(2,10): changes.append({"cell":Vector3i(x,y,z),"before":0,"after":0x01708090,"flags":0})
	var tx: Dictionary = {"epoch":sim.epoch,"map_sequence":1,"transaction_id":1,"tick":1,"actor_id":0,"action_id":1,"dimensions":sim.data.dimensions,"changes":changes}
	var began := Time.get_ticks_usec()
	check(sim.data.apply_transaction(tx).ok,"full bounded private benchmark authority receipt")
	var apply_us := Time.get_ticks_usec()-began
	sim.step_fixed()
	sim.data.last_tick = sim.tick
	began = Time.get_ticks_usec()
	check(history.record_frame(sim.tick,sim.data,actors,[tx]).ok,"history accepts 32768 committed ordered changes")
	var record_us := Time.get_ticks_usec()-began
	began=Time.get_ticks_usec()
	var cold := history.query_at(0,1)
	var cold_query_us := Time.get_ticks_usec()-began
	check(cold.ok and cold.query.is_valid() and cold.query.get_block(Vector3i(64,2,0))==0,"first cold query restores pre-edit terrain")
	if cold.ok: cold.query.cancel()
	var queries: Dictionary = {}
	for count: int in [1,8,32]:
		var samples: Array[int] = []
		for _repeat: int in range(3):
			began = Time.get_ticks_usec()
			for _query: int in range(count):
				var queried := history.query_at(0,1)
				if not queried.ok: check(false,"history query: "+queried.error);break
				check(queried.query.is_valid() and queried.query.get_block(Vector3i(64,2,0))==0,"rewound terrain is isolated pre-edit air")
				queried.query.cancel()
			samples.append(Time.get_ticks_usec()-began)
		queries[str(count)] = summary(samples)
	sim.set_rewind_query_factory(history.query_at)
	var commands: Dictionary = {}
	var admitted: Dictionary = {}
	for actor: SharedPlayerState in actors:
		actor.tool_raise = 1.0
		var cmd := RULES.Command.new()
		cmd.sequence = 1; cmd.spawn_generation = actor.spawn_generation; cmd.buttons = RULES.Buttons.PRIMARY
		commands[actor.player_id] = cmd; admitted[actor.player_id] = 0
	# Trusted benchmark-only cache eviction: the actual shot tick must pay the
	# first cold build, as it does after Runtime records each new closed frame.
	if history.has_method("_clear_query_cache"): history.call("_clear_query_cache")
	began = Time.get_ticks_usec()
	var fired := sim.step_fixed(commands,admitted)
	var shot_step_us := Time.get_ticks_usec()-began
	var shots: int = 0
	for event: Dictionary in fired: if event.type=="shot":shots+=1
	check(shots==32 and sim.get_rewind_stats().denied_shots==0,"32 simultaneous valid historical preplans")
	results.history_full = {"changes":changes.size(),"apply_us":apply_us,"record_us":record_us,"cold_query_us":cold_query_us,"query_batches":queries,"query_batches_cache":"warm when implementation supports reuse","32_shot_step_us":shot_step_us,"32_shot_cache":"cold before step","shots":shots,"history":history.get_stats(),"rewind":sim.get_rewind_stats()}
	print("SERVER_CAPACITY full history: "+JSON.stringify(results.history_full))

func terrain_case() -> void:
	var remove_samples: Array[int] = [];var record_samples: Array[int] = []
	var changed: int = 0;var collapsed: int = 0
	for _repeat:int in range(12):
		var data:=DATA.new();data.clear(Vector3i(16,16,16),51)
		data.seed_box(Vector3i.ZERO,Vector3i(16,2,16),0x01608070)
		data.seed_box(Vector3i(8,2,8),Vector3i(9,7,9),0x01aabbcc)
		var history:=HISTORY.new();history.reset(51,data)
		check(history.record_frame(0,data,[],[]).ok,"terrain baseline frame")
		var began:=Time.get_ticks_usec()
		var tx:=data.remove_blocks([Vector3i(8,2,8)],true,{"tick":1,"actor_id":0,"action_id":1})
		remove_samples.append(Time.get_ticks_usec()-began)
		check(tx.ok and tx.changed and tx.changes.size()==5,"source support removal returns five atomic cells")
		changed=tx.changes.size();collapsed=0
		for change:Dictionary in tx.changes:if change.flags==1:collapsed+=1
		check(collapsed==4,"source support collapse flags remain ordered authority receipt")
		began=Time.get_ticks_usec();var recorded:=history.record_frame(1,data,[],[tx]);record_samples.append(Time.get_ticks_usec()-began)
		check(recorded.ok,"same-time source collapse history receipt")
	results.terrain={"support_remove_and_collapse":summary(remove_samples),"history_record":summary(record_samples),"changed":changed,"collapsed":collapsed}
	print("SERVER_CAPACITY terrain: "+JSON.stringify(results.terrain))

func queue_peaks(runtime: SERVER) -> Dictionary:
	var frames: int = 0; var bytes: int = 0; var connections: int = 0
	for transport: RefCounted in [runtime.game_transport,runtime.map_transport]:
		for peer: Dictionary in transport.get_stats().peers:
			connections+=1; frames=maxi(frames,peer.queued_frames); bytes=maxi(bytes,peer.queued_bytes+peer.socket_buffered_bytes)
	return {"frames":frames,"bytes":bytes,"connections":connections}

func socket_case() -> void:
	var sim := MATCH.new()
	check(sim.configure(map_data()).ok,"socket Match configure")
	sim.friendly_fire = false
	var runtime := SERVER.new()
	check(runtime.configure(sim,COMPAT.build_hash(),COMPAT.rules_hash()),"socket Runtime configure")
	var endpoints := runtime.start()
	check(endpoints.ok,"native ephemeral loopback listeners")
	if not endpoints.ok:return
	var replicas: Array[CLIENT] = []
	var joins: Array[int] = []
	var started := Time.get_ticks_msec()
	var max_frames: int = 0; var max_bytes: int = 0
	var completed_joins: int = 0
	var counts: Array[int] = [1,2]
	if socket_clients==32: counts.append_array([8,16,32])
	var stop_reason := ""
	for count: int in counts:
		if Time.get_ticks_msec()-started>=SOCKET_BUDGET_MS: stop_reason="global socket budget"; break
		while replicas.size()<count:
			var client := CLIENT.new()
			var joined_at := Time.get_ticks_msec()
			check(client.connect_to("ws://127.0.0.1:%d/play"%endpoints.game_port,"ws://127.0.0.1:%d/map"%endpoints.map_port,"SocketBench%d"%replicas.size()).ok,"actual complete client start")
			replicas.append(client)
			while client.status not in ["live","failed","closed"] and Time.get_ticks_msec()-joined_at<5000 and Time.get_ticks_msec()-started<SOCKET_BUDGET_MS:
				runtime.poll()
				for replica: CLIENT in replicas: replica.poll(); replica.drain_events()
				runtime.step_once()
				await process_frame
			joins.append(Time.get_ticks_msec()-joined_at)
			check(client.status=="live","bounded sequential actual join")
			if client.status!="live":
				stop_reason="global socket join budget" if Time.get_ticks_msec()-started>=SOCKET_BUDGET_MS else "join failed or per-client deadline"
				break
			completed_joins+=1
			if replicas.size()%8==0: print("SERVER_CAPACITY joined %d actual clients after %d ms"%[replicas.size(),Time.get_ticks_msec()-started])
		if replicas.size()!=count or replicas[-1].status!="live":break
		var steps: Array[int] = []; var polls: Array[int] = []; var client_polls: Array[int] = [];var whole: Array[int] = []
		var case_start := Time.get_ticks_msec()
		for measured: int in range(60):
			if Time.get_ticks_msec()-started>=SOCKET_BUDGET_MS:stop_reason="global socket budget"; break
			var overall := Time.get_ticks_usec()
			for replica: CLIENT in replicas:
				var submitted := replica.submit_input(0,Vector2(.05,0),0,0)
				if not submitted.ok:check(false,"actual input "+submitted.error)
			var began := Time.get_ticks_usec();runtime.poll();polls.append(Time.get_ticks_usec()-began)
			began=Time.get_ticks_usec();check(runtime.step_once(),"socket fixed step");steps.append(Time.get_ticks_usec()-began)
			began=Time.get_ticks_usec()
			for replica: CLIENT in replicas:replica.poll();replica.drain_events()
			client_polls.append(Time.get_ticks_usec()-began)
			whole.append(Time.get_ticks_usec()-overall)
			var peaks:=queue_peaks(runtime);max_frames=maxi(max_frames,peaks.frames);max_bytes=maxi(max_bytes,peaks.bytes)
			await process_frame
		for replica:CLIENT in replicas:check(replica.status=="live" and replica.last_error.is_empty(),"healthy real client after measured batch")
		check(steps.size()==60,"socket count%d completed bounded60-step batch"%count)
		results["sockets_%d"%count] = {"clients":count,"publication":"Runtime default prepared, independent of benchmark flag","ticks":steps.size(),"server_step":summary(steps),"server_poll":summary(polls),"client_poll_decode_all":summary(client_polls),"whole_harness_compute":summary(whole),"wall_ms":Time.get_ticks_msec()-case_start,"peak_peer_frames":max_frames,"peak_peer_bytes":max_bytes,"runtime":runtime.get_stats(),"join_ms":joins.duplicate()}
		print("SERVER_CAPACITY sockets %d: %s"%[count,JSON.stringify(results["sockets_%d"%count])])
	var client_states: Array[Dictionary] = []
	var live_clients: int = 0
	for replica: CLIENT in replicas:
		if replica.status=="live": live_clients+=1
		client_states.append({"status":replica.status,"last_error":replica.last_error})
	results.socket_run={"requested_clients":socket_clients,"attempted_clients":replicas.size(),"completed_joins":completed_joins,"live_clients_at_end":live_clients,"client_states":client_states,"wall_ms":Time.get_ticks_msec()-started,"stop_reason":stop_reason,"budget_ms":SOCKET_BUDGET_MS,
		"terminal_runtime":runtime.get_stats(),"terminal_queues":queue_peaks(runtime),"simulation_error":sim.last_error}
	check(replicas.size()==socket_clients and stop_reason.is_empty(),"requested real socket roster completed without deadline")
	for replica:CLIENT in replicas:replica.close()
	runtime.stop()
	check(runtime.get_stats().game.connections==0 and runtime.get_stats().map.connections==0,"all benchmark listeners and sockets released")

func run() -> void:
	total_started=Time.get_ticks_msec()
	var history_only := "--history-only" in OS.get_cmdline_user_args()
	var sockets_only := "--sockets-only" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--publication="):
			publication=argument.trim_prefix("--publication=")
		if argument.begins_with("--socket-clients="):
			var requested := argument.trim_prefix("--socket-clients=")
			socket_clients=requested.to_int() if requested.is_valid_int() else 0
	if publication not in ["legacy","prepared"]:
		push_error("SERVER_CAPACITY: --publication must be legacy or prepared")
		quit(1); return
	if socket_clients not in [2,32] or (history_only and sockets_only):
		push_error("SERVER_CAPACITY: --socket-clients must be2 or32; choose one isolated mode")
		quit(1); return
	var hashes:Dictionary={}
	for path:String in ["res://network/server_runtime.gd","res://network/simulation_codec.gd","res://network/events_codec.gd","res://network/protocol.gd","res://network/hit_history.gd","res://network/ws_transport.gd","res://network/input_queue.gd","res://network/session_registry.gd","res://network/map_transfer.gd","res://network/client_replica.gd","res://network/compatibility.gd","res://simulation/match_simulation.gd","res://simulation/player_rules.gd","res://world/voxel_data.gd","res://gameplay/lab_hit_volumes.gd"]:hashes[path]=FileAccess.get_sha256(path)
	results.source_hashes=hashes
	var output_name := "server-capacity.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-name="):
			var requested := argument.trim_prefix("--output-name=")
			if requested.get_file()==requested and requested.ends_with(".json"): output_name=requested
	output=ProjectSettings.globalize_path("res://../.cache/benchmarks/"+output_name)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if not history_only and not sockets_only:
		for count:int in [1,8,16,32]:await pure_case(count)
	if not sockets_only: history_case()
	if not history_only:
		if not sockets_only: terrain_case()
		await process_frame
		await socket_case()
	results.meta={"engine":Engine.get_version_info().string,"publication":publication,"socket_publication":"Runtime default prepared; no snapshot factory override","os":OS.get_name(),"processor":OS.get_processor_name(),"processor_count":OS.get_processor_count(),"wall_ms":Time.get_ticks_msec()-total_started,"checks":checks,"failures":failures,"errors":errors,"preferences":"untouched","tick_hz":60,"snapshot_hz":20,"renderer":"headless; no Main/render/audio"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("SERVER_CAPACITY COMPLETE: %d checks, %d failures; %s"%[checks,failures,output])
	await process_frame
	await process_frame
	quit(1 if failures else 0)
