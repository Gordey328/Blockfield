class_name ClientPrediction
extends RefCounted
## Pure client simulation. Trusted owner snapshots enter through an owned copy;
## commands contain intent only. No transport, presentation or world mutation.

const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const DATA = preload("res://world/voxel_data.gd")
const MAX_HISTORY := 256
const MAX_UINT32 := 0xffffffff
const CORRECTION_SECONDS := 0.08
const SNAP_DISTANCE := 3.0
const PRIVATE_COSMETIC_SEED := 0x42504644
var _state: STATE
var _confirmed: STATE
var _history: Array[Dictionary] = []
var _map_sequence := 0
var _last_server_tick := -1
var _last_ack := 0
var _last_submitted := 0
var _needs_rebase := false
var _map_sync := false
var _reason := "not initialized"
var _position_correction := Vector3.ZERO
var _yaw_correction := 0.0
var _pitch_correction := 0.0

static func _u32(value: int, positive: bool = false) -> bool:
	return value >= (1 if positive else 0) and value <= MAX_UINT32

static func _result(ok: bool, error: String = "", events: Array = []) -> Dictionary:
	return {"ok":ok, "error":error, "events":events}

static func _owner_error(owner: STATE, tick: int) -> String:
	if owner == null or owner.motion == null or not _u32(tick) or owner.last_tick != tick:
		return "invalid owner snapshot tick"
	if not _u32(owner.player_id, true) or not _u32(owner.match_epoch, true) or not _u32(owner.spawn_generation) or not _u32(owner.consumed_input_sequence):
		return "invalid owner snapshot identity"
	if not PROFILES.valid(owner.profile, owner.weapon) or owner.team not in [0,1,2] or owner.tool not in [0,1,2,3] or owner.displayed_tool not in [0,1,2,3]:
		return "invalid owner replay profile/tool"
	if not owner.motion.feet_position.is_finite() or not owner.motion.native_velocity.is_finite() or not owner.motion.eye_position.is_finite() or not owner.motion.front.is_finite():
		return "nonfinite owner motion"
	if not is_finite(owner.motion.last_climb_time) or not is_finite(owner.motion.fall_speed):
		return "nonfinite owner motion timer"
	for property: Dictionary in owner.get_script().get_script_property_list():
		var value: Variant = owner.get(property.name)
		if typeof(value) == TYPE_FLOAT and not is_finite(value):
			return "nonfinite owner replay field"
	if absf(owner.yaw) > PI + 0.000001 or absf(owner.pitch) > PI * 0.5 + 0.000001 or not owner.input_move.is_finite() or owner.input_move.length_squared() > 1.000001:
		return "invalid owner input pose"
	return ""

static func _owned_copy(source: STATE) -> STATE:
	# Do not copy/retain the server's pellet RNG seed/state, even transiently.
	var value := STATE.new(source.player_id, source.player_name, source.match_epoch, source.profile, PRIVATE_COSMETIC_SEED)
	for property: Dictionary in source.get_script().get_script_property_list():
		var key: String = property.name
		if key not in ["motion", "shot_rng"]:
			value.set(key, source.get(key))
	value.motion = source.motion.copy()
	return value

static func _copy_command(source: RULES.Command) -> RULES.Command:
	var value := RULES.Command.new()
	value.sequence = source.sequence
	value.spawn_generation = source.spawn_generation
	value.buttons = source.buttons
	value.move = source.move
	value.yaw = source.yaw
	value.pitch = source.pitch
	value.tool = source.tool
	value.weapon = source.weapon
	return value

static func _preserve_authority(predicted: STATE, confirmed: STATE) -> void:
	predicted.health = confirmed.health
	predicted.kills = confirmed.kills
	predicted.deaths = confirmed.deaths
	predicted.score = confirmed.score
	predicted.event_sequence = confirmed.event_sequence
	predicted.death_tick = confirmed.death_tick
	predicted.respawn_tick = confirmed.respawn_tick

func _sync_failure(message: String, map_required: bool) -> Dictionary:
	_reason = message
	_map_sync = map_required
	_needs_rebase = not map_required
	return _result(false, message)

func _map_error(query: DATA, epoch: int, sequence: int) -> String:
	if query == null or not DATA.valid_dimensions(query.dimensions) or query.blocks.size() != query.dimensions.x * query.dimensions.y * query.dimensions.z:
		return "confirmed terrain unavailable"
	if query.epoch != epoch or query.map_sequence != sequence:
		return "confirmed terrain sequence/epoch unavailable"
	return ""

func reset(owner: STATE, server_tick: int, map_sequence: int) -> Dictionary:
	var error := _owner_error(owner, server_tick)
	if not error.is_empty() or not _u32(map_sequence):
		return _result(false, error if not error.is_empty() else "invalid map sequence")
	_state = _owned_copy(owner)
	_confirmed = _owned_copy(owner)
	_map_sequence = map_sequence
	_last_server_tick = server_tick
	_last_ack = owner.consumed_input_sequence
	_last_submitted = _last_ack
	_history.clear()
	_needs_rebase = false
	_map_sync = false
	_reason = ""
	_position_correction = Vector3.ZERO
	_yaw_correction = 0.0
	_pitch_correction = 0.0
	return _result(true)

func predict(command: RULES.Command, query: DATA) -> Dictionary:
	if _state == null:
		return _result(false, "not initialized")
	if _needs_rebase or _map_sync:
		return _result(false, _reason)
	var error := _map_error(query, _state.match_epoch, _map_sequence)
	if not error.is_empty():
		return _sync_failure(error, true)
	if command == null or not command.valid() or command.spawn_generation != _state.spawn_generation or command.sequence != _last_submitted + 1:
		return _result(false, "invalid/gapped prediction command")
	if _history.size() >= MAX_HISTORY or _state.last_tick >= MAX_UINT32:
		return _sync_failure("prediction history/tick exhausted; input rebase required", false)
	var owned := _copy_command(command)
	var tick := _state.last_tick + 1
	var events := RULES.step_fixed(_state, tick, owned, query, null, false)
	_preserve_authority(_state, _confirmed)
	_history.append({"command":owned, "tick":tick, "map_sequence":_map_sequence})
	_last_submitted = owned.sequence
	return _result(true, "", _cosmetic_events(events))

func reconcile(owner: STATE, server_tick: int, map_sequence: int, query: DATA) -> Dictionary:
	var error := _owner_error(owner, server_tick)
	if not error.is_empty() or not _u32(map_sequence):
		return _result(false, error if not error.is_empty() else "invalid map sequence")
	if _state != null:
		if owner.player_id != _state.player_id:
			return _result(false, "owner identity changed; explicit reset required")
		if owner.match_epoch < _state.match_epoch or (owner.match_epoch == _state.match_epoch and owner.spawn_generation < _state.spawn_generation):
			return _result(false, "stale owner epoch/generation")
		if owner.match_epoch == _state.match_epoch and owner.spawn_generation == _state.spawn_generation and (server_tick <= _last_server_tick or owner.consumed_input_sequence < _last_ack):
			return _result(false, "stale owner tick/input acknowledgement")
	error = _map_error(query, owner.match_epoch, map_sequence)
	if not error.is_empty():
		return _sync_failure(error, true)
	if _state == null:
		return reset(owner, server_tick, map_sequence)
	if owner.match_epoch != _state.match_epoch or owner.spawn_generation != _state.spawn_generation or owner.team != _confirmed.team or owner.weapon != _confirmed.weapon or owner.profile != _confirmed.profile or owner.is_alive() != _confirmed.is_alive() or owner.connected != _confirmed.connected:
		return reset(owner, server_tick, map_sequence)
	if owner.consumed_input_sequence > _last_submitted:
		return _sync_failure("input acknowledgement outside retained window", false)
	var pending: Array[Dictionary] = []
	var expected := owner.consumed_input_sequence + 1
	for entry: Dictionary in _history:
		var command: RULES.Command = entry.command
		if command.sequence <= owner.consumed_input_sequence:
			continue
		if command.sequence != expected:
			return _sync_failure("input history gap; input rebase required", false)
		if entry.map_sequence != map_sequence:
			return _sync_failure("historical terrain unavailable; input rebase required", false)
		pending.append(entry)
		expected += 1
	if server_tick + pending.size() > MAX_UINT32:
		return _sync_failure("prediction tick rebase required", false)
	var old_feet := _state.feet() + _position_correction
	var old_yaw := _state.yaw + _yaw_correction
	var old_pitch := _state.pitch + _pitch_correction
	var replay := _owned_copy(owner)
	var next_tick := server_tick
	for entry: Dictionary in pending:
		next_tick += 1
		RULES.step_fixed(replay, next_tick, entry.command, query, null, false)
		_preserve_authority(replay, owner)
		entry.tick = next_tick
	_state = replay
	_confirmed = _owned_copy(owner)
	_history = pending
	_map_sequence = map_sequence
	_last_server_tick = server_tick
	_last_ack = owner.consumed_input_sequence
	_needs_rebase = false
	_map_sync = false
	_reason = ""
	_position_correction = old_feet - _state.feet()
	_yaw_correction = wrapf(old_yaw - _state.yaw, -PI, PI)
	_pitch_correction = old_pitch - _state.pitch
	if _position_correction.length() > SNAP_DISTANCE:
		_position_correction = Vector3.ZERO
		_yaw_correction = 0.0
		_pitch_correction = 0.0
	# No events escape replay. Live predicted effects retain their original keys.
	var result := _result(true)
	result["replayed"] = pending.size()
	return result

func _cosmetic_events(events: Array[Dictionary]) -> Array:
	var result: Array = []
	for event: Dictionary in events:
		var kind: String = event.type
		if kind not in ["shot","dry_fire","reload_started","reload_cancelled","shell_loaded","reload_completed","tool_selected","class_pending","grenade_pin","grenade_thrown","spade_bash","spade_dig","jump","land","footstep"]:
			continue
		var cosmetic := {"kind":"grenade_release" if kind == "grenade_thrown" else kind,
			"predicted":true, "owner_id":event.owner_id, "spawn_generation":event.spawn_generation,
			"epoch":event.epoch, "input_sequence":event.action_sequence, "tick":event.tick,
			"effect_key":"%d:%d:%d:%d:%s:%d" % [event.epoch,event.owner_id,event.spawn_generation,event.action_sequence,kind,event.tick]}
		if kind == "shot":
			cosmetic.weapon = event.weapon
			cosmetic.profile = event.profile
			cosmetic.recoil_direction = event.recoil_direction
		if kind in ["tool_selected","class_pending","reload_started"]:
			for key: String in ["tool","weapon"]:
				if event.has(key): cosmetic[key] = event[key]
		if kind == "footstep": cosmetic.wade = event.wade
		if kind == "land": cosmetic.fall_warning = event.hurt
		cosmetic.make_read_only()
		result.append(cosmetic)
	result.make_read_only()
	return result

func get_state() -> STATE:
	return _owned_copy(_state) if _state != null else null

func get_confirmed_state() -> STATE:
	return _owned_copy(_confirmed) if _confirmed != null else null

func get_pending_commands() -> Array[RULES.Command]:
	var result: Array[RULES.Command] = []
	for entry: Dictionary in _history:
		result.append(_copy_command(entry.command))
	return result

func sample_local_presentation(delta: float = 0.0) -> Dictionary:
	if _state == null or not is_finite(delta) or delta < 0.0:
		return {}
	var decay := exp(-delta / CORRECTION_SECONDS)
	_position_correction *= decay
	_yaw_correction *= decay
	_pitch_correction *= decay
	return {"feet":_state.feet() + _position_correction, "eye":_state.motion.eye_position + _position_correction,
		"yaw":wrapf(_state.yaw + _yaw_correction,-PI,PI), "pitch":clampf(_state.pitch + _pitch_correction,-PI*0.5,PI*0.5)}

func get_status() -> Dictionary:
	return {"ready":_state != null, "needs_rebase":_needs_rebase, "map_sync":_map_sync, "reason":_reason,
		"pending":_history.size(), "history_limit":MAX_HISTORY, "input_ack":_last_ack,
		"last_submitted":_last_submitted, "server_tick":_last_server_tick, "map_sequence":_map_sequence,
		"predicted_tick":_state.last_tick if _state != null else -1, "correction":_position_correction,
		"epoch":_state.match_epoch if _state != null else 0, "spawn_generation":_state.spawn_generation if _state != null else 0}

class RemotePoseBuffer extends RefCounted:
	const CAPACITY := 32
	const MAX_EXTRAPOLATION_TICKS := 6.0 # Source velocity units *32; 100ms at60Hz.
	var _poses: Array[Dictionary] = []
	var _actor_id := 0
	var _epoch := 0
	var _generation := 0
	var _delay_ticks := 6.0

	static func _u32(value: int, positive: bool = false) -> bool:
		return value >= (1 if positive else 0) and value <= MAX_UINT32

	func clear() -> void:
		_poses.clear()
		_actor_id = 0
		_epoch = 0
		_generation = 0

	func set_delay_seconds(seconds: float) -> float:
		if is_finite(seconds): _delay_ticks = clampf(seconds,0,0.25) * RULES.HZ
		return _delay_ticks / RULES.HZ

	func push(pose: Dictionary, epoch: int, tick: int) -> Dictionary:
		for key: String in ["id","spawn_generation","team","flags","tool","weapon"]:
			if typeof(pose.get(key)) != TYPE_INT: return {"ok":false,"error":"invalid remote identity fields"}
		if not _u32(epoch,true) or not _u32(tick) or not _u32(pose.id,true) or not _u32(pose.spawn_generation,true) or pose.team not in [0,1,2] or pose.tool not in [0,1,2,3] or pose.weapon not in [0,1,2] or pose.flags < 0 or pose.flags & ~255 != 0:
			return {"ok":false,"error":"invalid remote identity/flags"}
		for key: String in ["feet","native_velocity"]:
			if typeof(pose.get(key)) != TYPE_VECTOR3 or not pose[key].is_finite(): return {"ok":false,"error":"nonfinite remote vector"}
		for key: String in ["yaw","pitch"]:
			if typeof(pose.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(pose[key]): return {"ok":false,"error":"nonfinite remote angle"}
		if absf(pose.yaw) > PI + 0.000001 or absf(pose.pitch) > PI * 0.5 + 0.000001:
			return {"ok":false,"error":"invalid remote angle range"}
		if _actor_id != 0 and pose.id != _actor_id: return {"ok":false,"error":"wrong remote actor"}
		if epoch < _epoch or (epoch == _epoch and pose.spawn_generation < _generation): return {"ok":false,"error":"stale remote epoch/generation"}
		if epoch != _epoch or pose.spawn_generation != _generation:
			_poses.clear()
		elif not _poses.is_empty() and tick <= _poses.back().tick:
			return {"ok":false,"error":"stale remote tick"}
		_actor_id = pose.id
		_epoch = epoch
		_generation = pose.spawn_generation
		# Only public value fields retained. Ignore private owner/RNG/extensions.
		var owned := {"id":pose.id,"spawn_generation":pose.spawn_generation,"epoch":epoch,"tick":tick,
			"team":pose.team,"flags":pose.flags,"tool":pose.tool,"weapon":pose.weapon,
			"feet":pose.feet,"native_velocity":pose.native_velocity,"yaw":float(pose.yaw),"pitch":float(pose.pitch)}
		if typeof(pose.get("name")) == TYPE_STRING: owned.name = pose.name
		_poses.append(owned)
		if _poses.size() > CAPACITY: _poses.pop_front()
		return {"ok":true,"error":""}

	func sample(estimated_server_tick: float) -> Dictionary:
		if _poses.is_empty() or not is_finite(estimated_server_tick): return {}
		var target := estimated_server_tick - _delay_ticks
		if target <= _poses[0].tick:
			var first: Dictionary = _poses[0].duplicate(true)
			first["mode"] = "oldest"
			first["poor_connection"] = false
			return first
		for i: int in range(1,_poses.size()):
			var previous: Dictionary = _poses[i-1]
			var current: Dictionary = _poses[i]
			if target < current.tick:
				var amount: float = (target - previous.tick) / float(current.tick - previous.tick)
				var interpolated: Dictionary = previous.duplicate(true)
				interpolated.feet = previous.feet.lerp(current.feet,amount)
				interpolated.native_velocity = previous.native_velocity.lerp(current.native_velocity,amount)
				interpolated.yaw = wrapf(previous.yaw + wrapf(current.yaw - previous.yaw,-PI,PI) * amount,-PI,PI)
				interpolated.pitch = clampf(previous.pitch + wrapf(current.pitch - previous.pitch,-PI,PI) * amount,-PI*0.5,PI*0.5)
				interpolated["mode"] = "interpolated"
				interpolated["poor_connection"] = false
				return interpolated
		var latest: Dictionary = _poses.back().duplicate(true)
		var age := maxf(0,target - latest.tick)
		latest.feet += latest.native_velocity * 32.0 * minf(age,MAX_EXTRAPOLATION_TICKS) / RULES.HZ
		latest["mode"] = "frozen" if age > MAX_EXTRAPOLATION_TICKS else ("extrapolated" if age > 0 else "latest")
		latest["poor_connection"] = age > MAX_EXTRAPOLATION_TICKS
		return latest

	func get_stats() -> Dictionary:
		return {"poses":_poses.size(),"capacity":CAPACITY,"actor_id":_actor_id,"epoch":_epoch,"spawn_generation":_generation,"delay_seconds":_delay_ticks/RULES.HZ}
