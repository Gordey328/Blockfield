extends SceneTree
## Exercise actual VoxelData routes and fixed movement, not a mirrored cost formula.
const ARENA = preload("res://ai/survival_arena.gd")
const NAVIGATION = preload("res://ai/zombie_navigation.gd")
const DIRECTOR = preload("res://ai/zombie_director.gd")
const SIMULATION = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("Zombie AI: " + message)

func _run() -> void:
	_authored_spawn_and_edit()
	_cost_choice_and_damage()
	_shared_movement_and_bite_intents()
	_breach_intents_and_separation()
	print("Zombie AI: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _match(data: VoxelData) -> MatchSimulation:
	var match_state: MatchSimulation = SIMULATION.new()
	check(match_state.configure(data, "0.75", "sandbox").ok, "real shared authority configures")
	match_state.friendly_fire = false
	return match_state

func _owner(match_state: MatchSimulation, point: Vector3) -> SharedPlayerState:
	check(match_state.add_actor("Player", 2, 773, Vector3.INF, 1).ok, "human slot admitted")
	check(match_state.spawn_actor(1, 0, 0, point).ok, "human safe spawn")
	return match_state.get_actor(1)

func _zombie(match_state: MatchSimulation, id: int, point: Vector3) -> SharedPlayerState:
	check(match_state.register_zombie_slot(id).ok, "reusable zombie registered")
	check(match_state.spawn_zombie_slot(id, point).ok, "reusable zombie gets safe life")
	return match_state.get_actor(id)

func _flat(size: Vector3i = Vector3i(48, 16, 48)) -> VoxelData:
	var data: VoxelData = DATA.new()
	check(data.clear(size) == OK, "fixture dimensions accepted")
	data.seed_box(Vector3i.ZERO, Vector3i(size.x, 4, size.z), 0x01776655)
	return data

func _authored_spawn_and_edit() -> void:
	var data: VoxelData = ARENA.build()
	var arena: Dictionary = ARENA.metadata()
	var match_state: MatchSimulation = _match(data)
	var player: SharedPlayerState = _owner(match_state, arena.owner_spawn)
	var director: ZombieDirector = DIRECTOR.new()
	var ids: Array[int] = [2, 3]
	director.configure(data, arena, ids)
	var nav: ZombieNavigation = NAVIGATION.new()
	nav.configure(data, arena)
	check(nav.can_stand(arena.owner_spawn), "authored owner spawn supported and body clear")
	for point: Vector3 in arena.spawn_sectors:
		check(nav.can_stand(point), "every authored sector supports full standing body")
	var selected: Dictionary = director.choose_spawn(match_state, 1, 12)
	check(selected.ok and selected.route_valid, "emergence includes a proven actual map route")
	if not selected.ok:
		return
	check(selected.point.distance_to(player.feet()) >= 12, "emergence excludes near-player sector")
	check(selected.map_sequence == data.map_sequence, "warning candidate records geometry version")
	var duplicate: Dictionary = director.choose_spawn(match_state, 1, 12)
	check(not duplicate.ok and duplicate.error == "budget_deferred", "spawn searches share one job per tick")
	# Genuine terrain transactions remove support; a cached candidate becomes invalid.
	var point: Vector3 = selected.point
	var cell: Vector3i = Vector3i(floori(point.x), 3, floori(point.z))
	check(data.set_block(cell, 0, {"tick":0}).changed, "support edit committed")
	check(not nav.can_stand(point), "spawn cannot stand on removed support")
	match_state.step_fixed()
	var again: Dictionary = director.choose_spawn(match_state, 1, 12)
	check(again.ok and again.point != point, "future emergence uses supported alternative")
	match_state.drain_events()
	match_state.drain_transactions()

func _cost_choice_and_damage() -> void:
	var data: VoxelData = _flat()
	# Long open detour exists around a three-cell-high, one-cell-thick wall.
	data.seed_box(Vector3i(24, 4, 8), Vector3i(25, 7, 40), 0x01abbbaa)
	var match_state: MatchSimulation = _match(data)
	var player: SharedPlayerState = _owner(match_state, Vector3(30.5, 4.01, 24.5))
	var zombie: SharedPlayerState = _zombie(match_state, 2, Vector3(18.5, 4.01, 24.5))
	var nav: ZombieNavigation = NAVIGATION.new()
	nav.configure(data, {"floor_y":4, "navigation_ceiling":12})
	nav.begin_tick(0)
	var intact: Dictionary = nav.plan(zombie.feet(), player.feet(), match_state)
	check(intact.ok and intact.mode == "detour", "full-health tall wall favors the real open detour")
	# Shared authoritative persistent damage changes the planner's actual health input.
	for y: int in range(4, 7):
		match_state._damage_block(player, Vector3i(24, y, 24), 80, false)
	check(match_state.get_block_remaining_health(Vector3i(24, 5, 24)) == 20, "fixture uses genuine remaining block health")
	nav.begin_tick(1)
	var damaged: Dictionary = nav.plan(zombie.feet(), player.feet(), match_state)
	check(damaged.ok and damaged.mode == "breach", "damaged thin wall beats an existing long detour")
	if damaged.ok:
		check(damaged.breach_seconds < intact.breach_seconds, "real damage reduces total approach/break/post-path seconds")
		check(damaged.breach_seconds < damaged.detour_seconds, "breach chosen against a finite verified detour")
		var all_cells: Array[Vector3i] = []
		for index: int in damaged.blockers:
			for blocker: Vector3i in damaged.blockers[index]:
				all_cells.append(blocker)
		check(all_cells.has(Vector3i(24, 4, 24)) and all_cells.has(Vector3i(24, 6, 24)), "planned passage accounts for lower and upper body blocks")
		for blocker: Vector3i in all_cells:
			check(blocker.y > 1, "bedrock never becomes a breach candidate")
	nav.begin_tick(2)
	var stable: Dictionary = nav.plan(zombie.feet(), player.feet(), match_state, "breach")
	check(stable.ok and stable.mode == "breach", "nearby reevaluation retains the faster committed approach")
	# A thick obstacle with a short detour is a different actual geometry fixture.
	var short_data: VoxelData = _flat()
	short_data.seed_box(Vector3i(22, 4, 22), Vector3i(27, 7, 27), 0x01bbbbaa)
	var short_match: MatchSimulation = _match(short_data)
	_owner(short_match, Vector3(30.5, 4.01, 24.5))
	_zombie(short_match, 2, Vector3(18.5, 4.01, 24.5))
	var short_nav: ZombieNavigation = NAVIGATION.new()
	short_nav.configure(short_data, {})
	short_nav.begin_tick(0)
	var short_route: Dictionary = short_nav.plan(Vector3(18.5, 4.01, 24.5), Vector3(30.5, 4.01, 24.5), short_match)
	check(short_route.ok and short_route.mode == "detour", "thick barrier favors short walk around it")
	# Two verified routes with close arrival times demonstrate actual hysteresis.
	var close_data: VoxelData = _flat()
	close_data.seed_box(Vector3i(24, 4, 11), Vector3i(25, 7, 39), 0x01aabbaa)
	var close_match: MatchSimulation = _match(close_data)
	var close_owner: SharedPlayerState = _owner(close_match, Vector3(30.5, 4.01, 24.5))
	_zombie(close_match, 2, Vector3(18.5, 4.01, 24.5))
	for y: int in range(4, 7):
		close_match._damage_block(close_owner, Vector3i(24, y, 24), 59, false)
	var close_nav: ZombieNavigation = NAVIGATION.new()
	close_nav.configure(close_data, {})
	close_nav.begin_tick(0)
	var prefer_open: Dictionary = close_nav.plan(Vector3(18.5, 4.01, 24.5), close_owner.feet(), close_match, "detour")
	close_nav.begin_tick(1)
	var prefer_committed: Dictionary = close_nav.plan(Vector3(18.5, 4.01, 24.5), close_owner.feet(), close_match, "breach")
	check(prefer_open.ok and prefer_open.mode == "detour", "small arrival advantage does not flip an open route")
	check(prefer_committed.ok and prefer_committed.mode == "breach", "same actual close-cost geometry preserves committed breach")
	var stats: Dictionary = nav.get_statistics()
	check(stats.max_jobs_per_tick == 1 and stats.max_expansions_per_job <= 2 * NAVIGATION.MAX_EXPANSIONS, "aggregate work has fixed bounds")
	match_state.drain_events()
	short_match.drain_events()

func _shared_movement_and_bite_intents() -> void:
	var data: VoxelData = ARENA.build()
	var arena: Dictionary = ARENA.metadata()
	var match_state: MatchSimulation = _match(data)
	var player: SharedPlayerState = _owner(match_state, arena.owner_spawn)
	var ids: Array[int] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
	for index: int in range(ids.size()):
		_zombie(match_state, ids[index], arena.spawn_sectors[index])
	var director: ZombieDirector = DIRECTOR.new()
	director.configure(data, arena, ids)
	var bites: int = 0
	var forbidden_events: int = 0
	var decision_microseconds: Array[int] = []
	var total_microseconds: int = 0
	for tick: int in range(900):
		var started: int = Time.get_ticks_usec()
		var inputs: Dictionary = director.commands(match_state)
		var elapsed: int = Time.get_ticks_usec() - started
		decision_microseconds.append(elapsed)
		total_microseconds += elapsed
		# The final five seconds include accepted human motion and route retargeting.
		var human: PlayerRules.Command = RULES.Command.new()
		human.sequence = tick + 1
		human.spawn_generation = player.spawn_generation
		human.move = Vector2(.3 if tick < 780 else -.3, 0) if tick >= 600 else Vector2.ZERO
		inputs[1] = human
		if tick % 60 == 0:
			for id: int in inputs:
				if id != 1:
					check(inputs[id].valid() and inputs[id].buttons == 0, "zombie emits valid movement without source tool/fire buttons")
		for intent: Dictionary in director.drain_attack_intents():
			if intent.kind == "bite":
				bites += 1
		var events: Array[Dictionary] = match_state.step_fixed(inputs)
		forbidden_events += MatchSimulation.events_of(events, "shot").size()
		forbidden_events += MatchSimulation.events_of(events, "spade_bash").size()
		match_state.drain_events()
		match_state.drain_transactions()
	var diagnostics: Dictionary = director.get_diagnostics()
	check(bites > 0, "actual shared movement reaches bite range on authored Crossroads")
	check(player.health == 100 and forbidden_events == 0, "AI only proposes attacks, never applies damage or source spade100")
	for record: Dictionary in diagnostics.bots:
		check(record.distance_moved > 5, "every actor follows a real map route")
	check(diagnostics.navigation.max_jobs_per_tick == 1, "simultaneous pursuit shares aggregate search budget")
	decision_microseconds.sort()
	print("ZOMBIE_AI_PROFILE " + JSON.stringify({"ticks":900, "actors":ids.size(), "moving_owner_ticks":300,
		"mean_ms":float(total_microseconds) / 900000.0,
		"p95_ms":float(decision_microseconds[854]) / 1000.0,
		"max_ms":float(decision_microseconds.back()) / 1000.0,
		"navigation":diagnostics.navigation}))
	# Close hidden targets must not generate through-wall bites.
	var wall_data: VoxelData = _flat(Vector3i(24, 16, 24))
	wall_data.seed_box(Vector3i(12, 4, 2), Vector3i(13, 7, 22), 0x01abbbaa)
	var wall_match: MatchSimulation = _match(wall_data)
	_owner(wall_match, Vector3(13.5, 4.01, 12.5))
	_zombie(wall_match, 2, Vector3(11.5, 4.01, 12.5))
	var wall_director: ZombieDirector = DIRECTOR.new()
	var one: Array[int] = [2]
	wall_director.configure(wall_data, {}, one)
	wall_director.commands(wall_match)
	for intent: Dictionary in wall_director.drain_attack_intents():
		check(intent.kind != "bite", "wall blocks AI bite proposal")

func _breach_intents_and_separation() -> void:
	var data: VoxelData = _flat(Vector3i(24, 16, 24))
	data.seed_box(Vector3i(12, 4, 1), Vector3i(13, 7, 23), 0x01aabbaa)
	var match_state: MatchSimulation = _match(data)
	_owner(match_state, Vector3(15.5, 4.01, 12.5))
	var zombie: SharedPlayerState = _zombie(match_state, 2, Vector3(10.5, 4.01, 12.5))
	var director: ZombieDirector = DIRECTOR.new()
	var ids: Array[int] = [2]
	director.configure(data, {}, ids)
	var accepted: int = 0
	var last_attack: int = -90
	for tick: int in range(900):
		var inputs: Dictionary = director.commands(match_state)
		var proposals: Array[Dictionary] = director.drain_attack_intents()
		match_state.step_fixed(inputs)
		for intent: Dictionary in proposals:
			if intent.kind == "breach" and tick >= last_attack + 90:
				var events: Array[Dictionary] = match_state.resolve_zombie_breach(intent.actor_id, intent.cell)
				if not events.is_empty():
					accepted += 1
					last_attack = tick
		match_state.drain_events()
		match_state.drain_transactions()
	check(accepted > 0, "proposed accessible cells pass actual authoritative breach validation")
	check(zombie.feet().x > 12.5, "real shared movement crosses the actually demolished passage: position=%s accepted=%d diagnostic=%s" % [zombie.feet(), accepted, director.get_diagnostics()])
	check(director.get_diagnostics().navigation.invalidations > 0, "committed destruction invalidates route geometry")
	# Steering separates approaching actors without moving their state directly.
	var open_data: VoxelData = _flat(Vector3i(24, 16, 24))
	var open_match: MatchSimulation = _match(open_data)
	_owner(open_match, Vector3(18.5, 4.01, 12.5))
	var left: SharedPlayerState = _zombie(open_match, 2, Vector3(5.5, 4.01, 12.5))
	var right: SharedPlayerState = _zombie(open_match, 3, Vector3(5.5, 4.01, 14.5))
	# Fixture places a near pair after individually safe admission.
	right.motion.feet_position = Vector3(5.5, 4.01, 13.0)
	var pair: ZombieDirector = DIRECTOR.new()
	var pair_ids: Array[int] = [2, 3]
	pair.configure(open_data, {}, pair_ids)
	for tick: int in range(90):
		open_match.step_fixed(pair.commands(open_match))
		pair.drain_attack_intents()
		open_match.drain_events()
		open_match.drain_transactions()
	check(left.feet().distance_to(right.feet()) > .5, "close pursuit steering expands separation through shared movement")
	check(left.feet().x > 5.5 and right.feet().x > 5.5, "separation allows forward progress")
