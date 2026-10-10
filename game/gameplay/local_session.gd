class_name LocalSession
extends Node
## Local authoritative match state. Values copied from OpenSpades v0.1.3
## Weapon.cpp/Player.cpp are separated from newly authored offline match rules.

signal changed
signal shot_fired
signal reloaded
signal player_died
signal player_respawned
signal target_died(target_id: int)
signal target_respawned(target_id: int)
signal grenade_thrown(grenade: Dictionary)
signal grenade_exploded(grenade: Dictionary)
signal objectives_changed
signal round_won(winning_team: int)

enum Weapon { RIFLE, SMG, SHOTGUN }
enum Tool { SPADE, BLOCK, WEAPON, GRENADE }

const WEAPON_PROFILES: Dictionary = {
	"0.75": [
		{"name": "Rifle", "delay": 0.5, "clip_size": 10, "max_stock": 50,
		"reload_time": 2.5, "slow_reload": false, "spread": 0.012,
		"recoil": Vector3(0.025, 0.05, 0.0), "pellets": 1,
		"torso": 49, "head": 100, "arms": 33, "legs": 33, "block": 50},
		{"name": "SMG", "delay": 0.11, "clip_size": 30, "max_stock": 120,
		"reload_time": 2.5, "slow_reload": false, "spread": 0.025,
		"recoil": Vector3(0.01, 0.0125, 0.0), "pellets": 1,
		"torso": 29, "head": 75, "arms": 18, "legs": 18, "block": 35},
		{"name": "Shotgun", "delay": 1.0, "clip_size": 6, "max_stock": 48,
		"reload_time": 0.5, "slow_reload": true, "spread": 0.024,
		"recoil": Vector3(0.05, 0.1, 0.0), "pellets": 8,
		"torso": 27, "head": 37, "arms": 16, "legs": 16, "block": 34}
	],
	"0.76": [
		{"name": "Rifle", "delay": 0.6, "clip_size": 8, "max_stock": 48,
		"reload_time": 2.5, "slow_reload": false, "spread": 0.004,
		"recoil": Vector3(0.0001, 0.075, 0.0), "pellets": 1,
		"torso": 49, "head": 100, "arms": 33, "legs": 33, "block": 50},
		{"name": "SMG", "delay": 0.1, "clip_size": 30, "max_stock": 150,
		"reload_time": 2.5, "slow_reload": false, "spread": 0.012,
		"recoil": Vector3(0.00005, 0.0125, 0.0), "pellets": 1,
		"torso": 29, "head": 75, "arms": 18, "legs": 18, "block": 34},
		{"name": "Shotgun", "delay": 0.8, "clip_size": 8, "max_stock": 48,
		"reload_time": 0.4, "slow_reload": true, "spread": 0.036,
		"recoil": Vector3(0.0002, 0.075, 0.0), "pellets": 8,
		"torso": 27, "head": 37, "arms": 16, "legs": 16, "block": 34}
	]
}

## Offline policy; the original client receives these from a server.
const LOCAL_MELEE_DAMAGE: float = 100.0
const LOCAL_RESPAWN_SECONDS: float = 3.0
const LOCAL_CTF_PICKUP_DISTANCE: float = 2.0
const LOCAL_CTF_RESUPPLY_DISTANCE: float = 2.0
const TC_CAPTURE_RATE: float = 0.05
const TC_CAPTURE_DISTANCE: float = 16.0
const LOCAL_GRENADE_DAMAGE_RADIUS: float = 16.0

var profile_version: String = "0.75"
var current_weapon: int = Weapon.RIFLE
var current_tool: int = Tool.WEAPON
var magazine: int = 10
var reserve: int = 50
var grenades: int = 3
var blocks: int = 50
var health: int = 100
var team: int = 0
var unlimited_ammo: bool = false
var invulnerable: bool = false
var is_reloading: bool = false
var reload_remaining: float = 0.0
var fire_cooldown: float = 0.0
var grenade_cooldown: float = 0.0
var block_cooldown: float = 0.0
var is_cooking_grenade: bool = false
var grenade_cook_time: float = 0.0
var respawn_remaining: float = 0.0
var player_position: Vector3 = Vector3.ZERO
var score: int = 0
var shots_fired: int = 0
var hits_landed: int = 0
var last_damage: float = 0.0
var last_hit_part: String = ""
var last_shot_time: float = -1.0
var session_time: float = 0.0
var mode: String = "sandbox"
var capture_limit: int = 3
var team_scores: Array[int] = [0, 0]
var winning_team: int = -1
var targets: Array[Dictionary] = []
var live_grenades: Array[Dictionary] = []
var ctf_bases: Array[Vector3] = [Vector3(16, 5, 48), Vector3(80, 5, 48)]
var ctf_flags: Array[Dictionary] = []
var territories: Array[Dictionary] = []

var _next_target_id: int = 1
var _next_grenade_id: int = 1
var _resupply_cooldown: float = 0.0
var _grenade_release_pending: bool = false


func _ready() -> void:
	_reset_objectives()


func get_weapon_info() -> Dictionary:
	var info: Dictionary = WEAPON_PROFILES[profile_version][current_weapon].duplicate(true)
	info["weapon_index"] = current_weapon
	info["profile"] = profile_version
	info["magazine"] = magazine
	info["reserve"] = reserve
	return info


func set_profile_version(version: String) -> void:
	if not WEAPON_PROFILES.has(version) or profile_version == version:
		return
	profile_version = version
	select_weapon(current_weapon)


func select_weapon(index: int) -> void:
	if index < Weapon.RIFLE or index > Weapon.SHOTGUN:
		return
	current_weapon = index
	current_tool = Tool.WEAPON
	is_reloading = false
	reload_remaining = 0.0
	fire_cooldown = 0.0
	var info := get_weapon_info()
	magazine = int(info["clip_size"])
	reserve = int(info["max_stock"])
	changed.emit()


func select_tool(index: int) -> void:
	if index < Tool.SPADE or index > Tool.GRENADE or not is_tool_selectable(index):
		return
	if is_cooking_grenade and index != Tool.GRENADE:
		release_grenade()
	current_tool = index
	changed.emit()


func is_tool_selectable(index: int) -> bool:
	match index:
		Tool.SPADE:
			return true
		Tool.BLOCK:
			return blocks > 0 or unlimited_ammo
		Tool.WEAPON:
			return magazine > 0 or reserve > 0 or unlimited_ammo
		Tool.GRENADE:
			return grenades > 0 or unlimited_ammo
	return false


func select_team(index: int) -> void:
	if index < 0 or index > 2:
		return
	_drop_carried_intel()
	team = index
	if is_cooking_grenade:
		release_grenade()
	if team < 2:
		respawn()
	else:
		is_reloading = false
		respawn_remaining = 0.0
	changed.emit()


func can_fire() -> bool:
	var info := get_weapon_info()
	return health > 0 and team < 2 and current_tool == Tool.WEAPON \
		and fire_cooldown <= 0.0 and (magazine > 0 or unlimited_ammo) \
		and (not is_reloading or bool(info["slow_reload"]))


func fire() -> bool:
	if not can_fire():
		return false
	is_reloading = false
	reload_remaining = 0.0
	if not unlimited_ammo:
		magazine -= 1
	fire_cooldown = float(get_weapon_info()["delay"])
	last_shot_time = session_time
	shots_fired += 1
	shot_fired.emit()
	changed.emit()
	return true


func reload_weapon() -> void:
	var info := get_weapon_info()
	if health <= 0 or team >= 2 or is_reloading or magazine >= int(info["clip_size"]):
		return
	if reserve <= 0 and not unlimited_ammo:
		return
	is_reloading = true
	reload_remaining = float(info["reload_time"])
	changed.emit()


func get_reload_progress() -> float:
	if not is_reloading:
		return 0.0
	return clampf(1.0 - reload_remaining / float(get_weapon_info()["reload_time"]), 0.0, 1.0)


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	session_time += delta
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	grenade_cooldown = maxf(0.0, grenade_cooldown - delta)
	block_cooldown = maxf(0.0, block_cooldown - delta)
	_resupply_cooldown = maxf(0.0, _resupply_cooldown - delta)
	# Advance already-dead actors before this interval's explosions can create
	# new deaths. New respawn clocks must not age by the whole interval twice.
	if health <= 0 and team < 2:
		respawn_remaining = maxf(0.0, respawn_remaining - delta)
		if respawn_remaining <= 0.0:
			respawn()
	_update_targets(delta)
	# Tick existing projectiles before auto-release can create a new one. A grenade
	# thrown at the end of this interval must retain its remaining fuse.
	_update_grenades(delta)
	_update_reload(delta)
	if is_cooking_grenade:
		grenade_cook_time += delta
		if grenade_cook_time >= 2.9 or (_grenade_release_pending and grenade_cook_time >= 0.15):
			release_grenade()
	_update_objectives(delta)


func _update_reload(delta: float) -> void:
	if not is_reloading:
		return
	reload_remaining -= delta
	if reload_remaining > 0.0:
		return
	var info := get_weapon_info()
	if bool(info["slow_reload"]):
		# Preserve elapsed remainder so low frame rates do not slow shell loading.
		while is_reloading and reload_remaining <= 0.0:
			magazine += 1
			if not unlimited_ammo:
				reserve -= 1
			if magazine < int(info["clip_size"]) and (reserve > 0 or unlimited_ammo):
				reload_remaining += float(info["reload_time"])
			else:
				is_reloading = false
				end_reload()
	else:
		var load_count := int(info["clip_size"]) - magazine
		if not unlimited_ammo:
			load_count = mini(load_count, reserve)
			reserve -= load_count
		magazine += load_count
		is_reloading = false
		end_reload()
	changed.emit()


func end_reload() -> void:
	reload_remaining = 0.0
	reloaded.emit()


func compute_damage(hit_part: String, distance: float) -> float:
	# Call with horizontal distance, matching Player::FireWeapon.
	if distance >= 128.0:
		return 0.0
	if hit_part == "melee":
		return LOCAL_MELEE_DAMAGE if distance < 3.0 else 0.0
	var key := hit_part.to_lower()
	if key == "body":
		key = "torso"
	elif key == "arm":
		key = "arms"
	elif key == "leg" or key == "limb":
		key = "legs"
	return float(get_weapon_info().get(key, 0))


func damage_player(amount: float) -> void:
	if invulnerable or health <= 0 or team >= 2 or amount <= 0.0:
		return
	health = maxi(0, health - int(ceilf(amount)))
	if health == 0:
		_drop_carried_intel()
		is_reloading = false
		respawn_remaining = LOCAL_RESPAWN_SECONDS
		if is_cooking_grenade:
			release_grenade()
		player_died.emit()
	changed.emit()


func respawn() -> void:
	health = 100
	respawn_remaining = 0.0
	is_reloading = false
	reload_remaining = 0.0
	fire_cooldown = 0.0
	grenade_cooldown = 0.0
	block_cooldown = 0.0
	is_cooking_grenade = false
	grenade_cook_time = 0.0
	_grenade_release_pending = false
	var info := get_weapon_info()
	magazine = int(info["clip_size"])
	reserve = int(info["max_stock"])
	grenades = 3
	blocks = 50
	player_respawned.emit()
	changed.emit()


func restock() -> void:
	if health <= 0:
		return
	# Original restock replenishes reserve, HP, blocks and grenades, not the clip.
	reserve = int(get_weapon_info()["max_stock"])
	grenades = 3
	blocks = 50
	health = 100
	changed.emit()


func use_block(count: int = 1) -> bool:
	if health <= 0 or team >= 2 or count <= 0 or block_cooldown > 0.0:
		return false
	if not unlimited_ammo and blocks < count:
		return false
	if not unlimited_ammo:
		blocks -= count
	block_cooldown = 0.5
	changed.emit()
	return true


func recover_block() -> void:
	blocks = mini(50, blocks + 1)
	changed.emit()


func begin_grenade_cook() -> bool:
	if health <= 0 or team >= 2 or is_cooking_grenade or grenade_cooldown > 0.0:
		return false
	if grenades <= 0 and not unlimited_ammo:
		return false
	is_cooking_grenade = true
	grenade_cook_time = 0.0
	_grenade_release_pending = false
	changed.emit()
	return true


func release_grenade() -> Dictionary:
	if not is_cooking_grenade:
		return {}
	if grenade_cook_time < 0.15 and health > 0:
		_grenade_release_pending = true
		return {}
	var grenade: Dictionary = {
		"id": _next_grenade_id, "position": player_position,
		"fuse": maxf(0.0, 3.0 - grenade_cook_time), "cook_time": grenade_cook_time,
		"drop": health <= 0, "team": team
	}
	_next_grenade_id += 1
	if not unlimited_ammo:
		grenades -= 1
	is_cooking_grenade = false
	_grenade_release_pending = false
	grenade_cook_time = 0.0
	grenade_cooldown = 0.5
	live_grenades.append(grenade)
	grenade_thrown.emit(grenade)
	changed.emit()
	return grenade


func use_grenade() -> bool:
	if not begin_grenade_cook():
		return false
	# Immediate throw helper for UI/legacy callers; gameplay can use cook/release.
	grenade_cook_time = 0.15
	release_grenade()
	return true


func set_grenade_position(grenade_id: int, position: Vector3) -> void:
	for grenade in live_grenades:
		if int(grenade["id"]) == grenade_id:
			grenade["position"] = position
			return


func _update_grenades(delta: float) -> void:
	for index in range(live_grenades.size() - 1, -1, -1):
		var grenade := live_grenades[index]
		grenade["fuse"] = float(grenade["fuse"]) - delta
		if float(grenade["fuse"]) <= 0.0:
			live_grenades.remove_at(index)
			grenade_exploded.emit(grenade)


func add_target(position: Vector3, target_team: int = 1, moving: bool = false) -> int:
	var target: Dictionary = {
		"id": _next_target_id, "health": 100, "team": clampi(target_team, 0, 1),
		"position": position, "spawn_position": position, "moving": moving,
		"alive": true, "respawn_remaining": 0.0, "state": "standing",
		"weapon": Weapon.RIFLE, "tool": Tool.WEAPON, "phase": 0.0
	}
	_next_target_id += 1
	targets.append(target)
	changed.emit()
	return int(target["id"])


func get_target(target_id: int) -> Dictionary:
	for target in targets:
		if int(target["id"]) == target_id:
			return target
	return {}


func remove_target(target_id: int) -> void:
	for index in range(targets.size() - 1, -1, -1):
		if int(targets[index]["id"]) == target_id:
			targets.remove_at(index)
			changed.emit()
			return


func set_target_state(target_id: int, state: String, weapon: int = Weapon.RIFLE,
		tool: int = Tool.WEAPON) -> void:
	var target := get_target(target_id)
	if target.is_empty():
		return
	target["state"] = state
	target["weapon"] = clampi(weapon, Weapon.RIFLE, Weapon.SHOTGUN)
	target["tool"] = clampi(tool, Tool.SPADE, Tool.GRENADE)
	target["moving"] = state == "walking" or state == "sprinting"
	if state == "dead":
		target["health"] = 0
		target["alive"] = false
		target["respawn_remaining"] = -1.0 # Explicit lab pose, keep until reset.
	elif not bool(target["alive"]):
		target["health"] = 100
		target["alive"] = true
		target["respawn_remaining"] = 0.0
	changed.emit()


func damage_target(target_id: int, hit_part: String, distance: float) -> float:
	return apply_target_damage(target_id, compute_damage(hit_part, distance), hit_part)


func apply_target_damage(target_id: int, amount: float, hit_part: String = "torso") -> float:
	var target := get_target(target_id)
	if target.is_empty() or not bool(target["alive"]) or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, float(target["health"]))
	target["health"] = maxi(0, int(target["health"]) - int(ceilf(amount)))
	hits_landed += 1
	last_damage = dealt
	last_hit_part = hit_part
	if int(target["health"]) == 0:
		target["alive"] = false
		target["state"] = "dead"
		target["respawn_remaining"] = LOCAL_RESPAWN_SECONDS
		add_score()
		target_died.emit(target_id)
	changed.emit()
	return dealt


func apply_grenade_damage(position: Vector3) -> void:
	# Authored offline policy: quadratic radial falloff; occlusion belongs to world.
	for target in targets:
		var target_position: Vector3 = target["position"]
		var distance := position.distance_to(target_position)
		if distance < LOCAL_GRENADE_DAMAGE_RADIUS:
			var factor := 1.0 - distance / LOCAL_GRENADE_DAMAGE_RADIUS
			apply_target_damage(int(target["id"]), 100.0 * factor * factor, "grenade")
	var player_distance := position.distance_to(player_position)
	if player_distance < LOCAL_GRENADE_DAMAGE_RADIUS:
		var player_factor := 1.0 - player_distance / LOCAL_GRENADE_DAMAGE_RADIUS
		damage_player(100.0 * player_factor * player_factor)


func _update_targets(delta: float) -> void:
	for target in targets:
		if not bool(target["alive"]):
			if float(target["respawn_remaining"]) < 0.0:
				continue
			target["respawn_remaining"] = maxf(0.0, float(target["respawn_remaining"]) - delta)
			if float(target["respawn_remaining"]) <= 0.0:
				target["health"] = 100
				target["alive"] = true
				target["state"] = "walking" if bool(target["moving"]) else "standing"
				target["position"] = target["spawn_position"]
				target_respawned.emit(int(target["id"]))
				changed.emit()
		elif bool(target["moving"]):
			var speed := 2.0 if str(target["state"]) == "sprinting" else 1.0
			target["phase"] = float(target["phase"]) + delta * speed
			var spawn_position: Vector3 = target["spawn_position"]
			target["position"] = spawn_position + Vector3(sin(float(target["phase"])) * 3.0, 0.0, 0.0)


func add_score(amount: int = 1) -> void:
	score += amount
	changed.emit()


func update_player_position(position: Vector3) -> void:
	player_position = position


func configure_ctf(blue_base: Vector3, green_base: Vector3, limit: int = 3) -> void:
	ctf_bases = [blue_base, green_base]
	capture_limit = maxi(1, limit)
	_reset_objectives()


func configure_tc(positions: Array[Vector3]) -> void:
	territories.clear()
	for position in positions:
		territories.append({"position": position, "owner": 2, "capturing_team": -1,
			"progress": 0.0, "contested": false})
	objectives_changed.emit()


func set_mode(new_mode: String) -> void:
	if new_mode not in ["sandbox", "ctf", "tc"]:
		return
	mode = new_mode
	_reset_objectives()
	changed.emit()


func _reset_objectives() -> void:
	team_scores = [0, 0]
	winning_team = -1
	ctf_flags.clear()
	for flag_team in range(2):
		ctf_flags.append({"team": flag_team, "position": ctf_bases[flag_team],
			"carrier": -1, "at_base": true})
	for territory in territories:
		territory["owner"] = 2
		territory["capturing_team"] = -1
		territory["progress"] = 0.0
		territory["contested"] = false
	objectives_changed.emit()


func _update_objectives(delta: float) -> void:
	if winning_team >= 0:
		return
	if mode == "ctf" and team < 2 and health > 0:
		_update_ctf()
	elif mode == "tc":
		_update_tc(delta)


func _update_ctf() -> void:
	if ctf_flags.size() != 2:
		_reset_objectives()
	var enemy_team := 1 - team
	var enemy_flag := ctf_flags[enemy_team]
	var own_flag := ctf_flags[team]
	var enemy_flag_position: Vector3 = enemy_flag["position"]
	var own_flag_position: Vector3 = own_flag["position"]
	if int(enemy_flag["carrier"]) < 0 and player_position.distance_to(enemy_flag_position) < LOCAL_CTF_PICKUP_DISTANCE:
		enemy_flag["carrier"] = 0
		enemy_flag["at_base"] = false
		objectives_changed.emit()
	if int(enemy_flag["carrier"]) == 0:
		enemy_flag["position"] = player_position
		if player_position.distance_to(ctf_bases[team]) < LOCAL_CTF_PICKUP_DISTANCE:
			enemy_flag["carrier"] = -1
			enemy_flag["position"] = ctf_bases[enemy_team]
			enemy_flag["at_base"] = true
			team_scores[team] += 1
			add_score(10)
			objectives_changed.emit()
			if team_scores[team] >= capture_limit:
				winning_team = team
				round_won.emit(team)
	if not bool(own_flag["at_base"]) and int(own_flag["carrier"]) < 0 \
			and player_position.distance_to(own_flag_position) < LOCAL_CTF_PICKUP_DISTANCE:
		own_flag["position"] = ctf_bases[team]
		own_flag["at_base"] = true
		objectives_changed.emit()
	if _resupply_cooldown <= 0.0 and player_position.distance_to(ctf_bases[team]) < LOCAL_CTF_RESUPPLY_DISTANCE:
		restock()
		_resupply_cooldown = 1.0


func _drop_carried_intel() -> void:
	for flag in ctf_flags:
		if int(flag["carrier"]) == 0:
			flag["carrier"] = -1
			flag["position"] = player_position
			flag["at_base"] = false
			objectives_changed.emit()


func _update_tc(delta: float) -> void:
	var did_change := false
	for territory in territories:
		var position: Vector3 = territory["position"]
		var nearby_teams: Array[int] = [0, 0]
		if team < 2 and health > 0 and player_position.distance_to(position) < TC_CAPTURE_DISTANCE:
			nearby_teams[team] += 1
		for target in targets:
			var target_position: Vector3 = target["position"]
			if bool(target["alive"]) and target_position.distance_to(position) < TC_CAPTURE_DISTANCE:
				nearby_teams[int(target["team"])] += 1
		var balance := nearby_teams[0] - nearby_teams[1]
		var contested := nearby_teams[0] > 0 and nearby_teams[1] > 0
		if bool(territory["contested"]) != contested:
			territory["contested"] = contested
			did_change = true
		if balance == 0:
			continue
		var capture_team := 0 if balance > 0 else 1
		if int(territory["owner"]) == capture_team:
			if float(territory["progress"]) > 0.0:
				territory["progress"] = maxf(0.0, float(territory["progress"]) - absf(float(balance)) * TC_CAPTURE_RATE * delta)
				did_change = true
			continue
		if int(territory["capturing_team"]) >= 0 and int(territory["capturing_team"]) != capture_team:
			territory["progress"] = maxf(0.0, float(territory["progress"]) - absf(float(balance)) * TC_CAPTURE_RATE * delta)
			if float(territory["progress"]) <= 0.0:
				territory["capturing_team"] = capture_team
		else:
			territory["capturing_team"] = capture_team
			territory["progress"] = minf(1.0, float(territory["progress"]) + absf(float(balance)) * TC_CAPTURE_RATE * delta)
		if float(territory["progress"]) >= 1.0:
			territory["owner"] = capture_team
			territory["capturing_team"] = -1
			territory["progress"] = 0.0
		did_change = true
	if not did_change:
		return
	team_scores = [0, 0]
	for territory in territories:
		var owner := int(territory["owner"])
		if owner < 2:
			team_scores[owner] += 1
	objectives_changed.emit()
	if not territories.is_empty():
		for candidate_team in range(2):
			if team_scores[candidate_team] == territories.size():
				winning_team = candidate_team
				round_won.emit(candidate_team)
				break
	changed.emit()


func reset_lab() -> void:
	_drop_carried_intel()
	team = 0
	score = 0
	shots_fired = 0
	hits_landed = 0
	last_damage = 0.0
	last_hit_part = ""
	session_time = 0.0
	last_shot_time = -1.0
	live_grenades.clear()
	_resupply_cooldown = 0.0
	for target in targets:
		target["health"] = 100
		target["alive"] = true
		target["state"] = "walking" if bool(target["moving"]) else "standing"
		target["position"] = target["spawn_position"]
		target["respawn_remaining"] = 0.0
		target["phase"] = 0.0
	current_tool = Tool.WEAPON
	_reset_objectives()
	respawn()
