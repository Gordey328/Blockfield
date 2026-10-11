class_name TdmVoxelNavigation
extends RefCounted
## Bounded authored arena navigation. Lazy stand-column graph, no voxel scene nodes.
## Terrain edits invalidate nearby columns; live clearance is checked before movement.

const MAX_EXPANSIONS: int = 1600
const MAX_INVALIDATIONS: int = 384
const NEIGHBORS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var _data: VoxelData
var _ceiling: int = 12
var _sequence: int = 0
var _heights: Dictionary[Vector2i, float] = {}
var _stats: Dictionary = {}

func configure(data: VoxelData, ceiling: int = 12) -> void:
	_data = data
	_ceiling = clampi(ceiling, 4, data.dimensions.y - 3)
	_sequence = data.map_sequence
	_heights.clear()
	_stats = {"path_requests":0, "expanded_nodes":0, "invalidated_columns":0,
		"full_invalidations":0, "path_rechecks":0, "blocked_rechecks":0, "failed_paths":0}

func refresh() -> void:
	if _data == null or _sequence == _data.map_sequence:
		return
	var journal: Dictionary = _data.transactions_since(_sequence)
	_sequence = _data.map_sequence
	if not bool(journal.ok):
		_heights.clear()
		_stats.full_invalidations += 1
		return
	var dirty: Dictionary[Vector2i, bool] = {}
	for transaction: Dictionary in journal.transactions:
		for change: Dictionary in transaction.changes:
			var cell: Vector3i = change.cell
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					dirty[Vector2i(cell.x + dx, cell.z + dz)] = true
			if dirty.size() > MAX_INVALIDATIONS:
				_heights.clear()
				_stats.full_invalidations += 1
				return
	for column: Vector2i in dirty:
		_heights.erase(column)
	_stats.invalidated_columns += dirty.size()

func can_stand(feet: Vector3) -> bool:
	if _data == null or not feet.is_finite() or feet.x < 1 or feet.z < 1 \
			or feet.x >= _data.dimensions.x - 1 or feet.z >= _data.dimensions.z - 1:
		return false
	var bottom: int = floori(feet.y + .02)
	var top: int = floori(feet.y + 2.3)
	for dx: float in [-.46, .46]:
		for dz: float in [-.46, .46]:
			var x: int = floori(feet.x + dx)
			var z: int = floori(feet.z + dz)
			if _data.get_block(Vector3i(x, floori(feet.y - .05), z)) == 0:
				return false
			for y: int in range(bottom, top + 1):
				if _data.get_block(Vector3i(x, y, z)) != 0:
					return false
	return true

func _point(column: Vector2i) -> Vector3:
	if column.x < 1 or column.y < 1 or column.x >= _data.dimensions.x - 1 or column.y >= _data.dimensions.z - 1:
		return Vector3.INF
	if not _heights.has(column):
		var height: float = INF
		for y: int in range(_ceiling, 0, -1):
			if _data.get_block(Vector3i(column.x, y - 1, column.y)) != 0:
				var candidate: Vector3 = Vector3(column.x + .5, y, column.y + .5)
				if can_stand(candidate):
					height = float(y)
					break
		_heights[column] = height
	return Vector3(column.x + .5, _heights[column], column.y + .5) if is_finite(_heights[column]) else Vector3.INF

func nearest_stand(point: Vector3, radius: int = 4) -> Vector3:
	refresh()
	var center: Vector2i = Vector2i(floori(point.x), floori(point.z))
	var closest: Vector3 = Vector3.INF
	var best: float = INF
	for dx: int in range(-radius, radius + 1):
		for dz: int in range(-radius, radius + 1):
			var candidate: Vector3 = _point(center + Vector2i(dx, dz))
			if candidate.is_finite() and absf(candidate.y - point.y) <= 2.1:
				var cost: float = candidate.distance_squared_to(point)
				if cost < best:
					best = cost
					closest = candidate
	return closest

func segment_clear(start: Vector3, finish: Vector3) -> bool:
	refresh()
	_stats.path_rechecks += 1
	var steps: int = maxi(1, ceili(start.distance_to(finish) / .45))
	# Callers only check short path edges; cap externally malformed requests too.
	if steps > 24 or absf(finish.y - start.y) > 1.1:
		_stats.blocked_rechecks += 1
		return false
	var previous_height: float = start.y
	for index: int in range(1, steps + 1):
		var sample: Vector3 = start.lerp(finish, float(index) / steps)
		var stand: Vector3 = _point(Vector2i(floori(sample.x), floori(sample.z)))
		if not stand.is_finite() or stand.y - previous_height > 1.1 or stand.y - previous_height < -2.1:
			_stats.blocked_rechecks += 1
			return false
		sample.y = stand.y
		previous_height = stand.y
		if not can_stand(sample):
			_stats.blocked_rechecks += 1
			return false
	return true

func get_path(start: Vector3, goal: Vector3) -> Array[Vector3]:
	refresh()
	_stats.path_requests += 1
	var result: Array[Vector3] = []
	var source: Vector3 = nearest_stand(start, 2)
	var destination: Vector3 = nearest_stand(goal, 3)
	if not source.is_finite() or not destination.is_finite():
		_stats.failed_paths += 1
		return result
	var from: Vector2i = Vector2i(floori(source.x), floori(source.z))
	var to: Vector2i = Vector2i(floori(destination.x), floori(destination.z))
	var queue: Array[Vector2i] = []
	var priorities: Array[float] = []
	var previous: Dictionary[Vector2i, Vector2i] = {}
	var costs: Dictionary[Vector2i, float] = {from:0.0}
	var closed: Dictionary[Vector2i, bool] = {}
	_push(queue, priorities, from, _heuristic(from, to))
	var expanded: int = 0
	var found: bool = false
	while not queue.is_empty() and expanded < MAX_EXPANSIONS:
		var current: Vector2i = _pop(queue, priorities)
		if closed.has(current):
			continue
		if current == to:
			found = true
			break
		closed[current] = true
		expanded += 1
		var current_point: Vector3 = _point(current)
		for direction: Vector2i in NEIGHBORS:
			var next: Vector2i = current + direction
			if closed.has(next):
				continue
			var next_point: Vector3 = _point(next)
			if not next_point.is_finite():
				continue
			var rise: float = next_point.y - current_point.y
			if rise > 1.01 or rise < -2.01:
				continue
			var cost: float = costs[current] + 1.0 + absf(rise) * 1.5
			if cost >= float(costs.get(next, INF)):
				continue
			costs[next] = cost
			previous[next] = current
			_push(queue, priorities, next, cost + _heuristic(next, to))
	_stats.expanded_nodes += expanded
	if not found:
		_stats.failed_paths += 1
		return result
	var cursor: Vector2i = to
	result.append(_point(cursor))
	while cursor != from and result.size() <= MAX_EXPANSIONS:
		cursor = previous[cursor]
		result.append(_point(cursor))
	result.reverse()
	return result

static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))

static func _push(queue: Array[Vector2i], priorities: Array[float], point: Vector2i, priority: float) -> void:
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

static func _pop(queue: Array[Vector2i], priorities: Array[float]) -> Vector2i:
	var result: Vector2i = queue[0]
	var point: Vector2i = queue.pop_back()
	var priority: float = priorities.pop_back()
	if queue.is_empty():
		return result
	var index: int = 0
	while index * 2 + 1 < queue.size():
		var child: int = index * 2 + 1
		if child + 1 < queue.size() and priorities[child + 1] < priorities[child]:
			child += 1
		if priorities[child] >= priority:
			break
		queue[index] = queue[child]
		priorities[index] = priorities[child]
		index = child
	queue[index] = point
	priorities[index] = priority
	return result

func get_statistics() -> Dictionary:
	var result: Dictionary = _stats.duplicate()
	result.cached_columns = _heights.size()
	result.max_expansions = MAX_EXPANSIONS
	return result
