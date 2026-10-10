class_name VoxelAmbientOcclusion
extends RefCounted
## GLMapChunk::calcAOID: native eight-neighbor atlas with fragment UVs.
## Source tangent axes are mapped from Z-down to Godot Y-up.

const ATLAS: Texture2D = preload("res://assets/openspades/images/Gfx/AmbientOcclusion.png")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const HALO_SIZE := 18
const HALO_VOLUME := HALO_SIZE * HALO_SIZE * HALO_SIZE
# Offsets use y + 18 * (x + 18 * z). Each row is -u,+u,-v,+v,-u+v,-u-v,+u+v,+u-v.
const OFFSETS := [
	[1, -1, -324, 324, 325, -323, 323, -325],
	[1, -1, 324, -324, -323, 325, -325, 323],
	[-18, 18, -324, 324, 306, -342, 342, -306],
	[18, -18, -324, 324, 342, -306, 306, -342],
	[1, -1, 18, -18, -17, 19, -19, 17],
	[1, -1, -18, 18, 19, -17, 17, -19]
]
# Atlas corners are (0,0),(15,0),(0,15),(15,15); chunk corners follow VoxelChunk.
const CORNER_LOOKUP := [[1, 0, 2, 3], [1, 0, 2, 3], [2, 3, 1, 0], [1, 0, 2, 3], [1, 0, 2, 3], [1, 0, 2, 3]]
static var _corners := PackedFloat32Array()
static var _uvs := PackedVector2Array()
static var _texture: Texture2D
static var _generation := -1

static func get_texture() -> Texture2D:
	if _texture == null or _generation != EXTENSIONS.get_generation():
		_generation = EXTENSIONS.get_generation()
		_texture = EXTENSIONS.texture("res://assets/openspades/images/Gfx/AmbientOcclusion.png")
		if _texture == null or _texture.get_size() != Vector2(256, 256):
			_texture = ATLAS
		_corners.clear()
	return _texture

static func initialize() -> void:
	get_texture()
	if not _corners.is_empty():
		return
	var image := _texture.get_image()
	assert(image != null and image.get_size() == Vector2i(256, 256), "Native AO atlas must be 256 x 256")
	_corners.resize(256 * 4)
	_uvs.resize(256 * 4)
	for tile in range(256):
		var x := (tile & 15) * 16
		var y := (tile >> 4) * 16
		_corners[tile * 4] = image.get_pixel(x, y).r
		_corners[tile * 4 + 1] = image.get_pixel(x + 15, y).r
		_corners[tile * 4 + 2] = image.get_pixel(x, y + 15).r
		_corners[tile * 4 + 3] = image.get_pixel(x + 15, y + 15).r
		for corner in range(4):
			_uvs[tile * 4 + corner] = Vector2(x + (corner & 1) * 15 + 0.5, y + (corner >> 1) * 15 + 0.5) / 256.0

static func atlas_corner(tile: int, corner: int) -> float:
	initialize()
	return _corners[tile * 4 + corner]

static func face_corner(tile: int, face: int, corner: int) -> float:
	return _corners[tile * 4 + CORNER_LOOKUP[face][corner]]

static func face_uv(tile: int, face: int, corner: int) -> Vector2:
	return _uvs[tile * 4 + CORNER_LOOKUP[face][corner]]

static func tile_id(solids: PackedByteArray, center: int, face: int) -> int:
	var mask := 0
	for bit in range(8):
		if solids[center + OFFSETS[face][bit]] != 0:
			mask |= 1 << bit
	return mask

static func build_halo(world: Node3D, base: Vector3i) -> Dictionary:
	var size: Vector3i = world.dimensions
	var data: PackedInt32Array = world._blocks
	var water: bool = world.water_enabled
	var native := size == Vector3i(512, 64, 512)
	var blocks := PackedInt32Array()
	var solids := PackedByteArray()
	blocks.resize(HALO_VOLUME)
	solids.resize(HALO_VOLUME)
	var index := 0
	for hz in range(HALO_SIZE):
		var z := base.z + hz - 1
		for hx in range(HALO_SIZE):
			var x := base.x + hx - 1
			var valid := x >= 0 and x < size.x and z >= 0 and z < size.z
			var column := size.y * (x + size.x * z)
			var ao_column := size.y * (posmod(x, size.x) + size.x * posmod(z, size.z)) if native else column
			for hy in range(HALO_SIZE):
				var y := base.y + hy - 1
				if valid and y >= 0 and y < size.y:
					blocks[index] = data[column + y]
				# GLMapChunk::IsSolid wraps horizontal native coordinates,
				# treats below-map as solid, and uses source z62 for water z63.
				if y < 0:
					solids[index] = 1
				elif y < size.y and (valid or native):
					var sample_y := 1 if water and y == 0 and size.y > 1 else y
					solids[index] = 1 if data[ao_column + sample_y] != 0 else 0
				index += 1
	return {"blocks": blocks, "solids": solids}
