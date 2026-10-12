class_name ZombieDirector
extends RefCounted
## Pursuit produces ordinary movement plus attack intents. The session alone owns
## windups, damage, cell hit limits, death and map transactions. No source spade fire.
const NAVIGATION = preload("res://ai/zombie_navigation.gd")
const RULES = preload("res://simulation/player_rules.gd")
const OWNER_ID: int = 1
const MAX_ZOMBIES: int = 12
const MAX_SPAWN_CANDIDATES: int = 12
const REPLAN_TICKS: int = 60
const RETRY_TICKS: int = 30
const NO_CELL: Vector3i = Vector3i(-1, -1, -1)
const TURN_PER_TICK: float = .085
const MOVE_GAIN: float = .4 # Shared ground movement: approximately3.2units/s.

class Brain extends RefCounted:
	var actor_id: int = 0
	var generation: int = -1
	var sequence: int = 0
	var path: Array[Vector3] = []
	var path_index: int = 0
	var goal: Vector3 = Vector3.INF
	var mode: String = "detour"
	var chosen_mode: String = "detour"
	var choice_locked: bool = false
	var choice_rolls: int = 0
	var choice_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var elevated_goal: bool = false
	var loadout_generation: int = -1
	var zombie_type: String = "walker"
	var can_throw: bool = false
	var throw_intents: int = 0
	var state: String = "waiting"
	var planned_tick: int = -10000
	var map_sequence: int = -1
	var last_position: Vector3 = Vector3.INF
	var progress_position: Vector3 = Vector3.INF
	var progress_tick: int = 0
	var distance_moved: float = 0.0
	var detour_seconds: float = INF
	var breach_seconds: float = INF
	var segment_ok: bool = false
	var segment_index: int = -1
	var segment_sequence: int = -1
	var segment_tick: int = -10000
	var decisions: int = 0
	var breach_intents: int = 0
	var bite_intents: int = 0
	var move_commands: int = 0

var _data: VoxelData
var _arena: Dictionary = {}
var _brains: Array[Brain] = []
var _navigation: ZombieNavigation = NAVIGATION.new()
var _attack_intents: Array[Dictionary] = []
var _planning_cursor: int = 0
var _spawn_cursor: int = 0
var _spawn_checks: int = 0
var _last_command_tick: int = -2

func configure(data: VoxelData, arena: Dictionary, actor_ids: Array[int]) -> void:
	_data = data
	_arena = arena.duplicate(true)
	_navigation.configure(data, arena)
	_brains.clear()
	_attack_intents.clear()
	_planning_cursor = 0
	_spawn_cursor = 0
	_spawn_checks = 0
	_last_command_tick = -2
	for id: int in actor_ids:
		if id <= OWNER_ID or _brain_for(id) != null or _brains.size() >= MAX_ZOMBIES:
			continue
		var brain: Brain = Brain.new()
		brain.actor_id = id
		_brains.append(brain)

func _brain_for(id: int) -> Brain:
	for brain: Brain in _brains:
		if brain.actor_id == id:
			return brain
	return null

func set_zombie_loadout(id: int, generation: int, type: String, can_throw: bool) -> void:
	# The authoritative session supplies per-life role/capacity, never the renderer.
	var brain: Brain = _brain_for(id)
	if brain == null or generation < 1:
		return
	brain.loadout_generation = generation
	brain.zombie_type = "grenadier" if type == "grenadier" else "walker"
	brain.can_throw = can_throw and brain.zombie_type == "grenadier"

func choose_spawn(simulation: MatchSimulation, owner_id: int = OWNER_ID,
		min_distance: float = 12.0) -> Dictionary:
	if simulation == null or simulation.data != _data:
		return {"ok":false, "error":"unconfigured"}
	var owner: SharedPlayerState = simulation.get_actor(owner_id)
	if owner == null or not owner.is_alive():
		return {"ok":false, "error":"owner_inactive"}
	_navigation.begin_tick(simulation.tick + 1)
	if not _navigation.can_plan():
		return {"ok":false, "error":"budget_deferred"}
	var sectors: Array = _arena.get("spawn_sectors", [])
	if sectors.is_empty():
		return {"ok":false, "error":"no_safe_point"}
	var chosen: Vector3 = Vector3.INF
	var chosen_index: int = -1
	var hidden: bool = false
	var best: float = -INF
	for offset: int in range(mini(MAX_SPAWN_CANDIDATES, sectors.size())):
		_spawn_checks += 1
		var index: int = (_spawn_cursor + offset) % sectors.size()
		var value: Variant = sectors[index]
		if typeof(value) != TYPE_VECTOR3:
			continue
		var point: Vector3 = value
		if not _navigation.can_stand(point) or not simulation._spawn_clear(point) \
				or point.distance_squared_to(owner.feet()) < min_distance * min_distance:
			continue
		var concealed: bool = not _line_clear(owner.motion.physics_eye(), point + Vector3.UP * 1.35)
		# Rotate equally suitable sectors, and prefer concealed emergence.
		var score: float = (10000.0 if concealed else 0.0) - offset
		if score > best:
			best = score
			chosen = point
			chosen_index = index
			hidden = concealed
	if chosen_index < 0:
		return {"ok":false, "error":"no_safe_point"}
	_spawn_cursor = (chosen_index + 1) % sectors.size()
	var route: Dictionary = _navigation.plan(chosen, owner.feet(), simulation)
	if not bool(route.get("ok", false)):
		return {"ok":false, "error":route.get("status", "no_route"), "route_valid":false}
	return {"ok":true, "point":chosen, "hidden":hidden, "route_valid":true, "map_sequence":_data.map_sequence}

func route_valid(start: Vector3, goal: Vector3, simulation: MatchSimulation) -> Dictionary:
	_navigation.begin_tick(simulation.tick + 1)
	var route: Dictionary = _navigation.plan(start, goal, simulation)
	return {"ok":bool(route.get("ok", false)), "status":route.get("status", "unreachable")}

func commands(simulation: MatchSimulation) -> Dictionary:
	var output: Dictionary = {}
	_attack_intents.clear()
	if simulation == null or simulation.data != _data:
		return output
	var tick: int = simulation.tick + 1
	_navigation.begin_tick(tick)
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
	if owner == null or not owner.is_alive():
		return output
	var crowd: Dictionary[Vector2i, int] = {}
	for brain: Brain in _brains:
		var actor: SharedPlayerState = simulation.get_actor(brain.actor_id)
		if actor == null or not actor.is_alive():
			brain.state = "inactive"
			continue
		if brain.generation != actor.spawn_generation:
			_reset_life(brain, actor, tick)
		var feet: Vector3 = actor.feet()
		if _last_command_tick != tick and brain.last_position.is_finite():
			brain.distance_moved += minf(1.0, feet.distance_to(brain.last_position))
		brain.last_position = feet
		if not brain.progress_position.is_finite() or feet.distance_squared_to(brain.progress_position) > .25:
			brain.progress_position = feet
			brain.progress_tick = tick
		var column: Vector2i = Vector2i(floori(feet.x), floori(feet.z))
		crowd[column] = int(crowd.get(column, 0)) + 1
	# One fair planning job at most, irrespective of how many actors need a route.
	for offset: int in range(_brains.size()):
		var index: int = (_planning_cursor + offset) % _brains.size()
		var brain: Brain = _brains[index]
		var actor: SharedPlayerState = simulation.get_actor(brain.actor_id)
		if actor == null or not actor.is_alive() or not _navigation.can_plan():
			continue
		var moved_goal: bool = not brain.goal.is_finite() or brain.goal.distance_squared_to(owner.feet()) > 4.0
		var changed_map: bool = brain.map_sequence != _data.map_sequence
		var age: int = tick - brain.planned_tick
		if age < RETRY_TICKS or (age < REPLAN_TICKS and not moved_goal and not changed_map):
			continue
		var obstacle: bool = _navigation.has_direct_obstacle(actor.feet(), owner.feet())
		if obstacle and not brain.choice_locked:
			brain.chosen_mode = "breach" if brain.choice_rng.randi() % 2 == 0 else "detour"
			brain.choice_locked = true
			brain.choice_rolls += 1
		elif not obstacle:
			brain.choice_locked = false
			brain.chosen_mode = "detour"
		var route: Dictionary = _navigation.plan(actor.feet(), owner.feet(), simulation, brain.chosen_mode, crowd)
		brain.decisions += 1
		brain.planned_tick = tick
		brain.goal = owner.feet()
		brain.map_sequence = _data.map_sequence
		brain.path.clear()
		brain.path_index = 0
		brain.segment_index = -1
		if bool(route.get("ok", false)):
			brain.path.assign(route.path)
			# The source center can be behind an already moving actor. A replan
			# starts at its next safe edge rather than repeatedly walking backward.
			if brain.path.size() > 1 and _navigation.segment_clear(actor.feet(), brain.path[1]):
				brain.path_index = 1
			brain.mode = route.mode
			brain.elevated_goal = route.elevated_goal
			brain.detour_seconds = route.detour_seconds
			brain.breach_seconds = route.breach_seconds
			brain.state = brain.mode
		else:
			brain.state = String(route.get("status", "unreachable"))
		_planning_cursor = (index + 1) % _brains.size()
		break
	for brain: Brain in _brains:
		var actor: SharedPlayerState = simulation.get_actor(brain.actor_id)
		if actor != null and actor.is_alive():
			output[brain.actor_id] = _command(brain, actor, owner, simulation, tick)
	_last_command_tick = tick
	return output

func _reset_life(brain: Brain, actor: SharedPlayerState, tick: int) -> void:
	brain.generation = actor.spawn_generation
	brain.sequence = actor.consumed_input_sequence
	brain.path.clear()
	brain.path_index = 0
	brain.goal = Vector3.INF
	brain.mode = "detour"
	brain.chosen_mode = "detour"
	brain.choice_locked = false
	brain.choice_rng.seed = int(_arena.get("zombie_seed", 71317)) + actor.player_id * 199 + actor.spawn_generation * 3571
	brain.elevated_goal = false
	brain.state = "waiting"
	brain.planned_tick = -10000
	brain.map_sequence = -1
	brain.segment_index = -1
	brain.segment_sequence = -1
	brain.segment_tick = -10000
	brain.segment_ok = false
	brain.last_position = actor.feet()
	brain.progress_position = actor.feet()
	brain.progress_tick = tick

func _command(brain: Brain, actor: SharedPlayerState, owner: SharedPlayerState,
		simulation: MatchSimulation, tick: int) -> PlayerRules.Command:
	var command: PlayerRules.Command = RULES.Command.new()
	brain.sequence = maxi(brain.sequence, actor.consumed_input_sequence) + 1
	command.sequence = brain.sequence
	command.spawn_generation = actor.spawn_generation
	command.tool = RULES.Tool.SPADE
	var direction: Vector3 = Vector3.ZERO
	var aim: Vector3 = owner.feet() + Vector3.UP * 1.25 - actor.motion.physics_eye()
	var elevated: bool = owner.feet().y > actor.feet().y + 1.1
	var frontal: Vector3i = _frontal_cell(actor, owner) if elevated else NO_CELL
	var throw_ready: bool = brain.zombie_type == "grenadier" and brain.can_throw \
		and brain.loadout_generation == actor.spawn_generation \
		and actor.feet().distance_squared_to(owner.feet()) >= 6.0 * 6.0 \
		and actor.feet().distance_squared_to(owner.feet()) <= 24.0 * 24.0 \
		and _line_clear(actor.feet() + Vector3.UP * 1.1, owner.feet() + Vector3.UP * 1.1)
	var bite_ready: bool = actor.feet().distance_squared_to(owner.feet()) <= 2.1 * 2.1 \
		and _line_clear(actor.feet() + Vector3.UP * 1.1, owner.feet() + Vector3.UP * 1.1)
	if throw_ready:
		brain.state = "throw"
		brain.throw_intents += 1
		_attack_intents.append({"actor_id":brain.actor_id, "kind":"throw", "target":owner.feet() + Vector3.UP * 1.1})
	elif frontal != NO_CELL:
		brain.state = "breach"
		brain.breach_intents += 1
		_attack_intents.append({"actor_id":brain.actor_id, "kind":"breach", "cell":frontal})
		aim = Vector3(frontal) + Vector3.ONE * .5 - actor.motion.physics_eye()
	elif bite_ready:
		brain.state = "bite"
		brain.bite_intents += 1
		_attack_intents.append({"actor_id":brain.actor_id, "kind":"bite"})
	elif not elevated and actor.feet().distance_squared_to(owner.feet()) < 4.0 * 4.0 \
			and _line_clear(actor.feet() + Vector3.UP * 1.1, owner.feet() + Vector3.UP * 1.1) \
			and not _navigation.has_direct_obstacle(actor.feet(), owner.feet()) \
			and _navigation.can_stand(owner.feet()):
		# Chase the actual moving bite boundary, not the last plan's old endpoint.
		direction = _forward_step(actor, _steer(actor, owner.feet()))
		brain.state = "approach"
	else:
		while brain.path_index < brain.path.size() and _waypoint_passed(actor, brain):
			brain.path_index += 1
		if brain.path_index < brain.path.size():
			var waypoint: Vector3 = brain.path[brain.path_index]
			var cells: Array[Vector3i] = _navigation.clearance_cells(waypoint)
			if not cells.is_empty():
				var cell: Vector3i = _accessible_cell(actor, cells) if brain.mode == "breach" and brain.map_sequence == _data.map_sequence else NO_CELL
				if brain.mode != "breach" or brain.map_sequence != _data.map_sequence:
					# A new obstacle gets a validated plan before the locked choice acts.
					brain.planned_tick = mini(brain.planned_tick, tick - RETRY_TICKS)
					brain.state = "replan"
				elif cell != NO_CELL:
					brain.state = "breach"
					brain.breach_intents += 1
					_attack_intents.append({"actor_id":brain.actor_id, "kind":"breach", "cell":cell})
					aim = Vector3(cell) + Vector3.ONE * .5 - actor.motion.physics_eye()
				else:
					direction = _forward_step(actor, _steer(actor, waypoint))
			else:
				var feet: Vector3 = actor.feet()
				feet.y = roundf(feet.y) + .01
				if brain.segment_index != brain.path_index or brain.segment_sequence != _data.map_sequence \
						or (tick + brain.actor_id) % 6 == 0 or tick - brain.segment_tick >= 6:
					brain.segment_ok = _navigation.segment_clear(feet, waypoint)
					brain.segment_index = brain.path_index
					brain.segment_sequence = _data.map_sequence
					brain.segment_tick = tick
				if brain.segment_ok:
					direction = _steer(actor, waypoint)
					brain.state = brain.mode
				else:
					# Try a safe forward axis around the corner. Never seek a stale
					# rear anchor merely because another plan is due.
					direction = _forward_step(actor, _steer(actor, waypoint))
					brain.planned_tick = mini(brain.planned_tick, tick - RETRY_TICKS)
	if direction.length_squared() > .0001:
		direction = _separate(actor, direction, simulation)
		brain.move_commands += 1
		if elevated:
			aim = direction # Avoid pitch-dependent slowdown while chasing a tower.
	if aim.length_squared() < .0001:
		aim = actor.front()
	command.yaw = wrapf(actor.yaw + clampf(angle_difference(actor.yaw, atan2(-aim.x, -aim.z)), -TURN_PER_TICK, TURN_PER_TICK), -PI, PI)
	command.pitch = clampf(move_toward(actor.pitch, asin(clampf(aim.normalized().y, -.95, .95)), TURN_PER_TICK), -PI * .49, PI * .49)
	var forward: Vector3 = Vector3(-sin(command.yaw), 0, -cos(command.yaw))
	var right: Vector3 = Vector3(cos(command.yaw), 0, -sin(command.yaw))
	command.move = Vector2(direction.dot(right), -direction.dot(forward)).limit_length(MOVE_GAIN)
	return command

static func _steer(actor: SharedPlayerState, target: Vector3) -> Vector3:
	var offset: Vector3 = target - actor.feet()
	offset.y = 0
	var velocity: Vector3 = Vector3(actor.motion.native_velocity.x, 0, actor.motion.native_velocity.z) * 32.0
	if offset.length_squared() < .000001:
		return Vector3.ZERO
	var toward: Vector3 = offset.normalized()
	var gain: float = clampf(offset.length() * 2.0 - maxf(0, velocity.dot(toward)) * .25, 0, MOVE_GAIN)
	return toward * gain

static func _waypoint_passed(actor: SharedPlayerState, brain: Brain) -> bool:
	var offset: Vector3 = actor.feet() - brain.path[brain.path_index]
	if absf(offset.y) > 1.3:
		return false
	offset.y = 0
	if offset.length_squared() < .45 * .45:
		return true
	if brain.path_index > 0 and offset.length_squared() < .75 * .75:
		var edge: Vector3 = brain.path[brain.path_index] - brain.path[brain.path_index - 1]
		edge.y = 0
		return offset.dot(edge) >= 0
	return false

func _forward_step(actor: SharedPlayerState, intended: Vector3) -> Vector3:
	if intended.length_squared() < .000001:
		return Vector3.ZERO
	var probe: Vector3 = actor.feet() + intended.normalized() * .25
	probe.y = roundf(actor.feet().y) + .01
	if _navigation.can_stand(probe):
		return intended
	if _navigation.can_climb_step(actor.feet(), actor.feet() + intended.normalized() * .8):
		# Shared motion handles a step and its partial support at the edge.
		# Requiring all four old-height corners would stop after auto-climb.
		return intended
	for axis: Vector3 in [Vector3(intended.x, 0, 0), Vector3(0, 0, intended.z)]:
		if axis.length_squared() < .000001:
			continue
		probe = actor.feet() + axis.normalized() * .25
		probe.y = roundf(actor.feet().y) + .01
		if _navigation.can_stand(probe):
			return axis
	return Vector3.ZERO

func _separate(actor: SharedPlayerState, intended: Vector3, simulation: MatchSimulation) -> Vector3:
	var avoid: Vector3 = Vector3.ZERO
	for brain: Brain in _brains:
		var other: SharedPlayerState = simulation.get_actor(brain.actor_id)
		if other == null or not other.is_alive() or other.player_id == actor.player_id:
			continue
		var delta: Vector3 = actor.feet() - other.feet()
		delta.y = 0
		var distance: float = delta.length()
		if distance >= 1.0:
			continue
		if distance < .001:
			delta = Vector3(0, 0, 1 if actor.player_id > other.player_id else -1)
			distance = .1
		avoid += delta.normalized() * (.18 * (1.0 - distance))
	if avoid.length_squared() < .000001:
		return intended
	var result: Vector3 = (intended + avoid.limit_length(.3)).limit_length(MOVE_GAIN)
	var backward: float = result.dot(intended.normalized())
	if backward < 0:
		result -= intended.normalized() * backward
	var probe: Vector3 = actor.feet() + result.normalized() * .3
	probe.y = roundf(actor.feet().y) + .01
	# Separation is steering, not displacement or a second movement authority.
	return result if _navigation.can_stand(probe) else intended

func _frontal_cell(actor: SharedPlayerState, owner: SharedPlayerState) -> Vector3i:
	var toward: Vector3 = owner.feet() - actor.feet()
	toward.y = 0
	if toward.length_squared() < .01:
		toward = actor.front()
		toward.y = 0
	if toward.length_squared() < .0001:
		return NO_CELL
	for height: float in [1.1, .35, 2.1]:
		var hit: Dictionary = _data.cast_voxel(actor.feet() + Vector3.UP * height, toward, 2.8)
		if not bool(hit.hit) or hit.cell.y <= 1:
			continue
		var candidates: Array[Vector3i] = [hit.cell]
		var exposed: Vector3i = _accessible_cell(actor, candidates)
		if exposed != NO_CELL:
			return exposed
	return NO_CELL

func _accessible_cell(actor: SharedPlayerState, cells: Array[Vector3i]) -> Vector3i:
	var eye: Vector3 = actor.feet() + Vector3.UP * 1.1
	for cell: Vector3i in cells:
		var center: Vector3 = Vector3(cell) + Vector3.ONE * .5
		var delta: Vector3 = center - eye
		if cell.y <= 1 or not MatchSimulation.in_reach(actor, cell):
			continue
		var hit: Dictionary = _data.cast_voxel(eye, delta, delta.length() + .1)
		if bool(hit.hit) and cells.has(hit.cell) and hit.cell.y > 1:
			return hit.cell
	return NO_CELL

func _line_clear(origin: Vector3, target: Vector3) -> bool:
	var delta: Vector3 = target - origin
	return delta.length_squared() < .001 or not bool(_data.cast_voxel(origin, delta, maxf(0, delta.length() - .05)).hit)

func drain_attack_intents() -> Array[Dictionary]:
	var result: Array[Dictionary] = _attack_intents.duplicate(true)
	_attack_intents.clear()
	return result

func get_diagnostics() -> Dictionary:
	var rows: Array[Dictionary] = []
	var stalled_ids: Array[int] = []
	var result: Dictionary = {"bot_count":_brains.size(), "decisions":0,
		"move_commands":0, "bite_intents":0, "breach_intents":0,
		"throw_intents":0,
		"spawn_checks":_spawn_checks, "navigation":_navigation.get_statistics()}
	for brain: Brain in _brains:
		rows.append({"actor_id":brain.actor_id, "state":brain.state, "mode":brain.mode,
			"zombie_type":brain.zombie_type, "loadout_generation":brain.loadout_generation,
			"can_throw":brain.can_throw, "throw_intents":brain.throw_intents,
			"chosen_mode":brain.chosen_mode, "choice_rolls":brain.choice_rolls, "choice_locked":brain.choice_locked,
			"elevated_goal":brain.elevated_goal,
			"generation":brain.generation, "distance_moved":brain.distance_moved,
			"progress_tick":brain.progress_tick, "path_size":brain.path.size(),
			"path_index":brain.path_index, "detour_seconds":brain.detour_seconds,
			"breach_seconds":brain.breach_seconds})
		if _last_command_tick - brain.progress_tick >= 1200 and brain.state not in ["inactive", "bite", "breach"]:
			stalled_ids.append(brain.actor_id)
		for key: String in ["decisions", "move_commands", "bite_intents", "breach_intents", "throw_intents"]:
			result[key] += brain.get(key)
	result.bots = rows
	result.stalled_ids = stalled_ids
	return result
