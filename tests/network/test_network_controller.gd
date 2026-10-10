extends SceneTree
const PLAYER = preload("res://gameplay/player_controller.gd")
const SESSION = preload("res://network/network_session.gd")
const CLIENT = preload("res://network/client_replica.gd")
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const COMPATIBILITY = preload("res://network/compatibility.gd")
const DT := 1.0/60
const ACTIONS := ["left","right","forward","back","jump","crouch","sprint","sneak","primary","secondary","reload","tool_spade","tool_block","tool_weapon","tool_grenade","eyedropper","view_toggle","last_tool"]
var assertions := 0
var failures := 0
var server: SERVER
var simulation: MATCH
var clients: Array[CLIENT] = []
var session: SESSION
var player: PLAYER
var lab: TestLab
var world: VoxelWorld
var skin: TestSkin
var new_actions: Array[String] = []
var started := {}

class TraceServer extends SERVER:
	var close_reasons: Array[String] = []
	var input_receipt := {}
	func _game_packet(connection: int,packet: BlockfieldProtocol.Packet,now: int) -> void:
		if packet.kind==P.Kind.INPUT_BATCH:
			var id := registry.owner_of_game(connection)
			if _inputs.has(id):
				var current: BlockfieldInputQueue = _inputs[id]
				var shadow := BlockfieldInputQueue.new()
				for field in ["epoch","generation","input_ack","needs_resync","_last_server_tick","_last_command_tick","_tail_sequence","_tail_input_tick"]: shadow.set(field,current.get(field))
				shadow._pending=current._pending.duplicate()
				var result := shadow.accept(packet,simulation.tick)
				input_receipt={"server_tick":simulation.tick,"input_tick":packet.tick,"sequence":packet.payload.records[0].input_sequence,"generation":packet.sequence,"queue":current.get_stats(),"error":result.error}
		super._game_packet(connection,packet,now)
	func _close_game(connection: int,reason: String,now: int) -> void:
		var wire_reason := reason
		if reason == "state serialization failed":
			var id := registry.owner_of_game(connection,false)
			var result := preload("res://network/simulation_codec.gd").from_snapshot(simulation.snapshot_for(id))
			var actor := simulation.get_actor(id)
			reason += ": %s; fall_speed=%s, climb=%s, tick=%s" % [result.error,actor.motion.fall_speed,actor.motion.last_climb_time,actor.last_tick]
		elif reason == "invalid input stream": reason += ": "+JSON.stringify(input_receipt)
		close_reasons.append(reason)
		super._close_game(connection,wire_reason,now)

class TestLab extends Node3D:
	var network_client: CLIENT
	var audio: Object
	var effects: Object
	var hud: Object
	var browser_pointer_fallback := false
	var graphics_options := {"shake":0}
	func handle_focus_input(_event: InputEvent) -> bool: return false
	func get_player_corpse_center() -> Vector3: return Vector3(8,4,8)

class TestSkin extends Node3D:
	var fires := 0
	var reloads := 0
	var poses := 0
	var blends := {}
	var changing := false
	func set_selection(_tool: int,_weapon: int) -> void: pass
	func set_team(_team: int,_color: Color) -> void: pass
	func set_block_color(_color: Color) -> void: pass
	func set_ammo(_rounds: int,_size: int) -> void: pass
	func set_grenade_cook(_age: float) -> void: pass
	func set_tool_action(_kind: int,_progress: float,_ready: float) -> void: pass
	func set_motion_state(_velocity: Vector3,_walk: float,_turn: Vector3,_offset: Vector3) -> void: pass
	func set_animations_enabled(_enabled: bool) -> void: pass
	func set_simulation_state(values: Dictionary) -> void: blends = values.duplicate()
	func update_pose(_dt: float,_aim: bool,_sprint: bool,_crouch: bool,_speed: float,_reload: float) -> void: poses += 1
	func cancel_reload() -> void: pass
	func reload_completed() -> void: pass
	func reload() -> void: reloads += 1
	func fire() -> void: fires += 1
	func is_changing_tool() -> bool: return changing
	func get_displayed_tool() -> int: return 3 # Deliberately wrong cosmetic gate.
	func get_muzzle_transform() -> Transform3D: return global_transform

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("NETWORK CONTROLLER: "+message)

func release_inputs() -> void:
	for action: String in ACTIONS: Input.action_release(action)

func pump() -> void:
	server.poll()
	for client: CLIENT in clients: client.poll()
	check(server.step_once(),"actual authority fixed step")
	session.update(0)
	for client: CLIENT in clients:
		for event: Dictionary in client.drain_events():
			if client != clients[0]: continue
			if event.get("predicted",false):
				session.ingest_cosmetic(event)
				if player != null: player.apply_network_cosmetic(event)
			elif event.has("type") and event.type not in ["map_installed","chat"]:
				session.ingest_event(event,event.get("predicted_already_played",false))
	await process_frame

func wait_until(predicate: Callable,message: String) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec() < deadline:
		if clients.any(func(client: CLIENT) -> bool: return client.status == "failed"):
			check(false,"replica failure while waiting %s: %s; server %s" % [message,clients[0].last_error,(server as TraceServer).close_reasons]);return
		if predicate.call(): check(true,message);return
		await pump()
	check(false,message+" timed out")

func make_player() -> void:
	world = VoxelWorld.new()
	root.add_child(world)
	check(world.set_map_data(clients[0].data,"Network controller fixture") == OK,"trusted replica map installed")
	world.set_process(false)
	lab = TestLab.new();lab.network_client = clients[0];root.add_child(lab)
	player = PLAYER.new();player.name = "Player"
	var head := Node3D.new();head.name = "Head";player.add_child(head)
	var camera := Camera3D.new();camera.name = "Camera3D";head.add_child(camera)
	var weapons := Node3D.new();weapons.name = "WeaponRoot";camera.add_child(weapons)
	var collision := CollisionShape3D.new();collision.name = "CollisionShape3D";collision.shape = BoxShape3D.new();player.add_child(collision)
	skin = TestSkin.new();weapons.add_child(skin);player._weapon_view = skin
	player.world = world;player.session = session;player.lab = lab;player.controls_enabled = true
	root.add_child(player);player.set_physics_process(false);player.set_process_unhandled_input(false)
	player._physics_process(DT)

func authority_guards() -> void:
	var owner := clients[0].get_owner_state()
	var actor := simulation.get_actor(owner.player_id)
	var server_blocks := simulation.data.blocks.duplicate()
	var client_blocks := clients[0].data.blocks.duplicate()
	var feet := player.global_position
	var pose := player.head.position
	var sequence: int = clients[0].prediction.get_status().last_submitted
	var fire_count := skin.fires
	player._shoot();player._spade(false);player._spade(true);player._build_single();player._build_line();player._begin_block_line()
	player._begin_grenade_cook();player._throw_grenade();player.respawn_at(Vector3(999,999,999));player._clip_motion(500)
	check(not player._place(Vector3i(8,4,8)) and not player._damage_block(Vector3i(8,3,8),1000),"direct build/damage entry points deny local authority")
	check(player.global_position == feet and player.head.position == pose,"direct respawn/clip cannot move network body")
	check(player._pending_cell.x < 0 and player._line_start.x < 0 and player._block_health.is_empty(),"no pending local build or damage cache")
	check(skin.fires == fire_count and clients[0].prediction.get_status().last_submitted == sequence,"authority bypass does not manufacture input/fire animation")
	check(clients[0].get_owner_state().magazine == owner.magazine and clients[0].get_owner_state().health == owner.health and clients[0].get_owner_state().grenades == owner.grenades,"bypass leaves owner prediction inventory/health intact")
	check(actor.magazine == owner.magazine and actor.health == owner.health and actor.score == owner.score,"bypass leaves actual authority resources/health/score intact")
	check(simulation.data.blocks == server_blocks and clients[0].data.blocks == client_blocks,"bypass leaves server and rendered replica terrain intact")
	session.grenade_thrown.emit({"owner_id":clients[1].actor_id,"predicted_already_played":false})
	session.grenade_thrown.emit({"owner_id":clients[0].actor_id,"predicted_already_played":true})
	check(skin.fires == fire_count,"remote/already-predicted confirmed grenade release cannot fire local hand twice")

func aim_and_shared_motion() -> void:
	var client := clients[0]
	var owner := client.get_owner_state()
	player._network_adopt(owner,client,0)
	player.apply_mouse_motion(Vector2(80,-40))
	var yaw := player.rotation.y
	var pitch := player.head.rotation.x
	for i: int in range(8): player._network_adopt(owner.copy(),client,0)
	check(absf(angle_difference(yaw,player.rotation.y)) < .00001 and absf(pitch-player.head.rotation.x) < .00001,"unchanged snapshot does not erase or duplicate accumulated mouse motion")
	var seq: int = client.prediction.get_status().last_submitted
	# A live terrain barrier rejects submission before prediction; retain the
	# UI selection without turning it into a frontend authority change.
	var map_sequence := client.data.map_sequence
	client.data.map_sequence += 1
	session.select_tool(0)
	player._physics_process(DT)
	check(client.prediction.get_status().last_submitted == seq and client.get_owner_state().tool == owner.tool,"terrain barrier prevents input/prediction rather than guessing a map")
	check(session.drain_intent().tool == 0,"blocked selection retained as bounded intent")
	client.data.map_sequence = map_sequence
	Input.action_press("forward");Input.action_press("right")
	player._physics_process(DT)
	var predicted := client.get_owner_state()
	check(client.prediction.get_status().last_submitted == seq+1 and predicted.last_tick == owner.last_tick+1,"one controller physics callback produces exactly one fixed command")
	check(predicted.input_move.length() <= 1.000001 and predicted.input_move == Vector2(1,-1).normalized(),"diagonal movement command normalized")
	check(absf(angle_difference(yaw,predicted.yaw)) < .00001 and absf(predicted.pitch-pitch) < .00001,"mouse angles enter source input unchanged")
	check(player.global_position == predicted.feet() and player.velocity == predicted.motion.native_velocity*32,"physics pose and velocity are exact shared prediction copies")
	check(player._motion != predicted.motion and player._motion.eye_position == predicted.motion.eye_position,"source motion copy is owned and preserves eye/climb state")
	check(absf(player.get_walk_progress()-predicted.walk_progress()) < .000001,"source fractional walking phase retained")
	check(player.get_camera_tool() == predicted.displayed_tool,"native display selection overrides erroneous skin display getter")
	check(player.can_use_tool() == RULES.can_use_tool(predicted),"shared readiness determines permission independently of skin gate")
	skin.changing = true
	check(player.can_use_tool() == RULES.can_use_tool(predicted),"cosmetic skin cannot suppress shared source tool readiness")
	skin.changing = false
	release_inputs()
	await wait_until(func():return client.prediction.get_status().pending == 0,"real server acknowledges controller command")
	await wait_until(func():return client.get_owner_state().tool_raise >= .999,"native tool finishes raising")
	player._physics_process(DT)
	Input.action_press("primary")
	var before := client.get_owner_state()
	var fires_before := skin.fires
	player._physics_process(DT)
	predicted = client.get_owner_state()
	check(predicted.magazine == before.magazine-1 and predicted.last_shot_tick == predicted.last_tick,"real shared rules predict one permitted shot")
	check(absf(angle_difference(player.rotation.y,predicted.yaw)) < .00001 and absf(player.head.rotation.x-predicted.pitch) < .00001,"source recoil applies once with Godot positive pitch sign")
	var recoil_pitch := player.head.rotation.x
	for event: Dictionary in client.drain_events():
		if event.get("predicted",false): session.ingest_cosmetic(event);player.apply_network_cosmetic(event)
	check(skin.fires == fires_before+1,"single predicted fire animation from session signal")
	check(player.head.rotation.x == recoil_pitch,"cosmetic muzzle/casing hook does not apply recoil again")
	check(player._kick == .12,"predicted shot retains camera kick presentation")
	release_inputs()
	await wait_until(func():return client.prediction.get_status().pending == 0,"actual shot acknowledges without repeated animation")
	check(skin.fires == fires_before+1,"matching confirmed shot is suppressed by actual replica effect dedup")
	# All seven source buttons travel in the single command. Weapon ADS hold
	# is explicit here; toggle mode is exercised by ordinary mouse/UI input.
	player.hold_aim_down_sight = true
	for action: String in ["jump","crouch","sprint","sneak","primary","secondary"]: Input.action_press(action)
	session.reload_weapon()
	player._physics_process(DT)
	check(client.get_owner_state().input_buttons == 127,"single fixed command carries exactly seven allowed buttons")
	check(player.crouching == client.get_owner_state().motion.crouch and player.sprinting == client.get_owner_state().sprinting and player.wading == client.get_owner_state().motion.wading,"shared source stance/wade/sprint copied rather than run twice")
	check(client.get_owner_state().reloading and session.is_reloading,"one reload intent starts source shared reload")
	release_inputs()
	player._physics_process(DT)
	check(client.get_owner_state().input_buttons == 0 and session.drain_intent() == SESSION.EMPTY_INTENT,"reload intent edge is drained once")
	await wait_until(func():return client.prediction.get_status().pending == 0,"actual reload/stance commands acknowledged")
	if client.status != "live": return
	check(simulation.get_actor(client.actor_id).reloading,"actual server begins the same source reload")
	var reserve := client.get_owner_state().reserve
	var reload_deadline := client.get_owner_state().reload_deadline_tick
	player._update_view(100)
	check(client.get_owner_state().reserve == reserve and client.get_owner_state().reload_deadline_tick == reload_deadline and session.is_reloading,"large presentation delta cannot finish reload or refill stock")
	await wait_until(func():return not client.get_owner_state().reloading,"source authority completes reload at deadline")
	check(client.get_owner_state().magazine == session.get_weapon_info().clip_size and simulation.get_actor(client.actor_id).magazine == session.magazine,"reload resources come from actual owner snapshot")
	player.hold_aim_down_sight = false

func menu_and_intents() -> void:
	var client := clients[0]
	player.controls_enabled = false
	Input.action_press("primary");Input.action_press("forward");Input.action_press("jump");Input.action_press("crouch")
	var owner := client.get_owner_state()
	var seq: int = client.prediction.get_status().last_submitted
	player._physics_process(DT)
	var next := client.get_owner_state()
	check(next.input_buttons == 0 and next.input_move == Vector2.ZERO and not next.trigger_held,"menu sends neutral input despite held OS actions")
	check(next.health == owner.health and client.prediction.get_status().last_submitted == seq+1,"menu advances source gravity cadence while preserving confirmed life")
	release_inputs();player.controls_enabled = true
	session.select_tool(3)
	player._physics_process(DT)
	check(client.get_owner_state().tool == 3 and session.drain_intent() == SESSION.EMPTY_INTENT,"selection intent consumed exactly once by fixed input")
	await wait_until(func():return client.get_owner_state().tool == 3 and client.get_owner_state().tool_raise >= .999,"actual selected grenade raises")
	player._physics_process(DT)
	Input.action_press("primary");player._physics_process(DT)
	check(client.get_owner_state().cooking and player._grenade_cooking,"grenade cook state comes from shared rules")
	await pump()
	player.controls_enabled = false
	player._physics_process(DT)
	check(client.get_owner_state().release_pending and client.get_owner_state().input_buttons == 0,"menu neutral primary requests source minimum-age grenade release")
	check(simulation.grenades.is_empty(),"predicted release does not directly create server grenade")
	for i: int in range(9):
		await pump()
		player._physics_process(DT)
	check(not client.get_owner_state().cooking and not player._grenade_cooking,"source nine-tick cook minimum completes release in menu")
	release_inputs();player.controls_enabled = true
	await wait_until(func():return not simulation.grenades.is_empty(),"real authority receives cook release and creates projectile")
	# Same wire request path used by eyedropper and palette UI.
	check(session.request_block_color(0x01aabbcc),"queue canonical block color")
	var held_team: int = session.team
	session.select_team(held_team)
	var held_sequence: int = client.prediction.get_status().last_submitted
	var held_request: int = client._request_sequence
	# A valid maintenance event models a partially drained transport batch.
	client.game._emit({"type":"rtt","connection_id":client._game_id,"rtt_ms":1.0})
	player._physics_process(DT)
	check(client.prediction.get_status().last_submitted==held_sequence and client._request_sequence==held_request,"partial authority batch cannot commit input or request cursors")
	check(session._intent.team==held_team and session._intent.color==0x01aabbcc,"unsent menu team/color choice survives authority-stream wait")
	client.game.drain_events()
	player._physics_process(DT)
	check(session._intent.team==-1 and session._intent.color==-1,"fresh stream sends retained menu choice once")
	await wait_until(func():return simulation.snapshot_for(client.actor_id).get("block_colors",{}).get(client.actor_id,0) == 0x01aabbcc,"typed color request reaches actual authority")
	var buttons := InputEventAction.new();buttons.action = "primary";buttons.pressed = true
	player._unhandled_input(buttons)
	check(player._pending_cell.x < 0 and player._line_start.x < 0,"network unhandled input cannot enter offline build/grenade authority")
	# Shared visual blends are read, never integrated a second time by controller.
	var copied := client.get_owner_state()
	player._network_adopt(copied,client,0)
	player._update_view(3)
	check(player.get_aim_down_state() == session.aim_down_state and player._sprint_state == session.sprint_state,"view delta cannot advance source ADS/sprint blends")
	check(skin.blends.tool_raise == session.tool_raise and skin.blends.displayed_tool == session.displayed_tool and skin.blends.aim_down_state == session.aim_down_state,"skin receives complete raw shared readiness blend")

func inactive_and_identity() -> void:
	var client := clients[0]
	session.select_team(2);player._physics_process(DT)
	await wait_until(func():return session.team == 2,"typed team request enters spectator on real authority")
	await wait_until(func():return not client.prediction.get_status().needs_rebase and client.prediction.get_status().pending==0,"spectator mode acknowledges prior input before new class intent")
	player._physics_process(DT)
	var confirmed := client.prediction.get_confirmed_state()
	var seq: int = client.prediction.get_status().last_submitted
	Input.action_press("forward");Input.action_press("primary")
	player._physics_process(DT)
	check(client.prediction.get_status().last_submitted == seq,"inactive spectator movement does not submit owner simulation input")
	check(player.global_position == confirmed.feet() and player._motion.feet_position == confirmed.feet(),"spectator body displays confirmed pose while camera moves locally")
	check(player.camera_mode == PLAYER.CameraMode.FREE and player._free_position.is_finite(),"spectator free camera remains local presentation")
	release_inputs();session.select_weapon(2);player._physics_process(DT)
	check(client.prediction.get_status().last_submitted == seq+1,"inactive class intent sends one neutral command")
	check(client.get_owner_state().input_buttons == 0 and client.get_owner_state().input_move == Vector2.ZERO,"inactive class command carries no gameplay buttons/movement")
	check(player.global_position == confirmed.feet(),"inactive class prediction never moves displayed confirmed body")
	player._physics_process(DT)
	check(client.prediction.get_status().last_submitted == seq+1,"drained class intent is not sent twice")
	await wait_until(func():return simulation.get_actor(client.actor_id).pending_weapon == 2,"inactive pending class reaches authority without refill")
	var previous_generation := confirmed.spawn_generation
	# The pending-class predicate reads authority before its ACK reaches this
	# replica. Actual Main retries retained menu intents every physics frame;
	# this manually driven controller must do so too when the clock/stream waits.
	var request_before: int = client._request_sequence
	session.select_team(0)
	var intent_deadline := Time.get_ticks_msec()+4000
	while session._intent.team != -1 and Time.get_ticks_msec()<intent_deadline:
		player._physics_process(DT)
		if session._intent.team != -1: await pump()
	check(session._intent.team==-1 and client._request_sequence==request_before+1,"retained team intent crosses fresh-stream gate exactly once")
	await wait_until(func():return session.team == 0 and session.spawn_generation > previous_generation,"authority team spawn advances life generation")
	player._physics_process(DT)
	check(player._network_generation == client.get_owner_state().spawn_generation and player.global_position == client.get_owner_state().feet(),"new life adopts authoritative generation/feet without local respawn")
	check(client.get_owner_state().weapon == 2 and session.current_weapon == 2,"pending class applies only to confirmed new spawn")
	confirmed = client.prediction.get_confirmed_state()
	var angle := player.head.rotation.x
	var count := skin.fires
	var event := {"kind":"spade_bash","epoch":client.epoch,"owner_id":client.actor_id+1,"spawn_generation":confirmed.spawn_generation,"tick":confirmed.last_tick}
	player.apply_network_cosmetic(event)
	event.owner_id = client.actor_id;event.epoch += 1;player.apply_network_cosmetic(event)
	event.epoch = client.epoch;event.spawn_generation += 1;player.apply_network_cosmetic(event)
	check(skin.fires == count and player.head.rotation.x == angle,"remote/stale-epoch/stale-generation cosmetics cannot drive local presentation")
	client.close();session.update(0);player._physics_process(DT)
	check(player._network_owner == null and not player.can_use_tool(),"disconnect never falls back into offline playable authority")

func run() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action);new_actions.append(action)
	release_inputs()
	session = SESSION.new();root.add_child(session)
	var data := DATA.new();data.clear(Vector3i(32,16,32),29);data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01607080)
	simulation = MATCH.new();check(simulation.configure(data,"0.76","ctf").ok,"actual source match")
	server = TraceServer.new();check(server.configure(simulation,COMPATIBILITY.build_hash(),COMPATIBILITY.rules_hash()),"actual runtime configured")
	started = server.start();check(started.ok,"actual two-channel listeners")
	for i: int in range(2):
		var client := CLIENT.new();clients.append(client)
		check(client.connect_to("ws://127.0.0.1:%d/play" % started.game_port,"ws://127.0.0.1:%d/map" % started.map_port,"Controller %d" % i).ok,"actual two-client connection")
	session.bind_replica(clients[0])
	await wait_until(func():return clients[0].status == "live" and clients[1].status == "live","actual baseline/state/spawn barriers")
	if clients[0].status != "live" or clients[1].status != "live": finish();return
	make_player()
	await wait_until(func():return clients[0].prediction.get_status().pending == 0,"initial controller input acknowledged")
	# Map installation can take real wall time while this fixture's manually
	# stepped authority is paused. Wait for a current state as actual Main does.
	await wait_until(func():return clients[0]._input_clock.next_tick(Time.get_ticks_usec())>=0 and not clients[0].game.has_pending_incoming(),"installed world reaches fresh authority clock")
	authority_guards()
	await aim_and_shared_motion()
	if clients[0].status != "live": finish();return
	await menu_and_intents()
	if clients[0].status != "live": finish();return
	await inactive_and_identity()
	finish()

func finish() -> void:
	release_inputs()
	for action: String in new_actions: InputMap.erase_action(action)
	for client: CLIENT in clients: client.close()
	if server != null: server.stop()
	if player != null: player.free()
	if world != null: world.free()
	if lab != null: lab.free()
	if session != null: session.free()
	print("NETWORK CONTROLLER: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
