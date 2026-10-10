class_name GrenadeRules
extends RefCounted
## Grenade.cpp flight/collision/roll, GPL-3.0-or-later (yvt / Mathias Kaerlev).
## Radial damage is the documented authored offline/server policy.
const STATE = preload("res://simulation/grenade_state.gd")
const HZ: int = 60
const DT: float = 1.0 / HZ
const DAMAGE_RADIUS: float = 16.0

static func create(id: int, owner: int, generation: int, epoch: int, tick: int,
		origin: Vector3, velocity: Vector3, fuse: float, action: int = 0) -> SharedGrenadeState:
	# This is a trusted simulation call after PlayerRules releases a grenade.
	if id <= 0 or owner <= 0 or generation <= 0 or epoch <= 0 or tick < 0 or action < 0 \
			or not origin.is_finite() or not velocity.is_finite() or not is_finite(fuse) or fuse < 0 or fuse > 3:
		return null
	var result := STATE.new()
	result.grenade_id = id
	result.owner_id = owner
	result.owner_generation = generation
	result.match_epoch = epoch
	result.action_sequence = action
	result.position = origin
	result.velocity = velocity
	result.created_tick = tick
	result.last_tick = tick
	result.fuse_deadline_tick = tick + fuse * HZ
	return result

static func step_fixed(state: SharedGrenadeState, tick: int, query: Variant) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state == null or state.finished or query == null or tick != state.last_tick + 1 \
			or int(query.epoch) != state.match_epoch:
		return frozen(events)
	state.last_tick = tick
	# Upstream expires only when fuse < 0: the exact zero boundary still moves.
	if float(tick) > state.fuse_deadline_tick + .000000001:
		state.finished = true
		events.append(event(state, tick, "grenade_exploded", {"position":state.position}))
		return frozen(events)
	var previous := state.position
	state.velocity.y -= 32 * DT
	state.position += state.velocity * DT
	var roll_axis := Vector3(-state.velocity.z, 0, state.velocity.x) * (DT / .12)
	if roll_axis.length_squared() > .000001:
		state.orientation = (Quaternion(roll_axis.normalized(), roll_axis.length()) * state.orientation).normalized()
	var cell := Vector3i(state.position.floor())
	var old_cell := Vector3i(previous.floor())
	if cell.y < floori(query.water_level) and old_cell.y >= floori(query.water_level):
		events.append(event(state, tick, "grenade_water", {"position":state.position}))
	if not query.clip_world(state.position): return frozen(events)
	var audible := absf(state.velocity.x) > 3.2 or absf(state.velocity.y) > 3.2 or absf(state.velocity.z) > 3.2
	if cell.y != old_cell.y and ((cell.x == old_cell.x and cell.z == old_cell.z) \
			or not query.clip_world(Vector3(cell.x, old_cell.y, cell.z))):
		state.velocity.y = -state.velocity.y
	elif cell.x != old_cell.x and ((cell.z == old_cell.z and cell.y == old_cell.y) \
			or not query.clip_world(Vector3(old_cell.x, cell.y, cell.z))):
		state.velocity.x = -state.velocity.x
	elif cell.z != old_cell.z and ((cell.x == old_cell.x and cell.y == old_cell.y) \
			or not query.clip_world(Vector3(cell.x, cell.y, old_cell.z))):
		state.velocity.z = -state.velocity.z
	state.position = previous
	state.velocity *= .36
	if audible and previous.y > query.water_level:
		events.append(event(state, tick, "grenade_bounced", {"position":previous}))
	return frozen(events)

static func damage_at(origin: Vector3, point: Vector3, query: Variant) -> float:
	if query == null or not origin.is_finite() or not point.is_finite(): return 0
	var offset := point - origin
	var distance := offset.length()
	if distance >= DAMAGE_RADIUS: return 0
	if distance > .01:
		var cover: Dictionary = query.cast_voxel(origin, offset / distance, distance)
		if bool(cover.hit): return 0
	var factor := 1 - distance / DAMAGE_RADIUS
	return 100 * factor * factor

static func event(state: SharedGrenadeState, tick: int, kind: String, detail: Dictionary) -> Dictionary:
	state.event_sequence += 1
	var result := detail.duplicate(true)
	result.merge({"event_id":"%d:g:%d:%d" % [state.match_epoch,state.grenade_id,state.event_sequence],
		"type":kind,"epoch":state.match_epoch,"tick":tick,"grenade_id":state.grenade_id,
		"owner_id":state.owner_id,"spawn_generation":state.owner_generation,
		"action_sequence":state.action_sequence}, true)
	freeze(result)
	return result

static func freeze(value: Variant) -> void:
	if value is Dictionary:
		for item: Variant in value.values(): freeze(item)
		value.make_read_only()
	elif value is Array:
		for item: Variant in value: freeze(item)
		value.make_read_only()

static func frozen(events: Array[Dictionary]) -> Array[Dictionary]:
	freeze(events)
	return events
