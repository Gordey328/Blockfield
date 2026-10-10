class_name NetworkSession
extends LocalSession
## Presentation compatibility only. The replica owns prediction/confirmed state;
## no inherited local authority, socket polling or fixed-step runs in this node.
const REPLICA = preload("res://network/client_replica.gd")
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const EVENTS = preload("res://network/events_codec.gd")
const MAX_LOG := 128
const MAX_SHOT_REFERENCES := 128
const EMPTY_INTENT := {"tool":255,"weapon":255,"reload":false,"team":-1,"color":-1}
const COSMETIC_TYPES := ["shot","dry_fire","reload_started","reload_cancelled","shell_loaded","reload_completed","tool_selected","class_pending","grenade_pin","grenade_release","spade_bash","spade_dig","jump","land","footstep"]

var tool_raise := 0.0
var displayed_tool := Tool.WEAPON
var displayed_weapon := Weapon.RIFLE
var sprint_state := 0.0
var aim_down_state := 0.0
var spawn_generation := 0
var input_ack := 0
var player_kills := 0
var confirmed_tick := -1
var _replica: REPLICA
var _owner: STATE
var _intent: Dictionary = EMPTY_INTENT.duplicate()
var _view_epoch := 0
var _shots: Dictionary[String,Dictionary] = {}

func _init() -> void: _clear_view()

func _ready() -> void:
	# LocalSession._ready resets objective authority. A network view must not.
	update(0)

func bind_replica(replica: REPLICA) -> void:
	if replica == _replica: return
	_replica = replica
	_view_epoch = 0
	_intent = EMPTY_INTENT.duplicate()
	_shots.clear()
	event_log.clear()
	shots_fired = 0
	hits_landed = 0
	last_damage = 0
	last_hit_part = ""
	_clear_view()
	update(0)

func local_player_id() -> int:
	return _replica.actor_id if _replica != null and _replica.actor_id > 0 else 0

func is_local_intel_carrier() -> bool:
	var id := local_player_id()
	if id <= 0: return false
	for flag: Dictionary in ctf_flags:
		if int(flag.carrier) == id: return true
	return false

func get_replica_status() -> Dictionary:
	return _replica.get_stats() if _replica != null else {"status":"unbound","actor_id":0}

func drain_intent() -> Dictionary:
	var pending := _intent.duplicate()
	_intent = EMPTY_INTENT.duplicate()
	return pending

func request_block_color(color: int) -> bool:
	if _owner == null or color < 0x01000000 or color > 0x01ffffff: return false
	_intent.color = color
	return true

func update(delta: float) -> void:
	if not is_finite(delta) or delta < 0: return
	if _replica == null or _replica.status != "live":
		var was_live := _owner != null
		_clear_view()
		_intent = EMPTY_INTENT.duplicate()
		if was_live: changed.emit()
		return
	var owner := _replica.get_owner_state()
	var confirmed := _replica.get_public_state()
	if owner == null or confirmed.is_empty(): return
	if owner.player_id != _replica.actor_id or owner.match_epoch != _replica.epoch: return
	if _view_epoch != owner.match_epoch:
		_view_epoch = owner.match_epoch
		_shots.clear()
		_intent = EMPTY_INTENT.duplicate()
		event_log.clear()
		shots_fired = 0
		hits_landed = 0
		last_damage = 0
		last_hit_part = ""
		last_shot_time = -1
	if spawn_generation != owner.spawn_generation:
		_intent = EMPTY_INTENT.duplicate()
		last_shot_time = -1
	_owner = owner # This getter already owns a copy, not the predictor pointer.
	profile_version = owner.profile
	current_weapon = owner.weapon
	current_tool = owner.tool
	displayed_weapon = owner.displayed_weapon
	displayed_tool = owner.displayed_tool
	tool_raise = owner.tool_raise
	sprint_state = owner.sprint_state
	aim_down_state = owner.aim_down_state
	spawn_generation = owner.spawn_generation
	input_ack = owner.consumed_input_sequence
	magazine = owner.magazine
	reserve = owner.reserve
	grenades = owner.grenades
	blocks = owner.blocks
	health = owner.health
	team = owner.team
	score = owner.score
	player_name = owner.player_name
	player_deaths = owner.deaths
	player_kills = owner.kills
	player_position = owner.feet()
	session_time = float(owner.last_tick)/RULES.HZ
	confirmed_tick = confirmed.tick
	is_reloading = owner.reloading
	reload_remaining = maxf(0,(owner.reload_deadline_tick-owner.last_tick)/RULES.HZ) if owner.reloading else 0
	fire_cooldown = (owner.next_shot_tick-owner.last_tick)/RULES.HZ
	grenade_cooldown = maxf(0,(owner.grenade_deadline_tick-owner.last_tick)/RULES.HZ)
	block_cooldown = maxf(0,(owner.block_deadline_tick-owner.last_tick)/RULES.HZ)
	is_cooking_grenade = owner.cooking
	grenade_cook_time = maxf(0,float(owner.last_tick-owner.cook_started_tick)/RULES.HZ) if owner.cooking else 0
	respawn_remaining = maxf(0,float(owner.respawn_tick-owner.last_tick)/RULES.HZ) if owner.health <= 0 and owner.respawn_tick >= 0 else 0
	if owner.last_shot_tick >= 0: last_shot_time = maxf(last_shot_time,float(owner.last_shot_tick)/RULES.HZ)
	unlimited_ammo = false
	invulnerable = false
	_trigger_held = owner.trigger_held
	_grenade_release_pending = owner.release_pending
	var objectives: Dictionary = confirmed.objectives
	var objective_changed: bool = mode != objectives.mode or capture_limit != objectives.capture_limit or winning_team != objectives.winning_team or team_scores != objectives.scores or ctf_bases != objectives.bases or ctf_flags != objectives.flags or territories != objectives.territories
	mode = objectives.mode
	capture_limit = objectives.capture_limit
	winning_team = objectives.winning_team
	team_scores.assign(objectives.scores)
	ctf_bases.assign(objectives.bases)
	ctf_flags.assign(objectives.flags.duplicate(true))
	territories.assign(objectives.territories.duplicate(true))
	_mirror_targets(confirmed.actors)
	live_grenades.clear()
	for grenade: Dictionary in confirmed.grenades:
		var visual := grenade.duplicate(true)
		visual.fuse = maxf(0,(float(grenade.fuse_deadline_tick)-confirmed.tick)/RULES.HZ)
		visual.visual_only = true
		live_grenades.append(visual)
	if objective_changed: objectives_changed.emit()
	changed.emit()

func _mirror_targets(actors: Array) -> void:
	targets.clear()
	for actor: Dictionary in actors:
		if actor.id == local_player_id(): continue
		var sampled := _replica.sample_remote(actor.id)
		if sampled.is_empty() or sampled.spawn_generation != actor.spawn_generation: sampled = actor
		var flags: int = sampled.flags
		var crouch := (flags&2) != 0
		var sprint := (flags&4) != 0
		var moving: bool = actor.alive and Vector2(sampled.native_velocity.x,sampled.native_velocity.z).length_squared() > .000001
		var state := "dead" if not actor.alive else ("crouching" if crouch else ("sprinting" if sprint else ("walking" if moving else "standing")))
		var carries := false
		for flag: Dictionary in ctf_flags:
			if int(flag.carrier) == actor.id: carries = true
		var target := actor.duplicate(true)
		target.position = sampled.feet
		target.feet = sampled.feet
		target.native_velocity = sampled.native_velocity
		target.yaw = sampled.yaw
		target.pitch = sampled.pitch
		target.crouch = crouch
		target.crouching = crouch
		target.sprinting = sprint
		target.wading = (flags&8) != 0
		target.grounded = (flags&16) != 0
		target.health = -1 # Public state intentionally does not disclose HP.
		target.health_known = false
		target.moving = moving
		target.state = state
		target.carries_intel = carries
		target.aiming = actor.aim_down_state > .001 # Visible blend, not private input.
		target.raise_state = actor.tool_raise
		target.profile = profile_version
		target.phase = session_time
		target.respawn_remaining = -1.0 # Remote respawn deadline is private.
		target.death_crouch = crouch
		target.death_velocity = sampled.native_velocity*32
		target.visual_only = true
		target.poor_connection = sampled.get("poor_connection",false)
		target.interpolation_mode = sampled.get("mode","confirmed")
		targets.append(target)

func get_target(target_id: int) -> Dictionary:
	for target: Dictionary in targets:
		if int(target.id) == target_id: return target.duplicate(true)
	return {}

func get_weapon_info() -> Dictionary:
	var version := _owner.profile if _owner != null else "0.75"
	var weapon := _owner.weapon if _owner != null else Weapon.RIFLE
	var info := PROFILES.get_info(version,weapon)
	info.weapon_index = weapon
	info.profile = version
	info.magazine = _owner.magazine if _owner != null else 0
	info.reserve = _owner.reserve if _owner != null else 0
	return info

func is_tool_selectable(index: int) -> bool:
	return _owner != null and RULES.can_act(_owner) and RULES.tool_selectable(_owner,index)

func can_fire() -> bool:
	return _owner != null and RULES.can_fire(_owner,_owner.last_tick)

func get_reload_progress() -> float:
	return RULES.reload_progress(_owner,_owner.last_tick) if _owner != null else 0.0

func select_weapon(index: int) -> void:
	if _owner != null and index >= 0 and index <= 2: _intent.weapon = index

func select_tool(index: int) -> void:
	if is_tool_selectable(index): _intent.tool = index

func select_team(index: int) -> void:
	if _owner != null and index >= 0 and index <= 2: _intent.team = index

func reload_weapon() -> void:
	if _owner != null and RULES.can_act(_owner): _intent.reload = true

func _actor_info(id: int) -> Dictionary:
	if id == local_player_id() and _owner != null: return {"id":id,"name":_owner.player_name,"team":_owner.team,"spawn_generation":_owner.spawn_generation}
	return get_target(id)

func ingest_event(event: Dictionary, predicted_already_played: bool = false) -> bool:
	# Caller supplies EventsCodec-validated confirmed events, already deduplicated
	# by the replica. This bridge only emits presentation signals/log records.
	if _replica == null or _owner == null or event.get("epoch",0) != _replica.epoch or typeof(event.get("type")) != TYPE_STRING or not EVENTS.SCHEMAS.has(event.type): return false
	for key: String in ["tick","owner_id","spawn_generation"]:
		if typeof(event.get(key)) != TYPE_INT or event[key] < 0 or event[key] > RULES.MAX_UINT32: return false
	if event.owner_id > 0 and event.spawn_generation == 0: return false
	for field: Array in EVENTS.SCHEMAS[event.type]:
		if not event.has(field[0]): return false
	if typeof(event.get("event_id")) != TYPE_STRING: return false
	var actor := _actor_info(event.owner_id)
	if not actor.is_empty() and event.spawn_generation < actor.spawn_generation: return false
	var own: bool = event.owner_id == local_player_id()
	var kind: String = event.type
	if kind == "shot":
		_shots[str(event.event_id)] = {"weapon":event.weapon,"owner_id":event.owner_id}
		while _shots.size() > MAX_SHOT_REFERENCES: _shots.erase(_shots.keys()[0])
		if own:
			shots_fired += 1
			last_shot_time = maxf(last_shot_time,float(event.tick)/RULES.HZ)
			if not predicted_already_played: shot_fired.emit()
	elif own:
		match kind:
			"reload_completed":
				if not predicted_already_played: reloaded.emit()
			"restock": restocked.emit()
			"hurt": player_hurt.emit(float(event.amount),Vector3.INF,str(event.cause))
			"death":
				last_death_kind = event.cause
				player_died.emit()
			"spawn": player_respawned.emit()
			"hit_confirmed":
				hits_landed += 1
				last_damage = event.damage
				last_hit_part = event.part
	if not own:
		if kind == "death": target_died.emit(event.owner_id)
		elif kind == "spawn": target_respawned.emit(event.owner_id)
	if kind == "grenade_thrown":
		var visual := event.duplicate(true)
		visual.visual_only = true
		visual.predicted_already_played = own and predicted_already_played
		grenade_thrown.emit(visual)
	elif kind == "grenade_exploded":
		var visual := event.duplicate(true)
		visual.id = event.grenade_id
		visual.visual_only = true
		grenade_exploded.emit(visual)
	elif kind == "round_won": round_won.emit(event.winning_team)
	var entry := event.duplicate(true)
	entry.time = float(event.tick)/RULES.HZ
	entry.predicted_already_played = predicted_already_played
	if not actor.is_empty():
		entry.name = actor.name
		if not entry.has("team"): entry.team = actor.team
	if kind == "spawn": entry.type = "respawn"
	elif kind == "team_changed": entry.type = "team"
	elif kind == "death": entry.kind = event.cause
	elif kind == "kill_credit":
		var victim := _actor_info(event.victim_id)
		entry.type = "kill"
		entry.killer = actor.get("name","Player %d" % event.owner_id)
		entry.killer_team = actor.get("team",2)
		entry.victim = victim.get("name","Player %d" % event.victim_id)
		entry.victim_team = victim.get("team",2)
		entry.target_id = event.victim_id
		entry.part = event.cause
		entry.weapon_known = _shots.has(event.source_event_id)
		if entry.weapon_known: entry.weapon = _shots[event.source_event_id].weapon
	_append_event(entry)
	changed.emit()
	return true

func ingest_cosmetic(event: Dictionary) -> bool:
	if _owner == null or typeof(event.get("predicted")) != TYPE_BOOL or not event.predicted or event.get("epoch",0) != _owner.match_epoch or event.get("owner_id",0) != local_player_id() or event.get("spawn_generation",0) != _owner.spawn_generation or event.get("kind","") not in COSMETIC_TYPES or typeof(event.get("tick")) != TYPE_INT or event.tick < 0: return false
	match event.kind:
		"shot":
			last_shot_time = maxf(last_shot_time,float(event.tick)/RULES.HZ)
			shot_fired.emit()
		"reload_completed": reloaded.emit()
	# No grenade_thrown/exploded signal: predicted release contains no position
	# and must not instantiate the legacy authoritative LabGrenade.
	return true

func _append_event(entry: Dictionary) -> void:
	event_log.append(entry.duplicate(true))
	if event_log.size() > MAX_LOG: event_log.pop_front()
	match_event.emit(entry.duplicate(true))

func _clear_view() -> void:
	_owner = null
	profile_version = "0.75"; current_weapon = Weapon.RIFLE; current_tool = Tool.WEAPON
	displayed_tool = Tool.WEAPON; displayed_weapon = Weapon.RIFLE
	player_name = "Player"; session_time = 0; last_shot_time = -1
	magazine = 0; reserve = 0; grenades = 0; blocks = 0; health = 0; team = 2
	score = 0; player_deaths = 0; player_kills = 0
	is_reloading = false; reload_remaining = 0; fire_cooldown = 0
	grenade_cooldown = 0; block_cooldown = 0; is_cooking_grenade = false
	grenade_cook_time = 0; respawn_remaining = 0; player_position = Vector3.ZERO
	tool_raise = 0; sprint_state = 0; aim_down_state = 0; spawn_generation = 0; input_ack = 0
	confirmed_tick = -1; unlimited_ammo = false; invulnerable = false
	targets.clear(); live_grenades.clear(); ctf_bases.clear(); ctf_flags.clear(); territories.clear()
	team_scores = [0,0]; winning_team = -1

# Exhaustive LocalSession mutation overrides. Frontend scalar/dictionary writes
# affect only view copies and are overwritten by update(), never replica data.
func set_profile_version(_version: String) -> void: pass
func set_mode(_mode: String) -> void: pass
func fire() -> bool: return false
func set_trigger_held(_held: bool) -> void: pass
func end_reload() -> void: pass
func compute_damage(_part: String, _distance: float) -> float: return 0
func damage_player(_amount: float, _origin: Vector3 = Vector3.INF, _kind: String = "weapon") -> void: pass
func respawn() -> void: pass
func restock() -> void: pass
func use_block(_count: int = 1) -> bool: return false
func recover_block() -> void: pass
func begin_grenade_cook() -> bool: return false
func release_grenade() -> Dictionary: return {}
func use_grenade() -> bool: return false
func set_grenade_position(_id: int, _position: Vector3) -> void: pass
func add_target(_position: Vector3, _team: int = 1, _moving: bool = false) -> int: return -1
func remove_target(_id: int) -> void: pass
func set_target_state(_id: int, _state: String, _weapon: int = Weapon.RIFLE, _tool: int = Tool.WEAPON) -> void: pass
func damage_target(_id: int, _part: String, _distance: float) -> float: return 0
func apply_target_damage(_id: int, _amount: float, _part: String = "torso") -> float: return 0
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
