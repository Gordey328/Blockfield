class_name VoxelChunk
extends StaticBody3D
## One render mesh and one static collision shape for an entire 16-cube chunk.

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

var coordinate := Vector3i.ZERO
var face_count := 0
var mesh_instance: MeshInstance3D
var collision: CollisionShape3D

func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	collision = CollisionShape3D.new()
	add_child(collision)

func rebuild(world: Node3D, material: Material) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var base := coordinate * CHUNK_SIZE
	face_count = 0
	for local_z in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			for local_y in range(CHUNK_SIZE):
				var local_cell := Vector3i(local_x, local_y, local_z)
				var cell := base + local_cell
				var packed: int = world.get_block(cell)
				if packed == 0:
					continue
				var color := Color(float((packed >> 16) & 255) / 255.0, float((packed >> 8) & 255) / 255.0, float(packed & 255) / 255.0)
				for face in range(6):
					if world.get_block(cell + DIRECTIONS[face]) != 0:
						continue
					face_count += 1
					# Slight face shading keeps shape legible without costly lights.
					var shade := 1.0 if face == 2 else (0.55 if face == 3 else (0.83 if face < 2 else 0.70))
					var face_color := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
					for corner in TRIANGLES:
						vertices.append(Vector3(local_cell) + CORNERS[face][corner])
						normals.append(Vector3(DIRECTIONS[face]))
						colors.append(face_color)
	if vertices.is_empty():
		mesh_instance.mesh = null
		collision.shape = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	mesh_instance.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	collision.shape = shape
