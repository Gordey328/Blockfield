extends SceneTree

const PREDICTION = preload("res://network/client_prediction.gd")
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const DATA = preload("res://world/voxel_data.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("CLIENT PREDICTION: " + message)

func near(actual: float, expected: float, message: String, tolerance: float = 0.00002) -> void:
	check(absf(actual-expected) < tolerance,message + ": %f != %f" % [actual,expected])

func map_data(epoch: int = 7) -> DATA:
	var value := DATA.new()
	value.clear(Vector3i(64,32,64),epoch)
	value.seed_box(Vector3i.ZERO,Vector3i(64,4,64),0x01446688)
	return value

func actor(weapon: int = 1, epoch: int = 7, seed_value: int = 99) -> STATE:
	var value := STATE.new(5,"Owner",epoch,"0.75",seed_value)
	RULES.spawn(value,0,Vector3(20.5,4.01,20.5),0,weapon)
	value.tool_raise = 1.0
	value.last_tick = 0
	return value

func command(sequence: int, generation: int = 1, move: Vector2 = Vector2.ZERO, buttons: int = 0) -> RULES.Command:
	var value := RULES.Command.new()
	value.sequence = sequence
	value.spawn_generation = generation
	value.move = move
	value.buttons = buttons
	return value

func same_rules(actual: STATE, expected: STATE, label: String) -> void:
	check(actual.feet().distance_to(expected.feet()) < 0.00002 and actual.motion.native_velocity.distance_to(expected.motion.native_velocity) < 0.000002,label + " fixed source motion")
	check(actual.motion.crouch == expected.motion.crouch and actual.motion.grounded == expected.motion.grounded and actual.motion.wading == expected.motion.wading,label + " source motion flags")
	check(actual.magazine == expected.magazine and actual.reserve == expected.reserve and actual.grenades == expected.grenades and actual.blocks == expected.blocks,label + " private resources")
	check(actual.next_shot_tick == expected.next_shot_tick and actual.reload_deadline_tick == expected.reload_deadline_tick and actual.cook_started_tick == expected.cook_started_tick and actual.grenade_deadline_tick == expected.grenade_deadline_tick,label + " fractional cooldown/reload/cook replay")
	check(absf(actual.yaw-expected.yaw) < 0.000002 and absf(actual.pitch-expected.pitch) < 0.000002 and actual.tool_raise == expected.tool_raise and actual.sprint_state == expected.sprint_state and actual.aim_down_state == expected.aim_down_state,label + " source recoil/readiness/pose")

func trace_checks() -> void:
	var query := map_data()
	var server := actor()
	var initial := server.copy()
	var predictor := PREDICTION.new()
	check(predictor.reset(initial,0,0).ok,"trusted owner reset")
	initial.magazine = 0
	initial.motion.feet_position += Vector3(8,0,0)
	check(predictor.get_state().magazine == 30 and predictor.get_state().feet() == Vector3(20.5,4.01,20.5),"reset owns motion/value copy rather than transport pointer")
	check(predictor.get_state().shot_rng.seed == PREDICTION.PRIVATE_COSMETIC_SEED and predictor.get_state().shot_rng.seed != server.shot_rng.seed,"server shot RNG seed is stripped")
	var cosmetic_count := 0
	for tick: int in range(1,181):
		var move := Vector2(0,-1) if tick < 65 else Vector2(0.5,0)
		var buttons := 0
		if tick >= 25 and tick < 65: buttons |= RULES.Buttons.SPRINT
		if tick == 70: buttons |= RULES.Buttons.JUMP
		if tick >= 95 and tick < 115: buttons |= RULES.Buttons.CROUCH
		if tick >= 130 and tick < 165: buttons |= RULES.Buttons.PRIMARY
		if tick == 170: buttons |= RULES.Buttons.RELOAD
		var input := command(tick,1,move,buttons)
		input.yaw = sin(float(tick)*0.05)*0.1
		input.pitch = 0.05
		RULES.step_fixed(server,tick,input,query)
		var predicted: Dictionary = predictor.predict(input,query)
		check(predicted.ok,"fixed trace command accepted %d" % tick)
		cosmetic_count += predicted.events.size()
		for event: Dictionary in predicted.events:
			check(event.is_read_only() and event.predicted and not event.has("type") and not event.has("directions") and not event.has("origin") and not event.has("event_id"),"predicted effects never expose authority events/pellets/world origin")
		if tick%15 == 0:
			same_rules(predictor.get_state(),server,"trace%d" % tick)
			var reconciled: Dictionary = predictor.reconcile(server.copy(),tick,0,query)
			check(reconciled.ok and reconciled.replayed == 0 and reconciled.events.is_empty(),"fully acknowledged trace emits no replay effects")
	check(cosmetic_count > 0,"live prediction exposes own pose/recoil cues")
	check(predictor.get_status().pending == 0 and predictor.get_status().input_ack == 180,"acknowledged history released")
	check(server.shot_rng.seed == 99,"prediction never modifies server RNG")
	var external := predictor.get_state()
	external.motion.feet_position = Vector3.ZERO
	check(predictor.get_state().feet() != Vector3.ZERO,"read view owns its motion state")

func reconciliation_checks() -> void:
	var query := map_data()
	var server := actor()
	var predictor := PREDICTION.new()
	predictor.reset(server,0,0)
	var inputs: Array[RULES.Command] = []
	for tick: int in range(1,21):
		var input := command(tick,1,Vector2.RIGHT,RULES.Buttons.PRIMARY)
		inputs.append(input)
		predictor.predict(input,query)
		if tick <= 8: RULES.step_fixed(server,tick,input,query)
	var old_visual: Vector3 = predictor.sample_local_presentation().feet
	server.motion.feet_position.x += 0.25
	server.motion.eye_position.x += 0.25
	server.health = 73
	server.kills = 4
	server.deaths = 2
	server.score = 101
	server.event_sequence = 99
	server.magazine = 11
	var oracle := server.copy()
	for tick: int in range(9,21): RULES.step_fixed(oracle,tick,inputs[tick-1],query,null,false)
	# Commands are owned; modifying the caller's command after enqueue must not
	# change reconciliation or weapon edges retained for the fixed trace.
	inputs[10].move = Vector2.LEFT
	inputs[10].buttons = 0
	var result: Dictionary = predictor.reconcile(server.copy(),8,0,query)
	check(result.ok and result.replayed == 12 and result.events.is_empty(),"late snapshot replays only twelve unacked commands without effects")
	same_rules(predictor.get_state(),oracle,"late corrected replay")
	var replayed := predictor.get_state()
	check(replayed.health == 73 and replayed.kills == 4 and replayed.deaths == 2 and replayed.score == 101 and replayed.event_sequence == 99,"replay retains server health/score/kill/event authority")
	check(predictor.get_confirmed_state().consumed_input_sequence == 8 and predictor.get_status().input_ack == 8 and replayed.consumed_input_sequence == 20,"confirmed ack separated from replayed predicted consumption")
	check(predictor.sample_local_presentation().feet.distance_to(old_visual) < 0.00002,"small visual correction retains old rendered position")
	check(replayed.feet().distance_to(old_visual) > 0.20,"physics uses immediate corrected/replayed position")
	var correction: Vector3 = predictor.get_status().correction
	predictor.sample_local_presentation(0.08)
	check(predictor.get_status().correction.distance_to(correction*exp(-1.0)) < 0.000002,"render correction decays independently by source-independent authored80ms response")
	check(predictor.get_state().feet() == replayed.feet(),"render smoothing never moves physics")
	var before: Dictionary = predictor.get_status()
	check(not predictor.reconcile(server.copy(),8,0,query).ok and predictor.get_status() == before,"duplicate snapshot ignored without poisoning status")
	var pending: Array[RULES.Command] = predictor.get_pending_commands()
	pending[0].move = Vector2.LEFT
	check(predictor.get_pending_commands()[0].move == Vector2.RIGHT,"pending transport command copies cannot mutate replay history")
	var caught_up := oracle.copy()
	caught_up.motion.feet_position.x += 6
	caught_up.motion.eye_position.x += 6
	result = predictor.reconcile(caught_up,20,0,query)
	check(result.ok and predictor.get_status().pending == 0 and predictor.get_status().correction == Vector3.ZERO and predictor.sample_local_presentation().feet == caught_up.feet(),"large correction snaps rendering and retires history")
	var wrong_ack := caught_up.copy()
	wrong_ack.last_tick = 21
	wrong_ack.consumed_input_sequence = 99
	check(not predictor.reconcile(wrong_ack,21,0,query).ok and predictor.get_status().needs_rebase,"unknown acknowledgement requests explicit input rebase")
	check(predictor.get_state().feet() == caught_up.feet(),"failed reconciliation retains predicted state")

func authority_and_terrain_checks() -> void:
	var query := map_data()
	var server := actor(2,7,123456)
	server.motion.feet_position = Vector3(20.5,4.05,20.5)
	server.motion.eye_position = server.motion.physics_eye()
	server.motion.native_velocity = Vector3(0,-0.9,0)
	server.motion.grounded = false
	server.health = 5
	server.tool = RULES.Tool.GRENADE
	server.displayed_tool = RULES.Tool.GRENADE
	server.cooking = true
	server.cook_started_tick = 0
	server.cook_action_sequence = 1
	server.input_buttons = RULES.Buttons.PRIMARY
	server.previous_buttons = RULES.Buttons.PRIMARY
	var predictor := PREDICTION.new()
	predictor.reset(server,0,0)
	var result: Dictionary = predictor.predict(command(1,1,Vector2.ZERO,RULES.Buttons.PRIMARY),query)
	var value := predictor.get_state()
	check(result.ok and value.motion.fall_hurt and value.health == 5 and value.deaths == 0,"predicted hard landing never causes fall damage/death")
	check(value.grenades == 3 and value.cooking,"predicted fall cannot force a grenade death drop or resource use")
	for event: Dictionary in result.events:
		check(event.kind not in ["hurt","death","grenade_release"],"no damage/death/drop effect leaks from prediction")
	var before: STATE = predictor.get_state()
	query.set_block(Vector3i(50,4,50),0x01abcdef)
	check(not predictor.predict(command(2),query).ok and predictor.get_status().map_sync and predictor.get_state().feet() == before.feet(),"prediction waits for exact confirmed terrain sequence")
	var newer := server.copy()
	newer.last_tick = 2
	check(not predictor.reconcile(newer,2,0,query).ok and predictor.get_status().map_sync,"snapshot terrain not available is explicit map sync")
	check(not predictor.reconcile(newer,2,1,query).ok and predictor.get_status().needs_rebase,"pending inputs on missing historical terrain request rebase instead of speculative map replay")
	check(predictor.reset(newer,2,1).ok and predictor.get_status().pending == 0,"coordinator can explicitly rebase after trusted fresh barrier")
	check(predictor.predict(command(1),query).ok,"fresh input timeline resumes against new map barrier")
	var not_finite := newer.copy()
	not_finite.next_shot_tick = NAN
	check(not predictor.reset(not_finite,2,1).ok,"nonfinite replay deadline rejected")
	var mismatched := newer.copy()
	mismatched.last_tick = 3
	check(not predictor.reset(mismatched,2,1).ok,"header tick must describe actual complete owner state")
	var shot_a := actor(2,7,999)
	var shot_b := actor(2,7,888888)
	var first := PREDICTION.new()
	var second := PREDICTION.new()
	first.reset(shot_a,0,1)
	second.reset(shot_b,0,1)
	var event_a: Dictionary = first.predict(command(1,1,Vector2.ZERO,RULES.Buttons.PRIMARY),query)
	var event_b: Dictionary = second.predict(command(1,1,Vector2.ZERO,RULES.Buttons.PRIMARY),query)
	check(event_a.events == event_b.events and first.get_state().pitch == second.get_state().pitch,"different hidden server pellet seeds have identical predicted recoil/resources/cosmetics")

func reset_and_budget_checks() -> void:
	var query := map_data()
	var server := actor()
	var predictor := PREDICTION.new()
	predictor.reset(server,0,0)
	check(not predictor.predict(command(2),query).ok and predictor.get_status().pending == 0,"gapped local input rejected")
	check(not predictor.predict(command(1,2),query).ok,"stale/future generation local input rejected")
	for sequence: int in range(1,257):
		check(predictor.predict(command(sequence),query).ok,"bounded history command %d" % sequence)
	var state := predictor.get_state()
	check(not predictor.predict(command(257),query).ok and predictor.get_status().needs_rebase and predictor.get_status().pending == 256 and predictor.get_state().last_tick == state.last_tick,"history cap stops prediction without dropping unacked commands or granting catch-up steps")
	RULES.spawn(server,10,Vector3(30.5,4.01,30.5),1,2)
	server.last_tick = 10
	check(predictor.reconcile(server.copy(),10,0,query).ok and predictor.get_status().pending == 0 and predictor.get_state().spawn_generation == 2,"respawn resets incompatible history and visual correction")
	check(predictor.predict(command(1,2),query).ok,"new generation restarts explicit input sequence")
	var stale := actor()
	stale.last_tick = 100
	var status := predictor.get_status()
	check(not predictor.reconcile(stale,100,0,query).ok and predictor.get_status() == status,"old generation ignored without status/history mutation")
	query.clear(query.dimensions,8)
	query.seed_box(Vector3i.ZERO,Vector3i(64,4,64),0x01446688)
	var fresh_epoch := actor(1,8)
	check(predictor.reconcile(fresh_epoch,0,0,query).ok and predictor.get_state().match_epoch == 8 and predictor.get_status().pending == 0,"new epoch resets tick/history even with server clock restart")
	status = predictor.get_status()
	check(not predictor.reconcile(stale,100,0,query).ok and predictor.get_status() == status and not predictor.get_status().map_sync,"old epoch ignored before terrain guard, cannot poison new prediction")
	check(predictor.predict(command(1),query).ok,"new match accepts fresh input")
	var dead := fresh_epoch.copy()
	dead.last_tick = 1
	dead.health = 0
	dead.deaths = 1
	check(predictor.reconcile(dead,1,0,query).ok and predictor.get_status().pending == 0 and predictor.get_state().health == 0,"confirmed death resets outstanding prediction")
	status = predictor.get_status()
	check(not predictor.reconcile(fresh_epoch,0,0,query).ok and predictor.get_state().health == 0 and predictor.get_status() == status,"stale alive snapshot cannot resurrect confirmed death")
	var team_change := dead.copy()
	team_change.last_tick = 2
	team_change.team = 2
	check(predictor.reconcile(team_change,2,0,query).ok and predictor.get_state().team == 2,"trusted team/spectator switch resets prediction")
	var overflow := actor(1,8)
	overflow.last_tick = 0xffffffff
	predictor.reset(overflow,0xffffffff,0)
	check(not predictor.predict(command(1),query).ok and predictor.get_status().needs_rebase,"u32 fixed tick exhaustion requests rebase")

func pose(tick: int, feet: Vector3, yaw: float = 0.0, generation: int = 1) -> Dictionary:
	return {"id":9,"spawn_generation":generation,"team":0,"flags":1|16|32,"tool":2,"weapon":1,"name":"Remote","feet":feet,"native_velocity":Vector3(0.1,0,0),"yaw":yaw,"pitch":0.0,"secret_seed":9876,"health":99,"fixture_tick":tick}

func remote_checks() -> void:
	var remote := PREDICTION.RemotePoseBuffer.new()
	check(remote.sample(1).is_empty(),"no remote samples gives no pose")
	var earlier := pose(10,Vector3(10,4,10),deg_to_rad(179))
	var later := pose(20,Vector3(20,4,10),deg_to_rad(-179))
	later.flags = 2|32
	later.tool = 0
	check(remote.push(earlier,7,10).ok and remote.push(later,7,20).ok,"ordered public poses accepted")
	earlier.feet = Vector3.ZERO
	var sampled: Dictionary = remote.sample(21) #100ms delay =>target15.
	check(sampled.feet == Vector3(15,4,10) and sampled.mode == "interpolated","default100ms remote position interpolation")
	near(absf(sampled.yaw),PI,"remote yaw takes shortest 2-degree crossing")
	check(sampled.flags == 1|16|32 and sampled.tool == 2,"discrete alive/crouch/tool state retained until newer sample time")
	check(not sampled.has("health") and not sampled.has("secret_seed") and not sampled.has("fixture_tick"),"remote buffer retains public fields only")
	sampled.feet = Vector3.ZERO
	check(remote.sample(21).feet == Vector3(15,4,10),"remote samples own value copies")
	sampled = remote.sample(26)
	check(sampled.flags == 2|32 and sampled.tool == 0 and sampled.mode == "latest","discrete remote transitions occur at matching tick")
	sampled = remote.sample(29)
	near(sampled.feet.x,20+0.1*32*0.05,"native velocity100ms extrapolation scaling")
	var frozen: Dictionary = remote.sample(32.01)
	near(frozen.feet.x,20+0.1*32*0.1,"remote maximum extrapolated position")
	check(frozen.mode == "frozen" and frozen.poor_connection and remote.sample(600).feet == frozen.feet,"expired remote sample freezes extrapolated endpoint without snapping back")
	check(not remote.push(later,7,20).ok and not remote.push(later,7,19).ok,"duplicate/reordered remote tick rejected")
	var new_spawn := pose(2,Vector3(50,4,10),0,2)
	check(remote.push(new_spawn,7,2).ok and remote.get_stats().poses == 1 and remote.sample(2).feet == Vector3(50,4,10),"new generation clears corpse/old spawn interpolation even with restarted timestamp")
	check(not remote.push(later,7,21).ok,"older generation pose rejected")
	new_spawn.spawn_generation = 1
	check(remote.push(new_spawn,8,0).ok and remote.get_stats().epoch == 8 and remote.get_stats().poses == 1,"new match clears remote buffer/generation")
	check(not remote.push(later,7,99).ok,"old remote epoch rejected")
	for tick: int in range(1,41): remote.push(pose(tick,Vector3(tick,4,10)),8,tick)
	check(remote.get_stats().poses == 32 and remote.get_stats().capacity == 32,"remote history has exact32-pose cap")
	remote.set_delay_seconds(-1)
	near(remote.get_stats().delay_seconds,0,"remote delay minimum")
	remote.set_delay_seconds(2)
	near(remote.get_stats().delay_seconds,0.25,"remote jitter delay bounded to250ms")
	var malformed := pose(41,Vector3(INF,0,0))
	var stats: Dictionary = remote.get_stats()
	check(not remote.push(malformed,8,41).ok and remote.get_stats() == stats,"malformed remote data leaves buffer untouched")
	malformed = pose(41,Vector3.ZERO)
	malformed.id = 10
	check(not remote.push(malformed,8,41).ok,"per-actor remote buffer rejects another actor")
	check(remote.sample(INF).is_empty(),"invalid estimated clock rejected")
	remote.clear()
	check(remote.get_stats().poses == 0 and remote.sample(42).is_empty(),"disconnect clears remote public poses")

func run() -> void:
	var nodes := root.get_child_count()
	trace_checks()
	reconciliation_checks()
	authority_and_terrain_checks()
	reset_and_budget_checks()
	remote_checks()
	check(root.get_child_count() == nodes,"prediction/interpolation never creates presentation or physics nodes")
	print("CLIENT PREDICTION TESTS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
