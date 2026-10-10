extends SceneTree
const SESSION = preload("res://network/network_session.gd")
const LOCAL = preload("res://gameplay/local_session.gd")
const CLIENT = preload("res://network/client_replica.gd")
const SERVER = preload("res://network/server_runtime.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const EVENTS = preload("res://network/events_codec.gd")
const COMPATIBILITY = preload("res://network/compatibility.gd")
var assertions := 0
var failures := 0
var server: SERVER
var clients: Array[CLIENT] = []
var session: SESSION
var simulation: MATCH
var started := {}
var event_counter := 1
var signals_seen := {"shot":0,"reload":0,"restock":0,"death":0,"spawn":0,"target_death":0,"target_spawn":0,"throw":0,"explode":0,"won":0,"hurt":0,"log":0}
var last_hurt_origin := Vector3.ZERO
var last_thrown := {}

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("NETWORK SESSION: " + message)

func connect_client() -> CLIENT:
	var client := CLIENT.new()
	check(client.connect_to("ws://127.0.0.1:%d/play" % started.game_port,"ws://127.0.0.1:%d/map" % started.map_port,"Client %d" % (clients.size()+1)).ok,"actual replica connection")
	clients.append(client)
	return client

func pump() -> void:
	server.poll()
	for client: CLIENT in clients: client.poll()
	check(server.step_once(),"one actual authority step")
	session.update(1.0/60)
	await process_frame

func wait_until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await pump()
	check(predicate.call(),message)

func unbound() -> void:
	session = SESSION.new()
	root.add_child(session)
	check(session is LOCAL and session.health == 0 and session.team == 2,"base-compatible adapter starts without fictitious playable authority")
	check(session.local_player_id() == 0 and not session.is_local_intel_carrier(),"unbound identity never claims canonical actor0")
	session.select_weapon(2);session.select_tool(3);session.select_team(0);session.reload_weapon()
	check(session.drain_intent() == SESSION.EMPTY_INTENT,"no selections without initialized owner")
	check(not session.request_block_color(0x01000000),"no color intent without initialized owner")
	session.health = 999;session.magazine = 999;session.unlimited_ammo = true
	session.update(100)
	check(session.health == 0 and session.magazine == 0 and not session.unlimited_ammo,"unbound direct frontend writes are cleared")
	# A future LocalSession authority method must be deliberately audited.
	var overrides := {}
	for method: Dictionary in session.get_script().get_script_method_list(): overrides[method.name] = true
	var local_fixture := LOCAL.new()
	for method: Dictionary in local_fixture.get_script().get_script_method_list():
		if method.name in ["get_team_info","set_team_info"]: continue
		check(overrides.has(method.name),"explicit compatibility/authority override for " + str(method.name))
	local_fixture.free()

func mirror() -> void:
	var client := clients[0]
	var owner := client.get_owner_state()
	var authoritative := simulation.get_actor(client.actor_id)
	check(session.local_player_id() == client.actor_id and session.local_player_id() > 0,"actual positive stable owner ID")
	check(session.health == owner.health and session.magazine == owner.magazine and session.reserve == owner.reserve and session.grenades == owner.grenades and session.blocks == owner.blocks,"owner inventory mirrors complete predicted copy")
	check(session.profile_version == "0.76" and session.mode == "ctf","negotiated authority rules/profile mirrored")
	check(session.tool_raise == owner.tool_raise and session.displayed_tool == owner.displayed_tool and session.displayed_weapon == owner.displayed_weapon and session.aim_down_state == owner.aim_down_state and session.sprint_state == owner.sprint_state,"source readiness/display blends retained")
	check(session.score == owner.score and session.player_kills == owner.kills and session.player_deaths == owner.deaths,"confirmed owner counters mirrored")
	check(session.spawn_generation == owner.spawn_generation and session.input_ack == owner.consumed_input_sequence,"generation/input cursor mirrored")
	var target := session.get_target(clients[1].actor_id)
	check(not target.is_empty() and target.id == clients[1].actor_id and target.alive and target.connected,"public remote target uses stable ID/alive status")
	check(target.health == -1 and not target.health_known and not target.has("magazine") and not target.has("reserve") and not target.has("shot_rng") and not target.has("input_buttons"),"remote HP/resources/RNG/controls never fabricated")
	check(target.has("yaw") and target.has("pitch") and target.has("crouching") and target.has("native_velocity") and target.has("aim_down_state") and target.has("displayed_tool") and target.has("displayed_weapon") and target.has("tool_raise") and target.has("score") and target.visual_only,"full remote presentation fields")
	var expected := client.sample_remote(target.id)
	check(target.position.distance_to(expected.feet) < .05 and target.interpolation_mode == expected.mode,"target pose comes from actual replica interpolation")
	target.health = 100;target.position = Vector3.INF
	check(session.get_target(target.id).health == -1 and session.get_target(target.id).position.is_finite(),"get_target returns an independent presentation copy")
	var time_before := session.session_time
	var server_tick := simulation.tick
	var owner_tick := owner.last_tick
	for i: int in range(10): session.update(50)
	check(simulation.tick == server_tick and client.get_owner_state().last_tick == owner_tick and session.session_time == time_before,"render update never advances local authority/prediction clock")
	check(authoritative.health == owner.health,"mirror does not mutate authority actor")
	check(session.set_team_info(0,"Visual only",Color(.8,.2,.4)),"team name/color remain local presentation preference")
	check(session.get_team_info(0).name == "Visual only" and simulation.profile == "0.76" and simulation.mode == "ctf","visual preferences do not alter match rules")

func intents_and_denials() -> void:
	var client := clients[0]
	var owner := client.get_owner_state()
	var original := simulation.snapshot_for(client.actor_id)
	var cells: PackedInt32Array = simulation.data.blocks.duplicate()
	session.select_weapon(2);session.select_tool(0);session.reload_weapon();session.select_team(1)
	check(session.request_block_color(0x01010203),"canonical packed solid color request")
	check(not session.request_block_color(0) and not session.request_block_color(0xffffffff),"invalid color does not replace valid pending intent")
	check(session.current_weapon == owner.weapon and session.current_tool == owner.tool and not session.is_reloading and session.team == owner.team,"selection/reload/team are intents without immediate state mutation")
	check(session.drain_intent() == {"tool":0,"weapon":2,"reload":true,"team":1,"color":0x01010203},"root consumes exactly one bounded typed intent record")
	check(session.drain_intent() == SESSION.EMPTY_INTENT,"intent drain clears once")
	for i: int in range(1024): session.select_weapon(i%3);session.select_tool(i%4);session.reload_weapon()
	var pending := session.drain_intent()
	check(pending.size() == 5 and pending.weapon == 0 and pending.tool == 3 and pending.reload,"latest-value intent storage remains bounded after 1024 requests")
	session.select_weapon(-1);session.select_weapon(3);session.select_tool(-1);session.select_tool(4);session.select_team(-1);session.select_team(3)
	check(session.drain_intent() == SESSION.EMPTY_INTENT,"out-of-range selections ignored")
	check(not session.fire() and not session.use_block(5) and not session.begin_grenade_cook() and session.release_grenade().is_empty() and not session.use_grenade(),"offline shot/build/cook/throw authority denied")
	check(session.damage_target(clients[1].actor_id,"head",1) == 0 and session.apply_target_damage(clients[1].actor_id,1000) == 0 and session.compute_damage("head",1) == 0,"frontend target damage cannot award confirmed hits")
	check(session.add_target(Vector3.ONE) == -1,"frontend cannot spawn an authority actor")
	session.damage_player(10000);session.respawn();session.restock();session.recover_block();session.add_score(10000)
	session.apply_grenade_damage(Vector3.ZERO);session.set_grenade_position(1,Vector3.INF)
	session.remove_target(clients[1].actor_id);session.set_target_state(clients[1].actor_id,"dead")
	session.configure_ctf(Vector3.ZERO,Vector3.ONE,1);session.configure_tc([Vector3.ZERO]);session.set_mode("sandbox");session.set_profile_version("0.75");session.reset_lab()
	session.set_trigger_held(true);session.end_reload();session.update_player_position(Vector3.INF)
	for function: String in ["_cancel_selection_actions","_update_reload","_update_grenades","_update_targets","_reset_objectives","_update_objectives","_update_ctf","_drop_carried_intel","_update_tc"]:
		if function in ["_update_reload","_update_grenades","_update_targets","_update_objectives","_update_tc"]: session.call(function,1000)
		else: session.call(function)
	session._event("kill",{"target_id":clients[1].actor_id})
	check(client.get_owner_state().health == owner.health and client.get_owner_state().magazine == owner.magazine and client.get_owner_state().reserve == owner.reserve and client.get_owner_state().grenades == owner.grenades and client.get_owner_state().blocks == owner.blocks and client.get_owner_state().score == owner.score,"all denial calls leave predictor inventory/HP/score unchanged")
	check(simulation.get_actor(client.actor_id).health == original.owner_state.health and simulation.get_actor(client.actor_id).magazine == original.owner_state.magazine and simulation.get_actor(client.actor_id).reserve == original.owner_state.reserve and simulation.get_actor(client.actor_id).blocks == original.owner_state.blocks and simulation.get_actor(client.actor_id).grenades == original.owner_state.grenades and simulation.get_actor(client.actor_id).score == original.owner_state.score,"all denial calls leave real server inventory/HP/score unchanged")
	check(simulation.data.blocks == cells and simulation.data.map_sequence == original.map_sequence and simulation.mode == original.mode and simulation.profile == original.profile,"all denial calls leave real server map/match configuration unchanged")
	check(session.event_log.is_empty() and session.hits_landed == 0,"offline injection cannot write confirmed log or hit counters")
	session.health = 999;session.magazine = 999;session.reserve = 999;session.grenades = 999;session.blocks = 999;session.score = 999
	session.unlimited_ammo = true;session.invulnerable = true;session.profile_version = "bad";session.current_weapon = 99
	session.targets[0].health = 100;session.targets[0].score = 999;session.targets[0].position = Vector3.INF
	check(session.get_weapon_info().profile == owner.profile and session.get_weapon_info().weapon_index == owner.weapon,"weapon query reads approved owner copy despite frontend scalar spoofing")
	session.update(0)
	check(session.health == owner.health and session.magazine == owner.magazine and session.reserve == owner.reserve and session.grenades == owner.grenades and session.blocks == owner.blocks and session.score == owner.score and not session.unlimited_ammo and not session.invulnerable,"direct frontend scalar writes overwritten without granting cheats")
	check(session.get_target(clients[1].actor_id).health == -1 and session.get_target(clients[1].actor_id).score != 999 and session.get_target(clients[1].actor_id).position.is_finite(),"direct dictionary edits affect only presentation copies")

func actual_rules_and_objectives() -> void:
	var client := clients[0]
	var owner := simulation.get_actor(client.actor_id)
	for i: int in range(6):
		check(client.submit_input(0,Vector2(.6,-.8),.1,.05).ok,"actual root submits fixed input separately")
		await pump()
	await wait_until(func():return client.prediction.get_status().input_ack == 6,"actual prediction acknowledged")
	session.update(0)
	check(session.input_ack == 6 and session.player_position == client.get_owner_state().feet(),"adapter displays actual owned prediction/reconciliation")
	owner.magazine = 2
	owner.tool_raise = 1
	check(not RULES.begin_reload(owner,simulation.tick).is_empty(),"source authority starts reload fixture")
	await wait_until(func():return session.is_reloading,"confirmed reload reaches view")
	var view := client.get_owner_state()
	check(session.get_reload_progress() == RULES.reload_progress(view,view.last_tick),"reload progress uses source owner deadline/tick")
	var remaining := session.reload_remaining
	session.update(500)
	check(session.reload_remaining == remaining and session.is_reloading,"presentation delta never finishes authority reload/refills stock")
	RULES.cancel_actions(owner)
	owner.tool = 3;owner.displayed_tool = 3;owner.tool_raise = 1
	check(not RULES.begin_cook(owner,simulation.tick).is_empty(),"source authority starts held grenade fixture")
	await wait_until(func():return session.is_cooking_grenade,"confirmed cook reaches view")
	var cook_age := session.grenade_cook_time
	var inventory := owner.grenades
	session.update(500)
	check(session.grenade_cook_time == cook_age and owner.grenades == inventory and simulation.grenades.is_empty(),"presentation delta cannot auto-release/create an authoritative grenade")
	RULES.cancel_actions(owner)
	owner.motion.feet_position = Vector3(16,4.01,16)
	owner.motion.eye_position = owner.feet()
	var enemy_team := 1-owner.team
	simulation.objectives.flags[enemy_team].carrier = owner.player_id
	simulation.objectives.flags[enemy_team].at_base = false
	simulation.objectives.flags[enemy_team].position = owner.feet()
	await wait_until(func():return session.is_local_intel_carrier(),"positive canonical CTF carrier reaches view")
	check(session.ctf_flags[enemy_team].carrier == client.actor_id and session.ctf_flags[enemy_team].carrier != 0,"network view never rewrites canonical carrier into actor0")
	var objectives_before := simulation.objectives.snapshot()
	session.update(500);session.configure_ctf(Vector3.ZERO,Vector3.ONE);session._drop_carried_intel();session.set_mode("sandbox")
	check(simulation.objectives.snapshot() == objectives_before,"CTF update/config/drop APIs cannot change authority objectives")
	var grenade := preload("res://simulation/grenade_rules.gd").create(500,owner.player_id,owner.spawn_generation,simulation.epoch,simulation.tick,Vector3(16,8,16),Vector3(1,2,3),2)
	simulation.grenades[500] = grenade
	simulation._grenade_team[500] = owner.team
	await wait_until(func():return not session.live_grenades.is_empty(),"confirmed public projectile snapshot reaches view")
	check(session.live_grenades[0].visual_only and session.live_grenades[0].id == 500 and session.live_grenades[0].has("orientation"),"projectile records are snapshot-only visuals")
	var position_before := grenade.position
	var fuse_before: float = session.live_grenades[0].fuse
	session.set_grenade_position(500,Vector3.INF);session.update(500)
	check(grenade.position == position_before and session.live_grenades[0].fuse == fuse_before,"legacy grenade visual update cannot move/expire authority projectile")

func wire_event(owner_id: int, kind: String, details: Dictionary = {}) -> Dictionary:
	var generation := simulation.get_actor(owner_id).spawn_generation if owner_id > 0 else 0
	var id := "%d:%d:%d:%d" % [simulation.epoch,owner_id,generation,event_counter]
	if kind in EVENTS.OBJECTIVE_TYPES: id = "%d:o:%d" % [simulation.epoch,event_counter]
	elif kind in EVENTS.GRENADE_TYPES: id = "%d:g:%d:%d" % [simulation.epoch,details.grenade_id,event_counter]
	var event := {"type":kind,"epoch":simulation.epoch,"tick":simulation.tick,"owner_id":owner_id,"spawn_generation":generation,"action_sequence":0,"match_sequence":event_counter,"event_id":id}
	event.merge(details)
	event_counter += 1
	var encoded := EVENTS.encode({"epoch":simulation.epoch,"first_sequence":event.match_sequence,"last_sequence":event.match_sequence,"events":[event]})
	check(encoded.ok,"typed event fixture " + kind + ": " + encoded.error)
	if not encoded.ok: return {}
	var decoded := EVENTS.decode(encoded.bytes)
	check(decoded.ok,"typed event wire decoded " + kind)
	return decoded.payload.events[0]

func hook_events() -> void:
	session.shot_fired.connect(func():signals_seen.shot += 1)
	session.reloaded.connect(func():signals_seen.reload += 1)
	session.restocked.connect(func():signals_seen.restock += 1)
	session.player_died.connect(func():signals_seen.death += 1)
	session.player_respawned.connect(func():signals_seen.spawn += 1)
	session.target_died.connect(func(_id: int):signals_seen.target_death += 1)
	session.target_respawned.connect(func(_id: int):signals_seen.target_spawn += 1)
	session.grenade_thrown.connect(func(value: Dictionary):signals_seen.throw += 1;last_thrown = value)
	session.grenade_exploded.connect(func(_value: Dictionary):signals_seen.explode += 1)
	session.round_won.connect(func(_team: int):signals_seen.won += 1)
	session.player_hurt.connect(func(_amount: float, origin: Vector3, _cause: String):signals_seen.hurt += 1;last_hurt_origin = origin)
	session.match_event.connect(func(_event: Dictionary):signals_seen.log += 1)
	var id: int = clients[0].actor_id
	var other: int = clients[1].actor_id
	var owner := clients[0].get_owner_state()
	var cosmetic := {"kind":"shot","predicted":true,"epoch":owner.match_epoch,"owner_id":id,"spawn_generation":owner.spawn_generation,"tick":owner.last_tick,"input_sequence":owner.consumed_input_sequence,"effect_key":"private-cosmetic"}
	check(session.ingest_cosmetic(cosmetic) and signals_seen.shot == 1 and session.shots_fired == 0 and session.event_log.is_empty(),"predicted shot cue emits once without confirmed stats/log")
	var shot := wire_event(id,"shot",{"weapon":1,"profile":owner.profile,"origin":owner.motion.physics_eye(),"directions":[Vector3.FORWARD]})
	check(session.ingest_event(shot,true) and signals_seen.shot == 1 and session.shots_fired == 1,"confirmed predicted shot updates confirmed counters without repeating animation signal")
	check(session.ingest_event(wire_event(id,"shot",{"weapon":0,"profile":owner.profile,"origin":owner.motion.physics_eye(),"directions":[Vector3.FORWARD]})) and signals_seen.shot == 2,"unpredicted confirmed shot emits its animation cue")
	check(session.ingest_event(wire_event(other,"shot",{"weapon":0,"profile":owner.profile,"origin":owner.motion.physics_eye(),"directions":[Vector3.FORWARD]})) and signals_seen.shot == 2 and session.shots_fired == 2,"remote shot does not drive local weapon signal/counters")
	var reload_cosmetic := cosmetic.duplicate();reload_cosmetic.kind = "reload_completed"
	check(session.ingest_cosmetic(reload_cosmetic) and signals_seen.reload == 1,"predicted reload animation cue")
	check(session.ingest_event(wire_event(id,"reload_completed"),true) and signals_seen.reload == 1,"confirmed reload suppresses already-played cue")
	check(session.ingest_event(wire_event(id,"restock")) and signals_seen.restock == 1,"confirmed restock signal only")
	var health_before := simulation.get_actor(id).health
	var score_before := simulation.get_actor(id).score
	var resources_before := clients[0].get_owner_state()
	check(session.ingest_event(wire_event(id,"hurt",{"amount":20,"attacker_id":other,"cause":"weapon","action_id":shot.event_id})) and signals_seen.hurt == 1 and last_hurt_origin == Vector3.INF,"hurt missing source origin stays nondirectional")
	check(session.ingest_event(wire_event(id,"death",{"attacker_id":other,"cause":"grenade","action_id":""})) and signals_seen.death == 1 and session.last_death_kind == "grenade","confirmed death metadata/signal")
	check(session.ingest_event(wire_event(id,"spawn",{"feet":owner.feet(),"team":owner.team,"weapon":owner.weapon})) and signals_seen.spawn == 1,"confirmed spawn signal does not refill authority")
	check(session.ingest_event(wire_event(other,"death",{"attacker_id":id,"cause":"weapon","action_id":shot.event_id})) and signals_seen.target_death == 1,"remote death signal retains canonical ID")
	check(session.ingest_event(wire_event(other,"spawn",{"feet":clients[1].get_owner_state().feet(),"team":clients[1].get_owner_state().team,"weapon":0})) and signals_seen.target_spawn == 1,"remote spawn signal")
	check(session.ingest_event(wire_event(id,"hit_confirmed",{"victim_id":other,"part":"head","damage":20,"position":Vector3(20,5,20),"friendly":false,"source_event_id":shot.event_id,"pellet":0})) and session.hits_landed == 1 and session.last_damage == 20 and session.last_hit_part == "head","only confirmed hit updates hit counters")
	check(session.ingest_event(wire_event(id,"kill_credit",{"victim_id":other,"victim_generation":clients[1].get_owner_state().spawn_generation,"cause":"weapon","source_event_id":shot.event_id})),"kill credit adapted for existing feed")
	check(session.event_log.back().type == "kill" and session.event_log.back().target_id == other and session.event_log.back().weapon_known and session.event_log.back().weapon == 1,"kill weapon comes from actual confirmed source event")
	check(session.ingest_event(wire_event(id,"kill_credit",{"victim_id":other,"victim_generation":clients[1].get_owner_state().spawn_generation,"cause":"weapon","source_event_id":"unknown_source"})) and not session.event_log.back().weapon_known and not session.event_log.back().has("weapon"),"missing source event never invents a Rifle kill")
	var release_cosmetic := cosmetic.duplicate();release_cosmetic.kind = "grenade_release"
	check(session.ingest_cosmetic(release_cosmetic) and signals_seen.throw == 0 and session.live_grenades.size() == 1,"predicted release cannot create authoritative projectile position")
	check(session.ingest_event(wire_event(id,"grenade_thrown",{"position":Vector3(20,6,20),"native_velocity":Vector3(1,.1,0),"fuse":2.2,"cook_time":.8,"drop":false,"team":owner.team,"cook_action_sequence":1,"automatic":false}),true) and signals_seen.throw == 1 and last_thrown.visual_only and last_thrown.predicted_already_played,"confirmed throw carries real position even when local hand animation already played")
	check(session.ingest_event(wire_event(id,"grenade_exploded",{"grenade_id":500,"position":Vector3(20,6,20)})) and signals_seen.explode == 1,"confirmed explosion signal remains visual only")
	check(session.ingest_event(wire_event(0,"round_won",{"team":owner.team,"winning_team":owner.team,"mode":"ctf"})) and signals_seen.won == 1,"confirmed objective signal")
	check(simulation.get_actor(id).health == health_before and simulation.get_actor(id).score == score_before and clients[0].get_owner_state().health == resources_before.health and clients[0].get_owner_state().magazine == resources_before.magazine and clients[0].get_owner_state().grenades == resources_before.grenades,"all event hooks leave real authority/prediction resources unchanged")
	var wrong := cosmetic.duplicate();wrong.owner_id = other
	check(not session.ingest_cosmetic(wrong),"remote cosmetic cannot drive local weapon")
	wrong = cosmetic.duplicate();wrong.epoch += 1
	check(not session.ingest_cosmetic(wrong),"wrong epoch cosmetic ignored")
	wrong = cosmetic.duplicate();wrong.spawn_generation -= 1
	check(not session.ingest_cosmetic(wrong),"stale generation cosmetic ignored")
	var stale := shot.duplicate();stale.epoch += 1
	check(not session.ingest_event(stale),"wrong epoch confirmed event ignored")
	stale = shot.duplicate();stale.spawn_generation -= 1
	check(not session.ingest_event(stale),"stale actor generation event ignored")
	check(not session.ingest_event({"type":"hurt","epoch":owner.match_epoch,"tick":owner.last_tick,"owner_id":id,"spawn_generation":owner.spawn_generation}),"missing validated event fields safely rejected")
	for i: int in range(140): session.ingest_event(wire_event(id,"reload_started",{"weapon":owner.weapon}))
	check(session.event_log.size() == 128,"presentation event log bounded to 128")
	var external: Dictionary = session.event_log.back().duplicate(true)
	external.name = "changed"
	check(session.event_log.back().name != "changed","log record data is independently owned")

func run() -> void:
	unbound()
	var data := DATA.new()
	data.clear(Vector3i(32,16,32),19)
	data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01607080)
	simulation = MATCH.new()
	check(simulation.configure(data,"0.76","ctf").ok,"actual server map/profile/mode")
	server = SERVER.new()
	check(server.configure(simulation,COMPATIBILITY.build_hash(),COMPATIBILITY.rules_hash()),"actual runtime configured")
	started = server.start()
	check(started.ok,"actual server listeners")
	var first := connect_client()
	var second := connect_client()
	session.bind_replica(first)
	await wait_until(func():return first.status == "live" and second.status == "live","actual replicas finish map/state barriers")
	if first.status != "live" or second.status != "live":
		check(false,"replica errors: %s / %s" % [first.last_error,second.last_error]);finish();return
	session.update(0)
	mirror()
	intents_and_denials()
	await actual_rules_and_objectives()
	hook_events()
	session.select_tool(0);first.close();session.update(0)
	check(session.health == 0 and session.team == 2 and session.targets.is_empty() and session.live_grenades.is_empty() and session.drain_intent() == SESSION.EMPTY_INTENT,"disconnect clears playable view/projectiles/intents without offline respawn")
	session.bind_replica(second)
	check(session.local_player_id() == second.actor_id and session.health == second.get_owner_state().health and session.event_log.is_empty(),"explicit binding adopts new stable owner and clears old presentation log")
	session.bind_replica(null)
	check(session.local_player_id() == 0 and session.health == 0 and not session.can_fire(),"unbind restores neutral presentation view")
	finish()

func finish() -> void:
	for client: CLIENT in clients: client.close()
	if server != null: server.stop()
	if session != null: session.free()
	print("NETWORK SESSION: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
