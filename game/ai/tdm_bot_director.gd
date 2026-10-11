class_name TdmBotDirector
extends RefCounted
## Original offline team AI. All motion, tools, bullets and damage use PlayerRules.
## Visible observations and noisy gunshot hints are copied into bounded memory;
## an occluded target's live coordinates are never used for chase or aiming.

const NAV = preload("res://ai/tdm_voxel_navigation.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const THINK_INTERVAL: int = 8
const MEMORY_TICKS: int = 240
const SIGHT_RANGE: float = 58.0
const FOV_DOT: float = .38268343 # 135 degrees total.
const TURN_PER_TICK: float = .062

class Brain extends RefCounted:
	var actor_id: int = 0
	var role: String = "attacker"
	var state: String = "advance"
	var sequence: int = 0
	var generation: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var goal: Vector3 = Vector3.INF
	var path: Array[Vector3] = []
	var path_index: int = 0
	var planned_goal: Vector3 = Vector3.INF
	var path_tick: int = -1000
	var path_sequence: int = 0
	var alignment: Vector3 = Vector3.INF
	var route_index: int = 0
	var patrol_side: int = 1
	var target_id: int = 0
	var visible: bool = false
	var last_known: Vector3 = Vector3.INF
	var last_seen_tick: int = -1000
	var memory_until: int = -1
	var reaction_tick: int = 0
	var noise_tick: int = -1
	var aim_error: Vector3 = Vector3.ZERO
	var last_position: Vector3 = Vector3.INF
	var progress_position: Vector3 = Vector3.INF
	var progress_tick: int = 0
	var dig_until: int = -1
	var dig_position: Vector3 = Vector3.INF
	var health: int = 100
	var action_tick: int = -1000
	var cover_until: int = -1
	var decisions: int = 0
	var perception_updates: int = 0
	var move_commands: int = 0
	var fire_commands: int = 0
	var reload_commands: int = 0
	var dig_commands: int = 0
	var cover_decisions: int = 0
	var flank_decisions: int = 0
	var distance_moved: float = 0.0

var _data: VoxelData
var _arena: Dictionary = {}
var _brains: Array[Brain] = []
var _navigation: TdmVoxelNavigation = NAV.new()

func configure(data: VoxelData, bot_ids: Array[int], arena: Dictionary) -> void:
	_data = data
	_arena = arena.duplicate(true)
	_brains.clear()
	_navigation.configure(data, int(arena.get("navigation_ceiling", 12)))
	for id: int in bot_ids:
		if id <= 0 or _brain_for(id) != null:
			continue
		var brain: Brain = Brain.new()
		brain.actor_id = id
		brain.rng.seed = 71317 + id * 199
		_brains.append(brain)

func _brain_for(id: int) -> Brain:
	for brain: Brain in _brains:
		if brain.actor_id == id:
			return brain
	return null

func commands(simulation: MatchSimulation) -> Dictionary:
	var output: Dictionary = {}
	if simulation == null or simulation.data != _data:
		return output
	_navigation.refresh()
	var tick: int = simulation.tick + 1
	for brain: Brain in _brains:
		var actor: SharedPlayerState = simulation.get_actor(brain.actor_id)
		if actor == null or not actor.is_alive() or not actor.connected:
			brain.state = "dead"
			brain.visible = false
			continue
		if brain.generation != actor.spawn_generation:
			_reset_life(brain, actor, tick)
		var feet: Vector3 = _ground_feet(actor)
		if brain.last_position.is_finite():
			brain.distance_moved += minf(1.0, feet.distance_to(brain.last_position))
		brain.last_position = feet
		if (tick + actor.player_id * 3) % THINK_INTERVAL == 0 or not brain.goal.is_finite():
			_decide(brain, actor, simulation, tick)
		output[actor.player_id] = _command(brain, actor, simulation, tick)
	return output

static func _ground_feet(actor: SharedPlayerState) -> Vector3:
	return actor.feet() - Vector3.UP * (.9 if actor.motion.crouch else 0.0)

func _reset_life(brain: Brain, actor: SharedPlayerState, tick: int) -> void:
	brain.generation = actor.spawn_generation
	brain.sequence = actor.consumed_input_sequence
	brain.role = "defender" if actor.weapon == 0 else ("flanker" if actor.weapon == 2 else "attacker")
	brain.state = "advance"
	brain.goal = Vector3.INF
	brain.path.clear()
	brain.planned_goal = Vector3.INF
	brain.path_tick = -1000
	brain.path_index = 0
	brain.alignment = Vector3.INF
	brain.route_index = 0
	brain.patrol_side = 1 if actor.player_id % 2 == 0 else -1
	brain.target_id = 0
	brain.visible = false
	brain.last_known = Vector3.INF
	brain.last_seen_tick = -1000
	brain.memory_until = -1
	brain.reaction_tick = tick
	brain.noise_tick = -1
	brain.last_position = _ground_feet(actor)
	brain.progress_position = brain.last_position
	brain.progress_tick = tick
	brain.dig_until = -1
	brain.cover_until = -1
	brain.health = actor.health

func _line_clear(origin: Vector3, target: Vector3) -> bool:
	var delta: Vector3 = target - origin
	if delta.length_squared() < .001:
		return true
	return not bool(_data.cast_voxel(origin, delta, maxf(0, delta.length() - .15)).hit)

func _sees(actor: SharedPlayerState, target: SharedPlayerState) -> bool:
	var eye: Vector3 = actor.motion.physics_eye()
	var torso: Vector3 = target.feet() + Vector3.UP * (1.05 if target.motion.crouch else 1.35)
	var delta: Vector3 = torso - eye
	if delta.length_squared() > SIGHT_RANGE * SIGHT_RANGE or delta.length_squared() < .0001:
		return false
	if actor.front().dot(delta.normalized()) < FOV_DOT and delta.length_squared() > 16.0:
		return false
	return _line_clear(eye, torso) or _line_clear(eye, target.motion.physics_eye())

func _observe(brain: Brain, actor: SharedPlayerState, simulation: MatchSimulation, tick: int) -> void:
	brain.perception_updates += 1
	brain.visible = false
	var selected: SharedPlayerState = null
	var best: float = INF
	var heard: SharedPlayerState = null
	var heard_distance: float = 27.0 * 27.0
	for id: int in simulation.actors:
		var candidate: SharedPlayerState = simulation.get_actor(id)
		if candidate == null or candidate.team == actor.team or not candidate.connected or not candidate.is_alive():
			continue
		if _sees(actor, candidate):
			var distance: float = actor.feet().distance_squared_to(candidate.feet())
			if id == brain.target_id:
				distance *= .75
			if distance < best:
				best = distance
				selected = candidate
		# Sound creates a coarse location once per new shot, not tracking through walls.
		elif candidate.last_shot_tick > brain.noise_tick and candidate.last_shot_tick >= tick - 12:
			var distance: float = actor.feet().distance_squared_to(candidate.feet())
			if distance < heard_distance:
				heard_distance = distance
				heard = candidate
	if selected != null:
		if brain.target_id != selected.player_id or brain.memory_until < tick or brain.last_seen_tick < 0:
			brain.reaction_tick = tick + brain.rng.randi_range(14, 24)
		brain.target_id = selected.player_id
		brain.visible = true
		brain.last_known = selected.feet() + Vector3.UP * (1.05 if selected.motion.crouch else 1.35)
		brain.last_seen_tick = tick
		brain.memory_until = tick + MEMORY_TICKS
		# Deliberately imperfect, locally seeded perception; no change to weapon spread.
		var error: float = .22 + minf(.32, sqrt(best) * .006)
		brain.aim_error = Vector3(brain.rng.randf_range(-error, error),
			brain.rng.randf_range(-.13, .13), brain.rng.randf_range(-error, error))
	elif heard != null:
		brain.target_id = heard.player_id
		brain.noise_tick = heard.last_shot_tick
		brain.last_known = heard.feet() + Vector3(brain.rng.randf_range(-4, 4), 1.35, brain.rng.randf_range(-4, 4))
		brain.memory_until = tick + 110
	elif tick > brain.memory_until:
		brain.target_id = 0
		brain.last_known = Vector3.INF

func _decide(brain: Brain, actor: SharedPlayerState, simulation: MatchSimulation, tick: int) -> void:
	brain.decisions += 1
	_observe(brain, actor, simulation, tick)
	var feet: Vector3 = _ground_feet(actor)
	var info: Dictionary = PROFILES.get_info(actor.profile, actor.weapon)
	if actor.reserve <= 0 and actor.magazine <= 2:
		var spawns: Array = _arena.get("team_spawns", [])
		var home: Vector3 = Vector3.INF
		var distance: float = INF
		if spawns.size() > actor.team:
			for spawn: Vector3 in spawns[actor.team]:
				if feet.distance_squared_to(spawn) < distance:
					distance = feet.distance_squared_to(spawn)
					home = spawn
		if home.is_finite():
			brain.goal = home
			brain.state = "resupply"
			_plan(brain, feet, tick)
			return
	var needs_reload: bool = actor.reloading or actor.magazine <= 0 \
		or (actor.magazine <= maxi(1, int(info.clip_size) >> 2) and not brain.visible)
	var hurt: bool = actor.health < brain.health
	brain.health = actor.health
	var threatened: bool = brain.last_known.is_finite() and ((actor.health <= 35 and tick > brain.cover_until + 180) or (hurt and actor.health <= 60))
	if needs_reload or threatened:
		var cover: Vector3 = _cover(brain, feet, brain.last_known)
		if cover.is_finite():
			if brain.state not in ["reload", "cover"] or brain.goal.distance_squared_to(cover) > 1.0:
				brain.cover_decisions += 1
			brain.goal = cover
			brain.cover_until = tick + 120
			brain.state = "reload" if needs_reload else "cover"
		else:
			brain.goal = feet
			brain.state = "reload" if needs_reload else "fight"
		_plan(brain, feet, tick)
		return
	if brain.state == "cover" and tick < brain.cover_until:
		_plan(brain, feet, tick)
		return
	if brain.role == "flanker" and brain.route_index < 3:
		var routes: Array = _arena.get("flank_routes", [])
		if routes.size() > actor.team:
			var route: Array = routes[actor.team]
			while brain.route_index < route.size() and feet.distance_squared_to(route[brain.route_index]) < 9.0:
				brain.route_index += 1
			if brain.route_index < route.size() and (not brain.visible or feet.distance_to(brain.last_known) > 15):
				if brain.state != "flank" or brain.goal != route[brain.route_index]:
					brain.flank_decisions += 1
				brain.goal = route[brain.route_index]
				brain.state = "flank"
				_plan(brain, feet, tick)
				return
	if brain.last_known.is_finite():
		var remembered_feet: Vector3 = brain.last_known - Vector3.UP * 1.35
		if not brain.visible:
			brain.goal = remembered_feet
			brain.state = "search"
		elif tick - brain.action_tick >= 60 or brain.state not in ["fight", "peek"]:
			brain.action_tick = tick
			var away: Vector3 = feet - remembered_feet
			away.y = 0
			var distance: float = away.length()
			var preferred: float = [25.0, 17.0, 10.0][actor.weapon]
			if distance > preferred + 3:
				brain.goal = remembered_feet + away.normalized() * preferred
			elif distance < preferred * .45:
				brain.goal = feet + away.normalized() * 4
			else:
				var side: Vector3 = Vector3(-away.z, 0, away.x).normalized()
				brain.goal = feet + side * brain.rng.randf_range(-2.8, 2.8)
			brain.state = "fight"
	else:
		var rallies: Array = _arena.get("rally_points", [])
		var rally: Vector3 = rallies[actor.team] if rallies.size() > actor.team else Vector3(40, 4, 28)
		if brain.role == "defender":
			rally.x += -5 if actor.team == 0 else 5
		if brain.state != "advance" or not brain.goal.is_finite():
			brain.goal = rally
		elif feet.distance_squared_to(brain.goal) < 4 and tick - brain.action_tick >= 120:
			# Hold the selected patrol target until arrival. Looking/moving toward
			# alternating sides exposes new sightlines without reading hidden actors.
			brain.goal = rally + Vector3(0, 0, 7 * brain.patrol_side)
			brain.patrol_side *= -1
			brain.action_tick = tick
		brain.state = "advance"
	_plan(brain, feet, tick)

func _cover(brain: Brain, feet: Vector3, threat: Vector3) -> Vector3:
	var best: float = INF
	var result: Vector3 = Vector3.INF
	var points: Array = _arena.get("cover_points", [])
	for point: Vector3 in points:
		var distance: float = feet.distance_squared_to(point)
		if distance > 24.0 * 24.0 or not _navigation.can_stand(point):
			continue
		if threat.is_finite() and (_line_clear(point + Vector3.UP * 2.25, threat) or point.distance_squared_to(threat) < 64):
			continue
		var score: float = distance
		if brain.goal.is_finite() and brain.goal.distance_squared_to(point) < 1:
			score *= .7
		if score < best:
			best = score
			result = point
	return result

func _plan(brain: Brain, feet: Vector3, tick: int) -> void:
	var changed: bool = not brain.planned_goal.is_finite() or brain.goal.distance_squared_to(brain.planned_goal) > 4.0
	if tick - brain.path_tick < 45 and not changed and brain.path_sequence == _data.map_sequence:
		return
	if tick - brain.path_tick < 12:
		return
	brain.path = _navigation.get_path(feet, brain.goal)
	brain.path_index = 0
	brain.path_tick = tick
	brain.path_sequence = _data.map_sequence
	brain.planned_goal = brain.goal

func _command(brain: Brain, actor: SharedPlayerState, simulation: MatchSimulation, tick: int) -> PlayerRules.Command:
	var command: PlayerRules.Command = RULES.Command.new()
	brain.sequence = maxi(brain.sequence, actor.consumed_input_sequence) + 1
	command.sequence = brain.sequence
	command.spawn_generation = actor.spawn_generation
	command.tool = RULES.Tool.WEAPON
	var feet: Vector3 = _ground_feet(actor)
	var direction: Vector3 = _path_direction(brain, actor, feet, tick)
	var aim: Vector3 = direction
	var has_aim: bool = brain.last_known.is_finite() and tick <= brain.memory_until
	if has_aim:
		aim = brain.last_known + brain.aim_error - actor.motion.physics_eye()
	if brain.dig_until > tick and brain.dig_position.is_finite():
		aim = brain.dig_position - actor.motion.physics_eye()
		command.tool = RULES.Tool.SPADE
		command.buttons |= RULES.Buttons.SECONDARY
		brain.dig_commands += 1
		brain.state = "dig"
	if aim.length_squared() < .001:
		aim = actor.front()
	var desired_yaw: float = atan2(-aim.x, -aim.z)
	var desired_pitch: float = asin(clampf(aim.normalized().y, -.98, .98))
	command.yaw = wrapf(actor.yaw + clampf(angle_difference(actor.yaw, desired_yaw), -TURN_PER_TICK, TURN_PER_TICK), -PI, PI)
	command.pitch = clampf(move_toward(actor.pitch, desired_pitch, TURN_PER_TICK), -PI * .49, PI * .49)
	if direction.length_squared() > .0004:
		var forward: Vector3 = Vector3(-sin(command.yaw), 0, -cos(command.yaw))
		var right: Vector3 = Vector3(cos(command.yaw), 0, -sin(command.yaw))
		command.move = Vector2(direction.dot(right), -direction.dot(forward)).limit_length(1.0)
		brain.move_commands += 1
		if brain.state in ["advance", "flank", "search", "resupply"] and not brain.visible and brain.dig_until <= tick:
			command.buttons |= RULES.Buttons.SPRINT
		if brain.path_index < brain.path.size() and brain.path[brain.path_index].y > feet.y + .45:
			command.buttons |= RULES.Buttons.JUMP
	var near_goal: bool = brain.goal.is_finite() and feet.distance_squared_to(brain.goal) < 4.0
	if brain.state in ["reload", "cover"] and near_goal:
		command.buttons |= RULES.Buttons.CROUCH
	var info: Dictionary = PROFILES.get_info(actor.profile, actor.weapon)
	if brain.state == "reload" and not actor.reloading and actor.magazine < int(info.clip_size) \
			and actor.reserve > 0 and (near_goal or tick - brain.path_tick > 120 or brain.path.is_empty()) and tick % 8 == 0:
		command.buttons |= RULES.Buttons.RELOAD
		brain.reload_commands += 1
	if brain.visible and has_aim and tick >= brain.reaction_tick and brain.state not in ["reload", "cover", "dig"]:
		# Aim uses only the latest copied visible sample. A fresh terrain ray gates fire.
		var front: Vector3 = Vector3(-sin(command.yaw) * cos(command.pitch), sin(command.pitch), -cos(command.yaw) * cos(command.pitch))
		var aim_distance: float = aim.length()
		var tolerance: float = .16 if actor.weapon == 2 else .065
		if front.dot(aim.normalized()) > cos(tolerance) and _line_clear(actor.motion.physics_eye(), brain.last_known):
			if not _friend_in_fire_lane(actor, simulation, front, aim_distance):
				command.buttons |= RULES.Buttons.PRIMARY
				if actor.weapon != 2 and aim_distance > 12:
					command.buttons |= RULES.Buttons.SECONDARY
				brain.fire_commands += 1
	return command

func _path_direction(brain: Brain, actor: SharedPlayerState, feet: Vector3, tick: int) -> Vector3:
	if brain.alignment.is_finite():
		var offset: Vector3 = brain.alignment - feet
		offset.y = 0
		if offset.length_squared() > .0009 and _navigation.can_stand(brain.alignment):
			var velocity: Vector3 = Vector3(actor.motion.native_velocity.x, 0, actor.motion.native_velocity.z) * 32.0
			return (offset * 1.3 - velocity * .25).limit_length(1.0)
		brain.alignment = Vector3.INF
	while brain.path_index < brain.path.size():
		var delta: Vector3 = brain.path[brain.path_index] - feet
		delta.y = 0
		if delta.length_squared() >= .4 * .4:
			break
		brain.path_index += 1
	if brain.path_index >= brain.path.size():
		return Vector3.ZERO
	var waypoint: Vector3 = brain.path[brain.path_index]
	var base: Vector3 = feet
	base.y = roundf(feet.y)
	if tick % 8 == actor.player_id % 8 and not _navigation.segment_clear(base, waypoint):
		# Source acceleration can carry an actor off a grid center at a corner.
		# Steer back onto the previous safe anchor before discarding the route;
		# otherwise replanning would choose and skip the same nearby anchor forever.
		var anchor: Vector3 = brain.path[maxi(0, brain.path_index - 1)]
		var correction: Vector3 = anchor - feet
		correction.y = 0
		if correction.length_squared() > .0009 and _navigation.can_stand(anchor):
			brain.alignment = anchor
			var velocity: Vector3 = Vector3(actor.motion.native_velocity.x, 0, actor.motion.native_velocity.z) * 32.0
			return (correction * 1.3 - velocity * .25).limit_length(1.0)
		brain.path_tick = -1000
		brain.path.clear()
		return Vector3.ZERO
	var direction: Vector3 = waypoint - feet
	direction.y = 0
	if tick - brain.progress_tick >= 75:
		if feet.distance_squared_to(brain.progress_position) < .3 * .3:
			# An authored short dig recovery, still normal spade range/timing/authority.
			var probe: Dictionary = _data.cast_voxel(actor.motion.physics_eye(), direction, 2.9)
			if probe.hit and probe.cell.y > 1 and not brain.visible:
				brain.dig_position = probe.position
				brain.dig_until = tick + 150
			brain.path_tick = -1000
		brain.progress_position = feet
		brain.progress_tick = tick
	return direction.normalized()

func _friend_in_fire_lane(actor: SharedPlayerState, simulation: MatchSimulation, front: Vector3, distance: float) -> bool:
	var eye: Vector3 = actor.motion.physics_eye()
	for id: int in simulation.actors:
		var friend: SharedPlayerState = simulation.get_actor(id)
		if friend == null or id == actor.player_id or friend.team != actor.team or not friend.is_alive():
			continue
		var delta: Vector3 = friend.feet() + Vector3.UP * 1.3 - eye
		var forward: float = delta.dot(front)
		if forward > 0 and forward < distance and (delta - front * forward).length_squared() < .75 * .75:
			return true
	return false

func get_diagnostics() -> Dictionary:
	var result: Dictionary = {"bot_count":_brains.size(), "decisions":0, "perception_updates":0,
		"move_commands":0, "fire_commands":0, "reload_commands":0, "dig_commands":0,
		"cover_decisions":0, "flank_decisions":0, "bots":[], "navigation":_navigation.get_statistics()}
	var bots: Array[Dictionary] = []
	for brain: Brain in _brains:
		var record: Dictionary = {"actor_id":brain.actor_id, "role":brain.role, "state":brain.state,
			"target_id":brain.target_id, "last_seen_tick":brain.last_seen_tick,
			"visible":brain.visible, "reaction_tick":brain.reaction_tick,
			"memory_position":brain.last_known, "goal":brain.goal, "spawn_generation":brain.generation,
			"distance_moved":brain.distance_moved, "decisions":brain.decisions,
			"perception_updates":brain.perception_updates, "move_commands":brain.move_commands,
			"fire_commands":brain.fire_commands, "reload_commands":brain.reload_commands,
			"dig_commands":brain.dig_commands, "cover_decisions":brain.cover_decisions,
			"flank_decisions":brain.flank_decisions}
		bots.append(record)
		for key: String in ["decisions", "perception_updates", "move_commands", "fire_commands", "reload_commands", "dig_commands", "cover_decisions", "flank_decisions"]:
			result[key] += record[key]
	result.bots = bots
	return result
