class_name OpenSpadesAudioEnvironment
extends RefCounted
## ALDevice.cpp:268–348,630–742. Pure room/obstruction queries, not DSP.
## The budget is a browser scheduling adaptation; incomplete/expired samples
## are explicitly unknown and do not turn on the obstruction filter.

const HISTORY_SIZE: int = 128
const ROOM_DISTANCE: float = 40.0
const ROOM_INTERVAL: float = 1.0 / 60.0
const OBSTRUCTION_REFRESH: float = .1
const OBSTRUCTION_HORIZON: float = .25
const MAX_CACHE: int = 128
const MAX_RAYS_PER_TURN: int = 128
const MAX_QUERY_USEC: int = 1500

var query: Variant
var distances: PackedFloat64Array = PackedFloat64Array()
var feedback_history: PackedFloat64Array = PackedFloat64Array()
var history_position: int = 0
var parameters: Dictionary = {}
var room_age: float = 0.0
var last_turn_rays: int = 0
var last_turn_usec: int = 0
var budget_exhausted: bool = false
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _cache: Dictionary = {}
var _last_room_time: float = -INF
var _now: float = 0.0
var _turn_start: int = 0
var _ray_limit: int = MAX_RAYS_PER_TURN
var _time_limit: int = MAX_QUERY_USEC
var _terrain_key: String = ""
var _query_epoch: int = -1
var _query_sequence: int = -1

func _init() -> void:
	_random.randomize()
	reset()

func reset() -> void:
	distances.resize(HISTORY_SIZE)
	distances.fill(20000.0)
	feedback_history.resize(HISTORY_SIZE)
	feedback_history.fill(0.0)
	history_position = 0
	_cache.clear()
	_last_room_time = -INF
	room_age = 0.0
	parameters = room_parameters(distances, feedback_history, query != null)
	_terrain_key = ""
	_query_epoch = -1
	_query_sequence = -1

func set_query(value: Variant) -> void:
	query = value
	reset()

func seed_random(value: int) -> void:
	_random.seed = value

func begin_turn(now_seconds: float, ray_limit: int = MAX_RAYS_PER_TURN, usec_limit: int = MAX_QUERY_USEC) -> void:
	_now = now_seconds
	_turn_start = Time.get_ticks_usec()
	_ray_limit = maxi(0, ray_limit)
	_time_limit = maxi(0, usec_limit)
	last_turn_rays = 0
	last_turn_usec = 0
	budget_exhausted = false
	# VoxelData sequence changes invalidate answers; do not reuse an old wall
	# after a block edit or a new epoch. This does not reset the source room ring.
	var key: String = "none"
	if query != null and query is VoxelData:
		# A new epoch or baseline rewind is a port lifecycle boundary, unlike
		# an ordinary block edit. Native SetGameMap did not reset this ring.
		if _query_epoch != -1 and (query.epoch != _query_epoch or query.map_sequence < _query_sequence):
			reset()
		_query_epoch = query.epoch
		_query_sequence = query.map_sequence
		key = "%d:%d:%d" % [query.get_instance_id(), query.epoch, query.map_sequence]
	elif query != null:
		key = str(query.get_instance_id())
	if key != _terrain_key:
		_cache.clear()
		_terrain_key = key
	room_age = maxf(0.0, _now - _last_room_time) if is_finite(_last_room_time) else INF

func finish_turn() -> void:
	last_turn_usec = Time.get_ticks_usec() - _turn_start

func _can_ray() -> bool:
	if last_turn_rays >= _ray_limit or (_time_limit > 0 and Time.get_ticks_usec() - _turn_start >= _time_limit):
		budget_exhausted = true
		return false
	return true

func _trace(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	last_turn_rays += 1
	if query.has_method("cast_source_ray_legacy"):
		return query.cast_source_ray_legacy(origin, direction, distance)
	return query.cast_voxel(origin, direction, distance)

func sample_room(eye: Vector3) -> void:
	if query == null:
		parameters = room_parameters(distances, feedback_history, false)
		_last_room_time = _now
		room_age = 0.0
		return
	if _now - _last_room_time < ROOM_INTERVAL:
		return
	var completed: int = 0
	for _sample: int in range(4):
		# Reserve a forward/opposite pair so an exhausted budget cannot commit
		# half an acoustic sample. No catch-up loop after a stalled browser frame.
		if last_turn_rays + 2 > _ray_limit or not _can_ray():
			budget_exhausted = true
			break
		var source_direction: Vector3 = Vector3(_random.randf() - _random.randf(), _random.randf() - _random.randf(), _random.randf() - _random.randf())
		if source_direction.length_squared() < .000000000001:
			source_direction = Vector3.RIGHT
		var direction: Vector3 = Vector3(source_direction.x, -source_direction.z, source_direction.y).normalized()
		var forward: Dictionary = _trace(eye, direction, ROOM_DISTANCE)
		if not bool(forward.get("valid",true)):
			continue
		var distance: float = ROOM_DISTANCE * 2.0
		var opposite_hit: Variant = null
		if bool(forward.hit):
			# W maps the native integer z corner to the top of a Godot voxel.
			distance = eye.distance_to(Vector3(forward.cell) + Vector3.UP)
			var opposite: Dictionary = _trace(eye, -direction, ROOM_DISTANCE)
			if not bool(opposite.get("valid",true)):
				continue
			opposite_hit = bool(opposite.hit)
		commit_room_sample(distance, opposite_hit)
		completed += 1
	if completed > 0:
		parameters = room_parameters(distances, feedback_history, true)
		_last_room_time = _now
		room_age = 0.0

func commit_room_sample(distance: float, opposite_hit: Variant = null) -> void:
	## Native forward misses replace distance with80 but leave the feedback slot
	## untouched. Keep this source quirk instead of silently changing the ring.
	distances[history_position] = distance
	if opposite_hit != null:
		feedback_history[history_position] = 1.0 if bool(opposite_hit) else 0.0
	history_position = (history_position + 1) % HISTORY_SIZE

static func room_parameters(samples: PackedFloat64Array, feedback: PackedFloat64Array, has_map: bool = true) -> Dictionary:
	var hits: int = 0
	var volume: float = 0.0
	var area: float = 0.0
	var size: float = 0.0
	var feedbackness: float = 0.0
	var reflections: float = 0.0
	if has_map:
		for distance: float in samples:
			if distance < ROOM_DISTANCE:
				hits += 1
				volume += distance * distance
				area += distance
				size += distance
		for value: float in feedback:
			feedbackness += value
		feedbackness /= float(HISTORY_SIZE)
		if hits > HISTORY_SIZE / 4:
			volume *= 4.0 * PI / (3.0 * hits)
			area *= 4.0 * PI / hits
			size /= hits
			reflections = float(hits) / HISTORY_SIZE
		else:
			volume = 8.0
			area = 100.0
			size = 100.0
			reflections = .2
	else:
		volume = 1.0
		area = 1.0
		size = 10.0
	var early_delay: float = minf(size / 324.0, .3)
	var late_delay: float = minf(size / 324.0, .1)
	return {"hits": hits, "volume": volume, "area": area, "room_size": size, "reflections": reflections, "feedback": feedbackness,
		"decay_time": clampf(.161 * volume / maxf(area, .000001) / .4, .1, 20.0), "gain": .8 * reflections,
		"early_delay": early_delay, "late_delay": late_delay, "late_onset": early_delay + late_delay,
		"early_gain": .25 * reflections, "late_gain": .34 * pow(reflections, 4) * pow(feedbackness, 3),
		"gain_hf": .5929, "gain_lf": 1.0, "hf_reference": 5000.0, "lf_reference": 250.0,
		"decay_hf_ratio": .83, "decay_lf_ratio": 1.0, "density": .4287, "diffusion": 1.0,
		"air_absorption_gain_hf": .9943, "room_rolloff": 0.0, "decay_hf_limit": true}

func obstruction(eye: Vector3, origin: Vector3) -> Dictionary:
	if query == null:
		return {"blocked": false, "known": true, "age": 0.0, "rays": 0}
	# Exact vectors retain source .2m endpoints at voxel boundaries. The cache
	# shares gun layers at one origin without quantizing their source geometry.
	var key: Array = [eye, origin]
	var cached: Dictionary = _cache.get(key, {})
	var age: float = _now - float(cached.get("time", -INF))
	if not cached.is_empty() and age < OBSTRUCTION_REFRESH:
		return {"blocked": bool(cached.blocked), "known": true, "age": maxf(0.0, age), "rays": 0}
	var answer: Dictionary = trace_obstruction(eye, origin, true)
	if bool(answer.known):
		if _cache.size() >= MAX_CACHE and not _cache.has(key):
			_cache.erase(_cache.keys()[0])
		_cache[key] = {"blocked": bool(answer.blocked), "time": _now}
		return answer
	if not cached.is_empty() and age <= OBSTRUCTION_HORIZON:
		return {"blocked": bool(cached.blocked), "known": true, "age": maxf(0.0, age), "rays": int(answer.rays)}
	return {"blocked": false, "known": false, "age": maxf(0.0, age), "rays": int(answer.rays)}

func trace_obstruction(eye: Vector3, origin: Vector3, budgeted: bool = false) -> Dictionary:
	## First clear ray proves the same AND-of27 predicate as native full loops.
	var traced: int = 0
	if query == null:
		return {"blocked": false, "known": true, "age": 0.0, "rays": 0}
	for x: int in range(-1, 2):
		for y: int in range(-1, 2):
			for z: int in range(-1, 2):
				if budgeted and not _can_ray():
					return {"blocked": false, "known": false, "age": INF, "rays": traced}
				var segment: Vector3 = origin + Vector3(x, y, z) * .2 - eye
				var hit: Dictionary = _trace(eye, segment.normalized(), segment.length())
				traced += 1
				if not bool(hit.get("valid",true)):
					return {"blocked":false,"known":false,"age":INF,"rays":traced}
				if not bool(hit.hit):
					return {"blocked": false, "known": true, "age": 0.0, "rays": traced}
	return {"blocked": true, "known": true, "age": 0.0, "rays": traced}

func debug_state() -> Dictionary:
	return {"parameters": parameters.duplicate(true), "history_position": history_position, "room_age": room_age,
		"rays": last_turn_rays, "query_usec": last_turn_usec, "budget_exhausted": budget_exhausted,
		"cache_entries": _cache.size(), "obstruction_refresh": OBSTRUCTION_REFRESH, "obstruction_horizon": OBSTRUCTION_HORIZON}
