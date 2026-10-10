class_name SourcePlayerMotion
extends RefCounted
## OpenSpades v0.1.3 Player.cpp:991–1093,1213–1248. GPL-3.0-or-later.
## Original algorithm copyright (c) 2013 yvt, based on pysnip code
## copyright (c) 2011–2012 Mathias Kaerlev. See the repository LICENSE.
## This module clips already-integrated velocity; acceleration/gravity/friction
## remain with the caller. All public points and vectors use Godot axes.
## The world query may be VoxelData or its VoxelWorld presentation wrapper:
## dimensions, get_block(cell), water_level and wade_origin_level are required.

const POSITION_SCALE: float = 32.0
const HALF_WIDTH: float = 0.45
const STANDING_EYE_HEIGHT: float = 2.25
const CROUCH_EYE_HEIGHT: float = 1.35
const CROUCH_SHIFT: float = 0.9
const CLIMB_EYE_SECONDS: float = 0.25
const NATIVE_MAP_TOP: float = 64.0
const FALL_SLOW_DOWN: float = 0.24
const FALL_HURT_SPEED: float = 0.58

class State extends RefCounted:
	var feet_position: Vector3 = Vector3.ZERO
	## Native magnitude, Godot axes: world displacement = this * 32 * dt.
	var native_velocity: Vector3 = Vector3.ZERO
	var crouch: bool = false
	var sprint: bool = false
	var front: Vector3 = Vector3.FORWARD
	var grounded: bool = true
	## Physical friction flag. Retained during flight, as in Player::BoxClipMove.
	var wading: bool = false
	## Smoothed rendering eye; physics_eye() is the unsmoothed collision point.
	var eye_position: Vector3 = Vector3.ZERO
	var last_climb_time: float = -100.0
	var climbed: bool = false
	var vertical_collision: bool = false
	var landed: bool = false
	var fall_hurt: bool = false
	var fall_speed: float = 0.0

	func physics_eye() -> Vector3:
		return feet_position + Vector3.UP * (CROUCH_EYE_HEIGHT if crouch else STANDING_EYE_HEIGHT)

	func copy() -> State:
		var result := State.new()
		result.feet_position = feet_position
		result.native_velocity = native_velocity
		result.crouch = crouch
		result.sprint = sprint
		result.front = front
		result.grounded = grounded
		result.wading = wading
		result.eye_position = eye_position
		result.last_climb_time = last_climb_time
		result.climbed = climbed
		result.vertical_collision = vertical_collision
		result.landed = landed
		result.fall_hurt = fall_hurt
		result.fall_speed = fall_speed
		return result

static func create_state(feet: Vector3, crouched: bool = false, grounded: bool = true) -> State:
	var result := State.new()
	result.feet_position = feet
	result.crouch = crouched
	result.grounded = grounded
	result.eye_position = result.physics_eye()
	return result

static func _f32(value: float) -> float:
	# Native uses float, whereas GDScript scalar float uses double. Vector3
	# components in the standard/web engine round to the same binary32 format.
	return Vector3(value, 0.0, 0.0).x

static func _to_native_point(point: Vector3) -> Vector3:
	return Vector3(point.x, point.z, NATIVE_MAP_TOP - point.y)

static func _from_native_point(point: Vector3) -> Vector3:
	return Vector3(point.x, NATIVE_MAP_TOP - point.z, point.y)

static func _native_clip_box(world: Variant, point: Vector3) -> bool:
	# GameMap.cpp:162–175,195–199: floor native coordinates BEFORE reflection.
	# Native z=63 aliases z=62; z>=64 is solid. The authored lab may extend
	# above native z=0, so its actual dimensions determine the empty sky.
	var cell := Vector3i(floori(point.x), 63 - floori(point.z), floori(point.y))
	if cell.x < 0 or cell.z < 0 or cell.x >= world.dimensions.x or cell.z >= world.dimensions.z:
		return true
	if cell.y < 0:
		return true
	if cell.y >= world.dimensions.y:
		return false
	if cell.y == 0:
		cell.y = 1
	return world.get_block(cell) != 0

static func source_clip_box(world: Variant, point: Vector3) -> bool:
	return _native_clip_box(world, _to_native_point(point))

static func _horizontal_clear(world: Variant, x: float, y: float, z: float, native_x: bool, low: float, limit: float) -> bool:
	var sample: float = _f32(low)
	while sample >= _f32(limit):
		var probe_height: float = _f32(z + sample)
		if native_x:
			if _native_clip_box(world, Vector3(x, _f32(y-_f32(HALF_WIDTH)), probe_height)) \
				or _native_clip_box(world, Vector3(x, _f32(y+_f32(HALF_WIDTH)), probe_height)):
				return false
		elif _native_clip_box(world, Vector3(_f32(x-_f32(HALF_WIDTH)), y, probe_height)) \
			or _native_clip_box(world, Vector3(_f32(x+_f32(HALF_WIDTH)), y, probe_height)):
			return false
		sample = _f32(sample - _f32(CROUCH_SHIFT))
	return true

static func _four_corners_blocked(world: Variant, x: float, y: float, z: float) -> bool:
	var half_width: float = _f32(HALF_WIDTH)
	return _native_clip_box(world, Vector3(_f32(x-half_width), _f32(y-half_width), z)) \
		or _native_clip_box(world, Vector3(_f32(x-half_width), _f32(y+half_width), z)) \
		or _native_clip_box(world, Vector3(_f32(x+half_width), _f32(y-half_width), z)) \
		or _native_clip_box(world, Vector3(_f32(x+half_width), _f32(y+half_width), z))

static func clip_move(world: Variant, state: State, delta: float, time: float) -> State:
	var result: State = state.copy()
	result.climbed = false
	result.vertical_collision = false
	result.landed = false
	result.fall_hurt = false
	result.fall_speed = 0.0
	var position: Vector3 = _to_native_point(state.physics_eye())
	var velocity := Vector3(state.native_velocity.x, state.native_velocity.z, -state.native_velocity.y)
	var tick: float = _f32(delta)
	var scale: float = _f32(tick * POSITION_SCALE)
	var nx: float = _f32(_f32(scale * velocity.x) + position.x)
	var ny: float = _f32(_f32(scale * velocity.y) + position.y)
	var offset: float = _f32(0.45 if state.crouch else 0.9)
	var m: float = _f32(0.9 if state.crouch else 1.35)
	var nz: float = _f32(position.z + offset)
	var leading: float = _f32(-HALF_WIDTH if velocity.x < 0.0 else HALF_WIDTH)
	var can_climb: bool = not state.crouch and -state.front.y < 0.5 and not state.sprint
	if _horizontal_clear(world, _f32(nx+leading), position.y, nz, true, m, -1.36):
		position.x = nx
	elif can_climb and _horizontal_clear(world, _f32(nx+leading), position.y, nz, true, 0.35, -2.36):
		position.x = nx
		result.climbed = true
	else:
		velocity.x = 0.0
	leading = _f32(-HALF_WIDTH if velocity.y < 0.0 else HALF_WIDTH)
	# Native updates X before probing Y. A failed Y probe after X climbed
	# retains Y velocity; that asymmetric branch is intentional source behavior.
	if _horizontal_clear(world, position.x, _f32(ny+leading), nz, false, m, -1.36):
		position.y = ny
	elif can_climb and not result.climbed and _horizontal_clear(world, position.x, _f32(ny+leading), nz, false, 0.35, -2.36):
		position.y = ny
		result.climbed = true
	elif not result.climbed:
		velocity.y = 0.0
	if result.climbed:
		velocity.x *= 0.5
		velocity.y *= 0.5
		result.last_climb_time = _f32(time)
		nz = _f32(nz - 1.0)
		m = _f32(-1.35)
	else:
		if velocity.z < 0.0:
			m = -m
		nz = _f32(nz + _f32(_f32(velocity.z * tick) * POSITION_SCALE))
	result.grounded = false
	result.vertical_collision = _four_corners_blocked(world, position.x, position.y, _f32(nz+m))
	if result.vertical_collision:
		if velocity.z >= 0.0:
			# Native checks the old physics eye, before any vertical reposition.
			result.wading = position.z > _f32(NATIVE_MAP_TOP - world.water_level - 2.0)
			result.grounded = true
		velocity.z = 0.0
	else:
		position.z = _f32(nz - offset)
	result.native_velocity = Vector3(velocity.x, -velocity.z, velocity.y)
	result.feet_position = _from_native_point(position) - Vector3.UP * (CROUCH_EYE_HEIGHT if result.crouch else STANDING_EYE_HEIGHT)
	return reposition(result, time)

static func reposition(state: State, time: float) -> State:
	var result: State = state.copy()
	result.eye_position = result.physics_eye()
	var native_f: float = _f32(result.last_climb_time - _f32(time))
	if native_f > -CLIMB_EYE_SECONDS:
		result.eye_position.y -= _f32(_f32(native_f + CLIMB_EYE_SECONDS) / CLIMB_EYE_SECONDS)
	return result

static func try_uncrouch(world: Variant, state: State, move: bool = false) -> Dictionary:
	var result: State = state.copy()
	var position: Vector3 = _to_native_point(state.physics_eye())
	if not state.grounded and not _four_corners_blocked(world, position.x, position.y, _f32(position.z + STANDING_EYE_HEIGHT)):
		return {"allowed": true, "lower_feet": true, "state": result}
	if not _four_corners_blocked(world, position.x, position.y, _f32(position.z - CROUCH_EYE_HEIGHT)):
		if move:
			result.feet_position.y += CROUCH_SHIFT
			result.eye_position.y += CROUCH_SHIFT
		return {"allowed": true, "lower_feet": false, "state": result}
	return {"allowed": false, "lower_feet": false, "state": result}

static func set_crouch(world: Variant, state: State, wanted: bool) -> State:
	# Client_Update.cpp:408–414 checks TryUncrouch(false), then SetInput.
	# SetInput does not perform the optional TryUncrouch(true) position shift.
	var result: State = state.copy()
	if wanted == state.crouch:
		return result
	if not wanted and not bool(try_uncrouch(world, state).allowed):
		return result
	if not state.grounded:
		result.feet_position.y += CROUCH_SHIFT if wanted else -CROUCH_SHIFT
	result.crouch = wanted
	return result

static func get_origin(state: State) -> Vector3:
	return state.eye_position - Vector3.UP * ((0.45 if state.crouch else 0.9) + 0.3)

static func get_wade(world: Variant, state: State) -> bool:
	# Presentation GetWade is distinct from the physical wading friction flag.
	return get_origin(state).y < world.wade_origin_level

static func is_on_ground_or_wade(state: State) -> bool:
	return state.grounded and -state.native_velocity.y >= 0.0 and -state.native_velocity.y < 0.017

static func finish_landing(state: State, incoming_down_speed: float) -> State:
	# Player.cpp:1169–1188. No HP authority is encoded by the native client.
	var result: State = state.copy()
	result.fall_speed = _f32(incoming_down_speed)
	result.landed = result.native_velocity.y == 0.0 and result.fall_speed > _f32(FALL_SLOW_DOWN)
	result.fall_hurt = result.landed and result.fall_speed > _f32(FALL_HURT_SPEED)
	if result.landed:
		result.native_velocity.x *= 0.5
		result.native_velocity.z *= 0.5
	return result
