class_name SourceWeaponProfiles
extends RefCounted
## OpenSpades v0.1.3 Weapon.cpp RifleWeapon3..ShotgunWeapon4; GPL-3.0-or-later.
## Pure, isolated provider. Live match policy chooses one profile for all actors.
const PROFILES: Dictionary = {
	"0.75": [
		{"name":"Rifle", "delay":.5, "clip_size":10, "max_stock":50, "reload_time":2.5, "slow_reload":false, "spread":.012, "recoil":Vector3(.025,.05,0), "pellets":1, "torso":49, "head":100, "arms":33, "legs":33, "block":50},
		{"name":"SMG", "delay":.11, "clip_size":30, "max_stock":120, "reload_time":2.5, "slow_reload":false, "spread":.025, "recoil":Vector3(.01,.0125,0), "pellets":1, "torso":29, "head":75, "arms":18, "legs":18, "block":35},
		{"name":"Shotgun", "delay":1.0, "clip_size":6, "max_stock":48, "reload_time":.5, "slow_reload":true, "spread":.024, "recoil":Vector3(.05,.1,0), "pellets":8, "torso":27, "head":37, "arms":16, "legs":16, "block":34}
	],
	"0.76": [
		{"name":"Rifle", "delay":.6, "clip_size":8, "max_stock":48, "reload_time":2.5, "slow_reload":false, "spread":.004, "recoil":Vector3(.0001,.075,0), "pellets":1, "torso":49, "head":100, "arms":33, "legs":33, "block":50},
		{"name":"SMG", "delay":.1, "clip_size":30, "max_stock":150, "reload_time":2.5, "slow_reload":false, "spread":.012, "recoil":Vector3(.00005,.0125,0), "pellets":1, "torso":29, "head":75, "arms":18, "legs":18, "block":34},
		{"name":"Shotgun", "delay":.8, "clip_size":8, "max_stock":48, "reload_time":.4, "slow_reload":true, "spread":.036, "recoil":Vector3(.0002,.075,0), "pellets":8, "torso":27, "head":37, "arms":16, "legs":16, "block":34}
	]
}

static func valid(profile: String, weapon: int = 0) -> bool:
	return PROFILES.has(profile) and weapon >= 0 and weapon < 3

static func get_info(profile: String, weapon: int) -> Dictionary:
	if not valid(profile, weapon):
		return {}
	var result: Dictionary = PROFILES[profile][weapon].duplicate(true)
	result.weapon_index = weapon
	result.profile = profile
	return result

static func clip_size(profile: String, weapon: int) -> int:
	# AI only reads this scalar. Public get_info still returns an owned mutable
	# copy; no shared profile Dictionary escapes through this narrow provider.
	return int(PROFILES[profile][weapon].clip_size) if valid(profile,weapon) else 0

static func is_slow_reload(profile: String, weapon: int) -> bool:
	return bool(PROFILES[profile][weapon].slow_reload) if valid(profile,weapon) else false

static func damage(profile: String, weapon: int, part: String, horizontal_distance: float) -> float:
	if not valid(profile, weapon) or not is_finite(horizontal_distance) or horizontal_distance < 0 or horizontal_distance >= 128:
		return 0.0
	var key := part.to_lower()
	if key == "body": key = "torso"
	elif key == "arm": key = "arms"
	elif key in ["leg", "limb"]: key = "legs"
	if key not in ["torso", "head", "arms", "legs", "block"]: return 0.0
	return float(PROFILES[profile][weapon][key])
