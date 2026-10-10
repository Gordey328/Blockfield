extends SceneTree
## Real authority/codec/sockets/Main/World. Hit fixtures use authority APIs;
## transport/input admission remains covered by existing network-scene suites.
const SCENE = preload("res://scenes/network.tscn")
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const COMPAT = preload("res://network/compatibility.gd")
const CELL := Vector3i(12,6,12)
const RGB := 0x01ff8041
var assertions := 0
var failures := 0
var app: Node3D
var server := SERVER.new()
var simulation := MATCH.new()
var prefs_existed := false
var prefs := PackedByteArray()
var next_step_us := 0

func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error("NETWORK BLOCK DAMAGE: " + message)
func pump(count: int = 1) -> void:
	for frame in count:
		var now := Time.get_ticks_usec()
		if now < next_step_us: OS.delay_usec(next_step_us-now)
		next_step_us = Time.get_ticks_usec()+16667
		server.poll()
		if not server.step_once(): check(false,"real fixed authority step")
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout
func wait_for(predicate: Callable,message: String) -> bool:
	var deadline := Time.get_ticks_msec()+14000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		if app.network_client.status == "failed": break
		await pump()
	var result: bool = predicate.call()
	check(result,message+" ("+app.network_client.status+", "+app.network_client.last_error+")")
	return result
func event_at(actor: SharedPlayerState, tick: int, type: String = "block_hit", dig: bool = false) -> Dictionary:
	var source_id := "%d:%d:%d:%d"%[actor.match_epoch,actor.player_id,actor.spawn_generation,maxi(1,actor.event_sequence)]
	var details := {"cell":CELL,"position":Vector3(CELL)+Vector3(.5,.5,1),"normal":Vector3i.BACK,"source_event_id":source_id}
	if type == "spade_block_hit": details.dig = dig
	else: details.pellet = 0
	return RULES.event(actor,tick,type,details).duplicate(true)
func _run() -> void:
	prefs_existed = FileAccess.file_exists("user://settings.cfg")
	if prefs_existed: prefs = FileAccess.get_file_as_bytes("user://settings.cfg")
	var data := DATA.new()
	check(data.clear(Vector3i(32,16,32),1909)==OK,"canonical small map")
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	data.seed_box(Vector3i(12,4,12),Vector3i(13,8,13),RGB)
	check(simulation.configure(data,"0.75","ctf").ok,"source-shaped authority")
	check(server.configure(simulation,COMPAT.build_hash(),COMPAT.rules_hash()),"unchanged wire/rules identity")
	var ports := server.start()
	check(ports.ok,"real WebSocket listener")
	app = SCENE.instantiate()
	root.add_child(app)
	await pump(2)
	check(app.network_connect("ws://127.0.0.1:%d/play"%ports.game_port,"ws://127.0.0.1:%d/map"%ports.map_port,"Damage observer").ok,"actual Main connection")
	if not await wait_for(func():return app.network_client.status=="live","installed baseline/state barrier"):
		await cleanup(); return
	await pump(28)
	var actor := simulation.get_actor(app.session.local_player_id())
	actor.motion.feet_position = Vector3(12.5,4.01,14.5)
	actor.yaw = 0.0; actor.pitch = 0.0
	var sequence: int = data.map_sequence
	var bash := RULES.event(actor,simulation.tick,"spade_bash")
	var spade := simulation._resolve_spade(actor,false,bash.event_id)
	check(spade.any(func(e):return e.type=="spade_block_hit" and e.cell==CELL),"genuine source spade ray reaches surviving block")
	check(simulation._block_health.get(CELL,{}).get("health")==45.0,"actual source spade applies55 damage")
	var first_hit: int = simulation.tick
	simulation._record_events([bash])
	simulation._record_events(spade)
	var encoded := EventsCodec.prepare_shared(simulation.epoch,simulation._events)
	check(encoded.ok,"authoritative fixture events serialize: "+encoded.error)
	if not encoded.ok: print("DAMAGE EVENT DIAGNOSTIC: ", simulation._events)
	if not await wait_for(func():return app.world.is_block_damaged(CELL),"confirmed socket event darkens actual World"):
		print("DAMAGE SOCKET DIAGNOSTICS: ", server.get_stats())
		await cleanup(); return
	check(app.world.get_block(CELL)==RGB and data.map_sequence==sequence,"damage leaves canonical RGB and map sequence intact")
	check(app.world.get_render_color(CELL,RGB).is_equal_approx(Color8(127,64,32)),"confirmed surviving block uses exact floor-halved RGB")
	await pump(30)
	check(not simulation._damage_block(actor,CELL,20.0),"second surviving authority hit")
	var last_hit: int = simulation.tick
	simulation._record_events([event_at(actor,last_hit)])
	await wait_for(func():return app._network_block_damage_ticks.get(CELL,-1)==last_hit,"repeated confirmed firearm hit extends timer")
	var recovery_deadline := Time.get_ticks_msec()+20000
	while simulation.tick<=first_hit+603 and Time.get_ticks_msec()<recovery_deadline: await pump()
	check(simulation.tick>first_hit+603,"authority recovery probe reaches its bounded deadline")
	check(app.world.is_block_damaged(CELL) and simulation._block_health.has(CELL),"first-hit ten seconds cannot clear a more recent hit")
	await wait_for(func():return not app.world.is_block_damaged(CELL),"confirmed latest-hit ten-second recovery")
	check(not simulation._block_health.has(CELL) and app.world.get_render_color(CELL,RGB).is_equal_approx(Color8(255,128,65)),"authority recovery and displayed source RGB agree")
	# Exact tick boundary and late/replacement policy are exercised directly on
	# the same Main adapter, independently of20Hz snapshot quantization.
	var tick: int = simulation.tick+10
	app.session.confirmed_tick = tick+600
	app._network_mark_block_damage(event_at(actor,tick))
	app._network_restore_block_colors()
	check(app.world.is_block_damaged(CELL),"600th tick retains damage like MatchSimulation")
	app.session.confirmed_tick = tick+601
	app._network_restore_block_colors()
	check(not app.world.is_block_damaged(CELL),"601st confirmed tick restores")
	app._network_mark_block_damage(event_at(actor,tick))
	check(not app.world.is_block_damaged(CELL),"already expired queued effect cannot re-darken")
	app.session.confirmed_tick = simulation.tick
	check(not simulation._damage_block(actor,CELL,35.0),"new source damage after recovery")
	simulation._record_events([event_at(actor,simulation.tick)])
	await wait_for(func():return app.world.is_block_damaged(CELL),"new damage after recovery crosses real wire")
	var old_tick: int = simulation.tick
	simulation._commit(data.set_block(CELL,0x014080e0,{"tick":simulation.tick,"actor_id":actor.player_id}))
	await wait_for(func():return app.world.get_block(CELL)==0x014080e0,"replacement delta adopted")
	check(not app.world.is_block_damaged(CELL) and not app._network_block_damage_ticks.has(CELL),"replacement clears damage and timer")
	app._network_mark_block_damage(event_at(actor,old_tick))
	check(not app.world.is_block_damaged(CELL),"queued old-incarnation hit cannot darken replacement")
	await pump(2)
	var predicted := event_at(actor,simulation.tick)
	predicted.predicted = true
	app._network_mark_block_damage(predicted)
	app._network_mark_block_damage(event_at(actor,simulation.tick,"spade_block_hit",true))
	check(not app.world.is_block_damaged(CELL),"prediction and dig do not invent partial damage")
	var bedrock := event_at(actor,simulation.tick)
	bedrock.cell = Vector3i(12,1,12)
	app._network_mark_block_damage(bedrock)
	check(not app.world.is_block_damaged(bedrock.cell),"bedrock remains healthy")
	check(not simulation._damage_block(actor,CELL,35.0),"replacement begins with fresh source health")
	simulation._record_events([event_at(actor,simulation.tick)])
	await wait_for(func():return app.world.is_block_damaged(CELL),"new-incarnation hit is displayed")
	app.network_disconnect()
	check(not app.world.is_block_damaged(CELL) and app._network_block_damage_ticks.is_empty() and app._network_block_edit_ticks.is_empty(),"disconnect clears all transient presentation")
	await cleanup()
func cleanup() -> void:
	app.network_disconnect()
	server.stop()
	app.queue_free()
	for frame in 8: await process_frame
	if prefs_existed:
		var file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(prefs); file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	check(FileAccess.file_exists("user://settings.cfg")==prefs_existed and (not prefs_existed or FileAccess.get_file_as_bytes("user://settings.cfg")==prefs),"exact preferences restored")
	print("NETWORK BLOCK DAMAGE: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
