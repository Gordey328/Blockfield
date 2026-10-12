class_name VoxelData
extends RefCounted
## Shared authority/query map. No scene, renderer, physics server or audio dependency.
## Canonical solid0x01RRGGBB; air0. Index is Y-fast in Godot axes.

## Observers may invalidate temporary ownership; they must not apply these edits again.
signal cells_committed(changes: Array)

const VXL = preload("res://world/vxl_reader.gd")
const DIRECTIONS: Array[Vector3i] = [Vector3i.DOWN,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK,Vector3i.UP]
const MAX_UINT32: int = 0xffffffff
const MAX_JOURNAL_BYTES: int = 8*1024*1024
const MAX_JOURNAL_CHANGES: int = 32768
const MAX_SOURCE_RAY_STEPS: int = 8192
const SOURCE_RAY_COORD_LIMIT: float = 1000000.0
var dimensions: Vector3i = Vector3i(96,32,96)
var blocks: PackedInt32Array = PackedInt32Array()
var water_level: float = 1.0
var wade_origin_level: float = 2.0
var epoch: int = 1
var map_sequence: int = 0
var last_tick: int = 0
var read_only: bool = false
var last_error: String = ""
## Local adoption identity, including a same-epoch/same-dimension replacement.
var generation: int = 0
var _journal: Array[Dictionary] = []
var _journal_bytes: int = 0
var _journal_changes: int = 0
var _journal_max_bytes: int = MAX_JOURNAL_BYTES
var _journal_max_transactions: int = 128
var _journal_max_changes: int = MAX_JOURNAL_CHANGES

static func valid_dimensions(size: Vector3i) -> bool:
	return size.x > 0 and size.x <= 512 and size.y > 0 and size.y <= 64 and size.z > 0 and size.z <= 512

static func valid_color(value: int) -> bool:
	return value == 0 or (value >= 0x01000000 and value <= 0x01ffffff)

static func _u32(value: Variant, positive: bool = false) -> bool:
	return typeof(value) == TYPE_INT and value >= (1 if positive else 0) and value <= MAX_UINT32

func clear(size: Vector3i, match_epoch: int = 1) -> Error:
	if read_only:
		return ERR_UNAUTHORIZED
	if not valid_dimensions(size) or not _u32(match_epoch,true):
		return ERR_INVALID_PARAMETER
	var empty: PackedInt32Array = PackedInt32Array()
	empty.resize(size.x*size.y*size.z)
	dimensions = size
	blocks = empty
	generation += 1
	epoch = match_epoch
	map_sequence = 0
	last_tick = 0
	_clear_journal()
	return OK

func index(cell: Vector3i) -> int:
	return cell.y+dimensions.y*(cell.x+dimensions.x*cell.z)

func is_in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < dimensions.x and cell.y < dimensions.y and cell.z < dimensions.z

func get_block(cell: Vector3i) -> int:
	return blocks[index(cell)] if is_in_bounds(cell) and not blocks.is_empty() else 0

func clip_box(position: Vector3) -> bool:
	var cell: Vector3i = Vector3i(position.floor())
	if cell.x < 0 or cell.z < 0 or cell.x >= dimensions.x or cell.z >= dimensions.z or cell.y < 0:
		return true
	if cell.y >= dimensions.y:
		return false
	if cell.y == 0:
		cell.y = 1
	return get_block(cell) != 0

func clip_world(position: Vector3) -> bool:
	var cell: Vector3i = Vector3i(position.floor())
	if cell.x < 0 or cell.z < 0 or cell.x >= dimensions.x or cell.z >= dimensions.z or cell.y >= dimensions.y:
		return false
	if cell.y < 0:
		return true
	if cell.y == 0:
		cell.y = 1
	return get_block(cell) != 0

func cast_voxel(origin: Vector3, direction: Vector3, max_dist: float = 128.0) -> Dictionary:
	var miss: Dictionary = {"hit":false,"cell":Vector3i.ZERO,"normal":Vector3i.ZERO,"position":origin+direction.normalized()*max_dist}
	if not origin.is_finite() or not direction.is_finite() or not is_finite(max_dist) or direction.length_squared() < 0.000001 or max_dist < 0.0:
		return miss
	var ray: Vector3 = direction.normalized()
	var cell: Vector3i = Vector3i(origin.floor())
	var step: Vector3i = Vector3i(signi(roundi(ray.x*1000000)),signi(roundi(ray.y*1000000)),signi(roundi(ray.z*1000000)))
	var delta: Vector3 = Vector3(INF,INF,INF)
	var next: Vector3 = Vector3(INF,INF,INF)
	for axis: int in range(3):
		if absf(ray[axis]) > 0.000001:
			delta[axis] = absf(1.0/ray[axis])
			var boundary: float = float(cell[axis]+(1 if step[axis] > 0 else 0))
			next[axis] = (boundary-origin[axis])/ray[axis]
	var traveled: float = 0.0
	var normal: Vector3i = Vector3i.ZERO
	while traveled <= max_dist:
		if get_block(cell) != 0:
			return {"hit":true,"cell":cell,"normal":normal,"position":origin+ray*traveled}
		var axis: int = 0
		if next.y < next.x:
			axis = 1
		if next.z < next[axis]:
			axis = 2
		traveled = next[axis]
		next[axis] += delta[axis]
		cell[axis] += step[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return miss

static func _ray_f32(value: float) -> float:
	return Vector3(value, 0.0, 0.0).x

static func _ray_to_native(point: Vector3) -> Vector3:
	# Points reflect around the native geometric ceiling64; cells use63-z.
	return Vector3(point.x, point.z, 64.0 - point.y)

static func _ray_from_native(point: Vector3) -> Vector3:
	return Vector3(point.x, 64.0 - point.z, point.y)

static func _ray_cell_from_native(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x, 63 - cell.z, cell.y)

static func _ray_normal_from_native(normal: Vector3i) -> Vector3i:
	return Vector3i(normal.x, -normal.z, normal.y)

func _source_ray_solid(native_cell: Vector3i) -> bool:
	var cell := _ray_cell_from_native(native_cell)
	if cell.y < 0:
		return true
	if cell.y >= dimensions.y:
		return false
	if dimensions == Vector3i(512, 64, 512):
		cell.x &= 511
		cell.z &= 511
	# Dispatch through get_block so a leased historical query reads its frame.
	# Authored smaller arenas keep bounded horizontal queries rather than wrap.
	return get_block(cell) != 0

static func _source_ray_result(origin: Vector3, native_cell: Vector3i = Vector3i.ZERO, native_normal: Vector3i = Vector3i.ZERO, steps: int = 0) -> Dictionary:
	return {"hit":false, "start_solid":false, "cell":_ray_cell_from_native(native_cell),
		"normal":_ray_normal_from_native(native_normal), "position":origin,
		"steps":steps, "valid":true, "error":""}

static func _source_ray_error(origin: Vector3, message: String) -> Dictionary:
	return {"hit":false, "start_solid":false, "cell":Vector3i.ZERO, "normal":Vector3i.ZERO,
		"position":origin, "steps":0, "valid":false, "error":message}

func cast_source_ray(origin: Vector3, direction: Vector3, max_steps: int = 500) -> Dictionary:
	# GameMap::CastRay2, v0.1.3 GameMap.cpp361-506. max_steps counts crossed
	# grid planes, not metres. Execute in native axes to retain X/Y/Z ties.
	if not origin.is_finite() or not direction.is_finite() or not valid_dimensions(dimensions) or max_steps < 0 or max_steps > MAX_SOURCE_RAY_STEPS:
		return _source_ray_error(origin, "invalid source ray input/budget")
	if maxf(absf(origin.x), maxf(absf(origin.y), absf(origin.z))) > SOURCE_RAY_COORD_LIMIT:
		return _source_ray_error(origin, "source ray origin exceeds coordinate budget")
	var native_origin := _ray_to_native(origin)
	var ray := Vector3(direction.x, direction.z, -direction.y)
	# Math.h359-374 uses left-associated float products/sums and sqrtf.
	var squared := ray * ray
	var length := _ray_f32(sqrt(_ray_f32(_ray_f32(squared.x + squared.y) + squared.z)))
	if not is_finite(length):
		return _source_ray_error(origin, "source ray direction cannot normalize")
	var scale := _ray_f32(1.0 / length) if length != 0.0 else 0.0
	ray *= scale
	if not ray.is_finite():
		return _source_ray_error(origin, "source ray direction cannot normalize")
	var cell := Vector3i(native_origin.floor())
	var result := _source_ray_result(origin, cell)
	if _source_ray_solid(cell):
		result.hit = true
		result.start_solid = true
		return result
	if max_steps == 0:
		return result
	if ray == Vector3.ZERO:
		return _source_ray_error(origin, "zero source ray has no next grid plane")
	var fractional := Vector3.ZERO
	var inverse := Vector3.ZERO
	var absolute := ray.abs()
	for axis in range(3):
		fractional[axis] = float(cell[axis] + 1) - native_origin[axis] if ray[axis] > 0.0 else native_origin[axis] - float(cell[axis])
		inverse[axis] = 1.0 / absolute[axis] if absolute[axis] != 0.0 else 0.0
	if not inverse.is_finite():
		return _source_ray_error(origin, "source ray reciprocal exceeds float32 range")
	var normal := Vector3i.ZERO
	for step in range(max_steps):
		var times := fractional * inverse
		var selected := -1
		var next_time := 0.0
		for axis in range(3):
			if inverse[axis] != 0.0 and (selected < 0 or times[axis] < next_time):
				selected = axis
				next_time = times[axis]
		var next_cell := cell
		next_cell[selected] += 1 if ray[selected] > 0.0 else -1
		# Vector3 multiplication/subtraction each round their components to
		# native binary32, matching separate float operations in the source.
		fractional -= absolute * next_time
		fractional[selected] = 1.0
		normal = cell - next_cell
		if _source_ray_solid(next_cell):
			var hit_position := Vector3.ZERO
			for axis in range(3):
				hit_position[axis] = float(next_cell[axis] + 1) - fractional[axis] if ray[axis] > 0.0 else float(next_cell[axis]) + fractional[axis]
			result = _source_ray_result(_ray_from_native(hit_position), next_cell, normal, step + 1)
			result.hit = true
			return result
		cell = next_cell
	return _source_ray_result(origin, cell, normal, max_steps)

func cast_source_ray_legacy(origin: Vector3, direction: Vector3, length: float = 256.0) -> Dictionary:
	# GameMap::CastRay, v0.1.3 GameMap.cpp208-358 (active #if1 branch).
	# direction is NOT normalized. The native result is an integer corner;
	# normal/start_solid are absent in that API and remain zero/false here.
	if not origin.is_finite() or not direction.is_finite() or not is_finite(length) or not valid_dimensions(dimensions) or length < 0.0 or length > MAX_SOURCE_RAY_STEPS:
		return _source_ray_error(origin, "invalid legacy source ray input/budget")
	if maxf(absf(origin.x), maxf(absf(origin.y), absf(origin.z))) > SOURCE_RAY_COORD_LIMIT:
		return _source_ray_error(origin, "legacy source ray origin exceeds coordinate budget")
	var native_origin := _ray_to_native(origin)
	var native_direction := Vector3(direction.x, direction.z, -direction.y)
	var endpoint := native_origin + native_direction * _ray_f32(length)
	if not endpoint.is_finite() or maxf(absf(endpoint.x), maxf(absf(endpoint.y), absf(endpoint.z))) > SOURCE_RAY_COORD_LIMIT:
		return _source_ray_error(origin, "legacy source ray endpoint exceeds coordinate budget")
	var cell := Vector3i(native_origin.floor())
	var target := Vector3i(endpoint.floor())
	var increment := Vector3i.ZERO
	var fractional := Vector3.ZERO
	var scaled := Vector3.ZERO
	var count := 0
	for axis in range(3):
		if target[axis] < cell[axis]:
			increment[axis] = -1
			fractional[axis] = native_origin[axis] - float(cell[axis])
			scaled[axis] = _ray_f32(native_origin[axis] - endpoint[axis]) * 1024.0
			count += cell[axis] - target[axis]
		elif target[axis] != cell[axis]:
			increment[axis] = 1
			fractional[axis] = float(cell[axis] + 1) - native_origin[axis]
			scaled[axis] = _ray_f32(endpoint[axis] - native_origin[axis]) * 1024.0
			count += target[axis] - cell[axis]
	var product_a := Vector3(fractional.x * scaled.z, fractional.y * scaled.z, fractional.y * scaled.x)
	var product_b := Vector3(fractional.z * scaled.x, fractional.z * scaled.y, fractional.x * scaled.y)
	var cross_difference := product_a - product_b
	if maxf(scaled.x, maxf(scaled.y, scaled.z)) > 536870911.0 or maxf(absf(cross_difference.x), maxf(absf(cross_difference.y), absf(cross_difference.z))) > 1073741823.0:
		return _source_ray_error(origin, "legacy source ray exceeds native integer arithmetic budget")
	var decision := Vector3i(cross_difference.floor())
	var integer_scaled := Vector3i(scaled.floor())
	count = mini(count, int(_ray_f32(length)))
	var steps := 0
	var cached_column := Vector2i(cell.x, cell.y)
	if cell.z < 0 and increment.z < 0:
		return _source_ray_result(origin, cell)
	elif cell.z >= 64:
		return _legacy_source_hit(cell, steps)
	var in_sky := cell.z < 0
	while count > 0:
		if cell.z >= 0:
			in_sky = false
		var axis: int
		if ((decision.x | decision.y) >= 0) and cell.z != target.z:
			axis = 2
			cell.z += increment.z
			decision.x -= integer_scaled.x
			decision.y -= integer_scaled.y
		elif decision.z >= 0 and cell.x != target.x:
			axis = 0
			cell.x += increment.x
			decision.x += integer_scaled.z
			decision.z -= integer_scaled.y
		else:
			axis = 1
			cell.y += increment.y
			decision.y += integer_scaled.z
			decision.z += integer_scaled.x
		steps += 1
		count -= 1
		# Source skips checking the first entered z0 cell and does not
		# refresh its cached column while traversing empty sky.
		if in_sky:
			continue
		if axis == 2:
			if cell.z < 0 and increment.z < 0:
				return _source_ray_result(origin, cell, Vector3i.ZERO, steps)
			elif cell.z >= 64:
				return _legacy_source_hit(cell, steps)
		else:
			cached_column = Vector2i(cell.x, cell.y)
		if _source_ray_solid(Vector3i(cached_column.x, cached_column.y, cell.z)):
			return _legacy_source_hit(cell, steps)
	return _source_ray_result(origin, cell, Vector3i.ZERO, steps)

static func _legacy_source_hit(native_cell: Vector3i, steps: int) -> Dictionary:
	var result := _source_ray_result(_ray_from_native(Vector3(native_cell)), native_cell, Vector3i.ZERO, steps)
	result.hit = true
	return result

func column_top(column: int, from_y: int) -> Vector2i:
	if column < 0 or column >= dimensions.x*dimensions.z or blocks.is_empty():
		return Vector2i(0,-1)
	var offset: int = column*dimensions.y
	for y: int in range(mini(from_y,dimensions.y-1),-1,-1):
		if blocks[offset+y] != 0:
			return Vector2i(blocks[offset+y],y)
	return Vector2i(0,-1)

func seed_box(start: Vector3i, end: Vector3i, color: int) -> void:
	# Bootstrap only; intentionally no action/journal/collapse. Once playing,
	# authority edits must use transactions so replicas can observe them.
	if read_only or blocks.is_empty():
		return
	var packed: int = 0 if color == 0 else (color&0xffffff)|0x01000000
	for z: int in range(maxi(start.z,0),mini(end.z,dimensions.z)):
		for x: int in range(maxi(start.x,0),mini(end.x,dimensions.x)):
			var base: int = dimensions.y*(x+dimensions.x*z)
			for y: int in range(maxi(start.y,0),mini(end.y,dimensions.y)):
				blocks[base+y] = packed

func generate_lab(match_epoch: int = 1) -> Error:
	var error: Error = clear(Vector3i(96,32,96),match_epoch)
	if error != OK:
		return error
	seed_box(Vector3i.ZERO,Vector3i(96,4,96),0x0179694c)
	seed_box(Vector3i(0,3,0),Vector3i(96,4,96),0x01668d57)
	seed_box(Vector3i(0,4,0),Vector3i(96,7,2),0x014a6254)
	seed_box(Vector3i(0,4,94),Vector3i(96,7,96),0x014a6254)
	seed_box(Vector3i(0,4,2),Vector3i(2,7,94),0x014a6254)
	seed_box(Vector3i(94,4,2),Vector3i(96,7,94),0x014a6254)
	for x: int in [14,36,58,80]:
		seed_box(Vector3i(x,4,18),Vector3i(x+8,10,20),0x01b58a62)
		seed_box(Vector3i(x,4,20),Vector3i(x+2,10,30),0x01b58a62)
		seed_box(Vector3i(x+6,4,20),Vector3i(x+8,10,30),0x01b58a62)
		seed_box(Vector3i(x,10,18),Vector3i(x+8,11,30),0x01877768)
		seed_box(Vector3i(x+3,4,41),Vector3i(x+5,8,43),0x01cc6657)
		seed_box(Vector3i(x+2,8,40),Vector3i(x+6,10,44),0x01dccaad)
	seed_box(Vector3i(12,4,57),Vector3i(14,11,59),0x016989ac)
	seed_box(Vector3i(28,4,57),Vector3i(30,11,59),0x016989ac)
	seed_box(Vector3i(12,11,56),Vector3i(30,12,60),0x018cb8cd)
	for step: int in range(6):
		seed_box(Vector3i(68+step*2,4,58),Vector3i(70+step*2,5+step,66),0x018b936a)
	seed_box(Vector3i(38,2,53),Vector3i(56,4,56),0)
	seed_box(Vector3i(72,1,72),Vector3i(88,4,88),0)
	return OK

func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"changed":false,"changes":[],"collapse_groups":[]}

func _metadata_error(metadata: Dictionary) -> String:
	if read_only:
		return "snapshot is read-only"
	if blocks.size() != dimensions.x*dimensions.y*dimensions.z:
		return "map not initialized"
	if map_sequence >= MAX_UINT32:
		return "map sequence exhausted; reset epoch"
	for key: Variant in metadata:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or key not in ["tick","actor_id","action_id","transaction_id"] or not _u32(metadata[key],key == "transaction_id"):
			return "invalid transaction metadata"
	if int(metadata.get("tick",last_tick)) < last_tick:
		return "transaction tick regressed"
	return ""

func _record(cell: Vector3i, after: int, changes: Array, collapsed: bool = false) -> void:
	var before: int = get_block(cell)
	blocks[index(cell)] = after
	changes.append({"cell":cell,"before":before,"after":after,"flags":1 if collapsed else 0})

func set_block(cell: Vector3i, color: int, metadata: Dictionary = {}) -> Dictionary:
	var error: String = _metadata_error(metadata)
	if not error.is_empty():
		return _failure(error)
	if not is_in_bounds(cell) or cell.y == 0:
		return _failure("out-of-bounds or immutable floor")
	var after: int = 0 if color == 0 else (color&0xffffff)|0x01000000
	var before: int = get_block(cell)
	var changes: Array = []
	var groups: Array = []
	if before != after:
		_record(cell,after,changes)
		if before != 0 and after == 0:
			_collapse_neighbors([cell],changes,groups)
	return _commit(changes,groups,metadata)

func remove_blocks(cells: Array[Vector3i], protect_lower_layer: bool = false, metadata: Dictionary = {}) -> Dictionary:
	var error: String = _metadata_error(metadata)
	if not error.is_empty():
		return _failure(error)
	var changes: Array = []
	var removed: Array[Vector3i] = []
	var groups: Array = []
	for cell: Vector3i in cells:
		if not is_in_bounds(cell) or cell.y <= (1 if protect_lower_layer else 0) or get_block(cell) == 0:
			continue
		_record(cell,0,changes)
		removed.append(cell)
	if not removed.is_empty():
		_collapse_neighbors(removed,changes,groups)
	return _commit(changes,groups,metadata)

func explode(position: Vector3, metadata: Dictionary = {}) -> Dictionary:
	if not position.is_finite():
		return _failure("nonfinite explosion position")
	var center: Vector3i = Vector3i(position.floor())
	var cells: Array[Vector3i] = []
	for z: int in range(center.z-1,center.z+2):
		for x: int in range(center.x-1,center.x+2):
			for y: int in range(center.y-1,center.y+2):
				cells.append(Vector3i(x,y,z))
	return remove_blocks(cells,true,metadata)

func _collapse_neighbors(removed: Array[Vector3i], changes: Array, groups: Array) -> void:
	# Preserve the existing downward-priority DFS and its ordered transaction.
	# Sparse integer marks avoid a full-map scratch allocation. Reuse work lists
	# across components, then release them on return, including pathological cuts.
	var checked: Dictionary[int, bool] = {}
	var visited: Dictionary[int, bool] = {}
	var stack: Array[int] = []
	var component: Array[int] = []
	var height: int = dimensions.y
	var width: int = dimensions.x
	var depth: int = dimensions.z
	var plane: int = height * width
	var offsets := PackedInt32Array([-1, -height, height, -plane, plane, 1])
	for cell: Vector3i in removed:
		for direction: Vector3i in DIRECTIONS:
			var start_cell: Vector3i = cell + direction
			if not is_in_bounds(start_cell):
				continue
			var start: int = index(start_cell)
			if blocks[start] == 0 or checked.has(start):
				continue
			stack.clear()
			component.clear()
			visited.clear()
			stack.append(start)
			visited[start] = true
			var supported: bool = false
			while not stack.is_empty():
				var current: int = stack.pop_back()
				component.append(current)
				var y: int = current % height
				if y <= 1:
					supported = true
					break
				var column: int = current / height
				var x: int = column % width
				var z: int = column / width
				for i: int in range(DIRECTIONS.size()-1,-1,-1):
					# Each storage edge is checked before applying its stride: linear
					# indices must never wrap between columns or horizontal planes.
					match i:
						5:
							if y + 1 >= height: continue
						4:
							if z + 1 >= depth: continue
						3:
							if z == 0: continue
						2:
							if x + 1 >= width: continue
						1:
							if x == 0: continue
						0:
							if y == 0: continue
					var neighbor: int = current + offsets[i]
					if blocks[neighbor] != 0 and not visited.has(neighbor):
						if neighbor % height <= 1 or checked.has(neighbor):
							supported = true
							break
						visited[neighbor] = true
						stack.append(neighbor)
				if supported:
					break
			if supported:
				for member: int in component:
					checked[member] = true
			else:
				var cells: Array[Vector3i] = []
				var colors := PackedInt32Array()
				colors.resize(component.size())
				for ordinal: int in component.size():
					var member: int = component[ordinal]
					var column: int = member / height
					var member_cell := Vector3i(column % width, member % height, column / width)
					var before: int = blocks[member]
					cells.append(member_cell)
					colors[ordinal] = before
					checked[member] = true
					blocks[member] = 0
					changes.append({"cell":member_cell,"before":before,"after":0,"flags":1})
				groups.append({"cells":cells,"colors":colors})

func _commit(changes: Array, groups: Array, metadata: Dictionary) -> Dictionary:
	var changed: bool = not changes.is_empty()
	if changed:
		map_sequence += 1
		last_tick = int(metadata.get("tick",last_tick))
	var transaction: Dictionary = {"ok":true,"error":"","changed":changed,"epoch":epoch,"map_sequence":map_sequence,"transaction_id":int(metadata.get("transaction_id",map_sequence)),"tick":last_tick,"actor_id":int(metadata.get("actor_id",0)),"action_id":int(metadata.get("action_id",0)),"dimensions":dimensions,"changes":changes,"collapse_groups":groups}
	if changed:
		_retain(transaction)
		cells_committed.emit(changes)
	return transaction

func commit_without_collapse(changes: Array[Dictionary], metadata: Dictionary = {}) -> Dictionary:
	# Only the cooperative ArsenalTerrain authority uses this seam. Source weapons
	# retain remove_blocks/set_block and their original synchronous collapse order.
	var error: String = _metadata_error(metadata)
	if not error.is_empty():
		return _failure(error)
	if changes.size() > 256:
		return _failure("cooperative transaction exceeds 256 changes")
	var seen: Dictionary[Vector3i, bool] = {}
	for change: Dictionary in changes:
		if typeof(change.get("cell")) != TYPE_VECTOR3I or typeof(change.get("before")) != TYPE_INT or typeof(change.get("after")) != TYPE_INT or typeof(change.get("flags")) != TYPE_INT:
			return _failure("invalid cooperative change fields")
		var cell: Vector3i = change.cell
		if not is_in_bounds(cell) or cell.y == 0 or seen.has(cell) or get_block(cell) != change.before:
			return _failure("cooperative before-color or cell conflict")
		if not valid_color(change.before) or not valid_color(change.after) or change.before == change.after or change.flags not in [0, 1]:
			return _failure("invalid cooperative colors or flags")
		if change.flags == 1 and (change.before == 0 or change.after != 0 or cell.y <= 1):
			return _failure("invalid cooperative collapse")
		seen[cell] = true
	var accepted: Array = []
	for change: Dictionary in changes:
		_record(change.cell, change.after, accepted, change.flags == 1)
	return _commit(accepted, _groups_from_flags(accepted), metadata)

func apply_transaction(transaction: Dictionary) -> Dictionary:
	if read_only or blocks.size() != dimensions.x*dimensions.y*dimensions.z:
		return _failure("map not writable or initialized")
	for key: String in ["epoch","map_sequence","transaction_id","tick","actor_id","action_id"]:
		if not transaction.has(key) or not _u32(transaction[key],key in ["epoch","map_sequence","transaction_id"]):
			return _failure("invalid transaction identity")
	if transaction.epoch != epoch or map_sequence == MAX_UINT32 or transaction.map_sequence != map_sequence+1:
		return _failure("epoch or map sequence mismatch; resync")
	if transaction.tick < last_tick or typeof(transaction.get("dimensions")) != TYPE_VECTOR3I or transaction.dimensions != dimensions:
		return _failure("transaction tick or dimensions mismatch")
	if typeof(transaction.get("changes")) != TYPE_ARRAY or transaction.changes.is_empty() or transaction.changes.size() > blocks.size():
		return _failure("invalid transaction change count")
	var seen: Dictionary = {}
	var changes: Array = []
	for value: Variant in transaction.changes:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("invalid change record")
		var change: Dictionary = value
		if typeof(change.get("cell")) != TYPE_VECTOR3I or typeof(change.get("before")) != TYPE_INT or typeof(change.get("after")) != TYPE_INT or typeof(change.get("flags")) != TYPE_INT:
			return _failure("invalid change fields")
		var cell: Vector3i = change.cell
		if not is_in_bounds(cell) or cell.y == 0 or seen.has(cell):
			return _failure("out-of-bounds, immutable or duplicate cell")
		if not valid_color(change.before) or not valid_color(change.after) or change.before == change.after or change.flags not in [0,1]:
			return _failure("invalid before/after color or flags")
		if change.flags == 1 and (change.before == 0 or change.after != 0 or cell.y <= 1):
			return _failure("invalid collapse removal")
		if get_block(cell) != change.before:
			return _failure("before-color conflict; resync")
		seen[cell] = true
		changes.append({"cell":cell,"before":change.before,"after":change.after,"flags":change.flags})
	# All records validated. Never rerun support collapse on a replica.
	for change: Dictionary in changes:
		blocks[index(change.cell)] = change.after
	map_sequence = transaction.map_sequence
	last_tick = transaction.tick
	var accepted: Dictionary = {"ok":true,"error":"","changed":true,"epoch":epoch,"map_sequence":map_sequence,"transaction_id":transaction.transaction_id,"tick":last_tick,"actor_id":transaction.actor_id,"action_id":transaction.action_id,"dimensions":dimensions,"changes":changes,"collapse_groups":_groups_from_flags(changes)}
	_retain(accepted)
	cells_committed.emit(changes)
	return accepted

func _groups_from_flags(changes: Array) -> Array:
	# Group cosmetic cells solely from authoritative flags; no terrain support
	# decisions and no reinsertion. Order follows the transaction's first cell.
	var remaining: Dictionary = {}
	for change: Dictionary in changes:
		if change.flags == 1:
			remaining[change.cell] = change.before
	var groups: Array = []
	for change: Dictionary in changes:
		if not remaining.has(change.cell):
			continue
		var cells: Array[Vector3i] = []
		var colors: PackedInt32Array = PackedInt32Array()
		var stack: Array[Vector3i] = [change.cell]
		while not stack.is_empty():
			var cell: Vector3i = stack.pop_back()
			if not remaining.has(cell):
				continue
			cells.append(cell)
			colors.append(remaining[cell])
			remaining.erase(cell)
			for direction: Vector3i in DIRECTIONS:
				if remaining.has(cell+direction):
					stack.append(cell+direction)
		groups.append({"cells":cells,"colors":colors})
	return groups

func _wire_cost(transaction: Dictionary) -> int:
	return transaction.changes.size()*15+ceili(float(transaction.changes.size())/2048.0)*56

func _clear_journal() -> void:
	_journal.clear()
	_journal_bytes = 0
	_journal_changes = 0

func _retain(transaction: Dictionary) -> void:
	var count: int = transaction.changes.size()
	var cost: int = _wire_cost(transaction)
	if cost > _journal_max_bytes or count > _journal_max_changes or _journal_max_transactions == 0:
		_clear_journal()
		return
	_journal.append(transaction.duplicate(true))
	_journal_bytes += cost
	_journal_changes += count
	while _journal_bytes > _journal_max_bytes or _journal_changes > _journal_max_changes or _journal.size() > _journal_max_transactions:
		var oldest: Dictionary = _journal.pop_front()
		_journal_bytes -= _wire_cost(oldest)
		_journal_changes -= oldest.changes.size()

func set_journal_budget(wire_bytes: int, transactions: int = 128, changes: int = MAX_JOURNAL_CHANGES) -> void:
	_journal_max_bytes = clampi(wire_bytes,0,MAX_JOURNAL_BYTES)
	_journal_max_transactions = clampi(transactions,0,1024)
	_journal_max_changes = clampi(changes,0,MAX_JOURNAL_CHANGES)
	while not _journal.is_empty() and (_journal_bytes > _journal_max_bytes or _journal_changes > _journal_max_changes or _journal.size() > _journal_max_transactions):
		var oldest: Dictionary = _journal.pop_front()
		_journal_bytes -= _wire_cost(oldest)
		_journal_changes -= oldest.changes.size()

func transactions_since(sequence: int) -> Dictionary:
	if not _u32(sequence) or sequence > map_sequence:
		return {"ok":false,"error":"invalid history sequence","transactions":[]}
	var earliest: int = _journal[0].map_sequence if not _journal.is_empty() else map_sequence+1
	if sequence < earliest-1:
		return {"ok":false,"error":"journal gap; new baseline required","transactions":[]}
	var result: Array = []
	for transaction: Dictionary in _journal:
		if transaction.map_sequence > sequence:
			result.append(transaction.duplicate(true))
	return {"ok":true,"error":"","epoch":epoch,"from_sequence":sequence,"map_sequence":map_sequence,"transactions":result}

func get_journal_stats() -> Dictionary:
	return {"epoch":epoch,"map_sequence":map_sequence,"last_tick":last_tick,"transactions":_journal.size(),"wire_bytes":_journal_bytes,"changes":_journal_changes,"max_wire_bytes":_journal_max_bytes,"max_transactions":_journal_max_transactions,"max_changes":_journal_max_changes,"earliest_sequence":_journal[0].map_sequence if not _journal.is_empty() else map_sequence+1}

func frozen_copy() -> RefCounted:
	var frozen: RefCounted = get_script().new()
	frozen.dimensions = dimensions
	# Packed arrays are reference-like in GDScript; plain assignment aliases
	# live edits. An explicit duplicate gives an independent snapshot container.
	frozen.blocks = blocks.duplicate()
	frozen.water_level = water_level
	frozen.wade_origin_level = wade_origin_level
	frozen.epoch = epoch
	frozen.map_sequence = map_sequence
	frozen.last_tick = last_tick
	frozen.generation = generation
	frozen.read_only = true
	return frozen

func snapshot_bytes() -> PackedByteArray:
	return snapshot_range(0,blocks.size()*4)

static var _snapshot_byte_order: int = -1

static func packed_byte_order() -> int:
	# Conversion encoding is an engine implementation detail. Verify both
	# directions once rather than assuming the native/export target endian.
	# 1=little, 2=big, 0=unsupported (use explicit scalar wire encoding).
	if _snapshot_byte_order>=0:
		return _snapshot_byte_order
	var integers: PackedInt32Array = PackedInt32Array([0x01020304])
	var bytes: PackedByteArray = integers.to_byte_array()
	_snapshot_byte_order=0
	if bytes.to_int32_array()==integers:
		if bytes==PackedByteArray([4,3,2,1]): _snapshot_byte_order=1
		elif bytes==PackedByteArray([1,2,3,4]): _snapshot_byte_order=2
	return _snapshot_byte_order

func snapshot_range(byte_offset: int, byte_count: int) -> PackedByteArray:
	# Read bounded byte ranges from a frozen local snapshot so edits across ticks
	# cannot produce mixed map bytes during import/export or diagnostics.
	var output: PackedByteArray = PackedByteArray()
	if blocks.size() != dimensions.x*dimensions.y*dimensions.z or byte_offset < 0 or byte_count < 0 or byte_offset > blocks.size()*4 or byte_count > blocks.size()*4-byte_offset:
		return output
	if byte_count==0:
		return output
	var first: int = byte_offset/4
	var colors: PackedInt32Array = blocks.slice(first,(byte_offset+byte_count+3)/4)
	# Validate the complete covering cells, including partial edge bytes.
	for color: int in colors:
		if not valid_color(color):
			return output
	var order: int = packed_byte_order()
	if order==0:
		output.resize(byte_count)
		for byte: int in range(byte_count):
			var source: int = byte_offset%4+byte
			output[byte]=(colors[source/4]>>((3-source%4)*8))&255
		return output
	output=colors.to_byte_array()
	if order==1: output.bswap32()
	var skip: int = byte_offset%4
	return output if skip==0 and byte_count==output.size() else output.slice(skip,skip+byte_count)

func load_snapshot_bytes(bytes: PackedByteArray, size: Vector3i, match_epoch: int, sequence: int, tick: int = 0) -> Error:
	if read_only:
		return ERR_UNAUTHORIZED
	if not valid_dimensions(size) or not _u32(match_epoch,true) or not _u32(sequence) or not _u32(tick) or bytes.size() != size.x*size.y*size.z*4:
		return ERR_INVALID_DATA
	var decoded: PackedInt32Array = PackedInt32Array()
	decoded.resize(size.x*size.y*size.z)
	for i: int in range(decoded.size()):
		var offset: int = i*4
		var value: int = (bytes[offset]<<24)|(bytes[offset+1]<<16)|(bytes[offset+2]<<8)|bytes[offset+3]
		if not valid_color(value):
			return ERR_INVALID_DATA
		decoded[i] = value
	dimensions = size
	blocks = decoded
	generation += 1
	epoch = match_epoch
	map_sequence = sequence
	last_tick = tick
	_clear_journal()
	return OK

func load_vxl_bytes(bytes: PackedByteArray, match_epoch: int = 1) -> Error:
	if read_only:
		return ERR_UNAUTHORIZED
	if not _u32(match_epoch,true):
		return ERR_INVALID_PARAMETER
	var decoded: Dictionary = VXL.decode(bytes)
	if decoded.error != OK:
		last_error = decoded.get("message","Invalid VXL")
		return decoded.error
	dimensions = decoded.size
	blocks = decoded.blocks
	generation += 1
	epoch = match_epoch
	map_sequence = 0
	last_tick = 0
	last_error = ""
	_clear_journal()
	return OK

func encode_vxl() -> PackedByteArray:
	return VXL.encode(blocks,dimensions)
