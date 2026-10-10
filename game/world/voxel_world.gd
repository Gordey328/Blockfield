class_name VoxelWorld
extends Node3D
## Packed voxel world. Coordinate axes: x east, y up, z south. One cube = 1 m.
## Empty blocks are 0; all solid colors use 0x01RRGGBB (black is 0x01000000).

signal blocks_changed(changes: Array)
signal map_loaded(map_name: String)

const CHUNK_SIZE := 16
const DIRECTIONS: Array[Vector3i] = [Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i.UP]
const VXL_READER = preload("res://world/vxl_reader.gd")
const CHUNK_SCRIPT = preload("res://world/voxel_chunk.gd")

var dimensions := Vector3i(96, 32, 96)
var map_name := "Blockfield Test Grounds"
var render_radius := 4
var rebuild_budget := 3
var _blocks := PackedInt32Array()
var _chunks: Dictionary = {}
var _dirty: Dictionary = {}
var _streaming := false
var _view_chunk := Vector3i(-1000, 0, -1000)
var _spawn := Vector3(48.5, 5.0, 70.5)
var _material: StandardMaterial3D

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _blocks.is_empty():
		generate_lab()

func _process(_delta: float) -> void:
	var rebuilt := 0
	for key in _dirty.keys():
		_dirty.erase(key)
		if not _streaming or _is_chunk_near(key):
			_rebuild_chunk(key)
			rebuilt += 1
			if rebuilt >= rebuild_budget:
				break

static func pack_color(color: Color) -> int:
	return 0x01000000 | (clampi(roundi(color.r * 255.0), 0, 255) << 16) | (clampi(roundi(color.g * 255.0), 0, 255) << 8) | clampi(roundi(color.b * 255.0), 0, 255)

static func block_color(packed: int) -> Color:
	return Color(float((packed >> 16) & 255) / 255.0, float((packed >> 8) & 255) / 255.0, float(packed & 255) / 255.0, 1.0)

func _index(cell: Vector3i) -> int:
	return cell.y + dimensions.y * (cell.x + dimensions.x * cell.z)

func is_in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < dimensions.x and cell.y < dimensions.y and cell.z < dimensions.z

func get_block(cell: Vector3i) -> int:
	if not is_in_bounds(cell) or _blocks.is_empty():
		return 0
	return _blocks[_index(cell)]

func set_block(cell: Vector3i, color: int) -> void:
	if not is_in_bounds(cell) or cell.y == 0:
		return
	var before := get_block(cell)
	var after := 0 if color == 0 else (color & 0x00ffffff) | 0x01000000
	if before == after:
		return
	var changes: Array = []
	_change_block(cell, after, changes)
	if before != 0 and after == 0:
		_collapse_neighbors([cell], changes)
	blocks_changed.emit(changes)

func remove_blocks(cells: Array[Vector3i], protect_lower_layer: bool = false) -> void:
	var changes: Array = []
	var removed: Array[Vector3i] = []
	for cell in cells:
		if not is_in_bounds(cell) or cell.y <= (1 if protect_lower_layer else 0) or get_block(cell) == 0:
			continue
		_change_block(cell, 0, changes)
		removed.append(cell)
	if not removed.is_empty():
		_collapse_neighbors(removed, changes)
		blocks_changed.emit(changes)

func _change_block(cell: Vector3i, color: int, changes: Array, collapsed: bool = false) -> void:
	var before := get_block(cell)
	_blocks[_index(cell)] = color
	changes.append({"cell": cell, "before": before, "after": color, "collapsed": collapsed})
	_mark_dirty(cell)

func _mark_dirty(cell: Vector3i) -> void:
	_dirty[_chunk_of(cell)] = true
	for direction in DIRECTIONS:
		var neighbor := cell + direction
		if is_in_bounds(neighbor):
			var chunk := _chunk_of(neighbor)
			if chunk != _chunk_of(cell):
				_dirty[chunk] = true

func _chunk_of(cell: Vector3i) -> Vector3i:
	return Vector3i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE), floori(float(cell.z) / CHUNK_SIZE))

func _collapse_neighbors(removed: Array[Vector3i], changes: Array) -> void:
	# A component survives iff six-neighbor-connected to either bottom layer.
	# Unlike the native link-tree, this performs local search, prioritizing down.
	var checked: Dictionary = {}
	for cell in removed:
		for direction in DIRECTIONS:
			var start := cell + direction
			if get_block(start) == 0 or checked.has(start):
				continue
			var stack: Array[Vector3i] = [start]
			var component: Array[Vector3i] = []
			var visited: Dictionary = {start: true}
			var supported := false
			while not stack.is_empty():
				var current: Vector3i = stack.pop_back()
				component.append(current)
				if current.y <= 1:
					supported = true
					break
				# Reverse push order makes downward support the next pop.
				for i in range(DIRECTIONS.size() - 1, -1, -1):
					var neighbor := current + DIRECTIONS[i]
					if get_block(neighbor) != 0 and not visited.has(neighbor):
						if neighbor.y <= 1 or checked.has(neighbor):
							supported = true
							break
						visited[neighbor] = true
						stack.append(neighbor)
				if supported:
					break
			if supported:
				# Only visited cells proven connected through this searched path.
				for member in component:
					checked[member] = true
			else:
				for member in component:
					checked[member] = true
					_change_block(member, 0, changes, true)

func explode(position: Vector3, _radius: float = 1.6) -> void:
	# Native grenade terrain damage is always a centered 3 x 3 x 3 cube.
	# Radius belongs to player damage/visuals and does not change this block set.
	var cells: Array[Vector3i] = []
	var center := Vector3i(position.floor())
	for z in range(center.z - 1, center.z + 2):
		for x in range(center.x - 1, center.x + 2):
			for y in range(center.y - 1, center.y + 2):
				cells.append(Vector3i(x, y, z))
	remove_blocks(cells, true)

func explode_sphere(position: Vector3, radius: float) -> void:
	var cells: Array[Vector3i] = []
	var center := Vector3i(position.floor())
	var extent := ceili(radius)
	for z in range(center.z - extent, center.z + extent + 1):
		for x in range(center.x - extent, center.x + extent + 1):
			for y in range(center.y - extent, center.y + extent + 1):
				var cell := Vector3i(x, y, z)
				if (Vector3(cell) + Vector3.ONE * 0.5).distance_squared_to(position) <= radius * radius:
					cells.append(cell)
	remove_blocks(cells, true)

func cast_voxel(origin: Vector3, direction: Vector3, max_dist: float = 128.0) -> Dictionary:
	var miss := {"hit": false, "cell": Vector3i.ZERO, "normal": Vector3i.ZERO, "position": origin + direction.normalized() * max_dist}
	if direction.length_squared() < 0.000001 or max_dist < 0.0:
		return miss
	var ray := direction.normalized()
	var cell := Vector3i(origin.floor())
	var step := Vector3i(signi(roundi(ray.x * 1000000.0)), signi(roundi(ray.y * 1000000.0)), signi(roundi(ray.z * 1000000.0)))
	var delta := Vector3(INF, INF, INF)
	var next := Vector3(INF, INF, INF)
	for axis in range(3):
		if absf(ray[axis]) > 0.000001:
			delta[axis] = absf(1.0 / ray[axis])
			var boundary := float(cell[axis] + (1 if step[axis] > 0 else 0))
			next[axis] = (boundary - origin[axis]) / ray[axis]
	var traveled := 0.0
	var normal := Vector3i.ZERO
	# Traversal advances one grid face at a time, including from outside bounds.
	while traveled <= max_dist:
		if get_block(cell) != 0:
			return {"hit": true, "cell": cell, "normal": normal, "position": origin + ray * traveled}
		var axis := 0
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

func get_spawn_position() -> Vector3:
	return _spawn

func clear_world(size: Vector3i) -> void:
	for chunk in _chunks.values():
		remove_child(chunk)
		chunk.queue_free()
	_chunks.clear()
	_dirty.clear()
	dimensions = size
	_blocks.resize(size.x * size.y * size.z)
	_blocks.fill(0)
	_view_chunk = Vector3i(-1000, 0, -1000)

func generate_lab() -> void:
	clear_world(Vector3i(96, 32, 96))
	_streaming = false
	map_name = "Blockfield Test Grounds"
	_spawn = Vector3(48.5, 5.0, 70.5)
	var grass := pack_color(Color("668d57"))
	var soil := pack_color(Color("79694c"))
	for z in range(96):
		for x in range(96):
			for y in range(4):
				_blocks[_index(Vector3i(x, y, z))] = grass if y == 3 else soil
	# Border berms, rifle/SMG/shotgun ranges and destructible bunkers.
	_fill_box(Vector3i(0, 4, 0), Vector3i(96, 7, 2), 0x014a6254)
	_fill_box(Vector3i(0, 4, 94), Vector3i(96, 7, 96), 0x014a6254)
	_fill_box(Vector3i(0, 4, 2), Vector3i(2, 7, 94), 0x014a6254)
	_fill_box(Vector3i(94, 4, 2), Vector3i(96, 7, 94), 0x014a6254)
	for x in [14, 36, 58, 80]:
		_fill_box(Vector3i(x, 4, 18), Vector3i(x + 8, 10, 20), 0x01b58a62)
		_fill_box(Vector3i(x, 4, 20), Vector3i(x + 2, 10, 30), 0x01b58a62)
		_fill_box(Vector3i(x + 6, 4, 20), Vector3i(x + 8, 10, 30), 0x01b58a62)
		_fill_box(Vector3i(x, 10, 18), Vector3i(x + 8, 11, 30), 0x01877768)
		_fill_box(Vector3i(x + 3, 4, 41), Vector3i(x + 5, 8, 43), 0x01cc6657)
		_fill_box(Vector3i(x + 2, 8, 40), Vector3i(x + 6, 10, 44), 0x01dccaad)
	# A supported bridge: cut both pillars to test disconnected collapse.
	_fill_box(Vector3i(12, 4, 57), Vector3i(14, 11, 59), 0x016989ac)
	_fill_box(Vector3i(28, 4, 57), Vector3i(30, 11, 59), 0x016989ac)
	_fill_box(Vector3i(12, 11, 56), Vector3i(30, 12, 60), 0x018cb8cd)
	# Steps and trench to exercise jumping and crouching.
	for step_number in range(6):
		_fill_box(Vector3i(68 + step_number * 2, 4, 58), Vector3i(70 + step_number * 2, 5 + step_number, 66), 0x018b936a)
	_fill_box(Vector3i(38, 2, 53), Vector3i(56, 4, 56), 0)
	_mark_all_chunks()
	rebuild_now()
	map_loaded.emit(map_name)

func _fill_box(start: Vector3i, end: Vector3i, color: int) -> void:
	for z in range(start.z, end.z):
		for x in range(start.x, end.x):
			for y in range(start.y, end.y):
				var cell := Vector3i(x, y, z)
				if is_in_bounds(cell):
					_blocks[_index(cell)] = color

func load_vxl(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	return load_vxl_bytes(file.get_buffer(file.get_length()), path.get_file().get_basename())

func load_vxl_bytes(bytes: PackedByteArray, title: String = "Imported VXL") -> Error:
	var decoded: Dictionary = VXL_READER.decode(bytes)
	if decoded.error != OK:
		push_warning("VXL import failed: %s at byte %d" % [decoded.get("message", "Invalid data"), decoded.get("offset", 0)])
		return decoded.error
	clear_world(decoded.size)
	_blocks = decoded.blocks
	map_name = title
	_streaming = true
	var center_x := dimensions.x / 2
	var center_z := dimensions.z / 2
	var surface_y := 1
	for y in range(dimensions.y - 1, 0, -1):
		if get_block(Vector3i(center_x, y, center_z)) != 0:
			surface_y = y + 1
			break
	_spawn = Vector3(center_x + 0.5, surface_y + 1.0, center_z + 0.5)
	set_view_position(_spawn)
	rebuild_now()
	map_loaded.emit(map_name)
	return OK

func encode_vxl() -> PackedByteArray:
	return VXL_READER.encode(_blocks, dimensions)

func save_vxl(path: String) -> Error:
	var bytes := encode_vxl()
	if bytes.is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	return file.get_error()

func set_view_position(position: Vector3) -> void:
	if not _streaming:
		return
	var center := _chunk_of(Vector3i(position.floor()))
	if center.x == _view_chunk.x and center.z == _view_chunk.z:
		return
	_view_chunk = center
	for key in _chunks.keys():
		if not _is_chunk_near(key):
			var chunk: Node3D = _chunks[key]
			remove_child(chunk)
			chunk.queue_free()
			_chunks.erase(key)
	for z in range(maxi(0, center.z - render_radius), mini(ceili(float(dimensions.z) / CHUNK_SIZE), center.z + render_radius + 1)):
		for x in range(maxi(0, center.x - render_radius), mini(ceili(float(dimensions.x) / CHUNK_SIZE), center.x + render_radius + 1)):
			for y in range(ceili(float(dimensions.y) / CHUNK_SIZE)):
				var key := Vector3i(x, y, z)
				if not _chunks.has(key):
					_dirty[key] = true

func _is_chunk_near(key: Vector3i) -> bool:
	return abs(key.x - _view_chunk.x) <= render_radius and abs(key.z - _view_chunk.z) <= render_radius

func _mark_all_chunks() -> void:
	for z in range(ceili(float(dimensions.z) / CHUNK_SIZE)):
		for x in range(ceili(float(dimensions.x) / CHUNK_SIZE)):
			for y in range(ceili(float(dimensions.y) / CHUNK_SIZE)):
				_dirty[Vector3i(x, y, z)] = true

func rebuild_now() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for key in _dirty.keys():
		if not _streaming or _is_chunk_near(key):
			_rebuild_chunk(key)
	_dirty.clear()

func _rebuild_chunk(key: Vector3i) -> void:
	var chunk: StaticBody3D
	if _chunks.has(key):
		chunk = _chunks[key]
	else:
		chunk = CHUNK_SCRIPT.new()
		chunk.coordinate = key
		chunk.position = Vector3(key * CHUNK_SIZE)
		chunk.name = "Chunk_%d_%d_%d" % [key.x, key.y, key.z]
		add_child(chunk)
		_chunks[key] = chunk
	chunk.rebuild(self, _material)

func get_stats() -> Dictionary:
	var faces := 0
	for chunk in _chunks.values():
		faces += chunk.face_count
	return {"dimensions": dimensions, "chunks": _chunks.size(), "faces": faces, "dirty_chunks": _dirty.size(), "data_bytes": _blocks.size() * 4}
