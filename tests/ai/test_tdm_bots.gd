extends SceneTree
## Pure-data AI behavioral checks. Presentation and actual-Main checks are separate.
const ARENA = preload("res://ai/tdm_arena.gd")
const NAV = preload("res://ai/tdm_voxel_navigation.gd")
const DIRECTOR = preload("res://ai/tdm_bot_director.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("TDM AI: " + message)

func _run() -> void:
	_arena_and_navigation()
	_perception_memory()
	_match_slice()
	print("TDM AI: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _arena_and_navigation() -> void:
	var data: VoxelData = ARENA.build()
	var metadata: Dictionary = ARENA.metadata()
	var navigation: TdmVoxelNavigation = NAV.new()
	navigation.configure(data)
	check(data.dimensions == Vector3i(80, 24, 56), "bounded authored arena dimensions")
	check(data.map_sequence == 0 and data.last_tick == 0, "arena bootstrap produces no gameplay transaction")
	var spawns: Array = metadata.team_spawns
	for team: int in range(2):
		check(spawns[team].size() >= 3, "three team spawn positions")
		for feet: Vector3 in spawns[team]:
			check(navigation.can_stand(feet), "spawn supports full source player height")
	var path: Array[Vector3] = navigation.get_path(spawns[0][0], spawns[1][0])
	check(path.size() > 60, "path traverses arena around high cover")
	for point: Vector3 in path:
		check(navigation.can_stand(point), "path graph uses supported and unobstructed actor positions")
	if path.size() < 4:
		return
	var blocked: Vector3 = path[3]
	var edit: Dictionary = {}
	for height: int in range(4, 7):
		edit = data.set_block(Vector3i(floori(blocked.x), height, floori(blocked.z)), 0x01ab7755, {"tick":1})
	check(edit.ok and edit.changed, "dynamic route obstacle commits a real edit")
	navigation.refresh()
	check(navigation.get_statistics().invalidated_columns > 0, "terrain journal invalidates affected navigation columns")
	check(not navigation.segment_clear(path[2], blocked), "live segment recheck rejects newly blocked route")
	var changed: Array[Vector3] = navigation.get_path(spawns[0][0], spawns[1][0])
	check(not changed.is_empty(), "bounded A star finds a changed route")

func _spawn(simulation: MatchSimulation, id: int, team: int, feet: Vector3, weapon: int) -> SharedPlayerState:
	var admitted: Dictionary = simulation.add_actor("Bot %d" % id, 2, id * 37, Vector3.INF, id)
	check(admitted.ok, "actor admitted")
	check(simulation.spawn_actor(id, team, weapon, feet).ok, "actor gets distinct safe shared-authority spawn")
	var actor: SharedPlayerState = simulation.get_actor(id)
	actor.yaw = -PI * .5 if team == 0 else PI * .5
	actor.tool_raise = 1.0
	return actor

func _perception_memory() -> void:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(32, 16, 32))
	data.seed_box(Vector3i.ZERO, Vector3i(32, 4, 32), 0x01667755)
	var simulation: MatchSimulation = MATCH.new()
	check(simulation.configure(data).ok, "perception fixture configured")
	var owner: SharedPlayerState = _spawn(simulation, 2, 0, Vector3(10.5, 4, 16.5), 0)
	var target: SharedPlayerState = _spawn(simulation, 4, 1, Vector3(22.5, 4, 16.5), 0)
	var director: TdmBotDirector = DIRECTOR.new()
	var ids: Array[int] = [2]
	director.configure(data, ids, {"rally_points":[Vector3(16.5, 4, 16.5), Vector3(16.5, 4, 16.5)]})
	var inputs: Dictionary = director.commands(simulation)
	var first: Dictionary = director.get_diagnostics().bots[0]
	check(first.visible and first.target_id == 4, "FOV and terrain rays acquire visible enemy")
	check(first.reaction_tick >= 14, "enemy acquisition waits before fire")
	check(inputs[2].buttons & PlayerRules.Buttons.PRIMARY == 0, "reaction delay blocks instant shot")
	check(owner.magazine == 10 and target.health == 100, "decision generation never applies damage or changes inventory")
	var memory: Vector3 = first.memory_position
	# A tall wall and a moved hidden target test observations, independent of rendering.
	data.seed_box(Vector3i(17, 4, 8), Vector3i(19, 9, 25), 0x01bbaabb)
	data.set_block(Vector3i(17, 4, 8), 0x01aabbcc)
	target.motion.feet_position = Vector3(25.5, 4, 20.5)
	for tick: int in range(48):
		simulation.step_fixed(director.commands(simulation))
		simulation.drain_events()
		simulation.drain_transactions()
	var hidden: Dictionary = director.get_diagnostics().bots[0]
	check(not hidden.visible, "new terrain occludes target")
	check(hidden.memory_position.is_equal_approx(memory), "hidden moving target does not update remembered position")
	check(target.health == 100, "occluded target receives no AI damage shortcut")

func _match_slice() -> void:
	var data: VoxelData = ARENA.build()
	var metadata: Dictionary = ARENA.metadata()
	var simulation: MatchSimulation = MATCH.new()
	check(simulation.configure(data).ok, "compact combat authority configured")
	simulation.friendly_fire = false
	var spawns: Array = metadata.team_spawns
	var weapons: Array[int] = [0, 1, 2, 0, 1, 2]
	for id: int in range(1, 7):
		var team: int = 0 if id <= 3 else 1
		_spawn(simulation, id, team, spawns[team][(id - 1) % 3], weapons[id - 1])
	var director: TdmBotDirector = DIRECTOR.new()
	var ids: Array[int] = [2, 3, 4, 5, 6]
	director.configure(data, ids, metadata)
	var shots: int = 0
	var hits: int = 0
	for tick: int in range(1200):
		var inputs: Dictionary = director.commands(simulation)
		for id: int in inputs:
			check(inputs[id].valid(), "bot emits valid shared typed command")
		var events: Array[Dictionary] = simulation.step_fixed(inputs)
		shots += MatchSimulation.events_of(events, "shot").size()
		hits += MatchSimulation.events_of(events, "hit_confirmed").size()
		simulation.drain_events()
		simulation.drain_transactions()
	var diagnostics: Dictionary = director.get_diagnostics()
	check(diagnostics.bot_count == 5, "exactly five bots managed alongside human actor")
	check(diagnostics.flank_decisions > 0, "shotgun roles choose authored flank route")
	check(diagnostics.cover_decisions > 0, "combat/reload chooses occluded cover")
	check(diagnostics.navigation.path_requests > 0, "movement uses bounded voxel navigation")
	check(diagnostics.fire_commands > 0 and shots > 0, "bot triggers produce actual shared-authority shots")
	check(hits > 0, "imperfect AI aim can hit through the common weapon rules")
	for record: Dictionary in diagnostics.bots:
		check(record.distance_moved > 2.0, "every bot travels before combat or death")
