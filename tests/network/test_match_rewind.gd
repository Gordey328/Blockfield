extends SceneTree
const MATCH = preload("res://simulation/match_simulation.gd")
const HISTORY = preload("res://network/hit_history.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures += 1; push_error("MATCH_REWIND: " + message)
func _run() -> void:
	_test_offline_preserved()
	_test_moving_target_and_origin()
	_test_same_time_cover()
	_test_all_shots_preplanned()
	_test_shotgun_preplanned()
	_test_generation_and_eligibility()
	_test_repaint_guard()
	_test_missing_and_stale_history()
	_test_command_lease_and_window()
	_test_invalid_factory_and_bounds()
	print("MATCH_REWIND: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _fixture() -> MATCH:
	var data: DATA = DATA.new()
	check(data.clear(Vector3i(32,16,32),7) == OK,"small canonical authority map")
	data.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x01608040)
	var sim: MATCH = MATCH.new()
	check(sim.configure(data).ok,"match fixture configured")
	return sim
func _spawn(sim: MATCH, name: String, team: int, feet: Vector3, weapon: int = 0) -> SharedPlayerState:
	var admitted: Dictionary = sim.add_actor(name)
	check(admitted.ok,"stable actor admitted: " + name)
	var actor: SharedPlayerState = sim.get_actor(admitted.actor_id)
	check(sim.spawn_actor(actor.player_id,team,weapon,feet).ok,"safe authoritative spawn: " + name)
	actor.tool_raise = 1
	return actor
func _input(actor: SharedPlayerState, buttons: int = RULES.Buttons.PRIMARY, yaw: float = 0.0, pitch: float = 0.0) -> RULES.Command:
	var command: RULES.Command = RULES.Command.new()
	command.sequence = actor.consumed_input_sequence + 1
	command.spawn_generation = actor.spawn_generation
	command.buttons = buttons
	command.yaw = yaw; command.pitch = pitch
	return command
func _record(sim: MATCH, history: HISTORY) -> void:
	sim.data.last_tick = sim.tick
	var actors: Array[SharedPlayerState] = []
	for actor: SharedPlayerState in sim.actors.values(): actors.append(actor)
	var transactions: Array[Dictionary] = sim.drain_transactions()
	check(history.record_frame(sim.tick,sim.data,actors,transactions).ok,"closed actors and committed terrain recorded at tick%d" % sim.tick)
func _start_history(sim: MATCH) -> HISTORY:
	sim.step_fixed()
	sim.data.last_tick = sim.tick
	var history: HISTORY = HISTORY.new()
	check(history.reset(sim.epoch,sim.data).ok,"history pins existing authority")
	_record(sim,history)
	sim.set_rewind_query_factory(history.query_at)
	return history
func _events(events: Array[Dictionary], type: String) -> Array[Dictionary]: return MATCH.events_of(events,type)
func _count(events: Array[Dictionary], type: String) -> int: return _events(events,type).size()

func _test_offline_preserved() -> void:
	var direct: MATCH = _fixture(); var empty: MATCH = _fixture()
	var a: SharedPlayerState = _spawn(direct,"Shooter",0,Vector3(12.5,2.01,25.5))
	var b: SharedPlayerState = _spawn(empty,"Shooter",0,Vector3(12.5,2.01,25.5))
	var victim_a: SharedPlayerState = _spawn(direct,"Victim",1,Vector3(12.5,2.01,15.5))
	var victim_b: SharedPlayerState = _spawn(empty,"Victim",1,Vector3(12.5,2.01,15.5))
	empty.set_rewind_query_factory(Callable())
	var first: Array[Dictionary] = direct.step_fixed({a.player_id:_input(a)})
	var second: Array[Dictionary] = empty.step_fixed({b.player_id:_input(b)},{b.player_id:999999})
	check(first == second,"empty factory preserves exact offline event/ray behavior even with unused tick metadata")
	check(victim_a.health == 0 and victim_b.health == 0 and a.magazine == b.magazine,"empty factory preserves original ammo and head damage")
	check(not empty.get_rewind_stats().enabled and empty.get_rewind_stats().planned_shots == 0,"offline mode has no rewind decisions")

func _test_moving_target_and_origin() -> void:
	var sim: MATCH = _fixture()
	var owner: SharedPlayerState = _spawn(sim,"Shooter",0,Vector3(12.5,2.01,25.5))
	var victim: SharedPlayerState = _spawn(sim,"Moving",1,Vector3(12.5,2.01,15.5))
	var history: HISTORY = _start_history(sim)
	var old_eye: Vector3 = owner.motion.physics_eye()
	owner.motion.feet_position.x = 17.5
	victim.motion.feet_position.x = 19.5
	check(sim.raycast_actors(owner.player_id,owner.motion.physics_eye(),Vector3.FORWARD).is_empty(),"current positions miss the old aim ray")
	var command: RULES.Command = _input(owner)
	var reference_actor: SharedPlayerState = owner.copy()
	var reference: Array[Dictionary] = RULES.step_fixed(reference_actor,sim.tick+1,command,sim.data)
	var queries: Array = []
	sim.set_rewind_query_factory(func(request: int, closed: int) -> Dictionary:
		check(request == 0 and closed == 0,"factory receives admitted tick and latest closed tick")
		var result: Dictionary = history.query_at(request,closed)
		queries.append(result.query)
		return result)
	var events: Array[Dictionary] = sim.step_fixed({owner.player_id:command},{owner.player_id:0})
	check(victim.health == 0 and owner.magazine == 9,"rewind hits the moved actor without trusting a client position")
	var shot: Dictionary = _events(events,"shot")[0]
	var tracer: Dictionary = _events(events,"tracer")[0]
	check(shot.origin.is_equal_approx(old_eye+Vector3.FORWARD*.01) and tracer.origin == shot.origin,"confirmed shot and tracer share historical shooter muzzle")
	check(shot.directions == _events(reference,"shot")[0].directions,"rewind preserves server source RNG rays")
	check(owner.shot_rng.state == reference_actor.shot_rng.state and owner.yaw == reference_actor.yaw and owner.pitch == reference_actor.pitch,"no extra RNG draw or recoil application")
	check(command.yaw == 0 and command.pitch == 0 and reference[0].origin.x > shot.origin.x,"caller command and frozen original event stay unchanged")
	check(queries.size() == 1 and not queries[0].is_valid() and queries[0]._live == null,"borrowed history query released before commits")
	check(sim.get_rewind_stats().planned_shots == 1 and sim.get_rewind_stats().applied_player_hits == 1,"bounded diagnostics count successful historical hit")
	check(_count(sim.drain_events(),"shot") == 1,"event journal receives the replaced historical public origin once")
	sim.set_rewind_query_factory(Callable()) # Release the test closure's sim cycle.

func _test_same_time_cover() -> void:
	var sim: MATCH = _fixture()
	var owner: SharedPlayerState = _spawn(sim,"Covered shooter",0,Vector3(12.5,2.01,25.5))
	var victim: SharedPlayerState = _spawn(sim,"Covered target",1,Vector3(12.5,2.01,15.5))
	var cover: Vector3i = Vector3i(12,4,20)
	sim.data.seed_box(Vector3i(12,2,20),Vector3i(13,6,21),0x01aaaacc)
	var history: HISTORY = _start_history(sim)
	# Remove cover at tick1, then record its full committed receipt.
	sim.step_fixed()
	var removed: Dictionary = sim.data.remove_blocks([cover],false,{"tick":sim.tick,"actor_id":owner.player_id,"action_id":1})
	sim._commit(removed)
	_record(sim,history)
	check(sim.data.get_block(cover) == 0,"current terrain no longer has historical cover")
	var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)},{owner.player_id:0})
	check(victim.health == 100 and _count(events,"hit_confirmed") == 0,"old actor pose is occluded by the same old terrain")
	check(sim.get_rewind_stats().blocked_color_hits == 1 and _count(events,"block_hit") == 0,"already removed historical cover cannot be damaged again")
	check(_events(events,"tracer")[0].position.z > victim.feet().z,"occlusion tracer ends at old cover instead of traversing current air")
	var after: MATCH = _fixture()
	var after_owner: SharedPlayerState = _spawn(after,"After",0,Vector3(12.5,2.01,25.5))
	var after_victim: SharedPlayerState = _spawn(after,"After target",1,Vector3(12.5,2.01,15.5))
	var after_history: HISTORY = _start_history(after)
	var exposed: Array[Dictionary] = after.step_fixed({after_owner.player_id:_input(after_owner)},{after_owner.player_id:0})
	check(after_victim.health == 0 and _count(exposed,"hit_confirmed") == 1,"matching exposed actor+terrain frame resolves a head hit")
	check(after_history.get_stats().latest_tick == 0,"exposed fixture retains its history owner")

func _test_all_shots_preplanned() -> void:
	var sim: MATCH = _fixture()
	var a: SharedPlayerState = _spawn(sim,"First",0,Vector3(12.35,2.01,25.5))
	var b: SharedPlayerState = _spawn(sim,"Second",0,Vector3(12.65,2.01,27.5))
	var victim: SharedPlayerState = _spawn(sim,"Behind cover",1,Vector3(12.5,2.01,15.5))
	var cover: Vector3i = Vector3i(12,4,20)
	sim.data.seed_box(Vector3i(12,2,20),Vector3i(13,6,21),0x01bbbbbb)
	var history: HISTORY = _start_history(sim)
	# One previous rifle hit's damage makes the first planned shot destroy it.
	sim._block_health[cover] = {"health":50.0,"color":sim.data.get_block(cover),"tick":0}
	var calls: int = 0
	var mutable_calls: Array[int] = [calls]
	sim.set_rewind_query_factory(func(request: int, closed: int) -> Dictionary:
		mutable_calls[0] += 1
		check(sim.data.get_block(cover) != 0 and victim.health == 100,"every shot plan runs before terrain/player damage")
		return history.query_at(request,closed))
	var events: Array[Dictionary] = sim.step_fixed({a.player_id:_input(a),b.player_id:_input(b)},{a.player_id:0,b.player_id:0})
	check(mutable_calls[0] == 2 and sim.get_rewind_stats().planned_shots == 2,"both shots query the same still-valid closed authority")
	check(sim.data.get_block(cover) == 0 and sim.drain_transactions().size() == 1,"first shot removes cover once")
	check(victim.health == 100 and _count(events,"hit_confirmed") == 0,"second preplanned shot does not hit through newly destroyed cover")
	check(sim.get_rewind_stats().blocked_color_hits == 1 and _count(events,"tracer") == 2,"second shot keeps its old occlusion endpoint and no repeated block damage")
	check(a.magazine == 9 and b.magazine == 9,"both authenticated shots retain ammo/cadence authority")
	sim.set_rewind_query_factory(Callable())

func _test_shotgun_preplanned() -> void:
	var sim: MATCH = _fixture()
	var owner: SharedPlayerState = _spawn(sim,"Shotgun",0,Vector3(12.5,2.01,25.5),2)
	var victim: SharedPlayerState = _spawn(sim,"Shotgun cover",1,Vector3(12.5,2.01,15.5))
	sim.data.seed_box(Vector3i(11,2,22),Vector3i(14,6,23),0x01aabbcc)
	var history: HISTORY = _start_history(sim)
	# All8 source spread rays hit this near wall. One destruction must not
	# re-cast later pellets into actors or air after the query is released.
	for x in range(11,14):
		for y in range(2,6): sim._block_health[Vector3i(x,y,22)] = {"health":1.0,"color":0x01aabbcc,"tick":0}
	var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)},{owner.player_id:0})
	check(_events(events,"shot")[0].directions.size() == 8 and _count(events,"tracer") == 8,"eight bounded source shotgun pellets retained")
	check(owner.magazine == 5 and victim.health == 100 and _count(events,"hit_confirmed") == 0,"shotgun charges one shell and all pellets remain occluded")
	check(sim.drain_transactions().size() == 1,"source one-block-destruction-per-shot survives rewind planning")
	check(sim.get_rewind_stats().denied_shots == 0 and sim.get_rewind_stats().blocked_color_hits > 0,"later pellets use owned plans after early destruction")
	check(history.get_stats().latest_tick == 0,"shotgun fixture retains history owner")

func _test_generation_and_eligibility() -> void:
	for transition: String in ["respawn","death","disconnect","spectator","old_shooter"]:
		var sim: MATCH = _fixture()
		var owner: SharedPlayerState = _spawn(sim,"Identity shooter",0,Vector3(12.5,2.01,25.5))
		var victim: SharedPlayerState = _spawn(sim,"Identity target",1,Vector3(12.5,2.01,15.5))
		var history: HISTORY = _start_history(sim)
		match transition:
			"respawn": victim.spawn_generation += 1
			"death": victim.health = 0
			"disconnect": victim.connected = false
			"spectator": victim.team = 2; victim.health = 0
			"old_shooter": owner.spawn_generation += 1
		var previous: int = victim.health
		var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)},{owner.player_id:0})
		check(victim.health == previous and _count(events,"hit_confirmed") == 0,"historical hit cannot damage current " + transition)
		check(owner.magazine == 9 and _count(events,"shot") == 1 and _count(events,"tracer") == 1,"denied identity still preserves the authorized shot: " + transition)
		var stats: Dictionary = sim.get_rewind_stats()
		if transition == "respawn": check(stats.blocked_generation_hits == 1,"victim generation mismatch diagnosed")
		elif transition == "old_shooter": check(stats.denied_shots == 1 and stats.last_reason == "historical_shooter_ineligible","historical shooter generation cannot authorize another life")
		else: check(stats.blocked_ineligible_hits == 1,"current target eligibility checked after planning")
		check(history.get_stats().latest_tick == 0,"identity fixture retains closed history")
	# Already committed shots may trade kills: planning is completed before the
	# first authority death, while each current victim still must be eligible.
	var trade: MATCH = _fixture()
	var a: SharedPlayerState = _spawn(trade,"Trade A",0,Vector3(12.5,2.01,25.5))
	var b: SharedPlayerState = _spawn(trade,"Trade B",1,Vector3(12.5,2.01,15.5))
	var trade_history: HISTORY = _start_history(trade)
	var trade_plans: Array[int] = [0]
	trade.set_rewind_query_factory(func(request: int,closed: int) -> Dictionary:
		trade_plans[0] += 1
		check(a.health == 100 and b.health == 100,"all actor-damage plans precede either trade death")
		return trade_history.query_at(request,closed))
	var trades: Array[Dictionary] = trade.step_fixed({a.player_id:_input(a),b.player_id:_input(b,RULES.Buttons.PRIMARY,PI)},{a.player_id:0,b.player_id:0})
	check(a.health == 0 and b.health == 0 and _count(trades,"hit_confirmed") == 2,"same-step authorized shots trade after all rays planned")
	check(a.kills == 1 and b.kills == 1,"trade credits each stable shooter once")
	check(trade_history.get_stats().latest_tick == 0,"trade fixture retains history owner")
	check(trade_plans[0] == 2,"both trade rays planned before applying actor damage")
	trade.set_rewind_query_factory(Callable())

func _test_repaint_guard() -> void:
	var sim: MATCH = _fixture()
	var owner: SharedPlayerState = _spawn(sim,"Repaint shooter",0,Vector3(12.5,2.01,25.5))
	var cell: Vector3i = Vector3i(12,4,20)
	sim.data.seed_box(Vector3i(12,2,20),Vector3i(13,6,21),0x01010203)
	var history: HISTORY = _start_history(sim)
	sim.step_fixed()
	sim._commit(sim.data.set_block(cell,0x01040506,{"tick":1,"actor_id":owner.player_id,"action_id":1}))
	_record(sim,history)
	var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)},{owner.player_id:0})
	check(sim.data.get_block(cell) == 0x01040506 and sim.drain_transactions().is_empty(),"old-color hit cannot damage a repainted current block")
	check(not sim._block_health.has(cell) and _count(events,"block_hit") == 0 and sim.get_rewind_stats().blocked_color_hits == 1,"repaint guard prevents hidden damage state as well as removal")

func _test_missing_and_stale_history() -> void:
	for denied: String in ["no_admission","future","negative","float_tick","missing","stale","cancelled","lost_target"]:
		var sim: MATCH = _fixture()
		var owner: SharedPlayerState = _spawn(sim,"Denied shooter",0,Vector3(12.5,2.01,25.5))
		var victim: SharedPlayerState = _spawn(sim,"Denied target",1,Vector3(12.5,2.01,15.5))
		var history: HISTORY = _start_history(sim)
		var admitted: Dictionary = {owner.player_id:0}
		match denied:
			"no_admission": admitted.clear()
			"future": admitted[owner.player_id] = 1
			"negative": admitted[owner.player_id] = -1
			"float_tick": admitted[owner.player_id] = 0.0
			"missing": sim.set_rewind_query_factory(func(_request: int,_closed: int) -> Dictionary: return {"ok":false,"error":"no history"})
			"stale": sim.data.last_tick = 1
			"cancelled": history.cancel()
			"lost_target":
				var released: HISTORY = HISTORY.new()
				sim.set_rewind_query_factory(released.query_at)
				released = null
		var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)},admitted)
		check(owner.magazine == 9 and victim.health == 100,"missing/stale history costs ammo but denies damage: " + denied)
		check(_count(events,"shot") == 1 and _count(events,"tracer") == 1 and _count(events,"hit_confirmed") == 0,"no new wire event or hit feedback for denied history: " + denied)
		var tracer: Dictionary = _events(events,"tracer")[0]
		check(is_equal_approx(tracer.origin.distance_to(tracer.position),128.0),"denied shot emits only a miss tracer: " + denied)
		check(sim.get_rewind_stats().denied_shots == 1 and sim.get_rewind_stats().denied_pellets == 1,"explicit denial diagnostics: " + denied)
		check(sim.get_rewind_stats().enabled,"configured but missing history never silently falls back to offline: " + denied)
		var copied: Dictionary = sim.get_rewind_stats(); copied.denials.clear(); copied.denied_shots = 500
		check(sim.get_rewind_stats().denied_shots == 1 and not sim.get_rewind_stats().denials.is_empty(),"caller cannot mutate diagnostic registry")

func _test_command_lease_and_window() -> void:
	var sim: MATCH = _fixture()
	var owner: SharedPlayerState = _spawn(sim,"Held lease",0,Vector3(12.5,2.01,25.5),1)
	_spawn(sim,"Off axis",1,Vector3(20.5,2.01,15.5))
	var history: HISTORY = _start_history(sim)
	var shots: int = 0
	for frame in range(1,17):
		var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)} if frame == 1 else {},{owner.player_id:0})
		shots += _count(events,"shot")
		_record(sim,history)
	check(shots >= 2 and sim.get_rewind_stats().planned_shots == shots and sim.get_rewind_stats().denied_shots == 0,"held input reuses a server-admitted tick while within the retained15-tick window")
	owner.next_shot_tick = sim.tick+1
	var expired: Array[Dictionary] = sim.step_fixed({},{owner.player_id:0})
	check(_count(expired,"shot") == 1 and sim.get_rewind_stats().last_reason == "history_unavailable","expired held request is explicitly denied, never clamped to a recent frame")
	check(_count(expired,"hit_confirmed") == 0,"expired lease produces no authoritative hit")
	sim.clear_controls(owner.player_id)
	var cleared: Array[Dictionary] = sim.step_fixed()
	check(_count(cleared,"shot") == 0,"cleared transport lease cannot continue shooting")

func _test_invalid_factory_and_bounds() -> void:
	for corruption: String in ["not_dictionary","wrong_tick","wrong_sequence","wrong_data","malformed_pose","duplicate_pose"]:
		var sim: MATCH = _fixture()
		var owner: SharedPlayerState = _spawn(sim,"Bad factory",0,Vector3(12.5,2.01,25.5))
		var victim: SharedPlayerState = _spawn(sim,"Bad factory target",1,Vector3(12.5,2.01,15.5))
		var history: HISTORY = _start_history(sim)
		sim.set_rewind_query_factory(func(request: int,closed: int) -> Variant:
			if corruption == "not_dictionary": return false
			var result: Dictionary = history.query_at(request,closed)
			match corruption:
				"wrong_tick": result.tick = 1
				"wrong_sequence": result.map_sequence += 1
				"wrong_data": result.query._live = DATA.new()
				"malformed_pose": result.actors[0].physics_eye = Vector3.INF
				"duplicate_pose": result.actors.append(result.actors[0].duplicate())
			return result)
		var events: Array[Dictionary] = sim.step_fixed({owner.player_id:_input(owner)},{owner.player_id:0})
		check(victim.health == 100 and _count(events,"hit_confirmed") == 0 and sim.get_rewind_stats().denied_shots == 1,"invalid trusted adapter output fails closed: " + corruption)
		check(_count(events,"shot") == 1 and _count(events,"tracer") == 1,"adapter rejection remains a regular bounded shot event")
		sim.set_rewind_query_factory(Callable())
	# A32-actor authority frame has at most32shots and256pellets. No generated
	# event may smuggle a caller-chosen ray/position or an unbounded packet here.
	var crowded: MATCH = _fixture()
	var inputs: Dictionary = {}; var admitted: Dictionary = {}
	for index in range(32):
		var actor: SharedPlayerState = _spawn(crowded,"Crowd%d" % index,index%2,Vector3(2.5+float(index%8)*3.5,2.01,3.5+float(index/8)*5.5),2)
		inputs[actor.player_id] = _input(actor)
		admitted[actor.player_id] = 0
	var crowd_history: HISTORY = _start_history(crowded)
	var many: Array[Dictionary] = crowded.step_fixed(inputs,admitted)
	check(crowded.get_rewind_stats().planned_shots == 32 and crowded.get_rewind_stats().denied_shots == 0,"full bounded authority actor frame is planned")
	check(_count(many,"shot") == 32 and _count(many,"tracer") == 256,"32source shots produce exactly256bounded pellet tracers")
	check(crowded.get_rewind_stats().denials.size() <= 10,"diagnostic reason registry stays bounded")
	check(crowd_history.get_stats().frames == 1,"crowd fixture retains its bounded pose frame")
