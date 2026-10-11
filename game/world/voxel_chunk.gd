class_name VoxelChunk
extends StaticBody3D
## One indexed render mesh and one static collision shape per 16-cube chunk.

const AO = preload("res://world/voxel_ao.gd")
const DIRECTIONS: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]
const CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]
]
const TRIANGLES: Array[int] = [0, 2, 1, 0, 3, 2]
const CHUNK_SIZE := 16
const HALO_FACE_OFFSETS: Array[int] = [18, -18, 1, -1, 324, -324]

# Packed span = (first face << 3) | face count. Hidden cells have span zero.
# Retain two bytes of AO metadata per face, rather than full mesh arrays.
class BuildJob:
	extends RefCounted
	var base: Vector3i
	var size: Vector3i
	var water: bool
	var native: bool
	var rebuild_collision: bool
	var stage := 0
	var cursor := 0
	var elapsed_usec := 0
	var faces := 0
	var blocks := PackedInt32Array()
	var solids := PackedByteArray()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var ao_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var spans := PackedInt32Array()
	var tiles := PackedByteArray()
	var directions := PackedByteArray()
	var collision_mask := PackedByteArray()
	var collision_slices := PackedByteArray()
	var collision_vertices := PackedVector3Array()

var coordinate := Vector3i.ZERO
var face_count := 0
var collision_face_count := 0
var build_usec := 0
var mesh_instance: MeshInstance3D
var collision: CollisionShape3D
var publish_usec := 0
var _job: BuildJob
var _cell_spans := PackedInt32Array()
var _face_tiles := PackedByteArray()
var _face_directions := PackedByteArray()
var _attribute_stride := 0
var _color_offset := 0
var _uv_offset := 0

func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	collision = CollisionShape3D.new()
	add_child(collision)

func rebuild(world: Node3D, material: Material, rebuild_collision: bool = true) -> void:
	begin_rebuild(world, rebuild_collision)
	while not advance_rebuild(world, material):
		pass

func begin_rebuild(world: Node3D, rebuild_collision: bool = true) -> void:
	AO.initialize()
	_job = BuildJob.new()
	_job.base = coordinate * CHUNK_SIZE
	_job.size = world.dimensions
	_job.water = world.water_enabled
	_job.native = _job.size == Vector3i(512, 64, 512)
	_job.rebuild_collision = rebuild_collision
	_job.blocks.resize(AO.HALO_VOLUME)
	_job.solids.resize(AO.HALO_VOLUME)
	_job.spans.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
	if rebuild_collision:
		_job.collision_mask.resize(6 * CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
		_job.collision_slices.resize(6 * CHUNK_SIZE)

func cancel_rebuild() -> void:
	_job = null

func is_rebuilding() -> bool:
	return _job != null

func advance_rebuild(world: Node3D, material: Material, pending_colors: Dictionary = {}) -> bool:
	# One 18-cell halo column, 16-cell mesh column, collision plane or publish.
	# No retained full-map PackedArray: shots cannot trigger map-sized COW here.
	if _job == null:
		return true
	var started := Time.get_ticks_usec()
	match _job.stage:
		0:
			_build_halo_column(world)
			_job.cursor += 1
			if _job.cursor == AO.HALO_SIZE * AO.HALO_SIZE:
				_job.stage = 1
				_job.cursor = 0
		1:
			_build_mesh_column(world)
			_job.cursor += 1
			if _job.cursor == CHUNK_SIZE * CHUNK_SIZE:
				_job.stage = 2 if _job.rebuild_collision else 3
				_job.cursor = 0
		2:
			_merge_collision_plane(_job.cursor)
			_job.cursor += 1
			if _job.cursor == 6 * CHUNK_SIZE:
				_job.stage = 3
		3:
			_publish(world, material, pending_colors)
			publish_usec = Time.get_ticks_usec() - started
			build_usec = _job.elapsed_usec + publish_usec
			_job = null
			return true
	_job.elapsed_usec += Time.get_ticks_usec() - started
	return false

func _build_halo_column(world: Node3D) -> void:
	var job := _job
	var base := job.base
	var size := job.size
	var water := job.water
	var native := job.native
	var x := base.x + job.cursor % AO.HALO_SIZE - 1
	var z := base.z + job.cursor / AO.HALO_SIZE - 1
	var valid := x >= 0 and x < size.x and z >= 0 and z < size.z
	var column := size.y * (x + size.x * z)
	var ao_column := size.y * (posmod(x, size.x) + size.x * posmod(z, size.z)) if native else column
	var map_blocks: PackedInt32Array = world._blocks
	# Move ownership into locals before mutating. Merely assigning a packed
	# member to a local would retain two references and copy it on each unit.
	var blocks := job.blocks
	var solids := job.solids
	job.blocks = PackedInt32Array()
	job.solids = PackedByteArray()
	var first := job.cursor * AO.HALO_SIZE
	for hy in range(AO.HALO_SIZE):
		var y := base.y + hy - 1
		if valid and y >= 0 and y < size.y:
			blocks[first + hy] = map_blocks[column + y]
		if y < 0:
			solids[first + hy] = 1
		elif y < size.y and (valid or native):
			var sample_y := 1 if water and y == 0 and size.y > 1 else y
			solids[first + hy] = 1 if map_blocks[ao_column + sample_y] != 0 else 0
	job.blocks = blocks
	job.solids = solids

func _build_mesh_column(world: Node3D) -> void:
	var job := _job
	var base := job.base
	var water := job.water
	var rebuild_collision := job.rebuild_collision
	var blocks := job.blocks
	var solids := job.solids
	var vertices := job.vertices
	var normals := job.normals
	var colors := job.colors
	var ao_uvs := job.ao_uvs
	var indices := job.indices
	var spans := job.spans
	var tiles := job.tiles
	var directions := job.directions
	var collision_mask := job.collision_mask
	var collision_slices := job.collision_slices
	job.vertices = PackedVector3Array()
	job.normals = PackedVector3Array()
	job.colors = PackedColorArray()
	job.ao_uvs = PackedVector2Array()
	job.indices = PackedInt32Array()
	job.spans = PackedInt32Array()
	job.tiles = PackedByteArray()
	job.directions = PackedByteArray()
	job.collision_mask = PackedByteArray()
	job.collision_slices = PackedByteArray()
	var faces := job.faces
	var local_x := job.cursor % CHUNK_SIZE
	var local_z := job.cursor / CHUNK_SIZE
	var column := AO.HALO_SIZE * (local_x + 1 + AO.HALO_SIZE * (local_z + 1))
	for local_y in range(CHUNK_SIZE):
		var index := column + local_y + 1
		var packed := blocks[index]
		if packed == 0:
			continue
		var local_cell := Vector3(local_x, local_y, local_z)
		var color := Color()
		var render_voxel := not (water and base.y + local_y == 0 and blocks[index + 1] == 0)
		var first_face := faces
		for face in range(6):
			var air_index := index + HALO_FACE_OFFSETS[face]
			if blocks[air_index] != 0:
				continue
			if rebuild_collision:
				var slice: int = local_x if face < 2 else (local_y if face < 4 else local_z)
				var u: int = local_y if face < 2 else local_x
				var v: int = local_z if face < 4 else local_y
				var plane := face * CHUNK_SIZE + slice
				collision_slices[plane] = 1
				collision_mask[plane * CHUNK_SIZE * CHUNK_SIZE + u + CHUNK_SIZE * v] = 1
			if not render_voxel:
				continue
			if faces == first_face:
				color = world.get_render_color(base + Vector3i(local_x, local_y, local_z), packed)
			faces += 1
			var tile: int = AO.tile_id(solids, air_index, face)
			tiles.append(tile)
			directions.append(face)
			var first := vertices.size()
			for corner in range(4):
				vertices.append(local_cell + CORNERS[face][corner])
				normals.append(Vector3(DIRECTIONS[face]))
				colors.append(Color(color.r, color.g, color.b, AO.face_corner(tile, face, corner)))
				ao_uvs.append(AO.face_uv(tile, face, corner))
			for corner in TRIANGLES:
				indices.append(first + corner)
		if faces != first_face:
			spans[local_y + CHUNK_SIZE * (local_x + CHUNK_SIZE * local_z)] = (first_face << 3) | (faces - first_face)
	job.vertices = vertices
	job.normals = normals
	job.colors = colors
	job.ao_uvs = ao_uvs
	job.indices = indices
	job.spans = spans
	job.tiles = tiles
	job.directions = directions
	job.collision_mask = collision_mask
	job.collision_slices = collision_slices
	job.faces = faces

func _publish(world: Node3D, material: Material, pending_colors: Dictionary) -> void:
	# Hits/repaints arriving after a column was sampled must win at publication.
	for cell: Vector3i in pending_colors:
		var local_cell := cell - _job.base
		var span := _job.spans[_local_index(local_cell)]
		var color: Color = world.get_render_color(cell, world.get_block(cell))
		for vertex in range((span >> 3) * 4, ((span >> 3) + (span & 7)) * 4):
			var previous := _job.colors[vertex]
			_job.colors[vertex] = Color(color.r, color.g, color.b, previous.a)
	var next_shape: ConcavePolygonShape3D
	if _job.rebuild_collision and not _job.collision_vertices.is_empty():
		next_shape = ConcavePolygonShape3D.new()
		next_shape.set_faces(_job.collision_vertices)
	var next_mesh: ArrayMesh
	if not _job.vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _job.vertices
		arrays[Mesh.ARRAY_NORMAL] = _job.normals
		arrays[Mesh.ARRAY_COLOR] = _job.colors
		arrays[Mesh.ARRAY_TEX_UV2] = _job.ao_uvs
		arrays[Mesh.ARRAY_INDEX] = _job.indices
		next_mesh = ArrayMesh.new()
		next_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		next_mesh.surface_set_material(0, material)
		var format := next_mesh.surface_get_format(0)
		_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, _job.vertices.size())
		_color_offset = RenderingServer.mesh_surface_get_format_offset(format, _job.vertices.size(), Mesh.ARRAY_COLOR)
		_uv_offset = RenderingServer.mesh_surface_get_format_offset(format, _job.vertices.size(), Mesh.ARRAY_TEX_UV2)
		_cell_spans = _job.spans
		_face_tiles = _job.tiles
		_face_directions = _job.directions
	else:
		_cell_spans.clear()
		_face_tiles.clear()
		_face_directions.clear()
	mesh_instance.mesh = next_mesh
	face_count = _job.faces
	if _job.rebuild_collision:
		collision.shape = next_shape
		collision_face_count = _job.collision_vertices.size() / 6

func _local_index(cell: Vector3i) -> int:
	return cell.y + CHUNK_SIZE * (cell.x + CHUNK_SIZE * cell.z)

func update_color(world: Node3D, cell: Vector3i) -> int:
	# Color changes touch at most six faces; UVs/AO stay byte-identical. No mesh
	# readback, halo sampling, topology allocation or collider work on this path.
	if mesh_instance.mesh == null or _cell_spans.is_empty():
		return 0
	var span := _cell_spans[_local_index(cell - coordinate * CHUNK_SIZE)]
	if (span & 7) == 0:
		return 0
	var color: Color = world.get_render_color(cell, world.get_block(cell))
	var attributes := PackedByteArray()
	attributes.resize((span & 7) * 4 * _attribute_stride)
	var vertex := 0
	for face_index in range(span >> 3, (span >> 3) + (span & 7)):
		var tile := _face_tiles[face_index]
		var face := _face_directions[face_index]
		for corner in range(4):
			var offset := vertex * _attribute_stride + _color_offset
			attributes[offset] = int(clampf(color.r * 255.0, 0.0, 255.0))
			attributes[offset + 1] = int(clampf(color.g * 255.0, 0.0, 255.0))
			attributes[offset + 2] = int(clampf(color.b * 255.0, 0.0, 255.0))
			attributes[offset + 3] = int(clampf(AO.face_corner(tile, face, corner) * 255.0, 0.0, 255.0))
			var uv := AO.face_uv(tile, face, corner)
			attributes.encode_float(vertex * _attribute_stride + _uv_offset, uv.x)
			attributes.encode_float(vertex * _attribute_stride + _uv_offset + 4, uv.y)
			vertex += 1
	var mesh := mesh_instance.mesh as ArrayMesh
	var byte_offset := (span >> 3) * 4 * _attribute_stride
	mesh.surface_update_attribute_region(0, byte_offset, attributes)
	if DisplayServer.get_name() == "headless":
		# Pinned Godot's Dummy storage ignores region writes. Keep deterministic
		# headless mesh inspection truthful by replacing its stored raw surface,
		# with identical vertex/index/AO bytes and the same ArrayMesh/RID. The
		# real Compatibility renderer never reads or replaces a surface here.
		var surface: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
		var stored: PackedByteArray = surface.attribute_data
		for index in range(attributes.size()):
			stored[byte_offset + index] = attributes[index]
		surface.attribute_data = stored
		RenderingServer.mesh_surface_remove(mesh.get_rid(), 0)
		RenderingServer.mesh_add_surface(mesh.get_rid(), surface)
	return attributes.size()

func get_cached_color_bytes() -> int:
	return _cell_spans.size() * 4 + _face_tiles.size() + _face_directions.size()

func _merge_collision_plane(plane: int) -> void:
	# Color/AO seams are irrelevant to collision. Merge exact coplanar exposed
	# cells into rectangles, keeping holes, steps and outward triangle winding.
	if _job.collision_slices[plane] == 0:
		return
	var mask := _job.collision_mask
	var vertices := _job.collision_vertices
	_job.collision_mask = PackedByteArray()
	_job.collision_vertices = PackedVector3Array()
	var face := plane / CHUNK_SIZE
	var slice := plane % CHUNK_SIZE
	var offset := plane * CHUNK_SIZE * CHUNK_SIZE
	for v in range(CHUNK_SIZE):
		for u in range(CHUNK_SIZE):
			if mask[offset + u + CHUNK_SIZE * v] == 0:
				continue
			var width := 1
			while u + width < CHUNK_SIZE and mask[offset + u + width + CHUNK_SIZE * v] != 0:
				width += 1
			var height := 1
			while v + height < CHUNK_SIZE:
				var complete := true
				for x in range(u, u + width):
					if mask[offset + x + CHUNK_SIZE * (v + height)] == 0:
						complete = false
						break
				if not complete:
					break
				height += 1
			for y in range(v, v + height):
				for x in range(u, u + width):
					mask[offset + x + CHUNK_SIZE * y] = 0
			var origin := Vector3(slice, u, v) if face < 2 else (Vector3(u, slice, v) if face < 4 else Vector3(u, v, slice))
			var scale := Vector3(1, width, height) if face < 2 else (Vector3(width, 1, height) if face < 4 else Vector3(width, height, 1))
			for corner in TRIANGLES:
				vertices.append(origin + CORNERS[face][corner] * scale)
	_job.collision_mask = mask
	_job.collision_vertices = vertices
