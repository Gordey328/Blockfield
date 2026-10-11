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
const LOADING_CELL := Vector3i(14,6,12)
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
func event_at(actor: SharedPlayerState, tick: int, type: String = "block_hit", dig: bool = false, cell: Vector3i = CELL) -> Dictionary:
	var source_id := "%d:%d:%d:%d"%[actor.match_epoch,actor.player_id,actor.spawn_generation,maxi(1,actor.event_sequence)]
	var details := {"cell":cell,"position":Vector3(cell)+Vector3(.5,.5,1),"normal":Vector3i.BACK,"source_event_id":source_id}
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
	data.seed_box(Vector3i(14,4,12),Vector3i(15,8,13),RGB)
	check(simulation.configure(data,"0.75","ctf").ok,"source-shaped authority")
	check(server.configure(simulation,COMPAT.build_hash(),COMPAT.rules_hash()),"matching no-regeneration wire/rules identity")
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
	await wait_for(func():return app.world.is_block_damaged(CELL),"repeated surviving hit keeps darkened presentation")
	var idle_deadline := Time.get_ticks_msec()+22000
	while simulation.tick<=last_hit+660 and Time.get_ticks_msec()<idle_deadline: await pump()
	check(simulation.tick>last_hit+660,"real authority crosses the former ten-second recovery window")
	check(app.world.is_block_damaged(CELL) and simulation._block_health.get(CELL,{}).get("health")==25.0,"idle preserves both displayed damage and authoritative25HP")
	check(app.world.get_render_color(CELL,RGB).is_equal_approx(Color8(127,64,32)),"source darkened RGB persists after long idle")
	# Late delivery on the current incarnation must not expire with time.
	var confirmed: int = app.session.confirmed_tick
	app.session.confirmed_tick = last_hit+60000
	app.world.set_block_damaged(CELL,false)
	app._network_mark_block_damage(event_at(actor,last_hit))
	app._network_update_views()
	check(app.world.is_block_damaged(CELL),"valid old surviving-hit effect still darkens at an hour-later confirmed clock")
	app.session.confirmed_tick = confirmed
	# A resumed map baseline carries permanent damage without replaying old FX.
	var owner_id: int = app.session.local_player_id()
	app.network_disconnect()
	await pump(2)
	check(app.network_connect("ws://127.0.0.1:%d/play"%ports.game_port,"ws://127.0.0.1:%d/map"%ports.map_port,"Damage observer",false,true).ok,"same-actor resume starts fresh damage baseline")
	if not await wait_for(func():return server._streams.has(owner_id) and server._streams[owner_id].phase=="baseline","resumed immutable baseline is in flight"):
		await cleanup(); return
	check(not simulation._damage_block(actor,LOADING_CELL,35.0),"new surviving damage occurs after baseline was frozen")
	simulation._record_events([event_at(actor,simulation.tick,"block_hit",false,LOADING_CELL)])
	if not await wait_for(func():return app.network_client.status=="live","resumed map/state barrier"):
		await cleanup(); return
	check(app.session.local_player_id()==owner_id and app.world.is_block_damaged(CELL),"resume preserves owner and restores permanent baseline darkening")
	check(app.world.is_block_damaged(LOADING_CELL),"damage acquired during map loading is restored without healing")
	check(simulation._block_health.get(CELL,{}).get("health")==25.0,"reconnect cannot heal authority health")
	check(simulation._damage_block(actor,CELL,25.0),"later strike destroys using retained damage after idle and resume")
	await wait_for(func():return app.world.get_block(CELL)==0,"authoritative destruction reaches real client")
	check(not app.world.is_block_damaged(CELL) and not simulation._block_health.has(CELL),"destroyed cell clears health and mask")
	await pump(8)
	check(app.world.get_block(CELL)==0,"destroyed block stays air while authority keeps stepping")
	simulation._commit(data.set_block(CELL,RGB,{"tick":simulation.tick,"actor_id":actor.player_id}))
	await wait_for(func():return app.world.get_block(CELL)==RGB,"explicit same-color recreation reaches client")
	check(not app.world.is_block_damaged(CELL),"new incarnation starts healthy")
	check(not simulation._damage_block(actor,CELL,35.0),"recreated voxel starts100HP")
	simulation._record_events([event_at(actor,simulation.tick)])
	await wait_for(func():return app.world.is_block_damaged(CELL),"new incarnation displays its own damage")
	var old_tick: int = simulation.tick
	simulation._commit(data.set_block(CELL,0x014080e0,{"tick":simulation.tick,"actor_id":actor.player_id}))
	await wait_for(func():return app.world.get_block(CELL)==0x014080e0,"replacement delta adopted")
	check(not app.world.is_block_damaged(CELL) and not simulation._block_health.has(CELL),"replacement clears presentation and old health")
	confirmed = app.session.confirmed_tick
	app.session.confirmed_tick = old_tick+60000
	app._network_update_views()
	app._network_mark_block_damage(event_at(actor,old_tick))
	check(not app.world.is_block_damaged(CELL),"old-incarnation guard does not expire and cannot darken replacement")
	app.session.confirmed_tick = confirmed
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
	check(not app.world.is_block_damaged(CELL) and app._network_block_edit_ticks.is_empty(),"disconnect clears old-world presentation before a new baseline")
	await cleanup()
func cleanup() -> void:
	app.network_disconnect()
	server.stop()
	app.stop_audio()
	app.queue_free()
	for frame in 8: await process_frame
	# This fixed-FPS fixture exits soon after real spatial hit sounds. Give the
	# Vorbis/mixer thread wall time to release stopped playback, as lab/UI do.
	var audio_deadline := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < audio_deadline:
		OS.delay_msec(1)
		await process_frame
	if prefs_existed:
		var file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(prefs); file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	check(FileAccess.file_exists("user://settings.cfg")==prefs_existed and (not prefs_existed or FileAccess.get_file_as_bytes("user://settings.cfg")==prefs),"exact preferences restored")
	print("NETWORK BLOCK DAMAGE: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
