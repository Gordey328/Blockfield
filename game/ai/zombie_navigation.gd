class_name ZombieNavigation
extends RefCounted
## One pair of bounded A* searches per authority tick, shared by spawn and pursuit.
## Detour and breach are independently validated; the director chooses an encounter
## randomly. Estimated damage time is diagnostic and never selects the mode.
## This is a single-surface, authored-arena planner; it does not support stacked maps.
const MOTION = preload("res://gameplay/source_player_motion.gd")
const MAX_EXPANSIONS: int = 1800
const MAX_COLUMNS: int = 8192
const NEIGHBORS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _data: VoxelData
var _floor: int = 4
var _ceiling: int = 12
var _walk_speed: float = 3.2
var _breach_damage: float = 40.0
var _breach_cycle: float = 1.5
var _breach_windup: float = .75
var _sequence: int = -1
var _tick: int = -2
var _jobs_this_tick: int = 0
var _columns: Dictionary[Vector2i, Dictionary] = {}
var _stats: Dictionary = {}

func configure(data: VoxelData, arena: Dictionary) -> void:
	_data = data
	_floor = clampi(int(arena.get("floor_y", 4)), 2, data.dimensions.y - 3)
	_ceiling = clampi(int(arena.get("navigation_ceiling", 12)), 4, data.dimensions.y - 3)
	_walk_speed = clampf(float(arena.get("walk_speed", 3.2)), .5, 8.0)
	_breach_damage = maxf(1.0, float(arena.get("breach_damage", 40)))
	_breach_cycle = maxf(1.0 / 60.0, float(arena.get("breach_cycle_ticks", 90)) / 60.0)
	_breach_windup = maxf(0.0, float(arena.get("breach_windup_ticks", 45)) / 60.0)
	_sequence = data.map_sequence
	_tick = -2
	_jobs_this_tick = 0
	_columns.clear()
	_stats = {"plan_jobs":0, "searches":0, "expanded_nodes":0,
		"max_jobs_per_tick":0, "max_expansions_per_job":0,
		"budget_deferred":0, "exhausted_searches":0, "pruned_searches":0, "invalidations":0}

func begin_tick(tick: int) -> void:
	if tick != _tick:
		_tick = tick
		_jobs_this_tick = 0
	if _data != null and _sequence != _data.map_sequence:
		_columns.clear()
		_sequence = _data.map_sequence
		_stats.invalidations += 1

func can_plan() -> bool:
	return _data != null and _jobs_this_tick == 0

func can_stand(feet: Vector3) -> bool:
	if _data == null or not feet.is_finite() or feet.x < 1 or feet.z < 1 \
			or feet.x >= _data.dimensions.x - 1 or feet.z >= _data.dimensions.z - 1:
		return false
	for dx: float in [-.45, .45]:
		for dz: float in [-.45, .45]:
			if not MOTION.source_clip_box(_data, feet + Vector3(dx, -.05, dz)):
				return false
			for height: float in [.01, .9, 1.8, 2.7]:
				if MOTION.source_clip_box(_data, feet + Vector3(dx, height, dz)):
					return false
	return true

func clearance_cells(feet: Vector3) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dx: float in [-.45, .45]:
		for dz: float in [-.45, .45]:
			for y: int in range(floori(feet.y + .01), floori(feet.y + 2.7) + 1):
				var cell: Vector3i = Vector3i(floori(feet.x + dx), y, floori(feet.z + dz))
				if _data.get_block(cell) != 0 and not cells.has(cell):
					cells.append(cell)
	return cells

func _column(column: Vector2i) -> Dictionary:
	if column.x < 1 or column.y < 1 or column.x >= _data.dimensions.x - 1 \
			or column.y >= _data.dimensions.z - 1:
		return {}
	if _columns.has(column):
		return _columns[column]
	var point: Vector3 = Vector3.INF
	# Small steps remain normal movement. Tall cover is evaluated as a body-width
	# passage at the authored floor, rather than an impossible climb onto its roof.
	for height: int in range(mini(_floor + 1, _ceiling), 1, -1):
		var candidate: Vector3 = Vector3(column.x + .5, height + .01, column.y + .5)
		if _data.get_block(Vector3i(column.x, height - 1, column.y)) != 0:
			point = candidate
			if can_stand(candidate):
				break
			# A tall obstruction's base is the lower supported authored surface.
			if height > _floor:
				continue
			break
	var value: Dictionary = {}
	if point.is_finite():
		var cells: Array[Vector3i] = clearance_cells(point)
		var protected: bool = false
		for cell: Vector3i in cells:
			if cell.y <= 1:
				protected = true
		value = {"point":point, "cells":cells, "protected":protected}
	if _columns.size() < MAX_COLUMNS:
		_columns[column] = value
	return value

func _nearest(point: Vector3, radius: int, project_height: bool = false) -> Vector2i:
	var center: Vector2i = Vector2i(floori(point.x), floori(point.z))
	var result: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for dx: int in range(-radius, radius + 1):
		for dz: int in range(-radius, radius + 1):
			var column: Vector2i = center + Vector2i(dx, dz)
			var value: Dictionary = _column(column)
			if value.is_empty() or not value.cells.is_empty() or (not project_height and absf(value.point.y - point.y) > 2.1):
				continue
			var distance: float = point.distance_squared_to(value.point)
			if distance < best:
				best = distance
				result = column
	return result

func has_direct_obstacle(start: Vector3, goal: Vector3) -> bool:
	var horizontal: Vector2 = Vector2(goal.x - start.x, goal.z - start.z)
	var steps: int = clampi(ceili(horizontal.length()), 1, 128)
	for index: int in range(1, steps + 1):
		var sample: Vector3 = start.lerp(goal, float(index) / steps)
		var value: Dictionary = _column(Vector2i(floori(sample.x), floori(sample.z)))
		if value.is_empty() or not value.cells.is_empty():
			return true
	return false

func can_climb_step(start: Vector3, forward: Vector3) -> bool:
	var value: Dictionary = _column(Vector2i(floori(forward.x), floori(forward.z)))
	if value.is_empty() or not value.cells.is_empty():
		return false
	var rise: float = value.point.y - start.y
	return rise >= -2.1 and rise <= 1.1 and can_stand(value.point)

func segment_clear(start: Vector3, finish: Vector3) -> bool:
	if not start.is_finite() or not finish.is_finite() or start.distance_to(finish) > 3.0:
		return false
	var steps: int = maxi(1, ceili(start.distance_to(finish) / .25))
	var previous_height: float = start.y
	for index: int in range(steps + 1):
		var sample: Vector3 = start.lerp(finish, float(index) / steps)
		var column: Dictionary = _column(Vector2i(floori(sample.x), floori(sample.z)))
		if column.is_empty() or not column.cells.is_empty() or column.point.y - previous_height > 1.1 \
				or column.point.y - previous_height < -2.1:
			return false
		sample.y = column.point.y
		previous_height = sample.y
		if not can_stand(sample):
			return false
	return true

func plan(start: Vector3, goal: Vector3, simulation: MatchSimulation,
		preferred_mode: String = "detour", crowd: Dictionary = {}) -> Dictionary:
	if not can_plan():
		_stats.budget_deferred += 1
		return {"ok":false, "status":"budget_deferred"}
	_jobs_this_tick += 1
	_stats.plan_jobs += 1
	_stats.max_jobs_per_tick = maxi(_stats.max_jobs_per_tick, _jobs_this_tick)
	if not start.is_finite() or not goal.is_finite() or simulation == null or simulation.data != _data \
			or _data.dimensions.x * _data.dimensions.z > MAX_COLUMNS:
		return {"ok":false, "status":"unsupported"}
	var source: Vector2i = _nearest(start, 2)
	# A tower does not make the ground-level approach or all future spawns invalid.
	var destination: Vector2i = _nearest(goal, 2, true)
	if destination.x < 0:
		# A solid five-by-five platform can consume a normal fifty-block
		# inventory. Its safe lower approach may lie outside the first ring.
		destination = _nearest(goal, 8, true)
	if source.x < 0 or destination.x < 0:
		return {"ok":false, "status":"unreachable"}
	var before: int = int(_stats.expanded_nodes)
	var detour: Dictionary = _search(source, destination, simulation, false, crowd)
	var detour_seconds: float = float(detour.get("seconds", INF))
	var obstacle: bool = has_direct_obstacle(start, goal)
	var breach: Dictionary = _search(source, destination, simulation, true, crowd) if obstacle else \
		{"ok":false, "exhausted":false, "pruned":false, "seconds":INF}
	_stats.max_expansions_per_job = maxi(_stats.max_expansions_per_job, int(_stats.expanded_nodes) - before)
	var breach_seconds: float = float(breach.get("seconds", INF))
	var selected: Dictionary = detour
	if bool(breach.ok) and (not bool(detour.ok) or preferred_mode == "breach"):
		selected = breach
	if not bool(selected.ok):
		return {"ok":false, "status":"budget_exhausted" if detour.exhausted or breach.exhausted else "unreachable"}
	selected.mode = "breach" if selected == breach else "detour"
	selected.status = "valid"
	selected.detour_seconds = detour_seconds
	selected.breach_seconds = breach_seconds
	selected.breach_ruled_out = breach.pruned and not breach.ok
	selected.comparison_complete = not detour.exhausted and not breach.exhausted
	selected.map_sequence = _data.map_sequence
	selected.has_obstacle = obstacle
	selected.both_available = bool(detour.ok) and bool(breach.ok)
	selected.approach_point = _column(destination).point
	selected.elevated_goal = goal.y > selected.approach_point.y + 1.1
	return selected

func _search(source: Vector2i, destination: Vector2i, simulation: MatchSimulation,
		with_breach: bool, crowd: Dictionary, cost_limit: float = INF) -> Dictionary:
	_stats.searches += 1
	var start: Vector3i = Vector3i(source.x, source.y, 0)
	var queue: Array[Vector3i] = []
	var priorities: Array[float] = []
	var previous: Dictionary[Vector3i, Vector3i] = {}
	var costs: Dictionary[Vector3i, float] = {start:0.0}
	var closed: Dictionary[Vector3i, bool] = {}
	_push(queue, priorities, start, _heuristic(source, destination))
	var expanded: int = 0
	var pruned: bool = false
	var found: Vector3i = Vector3i(-1, -1, -1)
	while not queue.is_empty() and expanded < MAX_EXPANSIONS:
		var current: Vector3i = _pop(queue, priorities)
		if closed.has(current):
			continue
		if costs[current] + _heuristic(Vector2i(current.x, current.y), destination) > cost_limit:
			pruned = true
			continue
		if Vector2i(current.x, current.y) == destination and (not with_breach or current.z == 1):
			found = current
			break
		closed[current] = true
		expanded += 1
		var point: Vector3 = _column(Vector2i(current.x, current.y)).point
		for direction: Vector2i in NEIGHBORS:
			var next_column: Vector2i = Vector2i(current.x, current.y) + direction
			var next_data: Dictionary = _column(next_column)
			if next_data.is_empty() or next_data.protected:
				continue
			var rise: float = next_data.point.y - point.y
			if rise > 1.01 or rise < -2.01:
				continue
			var blocked: bool = not next_data.cells.is_empty()
			if blocked and not with_breach:
				continue
			var next: Vector3i = Vector3i(next_column.x, next_column.y, 1 if blocked or current.z == 1 else 0)
			if closed.has(next):
				continue
			var seconds: float = (1.0 + absf(rise) * 1.5) / _walk_speed
			seconds += .2 * clampi(int(crowd.get(next_column, 0)), 0, 12)
			# Within the breach option find a short exposed passage. Expensive
			# block health must not suppress the user's randomly selected option.
			if blocked:
				seconds += .25
			var cost: float = costs[current] + seconds
			if cost + _heuristic(next_column, destination) > cost_limit:
				pruned = true
				continue
			if cost >= float(costs.get(next, INF)):
				continue
			costs[next] = cost
			previous[next] = current
			_push(queue, priorities, next, cost + _heuristic(next_column, destination))
	_stats.expanded_nodes += expanded
	var exhausted: bool = found.x < 0 and not queue.is_empty()
	if exhausted:
		_stats.exhausted_searches += 1
	if pruned:
		_stats.pruned_searches += 1
	if found.x < 0:
		return {"ok":false, "exhausted":exhausted, "pruned":pruned, "seconds":INF}
	var reverse: Array[Vector3i] = [found]
	var cursor: Vector3i = found
	while cursor != start and reverse.size() <= MAX_EXPANSIONS:
		cursor = previous[cursor]
		reverse.append(cursor)
	reverse.reverse()
	var path: Array[Vector3] = []
	var blockers: Dictionary[int, Array] = {}
	var estimate: float = 0.0
	var hits_total: int = 0
	for state: Vector3i in reverse:
		var entry: Dictionary = _column(Vector2i(state.x, state.y))
		if not entry.cells.is_empty():
			blockers[path.size()] = entry.cells.duplicate()
			for cell: Vector3i in entry.cells:
				hits_total += maxi(1, ceili(simulation.get_block_remaining_health(cell) / _breach_damage))
		if not path.is_empty():
			estimate += path.back().distance_to(entry.point) / _walk_speed
		path.append(entry.point)
	if hits_total > 0:
		estimate += _breach_windup + (hits_total - 1) * _breach_cycle
	return {"ok":true, "exhausted":false, "pruned":pruned, "seconds":estimate, "path":path, "blockers":blockers}

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y)) / _walk_speed

static func _push(queue: Array[Vector3i], priorities: Array[float], point: Vector3i, priority: float) -> void:
	queue.append(point)
	priorities.append(priority)
	var index: int = queue.size() - 1
	while index > 0:
		var parent: int = (index - 1) >> 1
		if priorities[parent] <= priority:
			break
		queue[index] = queue[parent]
		priorities[index] = priorities[parent]
		index = parent
	queue[index] = point
	priorities[index] = priority

static func _pop(queue: Array[Vector3i], priorities: Array[float]) -> Vector3i:
	var result: Vector3i = queue[0]
	var point: Vector3i = queue.pop_back()
	var priority: float = priorities.pop_back()
	if queue.is_empty():
		return result
	var index: int = 0
	while index * 2 + 1 < queue.size():
		var child: int = index * 2 + 1
		if child + 1 < queue.size() and priorities[child + 1] < priorities[child]:
			child += 1
		if priority <= priorities[child]:
			break
		queue[index] = queue[child]
		priorities[index] = priorities[child]
		index = child
	queue[index] = point
	priorities[index] = priority
	return result

func get_statistics() -> Dictionary:
	var result: Dictionary = _stats.duplicate()
	result.cached_columns = _columns.size()
	result.max_expansions = MAX_EXPANSIONS
	return result
