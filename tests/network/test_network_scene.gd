extends SceneTree
## Real Main/World/Controller/HUD with two sockets and authoritative map.
const SCENE = preload("res://scenes/network.tscn")
const SERVER = preload("res://network/server_runtime.gd")
const CLIENT = preload("res://network/client_replica.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const COMPAT = preload("res://network/compatibility.gd")
var assertions := 0
var failures := 0
var app: Node3D
var server := SERVER.new()
var other := CLIENT.new()
var other_events: Array[Dictionary] = []
var prefs_existed := false
var prefs := PackedByteArray()
func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value: failures += 1;push_error("NETWORK SCENE: "+message)
func pump(count: int = 1) -> void:
	for frame in count:
		server.poll()
		other.poll()
		other_events.append_array(other.drain_events())
		if not server.step_once(): check(false,"authority fixed step")
		await physics_frame
		await process_frame
func wait_for(predicate: Callable,message: String) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		if app.network_client.status == "failed" or other.status == "failed": break
		await pump()
	var result: bool = predicate.call()
	check(result,message+" ("+app.network_client.status+"/"+other.status+")")
	return result
func _run() -> void:
	prefs_existed = FileAccess.file_exists("user://settings.cfg")
	if prefs_existed: prefs = FileAccess.get_file_as_bytes("user://settings.cfg")
	var data := DATA.new()
	check(data.clear(Vector3i(32,16,32),901)==OK,"small genuine canonical map")
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	var simulation := MATCH.new()
	check(simulation.configure(data,"0.75","ctf").ok,"authoritative CTF")
	check(server.configure(simulation,COMPAT.build_hash(),COMPAT.rules_hash()),"runtime")
	var ports := server.start()
	check(ports.ok,"native game/map listeners")
	app = SCENE.instantiate()
	root.add_child(app)
	await pump(2)
	check(app.network_mode and app.session is NetworkSession,"actual network inherited scene")
	check(app.hud.is_menu_open() and app.session.targets.is_empty(),"connection menu has no offline targets")
	check(app.hud._network_menu != null,"real network UI attached")
	var game_url := "ws://127.0.0.1:%d/play"%ports.game_port
	var map_url := "ws://127.0.0.1:%d/map"%ports.map_port
	check(app.network_connect(game_url,map_url,"Scene owner").ok,"real Main connect")
	check(other.connect_to(game_url,map_url,"Second guest").ok,"second independent replica")
	if not await wait_for(func():return app.network_client.status=="live" and other.status=="live","both map/state barriers complete"):
		await cleanup();return
	await pump(28)
	var id: int = app.session.local_player_id()
	check(id>0 and id!=other.actor_id,"canonical local identity")
	check(app.world.data==app.network_client.data and app.world.dimensions==Vector3i(32,16,32),"World adopts exact installed replica map")
	check(app.session.targets.size()==1 and app._target_nodes.size()==1,"only real remote actor creates soldier")
	var target: Dictionary = app.session.get_target(other.actor_id)
	check(target.name=="Second guest" and not target.health_known and target.health==-1,"remote name and unknown health stay public")
	check(app._objective_nodes.size()==4,"confirmed two bases/two intel models")
	var ammo: int = simulation.get_actor(id).magazine
	app.reset_lab();app.reset_targets();app.spawn_lab_target();app.session.restock();app.session.damage_player(1000)
	await pump(2)
	check(simulation.get_actor(id).magazine==ammo and simulation.get_actor(id).health==100 and simulation.actors.size()==2,"Main and session cheats have no authority")
	app.hud.set_menu_visible(false)
	Input.action_press("primary")
	await pump(1)
	Input.action_release("primary")
	await pump(10)
	check(simulation.get_actor(id).magazine==ammo-1 and app.session.magazine==ammo-1,"actual controller shot confirmed in HUD model")
	check(app.session.shots_fired==1 and app.player._kick>0,"one confirmed shot plus real cosmetic view")
	app.hud.set_menu_visible(true)
	var chat_before: int = app.hud._chat.messages.size()
	app.hud._send_chat("Scene handshake",false)
	check(app.hud._chat.messages.size()==chat_before,"no optimistic chat echo")
	await pump(6)
	check(app.hud._chat.messages.size()==chat_before+1 and app.hud._chat.messages.back().text=="Scene handshake","server chat reaches actual HUD")
	check(other_events.any(func(e):return e.get("type")=="chat" and e.text=="Scene handshake"),"same confirmed chat reaches second client")
	check(app.network_can_resume(),"Main exposes safe resume status")
	app.network_disconnect()
	await pump(2)
	check(app.hud.is_menu_open() and app._target_nodes.is_empty() and app.session.health==0,"disconnect clears live presentation")
	check(app.network_connect(game_url,map_url,"Scene owner",false,true).ok,"Main resumes stored credential")
	await wait_for(func():return app.network_client.status=="live","resumed Main crosses fresh baseline")
	await pump(3)
	check(app.session.local_player_id()==id and app.session.magazine==ammo-1,"resume preserves owner and authoritative resources")
	await cleanup()
func cleanup() -> void:
	app.network_disconnect()
	other.close()
	server.stop()
	app.queue_free()
	for frame in 8: await process_frame
	if prefs_existed:
		var file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(prefs);file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	check(FileAccess.file_exists("user://settings.cfg")==prefs_existed and (not prefs_existed or FileAccess.get_file_as_bytes("user://settings.cfg")==prefs),"exact preferences restored")
	finish()
func finish() -> void:
	Input.action_release("primary")
	other.close();server.stop()
	print("NETWORK SCENE: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
