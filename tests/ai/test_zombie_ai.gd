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
	_random_choice_and_damage()
	_shared_movement_and_bite_intents()
	_breach_intents_and_separation()
	_no_retreat_and_high_target()
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

func _random_choice_and_damage() -> void:
	var data: VoxelData = _flat()
	# Long open detour exists around a three-cell-high, one-cell-thick wall.
	data.seed_box(Vector3i(24, 4, 8), Vector3i(25, 7, 40), 0x01abbbaa)
	var match_state: MatchSimulation = _match(data)
	var player: SharedPlayerState = _owner(match_state, Vector3(30.5, 4.01, 24.5))
	var zombie: SharedPlayerState = _zombie(match_state, 2, Vector3(18.5, 4.01, 24.5))
	var nav: ZombieNavigation = NAVIGATION.new()
	nav.configure(data, {"floor_y":4, "navigation_ceiling":12})
	nav.begin_tick(0)
	var intact: Dictionary = nav.plan(zombie.feet(), player.feet(), match_state, "breach")
	check(intact.ok and intact.mode == "breach" and intact.both_available, "validated requested breach is available alongside a real detour")
	check(intact.breach_seconds > intact.detour_seconds, "expensive breach is retained independently of cheaper detour")
	# Shared authoritative persistent damage changes the planner's actual health input.
	for y: int in range(4, 7):
		match_state._damage_block(player, Vector3i(24, y, 24), 80, false)
	check(match_state.get_block_remaining_health(Vector3i(24, 5, 24)) == 20, "fixture uses genuine remaining block health")
	nav.begin_tick(1)
	var damaged: Dictionary = nav.plan(zombie.feet(), player.feet(), match_state, "detour")
	check(damaged.ok and damaged.mode == "detour", "requested detour survives damage making breach cheaper")
	if damaged.ok:
		check(damaged.breach_seconds < intact.breach_seconds, "real damage reduces total approach/break/post-path seconds")
		check(damaged.breach_seconds < damaged.detour_seconds, "damage changes estimate without changing requested mode")
		var all_cells: Array[Vector3i] = []
		for index: int in intact.blockers:
			for blocker: Vector3i in intact.blockers[index]:
				all_cells.append(blocker)
		check(all_cells.has(Vector3i(24, 4, 24)) and all_cells.has(Vector3i(24, 6, 24)), "planned passage accounts for lower and upper body blocks")
		for blocker: Vector3i in all_cells:
			check(blocker.y > 1, "bedrock never becomes a breach candidate")
	nav.begin_tick(2)
	var stable: Dictionary = nav.plan(zombie.feet(), player.feet(), match_state, "breach")
	check(stable.ok and stable.mode == "breach", "requested mode remains fixed across reevaluation")
	# Actual map plans for independently seeded encounters, not a copied coin formula.
	var breach_count: int = 0
	var ids: Array[int] = [2]
	for seed_value: int in range(64):
		var director: ZombieDirector = DIRECTOR.new()
		director.configure(data, {"zombie_seed":seed_value}, ids)
		director.commands(match_state)
		var initial: Dictionary = director.get_diagnostics().bots[0]
		check(initial.mode == initial.chosen_mode, "both real routes honor the seeded choice instead of cheapest selection")
		if initial.chosen_mode == "breach":
			breach_count += 1
		var replay: ZombieDirector = DIRECTOR.new()
		replay.configure(data, {"zombie_seed":seed_value}, ids)
		replay.commands(match_state)
		check(replay.get_diagnostics().bots[0].chosen_mode == initial.chosen_mode, "same seed/life replays encounter choice")
		# Repeated render sampling cannot reroll a choice at this same obstacle.
		for sample: int in range(4):
			director.commands(match_state)
		var after: Dictionary = director.get_diagnostics().bots[0]
		check(after.choice_rolls == 1 and after.chosen_mode == initial.chosen_mode, "obstacle choice is locked, never drawn each frame")
		if seed_value == 0:
			for tick: int in range(70):
				match_state.step_fixed()
				director.commands(match_state)
				director.drain_attack_intents()
				match_state.drain_events()
			var replanned: Dictionary = director.get_diagnostics().bots[0]
			check(replanned.choice_rolls == 1 and replanned.chosen_mode == initial.chosen_mode, "real fixed-tick plan refreshes preserve the same obstacle choice")
	check(breach_count >= 20 and breach_count <= 44, "actual seeded encounters select both options approximately equally: breaches=%d/64" % breach_count)
	print("ZOMBIE_AI_RANDOM breaches=%d/64" % breach_count)
	var stats: Dictionary = nav.get_statistics()
	check(stats.max_jobs_per_tick == 1 and stats.max_expansions_per_job <= 2 * NAVIGATION.MAX_EXPANSIONS, "aggregate work has fixed bounds")
	match_state.drain_events()

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
	var last_breach: Dictionary[int, int] = {}
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
		var proposals: Array[Dictionary] = director.drain_attack_intents()
		for intent: Dictionary in proposals:
			if intent.kind == "bite":
				bites += 1
		var events: Array[Dictionary] = match_state.step_fixed(inputs)
		for intent: Dictionary in proposals:
			if intent.kind == "breach" and tick >= int(last_breach.get(intent.actor_id, -90)) + 90:
				if not match_state.resolve_zombie_breach(intent.actor_id, intent.cell).is_empty():
					last_breach[intent.actor_id] = tick
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

func _no_retreat_and_high_target() -> void:
	var data: VoxelData = _flat(Vector3i(32, 16, 32))
	var match_state: MatchSimulation = _match(data)
	var player: SharedPlayerState = _owner(match_state, Vector3(27.5, 4.01, 16.5))
	var zombie: SharedPlayerState = _zombie(match_state, 2, Vector3(5.9, 4.01, 16.5))
	var director: ZombieDirector = DIRECTOR.new()
	var ids: Array[int] = [2]
	director.configure(data, {}, ids)
	var retreats: int = 0
	var backward_commands: int = 0
	var bite_ticks: int = 0
	for tick: int in range(720):
		var before: Vector3 = zombie.feet()
		var inputs: Dictionary = director.commands(match_state)
		var command: PlayerRules.Command = inputs[2]
		var front: Vector3 = Vector3(-sin(command.yaw), 0, -cos(command.yaw))
		var right: Vector3 = Vector3(cos(command.yaw), 0, -sin(command.yaw))
		var issued: Vector3 = right * command.move.x - front * command.move.y
		if issued.x < -.0001:
			backward_commands += 1
		for intent: Dictionary in director.drain_attack_intents():
			if intent.kind == "bite":
				bite_ticks += 1
		var human: PlayerRules.Command = RULES.Command.new()
		human.sequence = tick + 1
		human.spawn_generation = player.spawn_generation
		human.move = Vector2(.1, 0) if tick >= 540 else Vector2.ZERO
		inputs[1] = human
		match_state.step_fixed(inputs)
		if zombie.feet().x < before.x - .002:
			retreats += 1
		match_state.drain_events()
		match_state.drain_transactions()
	check(backward_commands == 0 and retreats == 0, "open replans and moving bite boundary never issue backward chase or retreat: commands=%d retreats=%d" % [backward_commands, retreats])
	check(bite_ticks > 0 and zombie.feet().x > 24, "forward chase actually reaches and follows the bite boundary")
	check(director.get_diagnostics().bots[0].choice_rolls == 0, "open pursuit does not randomly seek unrelated walls")
	var step_data: VoxelData = _flat(Vector3i(32, 16, 32))
	step_data.seed_box(Vector3i(16, 4, 1), Vector3i(17, 5, 31), 0x01aabbaa)
	var step_match: MatchSimulation = _match(step_data)
	_owner(step_match, Vector3(21.5, 4.01, 16.5))
	var step_zombie: SharedPlayerState = _zombie(step_match, 2, Vector3(10.5, 4.01, 16.5))
	var step_director: ZombieDirector = DIRECTOR.new()
	step_director.configure(step_data, {}, ids)
	for tick: int in range(400):
		step_match.step_fixed(step_director.commands(step_match))
		step_director.drain_attack_intents()
		step_match.drain_events()
		step_match.drain_transactions()
	check(step_zombie.feet().x > 17.5, "forward recovery preserves ordinary source one-block auto-climb: feet=%s diag=%s" % [step_zombie.feet(), step_director.get_diagnostics()])
	# A two-block pedestal already exceeds one-step motion; it is not a tall tower.
	var low_data: VoxelData = _flat(Vector3i(24, 16, 24))
	low_data.seed_box(Vector3i(12, 4, 12), Vector3i(13, 6, 13), 0x01aabbaa)
	var low_match: MatchSimulation = _match(low_data)
	var low_owner: SharedPlayerState = _owner(low_match, Vector3(12.5, 6.01, 12.5))
	_zombie(low_match, 2, Vector3(8.5, 4.01, 12.5))
	var low_director: ZombieDirector = DIRECTOR.new()
	low_director.configure(low_data, {}, ids)
	var low_hits: int = 0
	var low_last: int = -90
	for tick: int in range(360):
		var inputs: Dictionary = low_director.commands(low_match)
		var proposals: Array[Dictionary] = low_director.drain_attack_intents()
		low_match.step_fixed(inputs)
		for intent: Dictionary in proposals:
			if intent.kind == "breach" and tick >= low_last + 90:
				if not low_match.resolve_zombie_breach(intent.actor_id, intent.cell).is_empty():
					low_hits += 1
					low_last = tick
		low_match.drain_events()
		low_match.drain_transactions()
	check(low_hits >= 3 and low_owner.feet().y < 6, "two-block inaccessible pedestal triggers actual nearby support attacks")
	var platform_data: VoxelData = _flat(Vector3i(32, 16, 32))
	platform_data.seed_box(Vector3i(14, 4, 14), Vector3i(19, 6, 19), 0x01aabbaa)
	var platform_match: MatchSimulation = _match(platform_data)
	_owner(platform_match, Vector3(16.5, 6.01, 16.5))
	var platform_director: ZombieDirector = DIRECTOR.new()
	platform_director.configure(platform_data, {"spawn_sectors":[Vector3(3.5, 4.01, 16.5)]}, ids)
	var platform_spawn: Dictionary = platform_director.choose_spawn(platform_match, 1, 12)
	check(platform_spawn.ok and platform_spawn.route_valid, "fifty-block5x5 platform retains a proven lower approach outside radius2")
	if platform_spawn.ok:
		var platform_zombie: SharedPlayerState = _zombie(platform_match, 2, platform_spawn.point)
		var platform_hits: int = 0
		for tick: int in range(420):
			var inputs: Dictionary = platform_director.commands(platform_match)
			var proposals: Array[Dictionary] = platform_director.drain_attack_intents()
			platform_match.step_fixed(inputs)
			for intent: Dictionary in proposals:
				if intent.kind == "breach" and tick % 90 == 0:
					if not platform_match.resolve_zombie_breach(intent.actor_id, intent.cell).is_empty():
						platform_hits += 1
			platform_match.drain_events()
			platform_match.drain_transactions()
		check(platform_zombie.feet().x > 10 and platform_hits > 0, "wide platform receives actual approach and local exposed-block breach")
	# A real narrow tower, with an ordinary safe lower sector and physical support.
	var tower_data: VoxelData = _flat(Vector3i(32, 16, 32))
	tower_data.seed_box(Vector3i(18, 4, 16), Vector3i(19, 10, 17), 0x01aabbaa)
	var tower_match: MatchSimulation = _match(tower_data)
	var elevated_owner: SharedPlayerState = _owner(tower_match, Vector3(18.5, 10.01, 16.5))
	var tower_director: ZombieDirector = DIRECTOR.new()
	tower_director.configure(tower_data, {"spawn_sectors":[Vector3(4.5, 4.01, 16.5)]}, ids)
	var candidate: Dictionary = tower_director.choose_spawn(tower_match, 1, 12)
	check(candidate.ok and candidate.route_valid, "high player permits a proven safe ground approach and spawn")
	if not candidate.ok:
		return
	var tower_zombie: SharedPlayerState = _zombie(tower_match, 2, candidate.point)
	var receipts: int = 0
	var last_hit: int = -90
	var exposed_only: bool = true
	for tick: int in range(720):
		var inputs: Dictionary = tower_director.commands(tower_match)
		var proposals: Array[Dictionary] = tower_director.drain_attack_intents()
		tower_match.step_fixed(inputs)
		for intent: Dictionary in proposals:
			if intent.kind != "breach":
				continue
			var endpoint: Vector3 = Vector3(intent.cell) + Vector3.ONE * .5
			var origin: Vector3 = tower_zombie.feet() + Vector3.UP * 1.1
			var ray: Dictionary = tower_data.cast_voxel(origin, endpoint - origin, origin.distance_to(endpoint) + .1)
			exposed_only = exposed_only and intent.cell.y > 1 and MatchSimulation.in_reach(tower_zombie, intent.cell) and ray.hit and ray.cell == intent.cell
			if tick >= last_hit + 90 and not tower_match.resolve_zombie_breach(intent.actor_id, intent.cell).is_empty():
				receipts += 1
				last_hit = tick
		tower_match.drain_events()
		tower_match.drain_transactions()
	check(receipts >= 3 and exposed_only, "high-target fallback gives reachable exposed support/front blocks to common damage authority")
	check(tower_data.get_block(Vector3i(18, 1, 16)) != 0 and tower_data.get_block(Vector3i(18, 3, 16)) != 0, "fallback preserves protected bedrock and does not dig remote floor")
	check(elevated_owner.feet().y < 10 and elevated_owner.health > 0, "real local support destruction lowers the tower occupant without teleport or phantom damage")
