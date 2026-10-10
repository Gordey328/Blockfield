class_name BlockfieldHitHistory
extends RefCounted
## Same-time public poses and terrain rewind from committed authority receipts.
const DATA = preload("res://world/voxel_data.gd")
const PLAYER = preload("res://simulation/player_state.gd")
const HITS = preload("res://gameplay/lab_hit_volumes.gd")
const MAX_TICKS: int = 15
const MAX_ACTORS: int = 32
const MAX_CHANGES: int = 32768
const MAX_BYTES: int = 8 * 1024 * 1024
const U32_MAX: int = 0xffffffff

class QueryLease extends RefCounted:
	var active: bool = true

class QueryContext extends RefCounted:
	## One index for all requested frames of the same closed authority tick.
	## Timelines are chronological [sequence,before,...] and recursively frozen.
	var active: bool = true
	var cells: Dictionary[Vector3i,Array] = {}
	var records: int = 0
	var indexed: bool = false
	func before_color(cell: Vector3i, frame_sequence: int, fallback: int) -> int:
		var timeline: Variant = cells.get(cell)
		if timeline == null: return fallback
		var low: int = 0
		var high: int = timeline.size()/2
		# First committed change strictly newer than the requested frame.
		while low < high:
			var middle: int = (low+high)/2
			if timeline[middle*2] <= frame_sequence: low=middle+1
			else: high=middle
		return timeline[low*2+1] if low*2 < timeline.size() else fallback
	func revoke() -> void:
		active=false
		# Leases retain this small context, not an old change-sized index.
		cells={}; records=0; indexed=false

class HistoricalVoxelQuery extends "res://world/voxel_data.gd":
	## Inherited DDA/ClipWorld dispatch to this get_block override.
	## Use immediately and check is_valid again before committing damage.
	var _live: VoxelData
	var _identity: Dictionary = {}
	var _context: QueryContext
	var _lease: QueryLease
	var _request_tick: int = -1
	var _frame_sequence: int = -1
	func is_valid() -> bool:
		return _lease!=null and _lease.active and _context!=null and _context.active and _live!=null and _live.epoch==_identity.epoch and _live.map_sequence==_identity.map_sequence and _live.last_tick==_identity.tick \
			and _live.dimensions==_identity.dimensions and _live.blocks.size()==_identity.cells \
			and _live.water_level==_identity.water_level and _live.wade_origin_level==_identity.wade_origin_level \
			and dimensions==_identity.dimensions and water_level==_identity.water_level and wade_origin_level==_identity.wade_origin_level \
			and epoch==_identity.epoch and last_tick==_request_tick and map_sequence==_frame_sequence
	func get_block(cell: Vector3i) -> int:
		if not is_valid(): last_error="stale historical query"; return 0x01000000
		return _context.before_color(cell,_frame_sequence,_live.get_block(cell))
	func clip_world(position: Vector3) -> bool:
		if not is_valid(): last_error="stale historical query"; return true
		return super.clip_world(position)
	func cast_voxel(origin: Vector3, direction: Vector3, max_dist: float = 128.0) -> Dictionary:
		if not is_valid():
			last_error="stale historical query"
			return {"hit":false,"valid":false,"error":last_error,"cell":Vector3i.ZERO,"normal":Vector3i.ZERO,"position":origin}
		var result: Dictionary = super.cast_voxel(origin,direction,max_dist)
		result["valid"]=true; result["error"]=""; return result
	func cancel() -> void:
		if _lease!=null: _lease.active=false
		_live=null; _identity={}; _context=null; _lease=null

var _window: int = MAX_TICKS
var _max_changes: int = MAX_CHANGES
var _max_bytes: int = MAX_BYTES
var _epoch: int = 0
var _data: DATA
var _dimensions: Vector3i
var _water_level: float = 1.0
var _wade_origin_level: float = 2.0
var _baseline_tick: int = 0
var _latest_tick: int = -1
var _sequence: int = 0
var _frames: Array[Dictionary] = []
var _transactions: Array[Dictionary] = []
var _changes: int = 0
var _bytes: int = 0
var _state: String = "idle"
var _error: String = ""
var _query_context: QueryContext
var _query_identity: Dictionary = {}
var _cache_builds: int = 0
var _cache_hits: int = 0

static func _result(ok: bool, error: String = "") -> Dictionary:
	return {"ok":ok,"error":error}
static func _u32(value: Variant, positive: bool = false) -> bool:
	return typeof(value)==TYPE_INT and value>=(1 if positive else 0) and value<=U32_MAX
static func _valid_map(data: DATA) -> bool:
	return data!=null and not data.read_only and DATA.valid_dimensions(data.dimensions) and data.blocks.size()==data.dimensions.x*data.dimensions.y*data.dimensions.z \
		and _u32(data.epoch,true) and _u32(data.map_sequence) and _u32(data.last_tick) and is_finite(data.water_level) and is_finite(data.wade_origin_level)
static func _wire_bytes(count: int) -> int:
	return count*15+ceili(float(count)/2048.0)*56

func configure(window_ticks: int = MAX_TICKS, max_changes: int = MAX_CHANGES, max_bytes: int = MAX_BYTES) -> Dictionary:
	if _state not in ["idle","cancelled","invalid"]: return _result(false,"configure before reset")
	if window_ticks<0 or window_ticks>MAX_TICKS or max_changes<1 or max_changes>MAX_CHANGES or max_bytes<1 or max_bytes>MAX_BYTES: return _result(false,"invalid history bounds")
	_window=window_ticks; _max_changes=max_changes; _max_bytes=max_bytes
	return _result(true)

func reset(epoch: int, data: DATA) -> Dictionary:
	if not _u32(epoch,true) or not _valid_map(data) or data.epoch!=epoch: return _result(false,"invalid history baseline")
	_clear(); _epoch=epoch; _data=data; _dimensions=data.dimensions; _water_level=data.water_level; _wade_origin_level=data.wade_origin_level
	_baseline_tick=data.last_tick; _sequence=data.map_sequence; _state="recording"; _error=""
	_cache_builds=0; _cache_hits=0
	return _result(true)

func _clear_query_cache() -> void:
	if _query_context!=null: _query_context.revoke()
	_query_context=null; _query_identity={}

func _clear() -> void:
	_clear_query_cache()
	_data=null; _frames.clear(); _transactions.clear(); _changes=0; _bytes=0; _latest_tick=-1

func cancel(reason: String = "cancelled") -> void:
	_clear(); _state="cancelled"; _error=reason.left(256)

func _invalidate(reason: String) -> Dictionary:
	_clear(); _state="invalid"; _error=reason
	return _result(false,reason)

func _map_matches(data: DATA) -> bool:
	return data==_data and _valid_map(data) and data.epoch==_epoch and data.dimensions==_dimensions \
		and data.water_level==_water_level and data.wade_origin_level==_wade_origin_level

func _poses(tick: int, actors: Array[SharedPlayerState]) -> Dictionary:
	if actors.size()>MAX_ACTORS: return _result(false,"actor history limit")
	var poses: Array[Dictionary] = []
	var ids: Dictionary[int,bool] = {}
	var generations: Dictionary[int,int] = {}
	for frame: Dictionary in _frames:
		for pose: Dictionary in frame.actors: generations[pose.id]=pose.spawn_generation
	for actor: SharedPlayerState in actors:
		if actor==null or not _u32(actor.player_id,true) or ids.has(actor.player_id) or actor.match_epoch!=_epoch \
			or not _u32(actor.spawn_generation,true) or actor.team not in [0,1,2] or actor.motion==null or actor.health<0 or actor.health>100 \
			or actor.last_tick>tick or actor.last_tick< -1 or not is_finite(actor.yaw) or absf(actor.yaw)>PI+.000001 \
			or not is_finite(actor.pitch) or absf(actor.pitch)>PI*.5+.000001: return _result(false,"invalid public actor pose")
		if actor.spawn_generation<generations.get(actor.player_id,0): return _result(false,"actor generation regressed")
		var feet: Vector3 = actor.feet()
		var valid: bool = feet.is_finite()
		if actor.is_alive() and not valid: return _result(false,"live actor has nonfinite feet")
		ids[actor.player_id]=true
		feet=feet if valid else Vector3.ZERO
		poses.append({"id":actor.player_id,"spawn_generation":actor.spawn_generation,"epoch":_epoch,"team":actor.team,
			"alive":actor.is_alive(),"connected":actor.connected,"pose_valid":valid,"feet":feet,
			"physics_eye":feet+Vector3.UP*(1.35 if actor.motion.crouch else 2.25),"front":actor.front(),"yaw":actor.yaw,"pitch":actor.pitch,"crouch":actor.motion.crouch})
	poses.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id<b.id)
	var accepted: Dictionary = _result(true); accepted["actors"]=poses; return accepted

func record_frame(tick: int, data: DATA, actors: Array[SharedPlayerState], transactions: Array[Dictionary]) -> Dictionary:
	if _state!="recording": return _result(false,"history is not recording; reset required")
	if not _u32(tick) or not _map_matches(data) or data.last_tick!=tick: return _invalidate("history map identity/tick changed")
	if tick!=(_baseline_tick if _latest_tick<0 else _latest_tick+1): return _invalidate("history frame gap/duplicate")
	var poses: Dictionary = _poses(tick,actors)
	if not poses.ok: return _invalidate(poses.error)
	if transactions.size()>MAX_CHANGES: return _invalidate("history transaction count limit")
	var incoming: Array[Dictionary] = []
	var next_sequence: int = _sequence
	var incoming_changes: int = 0; var incoming_bytes: int = 0
	for transaction: Dictionary in transactions:
		for key: String in ["epoch","map_sequence","transaction_id","tick","actor_id","action_id"]:
			if not _u32(transaction.get(key),key in ["epoch","map_sequence","transaction_id"]): return _invalidate("invalid committed transaction identity")
		if next_sequence==U32_MAX or transaction.epoch!=_epoch or transaction.map_sequence!=next_sequence+1 or transaction.tick!=tick \
			or typeof(transaction.get("dimensions"))!=TYPE_VECTOR3I or transaction.dimensions!=_dimensions \
			or typeof(transaction.get("changes"))!=TYPE_ARRAY or transaction.changes.is_empty(): return _invalidate("committed transaction gap/tick/dimensions")
		var count: int = transaction.changes.size()
		incoming_changes+=count; incoming_bytes+=_wire_bytes(count)
		if incoming_changes>_max_changes or incoming_bytes>_max_bytes: return _invalidate("history incoming change/byte limit")
		var changes: Array[Dictionary] = []
		var seen: Dictionary[Vector3i,bool] = {}
		for value: Variant in transaction.changes:
			if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("cell"))!=TYPE_VECTOR3I or typeof(value.get("before"))!=TYPE_INT or typeof(value.get("after"))!=TYPE_INT or typeof(value.get("flags"))!=TYPE_INT: return _invalidate("invalid committed change fields")
			var cell: Vector3i = value.cell
			if not data.is_in_bounds(cell) or cell.y==0 or seen.has(cell) or not DATA.valid_color(value.before) or not DATA.valid_color(value.after) \
				or value.before==value.after or value.flags not in [0,1] or (value.flags==1 and (value.before==0 or value.after!=0 or cell.y<=1)): return _invalidate("invalid committed before/after/cell/flags")
			seen[cell]=true
			changes.append({"cell":cell,"before":value.before,"after":value.after})
		incoming.append({"tick":tick,"map_sequence":transaction.map_sequence,"changes":changes,"wire_bytes":_wire_bytes(count)})
		next_sequence=transaction.map_sequence
	if next_sequence!=data.map_sequence: return _invalidate("committed map changes missing from history")
	# Walk committed changes backwards against current authority colors. A cell
	# may occur in different transactions; latest after / earlier before must join.
	var reverse: Dictionary[Vector3i,int] = {}
	for index: int in range(incoming.size()-1,-1,-1):
		for change: Dictionary in incoming[index].changes:
			if reverse.get(change.cell,data.get_block(change.cell))!=change.after: return _invalidate("committed after-color/reverse-chain mismatch")
			reverse[change.cell]=change.before
	var previous_colors: Dictionary[Vector3i,int] = {}
	for transaction: Dictionary in _transactions:
		for change: Dictionary in transaction.changes: previous_colors[change.cell]=change.after
	for cell: Vector3i in reverse:
		if previous_colors.has(cell) and previous_colors[cell]!=reverse[cell]: return _invalidate("committed before-color history mismatch")
	var oldest_tick: int = maxi(_baseline_tick,tick-_window)
	var retained_changes: int = incoming_changes; var retained_bytes: int = incoming_bytes
	for transaction: Dictionary in _transactions:
		if transaction.tick>oldest_tick: retained_changes+=transaction.changes.size(); retained_bytes+=transaction.wire_bytes
	# The first/current-only frame has no older pose to rewind before these edits.
	if tick==oldest_tick: retained_changes=0; retained_bytes=0
	if retained_changes>_max_changes or retained_bytes>_max_bytes: return _invalidate("history retained change/byte limit")
	while not _frames.is_empty() and _frames[0].tick<oldest_tick: _frames.pop_front()
	while not _transactions.is_empty() and _transactions[0].tick<=oldest_tick: _transactions.pop_front()
	if tick>oldest_tick: _transactions.append_array(incoming)
	_frames.append({"tick":tick,"map_sequence":next_sequence,"actors":poses.actors})
	_changes=retained_changes; _bytes=retained_bytes; _sequence=next_sequence; _latest_tick=tick
	_clear_query_cache()
	return _result(true)

func _query_context_for_closed_tick(frame_sequence: int) -> QueryContext:
	if _query_context!=null:
		_cache_hits=mini(U32_MAX,_cache_hits+1)
	else:
		_query_context=QueryContext.new()
		_query_context.cells.make_read_only()
		_query_identity={"epoch":_epoch,"map_sequence":_sequence,"tick":_latest_tick,"dimensions":_dimensions,"cells":_data.blocks.size(),"water_level":_water_level,"wade_origin_level":_wade_origin_level}
		_query_identity.make_read_only()
	# A current-map query must not pay for unused old terrain. Once an older
	# map sequence is requested, build one index for every retained frame.
	if frame_sequence < _sequence and not _query_context.indexed:
		var cells: Dictionary[Vector3i,Array] = {}
		var records: int = 0
		for transaction: Dictionary in _transactions:
			for change: Dictionary in transaction.changes:
				var timeline: Array = cells.get(change.cell,[])
				timeline.append(transaction.map_sequence); timeline.append(change.before)
				cells[change.cell]=timeline; records+=1
		for timeline: Array in cells.values(): timeline.make_read_only()
		cells.make_read_only()
		_query_context.cells=cells; _query_context.records=records; _query_context.indexed=true
		_cache_builds=mini(U32_MAX,_cache_builds+1)
	return _query_context

func query_at(request_tick: int, current_tick: int) -> Dictionary:
	if _state!="recording" or _frames.is_empty(): return _result(false,"no valid hit history")
	if not _u32(request_tick) or current_tick!=_latest_tick or request_tick>current_tick: return _result(false,"future/current tick mismatch")
	if not _map_matches(_data) or _data.last_tick!=_latest_tick or _data.map_sequence!=_sequence:
		_clear_query_cache()
		return _result(false,"authority advanced beyond recorded history")
	var frame: Dictionary = {}
	for candidate: Dictionary in _frames:
		if candidate.tick==request_tick: frame=candidate; break
	if frame.is_empty(): return _result(false,"requested tick outside retained history")
	var query: HistoricalVoxelQuery = HistoricalVoxelQuery.new()
	query.dimensions=_dimensions; query.water_level=_water_level; query.wade_origin_level=_wade_origin_level; query.read_only=true
	query.epoch=_epoch; query.map_sequence=frame.map_sequence; query.last_tick=request_tick; query._live=_data
	query._request_tick=request_tick; query._frame_sequence=frame.map_sequence
	query._context=_query_context_for_closed_tick(frame.map_sequence); query._lease=QueryLease.new(); query._identity=_query_identity
	var accepted: Dictionary = _result(true)
	accepted["query"]=query; accepted["actors"]=frame.actors.duplicate(true); accepted["tick"]=request_tick; accepted["map_sequence"]=frame.map_sequence
	return accepted

func get_stats() -> Dictionary:
	return {"status":_state,"error":_error,"epoch":_epoch,"latest_tick":_latest_tick,"map_sequence":_sequence,"frames":_frames.size(),
		"oldest_tick":_frames[0].tick if not _frames.is_empty() else -1,"transactions":_transactions.size(),"changes":_changes,"wire_bytes":_bytes,"window_ticks":_window,
		"cache_builds":_cache_builds,"cache_hits":_cache_hits,"cache_entries":1 if _query_context!=null else 0,"cache_records":_query_context.records if _query_context!=null else 0,
		"cache_cells":_query_context.cells.size() if _query_context!=null else 0,"cache_indexed":_query_context.indexed if _query_context!=null else false}
