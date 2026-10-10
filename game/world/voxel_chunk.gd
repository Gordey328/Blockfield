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

var coordinate := Vector3i.ZERO
var face_count := 0
var collision_face_count := 0
var build_usec := 0
var mesh_instance: MeshInstance3D
var collision: CollisionShape3D

func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	collision = CollisionShape3D.new()
	add_child(collision)

func rebuild(world: Node3D, material: Material, rebuild_collision: bool = true) -> void:
	var started := Time.get_ticks_usec()
	AO.initialize()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var ao_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var collision_vertices := PackedVector3Array()
	var collision_mask := PackedByteArray()
	var collision_slices := PackedByteArray()
	if rebuild_collision:
		collision_mask.resize(6 * CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
		collision_slices.resize(6 * CHUNK_SIZE)
	var base := coordinate * CHUNK_SIZE
	var halo: Dictionary = AO.build_halo(world, base)
	var blocks: PackedInt32Array = halo.blocks
	var solids: PackedByteArray = halo.solids
	var water: bool = world.water_enabled
	face_count = 0
	for local_z in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			var column := 18 * (local_x + 1 + 18 * (local_z + 1))
			for local_y in range(CHUNK_SIZE):
				var index := column + local_y + 1
				var packed := blocks[index]
				if packed == 0:
					continue
				var local_cell := Vector3(local_x, local_y, local_z)
				var color := Color(float((packed >> 16) & 255) / 255.0, float((packed >> 8) & 255) / 255.0, float(packed & 255) / 255.0)
				var render_voxel := not (water and base.y + local_y == 0 and blocks[index + 1] == 0)
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
					face_count += 1
					var tile: int = AO.tile_id(solids, air_index, face)
					var first := vertices.size()
					for corner in range(4):
						vertices.append(local_cell + CORNERS[face][corner])
						normals.append(Vector3(DIRECTIONS[face]))
						colors.append(Color(color.r, color.g, color.b, AO.face_corner(tile, face, corner)))
						ao_uvs.append(AO.face_uv(tile, face, corner))
					for corner in TRIANGLES:
						indices.append(first + corner)
	if rebuild_collision:
		collision_vertices = _merge_collision_faces(collision_mask, collision_slices)
		collision_face_count = collision_vertices.size() / 6
		if collision_vertices.is_empty():
			collision.shape = null
		else:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(collision_vertices)
			collision.shape = shape
	if vertices.is_empty():
		mesh_instance.mesh = null
	else:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV2] = ao_uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		mesh_instance.mesh = mesh
	build_usec = Time.get_ticks_usec() - started

func _merge_collision_faces(mask: PackedByteArray, slices: PackedByteArray) -> PackedVector3Array:
	# Color/AO seams are irrelevant to collision. Merge exact coplanar exposed
	# cells into rectangles, keeping holes, steps and outward triangle winding.
	var vertices := PackedVector3Array()
	for face in range(6):
		for slice in range(CHUNK_SIZE):
			var plane := face * CHUNK_SIZE + slice
			if slices[plane] == 0:
				continue
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
	return vertices
