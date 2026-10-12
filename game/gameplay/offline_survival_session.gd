class_name OfflineSurvivalSession
extends OfflineTDMSession
## Timed survival authority. Inherits only the existing local command/view bridge;
## roster, clocks, allocation, attacks, supply and end conditions are independent.
const SETTINGS = preload("res://gameplay/survival_settings.gd")
const ZOMBIES = preload("res://ai/zombie_director.gd")
const ZOMBIE_IDS: Array[int] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
const BITE_WINDUP: int = 27
const BITE_CYCLE: int = 72
const BITE_DAMAGE: int = 20
const BITE_RANGE: float = 2.2
const CROWD_PROTECTION: int = 24
const BREACH_WINDUP: int = 45
const BREACH_CYCLE: int = 90
const BREACH_DAMAGE: int = 40
const THROW_WINDUP: int = 60
const THROW_COOLDOWN: int = 480
const THROW_MIN_RANGE: float = 6.0
const THROW_MAX_RANGE: float = 24.0
const VISIBLE_WARNING_TICKS: int = 60
const STALL_TICKS: int = 1200
const SUPPLY_STAND_TICKS: int = 120
const SUPPLY_SAFE_DISTANCE: float = 8.0
const RUSH_KILL_THRESHOLDS: Array[int] = [3, 7, 12, 18, 25]
const RUSH_MAX_PERK_LEVEL: int = 3

var phase: String = "preparation"
var outcome: String = ""
var wave: int = 0
var headshots: int = 0
var damage_taken: int = 0
var _settings: Dictionary = {}
var _test_overrides: bool = false
var _zombie_director: ZombieDirector
var _preparation_ticks: int = 0
var _active_ticks: int = 0
var _duration_ticks: int = 0
var _interval_ticks: int = 0
var _wave_start: int = 0
var _wave_window_ticks: int = 0
var _wave_planned: int = 0
var _wave_attempted: int = 0
var _wave_spawned: int = 0
var _wave_skipped: int = 0
var _planned: int = 0
var _spawned: int = 0
var _skipped: int = 0
var _pending_spawn: Dictionary = {}
var _attacks: Dictionary[int, Dictionary] = {}
var _attack_deadlines: Dictionary[int, int] = {}
var _throw_deadlines: Dictionary[int, int] = {}
var _bite_protection_deadline: int = -1
var _progress: Dictionary[int, Dictionary] = {}
var _last_spawn_tick: int = -1
var _spawn_unavailable_since: int = -1
var _last_owner_hurt_tick: int = -10000
var _supply_ticks: int = 0
var _supply_used_wave: int = 0
var _supply_status: String = "unavailable"
var _supply_position: Vector3 = Vector3.ZERO
var _survival_event_sequence: int = 0
var _rush_pending: bool = false
var _rush_choices_taken: int = 0
var _rush_levels: Dictionary[String, int] = {"power": 0, "armor": 0, "field_kit": 0}
var _rush_choices: Array[Dictionary] = []


func get_match_mode() -> String:
	return "survival"


func configure_match(data: VoxelData, arena: Dictionary, local_name: String = "Player") -> Dictionary:
	return configure_survival(data, arena, _settings if not _settings.is_empty() else SETTINGS.defaults(), local_name, _test_overrides)


func configure_survival(data: VoxelData, arena: Dictionary, settings: Dictionary,
		local_name: String = "Player", test_overrides: bool = false, starting_weapon: int = -1) -> Dictionary:
	var checked: Dictionary = SETTINGS.validate(settings, test_overrides)
	if not checked.ok:
		return checked
	if starting_weapon not in [-1, 0, 1, 2]:
		return {"ok": false, "error": "Invalid survival starting weapon"}
	var selected_weapon: int = _starting_weapon if starting_weapon < 0 else starting_weapon
	if data == null or typeof(arena.get("owner_spawn")) != TYPE_VECTOR3 \
			or typeof(arena.get("supply_point")) != TYPE_VECTOR3:
		return {"ok": false, "error": "Survival requires authored owner spawn and supply point"}
	if not (arena.owner_spawn as Vector3).is_finite() or not (arena.supply_point as Vector3).is_finite():
		return {"ok": false, "error": "Survival spawn and supply must be finite"}
	var profile: String = profile_version if PROFILES.valid(profile_version) else "0.75"
	var candidate: MatchSimulation = SIMULATION.new()
	var configured: Dictionary = candidate.configure(data, profile, "sandbox")
	if not configured.ok:
		return configured
	candidate.friendly_fire = false
	var added: Dictionary = candidate.add_actor(local_name, 2, 7197, Vector3.INF, OWNER_ID)
	if not added.ok:
		return added
	var point: Vector3 = arena.owner_spawn + Vector3.UP * SPAWN_CLEARANCE_EPSILON
	if not _supported_spawn(data, point):
		return {"ok": false, "error": "Survival owner spawn requires solid support"}
	var spawned: Dictionary = candidate.spawn_actor(OWNER_ID, 0, selected_weapon, point)
	if not spawned.ok:
		return spawned
	_face_front(candidate.get_actor(OWNER_ID), data.dimensions)
	for id: int in ZOMBIE_IDS:
		var registered: Dictionary = candidate.register_zombie_slot(id)
		if not registered.ok:
			return registered
	var director: ZombieDirector = ZOMBIES.new()
	var authored: Dictionary = arena.duplicate(true)
	authored.breach_damage = int(checked.settings.zombie_block_damage)
	authored.breach_windup_ticks = BREACH_WINDUP
	authored.breach_cycle_ticks = BREACH_CYCLE
	director.configure(data, authored, ZOMBIE_IDS.duplicate())
	simulation = candidate
	_director = null
	_zombie_director = director
	_arena = authored
	_baseline_blocks = data.blocks.duplicate()
	_baseline_dimensions = data.dimensions
	_baseline_water_level = data.water_level
	_baseline_wade_level = data.wade_origin_level
	_match_profile = profile
	_local_name = local_name
	_starting_weapon = selected_weapon
	_settings = checked.settings.duplicate(true)
	_test_overrides = test_overrides
	_reset_view_state()
	_reset_survival()
	update(0.0)
	_ingest_events(simulation.drain_events())
	return {"ok": true, "error": "", "data": data, "arena": _arena.duplicate(true), "settings": _settings.duplicate(true)}


func restart_match() -> Dictionary:
	if simulation == null or _baseline_blocks.is_empty() or simulation.epoch >= RULES.MAX_UINT32:
		return {"ok": false, "error": "No restartable survival match"}
	var data: VoxelData = DATA.new()
	var cleared: Error = data.clear(_baseline_dimensions, simulation.epoch + 1)
	if cleared != OK:
		return {"ok": false, "error": "Survival map reset failed"}
	data.blocks = _baseline_blocks.duplicate()
	data.water_level = _baseline_water_level
	data.wade_origin_level = _baseline_wade_level
	_starting_weapon = simulation.get_actor(OWNER_ID).weapon
	profile_version = _match_profile
	return configure_survival(data, _arena.duplicate(true), _settings.duplicate(true), _local_name, _test_overrides)


func _reset_survival() -> void:
	phase = "preparation" if int(_settings.preparation_seconds) > 0 else "active"
	outcome = ""
	wave = 0
	headshots = 0
	damage_taken = 0
	_preparation_ticks = 0
	_active_ticks = 0
	_duration_ticks = int(_settings.duration_seconds) * RULES.HZ
	_interval_ticks = int(_settings.wave_interval_seconds) * RULES.HZ
	match_duration_ticks = _duration_ticks
	_wave_start = 0
	_wave_window_ticks = mini(SETTINGS.SPAWN_WINDOW_SECONDS * RULES.HZ, _interval_ticks)
	_wave_planned = 0
	_wave_attempted = 0
	_wave_spawned = 0
	_wave_skipped = 0
	_planned = 0
	_spawned = 0
	_skipped = 0
	_pending_spawn.clear()
	_attacks.clear()
	_attack_deadlines.clear()
	_throw_deadlines.clear()
	_bite_protection_deadline = -1
	_progress.clear()
	_last_spawn_tick = -1
	_spawn_unavailable_since = -1
	_last_owner_hurt_tick = -10000
	_supply_ticks = 0
	_supply_used_wave = 0
	_supply_status = "unavailable"
	_supply_position = _arena.supply_point
	_survival_event_sequence = 0
	_rush_pending = false
	_rush_choices_taken = 0
	_rush_levels = {"power": 0, "armor": 0, "field_kit": 0}
	_rush_choices.clear()


func step_local(buttons: int, move: Vector2, yaw: float, pitch: float,
		tool: int = 255, weapon: int = 255) -> Dictionary:
	var empty: Array[Dictionary] = []
	if simulation == null:
		return {"ok": false, "error": "Survival is not configured", "tick": -1, "transactions": empty, "presentation_refresh_required": false}
	if paused or finished:
		update(0.0)
		return {"ok": true, "error": "", "advanced": false, "tick": simulation.tick, "transactions": empty, "presentation_refresh_required": false}
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
	if owner == null or _input_sequence >= RULES.MAX_UINT32:
		return {"ok": false, "error": "Survival owner/input sequence unavailable", "tick": simulation.tick, "transactions": empty, "presentation_refresh_required": false}
	var command: PlayerRules.Command = RULES.Command.new()
	command.sequence = _input_sequence + 1
	command.spawn_generation = owner.spawn_generation
	command.buttons = buttons | (RULES.Buttons.RELOAD if _pending_reload else 0)
	command.move = move
	command.yaw = yaw
	command.pitch = pitch
	command.tool = tool if tool != 255 else _pending_tool
	# A survival life keeps its chosen class; no future life exists to change it.
	command.weapon = 255
	if weapon not in [0, 1, 2, 255] or not command.valid():
		return {"ok": false, "error": "Invalid survival input", "tick": simulation.tick, "transactions": empty, "presentation_refresh_required": false}
	if not owner.is_alive():
		_finish("defeat", "death")
		_ingest_events(simulation.drain_events())
		update(0.0)
		return {"ok": true, "error": "", "advanced": false, "tick": simulation.tick, "transactions": empty, "presentation_refresh_required": false}
	if _rush_pending:
		# Choice time is outside the simulation: projectiles, actor deadlines,
		# wave windows and the active clock all stop at the same fixed boundary.
		update(0.0)
		return {"ok": true, "error": "", "advanced": false, "tick": simulation.tick, "transactions": empty, "presentation_refresh_required": false}
	if _pending_color >= 0:
		simulation.set_block_color(OWNER_ID, _pending_color)
	_input_sequence = command.sequence
	_clear_pending_intent()
	if phase == "active":
		_advance_spawns()
	_sync_zombie_loadouts()
	if _zombie_director != null:
		_zombie_director.arsenal = arsenal
		_zombie_director.arsenal_locked_actors.assign(_attacks.keys())
	var commands: Dictionary = _zombie_director.commands(simulation) if _zombie_director != null else {}
	if arsenal != null:
		for id: int in commands:
			var actor: SharedPlayerState = simulation.get_actor(id)
			var scale: float = arsenal.movement_scale(id)
			var zombie_command: PlayerRules.Command = commands[id]
			zombie_command.move *= scale
			if actor != null and scale <= 0.0:
				actor.motion.native_velocity.x = 0.0
				actor.motion.native_velocity.z = 0.0
	commands[OWNER_ID] = command
	simulation.step_fixed(commands)
	if arsenal != null: arsenal.step()
	var proposals: Array[Dictionary] = _zombie_director.drain_attack_intents() if _zombie_director != null else []
	_advance_attacks(proposals)
	if phase == "preparation":
		_preparation_ticks += 1
		if _preparation_ticks >= int(_settings.preparation_seconds) * RULES.HZ:
			phase = "active"
	elif phase == "active":
		_active_ticks += 1
		if _active_ticks >= _duration_ticks:
			_close_window()
			phase = "cleanup"
	var events: Array[Dictionary] = simulation.drain_events()
	_track_survival_events(events)
	_ingest_events(events)
	_advance_supply()
	_ingest_events(simulation.drain_events())
	if not owner.is_alive():
		_finish("defeat", "death")
	elif phase == "cleanup" and _live_count() == 0 and simulation.grenades.is_empty() and (arsenal == null or not arsenal.has_pending()):
		if _spawned > 0 and not (_wave_spawned == 0 and _spawn_unavailable_since >= 0):
			_finish("win", "survived")
		else:
			_finish("interrupted", "spawn_unavailable")
	elif phase in ["active", "cleanup"]:
		_check_stalls()
	var transactions: Array[Dictionary] = simulation.drain_transactions()
	var refresh_required: bool = not transactions.is_empty() and bool(transactions[-1].get("refresh_required", false))
	update(0.0)
	_offer_rush_upgrade()
	return {"ok": true, "error": "", "advanced": true, "tick": simulation.tick,
		"transactions": transactions, "presentation_refresh_required": refresh_required}


func _advance_spawns() -> void:
	# Exactly one allocation attempt per tick. Expired windows never accumulate
	# debt, even after cap pressure, pause, or a deferred navigation budget.
	if _active_ticks >= _duration_ticks:
		return
	if _active_ticks % _interval_ticks == 0:
		_close_window()
		wave += 1
		_wave_start = _active_ticks
		_wave_planned = SETTINGS.wave_quota(_settings, _active_ticks)
		_wave_attempted = 0
		_wave_spawned = 0
		_wave_skipped = 0
		_planned += _wave_planned
		_supply_ticks = 0
		_emit_survival_event("survival_wave", {"wave": wave, "quota": _wave_planned, "up_to": true}, simulation.tick + 1)
	var elapsed: int = _active_ticks - _wave_start
	if elapsed >= _wave_window_ticks:
		_close_window()
		return
	if not _pending_spawn.is_empty():
		if simulation.tick + 1 >= int(_pending_spawn.ready_tick):
			_commit_spawn(_pending_spawn)
			_pending_spawn.clear()
		return
	# Navigation may defer work within an allocation interval, but missed
	# intervals expire instead of issuing a catch-up burst on later ticks.
	while _wave_attempted + 1 < _wave_planned:
		var next_due: int = floori(float((_wave_attempted + 1) * _wave_window_ticks) / float(_wave_planned))
		if next_due > elapsed:
			break
		_wave_attempted += 1
		_skip_spawn()
	if _wave_attempted >= _wave_planned:
		return
	var due: int = int(floorf(float(_wave_attempted * _wave_window_ticks) / float(_wave_planned)))
	if elapsed < due:
		return
	if _live_count() >= int(_settings.live_limit):
		_wave_attempted += 1
		_skip_spawn()
		return
	var candidate: Dictionary = _zombie_director.choose_spawn(simulation, OWNER_ID, 12.0) if _zombie_director != null else {"ok": false}
	if not bool(candidate.get("ok", false)):
		if bool(candidate.get("budget_deferred", false)) or str(candidate.get("error", "")) in ["budget_deferred", "budget_exhausted"]:
			return
		_wave_attempted += 1
		_skip_spawn()
		_note_spawn_failure()
		return
	_wave_attempted += 1
	if not bool(candidate.get("route_valid", false)) or not _safe_spawn(candidate.point):
		_skip_spawn()
		_note_spawn_failure()
		return
	if bool(candidate.get("hidden", false)):
		_commit_spawn(candidate)
	else:
		_pending_spawn = candidate.duplicate(true)
		_pending_spawn.ready_tick = simulation.tick + 1 + VISIBLE_WARNING_TICKS
		_emit_survival_event("zombie_spawn_warning", {"position": candidate.point,
			"seconds": float(VISIBLE_WARNING_TICKS) / RULES.HZ, "wave": wave}, simulation.tick + 1)


func _commit_spawn(candidate: Dictionary) -> void:
	var point: Vector3 = candidate.point
	if not _safe_spawn(point) or _live_count() >= int(_settings.live_limit):
		_skip_spawn()
		if _live_count() < int(_settings.live_limit):
			_note_spawn_failure()
		return
	if int(candidate.get("map_sequence", simulation.data.map_sequence)) != simulation.data.map_sequence:
		var route: Dictionary = _zombie_director.route_valid(point, simulation.get_actor(OWNER_ID).feet(), simulation) if _zombie_director != null else {"ok": false}
		if not bool(route.get("ok", false)):
			_skip_spawn()
			_note_spawn_failure()
			return
	var free_id: int = -1
	for id: int in ZOMBIE_IDS:
		if not simulation.get_actor(id).is_alive():
			free_id = id
			break
	if free_id < 0:
		_skip_spawn()
		return
	var result: Dictionary = simulation.spawn_zombie_slot(free_id, point)
	if not result.ok:
		_skip_spawn()
		return
	# Count successful admission, not planned/skipped quota or registry ID. The
	# fourth real life of a match is a grenadier even when earlier slots recycle.
	var zombie_type: String = "grenadier" if (_spawned + 1) % 4 == 0 else "walker"
	simulation.assign_zombie_type(free_id, zombie_type)
	_face_front(simulation.get_actor(free_id), simulation.data.dimensions)
	_attacks.erase(free_id)
	_attack_deadlines.erase(free_id)
	_throw_deadlines.erase(free_id)
	_progress[free_id] = {"position": point, "tick": simulation.tick + 1}
	_wave_spawned += 1
	_spawned += 1
	_last_spawn_tick = simulation.tick + 1
	_spawn_unavailable_since = -1


func _note_spawn_failure() -> void:
	if _spawn_unavailable_since < 0:
		_spawn_unavailable_since = simulation.tick + 1


func _safe_spawn(point: Vector3) -> bool:
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
	return point.is_finite() and point.distance_to(owner.feet()) >= 12.0 \
		and _supported_spawn(simulation.data, point) and simulation._spawn_clear(point)


func _skip_spawn() -> void:
	_wave_skipped += 1
	_skipped += 1


func _close_window() -> void:
	if _wave_planned == 0:
		return
	# All quota not actually admitted expires here; no skipped lives enter a
	# later wave. Counting once uses the remaining quota rather than attempts.
	var remaining: int = maxi(0, _wave_planned - _wave_spawned - _wave_skipped)
	_wave_skipped += remaining
	_skipped += remaining
	_wave_attempted = _wave_planned
	_pending_spawn.clear()


func _advance_attacks(proposals: Array[Dictionary]) -> void:
	var proposed: Dictionary[int, Dictionary] = {}
	for proposal: Dictionary in proposals:
		var id: int = int(proposal.get("actor_id", 0))
		var actor: SharedPlayerState = simulation.get_actor(id)
		if id in ZOMBIE_IDS and not proposed.has(id) and actor != null and actor.is_alive() and _valid_attack(actor, proposal):
			proposed[id] = proposal
	for id: int in ZOMBIE_IDS:
		var actor: SharedPlayerState = simulation.get_actor(id)
		if actor != null and actor.is_alive() and arsenal != null and arsenal.movement_scale(id) <= 0.0:
			if _attacks.has(id):
				_attacks[id].deadline += 1
				_attacks[id].started += 1
			continue
		if actor == null or not actor.is_alive() or not proposed.has(id):
			_attacks.erase(id)
			continue
		var proposal: Dictionary = proposed[id]
		var kind: String = str(proposal.get("kind", ""))
		if not _valid_attack(actor, proposal):
			_attacks.erase(id)
			continue
		if _attacks.has(id) and (_attacks[id].kind != kind or _attacks[id].get("cell") != proposal.get("cell")):
			_attacks.erase(id)
		if not _attacks.has(id):
			if simulation.tick < int(_attack_deadlines.get(id, -1)):
				continue
			var windup: int = THROW_WINDUP if kind == "throw" else (BITE_WINDUP if kind == "bite" else BREACH_WINDUP)
			_attacks[id] = {"kind": kind, "cell": proposal.get("cell"), "started": simulation.tick,
				"deadline": simulation.tick + windup, "windup": windup, "generation": actor.spawn_generation}
			_emit_survival_event("zombie_attack_started", {"actor_id": id,
				"kind": kind, "position": actor.feet(), "windup_seconds": float(windup) / RULES.HZ})
		var attack: Dictionary = _attacks[id]
		if simulation.tick < int(attack.deadline):
			continue
		_attacks.erase(id)
		if kind != "throw":
			_attack_deadlines[id] = int(attack.started) + (BITE_CYCLE if kind == "bite" else BREACH_CYCLE)
		var confirmed: Array[Dictionary] = []
		if kind == "bite" and simulation.tick >= _bite_protection_deadline:
			confirmed = simulation.resolve_zombie_bite(id, OWNER_ID, int(_settings.zombie_damage), BITE_RANGE)
			if not MatchSimulation.events_of(confirmed, "hurt").is_empty():
				_bite_protection_deadline = simulation.tick + CROWD_PROTECTION
		elif kind == "breach":
			confirmed = simulation.resolve_zombie_breach(id, proposal.cell, int(_settings.zombie_block_damage), BREACH_CYCLE)
		elif kind == "throw":
			confirmed = simulation.throw_zombie_grenade(id, simulation.get_actor(OWNER_ID).feet() + Vector3.UP * 1.1,
				int(_settings.zombie_damage), int(_settings.zombie_block_damage))
			if not confirmed.is_empty():
				_throw_deadlines[id] = simulation.tick + THROW_COOLDOWN
		if not confirmed.is_empty():
			_record_attack_progress(id, proposal, proposed)


func _record_attack_progress(actor_id: int, confirmed: Dictionary, proposals: Dictionary[int, Dictionary]) -> void:
	# A shared-cell hit advances the whole valid attack queue. Only one member
	# can damage that cell per cadence; waiting members must not time out while
	# its real health is falling. A proposal/windup alone is never progress.
	for id: int in ZOMBIE_IDS:
		var actor: SharedPlayerState = simulation.get_actor(id)
		if not actor.is_alive():
			continue
		var progressed: bool = id == actor_id
		if not progressed and proposals.has(id):
			var queued: Dictionary = proposals[id]
			if str(confirmed.kind) == "breach" and str(queued.get("kind", "")) == "breach" \
					and queued.get("cell") == confirmed.get("cell"):
				# The final strike may already remove/collapse the cell. Reach is
				# checked against its captured coordinates, not its former color.
				progressed = SIMULATION.in_reach(actor, confirmed.cell)
			elif str(confirmed.kind) == "bite" and str(queued.get("kind", "")) == "bite":
				progressed = _valid_attack(actor, queued)
		if progressed:
			_progress[id] = {"position": actor.feet(), "tick": simulation.tick}


func _valid_attack(actor: SharedPlayerState, proposal: Dictionary) -> bool:
	var kind: String = str(proposal.get("kind", ""))
	if kind == "throw":
		if not _can_throw(actor.player_id) or typeof(proposal.get("target")) != TYPE_VECTOR3:
			return false
		var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
		var range_to_owner: float = actor.feet().distance_to(owner.feet())
		var target: Vector3 = proposal.target
		var torso: Vector3 = owner.feet() + Vector3.UP * 1.1
		if not owner.is_alive() or not target.is_finite() or range_to_owner < THROW_MIN_RANGE \
				or range_to_owner > THROW_MAX_RANGE or target.distance_to(torso) > 0.75:
			return false
		var origin: Vector3 = actor.feet() + Vector3.UP * 1.1
		var offset: Vector3 = torso - origin
		return not bool(simulation.data.cast_voxel(origin, offset, offset.length() - 0.05).hit)
	if kind == "bite":
		var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
		if not owner.is_alive() or actor.feet().distance_to(owner.feet()) > BITE_RANGE:
			return false
		var origin: Vector3 = actor.feet() + Vector3.UP * 1.1
		var endpoint: Vector3 = owner.feet() + Vector3.UP * 1.1
		var difference: Vector3 = endpoint - origin
		var hit: Dictionary = simulation.data.cast_voxel(origin, difference, difference.length())
		return not bool(hit.get("hit", false)) or origin.distance_to(hit.position) >= difference.length() - 0.05
	if kind == "breach" and typeof(proposal.get("cell")) == TYPE_VECTOR3I:
		var cell: Vector3i = proposal.cell
		if cell.y <= 1 or not simulation.data.is_in_bounds(cell) or simulation.data.get_block(cell) == 0 \
				or not SIMULATION.in_reach(actor, cell):
			return false
		var origin: Vector3 = actor.feet() + Vector3.UP * 1.1
		var difference: Vector3 = Vector3(cell) + Vector3.ONE * 0.5 - origin
		var hit: Dictionary = simulation.data.cast_voxel(origin, difference, difference.length() + 0.1)
		return bool(hit.get("hit", false)) and hit.cell == cell
	return false


func _can_throw(id: int) -> bool:
	var actor: SharedPlayerState = simulation.get_actor(id)
	var loadout: Dictionary = simulation.get_zombie_loadout(id)
	return actor != null and actor.is_alive() and not loadout.is_empty() \
		and str(loadout.type) == "grenadier" and int(loadout.generation) == actor.spawn_generation \
		and int(loadout.remaining) > 0 and simulation.tick >= int(_throw_deadlines.get(id, -1)) \
		and simulation.zombie_projectile_count() < SIMULATION.MAX_ZOMBIE_GRENADES


func _sync_zombie_loadouts() -> void:
	if _zombie_director == null:
		return
	for id: int in ZOMBIE_IDS:
		var actor: SharedPlayerState = simulation.get_actor(id)
		if not actor.is_alive():
			continue
		var loadout: Dictionary = simulation.get_zombie_loadout(id)
		_zombie_director.set_zombie_loadout(id, actor.spawn_generation, str(loadout.get("type", "walker")), _can_throw(id))


func _track_survival_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		if int(event.get("owner_id", 0)) != OWNER_ID:
			continue
		if event.type == "hurt":
			damage_taken += int(event.amount)
			_last_owner_hurt_tick = simulation.tick
		elif event.type == "hit_confirmed" and event.part == "head":
			headshots += 1


func _advance_supply() -> void:
	var owner: SharedPlayerState = simulation.get_actor(OWNER_ID)
	var between_windows: bool = phase == "cleanup" or (phase == "active" and _active_ticks - _wave_start >= _wave_window_ticks)
	if not owner.is_alive() or not between_windows or wave == 0:
		_supply_ticks = 0
		_supply_status = "unavailable"
		return
	if _supply_used_wave >= wave:
		_supply_ticks = 0
		_supply_status = "used"
		return
	var safe: bool = simulation.tick - _last_owner_hurt_tick >= SUPPLY_STAND_TICKS
	for id: int in ZOMBIE_IDS:
		var actor: SharedPlayerState = simulation.get_actor(id)
		if actor.is_alive() and actor.feet().distance_to(owner.feet()) < SUPPLY_SAFE_DISTANCE:
			safe = false
			break
	for projectile: SharedGrenadeState in simulation.grenades.values():
		if projectile.position.distance_to(owner.feet()) < SUPPLY_SAFE_DISTANCE:
			safe = false
			break
	if not safe:
		_supply_ticks = 0
		_supply_status = "unsafe"
		return
	_supply_status = "ready"
	if owner.feet().distance_to(_supply_position) >= SUPPLY_RADIUS \
			or Vector2(owner.motion.native_velocity.x, owner.motion.native_velocity.z).length() > 0.02:
		_supply_ticks = 0
		return
	_supply_ticks += 1
	_supply_status = "progress"
	if _supply_ticks >= SUPPLY_STAND_TICKS:
		simulation.survival_supply(OWNER_ID)
		_supply_used_wave = wave
		_supply_ticks = 0
		_supply_status = "used"


func _check_stalls() -> void:
	for id: int in ZOMBIE_IDS:
		var actor: SharedPlayerState = simulation.get_actor(id)
		if not actor.is_alive():
			_progress.erase(id)
			continue
		var progress: Dictionary = _progress.get(id, {"position": actor.feet(), "tick": simulation.tick})
		if actor.feet().distance_to(progress.position) >= 0.6:
			_progress[id] = {"position": actor.feet(), "tick": simulation.tick}
		elif simulation.tick - int(progress.tick) >= STALL_TICKS:
			_finish("interrupted", "route_unavailable")
			return
	# Failure to admit any enemy is a technical failure, never a free victory.
	if phase == "active" and _live_count() == 0 and (_spawned == 0 and _active_ticks >= STALL_TICKS \
			or _spawn_unavailable_since >= 0 and simulation.tick - _spawn_unavailable_since >= STALL_TICKS):
		_finish("interrupted", "spawn_unavailable")


func _live_count() -> int:
	var count: int = 0
	if simulation != null:
		for id: int in ZOMBIE_IDS:
			if simulation.get_actor(id).is_alive():
				count += 1
	return count


func _finish(result: String, reason: String) -> void:
	if finished:
		return
	# A bite can end the life after arsenal.step(), and a finished run never
	# advances again. Cancel per-life ordnance at this terminal boundary itself.
	if arsenal != null: arsenal.clear()
	_close_window()
	finished = true
	paused = true
	phase = "finished"
	outcome = result
	finish_reason = reason
	winning_team = 0 if result == "win" else -1
	_supply_ticks = 0
	_rush_pending = false
	_rush_choices.clear()
	_attacks.clear()
	for id: int in simulation.actors:
		simulation.clear_controls(id)
	_emit_survival_event("survival_finished", {"outcome": outcome, "reason": finish_reason,
		"wave": wave, "spawned": _spawned, "skipped": _skipped, "time": float(_active_ticks) / RULES.HZ})
	objectives_changed.emit()
	if result == "win":
		round_won.emit(0)


func _emit_survival_event(kind: String, details: Dictionary, event_tick: int = -1) -> void:
	_survival_event_sequence += 1
	var event: Dictionary = details.duplicate(true)
	event.merge({"type": kind, "epoch": simulation.epoch, "tick": maxi(0, simulation.tick) if event_tick < 0 else event_tick,
		"owner_id": 0, "spawn_generation": 0, "mode": "survival",
		"event_id": "%d:survival:%d" % [simulation.epoch, _survival_event_sequence]}, true)
	_queue_presentation(event)
	_append_log(event)


func get_survival_state() -> Dictionary:
	var remaining: float = maxf(0.0, float(_duration_ticks - _active_ticks) / RULES.HZ)
	var preparation_remaining: float = maxf(0.0, float(int(_settings.get("preparation_seconds", 20)) * RULES.HZ - _preparation_ticks) / RULES.HZ)
	return {"phase": phase, "outcome": outcome, "paused": paused, "finished": finished,
		"finish_reason": finish_reason, "time_remaining": remaining, "preparation_remaining": preparation_remaining,
		"elapsed_seconds": float(_active_ticks) / RULES.HZ, "wave": wave,
		"wave_planned": _wave_planned, "wave_spawned": _wave_spawned, "wave_skipped": _wave_skipped,
		"planned": _planned, "spawned": _spawned, "skipped": _skipped, "live": _live_count(),
		"active_grenades": simulation.grenades.size() if simulation != null else 0,
		"zombie_grenades": simulation.zombie_projectile_count() if simulation != null else 0,
		"live_limit": int(_settings.get("live_limit", SETTINGS.MAX_LIVE)), "quota_up_to": true,
		"next_wave_seconds": maxf(0.0, float(_interval_ticks - (_active_ticks - _wave_start)) / RULES.HZ) if phase == "active" else 0.0,
		"window_remaining": maxf(0.0, float(_wave_window_ticks - (_active_ticks - _wave_start)) / RULES.HZ) if phase == "active" else 0.0,
		"kills": player_kills, "headshots": headshots, "damage_taken": damage_taken,
		"supply_position": _supply_position, "supply_progress": float(_supply_ticks) / SUPPLY_STAND_TICKS,
		"supply_available": _supply_status in ["ready", "progress"], "supply_status": _supply_status,
		"supply_used_wave": _supply_used_wave, "settings": _settings.duplicate(true)}


func get_rush_state() -> Dictionary:
	var owner: SharedPlayerState = get_owner_state()
	var kills: int = owner.kills if owner != null else 0
	var enabled: bool = str(_settings.get("run_style", "classic")) == "rush"
	var score: int = 0
	if enabled and outcome != "interrupted":
		score = kills * 100 + headshots * 50 + floori(float(_active_ticks) / RULES.HZ) * 5
		if outcome == "win":
			score += 1000
	return {"enabled": enabled, "pending": _rush_pending,
		"choices": _rush_choices.duplicate(true), "levels": _rush_levels.duplicate(true),
		"kills": kills, "next_kills": RUSH_KILL_THRESHOLDS[_rush_choices_taken] if enabled and _rush_choices_taken < RUSH_KILL_THRESHOLDS.size() else 0,
		"score": score}


func _offer_rush_upgrade() -> void:
	var owner: SharedPlayerState = get_owner_state()
	if str(_settings.get("run_style", "classic")) != "rush" or _rush_pending or finished \
			or owner == null or not owner.is_alive() or _rush_choices_taken >= RUSH_KILL_THRESHOLDS.size() \
			or owner.kills < RUSH_KILL_THRESHOLDS[_rush_choices_taken]:
		return
	_rush_choices.clear()
	if _rush_levels.power < RUSH_MAX_PERK_LEVEL:
		_rush_choices.append({"id": "power", "title_ru": "Мощность", "title_en": "Firepower",
			"description_ru": "+25% урона огнестрельного оружия. До 3 уровней.",
			"description_en": "+25% firearm damage. Up to 3 ranks."})
	if _rush_levels.armor < RUSH_MAX_PERK_LEVEL:
		_rush_choices.append({"id": "armor", "title_ru": "Броня", "title_en": "Armor",
			"description_ru": "−15% урона укусов и гранат зомби. До 3 уровней.",
			"description_en": "−15% damage from zombie bites and grenades. Up to 3 ranks."})
	_rush_choices.append({"id": "field_kit", "title_ru": "Полевой набор", "title_en": "Field kit",
		"description_ru": "+35 здоровья, полный запас патронов, +20 блоков и +1 граната.",
		"description_en": "+35 health, full reserve ammo, +20 blocks and +1 grenade."})
	_rush_pending = true
	_clear_pending_intent()
	for id: int in simulation.actors:
		simulation.clear_controls(id)
	_emit_survival_event("rush_upgrade_ready", {"milestone": _rush_choices_taken, "kills": owner.kills})


func choose_upgrade(id: String) -> Dictionary:
	var owner: SharedPlayerState = get_owner_state()
	if not _rush_pending or paused or finished or owner == null or not owner.is_alive():
		return {"ok": false, "error": "No active Rush choice"}
	var offered: bool = false
	for choice: Dictionary in _rush_choices:
		if str(choice.id) == id:
			offered = true
			break
	if not offered:
		return {"ok": false, "error": "Choose an offered upgrade"}
	var applied: bool = false
	match id:
		"power": applied = simulation.set_survival_firearm_level(OWNER_ID, _rush_levels.power + 1)
		"armor": applied = simulation.set_survival_armor_level(OWNER_ID, _rush_levels.armor + 1)
		"field_kit": applied = simulation.survival_field_kit(OWNER_ID)
	if applied and id == "field_kit" and arsenal != null: arsenal.refill_primary()
	if not applied:
		return {"ok": false, "error": "Upgrade could not be applied"}
	_rush_levels[id] += 1
	_rush_choices_taken += 1
	_rush_pending = false
	_rush_choices.clear()
	_clear_pending_intent()
	simulation.clear_controls(OWNER_ID)
	_ingest_events(simulation.drain_events())
	_emit_survival_event("rush_upgrade_chosen", {"upgrade": id, "level": _rush_levels[id]})
	update(0.0)
	return {"ok": true, "error": ""}


func get_diagnostics() -> Dictionary:
	var result: Dictionary = get_survival_state()
	result.merge({"tick": simulation.tick if simulation != null else -1,
		"bot_count": _live_count(), "slot_count": ZOMBIE_IDS.size(),
		"elapsed_ticks": _active_ticks, "preparation_ticks": _preparation_ticks,
		"pending_spawn": not _pending_spawn.is_empty(), "presentation_overflow": _presentation_overflow,
		"bots": _zombie_director.get_diagnostics() if _zombie_director != null else {}}, true)
	return result


func update(delta: float) -> void:
	super.update(delta)
	mode = "survival"
	round_remaining = maxf(0.0, float(_duration_ticks - _active_ticks) / RULES.HZ)
	respawn_remaining = 0.0
	team_scores = [player_kills, 0]
	capture_limit = 0


func _mirror_targets() -> void:
	targets.clear()
	for id: int in ZOMBIE_IDS:
		var actor: SharedPlayerState = simulation.get_actor(id)
		if actor == null:
			continue
		var alive: bool = actor.is_alive()
		var moving: bool = alive and Vector2(actor.motion.native_velocity.x, actor.motion.native_velocity.z).length_squared() > 0.000001
		var attack: Dictionary = _attacks.get(id, {})
		var loadout: Dictionary = simulation.get_zombie_loadout(id)
		var attack_phase: float = clampf(float(simulation.tick - int(attack.get("started", 0))) / float(attack.get("windup", 1)), 0.0, 1.0) if not attack.is_empty() else 0.0
		targets.append({"id": id, "name": actor.player_name, "kind": "zombie", "team": 1,
			"registry_kind": actor.registry_kind, "health": -1, "health_known": false, "alive": alive,
			"zombie_type": str(loadout.get("type", "walker")), "throw_remaining": int(loadout.get("remaining", 0)),
			"slot_alive": alive, "kills": actor.kills, "deaths": actor.deaths, "score": actor.score,
			"position": actor.feet(), "feet": actor.feet(), "spawn_generation": actor.spawn_generation,
			"native_velocity": actor.motion.native_velocity, "yaw": actor.yaw, "pitch": actor.pitch,
			"crouch": actor.motion.crouch, "crouching": actor.motion.crouch, "sprinting": false,
			"wading": actor.motion.wading, "grounded": actor.motion.grounded, "moving": moving,
			"state": "dead" if not alive else ("walking" if moving else "standing"),
			"weapon": 0, "tool": 0, "displayed_weapon": 0, "displayed_tool": 0,
			"aiming": false, "aim_down_state": 0.0, "raise_state": 1.0, "tool_raise": 1.0,
			"sprint_state": 0.0, "reloading": false, "profile": actor.profile, "phase": session_time,
			"respawn_remaining": 0.0, "death_crouch": actor.motion.crouch,
			"death_velocity": actor.motion.native_velocity * 32.0, "carries_intel": false,
			"attack_phase": attack_phase, "attack_kind": str(attack.get("kind", "")), "visual_only": true})


func select_weapon(index: int) -> void:
	if simulation != null and paused and not finished and simulation.tick < 0 and index in [0, 1, 2]:
		_starting_weapon = index
		configure_survival(simulation.data, _arena.duplicate(true), _settings.duplicate(true), _local_name, _test_overrides)


# Deliberate replacement of all TDM policy extension points.
func _respawn_ready_actors() -> void: pass
func _restock_at_supply() -> void: pass
func _recount_scores() -> void: pass
