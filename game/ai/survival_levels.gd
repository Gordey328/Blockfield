class_name SurvivalLevels
extends RefCounted
## Trusted catalog identities; downloaded scene scripts are never executed.
const CROSSROADS = preload("res://ai/survival_arena.gd")
const PACKAGE = preload("res://world/blockfield_map.gd")
const NAVIGATION = preload("res://ai/zombie_navigation.gd")
const PATHS: Dictionary = {
	"minecraft_chunk": "res://assets/maps/survival_minecraft_chunk.bfmap",
	"mira_hq": "res://assets/maps/survival_mira_hq.bfmap"}

static func load_level(id: String) -> Dictionary:
	if id == "crossroads":
		return {"ok":true, "data":CROSSROADS.build(), "arena":CROSSROADS.metadata(), "metadata":{}, "title":"Crossroads"}
	if not PATHS.has(id): return {"ok":false, "error":"Unknown survival level"}
	var decoded: Dictionary = PACKAGE.load(str(PATHS[id]))
	if decoded.error != OK: return {"ok":false, "error":decoded.message}
	var data: VoxelData = decoded.data
	if data.dimensions.x * data.dimensions.z > NAVIGATION.MAX_COLUMNS:
		return {"ok":false, "error":"Survival level exceeds the navigation budget"}
	var raw: Variant = decoded.metadata.get("survival_arena", {})
	if not raw is Dictionary: return {"ok":false, "error":"Missing survival arena"}
	var owner: Vector3 = _point(raw.get("owner_spawn"))
	var supply: Vector3 = _point(raw.get("supply_point"))
	if not owner.is_finite() or not supply.is_finite() or not PACKAGE.is_valid_spawn(data, owner) or not PACKAGE.is_valid_spawn(data, supply):
		return {"ok":false, "error":"Survival spawn and supply require standing clearance"}
	var sectors: Array[Vector3] = []
	var candidates: Variant = raw.get("spawn_sectors", [])
	if not candidates is Array: return {"ok":false, "error":"Missing emergence sectors"}
	for candidate: Variant in candidates:
		var point: Vector3 = _point(candidate)
		if not point.is_finite() or not PACKAGE.is_valid_spawn(data, point) or point.distance_to(owner) < 12.0:
			return {"ok":false, "error":"Unsafe survival emergence sector"}
		sectors.append(point)
	if sectors.size() < 4: return {"ok":false, "error":"Survival requires four emergence sectors"}
	var floor_value: Variant = raw.get("floor_y")
	var ceiling_value: Variant = raw.get("navigation_ceiling")
	if not _integer(floor_value, 2, data.dimensions.y - 3) or not _integer(ceiling_value, int(floor_value) + 3, data.dimensions.y - 1):
		return {"ok":false, "error":"Invalid survival navigation surface"}
	var title: String = str(decoded.metadata.get("title", id))
	var arena: Dictionary = {"title":title, "authored":true, "floor_y":float(floor_value),
		"navigation_ceiling":int(ceiling_value), "owner_spawn":owner, "player_spawn":owner,
		"supply_point":supply, "supply_points":[supply], "spawn_sectors":sectors, "walk_speed":3.2}
	return {"ok":true, "data":data, "arena":arena, "metadata":decoded.metadata, "title":title}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _point(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3: return Vector3.INF
	for coordinate: Variant in value:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)): return Vector3.INF
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
