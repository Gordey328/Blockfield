extends SceneTree
## Isolated source rules, with a real shared voxel query and no main/settings.
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const DATA = preload("res://world/voxel_data.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("PLAYER RULES: " + message)

func near(actual: float, expected: float, message: String, tolerance: float = .000002) -> void:
	check(absf(actual-expected) <= tolerance, "%s: %s != %s" % [message,actual,expected])

func vector(actual: Vector3, expected: Vector3, message: String, tolerance: float = .00002) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s: %s != %s" % [message,actual,expected])

func actor(id: int = 1, weapon: int = 0, profile: String = "0.75", tick: int = 0) -> SharedPlayerState:
	var result := STATE.new(id,"Actor%d" % id,7,profile,1234+id)
	RULES.spawn(result,tick,Vector3(20.5,4.01,20.5),id%2,weapon)
	result.tool_raise = 1 # Fixture: spawning native weapon has finished raising.
	return result

func command(value: SharedPlayerState, buttons: int = 0, move: Vector2 = Vector2.ZERO) -> PlayerRules.Command:
	var result := RULES.Command.new()
	result.sequence = value.consumed_input_sequence + 1
	result.spawn_generation = value.spawn_generation
	result.buttons = buttons
	result.move = move
	result.yaw = value.yaw
	result.pitch = value.pitch
	return result

func events_of(events: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in events:
		if value.type == kind: result.append(value)
	return result

func grenade_tool(value: SharedPlayerState) -> void:
	value.tool = RULES.Tool.GRENADE
	value.displayed_tool = RULES.Tool.GRENADE
	value.tool_raise = 1

func _run() -> void:
	for scenario: String in ["profiles","independent_actors","cadence","reload_rules","tool_and_sprint_gates","class_resources","grenade_rules","spade_rules","rng_and_recoil","motion_rules","command_generation"]:
		check(call(scenario) == true,"scenario completes: " + scenario)
	print("PLAYER RULES: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func profiles() -> bool:
	check(PROFILES.get_info("0.75",0).clip_size == 10 and PROFILES.get_info("0.76",0).clip_size == 8,"source rifle clip profile change")
	check(PROFILES.get_info("0.75",1).max_stock == 120 and PROFILES.get_info("0.76",1).max_stock == 150,"source SMG reserve profile change")
	near(PROFILES.get_info("0.75",1).delay,.11,"0.75 SMG cadence")
	near(PROFILES.get_info("0.76",1).delay,.1,"0.76 SMG cadence")
	near(PROFILES.get_info("0.76",2).reload_time,.4,"0.76 shotgun shell time")
	check(PROFILES.get_info("0.75",2).pellets == 8,"original eight cumulative pellets")
	var isolated := PROFILES.get_info("0.75",0)
	isolated.clip_size = 900
	check(PROFILES.get_info("0.75",0).clip_size == 10,"returned profile cannot modify source constants")
	check(PROFILES.get_info("unknown",0).is_empty() and not PROFILES.valid("0.75",3),"invalid profiles reject")
	check(PROFILES.damage("0.75",0,"head",127.999) == 100 and PROFILES.damage("0.75",0,"head",128) == 0,"horizontal damage cutoff, not camera distance")
	check(PROFILES.damage("0.76",1,"block",1) == 34 and PROFILES.damage("0.75",1,"block",1) == 35,"SMG block profile difference")
	check(PROFILES.damage("0.75",0,"delay",1) == 0 and PROFILES.damage("0.75",0,"head",NAN) == 0,"no arbitrary profile field as damage")
	return true

func independent_actors() -> bool:
	var first := actor(1)
	var second := actor(2)
	var shot := RULES.step_fixed(first,0,command(first,RULES.Buttons.PRIMARY))
	RULES.step_fixed(second,0,command(second))
	check(first.magazine == 9 and second.magazine == 10,"two actors have separate inventory")
	check(first.next_shot_tick == 30 and second.next_shot_tick == 0,"two actors have separate deadlines")
	check(events_of(shot,"shot")[0].owner_id == 1,"events retain stable actor ownership")
	check(shot.is_read_only() and shot[0].is_read_only() and shot[0].directions.is_read_only(),"event arrays and nested payloads immutable")
	var replay := first.copy()
	replay.motion.native_velocity.x = .7
	replay.magazine = 1
	check(first.motion.native_velocity.x == 0 and first.magazine == 9,"diagnostic copy owns motion/resources")
	check(replay.shot_rng.state == first.shot_rng.state and replay.shot_rng != first.shot_rng,"copy owns identical isolated RNG state")
	replay.shot_rng.randf()
	check(replay.shot_rng.state != first.shot_rng.state,"replay RNG cannot mutate original actor")
	first.score = 12
	check(first.copy().score == 12 and first.kills == 0,"score copied independently of kill count")
	var before := first.magazine
	check(RULES.step_fixed(first,0,command(first,RULES.Buttons.PRIMARY)).is_empty() and first.magazine == before,"duplicate tick cannot repeat shot")
	check(RULES.step_fixed(first,2,command(first,RULES.Buttons.PRIMARY)).is_empty() and first.last_tick == 0,"skipped clock rejected, no variable clock delta")
	var old_id: String = shot[0].event_id
	RULES.spawn(first,40,first.feet(),0)
	var fresh := RULES.event(first,40,"fixture")
	check(fresh.event_id != old_id and fresh.spawn_generation == 2,"event IDs separated by respawn generation")
	return true

func cadence() -> bool:
	var smg := actor(1,1)
	var ticks: Array[int] = []
	for tick in range(41):
		for value: Dictionary in RULES.step_fixed(smg,tick,command(smg,RULES.Buttons.PRIMARY)):
			if value.type == "shot": ticks.append(value.tick)
	check(ticks == [0,7,14,20,27,33,40],"0.75 held SMG retains fractional 6.6-tick overshoot: " + str(ticks))
	near(smg.next_shot_tick,46.2,"fractional deadline retained")
	var smg76 := actor(2,1,"0.76")
	var ticks76: Array[int] = []
	for tick in range(25):
		for value: Dictionary in RULES.step_fixed(smg76,tick,command(smg76,RULES.Buttons.PRIMARY)):
			if value.type == "shot": ticks76.append(value.tick)
	check(ticks76 == [0,6,12,18,24],"0.76 held SMG six-tick cadence")
	var rifle := actor()
	rifle.magazine = 1
	var dry := 0
	for tick in range(41): dry += events_of(RULES.step_fixed(rifle,tick,command(rifle,RULES.Buttons.PRIMARY)),"dry_fire").size()
	check(dry == 1 and rifle.magazine == 0,"empty held trigger emits dry fire exactly once")
	RULES.step_fixed(rifle,41,command(rifle))
	check(events_of(RULES.step_fixed(rifle,42,command(rifle,RULES.Buttons.PRIMARY)),"dry_fire").size() == 1,"new trigger allows one new dry feedback")
	rifle.magazine = 2
	RULES.step_fixed(rifle,43,command(rifle))
	check(events_of(RULES.step_fixed(rifle,44,command(rifle,RULES.Buttons.PRIMARY)),"shot").size() == 1,"late fresh trigger rebases old deadline")
	near(rifle.next_shot_tick,74,"fresh trigger cadence deadline")
	return true

func reload_rules() -> bool:
	var rifle := actor()
	rifle.magazine = 3
	check(RULES.begin_reload(rifle,0).size() == 1,"fast reload starts")
	for tick in range(150): RULES.step_fixed(rifle,tick,command(rifle,RULES.Buttons.PRIMARY))
	check(rifle.magazine == 3 and rifle.reloading,"fast reload rejects fire before 150 ticks")
	var completed := RULES.step_fixed(rifle,150,command(rifle))
	check(rifle.magazine == 10 and rifle.reserve == 43 and not rifle.reloading,"fast reload transfers missing rounds at deadline")
	check(events_of(completed,"reload_completed").size() == 1,"single completion event")
	var shotgun := actor(2,2)
	shotgun.magazine = 0
	RULES.begin_reload(shotgun,0)
	for tick in range(30): RULES.step_fixed(shotgun,tick,command(shotgun))
	check(shotgun.magazine == 0,"shell cannot load early")
	check(events_of(RULES.step_fixed(shotgun,30,command(shotgun)),"shell_loaded").size() == 1,"one original shell at .5 seconds")
	check(shotgun.magazine == 1 and shotgun.reserve == 47 and shotgun.reloading,"shell reload conserves stock")
	var interrupted := RULES.step_fixed(shotgun,31,command(shotgun,RULES.Buttons.PRIMARY))
	check(events_of(interrupted,"reload_cancelled").size() == 1 and events_of(interrupted,"shot").size() == 1,"loaded slow reload interrupts and fires")
	check(shotgun.magazine == 0 and not shotgun.reloading,"interrupt consumes one loaded shell")
	var sg76 := actor(3,2,"0.76")
	sg76.magazine = 7
	RULES.begin_reload(sg76,0)
	for tick in range(25): RULES.step_fixed(sg76,tick,command(sg76))
	check(sg76.magazine == 8 and sg76.reserve == 47 and not sg76.reloading,"0.76 last shell completes at 24 ticks")
	var empty := actor()
	empty.magazine = 0
	empty.reserve = 0
	check(RULES.begin_reload(empty,0).is_empty(),"no infinite reload without reserve")
	var boundary := actor(4,2)
	boundary.magazine = 0
	RULES.begin_reload(boundary,0)
	for tick in range(30): RULES.step_fixed(boundary,tick,command(boundary))
	var pressed := RULES.step_fixed(boundary,30,command(boundary,RULES.Buttons.PRIMARY))
	check(boundary.magazine == 0 and boundary.reserve == 48 and not boundary.reloading,"shoot-first source phase cancels empty reload at shell deadline")
	check(events_of(pressed,"shell_loaded").is_empty() and events_of(pressed,"shot").is_empty() and events_of(pressed,"dry_fire").size() == 1,"no phantom loaded shell/fire at interruption boundary")
	return true

func tool_and_sprint_gates() -> bool:
	var value := actor()
	value.tool_raise = 0
	for tick in range(15): check(events_of(RULES.step_fixed(value,tick,command(value,RULES.Buttons.PRIMARY)),"shot").is_empty(),"native raise gates tick %d" % tick)
	check(events_of(RULES.step_fixed(value,15,command(value,RULES.Buttons.PRIMARY)),"shot").size() == 1,"native raising permits fire next input phase")
	RULES.select_tool(value,RULES.Tool.SPADE,16)
	check(RULES.is_changing_tool(value) and not RULES.can_use_tool(value),"selection gates while desired differs from displayed")
	var swaps := 0
	for tick in range(16,48): swaps += events_of(RULES.step_fixed(value,tick,command(value)),"tool_swapped").size()
	check(swaps == 1 and value.displayed_tool == 0 and value.tool_raise == 1,"single lower/swap/raise transition")
	var sprinter := actor()
	sprinter.sprint_state = .1
	check(events_of(RULES.step_fixed(sprinter,0,command(sprinter,RULES.Buttons.PRIMARY)),"shot").is_empty(),"sprint recovery raw .1 blocks action")
	check(events_of(RULES.step_fixed(sprinter,1,command(sprinter,RULES.Buttons.PRIMARY)),"shot").is_empty(),"sprint recovery raw .05 blocks action")
	check(events_of(RULES.step_fixed(sprinter,2,command(sprinter,RULES.Buttons.PRIMARY)),"shot").size() == 1,"action waits until raw sprint fully zero")
	var empty := actor()
	empty.tool = RULES.Tool.GRENADE
	empty.displayed_tool = RULES.Tool.GRENADE
	empty.grenades = 0
	var selected := events_of(RULES.step_fixed(empty,0,command(empty)),"tool_selected")
	check(selected.size() == 1 and empty.tool == RULES.Tool.WEAPON,"depleted grenade automatically chooses source previous usable tool")
	return true

func class_resources() -> bool:
	var value := actor()
	value.magazine = 2
	value.reserve = 7
	value.health = 31
	value.blocks = 4
	value.grenades = 1
	check(RULES.request_class(value,2,0).size() == 1,"pending class accepted")
	check(value.weapon == 0 and value.magazine == 2 and value.reserve == 7 and value.health == 31,"live class request never switches/refills")
	check(RULES.restock(value,0).is_empty() and value.reserve == 7,"restock needs coordinator authority")
	RULES.restock(value,0,true)
	check(value.magazine == 2 and value.reserve == 50 and value.health == 100 and value.blocks == 50 and value.grenades == 3,"source restock preserves clip")
	RULES.spawn(value,2,value.feet(),1)
	check(value.weapon == 2 and value.magazine == 6 and value.reserve == 48 and value.pending_weapon == -1,"authorized spawn applies pending class once")
	value.tool = RULES.Tool.BLOCK
	value.displayed_tool = RULES.Tool.BLOCK
	value.tool_raise = 1
	RULES.use_blocks(value,2,3)
	check(value.blocks == 47 and RULES.use_blocks(value,31).is_empty(),"block stock and .5 second deadline")
	check(RULES.use_blocks(value,32).size() == 1 and value.blocks == 46,"block deadline opens exactly at 30 ticks")
	RULES.recover_block(value,32)
	check(value.blocks == 47,"successful source dig recovers one block")
	value.team = 2
	check(RULES.fire(value,40).is_empty() and RULES.restock(value,40,true).is_empty() and RULES.use_blocks(value,40).is_empty(),"spectator cannot fire/restock/build")
	value.team = 1
	var damaged := actor(5)
	check(RULES.damage(damaged,NAN,0).is_empty() and RULES.damage(damaged,INF,0).is_empty(),"nonfinite damage cannot corrupt health")
	check(events_of(RULES.damage(damaged,1e100,0),"death").size() == 1 and damaged.health == 0,"large finite damage clamps before integer overflow")
	return true

func grenade_rules() -> bool:
	var value := actor(11)
	grenade_tool(value)
	value.motion.native_velocity = Vector3(.1,.2,.3)
	value.consumed_input_sequence = 15
	RULES.begin_cook(value,0)
	check(value.grenades == 3 and value.cooking,"pin does not consume grenade until release")
	check(RULES.release_grenade(value,2).is_empty() and value.release_pending,"early release queues original .15 second pin delay")
	var released := RULES.release_grenade(value,9)
	check(released.size() == 1 and value.grenades == 2 and not value.cooking,"queued release costs exactly one at minimum delay")
	vector(released[0].native_velocity,Vector3(.1,.2,-.7),"throw combines front with native velocity")
	near(released[0].fuse,2.85,"minimum delay consumes original fuse")
	check(released[0].cook_action_sequence == 15 and released[0].owner_id == 11,"grenade pin owns original action and actor")
	check(RULES.release_grenade(value,9).is_empty() and RULES.begin_cook(value,38).is_empty(),"release dedup and .5 second cooldown")
	check(RULES.begin_cook(value,39).size() == 1,"new pin at grenade deadline")
	var death := RULES.damage(value,100,40,3,"weapon","shot-3")
	var dropped := events_of(death,"grenade_thrown")
	check(dropped.size() == 1 and dropped[0].drop and dropped[0].owner_id == 11,"death forces exactly one owned grenade drop even before pin delay")
	vector(dropped[0].native_velocity,Vector3(.1,.2,.3),"death drop has native velocity without throw impulse")
	near(dropped[0].fuse,3-1.0/60,"death drop preserves consumed fuse")
	check(value.grenades == 1 and value.deaths == 1 and value.respawn_tick == 220,"death resources and authored respawn eligibility")
	check(RULES.damage(value,100,40).is_empty() and RULES.release_grenade(value,40,true).is_empty(),"duplicate death cannot duplicate grenade or death")
	check(RULES.fire(value,41).is_empty() and RULES.begin_reload(value,41).is_empty(),"dead actor cannot use weapon")
	var cooked := actor(12)
	grenade_tool(cooked)
	var thrown: Array[int] = []
	for tick in range(201):
		for event: Dictionary in RULES.step_fixed(cooked,tick,command(cooked,RULES.Buttons.PRIMARY)):
			if event.type == "grenade_thrown": thrown.append(event.tick)
	check(thrown == [175] and cooked.grenades == 2,"native strict >2.9 seconds cooks once per held press")
	RULES.step_fixed(cooked,201,command(cooked))
	check(events_of(RULES.step_fixed(cooked,202,command(cooked,RULES.Buttons.PRIMARY)),"grenade_pin").size() == 1,"source automatic cook throw adds no manual-release cooldown; new press may pull next pin")
	RULES.spawn(cooked,300,cooked.feet(),0)
	check(cooked.grenades == 3 and not cooked.cooking and cooked.spawn_generation == 2,"respawn resets cook once with new generation")
	return true

func spade_rules() -> bool:
	var value := actor()
	value.tool = 0
	value.displayed_tool = 0
	var digs: Array[int] = []
	for tick in range(123):
		for event: Dictionary in RULES.step_fixed(value,tick,command(value,RULES.Buttons.PRIMARY|RULES.Buttons.SECONDARY)):
			check(event.type != "spade_bash","secondary dig takes priority over bash")
			if event.type == "spade_dig": digs.append(event.tick)
	check(digs == [61,122],"source dig strictly after 1-second timer")
	check(events_of(RULES.step_fixed(value,123,command(value,RULES.Buttons.PRIMARY)),"spade_bash").size() == 1,"switching to primary permits bash")
	check(events_of(RULES.step_fixed(value,124,command(value,RULES.Buttons.PRIMARY)),"spade_bash").is_empty(),"spade bash has independent .2 second deadline")
	return true

func rng_and_recoil() -> bool:
	var samples := PackedFloat32Array([1,0,1,0,1,0,0,1,0,1,0,1])
	var spread := RULES.spread_from_samples(Vector3.FORWARD,.02,samples)
	vector(spread[0],Vector3(.02039968,.02039968,-.99958384),"triangular axis sample golden")
	vector(spread[1],Vector3.FORWARD,"second pellet cancels unnormalized cumulative offset")
	check(RULES.spread_from_samples(Vector3.FORWARD,.02,PackedFloat32Array([1])).is_empty(),"malformed sample grouping rejected")
	var first := actor(1,2)
	var second := first.copy()
	for unused in range(17): randf() # Cosmetic/global RNG must have no influence.
	var a := RULES.fire(first,0)
	var b := RULES.fire(second,0)
	check(a[0].directions == b[0].directions and first.shot_rng.state == second.shot_rng.state,"equal isolated seeds reproduce source spread regardless of global random")
	var injected := RandomNumberGenerator.new()
	injected.seed = 999
	var before := first.shot_rng.state
	first.trigger_held = false
	RULES.fire(first,60,injected)
	check(first.shot_rng.state == before,"injected local test RNG does not consume actor RNG")
	var stand := RULES.source_recoil(Vector3.FORWARD,Vector3.RIGHT,Vector3.UP,Vector3(.025,.05,0),0,false)
	vector(stand,Vector3(-.02496103,.04992205,-.99844115),"source triangular recoil phase zero")
	var crouch := RULES.source_recoil(Vector3.FORWARD,Vector3.RIGHT,Vector3.UP,Vector3(.025,.05,0),0,true)
	vector(crouch,Vector3(-.01249512,.02499024,-.9996096),"source crouch halves recoil")
	return true

func motion_rules() -> bool:
	var value := actor()
	value.input_move = Vector2(0,-1)
	vector(RULES.integrated_velocity(value),Vector3(0,-.01639344,-.015625),"source grounded acceleration/gravity/friction golden")
	value.motion.grounded = false
	vector(RULES.integrated_velocity(value),Vector3(0,-.01639344,-.00163934),"air acceleration tenth and air friction")
	value.motion.grounded = true
	value.motion.crouch = true
	near(RULES.integrated_velocity(value).z,-.0046875,"source crouch acceleration .3")
	value.motion.crouch = false
	value.aiming = true
	near(RULES.integrated_velocity(value).z,-.0078125,"source ADS movement acceleration .5")
	value.aiming = false
	value.sneaking = true
	near(RULES.integrated_velocity(value).z,-.0078125,"source sneak acceleration .5")
	value.sneaking = false
	value.sprinting = true
	near(RULES.integrated_velocity(value).z,-.0203125,"source sprint acceleration 1.3")
	value.sprinting = false
	value.input_move = Vector2(1,-1).normalized()
	near(Vector2(RULES.integrated_velocity(value).x,RULES.integrated_velocity(value).z).length(),.015625,"normalized diagonal cannot accelerate faster")
	value.input_move = Vector2(0,-1)
	value.motion.wading = true
	vector(RULES.integrated_velocity(value),Vector3(0,-.01639344,-.015151515),"wading friction six overrides grounded four")
	value.motion.wading = false
	value.input_buttons = RULES.Buttons.JUMP
	near(RULES.integrated_velocity(value).y,.33770492,"held grounded jump .36 then gravity")
	value.input_buttons = 0
	value.pitch = PI*.5
	near(RULES.integrated_velocity(value).z,-.0015625,"looking vertically slows forward input to one tenth")
	var data := DATA.new()
	check(data.clear(Vector3i(64,64,64),7) == OK,"shared map fixture created")
	data.seed_box(Vector3i(0,3,0),Vector3i(64,4,64),0x01ffffff)
	var runner := actor(5)
	var replay := runner.copy()
	for tick in range(40):
		RULES.step_fixed(runner,tick,command(runner,0,Vector2(0,-1)),data)
		RULES.step_fixed(replay,tick,command(replay,0,Vector2(0,-1)),data)
	vector(runner.feet(),replay.feet(),"same fixed ticks reproduce map collision position")
	vector(runner.motion.native_velocity,replay.motion.native_velocity,"same fixed ticks reproduce map velocity")
	check(runner.feet().z < 17.5 and runner.motion.grounded,"source query actually moves and contacts shared data floor: " + str(runner.feet()))
	var feet_before := runner.feet()
	RULES.step_fixed(runner,39,command(runner,0,Vector2(0,-1)),data)
	RULES.step_fixed(runner,400,command(runner,0,Vector2(0,-1)),data)
	vector(runner.feet(),feet_before,"duplicate/future ticks cannot create extra displacement")
	var jumper := actor(6)
	var jumps := 0
	for tick in range(150): jumps += events_of(RULES.step_fixed(jumper,tick,command(jumper,RULES.Buttons.JUMP),data),"jump").size()
	check(jumps >= 2 and jumper.health == 100,"held jump repeats only after source landing")
	var sprint := actor(7)
	RULES.step_fixed(sprint,0,command(sprint,RULES.Buttons.SPRINT,Vector2(0,-1)),data)
	check(not sprint.sprinting,"native sprint checks previous horizontal velocity .1 threshold")
	for tick in range(1,21): RULES.step_fixed(sprint,tick,command(sprint,RULES.Buttons.SPRINT,Vector2(0,-1)),data)
	check(sprint.sprinting and sprint.sprint_state > 0,"sprint begins after real movement threshold")
	var crouched := actor(8)
	RULES.step_fixed(crouched,0,command(crouched,RULES.Buttons.CROUCH),data)
	check(crouched.motion.crouch,"shared source crouch query applied")
	vector(crouched.feet(),Vector3(20.5,4.01,20.5),"ground crouch preserves feet within one gravity step",.02)
	return true

func command_generation() -> bool:
	var value := actor()
	var stale := command(value,RULES.Buttons.PRIMARY)
	stale.spawn_generation = 99
	RULES.step_fixed(value,0,stale)
	check(value.magazine == 10 and value.consumed_input_sequence == 0,"stale generation cannot control respawn")
	var invalid := command(value,RULES.Buttons.PRIMARY,Vector2(1,1))
	check(not invalid.valid(),"overlength movement rejected instead of extra diagonal speed")
	var overflow := command(value)
	overflow.sequence = 0x100000000
	check(not overflow.valid(),"command sequence cannot wrap bounded sequence range")
	RULES.step_fixed(value,1,invalid)
	check(value.magazine == 10,"invalid command cannot fire")
	var accepted := command(value)
	RULES.step_fixed(value,2,accepted)
	accepted.buttons = RULES.Buttons.PRIMARY
	RULES.step_fixed(value,3,accepted)
	check(value.magazine == 10,"replayed sequence cannot overwrite accepted controls")
	var intent := command(value)
	intent.weapon = 1
	RULES.step_fixed(value,4,intent)
	check(value.pending_weapon == 1 and value.weapon == 0 and value.magazine == 10,"local class intent cannot refill live actor")
	return true
