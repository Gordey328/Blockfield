class_name SurvivalArena
extends RefCounted
## Survival uses the accepted Crossroads geometry, with authored emergence sectors.
const CROSSROADS = preload("res://ai/tdm_arena.gd")

static func build() -> VoxelData:
	return CROSSROADS.build()

static func metadata() -> Dictionary:
	var sectors: Array[Vector3] = [
		Vector3(7.5, 4.01, 7.5), Vector3(7.5, 4.01, 48.5),
		Vector3(72.5, 4.01, 7.5), Vector3(72.5, 4.01, 48.5),
		Vector3(7.5, 4.01, 18.5), Vector3(7.5, 4.01, 38.5),
		Vector3(72.5, 4.01, 18.5), Vector3(72.5, 4.01, 38.5),
		Vector3(24.5, 4.01, 7.5), Vector3(55.5, 4.01, 48.5),
		Vector3(24.5, 4.01, 48.5), Vector3(55.5, 4.01, 7.5)]
	return {"title":"Crossroads", "authored":true, "floor_y":4.0,
		"team_spawns":CROSSROADS.metadata().team_spawns,
		"owner_spawn":Vector3(39.5, 4.01, 20.5),
		"player_spawn":Vector3(39.5, 4.01, 20.5),
		"supply_point":Vector3(39.5, 4.01, 20.5),
		"supply_points":[Vector3(39.5, 4.01, 20.5)], "spawn_sectors":sectors,
		"navigation_ceiling":12, "walk_speed":3.2,
		"breach_damage":40.0, "breach_windup_ticks":45, "breach_cycle_ticks":90}
