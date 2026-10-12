class_name ArsenalBridge
extends RefCounted
## Narrow local authority adapter. Renderers never invoke this object.
const TERRAIN = preload("res://world/arsenal_terrain.gd")
const HITS = preload("res://gameplay/lab_hit_volumes.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const MAX_LAB_IMPULSES: int = 32
var session: LocalSession
var player: Node3D
var world: VoxelWorld
var data: VoxelData
var terrain: RefCounted
var action_sequence: int = 0
var _lab_motion: Dictionary[int, SourcePlayerMotion.State] = {}
var _lab_motion_generation: Dictionary[int,int] = {}
var _lab_health: Dictionary[Vector3i, float] = {}
var _receipts: Array[Dictionary] = []
var _watched_cells: Dictionary[Vector3i,int] = {}
var _watch_refs: Dictionary[Vector3i,int] = {}
const MAX_TERRAIN_REQUESTS: int = 64
var _reserved_removals: int = 0
var _deferred_removals: Array[Dictionary] = []
var _fatal_cells: Dictionary[Vector3i,bool] = {}
var _lab_tick: int = 0
var _lab_clock_enabled: bool = false

func configure(local_session: LocalSession, local_player: Node3D, voxel_world: VoxelWorld) -> void:
	session = local_session
	player = local_player
	world = voxel_world
	configure_data(local_session, voxel_world.data if voxel_world != null else null)

func configure_data(local_session: LocalSession, map_data: VoxelData) -> void:
	if data != null and data.cells_committed.is_connected(_on_cells_committed): data.cells_committed.disconnect(_on_cells_committed)
	if terrain != null: terrain.dispose()
	session = local_session
	data = map_data
	terrain = TERRAIN.new()
	terrain.configure(data)
	_lab_motion.clear()
	_lab_motion_generation.clear()
	_lab_health.clear()
	_receipts.clear()
	_watched_cells.clear()
	_watch_refs.clear()
	_reserved_removals = 0
	_deferred_removals.clear()
	_fatal_cells.clear()
	_lab_tick = maxi(0,map_data.last_tick) if map_data != null else 0
	_lab_clock_enabled = false
	if data != null: data.cells_committed.connect(_on_cells_committed)
	action_sequence = 0

func dispose() -> void:
	if data != null and data.cells_committed.is_connected(_on_cells_committed): data.cells_committed.disconnect(_on_cells_committed)
	if terrain != null: terrain.dispose()
	terrain = null
	data = null
	world = null
	player = null
	session = null
	_lab_motion.clear()
	_lab_motion_generation.clear()
	_lab_health.clear()
	_watched_cells.clear()
	_watch_refs.clear()
	_receipts.clear()
	_deferred_removals.clear()
	_fatal_cells.clear()

func cell_version(cell: Vector3i) -> int:
	return int(_watched_cells.get(cell,0))

func watch_cell(cell: Vector3i) -> int:
	if not _watched_cells.has(cell): _watched_cells[cell] = 0
	_watch_refs[cell] = int(_watch_refs.get(cell,0))+1
	return cell_version(cell)

func unwatch_cell(cell: Vector3i) -> void:
	var remaining: int = int(_watch_refs.get(cell,0))-1
	if remaining<=0:
		_watch_refs.erase(cell)
		_watched_cells.erase(cell)
	else: _watch_refs[cell]=remaining

func _on_cells_committed(changes: Array) -> void:
	for change: Dictionary in changes:
		if _watched_cells.has(change.cell): _watched_cells[change.cell] += 1
		_lab_health.erase(change.cell)
		_fatal_cells.erase(change.cell)

func simulation() -> MatchSimulation:
	return (session as OfflineTDMSession).simulation if session is OfflineTDMSession else null

func epoch() -> int:
	return data.epoch if data != null else 0

func tick() -> int:
	var match_state: MatchSimulation = simulation()
	if match_state != null: return maxi(0,match_state.tick)
	return _lab_tick if _lab_clock_enabled else maxi(0, roundi(session.session_time * 60.0))

func advance_lab_tick(advance: bool = true) -> bool:
	# A rendered frame may contain multiple fixed physics steps. Its session_time
	# cannot serve as their identity or slow down weapon fuses at low render FPS.
	# The host already gates loading, ordinary pause and catalogue ownership.
	# Death disables player actions, while committed terrain/foam cleanup still
	# needs distinct fixed ticks on this live map, including the respawn interval.
	if not advance or simulation()!=null or session==null or data==null or data.read_only: return false
	if not _lab_clock_enabled:
		_lab_tick = maxi(_lab_tick,maxi(data.last_tick,tick()))
		_lab_clock_enabled = true
	_lab_tick += 1
	return true

func owner_id() -> int:
	return session.local_player_id() if session != null else 0

func generation() -> int:
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var owner: SharedPlayerState = match_state.get_actor(owner_id())
		return owner.spawn_generation if owner != null else 0
	return session.player_deaths + 1 if session != null else 0

func alive() -> bool:
	if session == null or data == null: return false
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var owner: SharedPlayerState = match_state.get_actor(owner_id())
		return owner != null and owner.is_alive()
	return session.health > 0 and session.team in [0,1]

func allowed() -> bool:
	if not alive(): return false
	if session is OfflineTDMSession:
		var adapter: OfflineTDMSession = session as OfflineTDMSession
		if adapter.paused or adapter.finished: return false
	if session.has_method("get_rush_state") and bool((session.call("get_rush_state") as Dictionary).get("pending", false)): return false
	return true

func unlimited() -> bool:
	return session != null and not session is OfflineTDMSession and session.unlimited_ammo

func owner_position() -> Vector3:
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var owner: SharedPlayerState = match_state.get_actor(owner_id())
		if owner != null: return owner.feet()
	return player.global_position if is_instance_valid(player) and player.is_inside_tree() else session.player_position

func actors(include_owner: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var keys: Array = match_state.actors.keys()
		keys.sort()
		for id: int in keys:
			var actor: SharedPlayerState = match_state.get_actor(id)
			if not actor.is_alive() or (id == owner_id() and not include_owner): continue
			result.append({"id":id, "generation":actor.spawn_generation, "feet":actor.feet(),
				"position":actor.feet() + Vector3.UP * 1.25, "yaw":actor.yaw, "pitch":actor.pitch,
				"crouch":actor.motion.crouch, "team":actor.team, "alive":true, "kind":actor.registry_kind})
	else:
		for target: Dictionary in session.targets:
			if not bool(target.get("alive", false)): continue
			var feet: Vector3 = target.position
			result.append({"id":int(target.id), "generation":int(target.get("deaths",0)) + 1,
				"feet":feet, "position":feet + Vector3.UP * 1.25, "yaw":float(target.get("yaw",0)),
				"pitch":float(target.get("pitch",0)), "crouch":str(target.get("state","")) == "crouching",
				"team":int(target.get("team",1)), "alive":true, "kind":"target"})
		if include_owner and alive():
			result.append({"id":owner_id(), "generation":generation(), "feet":owner_position(),
				"position":owner_position() + Vector3.UP * 1.25, "yaw":0.0,"pitch":0.0,"crouch":false,
				"team":session.team,"alive":true,"kind":"human"})
	return result

func actor(id: int) -> Dictionary:
	for record: Dictionary in actors(true):
		if int(record.id) == id: return record
	return {}

func line_clear(from: Vector3, to: Vector3) -> bool:
	var offset: Vector3 = to - from
	return data != null and (offset.length() < .03 or not bool(data.cast_voxel(from, offset, maxf(0.0, offset.length() - .03)).hit))

func ray_world(origin: Vector3, direction: Vector3, distance: float = 48.0) -> Dictionary:
	return data.cast_voxel(origin, direction, distance) if data != null else {"hit":false,"position":origin,"cell":Vector3i.ZERO,"normal":Vector3.UP}

func ray_actor(origin: Vector3, direction: Vector3, distance: float, excluded: Array[int] = [], include_owner: bool = false) -> Dictionary:
	var result: Dictionary = {}
	var nearest: float = distance
	for record: Dictionary in actors(include_owner):
		if excluded.has(int(record.id)): continue
		var hit: Dictionary = HITS.cast_ray(origin,direction,record.feet,float(record.yaw),bool(record.crouch),float(record.pitch),distance)
		if bool(hit.hit) and float(hit.distance) < nearest:
			nearest = float(hit.distance)
			result = hit.duplicate()
			result.id = int(record.id)
			result.generation = int(record.generation)
	return result

func power_multiplier(item: String) -> float:
	if not ArsenalCatalog.get_item(item).get("power", false): return 1.0
	var match_state: MatchSimulation = simulation()
	return 1.0 + .25 * int(match_state._survival_firearm_levels.get(owner_id(), 0)) if match_state != null else 1.0

func damage(id: int, amount: float, item: String, hit_part: String = "torso") -> float:
	if not is_finite(amount) or amount <= 0.0: return 0.0
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var victim: SharedPlayerState = match_state.get_actor(id)
		if victim == null or not victim.is_alive(): return 0.0
		var before: int = victim.health
		match_state.damage_actor(id,amount,owner_id(),"arsenal", "%d:a:%d:%s" % [epoch(),action_sequence,item])
		return float(before - victim.health)
	if id == owner_id():
		var before: int = session.health
		session.damage_player(amount,owner_position(),"arsenal")
		return float(before-session.health)
	return session.apply_target_damage(id,amount,hit_part)

func impulse(id: int, velocity_mps: Vector3) -> void:
	if not velocity_mps.is_finite(): return
	var added: Vector3 = velocity_mps.limit_length(20.0) / MOTION.POSITION_SCALE
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var target: SharedPlayerState = match_state.get_actor(id)
		if target != null and target.is_alive():
			target.motion.native_velocity = (target.motion.native_velocity + added).limit_length(.75)
			if added.y > .01: target.motion.grounded = false
	elif id == owner_id() and is_instance_valid(player):
		if player.has_method("apply_arsenal_impulse"):
			player.call("apply_arsenal_impulse",velocity_mps.limit_length(20.0))
			return
		var velocity: Variant = player.get("_native_velocity")
		if velocity is Vector3: player.set("_native_velocity", (velocity + added).limit_length(.75))
	else:
		var target: Dictionary = session.get_target(id)
		if target.is_empty() or not bool(target.alive): return
		var life: int = int(target.get("deaths",0))+1
		if _lab_motion.has(id) and int(_lab_motion_generation.get(id,0))!=life: _erase_lab_motion(id)
		if not _lab_motion.has(id):
			if _lab_motion.size()>=MAX_LAB_IMPULSES: _prune_lab_motion()
			if _lab_motion.size()>=MAX_LAB_IMPULSES: return
		var motion: SourcePlayerMotion.State = _lab_motion[id] if _lab_motion.has(id) else MOTION.create_state(target.position)
		motion.native_velocity = (motion.native_velocity + added).limit_length(.75)
		_lab_motion[id] = motion
		_lab_motion_generation[id] = life

func _erase_lab_motion(id: int) -> void:
	_lab_motion.erase(id)
	_lab_motion_generation.erase(id)

func _prune_lab_motion() -> void:
	for id: int in _lab_motion.keys():
		var target: Dictionary = session.get_target(id)
		var motion: SourcePlayerMotion.State = _lab_motion[id]
		if target.is_empty() or not bool(target.alive) or int(target.get("deaths",0))+1 != int(_lab_motion_generation.get(id,0)) \
				or (motion.grounded and motion.native_velocity.length_squared()<.00001): _erase_lab_motion(id)

func velocity_mps(id: int) -> Vector3:
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var target: SharedPlayerState = match_state.get_actor(id)
		return target.motion.native_velocity*32.0 if target != null else Vector3.ZERO
	if id == owner_id() and is_instance_valid(player):
		var value: Variant = player.get("_native_velocity")
		return value*32.0 if value is Vector3 else Vector3.ZERO
	var target: Dictionary = session.get_target(id)
	return _lab_motion[id].native_velocity*32.0 if _lab_motion.has(id) and not target.is_empty() \
		and bool(target.alive) and int(target.get("deaths",0))+1==int(_lab_motion_generation.get(id,0)) else Vector3.ZERO

func push(id: int,direction: Vector3,speed: float) -> void:
	if not direction.is_finite() or direction.length_squared()<.00001 or not is_finite(speed): return
	var ray: Vector3 = direction.normalized()
	var correction: Vector3 = ray*(clampf(speed,-20.0,20.0)-velocity_mps(id).dot(ray))
	# Two bounded additions can reverse even a saturated attraction velocity.
	var first: Vector3 = correction.limit_length(20.0)
	impulse(id,first)
	impulse(id,correction-first)

func metadata() -> Dictionary:
	return {"tick":tick(), "actor_id":owner_id(), "action_id":action_sequence}

func can_reserve(count: int) -> bool:
	return terrain != null and _reserved_removals+_deferred_removals.size()+int(terrain.get_diagnostics().jobs)+count <= MAX_TERRAIN_REQUESTS

func reserve(count: int) -> bool:
	if not can_reserve(count): return false
	_reserved_removals += count
	return true

func release_reservation(count: int) -> void:
	_reserved_removals = maxi(0,_reserved_removals-count)

func cancel_reservations() -> void:
	_reserved_removals = 0

func remove(cells: Array[Vector3i],reserved: bool = false) -> Dictionary:
	if cells.size()>512: return {"ok":false,"error":"Terrain request exceeds512 cells"}
	if reserved and _reserved_removals<=0: return {"ok":false,"error":"Terrain effect has no reservation"}
	if not reserved and not can_reserve(1): return {"ok":false,"error":"Terrain request budget exhausted"}
	if reserved: release_reservation(1)
	if cells.is_empty(): return {"ok":true,"accepted":true,"changed":false}
	var request: Dictionary = {"cells":cells.duplicate(),"metadata":metadata()}
	if terrain.can_queue():
		var accepted: Dictionary = terrain.queue_remove(cells,request.metadata)
		if bool(accepted.ok): return accepted
	# The explosive effect has already committed damage exactly once. Its bounded
	# reserved crater retries admission, rather than replaying damage or vanishing.
	var guards: Dictionary = {}
	for cell: Vector3i in cells:
		if guards.has(cell): continue
		guards[cell] = {"before":data.get_block(cell),"version":watch_cell(cell)}
	request.guards = guards
	request.generation = data.generation
	request.epoch = data.epoch
	_deferred_removals.append(request)
	return {"ok":true,"accepted":true,"deferred":true}

func sphere(position: Vector3, radius: float, cap: int = 512, reserved: bool = false) -> Dictionary:
	var cells: Array[Vector3i] = []
	var center: Vector3i = Vector3i(position.floor())
	var extent: int = ceili(clampf(radius,0.0,6.0))
	for y: int in range(center.y-extent,center.y+extent+1):
		for z: int in range(center.z-extent,center.z+extent+1):
			for x: int in range(center.x-extent,center.x+extent+1):
				var cell: Vector3i = Vector3i(x,y,z)
				if y > 1 and data.is_in_bounds(cell) and data.get_block(cell) != 0 \
						and (Vector3(cell)+Vector3.ONE*.5).distance_squared_to(position) <= radius*radius: cells.append(cell)
	cells.sort_custom(func(a: Vector3i,b: Vector3i) -> bool: return (Vector3(a)+Vector3.ONE*.5).distance_squared_to(position) < (Vector3(b)+Vector3.ONE*.5).distance_squared_to(position))
	if cells.size() > cap: cells.resize(cap)
	return remove(cells,reserved)

func damage_cell(cell: Vector3i, amount: float,reserved: bool = false) -> void:
	if cell.y <= 1 or not data.is_in_bounds(cell) or data.get_block(cell) == 0 or amount <= 0.0 or _fatal_cells.has(cell):
		if reserved: release_reservation(1)
		return
	var match_state: MatchSimulation = simulation()
	if match_state != null:
		var owner: SharedPlayerState = match_state.get_actor(owner_id())
		match_state._damage_block(owner,cell,amount,false)
		if match_state.get_block_remaining_health(cell) <= 0.0:
			if remove([cell],reserved).ok: _fatal_cells[cell] = true
		elif reserved: release_reservation(1)
	else:
		var health: float = float(_lab_health.get(cell,100.0)) - amount
		_lab_health[cell] = health
		if is_instance_valid(world): world.set_block_damaged(cell,true)
		if health <= 0.0:
			if remove([cell],reserved).ok: _fatal_cells[cell] = true
		elif reserved: release_reservation(1)

func foam(point: Vector3, normal: Vector3) -> Dictionary:
	var base: Vector3i = Vector3i((point + normal*.55).floor())
	var cells: Array[Vector3i] = []
	var horizontal: Vector3i = Vector3i.RIGHT if absf(normal.z) >= absf(normal.x) else Vector3i.BACK
	for height: int in range(3):
		for side: int in range(-1,2): cells.append(base + horizontal*side + Vector3i.UP*height)
	return terrain.queue_place(cells,0x01ff93ce,tick()+720,metadata(),Callable(self,"_foam_clear"))

func _foam_clear(cell: Vector3i) -> bool:
	var box: AABB = AABB(Vector3(cell),Vector3.ONE)
	for record: Dictionary in actors(true):
		if box.intersects(AABB(record.feet-Vector3(.45,0,.45),Vector3(.9,2.7,.9))): return false
	return true

func step() -> void:
	if terrain != null:
		while not _deferred_removals.is_empty() and terrain.can_queue():
			var request: Dictionary = _deferred_removals[0]
			var guarded: Array[Vector3i] = []
			for cell: Vector3i in request.guards:
				var guard: Dictionary = request.guards[cell]
				if int(request.generation)==data.generation and int(request.epoch)==data.epoch \
						and data.get_block(cell)==int(guard.before) and cell_version(cell)==int(guard.version): guarded.append(cell)
			if guarded.is_empty():
				for cell: Vector3i in request.guards: unwatch_cell(cell)
				_deferred_removals.pop_front()
				continue
			request.metadata.tick = maxi(tick(),data.last_tick)
			var accepted: Dictionary = terrain.queue_remove(guarded,request.metadata)
			if not bool(accepted.ok): break
			for cell: Vector3i in request.guards: unwatch_cell(cell)
			_deferred_removals.pop_front()
		terrain.step(tick())
		for receipt: Dictionary in terrain.drain_transactions():
			var match_state: MatchSimulation = simulation()
			if match_state != null: match_state._commit(receipt)
			else: _receipts.append(receipt)
	if simulation() == null:
		for id: int in _lab_motion.keys():
			var target: Dictionary = session.get_target(id)
			if target.is_empty() or not bool(target.alive) or int(target.get("deaths",0))+1 != int(_lab_motion_generation.get(id,0)):
				_erase_lab_motion(id)
				continue
			var motion: SourcePlayerMotion.State = _lab_motion[id]
			motion.feet_position = target.position
			motion.native_velocity.y -= 1.0 / 60.0
			motion.native_velocity.x *= .94
			motion.native_velocity.z *= .94
			var next: SourcePlayerMotion.State = MOTION.clip_move(data,motion,1.0/60.0,float(tick())/60.0)
			var shift: Vector3 = next.feet_position - target.position
			target.position = next.feet_position
			target.spawn_position += shift
			_lab_motion[id] = next
			if next.grounded and next.native_velocity.length_squared() < .00001: _erase_lab_motion(id)

func flush_events() -> void:
	var match_state: MatchSimulation = simulation()
	if match_state == null: return
	var events: Array[Dictionary] = match_state.drain_events()
	if session.has_method("_track_survival_events"): session.call("_track_survival_events",events)
	(session as OfflineTDMSession)._ingest_events(events)
	session.update(0.0)

func drain_transactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = _receipts.duplicate()
	_receipts.clear()
	var match_state: MatchSimulation = simulation()
	if match_state != null: result.append_array(match_state.drain_transactions())
	return result

func has_pending() -> bool:
	return not _deferred_removals.is_empty() or (terrain != null and terrain.has_pending())
