class_name MatchSimulation
extends RefCounted
## Shared authority coordinator. Server scheduling/transport are external.
const PLAYER = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const HITS = preload("res://gameplay/lab_hit_volumes.gd")
const GRENADES = preload("res://simulation/grenade_rules.gd")
const OBJECTIVES = preload("res://simulation/match_objectives.gd")
const HISTORY = preload("res://network/hit_history.gd")
const MAX_ACTORS := 32
const MAX_SHOT_PELLETS := 8
const MAX_GRENADES := 256 # At least five live short-cooked grenades per actor.
const MAX_EVENTS := 2048
const MAX_STEP_EVENTS := 16384
const MAX_TRANSACTIONS := 256
const MAX_TRANSACTION_CHANGES := 32768
const NEIGHBORS: Array[Vector3i] = [Vector3i.DOWN,Vector3i.UP,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]
const NO_CELL := Vector3i(-1,-1,-1)
var data: VoxelData
var actors: Dictionary[int,SharedPlayerState] = {}
var tick: int = -1
var epoch: int = 1
var profile: String = "0.75"
var mode: String = "sandbox"
var friendly_fire: bool = true # Authored offline-compatible damage policy.
var objectives: MatchObjectives
var grenades: Dictionary[int,SharedGrenadeState] = {}
var event_sequence: int = 0 # Global, distinct from per-actor ordinals.
var resync_required: bool = false
var last_error: String = ""
var _next_actor_id: int = 1
var _issued_actor_ids: Dictionary[int,bool] = {} # Includes removed actors for this epoch.
var _next_grenade_id: int = 1
var _events: Array[Dictionary] = []
var _transactions: Array[Dictionary] = []
var _transaction_changes: int = 0
var _events_overflow: bool = false
var _colors: Dictionary[int,int] = {}
var _line_start: Dictionary[int,Vector3i] = {}
var _pending_cell: Dictionary[int,Vector3i] = {}
var _secondary: Dictionary[int,bool] = {}
var _block_health: Dictionary[Vector3i,Dictionary] = {}
var _grenade_team: Dictionary[int,int] = {}
var _rewind_query_factory: Callable
var _rewind_enabled: bool = false
var _rewind_stats: Dictionary = {}

func set_rewind_query_factory(factory: Callable) -> void:
	# Trusted coordinator only. An empty factory keeps the offline rules intact.
	_rewind_query_factory = factory
	_rewind_enabled = not factory.is_null()
	_reset_rewind_stats()

func _reset_rewind_stats() -> void:
	_rewind_stats = {"planned_shots":0,"denied_shots":0,"denied_pellets":0,
		"applied_player_hits":0,"blocked_generation_hits":0,"blocked_ineligible_hits":0,
		"blocked_color_hits":0,"last_reason":"","denials":{}}

func get_rewind_stats() -> Dictionary:
	if _rewind_stats.is_empty(): _reset_rewind_stats()
	var result := _rewind_stats.duplicate(true)
	result.enabled = _rewind_enabled
	return result

func _rewind_count(key: String, amount: int = 1) -> void:
	if _rewind_stats.is_empty(): _reset_rewind_stats()
	_rewind_stats[key] = mini(RULES.MAX_UINT32,int(_rewind_stats[key])+amount)

func _rewind_denial(reason: String, shot: Dictionary) -> Dictionary:
	_rewind_count("denied_shots")
	_rewind_count("denied_pellets",mini(MAX_SHOT_PELLETS,shot.directions.size()))
	_rewind_stats.last_reason = reason
	# Reasons are fixed strings below; external errors never grow this registry.
	var denials: Dictionary = _rewind_stats.denials
	denials[reason] = mini(RULES.MAX_UINT32,int(denials.get(reason,0))+1)
	return {"ok":false,"shot":shot,"pellets":[]}

func configure(map_data: VoxelData, match_profile: String = "0.75", game_mode: String = "sandbox") -> Dictionary:
	if map_data == null or map_data.read_only or map_data.blocks.size() != map_data.dimensions.x*map_data.dimensions.y*map_data.dimensions.z \
			or map_data.epoch <= 0 or map_data.epoch > RULES.MAX_UINT32 or map_data.last_tick > 0 \
			or not PROFILES.valid(match_profile) or game_mode not in ["sandbox","ctf","tc"]:
		return _result(false,"invalid writable map/profile/mode")
	if data != null and map_data.epoch == epoch and (tick >= 0 or not actors.is_empty()):
		return _result(false,"reconfiguration requires a new epoch")
	# Validate all new-match policy before changing the running registry.
	var probe := MatchSimulation.new()
	probe.data = map_data
	var bases: Array[Vector3] = []
	for team in range(2): bases.append(probe._find_spawn(team))
	if not bases[0].is_finite() or not bases[1].is_finite(): return _result(false,"map has no safe team spawn")
	var territories: Array[Vector3] = []
	for fraction in [.25,.5,.75]:
		var point := probe._find_spawn(0,Vector2(map_data.dimensions.x*fraction,map_data.dimensions.z*.5))
		if point.is_finite(): territories.append(point)
	var new_objectives := OBJECTIVES.new()
	if not new_objectives.configure(map_data.epoch,game_mode,bases,territories): return _result(false,"objective configuration failed")
	data = map_data
	epoch = data.epoch
	profile = match_profile
	mode = game_mode
	tick = -1
	event_sequence = 0
	actors.clear()
	grenades.clear()
	_next_actor_id = 1
	_issued_actor_ids.clear()
	_next_grenade_id = 1
	_events.clear()
	_transactions.clear()
	_transaction_changes = 0
	_events_overflow = false
	resync_required = false
	_colors.clear()
	_line_start.clear()
	_pending_cell.clear()
	_secondary.clear()
	_block_health.clear()
	_grenade_team.clear()
	_reset_rewind_stats()
	objectives = new_objectives
	return _result(true)

func add_actor(player_name: String, team: int = 2, seed_value: int = 1,
		initial_feet: Vector3 = Vector3.INF, actor_id: int = 0) -> Dictionary:
	if data == null or data.read_only or data.epoch != epoch or actors.size() >= MAX_ACTORS or team not in [0,1,2] \
			or actor_id < 0 or actor_id > RULES.MAX_UINT32 or _next_tick() > RULES.MAX_UINT32 \
			or player_name.is_empty() or player_name.to_utf8_buffer().size() > 64:
		return _result(false,"invalid actor/admission limit")
	var id := actor_id if actor_id > 0 else _next_actor_id
	if id <= 0 or id > RULES.MAX_UINT32 or actors.has(id) or _issued_actor_ids.has(id):
		return _result(false,"actor ID exhausted or already issued")
	for character in player_name:
		var code: int = character.unicode_at(0)
		if code < 32 or code in range(127,160): return _result(false,"invalid actor name")
	var point := initial_feet
	if point == Vector3.INF:
		point = _find_spawn(team) if team < 2 else Vector3.INF
	elif not _spawn_clear(point): return _result(false,"invalid initial actor position")
	if team < 2 and not point.is_finite(): return _result(false,"no unoccupied spawn")
	var actor := PLAYER.new(id,player_name,epoch,profile,seed_value)
	actor.spawn_generation = 1 # Valid inactive spectator in wire snapshots.
	actor.last_tick = tick
	if team == 2 and point.is_finite(): actor.motion = MOTION.create_state(point)
	actors[id] = actor
	_colors[id] = 0x01a0a0a0
	_secondary[id] = false
	var events: Array[Dictionary] = [RULES.event(actor,_next_tick(),"actor_joined")]
	_record_events(events)
	if team < 2:
		var spawned := spawn_actor(id,team,-1,point)
		if not spawned.ok:
			actors.erase(id)
			_colors.erase(id)
			_secondary.erase(id)
			return spawned
	_issued_actor_ids[id] = true
	# GDScript int is signed64, so U32_MAX+1 is an exhaustion sentinel rather
	# than wrapping to actor0. Trusted unused lower gaps remain admissible.
	_next_actor_id = maxi(_next_actor_id,id+1)
	var result := _result(true)
	result.actor_id = id
	return result

func get_actor(id: int) -> SharedPlayerState:
	return actors.get(id,null)

func spawn_actor(id: int, team: int, weapon: int = -1, feet: Vector3 = Vector3.INF) -> Dictionary:
	var actor := get_actor(id)
	var now := _next_tick()
	if actor == null or not actor.connected or team not in [0,1] or actor.is_alive() \
			or (actor.respawn_tick >= 0 and now < actor.respawn_tick): return _result(false,"actor not eligible to spawn")
	var selected := actor.pending_weapon if weapon < 0 and actor.pending_weapon >= 0 else (actor.weapon if weapon < 0 else weapon)
	var point := _find_spawn(team) if feet == Vector3.INF else feet
	if not PROFILES.valid(profile,selected) or not _spawn_clear(point): return _result(false,"invalid spawn/class")
	var events := RULES.spawn(actor,now,point,team,weapon)
	if events.is_empty(): return _result(false,"spawn rejected")
	_clear_build(id)
	_record_events(events)
	var result := _result(true)
	result.events = events
	return result

func set_team(id: int, team: int) -> Dictionary:
	var actor := get_actor(id)
	if actor == null or team not in [0,1,2]: return _result(false,"invalid actor/team")
	var events: Array[Dictionary] = []
	if actor.team != team:
		if actor.is_alive(): events.append_array(_damage(actor,100,0,"team_change","",2))
		events.append_array(objectives.drop_actor(actor,_next_tick()))
		actor.team = team
		if team == 2: actor.health = 0
		RULES.cancel_actions(actor)
		clear_controls(id)
		_clear_build(id)
		events.append(RULES.event(actor,_next_tick(),"team_changed",{"team":team}))
	_record_events(events)
	var result := _result(true)
	result.events = RULES.frozen(events)
	return result

func clear_controls(id: int) -> bool:
	var actor := get_actor(id)
	if actor == null: return false
	actor.input_move = Vector2.ZERO
	actor.input_buttons = 0
	return true # Cook/previous input edge survive until the next fixed step.

func disconnect_actor(id: int) -> Dictionary:
	var actor := get_actor(id)
	if actor == null: return _result(false,"unknown actor")
	var events: Array[Dictionary] = []
	if actor.connected:
		events.append_array(RULES.release_grenade(actor,_next_tick(),true))
		events.append_array(objectives.drop_actor(actor,_next_tick()))
		actor.connected = false
		clear_controls(id)
		RULES.cancel_actions(actor)
		_clear_build(id)
		events.append(RULES.event(actor,_next_tick(),"actor_disconnected"))
		_process_releases(events)
	_record_events(events)
	var result := _result(true)
	result.events = RULES.frozen(events)
	return result

func reconnect_actor(id: int) -> Dictionary:
	var actor := get_actor(id)
	if actor == null: return _result(false,"unknown actor")
	var events: Array[Dictionary] = []
	if not actor.connected:
		actor.connected = true
		clear_controls(id)
		actor.last_tick = tick
		events.append(RULES.event(actor,_next_tick(),"actor_reconnected"))
	_record_events(events)
	var result := _result(true)
	result.events = RULES.frozen(events)
	return result

func remove_actor(id: int) -> Dictionary:
	var actor := get_actor(id)
	if actor == null: return _result(false,"unknown actor")
	var events: Array[Dictionary] = []
	events.append_array(disconnect_actor(id).events)
	events.append(RULES.event(actor,_next_tick(),"actor_removed"))
	actors.erase(id)
	_colors.erase(id)
	_clear_build(id)
	_secondary.erase(id)
	_record_events([events[-1]])
	var result := _result(true)
	result.events = RULES.frozen(events)
	return result

func set_block_color(id: int, packed_rgb: int) -> bool:
	if not actors.has(id) or packed_rgb < 0 or packed_rgb > 0x01ffffff: return false
	_colors[id] = (packed_rgb & 0xffffff)|0x01000000
	return true

func step_fixed(commands: Dictionary = {}, admitted_shot_ticks: Dictionary = {}) -> Array[Dictionary]:
	var current: Array[Dictionary] = []
	if data == null or data.epoch != epoch or tick >= RULES.MAX_UINT32 or data.read_only: return RULES.frozen(current)
	tick += 1
	_restore_block_health()
	var ordered := _ordered()
	var block_gates: Dictionary[int,bool] = {}
	var shot_fronts: Dictionary[int,Vector3] = {}
	for actor: SharedPlayerState in ordered:
		var displayed := actor.displayed_tool
		var desired := actor.tool
		var raise := actor.tool_raise
		var sprint := actor.sprint_state
		var supplied: Variant = commands.get(actor.player_id,null)
		var input: PlayerRules.Command = supplied if supplied is PlayerRules.Command else null
		# Every live cook reserves its eventual projectile. This server policy
		# bounds even rapid disconnect/rejoin churn without consuming a grenade
		# whose authoritative projectile would have to be discarded.
		if actor.tool == RULES.Tool.GRENADE and not actor.cooking and not _cook_capacity():
			actor.input_buttons &= ~RULES.Buttons.PRIMARY
			if input != null:
				var bounded := RULES.Command.new()
				bounded.sequence=input.sequence
				bounded.spawn_generation=input.spawn_generation
				bounded.buttons=input.buttons & ~RULES.Buttons.PRIMARY
				bounded.move=input.move
				bounded.yaw=input.yaw
				bounded.pitch=input.pitch
				bounded.tool=input.tool
				bounded.weapon=input.weapon
				input=bounded
		# fire() applies recoil to the actor after producing its rays. Preserve
		# the accepted pre-fire aim for the historical .01 muzzle offset.
		var shot_front := actor.front()
		if input != null and input.valid() and input.spawn_generation == actor.spawn_generation and input.sequence > actor.consumed_input_sequence:
			shot_front = Vector3(-sin(input.yaw)*cos(input.pitch),sin(input.pitch),-cos(input.yaw)*cos(input.pitch))
		shot_fronts[actor.player_id] = shot_front
		var actor_events := RULES.step_fixed(actor,tick,input,data)
		current.append_array(actor_events)
		_process_releases(actor_events)
		block_gates[actor.player_id] = RULES.can_act(actor) and not actor.sprinting and sprint <= 0 \
			and raise >= .999 and displayed == actor.tool and desired == actor.tool
	# Every shot sees all actors after the same fixed movement step.
	var intents := current.duplicate()
	var shot_plans: Dictionary[int,Dictionary] = {}
	if _rewind_enabled:
		var shot_count := 0
		# Resolve ALL same-time historical rays before any intent can damage an
		# actor or change terrain. The query's borrowed live identity then ends.
		for index: int in range(intents.size()):
			var intent: Dictionary = intents[index]
			if intent.type != "shot": continue
			var owner := get_actor(intent.owner_id)
			if owner == null: continue
			shot_count += 1
			var plan := _rewind_denial("step_shot_limit",intent) if shot_count > MAX_ACTORS else _plan_rewound_shot(owner,intent,admitted_shot_ticks.get(owner.player_id),shot_fronts[owner.player_id])
			shot_plans[index] = plan
			# Replace our event copy, never the frozen Rules event/caller data.
			current[index] = plan.shot
			intents[index] = plan.shot
	for index: int in range(intents.size()):
		var intent: Dictionary = intents[index]
		var actor := get_actor(intent.owner_id)
		if actor == null: continue
		match String(intent.type):
			"shot": current.append_array(_commit_rewound_shot(actor,shot_plans[index]) if shot_plans.has(index) else _resolve_shot(actor,intent))
			"spade_bash": current.append_array(_resolve_spade(actor,false,intent.event_id))
			"spade_dig": current.append_array(_resolve_spade(actor,true,intent.event_id))
			"death": current.append_array(objectives.drop_actor(actor,tick))
	for actor: SharedPlayerState in ordered:
		if actor.tool != RULES.Tool.BLOCK or not RULES.can_act(actor):
			_clear_build(actor.player_id)
		else: current.append_array(_step_build(actor,bool(block_gates[actor.player_id])))
	_process_releases(current)
	var grenade_ids := grenades.keys()
	grenade_ids.sort()
	for id: int in grenade_ids:
		var projectile: SharedGrenadeState = grenades[id]
		var flight := GRENADES.step_fixed(projectile,tick,data)
		current.append_array(flight)
		for event: Dictionary in flight:
			if event.type == "grenade_exploded": current.append_array(_explode(projectile,event))
		if projectile.finished:
			grenades.erase(id)
			_grenade_team.erase(id)
	# Death drops during explosions create projectiles for the next step.
	_process_releases(current)
	current.append_array(objectives.step_fixed(tick,ordered))
	if current.size() > MAX_STEP_EVENTS:
		current.resize(MAX_STEP_EVENTS-1)
		current.append(_system_event("events_resync_required",{"resync_required":true}))
	_record_events(current)
	return RULES.frozen(current)

func damage_actor(id: int, amount: float, attacker_id: int = 0, cause: String = "weapon", action_id: String = "") -> Array[Dictionary]:
	var actor := get_actor(id)
	if actor == null: return RULES.frozen([])
	var attacker := get_actor(attacker_id)
	var events := _damage(actor,amount,attacker_id,cause,action_id,attacker.team if attacker != null else 2)
	_process_releases(events)
	_record_events(events)
	return RULES.frozen(events)

func _damage(victim: SharedPlayerState, amount: float, attacker_id: int, cause: String, action_id: String, attacker_team: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not friendly_fire and attacker_id != victim.player_id and attacker_team == victim.team: return events
	events.append_array(RULES.damage(victim,amount,maxi(0,tick),attacker_id,cause,action_id))
	if not events_of(events,"death").is_empty():
		events.append_array(objectives.drop_actor(victim,maxi(0,tick)))
		_clear_build(victim.player_id)
		var killer := get_actor(attacker_id)
		if killer != null and killer.player_id != victim.player_id and attacker_team in [0,1] and attacker_team != victim.team:
			killer.kills += 1
			killer.score += 1
			events.append(RULES.event(killer,maxi(0,tick),"kill_credit",{"victim_id":victim.player_id,"victim_generation":victim.spawn_generation,"cause":cause,"source_event_id":action_id}))
	return events

static func events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.type == type: result.append(event)
	return result

static func source_weapon_hit(origin: Vector3, map_hit: Dictionary, player_hit: Dictionary) -> String:
	var map_distance := horizontal_distance(origin,map_hit.get("position",origin))
	var player_distance := horizontal_distance(origin,player_hit.get("position",origin))
	if bool(map_hit.get("hit",false)) and map_distance < 128 and (player_hit.is_empty() or map_distance < player_distance): return "map"
	if not player_hit.is_empty() and player_distance < 128: return "player"
	return "none"

static func horizontal_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func raycast_actors(owner_id: int, origin: Vector3, direction: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var closest := INF
	for target: SharedPlayerState in _ordered():
		if target.player_id == owner_id or not RULES.can_act(target): continue
		var hit := HITS.cast_ray(origin,direction,target.feet(),target.yaw,target.motion.crouch,target.pitch,500)
		if hit.hit:
			var distance := horizontal_distance(origin,hit.position)
			if distance < closest:
				closest = distance
				result = hit
				result.actor_id = target.player_id
	return result

static func _valid_rewind_pose(pose: Dictionary) -> bool:
	for key: String in ["id","epoch","spawn_generation","team"]:
		if typeof(pose.get(key)) != TYPE_INT: return false
	for key: String in ["alive","connected","pose_valid","crouch"]:
		if typeof(pose.get(key)) != TYPE_BOOL: return false
	for key: String in ["physics_eye","feet"]:
		if typeof(pose.get(key)) != TYPE_VECTOR3 or not pose[key].is_finite(): return false
	return pose.id > 0 and pose.id <= RULES.MAX_UINT32 and pose.spawn_generation > 0 and pose.spawn_generation <= RULES.MAX_UINT32 \
		and pose.team in [0,1,2] and typeof(pose.get("yaw")) == TYPE_FLOAT and is_finite(pose.yaw) and absf(pose.yaw) <= PI+.000001 \
		and typeof(pose.get("pitch")) == TYPE_FLOAT and is_finite(pose.pitch) and absf(pose.pitch) <= PI*.5+.000001

func _failed_rewind_query(query: HISTORY.HistoricalVoxelQuery, reason: String, shot: Dictionary) -> Dictionary:
	query.cancel()
	RULES.freeze_value(shot)
	return _rewind_denial(reason,shot)

func _plan_rewound_shot(owner: SharedPlayerState, source: Dictionary, admitted_tick: Variant, front: Vector3) -> Dictionary:
	var shot := source.duplicate(true)
	if typeof(admitted_tick) != TYPE_INT or admitted_tick < 0 or admitted_tick > tick-1:
		RULES.freeze_value(shot)
		return _rewind_denial("missing_or_future_admitted_tick",shot)
	if shot.directions.is_empty() or shot.directions.size() > MAX_SHOT_PELLETS:
		RULES.freeze_value(shot)
		return _rewind_denial("pellet_limit",shot)
	if not _rewind_query_factory.is_valid():
		RULES.freeze_value(shot)
		return _rewind_denial("history_unavailable",shot)
	var resolved: Variant = _rewind_query_factory.call(admitted_tick,tick-1)
	if typeof(resolved) != TYPE_DICTIONARY or not bool(resolved.get("ok",false)):
		RULES.freeze_value(shot)
		return _rewind_denial("history_unavailable",shot)
	var supplied_query: Variant = resolved.get("query")
	if not supplied_query is HISTORY.HistoricalVoxelQuery:
		RULES.freeze_value(shot)
		return _rewind_denial("invalid_history_query",shot)
	var query: HISTORY.HistoricalVoxelQuery = supplied_query
	if resolved.get("tick") != admitted_tick or resolved.get("map_sequence") != query.map_sequence or query.last_tick != admitted_tick \
			or query.epoch != epoch or query._live != data or not query.is_valid() or typeof(resolved.get("actors")) != TYPE_ARRAY or resolved.actors.size() > MAX_ACTORS:
		return _failed_rewind_query(query,"invalid_or_stale_history",shot)
	var poses: Array = resolved.actors
	var shooter: Dictionary = {}
	var previous_id := 0
	for value: Variant in poses:
		if typeof(value) != TYPE_DICTIONARY or not _valid_rewind_pose(value) or value.epoch != epoch or value.id <= previous_id:
			return _failed_rewind_query(query,"invalid_history_pose",shot)
		previous_id = value.id
		if value.id == owner.player_id: shooter = value
	if shooter.is_empty() or not shooter.alive or not shooter.connected or not shooter.pose_valid \
			or shooter.spawn_generation != shot.spawn_generation or owner.spawn_generation != shot.spawn_generation or owner.match_epoch != epoch:
		return _failed_rewind_query(query,"historical_shooter_ineligible",shot)
	shot.origin = shooter.physics_eye + front*.01
	# All poses have passed the closed-history/life checks above. Prepare each
	# target once for this shot, then reuse its exact source matrices for every
	# pellet. Nothing is cached across ticks, leases or authority mutations.
	var targets: Array[Dictionary] = []
	for pose: Dictionary in poses:
		if pose.id == owner.player_id or not pose.alive or not pose.connected or not pose.pose_valid: continue
		targets.append({"id":pose.id,"spawn_generation":pose.spawn_generation,
			"volumes":HITS.prepare_pose(pose.feet,pose.yaw,pose.crouch,pose.pitch)})
	var pellets: Array[Dictionary] = []
	for direction: Vector3 in shot.directions:
		var map_hit: Dictionary = query.cast_voxel(shot.origin,direction,500)
		if not bool(map_hit.get("valid",false)): return _failed_rewind_query(query,"invalid_or_stale_history",shot)
		var hit := _raycast_rewound_actors(shot.origin,direction,targets)
		var chosen := source_weapon_hit(shot.origin,map_hit,hit)
		var pellet := {"chosen":chosen,"position":shot.origin+direction*128}
		if chosen == "player":
			pellet.merge({"position":hit.position,"actor_id":hit.actor_id,"spawn_generation":hit.spawn_generation,"part":hit.part},true)
		elif chosen == "map":
			pellet.merge({"position":map_hit.position,"cell":map_hit.cell,"normal":map_hit.normal,"color":query.get_block(map_hit.cell)},true)
		pellets.append(pellet)
	# Queries borrow live storage: no reference may survive planning into damage.
	if not query.is_valid(): return _failed_rewind_query(query,"invalid_or_stale_history",shot)
	query.cancel()
	RULES.freeze_value(shot)
	RULES.freeze_value(pellets)
	_rewind_count("planned_shots")
	return {"ok":true,"shot":shot,"pellets":pellets}

static func _raycast_rewound_actors(origin: Vector3, direction: Vector3, targets: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	var closest := INF
	for pose: Dictionary in targets:
		var hit := HITS.cast_prepared(origin,direction,pose.volumes,500)
		if hit.hit:
			var distance := horizontal_distance(origin,hit.position)
			if distance < closest:
				closest = distance
				result = hit
				result.actor_id = pose.id
				result.spawn_generation = pose.spawn_generation
	return result

func _commit_rewound_shot(owner: SharedPlayerState, plan: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var shot: Dictionary = plan.shot
	var destroyed := false
	for index: int in range(mini(MAX_SHOT_PELLETS,shot.directions.size())):
		var direction: Vector3 = shot.directions[index]
		var endpoint: Vector3 = shot.origin+direction*128
		if plan.ok:
			var pellet: Dictionary = plan.pellets[index]
			endpoint = pellet.position
			if pellet.chosen == "player":
				var victim := get_actor(pellet.actor_id)
				if victim == null or not RULES.can_act(victim):
					_rewind_count("blocked_ineligible_hits")
				elif victim.match_epoch != epoch or victim.spawn_generation != pellet.spawn_generation:
					_rewind_count("blocked_generation_hits")
				else:
					var amount := PROFILES.damage(profile,int(shot.weapon),pellet.part,horizontal_distance(shot.origin,pellet.position))
					var damage_events := _damage(victim,amount,owner.player_id,"weapon",shot.event_id,owner.team)
					events.append_array(damage_events)
					if not damage_events.is_empty():
						_rewind_count("applied_player_hits")
						events.append(RULES.event(owner,tick,"hit_confirmed",{"victim_id":victim.player_id,"part":pellet.part,"damage":damage_events[0].amount,"position":pellet.position,"friendly":owner.team==victim.team,"source_event_id":shot.event_id,"pellet":index}))
			elif pellet.chosen == "map":
				if data.get_block(pellet.cell) != pellet.color:
					_rewind_count("blocked_color_hits")
				else:
					if _damage_block(owner,pellet.cell,PROFILES.get_info(profile,int(shot.weapon)).block,not destroyed): destroyed = true
					events.append(RULES.event(owner,tick,"block_hit",{"cell":pellet.cell,"position":pellet.position,"normal":pellet.normal,"source_event_id":shot.event_id,"pellet":index}))
		events.append(RULES.event(owner,tick,"tracer",{"origin":shot.origin,"position":endpoint,"weapon":shot.weapon,"source_event_id":shot.event_id,"pellet":index}))
	return events

func _resolve_shot(owner: SharedPlayerState, shot: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var destroyed := false
	var pellet := 0
	for direction: Vector3 in shot.directions:
		var map_hit: Dictionary = data.cast_voxel(shot.origin,direction,500)
		var hit := raycast_actors(owner.player_id,shot.origin,direction)
		var chosen := source_weapon_hit(shot.origin,map_hit,hit)
		var endpoint: Vector3 = shot.origin+direction*128
		if chosen == "player":
			endpoint=hit.position
			var victim := get_actor(hit.actor_id)
			var amount := PROFILES.damage(profile,int(shot.weapon),hit.part,horizontal_distance(shot.origin,hit.position))
			var damage_events := _damage(victim,amount,owner.player_id,"weapon",shot.event_id,owner.team)
			events.append_array(damage_events)
			if not damage_events.is_empty(): events.append(RULES.event(owner,tick,"hit_confirmed",{"victim_id":victim.player_id,"part":hit.part,"damage":damage_events[0].amount,"position":hit.position,"friendly":owner.team==victim.team,"source_event_id":shot.event_id,"pellet":pellet}))
		elif chosen == "map":
			endpoint=map_hit.position
			if _damage_block(owner,map_hit.cell,PROFILES.get_info(profile,int(shot.weapon)).block,not destroyed): destroyed = true
			events.append(RULES.event(owner,tick,"block_hit",{"cell":map_hit.cell,"position":map_hit.position,"normal":map_hit.normal,"source_event_id":shot.event_id,"pellet":pellet}))
		events.append(RULES.event(owner,tick,"tracer",{"origin":shot.origin,"position":endpoint,"weapon":shot.weapon,"source_event_id":shot.event_id,"pellet":pellet}))
		pellet += 1
	return events

func find_melee_target(owner_id: int, origin: Vector3, front: Vector3, right: Vector3, up: Vector3) -> int:
	for target: SharedPlayerState in _ordered():
		if target.player_id == owner_id or not RULES.can_act(target): continue
		var diff := target.motion.physics_eye()-origin
		if maxf(absf(diff.x),maxf(absf(diff.y),absf(diff.z))) >= 3: continue
		var projected := diff.dot(front)
		if projected <= 0: continue
		if maxf(absf(diff.dot(right)/projected),absf(diff.dot(up)/projected)) >= 5: continue
		if (diff-front*projected).length_squared() < 64: return target.player_id
	return -1

func _resolve_spade(owner: SharedPlayerState, dig: bool, source_event_id: String = "") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not RULES.can_act(owner): return events
	var origin := owner.motion.physics_eye()
	var front := owner.front()
	var right := Vector3(cos(owner.yaw),0,-sin(owner.yaw))
	if source_event_id.is_empty(): source_event_id="%d:%d:melee:%d" % [epoch,owner.player_id,tick]
	if not dig:
		var victim_id := find_melee_target(owner.player_id,origin,front,right,right.cross(front))
		if victim_id > 0:
			var victim := get_actor(victim_id)
			var damage_events := _damage(victim,100,owner.player_id,"melee",source_event_id,owner.team)
			events.append_array(damage_events)
			if not damage_events.is_empty(): events.append(RULES.event(owner,tick,"hit_confirmed",{"victim_id":victim.player_id,"part":"melee","damage":damage_events[0].amount,"position":victim.motion.physics_eye(),"friendly":owner.team==victim.team,"source_event_id":source_event_id}))
			return events # Source player priority, even behind nearby terrain.
	var hit: Dictionary = data.cast_voxel(origin,front,256)
	if not hit.hit or not in_reach(owner,hit.cell+hit.normal) or hit.cell.y <= 1:
		events.append(RULES.event(owner,tick,"spade_miss",{"source_event_id":source_event_id}))
		return events
	if dig:
		_commit(data.remove_blocks([hit.cell+Vector3i.DOWN,hit.cell,hit.cell+Vector3i.UP],true,_metadata(owner)))
	elif _damage_block(owner,hit.cell,55): events.append_array(RULES.recover_block(owner,tick))
	events.append(RULES.event(owner,tick,"spade_block_hit",{"cell":hit.cell,"position":hit.position,"normal":hit.normal,"dig":dig,"source_event_id":source_event_id}))
	return events

func _damage_block(owner: SharedPlayerState, cell: Vector3i, damage: float, allow_destroy: bool = true) -> bool:
	var color := data.get_block(cell)
	if cell.y <= 1 or color == 0: return false
	var prior: Dictionary = _block_health.get(cell,{"health":100.0,"color":color})
	var health := (float(prior.health) if int(prior.color) == color else 100.0)-damage
	if health <= 0 and allow_destroy:
		var transaction: Dictionary = data.set_block(cell,0,_metadata(owner))
		_commit(transaction)
		return bool(transaction.get("changed",false))
	_block_health[cell] = {"health":maxf(0,health),"tick":tick,"color":color}
	return false

func _restore_block_health() -> void:
	for cell: Vector3i in _block_health.keys():
		var state: Dictionary = _block_health[cell]
		if tick > int(state.tick)+600 or data.get_block(cell) != int(state.color): _block_health.erase(cell)

static func in_reach(actor: SharedPlayerState, cell: Vector3i) -> bool:
	var delta := (Vector3(cell)+Vector3.ONE*.5-actor.motion.physics_eye()).abs()
	return maxf(delta.x,maxf(delta.y,delta.z)) < 3

static func overlaps_actor(actor: SharedPlayerState, cell: Vector3i) -> bool:
	var height := .85 if actor.motion.crouch else 1.75
	var eye := actor.motion.physics_eye()
	return AABB(Vector3(cell),Vector3.ONE).intersects(AABB(eye-Vector3(.45,height,.45),Vector3(.9,height,.9)))

func _overlaps_any(cell: Vector3i) -> bool:
	for actor: SharedPlayerState in actors.values():
		if RULES.can_act(actor) and overlaps_actor(actor,cell): return true
	return false

func _supported(cell: Vector3i) -> bool:
	for direction: Vector3i in NEIGHBORS:
		var neighbor := cell+direction
		neighbor.x = posmod(neighbor.x,data.dimensions.x)
		neighbor.z = posmod(neighbor.z,data.dimensions.z)
		if data.get_block(neighbor) != 0: return true
	return false

func cube_line(start: Vector3i,end: Vector3i,limit: int = 256) -> Array[Vector3i]:
	var difference := end-start
	var dominant := maxi(absi(difference.x),maxi(absi(difference.y),absi(difference.z)))
	var increment := Vector3i.ZERO
	var crossing := Vector3i.ZERO
	var step := Vector3i(1 if difference.x >= 0 else -1,1 if difference.y >= 0 else -1,1 if difference.z >= 0 else -1)
	for axis in range(3):
		increment[axis] = int(float(dominant*1024)/absi(difference[axis])) if difference[axis] != 0 else 0x3fffffff
		var source_step := -step[axis] if axis == 1 else step[axis]
		crossing[axis] = increment[axis]-int(increment[axis]/2) if source_step > 0 else int(increment[axis]/2)
	var cells: Array[Vector3i] = []
	var cell := start
	while cells.size() < clampi(limit,0,256) and data.is_in_bounds(cell):
		cells.append(cell)
		if cell == end: break
		var axis := 1 if crossing.y <= crossing.x and crossing.y <= crossing.z else (0 if crossing.x < crossing.z else 2)
		cell[axis] += step[axis]
		crossing[axis] += increment[axis]
	return cells

func _build_endpoint(actor: SharedPlayerState) -> Vector3i:
	var hit: Dictionary = data.cast_voxel(actor.motion.physics_eye(),actor.front(),12)
	if not hit.hit: return NO_CELL
	var cell: Vector3i = hit.cell+hit.normal
	if not data.is_in_bounds(cell) or cell.y <= 1 or not in_reach(actor,cell): return NO_CELL
	return cell

func _step_build(actor: SharedPlayerState, allowed: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var id := actor.player_id
	var pending: Vector3i = _pending_cell.get(id,NO_CELL)
	if pending != NO_CELL:
		if actor.motion.grounded or actor.blocks <= 0: _pending_cell.erase(id)
		elif allowed and in_reach(actor,pending) and not _overlaps_any(pending):
			events.append_array(_place_cells(actor,[pending],false))
			_pending_cell.erase(id)
	var start: Vector3i = _line_start.get(id,NO_CELL)
	if start != NO_CELL and not _supported(start):
		_line_start.erase(id)
		start = NO_CELL
		events.append(RULES.event(actor,tick,"build_error",{"reason":"line has no support"}))
	var secondary := allowed and actor.input_buttons & RULES.Buttons.SECONDARY != 0
	var was_secondary := bool(_secondary.get(id,false))
	var endpoint := _build_endpoint(actor)
	if secondary and not was_secondary and tick >= actor.block_deadline_tick:
		if endpoint != NO_CELL and not _overlaps_any(endpoint) and data.get_block(endpoint) == 0: _line_start[id] = endpoint
		else: events.append(RULES.event(actor,tick,"build_error",{"reason":"invalid line start"}))
	elif not secondary and was_secondary and start != NO_CELL:
		if allowed and endpoint != NO_CELL: events.append_array(_place_cells(actor,cube_line(start,endpoint),true))
		_line_start.erase(id)
	_secondary[id] = secondary
	if allowed and not secondary and actor.input_buttons & RULES.Buttons.PRIMARY != 0 and tick >= actor.block_deadline_tick:
		if endpoint != NO_CELL:
			if _overlaps_any(endpoint):
				if not actor.motion.grounded and overlaps_actor(actor,endpoint): _pending_cell[id] = endpoint
			else: events.append_array(_place_cells(actor,[endpoint],false))
	return events

func _place_cells(actor: SharedPlayerState, cells: Array[Vector3i], line: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if cells.is_empty() or cells.size() > actor.blocks or cells.size() > 50 or not RULES.can_use_tool(actor) \
			or actor.tool != RULES.Tool.BLOCK or tick < actor.block_deadline_tick: return events
	if not _supported(cells[0]): return events # Revalidate delayed single support too.
	var empty := 0
	for cell: Vector3i in cells:
		if not data.is_in_bounds(cell) or cell.y <= 1 or _overlaps_any(cell) or (not line and data.get_block(cell) != 0):
			events.append(RULES.event(actor,tick,"build_error",{"reason":"invalid placement"}))
			return events
		if data.get_block(cell) == 0: empty += 1
	if data.map_sequence+empty > RULES.MAX_UINT32 or tick < data.last_tick: return events
	for cell: Vector3i in cells:
		if data.get_block(cell) == 0: _commit(data.set_block(cell,_colors[actor.player_id],_metadata(actor)))
	events.append_array(RULES.use_blocks(actor,tick,cells.size())) # Source charges occupied line cells too.
	events.append(RULES.event(actor,tick,"blocks_built",{"cells":cells,"line":line,"color":_colors[actor.player_id]}))
	return events

func _process_releases(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		if event.type != "grenade_thrown": continue
		# A release is already immutable and may occur twice in processing phases.
		var exists := false
		for state: SharedGrenadeState in grenades.values():
			if state.owner_id == int(event.owner_id) and state.owner_generation == int(event.spawn_generation) \
				and state.created_tick == int(event.tick) and state.action_sequence == int(event.cook_action_sequence): exists = true; break
		if exists: continue
		if grenades.size() >= MAX_GRENADES:
			resync_required = true
			last_error = "grenade capacity exhausted"
			continue
		var state := GRENADES.create(_next_grenade_id,event.owner_id,event.spawn_generation,epoch,event.tick,event.position,event.native_velocity*32,event.fuse,event.cook_action_sequence)
		if state == null: continue
		grenades[_next_grenade_id] = state
		_grenade_team[_next_grenade_id] = int(event.team)
		_next_grenade_id += 1

func _cook_capacity() -> bool:
	var reserved := grenades.size()
	for actor: SharedPlayerState in actors.values():
		if actor.cooking: reserved += 1
	return reserved < MAX_GRENADES

func _explode(state: SharedGrenadeState, explosion: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var team := int(_grenade_team.get(state.grenade_id,2))
	# Cover is tested before removing explosion terrain, as offline authority.
	for victim: SharedPlayerState in _ordered():
		if not RULES.can_act(victim): continue
		var amount := GRENADES.damage_at(state.position,victim.feet()+Vector3.UP*.9,data)
		if amount > 0: events.append_array(_damage(victim,amount,state.owner_id,"grenade",explosion.event_id,team))
	_commit(data.explode(state.position,{"tick":tick,"actor_id":state.owner_id,"action_id":state.action_sequence}))
	return events

func _metadata(actor: SharedPlayerState) -> Dictionary:
	return {"tick":maxi(0,tick),"actor_id":actor.player_id,"action_id":actor.consumed_input_sequence}

func _commit(transaction: Dictionary) -> void:
	if not bool(transaction.get("ok",false)):
		last_error = "map transaction rejected"
		resync_required = true
		return
	if not bool(transaction.changed): return
	for change: Dictionary in transaction.changes: _block_health.erase(change.cell)
	if resync_required: return
	if _transactions.size() >= MAX_TRANSACTIONS or _transaction_changes+transaction.changes.size() > MAX_TRANSACTION_CHANGES:
		_transactions.clear()
		_transaction_changes = 0
		resync_required = true
		return
	var copy := transaction.duplicate(true)
	RULES.freeze_value(copy)
	_transactions.append(copy)
	_transaction_changes += transaction.changes.size()

func drain_transactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if resync_required:
		result.append({"ok":false,"type":"map_resync_required","resync_required":true,"epoch":epoch,"tick":maxi(0,tick),"map_sequence":data.map_sequence if data != null else 0})
	else: result = _transactions.duplicate()
	_transactions.clear()
	_transaction_changes = 0
	RULES.freeze_value(result)
	return result

func acknowledge_map_resync() -> bool:
	# Trusted runtime: invalidate old streams/start fresh immutable baselines
	# before this call. Draining the marker alone is not an acknowledgement.
	var required := resync_required
	_transactions.clear()
	_transaction_changes = 0
	resync_required = false
	return required

func _record_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		event_sequence += 1
		if _events.size() >= MAX_EVENTS:
			_events.clear()
			_events_overflow = true
		if not _events_overflow:
			var recorded := event.duplicate(true)
			recorded.match_sequence = event_sequence
			RULES.freeze_value(recorded)
			_events.append(recorded)

func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _events_overflow: result.append(_system_event("events_resync_required",{"resync_required":true,"event_sequence":event_sequence,"match_sequence":event_sequence}))
	else: result = _events.duplicate()
	_events.clear()
	_events_overflow = false
	RULES.freeze_value(result)
	return result

func snapshot_for(id: int) -> Dictionary:
	if data == null or not actors.has(id): return {}
	var copied: Array[SharedPlayerState] = []
	for actor: SharedPlayerState in _ordered(): copied.append(actor.copy())
	var projectiles: Array[SharedGrenadeState] = []
	var ids := grenades.keys()
	ids.sort()
	for grenade_id: int in ids: projectiles.append(grenades[grenade_id].copy())
	# Copied objects are owned by the caller; this is NOT a wire serializer.
	return {"epoch":epoch,"tick":maxi(0,tick),"profile":profile,"mode":mode,"owner_id":id,"owner_state":actors[id].copy(),"actors":copied,"grenades":projectiles,"grenade_teams":_grenade_team.duplicate(),"objectives":objectives.snapshot(),"map_sequence":data.map_sequence,"dimensions":data.dimensions,"event_sequence":event_sequence,"block_health":_block_health.duplicate(true),"block_colors":_colors.duplicate(),"line_start":_line_start.duplicate(),"pending_cell":_pending_cell.duplicate(),"secondary":_secondary.duplicate()}

func _system_event(type: String, details: Dictionary = {}) -> Dictionary:
	var event := details.duplicate(true)
	event.merge({"type":type,"owner_id":0,"spawn_generation":0,"epoch":epoch,"tick":maxi(0,tick),"event_id":"%d:m:%d" % [epoch,event_sequence]},true)
	RULES.freeze_value(event)
	return event

func _ordered() -> Array[SharedPlayerState]:
	var result: Array[SharedPlayerState] = []
	var ids := actors.keys()
	ids.sort()
	for id: int in ids: result.append(actors[id])
	return result

func _clear_build(id: int) -> void:
	_line_start.erase(id)
	_pending_cell.erase(id)
	_secondary[id] = false

func _spawn_clear(feet: Vector3) -> bool:
	if data == null or not feet.is_finite() or feet.x < .45 or feet.z < .45 or feet.x+.45 >= data.dimensions.x \
			or feet.z+.45 >= data.dimensions.z or feet.y < 2 or feet.y > data.dimensions.y+3: return false
	for y in [0.01,.9,1.8,2.7]:
		for x in [-.45,.45]:
			for z in [-.45,.45]:
				if MOTION.source_clip_box(data,feet+Vector3(x,y,z)): return false
	var spawn_box := AABB(feet-Vector3(.45,0,.45),Vector3(.9,2.7,.9))
	for actor: SharedPlayerState in actors.values():
		if not RULES.can_act(actor): continue
		var height := 1.8 if actor.motion.crouch else 2.7
		if spawn_box.intersects(AABB(actor.feet()-Vector3(.45,0,.45),Vector3(.9,height,.9))): return false
	return true

func _find_spawn(team: int, center: Vector2 = Vector2.INF) -> Vector3:
	if data == null: return Vector3.INF
	if center == Vector2.INF: center = Vector2(data.dimensions.x*(1.0/6 if team == 0 else 5.0/6),data.dimensions.z*.5)
	for radius in range(17):
		for dz in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				if radius > 0 and absi(dx) != radius and absi(dz) != radius: continue
				var x := clampi(floori(center.x)+dx,1,data.dimensions.x-2)
				var z := clampi(floori(center.y)+dz,1,data.dimensions.z-2)
				for y in range(data.dimensions.y-1,0,-1):
					if data.get_block(Vector3i(x,y,z)) == 0: continue
					var feet := Vector3(x+.5,y+1.01,z+.5)
					if _spawn_clear(feet): return feet
	return Vector3.INF

func _next_tick() -> int:
	return maxi(0,tick+1)

func _result(ok: bool,error: String = "") -> Dictionary:
	last_error = error
	return {"ok":ok,"error":error}
