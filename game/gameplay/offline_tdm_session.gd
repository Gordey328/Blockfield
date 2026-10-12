class_name OfflineTDMSession
extends LocalSession
## Offline 3x3 presentation adapter. MatchSimulation alone owns movement,
## tools, ammunition, hits, terrain and deaths; this node owns TDM round policy.
const SIMULATION = preload("res://simulation/match_simulation.gd")
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const DIRECTOR = preload("res://ai/tdm_bot_director.gd")
const DATA = preload("res://world/voxel_data.gd")
const OWNER_ID: int = 1
const BOT_IDS: Array[int] = [2, 3, 4, 5, 6]
const INITIAL_WEAPONS: Array[int] = [0, 1, 2, 0, 1, 2]
const ACTOR_NAMES: Array[String] = ["Player", "Mason", "Scout", "Rook", "Hunter", "Blaze"]
const MAX_LOG: int = 128
const MAX_SHOT_REFERENCES: int = 128
const MAX_PRESENTATION_EVENTS: int = 2048
const SUPPLY_RADIUS: float = 2.5
const SUPPLY_INTERVAL_TICKS: int = 60
const SPAWN_CLEARANCE_EPSILON: float = 0.01

var simulation: MatchSimulation
var paused: bool = true
var finished: bool = false
var kill_limit: int = 25:
	set(value): kill_limit = clampi(value, 1, 10000)
var match_duration_ticks: int = 18000:
	set(value): match_duration_ticks = clampi(value, 1, RULES.MAX_UINT32)
var finish_reason: String = ""
var tool_raise: float = 0.0
var displayed_tool: int = Tool.WEAPON
var displayed_weapon: int = Weapon.RIFLE
var sprint_state: float = 0.0
var aim_down_state: float = 0.0
var spawn_generation: int = 0
var player_kills: int = 0
var round_remaining: float = 300.0

var _director: TdmBotDirector
var _owner: SharedPlayerState
var _arena: Dictionary = {}
var _baseline_blocks: PackedInt32Array = PackedInt32Array()
var _baseline_dimensions: Vector3i = Vector3i.ZERO
var _baseline_water_level: float = 1.0
var _baseline_wade_level: float = 2.0
var _match_profile: String = "0.75"
var _local_name: String = "Player"
var _starting_weapon: int = Weapon.RIFLE
var _input_sequence: int = 0
var _pending_tool: int = 255
var _pending_weapon: int = 255
var _pending_reload: bool = false
var _pending_color: int = -1
var _presentation_events: Array[Dictionary] = []
var _shots: Dictionary[String, Dictionary] = {}
var _presentation_overflow: bool = false
var _respawn_deferred: int = 0
var _supply_deadlines: Dictionary[int, int] = {}


func _ready() -> void:
	# The inherited lab's objective/reset clock must never run here.
	update(0.0)


func configure_match(data: VoxelData, arena: Dictionary, local_name: String = "Player") -> Dictionary:
	var spawns: Variant = arena.get("team_spawns")
	if data == null or typeof(spawns) != TYPE_ARRAY or spawns.size() != 2:
		return {"ok": false, "error": "TDM requires a map and two spawn lists"}
	for list: Variant in spawns:
		if typeof(list) != TYPE_ARRAY or list.size() < 3:
			return {"ok": false, "error": "TDM requires three distinct spawns per team"}
		for point: Variant in list:
			if typeof(point) != TYPE_VECTOR3 or not point.is_finite():
				return {"ok": false, "error": "Invalid TDM spawn position"}
	var profile: String = profile_version if PROFILES.valid(profile_version) else "0.75"
	var candidate: MatchSimulation = SIMULATION.new()
	var configured: Dictionary = candidate.configure(data, profile, "sandbox")
	if not configured.ok:
		return configured
	candidate.friendly_fire = false
	for index: int in range(6):
		var actor_id: int = index + 1
		var actor_team: int = 0 if index < 3 else 1
		var actor_name: String = local_name if actor_id == OWNER_ID else ACTOR_NAMES[index]
		var added: Dictionary = candidate.add_actor(actor_name, 2, 1000 + actor_id * 97, Vector3.INF, actor_id)
		if not added.ok:
			return added
		# As MatchSimulation._find_spawn does, keep the source lower body
		# probe just above the solid-cell boundary to avoid an idle auto-climb.
		var point: Vector3 = spawns[actor_team][index % 3] + Vector3.UP * SPAWN_CLEARANCE_EPSILON
		if not _supported_spawn(data, point):
			return {"ok": false, "error": "TDM spawn requires solid support"}
		var selected_weapon: int = _starting_weapon if actor_id == OWNER_ID else INITIAL_WEAPONS[index]
		var spawned: Dictionary = candidate.spawn_actor(actor_id, actor_team, selected_weapon, point)
		if not spawned.ok:
			return spawned
		_face_front(candidate.get_actor(actor_id), data.dimensions)
	var director: TdmBotDirector = DIRECTOR.new()
	director.configure(data, BOT_IDS.duplicate(), arena.duplicate(true))
	simulation = candidate
	_director = director
	_arena = arena.duplicate(true)
	_baseline_blocks = data.blocks.duplicate()
	_baseline_dimensions = data.dimensions
	_baseline_water_level = data.water_level
	_baseline_wade_level = data.wade_origin_level
	_match_profile = profile
	_local_name = local_name
	_reset_view_state()
	update(0.0)
	_ingest_events(simulation.drain_events())
	return {"ok": true, "error": "", "data": data, "arena": _arena.duplicate(true)}


func restart_match() -> Dictionary:
	if simulation == null or _baseline_blocks.is_empty() or simulation.epoch >= RULES.MAX_UINT32:
		return {"ok": false, "error": "No restartable TDM match"}
	var data: VoxelData = DATA.new()
	var cleared: Error = data.clear(_baseline_dimensions, simulation.epoch + 1)
	if cleared != OK:
		return {"ok": false, "error": "TDM map reset failed"}
	data.blocks = _baseline_blocks.duplicate()
	data.water_level = _baseline_water_level
	data.wade_origin_level = _baseline_wade_level
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
	if owner != null:
		_starting_weapon = owner.pending_weapon if owner.pending_weapon >= 0 else owner.weapon
	profile_version = _match_profile
	return configure_match(data, _arena.duplicate(true), _local_name)


func local_player_id() -> int:
	return OWNER_ID


func get_match_mode() -> String:
	return "tdm"


func get_owner_state() -> SharedPlayerState:
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID) if simulation != null else null
	return owner.copy() if owner != null else null


func step_local(buttons: int, move: Vector2, yaw: float, pitch: float,
		tool: int = 255, weapon: int = 255) -> Dictionary:
	var empty_transactions: Array[Dictionary] = []
	if simulation == null:
		return {"ok": false, "error": "TDM is not configured", "tick": -1,
			"transactions": empty_transactions, "presentation_refresh_required": false}
	if paused or finished:
		update(0.0)
		return {"ok": true, "error": "", "advanced": false, "tick": simulation.tick,
			"transactions": empty_transactions, "presentation_refresh_required": false}
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
	if owner == null or _input_sequence >= RULES.MAX_UINT32:
		return {"ok": false, "error": "TDM owner/input sequence unavailable", "tick": simulation.tick,
			"transactions": empty_transactions, "presentation_refresh_required": false}
	var command: PlayerRules.Command = RULES.Command.new()
	command.sequence = _input_sequence + 1
	command.spawn_generation = owner.spawn_generation
	command.buttons = buttons | (RULES.Buttons.RELOAD if _pending_reload else 0)
	command.move = move
	command.yaw = yaw
	command.pitch = pitch
	command.tool = tool if tool != 255 else _pending_tool
	command.weapon = weapon if weapon != 255 else _pending_weapon
	if not command.valid():
		return {"ok": false, "error": "Invalid TDM input", "tick": simulation.tick,
			"transactions": empty_transactions, "presentation_refresh_required": false}
	if not owner.is_alive() and command.weapon != 255:
		# A class chosen on the exact eligible respawn tick must apply to that
		# spawn, rather than becoming pending immediately after the new life.
		var class_events: Array[Dictionary] = RULES.request_class(owner, command.weapon, simulation.tick + 1)
		simulation._record_events(class_events)
		command.weapon = 255
	# Respawn is the coordinator's explicit policy. Shared PlayerRules never
	# silently spawns a dead actor or supplies infinite ammo to keep it active.
	_respawn_ready_actors()
	command.spawn_generation = owner.spawn_generation
	if _pending_color >= 0:
		simulation.set_block_color(OWNER_ID, _pending_color)
	_input_sequence = command.sequence
	_clear_pending_intent()
	var commands: Dictionary = _director.commands(simulation) if _director != null else {}
	commands[OWNER_ID] = command
	simulation.step_fixed(commands)
	_restock_at_supply()
	var transactions: Array[Dictionary] = simulation.drain_transactions()
	# Receipts describe edits already owned by the adopted Data. A final marker
	# asks Main to rebuild presentation from that same Data after bounded overflow.
	var refresh_required: bool = not transactions.is_empty() \
		and bool(transactions[-1].get("refresh_required", false))
	_recount_scores()
	var should_finish: bool = team_scores[0] >= kill_limit or team_scores[1] >= kill_limit \
		or simulation.tick + 1 >= match_duration_ticks
	if should_finish:
		finished = true
		paused = true
		finish_reason = "kill_limit" if team_scores[0] >= kill_limit or team_scores[1] >= kill_limit else "time_limit"
		winning_team = 0 if team_scores[0] > team_scores[1] else (1 if team_scores[1] > team_scores[0] else -1)
		for actor_id: int in simulation.actors:
			simulation.clear_controls(actor_id)
	update(0.0)
	_ingest_events(simulation.drain_events())
	if should_finish:
		var end_event: Dictionary = {"type": "tdm_finished", "epoch": simulation.epoch,
			"tick": simulation.tick, "owner_id": 0, "spawn_generation": 0,
			"winner": winning_team, "scores": team_scores.duplicate(), "reason": finish_reason,
			"time": session_time, "mode": "tdm",
			"event_id": "%d:tdm:finished" % simulation.epoch}
		_queue_presentation(end_event)
		_append_log(end_event)
		objectives_changed.emit()
		if winning_team >= 0:
			round_won.emit(winning_team)
	return {"ok": true, "error": "", "advanced": true, "tick": simulation.tick,
		"transactions": transactions, "presentation_refresh_required": refresh_required}


func drain_presentation_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _presentation_events.duplicate(true)
	_presentation_events.clear()
	return result


func drain_intent() -> Dictionary:
	var result: Dictionary = {"tool": _pending_tool, "weapon": _pending_weapon,
		"reload": _pending_reload, "team": -1, "color": _pending_color}
	_pending_tool = 255
	_pending_weapon = 255
	_pending_reload = false
	# Color is consumed in step_local so menu/paused sampling cannot discard it.
	return result


func get_diagnostics() -> Dictionary:
	var counts: Array[int] = [0, 0]
	if simulation != null:
		for actor: SharedPlayerState in simulation.actors.values():
			if actor.team in [0, 1]:
				counts[actor.team] += 1
	var elapsed: int = maxi(0, simulation.tick + 1) if simulation != null else 0
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID) if simulation != null else null
	return {"tick": simulation.tick if simulation != null else -1,
		"bot_count": BOT_IDS.size() if simulation != null else 0, "team_counts": counts,
		"scores": team_scores.duplicate(), "time_remaining": maxf(0.0, float(match_duration_ticks - elapsed) / RULES.HZ),
		"winner": winning_team, "paused": paused, "finished": finished, "finish_reason": finish_reason,
		"elapsed_ticks": elapsed, "kill_limit": kill_limit, "match_duration_ticks": match_duration_ticks,
		"pending_weapon": owner.pending_weapon if owner != null else -1,
		"respawn_deferred": _respawn_deferred, "presentation_overflow": _presentation_overflow,
		"bots": _director.get_diagnostics() if _director != null else {}}


func update(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0 or simulation == null:
		return
	_owner = get_owner_state()
	if _owner == null:
		return
	profile_version = _owner.profile
	current_weapon = _owner.weapon
	current_tool = _owner.tool
	displayed_weapon = _owner.displayed_weapon
	displayed_tool = _owner.displayed_tool
	tool_raise = _owner.tool_raise
	sprint_state = _owner.sprint_state
	aim_down_state = _owner.aim_down_state
	spawn_generation = _owner.spawn_generation
	magazine = _owner.magazine
	reserve = _owner.reserve
	grenades = _owner.grenades
	blocks = _owner.blocks
	health = _owner.health
	team = _owner.team
	score = _owner.score
	player_name = _owner.player_name
	player_deaths = _owner.deaths
	player_kills = _owner.kills
	player_position = _owner.feet()
	session_time = float(maxi(0, simulation.tick + 1)) / RULES.HZ
	round_remaining = maxf(0.0, float(match_duration_ticks - maxi(0, simulation.tick + 1)) / RULES.HZ)
	is_reloading = _owner.reloading
	reload_remaining = maxf(0.0, (_owner.reload_deadline_tick - _owner.last_tick) / RULES.HZ) if _owner.reloading else 0.0
	fire_cooldown = (_owner.next_shot_tick - _owner.last_tick) / RULES.HZ
	grenade_cooldown = maxf(0.0, (_owner.grenade_deadline_tick - _owner.last_tick) / RULES.HZ)
	block_cooldown = maxf(0.0, (_owner.block_deadline_tick - _owner.last_tick) / RULES.HZ)
	is_cooking_grenade = _owner.cooking
	grenade_cook_time = maxf(0.0, float(_owner.last_tick - _owner.cook_started_tick) / RULES.HZ) if _owner.cooking else 0.0
	respawn_remaining = maxf(0.0, float(_owner.respawn_tick - _owner.last_tick) / RULES.HZ) if health <= 0 and _owner.respawn_tick >= 0 else 0.0
	if _owner.last_shot_tick >= 0:
		last_shot_time = maxf(last_shot_time, float(_owner.last_shot_tick) / RULES.HZ)
	unlimited_ammo = false
	invulnerable = false
	_trigger_held = _owner.trigger_held
	_grenade_release_pending = _owner.release_pending
	mode = get_match_mode()
	capture_limit = kill_limit
	ctf_flags.clear()
	ctf_bases.clear()
	territories.clear()
	_mirror_targets()
	live_grenades.clear()
	for projectile: SharedGrenadeState in simulation.grenades.values():
		live_grenades.append({"id": projectile.grenade_id, "position": projectile.position,
			"orientation": projectile.orientation, "velocity": projectile.velocity,
			"fuse": maxf(0.0, float(projectile.fuse_deadline_tick - simulation.tick) / RULES.HZ),
			"owner_id": projectile.owner_id, "spawn_generation": projectile.owner_generation,
			"epoch": projectile.match_epoch, "visual_only": true})
	changed.emit()


func _mirror_targets() -> void:
	targets.clear()
	for actor_id: int in BOT_IDS:
		var actor: SharedPlayerState = simulation.get_actor(actor_id)
		if actor == null:
			continue
		var alive: bool = actor.is_alive()
		var moving: bool = alive and Vector2(actor.motion.native_velocity.x, actor.motion.native_velocity.z).length_squared() > 0.000001
		var state: String = "dead" if not alive else ("crouching" if actor.motion.crouch else ("sprinting" if actor.sprinting else ("walking" if moving else "standing")))
		targets.append({"id": actor_id, "name": actor.player_name, "team": actor.team,
			"health": -1, "health_known": false, "alive": alive, "kills": actor.kills,
			"deaths": actor.deaths, "score": actor.score, "position": actor.feet(), "feet": actor.feet(),
			"spawn_generation": actor.spawn_generation, "native_velocity": actor.motion.native_velocity,
			"yaw": actor.yaw, "pitch": actor.pitch, "crouch": actor.motion.crouch,
			"crouching": actor.motion.crouch, "sprinting": actor.sprinting, "wading": actor.motion.wading,
			"grounded": actor.motion.grounded, "moving": moving, "state": state,
			"weapon": actor.weapon, "tool": actor.tool, "displayed_weapon": actor.displayed_weapon,
			"displayed_tool": actor.displayed_tool, "aiming": actor.aim_down_state > 0.001,
			"aim_down_state": actor.aim_down_state, "raise_state": actor.tool_raise,
			"tool_raise": actor.tool_raise, "sprint_state": actor.sprint_state,
			"reloading": actor.reloading, "profile": actor.profile, "phase": session_time,
			"respawn_remaining": maxf(0.0, float(actor.respawn_tick - simulation.tick) / RULES.HZ) if not alive else 0.0,
			"death_crouch": actor.motion.crouch, "death_velocity": actor.motion.native_velocity * 32.0,
			"carries_intel": false, "visual_only": true})


func _respawn_ready_actors() -> void:
	var now: int = simulation.tick + 1
	for actor_id: int in range(1, 7):
		var actor: SharedPlayerState = simulation.get_actor(actor_id)
		if actor == null or actor.is_alive() or actor.team not in [0, 1] or actor.respawn_tick < 0 or now < actor.respawn_tick:
			continue
		var points: Array = _arena.team_spawns[actor.team]
		var spawned: bool = false
		for offset: int in range(points.size()):
			var point: Vector3 = points[(actor_id - 1 + offset) % points.size()] + Vector3.UP * SPAWN_CLEARANCE_EPSILON
			if not _supported_spawn(simulation.data, point):
				continue
			var result: Dictionary = simulation.spawn_actor(actor_id, actor.team, -1, point)
			if result.ok:
				_face_front(actor, simulation.data.dimensions)
				spawned = true
				if actor_id == OWNER_ID:
					_clear_pending_intent()
				break
		if not spawned:
			_respawn_deferred += 1


func _restock_at_supply() -> void:
	for actor: SharedPlayerState in simulation.actors.values():
		if not RULES.can_act(actor) or actor.team not in [0, 1] \
				or simulation.tick < int(_supply_deadlines.get(actor.player_id, SUPPLY_INTERVAL_TICKS)):
			continue
		var stock: int = int(PROFILES.get_info(actor.profile, actor.weapon).max_stock)
		if actor.health >= 100 and actor.reserve >= stock and actor.blocks >= 50 and actor.grenades >= 3:
			continue
		var at_supply: bool = false
		for point: Vector3 in _arena.team_spawns[actor.team]:
			if actor.feet().distance_to(point) < SUPPLY_RADIUS:
				at_supply = true
				break
		if not at_supply:
			continue
		var events: Array[Dictionary] = RULES.restock(actor, simulation.tick, true)
		# Trusted offline coordinator records the standard shared event, preserving
		# global ordering. Neither the director nor the view can refill inventories.
		simulation._record_events(events)
		_supply_deadlines[actor.player_id] = simulation.tick + SUPPLY_INTERVAL_TICKS


static func _supported_spawn(data: VoxelData, point: Vector3) -> bool:
	for x: float in [-0.44, 0.44]:
		for z: float in [-0.44, 0.44]:
			if not MOTION.source_clip_box(data, point + Vector3(x, -0.05, z)):
				return false
	return true


static func _face_front(actor: SharedPlayerState, dimensions: Vector3i) -> void:
	var direction: Vector3 = Vector3(float(dimensions.x) * 0.5, actor.feet().y, float(dimensions.z) * 0.5) - actor.feet()
	actor.yaw = atan2(-direction.x, -direction.z)
	actor.pitch = 0.0
	actor.motion.front = actor.front()


func _recount_scores() -> void:
	var scores: Array[int] = [0, 0]
	for actor: SharedPlayerState in simulation.actors.values():
		if actor.team in [0, 1]:
			scores[actor.team] += actor.kills
	if scores != team_scores:
		team_scores.assign(scores)
		objectives_changed.emit()


func _ingest_events(events: Array[Dictionary]) -> void:
	for raw: Dictionary in events:
		var event: Dictionary = raw.duplicate(true)
		_queue_presentation(event)
		var own: bool = int(event.get("owner_id", 0)) == OWNER_ID
		var kind: String = str(event.get("type", ""))
		var actor: SharedPlayerState = simulation.get_actor(int(event.get("owner_id", 0)))
		if kind == "shot":
			_shots[str(event.event_id)] = {"weapon": event.weapon, "owner_id": event.owner_id}
			while _shots.size() > MAX_SHOT_REFERENCES:
				_shots.erase(_shots.keys()[0])
			if own:
				shots_fired += 1
				last_shot_time = maxf(last_shot_time, float(event.tick) / RULES.HZ)
				shot_fired.emit()
		elif own:
			match kind:
				"reload_completed": reloaded.emit()
				"restock": restocked.emit()
				"hurt":
					var attacker: SharedPlayerState = simulation.get_actor(int(event.attacker_id))
					player_hurt.emit(float(event.amount), attacker.feet() if attacker != null else Vector3.INF, str(event.cause))
				"death":
					last_death_kind = str(event.cause)
					player_died.emit()
				"spawn": player_respawned.emit()
				"hit_confirmed":
					hits_landed += 1
					last_damage = float(event.damage)
					last_hit_part = str(event.part)
		if not own:
			if kind == "death": target_died.emit(int(event.owner_id))
			elif kind == "spawn": target_respawned.emit(int(event.owner_id))
		if kind == "grenade_thrown":
			var thrown: Dictionary = event.duplicate(true)
			thrown.visual_only = true
			grenade_thrown.emit(thrown)
		elif kind == "grenade_exploded":
			var exploded: Dictionary = event.duplicate(true)
			exploded.id = event.grenade_id
			exploded.visual_only = true
			grenade_exploded.emit(exploded)
		var entry: Dictionary = event.duplicate(true)
		entry.time = float(event.tick) / RULES.HZ
		if actor != null:
			entry.name = actor.player_name
			if not entry.has("team"): entry.team = actor.team
		if kind == "spawn": entry.type = "respawn"
		elif kind == "death": entry.kind = event.cause
		elif kind == "kill_credit":
			var victim: SharedPlayerState = simulation.get_actor(int(event.victim_id))
			entry.type = "kill"
			entry.killer = actor.player_name if actor != null else "Player"
			entry.killer_team = actor.team if actor != null else 2
			entry.victim = victim.player_name if victim != null else "Soldier"
			entry.victim_team = victim.team if victim != null else 2
			entry.target_id = event.victim_id
			entry.part = event.cause
			entry.weapon_known = _shots.has(str(event.source_event_id))
			entry.weapon = _shots[str(event.source_event_id)].weapon if entry.weapon_known else (actor.weapon if actor != null else 0)
		_append_log(entry)


func _queue_presentation(event: Dictionary) -> void:
	if _presentation_events.size() >= MAX_PRESENTATION_EVENTS:
		_presentation_overflow = true
		return
	_presentation_events.append(event.duplicate(true))


func _append_log(entry: Dictionary) -> void:
	event_log.append(entry.duplicate(true))
	if event_log.size() > MAX_LOG:
		event_log.pop_front()
	match_event.emit(entry.duplicate(true))


func _reset_view_state() -> void:
	paused = true
	finished = false
	finish_reason = ""
	winning_team = -1
	team_scores = [0, 0]
	_input_sequence = 0
	_clear_pending_intent()
	_presentation_events.clear()
	_presentation_overflow = false
	_respawn_deferred = 0
	_supply_deadlines.clear()
	_shots.clear()
	event_log.clear()
	shots_fired = 0
	hits_landed = 0
	last_damage = 0.0
	last_hit_part = ""
	last_shot_time = -1.0
	last_death_kind = "weapon"


func _clear_pending_intent() -> void:
	_pending_tool = 255
	_pending_weapon = 255
	_pending_reload = false
	_pending_color = -1


func get_weapon_info() -> Dictionary:
	# Four synchronous scalar reads need no owned copy of motion/RNG/all state.
	# The returned profile Dictionary remains an independent mutable value.
	var owner: SharedPlayerState
	if get_script() == OfflineTDMSession:
		owner = simulation.get_actor(OWNER_ID) if simulation != null else null
		# Extension snapshots/copy hooks can transform values or have effects.
		# Keep their original dynamic dispatch and timing, including motion hooks.
		if owner != null and (owner.get_script() != SharedPlayerState or owner.motion == null or owner.motion.get_script() != MOTION.State):
			owner = get_owner_state()
	else:
		owner = get_owner_state()
	var version: String = owner.profile if owner != null else "0.75"
	var weapon: int = owner.weapon if owner != null else Weapon.RIFLE
	var info: Dictionary = PROFILES.get_info(version, weapon)
	info.weapon_index = weapon
	info.profile = version
	info.magazine = owner.magazine if owner != null else 0
	info.reserve = owner.reserve if owner != null else 0
	return info


func get_target(target_id: int) -> Dictionary:
	for target: Dictionary in targets:
		if int(target.id) == target_id:
			return target.duplicate(true)
	return {}


func is_tool_selectable(index: int) -> bool:
	return _owner != null and RULES.can_act(_owner) and RULES.tool_selectable(_owner, index)


func can_fire() -> bool:
	return not paused and not finished and _owner != null and RULES.can_fire(_owner, _owner.last_tick)


func get_reload_progress() -> float:
	return RULES.reload_progress(_owner, _owner.last_tick) if _owner != null else 0.0


func select_weapon(index: int) -> void:
	if _owner != null and index in [Weapon.RIFLE, Weapon.SMG, Weapon.SHOTGUN]:
		if paused and not finished and simulation.tick < 0:
			# Lobby class selection starts a new untouched shared registry. No
			# live inventory refill, fake death or direct actor mutation is used.
			_starting_weapon = index
			configure_match(simulation.data, _arena.duplicate(true), _local_name)
		else:
			_pending_weapon = index


func select_tool(index: int) -> void:
	if is_tool_selectable(index):
		_pending_tool = index


func reload_weapon() -> void:
	if _owner != null and RULES.can_act(_owner):
		_pending_reload = true


func request_block_color(color: int) -> bool:
	if _owner == null or color < 0x01000000 or color > 0x01ffffff:
		return false
	_pending_color = color
	return true


# Exhaustive LocalSession authority overrides. UI/lab compatibility calls must
# neither mutate the live shared actor nor create a second gameplay clock.
func set_profile_version(_version: String) -> void: pass
func set_mode(_mode: String) -> void: pass
func select_team(_index: int) -> void: pass
func set_team_info(_index: int, _name: String, _color: Color) -> bool: return false
func fire() -> bool: return false
func set_trigger_held(_held: bool) -> void: pass
func end_reload() -> void: pass
func compute_damage(_part: String, _distance: float) -> float: return 0.0
func damage_player(_amount: float, _origin: Vector3 = Vector3.INF, _kind: String = "weapon") -> void: pass
func respawn() -> void: pass
func restock() -> void: pass
func use_block(_count: int = 1) -> bool: return false
func recover_block() -> void: pass
func begin_grenade_cook() -> bool: return false
func release_grenade() -> Dictionary: return {}
func _release_grenade(_automatic: bool) -> Dictionary: return {}
func use_grenade() -> bool: return false
func set_grenade_position(_id: int, _position: Vector3) -> void: pass
func add_target(_position: Vector3, _team: int = 1, _moving: bool = false) -> int: return -1
func remove_target(_id: int) -> void: pass
func set_target_state(_id: int, _state: String, _weapon: int = Weapon.RIFLE, _tool: int = Tool.WEAPON) -> void: pass
func damage_target(_id: int, _part: String, _distance: float) -> float: return 0.0
func apply_target_damage(_id: int, _amount: float, _part: String = "torso") -> float: return 0.0
func apply_grenade_damage(_position: Vector3) -> void: pass
func add_score(_amount: int = 1) -> void: pass
func update_player_position(_position: Vector3) -> void: pass
func configure_ctf(_blue: Vector3, _green: Vector3, _limit: int = 3) -> void: pass
func configure_tc(_positions: Array[Vector3]) -> void: pass
func reset_lab() -> void: pass
func _cancel_selection_actions() -> void: pass
func _update_reload(_delta: float) -> void: pass
func _update_grenades(_delta: float) -> void: pass
func _update_targets(_delta: float) -> void: pass
func _reset_objectives() -> void: pass
func _update_objectives(_delta: float) -> void: pass
func _update_ctf() -> void: pass
func _drop_carried_intel() -> void: pass
func _update_tc(_delta: float) -> void: pass
func _event(_kind: String, _details: Dictionary) -> void: pass
