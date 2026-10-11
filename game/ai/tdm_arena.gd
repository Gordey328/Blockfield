class_name TdmArena
extends RefCounted
## Authored, compact offline combat map. These are bootstrap cells, not gameplay edits.
## Coordinates and actor heights follow the shared source-motion contract.

const DATA = preload("res://world/voxel_data.gd")
const SIZE: Vector3i = Vector3i(80, 24, 56)

static func build() -> VoxelData:
	var data: VoxelData = DATA.new()
	data.clear(SIZE)
	data.seed_box(Vector3i.ZERO, Vector3i(80, 4, 56), 0x0175664f)
	data.seed_box(Vector3i(0, 3, 0), Vector3i(80, 4, 56), 0x01838d68)
	# Three-block perimeter keeps shared player clipping and arena silhouettes clear.
	data.seed_box(Vector3i(0, 4, 0), Vector3i(80, 7, 2), 0x0155695b)
	data.seed_box(Vector3i(0, 4, 54), Vector3i(80, 7, 56), 0x0155695b)
	data.seed_box(Vector3i(0, 4, 2), Vector3i(2, 7, 54), 0x0155695b)
	data.seed_box(Vector3i(78, 4, 2), Vector3i(80, 7, 54), 0x0155695b)
	# Staggered high cover protects spawn approaches while leaving three routes.
	_box(data, 21, 23, 22, 31, 3, 0x01879cba)
	_box(data, 57, 59, 25, 34, 3, 0x01a9ba83)
	_box(data, 33, 35, 16, 24, 3, 0x01b69a72)
	_box(data, 45, 47, 32, 40, 3, 0x01b69a72)
	_box(data, 38, 42, 26, 29, 2, 0x01b7a17f)
	# Break sightlines in the outer lanes without closing either flank.
	_box(data, 16, 20, 11, 14, 2, 0x0184959f)
	_box(data, 28, 32, 41, 44, 2, 0x0184959f)
	_box(data, 48, 52, 12, 15, 2, 0x019eaa83)
	_box(data, 60, 64, 42, 45, 2, 0x019eaa83)
	_box(data, 38, 40, 8, 11, 3, 0x01947f69)
	_box(data, 40, 42, 45, 48, 3, 0x01947f69)
	# Colored spawn plinths are flush with the floor and do not alter movement.
	data.seed_box(Vector3i(4, 3, 16), Vector3i(11, 4, 41), 0x015f80a7)
	data.seed_box(Vector3i(69, 3, 16), Vector3i(76, 4, 41), 0x018baa60)
	return data

static func _box(data: VoxelData, x0: int, x1: int, z0: int, z1: int,
		height: int, color: int) -> void:
	data.seed_box(Vector3i(x0, 4, z0), Vector3i(x1, 4 + height, z1), color)

static func metadata() -> Dictionary:
	var blue: Array[Vector3] = [Vector3(7.5, 4, 28.5), Vector3(7.5, 4, 18.5), Vector3(7.5, 4, 38.5)]
	var green: Array[Vector3] = [Vector3(72.5, 4, 28.5), Vector3(72.5, 4, 18.5), Vector3(72.5, 4, 38.5)]
	var cover: Array[Vector3] = [
		Vector3(19.5, 4, 25.5), Vector3(24.5, 4, 25.5),
		Vector3(55.5, 4, 29.5), Vector3(60.5, 4, 29.5),
		Vector3(31.5, 4, 20.5), Vector3(36.5, 4, 20.5),
		Vector3(43.5, 4, 35.5), Vector3(48.5, 4, 35.5),
		Vector3(36.5, 4, 9.5), Vector3(41.5, 4, 9.5),
		Vector3(38.5, 4, 46.5), Vector3(43.5, 4, 46.5)]
	var north: Array[Vector3] = [Vector3(24.5, 4, 7.5), Vector3(43.5, 4, 7.5), Vector3(61.5, 4, 19.5)]
	var south: Array[Vector3] = [Vector3(55.5, 4, 49.5), Vector3(36.5, 4, 49.5), Vector3(18.5, 4, 36.5)]
	var routes: Array = [north, south]
	var rallies: Array[Vector3] = [Vector3(36.5, 4, 29.5), Vector3(43.5, 4, 25.5)]
	return {"title":"Crossroads", "dimensions":SIZE, "team_spawns":[blue, green],
		"cover_points":cover, "flank_routes":routes, "rally_points":rallies,
		"floor_y":4.0, "navigation_ceiling":12, "authored":true}
