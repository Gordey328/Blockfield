class_name BlockfieldMapTransfer
extends RefCounted
## Isolated joining-map staging, ordered transaction assembly and lazy senders.
const PROTOCOL = preload("res://network/protocol.gd")
const DATA = preload("res://world/voxel_data.gd")
const MAX_BUFFERED_BYTES: int = 8 * 1024 * 1024
const MAX_BUFFERED_CHANGES: int = 32768
const MAX_TRANSACTIONS: int = 128
const MAX_CLOCK_MS: int = 0x7ffffffffffe0000
const APPLY_RECORDS: int = 512

class Helpers extends RefCounted:
	static func result(ok: bool, error: String = "", status: String = "") -> Dictionary:
		return {"ok":ok,"error":error,"status":status}
	static func u32(value: Variant, positive: bool = false) -> bool:
		return typeof(value)==TYPE_INT and value >= (1 if positive else 0) and value <= PROTOCOL.U32_MAX
	static func clock(value: Variant, previous: int) -> Dictionary:
		if typeof(value)!=TYPE_INT: return result(false,"clock must be an integer")
		var now: int = Time.get_ticks_msec() if value==-1 else value
		if now<0 or now>MAX_CLOCK_MS or (previous>=0 and now<previous): return result(false,"negative, overflowing or regressing clock")
		var accepted: Dictionary = result(true); accepted["now"] = now; return accepted
	static func map_valid(data: DATA) -> bool:
		return data!=null and DATA.valid_dimensions(data.dimensions) and data.blocks.size()==data.dimensions.x*data.dimensions.y*data.dimensions.z and u32(data.epoch,true) and u32(data.map_sequence) and u32(data.last_tick)
	static func hash_map(data: DATA) -> Dictionary:
		if not map_valid(data): return result(false,"invalid map state")
		var context: HashingContext = HashingContext.new()
		if context.start(HashingContext.HASH_SHA256)!=OK: return result(false,"hash initialization failed")
		var count: int = data.blocks.size()*4
		for offset: int in range(0,count,PROTOCOL.CHUNK_BYTES):
			var bytes: PackedByteArray = data.snapshot_range(offset,mini(PROTOCOL.CHUNK_BYTES,count-offset))
			if bytes.is_empty() or context.update(bytes)!=OK: return result(false,"invalid baseline color or hash update")
		var accepted: Dictionary = result(true); accepted["hash"] = context.finish(); return accepted
	static func change_valid(change: Dictionary, dimensions: Vector3i) -> bool:
		if change.size()!=4 or typeof(change.get("cell"))!=TYPE_VECTOR3I or typeof(change.get("before"))!=TYPE_INT or typeof(change.get("after"))!=TYPE_INT or typeof(change.get("flags"))!=TYPE_INT: return false
		var cell: Vector3i = change.cell
		if cell.x<0 or cell.y<=0 or cell.z<0 or cell.x>=dimensions.x or cell.y>=dimensions.y or cell.z>=dimensions.z: return false
		if not DATA.valid_color(change.before) or not DATA.valid_color(change.after) or change.before==change.after or change.flags not in [0,1]: return false
		return change.flags==0 or (change.before!=0 and change.after==0 and cell.y>1)
	static func transaction_valid(transaction: Dictionary) -> Dictionary:
		for key: String in ["epoch","map_sequence","transaction_id","tick","actor_id","action_id"]:
			if not u32(transaction.get(key),key in ["epoch","map_sequence","transaction_id"]): return result(false,"invalid transaction identity")
		if typeof(transaction.get("dimensions"))!=TYPE_VECTOR3I or not DATA.valid_dimensions(transaction.dimensions): return result(false,"invalid transaction dimensions")
		if typeof(transaction.get("changes"))!=TYPE_ARRAY or transaction.changes.is_empty() or transaction.changes.size()>MAX_BUFFERED_CHANGES or transaction.changes.size()>transaction.dimensions.x*transaction.dimensions.y*transaction.dimensions.z: return result(false,"transaction change count exceeds limit")
		var seen: Dictionary[Vector3i,bool] = {}
		for value: Variant in transaction.changes:
			if typeof(value)!=TYPE_DICTIONARY or not change_valid(value,transaction.dimensions): return result(false,"invalid transaction change")
			if seen.has(value.cell): return result(false,"duplicate transaction cell")
			seen[value.cell] = true
		return result(true)
	static func copy_change(change: Dictionary) -> Dictionary:
		return {"cell":change.cell,"before":change.before,"after":change.after,"flags":change.flags}

class TransactionAssembler extends RefCounted:
	## Emits validated full transactions; the caller atomically applies them to its map.
	var _epoch: int = 0
	var _sequence: int = 0
	var _tick: int = 0
	var _dimensions: Vector3i
	var _identity: Dictionary = {}
	var _changes: Array[Dictionary] = []
	var _seen: Dictionary[Vector3i,bool] = {}
	var _next_fragment: int = 0
	var _wire_bytes: int = 0
	var _last_clock: int = -1
	var _started_ms: int = -1
	var _armed: bool = false
	var _error: String = ""
	var max_changes: int = MAX_BUFFERED_CHANGES
	var max_wire_bytes: int = MAX_BUFFERED_BYTES
	var timeout_ms: int = 10000
	func reset(epoch: int, sequence: int, dimensions: Vector3i, tick: int = 0) -> Dictionary:
		if not Helpers.u32(epoch,true) or not Helpers.u32(sequence) or not Helpers.u32(tick) or not DATA.valid_dimensions(dimensions): return Helpers.result(false,"invalid assembler baseline")
		cancel(); _epoch=epoch; _sequence=sequence; _dimensions=dimensions; _tick=tick; _armed=true; _error=""
		return Helpers.result(true,"","waiting")
	func cancel(reason: String = "cancelled") -> void:
		_identity.clear(); _changes.clear(); _seen.clear(); _next_fragment=0; _wire_bytes=0; _started_ms=-1; _last_clock=-1; _armed=false; _error=reason
	func _fail(reason: String) -> Dictionary:
		cancel(reason); return Helpers.result(false,reason,"failed")
	func poll(now_ms: Variant = -1) -> Dictionary:
		var clock: Dictionary = Helpers.clock(now_ms,_last_clock)
		if not clock.ok: return _fail(clock.error)
		_last_clock=clock.now
		if _started_ms>=0 and _last_clock-_started_ms>=clampi(timeout_ms,100,120000): return _fail("transaction timeout")
		return Helpers.result(_armed,_error,"assembling" if not _identity.is_empty() else "waiting")
	func push(packet: PROTOCOL.Packet, now_ms: Variant = -1) -> Dictionary:
		if not _armed: return Helpers.result(false,"assembler is not armed","failed")
		var timed: Dictionary = poll(now_ms)
		if not timed.ok: return timed
		if packet==null or packet.kind!=PROTOCOL.Kind.MAP_DELTA: return _fail("expected map delta")
		var encoded: PROTOCOL.Result = PROTOCOL.encode(packet)
		if not encoded.ok: return _fail(encoded.error)
		var payload: Dictionary = packet.payload
		if packet.epoch!=_epoch or payload.dimensions!=_dimensions or packet.sequence!=payload.map_sequence: return _fail("delta epoch, dimensions or header sequence mismatch")
		if _sequence==PROTOCOL.U32_MAX or payload.map_sequence!=_sequence+1 or packet.tick<_tick: return _fail("delta sequence gap, duplicate or tick regression")
		var identity: Dictionary = {"epoch":packet.epoch,"map_sequence":payload.map_sequence,"transaction_id":payload.transaction_id,"tick":packet.tick,"actor_id":payload.actor_id,"action_id":payload.action_id,"dimensions":payload.dimensions,"fragment_count":payload.fragment_count,"total_changes":payload.total_changes}
		if _identity.is_empty():
			if payload.fragment_index!=0: return _fail("transaction fragments must begin at zero")
			if payload.total_changes>clampi(max_changes,1,MAX_BUFFERED_CHANGES): return _fail("transaction change count exceeds assembly budget")
			_identity=identity; _started_ms=_last_clock
		elif identity!=_identity: return _fail("transaction fragment identity changed")
		if payload.fragment_index!=_next_fragment: return _fail("out-of-order or duplicate transaction fragment")
		if _wire_bytes+encoded.bytes.size()>clampi(max_wire_bytes,1,MAX_BUFFERED_BYTES): return _fail("transaction byte budget exceeded")
		# Check the entire fragment before retaining any records.
		for change: Dictionary in payload.changes:
			if not Helpers.change_valid(change,_dimensions): return _fail("invalid transaction change")
			if _seen.has(change.cell): return _fail("duplicate cell across transaction fragments")
		for change: Dictionary in payload.changes:
			_seen[change.cell]=true; _changes.append(Helpers.copy_change(change))
		_wire_bytes+=encoded.bytes.size(); _next_fragment+=1
		if _next_fragment<_identity.fragment_count: return Helpers.result(true,"","assembling")
		if _changes.size()!=_identity.total_changes: return _fail("assembled transaction count mismatch")
		var transaction: Dictionary = {"epoch":_identity.epoch,"map_sequence":_identity.map_sequence,"transaction_id":_identity.transaction_id,"tick":_identity.tick,"actor_id":_identity.actor_id,"action_id":_identity.action_id,"dimensions":_dimensions,"changes":_changes}
		var accepted: Dictionary = Helpers.result(true,"","complete"); accepted["complete"]=true; accepted["transaction"]=transaction; accepted["wire_bytes"]=_wire_bytes
		_sequence=transaction.map_sequence; _tick=transaction.tick
		# Rebind rather than clear: returned complete transaction owns this array.
		_changes=[]; _identity={}; _seen.clear(); _next_fragment=0; _wire_bytes=0; _started_ms=-1
		return accepted
	func get_stats() -> Dictionary:
		return {"armed":_armed,"epoch":_epoch,"map_sequence":_sequence,"tick":_tick,"partial":not _identity.is_empty(),"pending_sequence":_identity.get("map_sequence",0),"pending_tick":_identity.get("tick",0),"changes":_changes.size(),"wire_bytes":_wire_bytes,"next_fragment":_next_fragment,"error":_error}

class BaselineSender extends RefCounted:
	var _data: DATA
	var _snapshot_id: int
	var _hash: PackedByteArray
	var _index: int = 0
	func begin_packet() -> PROTOCOL.Packet:
		if _data==null: return null
		var count: int = _data.blocks.size()*4
		return PROTOCOL.make_packet(PROTOCOL.Kind.MAP_BEGIN,{"snapshot_id":_snapshot_id,"dimensions":_data.dimensions,"compression":0,"compressed_size":count,"uncompressed_size":count,"chunk_count":ceili(float(count)/PROTOCOL.CHUNK_BYTES),"map_sequence":_data.map_sequence,"hash":_hash.duplicate()},_data.epoch,_data.last_tick,_data.map_sequence)
	func next_chunk() -> Dictionary:
		if _data==null: return Helpers.result(false,"sender cancelled")
		var total: int = _data.blocks.size()*4
		var offset: int = _index*PROTOCOL.CHUNK_BYTES
		if offset>=total:
			var done: Dictionary = Helpers.result(true); done["done"]=true; return done
		var bytes: PackedByteArray = _data.snapshot_range(offset,mini(PROTOCOL.CHUNK_BYTES,total-offset))
		if bytes.is_empty(): return Helpers.result(false,"frozen map changed or invalid")
		var packet: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.MAP_CHUNK,{"snapshot_id":_snapshot_id,"index":_index,"total_size":total,"data":bytes},_data.epoch,_data.last_tick,_data.map_sequence)
		_index+=1
		var accepted: Dictionary = Helpers.result(true); accepted["done"]=false; accepted["packet"]=packet; return accepted
	func end_packet(barrier: DATA) -> Dictionary:
		if _data==null or not Helpers.map_valid(barrier) or barrier.epoch!=_data.epoch or barrier.dimensions!=_data.dimensions or barrier.map_sequence<_data.map_sequence or barrier.last_tick<_data.last_tick: return Helpers.result(false,"invalid barrier identity")
		var hashed: Dictionary = Helpers.hash_map(barrier)
		if not hashed.ok: return hashed
		var accepted: Dictionary = Helpers.result(true)
		accepted["packet"]=PROTOCOL.make_packet(PROTOCOL.Kind.MAP_END,{"snapshot_id":_snapshot_id,"map_sequence":barrier.map_sequence,"hash":hashed.hash},barrier.epoch,barrier.last_tick,barrier.map_sequence)
		return accepted
	func prepare_end(barrier: DATA) -> Dictionary:
		if _data==null or not Helpers.map_valid(barrier) or barrier.epoch!=_data.epoch or barrier.dimensions!=_data.dimensions or barrier.map_sequence<_data.map_sequence or barrier.last_tick<_data.last_tick: return Helpers.result(false,"invalid barrier identity")
		var job: HashPreparationJob = HashPreparationJob.new()
		var started: Dictionary = job._start(barrier,_snapshot_id,"end",true)
		if not started.ok: return started
		var accepted: Dictionary = Helpers.result(true); accepted["job"]=job; return accepted
	func cancel() -> void: _data=null; _hash=PackedByteArray()
	func get_stats() -> Dictionary:
		return {"retained_map_bytes":_data.blocks.size()*4 if _data!=null else 0,"next_chunk":_index,"snapshot_id":_snapshot_id}

class HashPreparationJob extends RefCounted:
	## Explicit bounded work between frames. Frozen container setup is synchronous.
	var _data: DATA
	var _context: HashingContext
	var _hash: PackedByteArray = PackedByteArray()
	var _index: int = 0
	var _snapshot_id: int = 0
	var _purpose: String = ""
	var _state: String = "idle"
	var _error: String = ""
	var _freeze_usec: int = 0
	func _start(data: DATA, snapshot_id: int, purpose: String, freeze: bool) -> Dictionary:
		if not Helpers.map_valid(data) or not Helpers.u32(snapshot_id,true) or purpose not in ["sender","end","hash"]: return Helpers.result(false,"invalid hash preparation identity")
		var started: int = Time.get_ticks_usec()
		_data=data.frozen_copy() as DATA if freeze else data
		_freeze_usec=Time.get_ticks_usec()-started
		_snapshot_id=snapshot_id; _purpose=purpose; _context=HashingContext.new()
		if _context.start(HashingContext.HASH_SHA256)!=OK: return _fail("hash initialization failed")
		_state="preparing"; return _progress()
	func _fail(reason: String) -> Dictionary:
		cancel(); _state="failed"; _error=reason; return _progress()
	func _progress() -> Dictionary:
		var accepted: Dictionary = Helpers.result(_state in ["preparing","ready"],_error,_state); accepted["done"]=_state=="ready"; return accepted
	func advance(max_chunks: int = 1) -> Dictionary:
		if max_chunks<1 or max_chunks>32: return Helpers.result(false,"hash work budget must be 1..32")
		if _state!="preparing": return _progress()
		var total: int = _data.blocks.size()*4
		for work: int in range(max_chunks):
			var offset: int = _index*PROTOCOL.CHUNK_BYTES
			if offset>=total: break
			var bytes: PackedByteArray = _data.snapshot_range(offset,mini(PROTOCOL.CHUNK_BYTES,total-offset))
			if bytes.is_empty() or _context.update(bytes)!=OK: return _fail("invalid baseline color or hash update")
			_index+=1
		if _index*PROTOCOL.CHUNK_BYTES>=total: _hash=_context.finish(); _context=null; _state="ready"
		return _progress()
	func take_sender() -> Dictionary:
		if _state!="ready" or _purpose!="sender": return Helpers.result(false,"no prepared sender")
		var sender: BaselineSender = BaselineSender.new(); sender._data=_data; sender._snapshot_id=_snapshot_id; sender._hash=_hash
		var accepted: Dictionary = Helpers.result(true); accepted["sender"]=sender; _release(); _state="consumed"; return accepted
	func take_packet() -> Dictionary:
		if _state!="ready" or _purpose!="end": return Helpers.result(false,"no prepared barrier")
		var packet: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.MAP_END,{"snapshot_id":_snapshot_id,"map_sequence":_data.map_sequence,"hash":_hash},_data.epoch,_data.last_tick,_data.map_sequence)
		var accepted: Dictionary = Helpers.result(true); accepted["packet"]=packet; _release(); _state="consumed"; return accepted
	func take_hash() -> Dictionary:
		if _state!="ready" or _purpose!="hash": return Helpers.result(false,"no prepared hash")
		var accepted: Dictionary = Helpers.result(true); accepted["hash"]=_hash; _release(); _state="consumed"; return accepted
	func _release() -> void: _data=null; _context=null; _hash=PackedByteArray()
	func cancel() -> void: _release(); _state="cancelled"
	func get_stats() -> Dictionary:
		return {"status":_state,"processed_chunks":_index,"retained_map_bytes":_data.blocks.size()*4 if _data!=null else 0,"freeze_usec":_freeze_usec}

class SnapshotDecodeJob extends RefCounted:
	## Private byte->packed decode. No map is returned until every color validates.
	var _bytes: PackedByteArray = PackedByteArray()
	var _data: DATA
	var _descriptor: Dictionary = {}
	var _index: int = 0
	var _state: String = "idle"
	var _error: String = ""
	func _start(bytes: PackedByteArray, descriptor: Dictionary) -> Dictionary:
		if typeof(descriptor.get("dimensions"))!=TYPE_VECTOR3I or not DATA.valid_dimensions(descriptor.dimensions) or not Helpers.u32(descriptor.get("epoch"),true) or not Helpers.u32(descriptor.get("map_sequence")) or not Helpers.u32(descriptor.get("tick")) or bytes.size()!=descriptor.dimensions.x*descriptor.dimensions.y*descriptor.dimensions.z*4: return Helpers.result(false,"invalid private decode descriptor")
		_bytes=bytes; _descriptor=descriptor.duplicate(true); _state="decoding"; return _progress()
	func _progress() -> Dictionary:
		var accepted: Dictionary = Helpers.result(_state in ["decoding","ready"],_error,_state); accepted["done"]=_state=="ready"; return accepted
	func advance(max_chunks: int = 1) -> Dictionary:
		if max_chunks<1 or max_chunks>32: return Helpers.result(false,"decode work budget must be 1..32")
		if _state!="decoding": return _progress()
		if _data==null:
			_data=DATA.new()
			_data.dimensions=_descriptor.dimensions; _data.epoch=_descriptor.epoch
			_data.map_sequence=_descriptor.map_sequence; _data.last_tick=_descriptor.tick; _data.set_journal_budget(0,0,0)
		var total: int = _bytes.size()/4
		var last: int = mini(total,_index+(PROTOCOL.CHUNK_BYTES/4)*max_chunks)
		var decoded: PackedInt32Array = PackedInt32Array()
		var order: int = DATA.packed_byte_order()
		if order!=0:
			var bytes: PackedByteArray = _bytes.slice(_index*4,last*4)
			if order==1: bytes.bswap32()
			decoded=bytes.to_int32_array()
		else:
			decoded.resize(last-_index)
			for index: int in range(_index,last):
				var offset: int = index*4
				decoded[index-_index]=(_bytes[offset]<<24)|(_bytes[offset+1]<<16)|(_bytes[offset+2]<<8)|_bytes[offset+3]
		# Native conversion never bypasses canonical color validation.
		for value: int in decoded:
			if not DATA.valid_color(value): return _fail("invalid canonical baseline colors")
		_data.blocks.append_array(decoded)
		_index=last
		if _index==total: _bytes=PackedByteArray(); _descriptor={}; _state="ready"
		return _progress()
	func _fail(reason: String) -> Dictionary:
		cancel(); _state="failed"; _error=reason; return _progress()
	func take_data() -> Dictionary:
		if _state!="ready": return Helpers.result(false,"no decoded map")
		var accepted: Dictionary = Helpers.result(true); accepted["data"]=_data; _data=null; _state="consumed"; return accepted
	func cancel() -> void: _bytes=PackedByteArray(); _data=null; _descriptor={}; _state="cancelled"
	func get_stats() -> Dictionary:
		return {"status":_state,"decoded_cells":_index,"baseline_bytes":_bytes.size(),"allocated_map_bytes":_data.blocks.size()*4 if _data!=null else 0}

class TransactionApplyJob extends RefCounted:
	## Joining stage only: all validation precedes bounded private writes.
	## The receiver exclusively owns/discards the stage until a final hash.
	var _data: DATA
	var _identity: Dictionary = {}
	var _changes: Array = []
	var _seen: Dictionary[Vector3i,bool] = {}
	var _index: int = 0
	var _state: String = "idle"
	var _error: String = ""
	func _start(data: DATA, transaction: Dictionary) -> Dictionary:
		if not Helpers.map_valid(data) or data.read_only: return Helpers.result(false,"private map is not writable")
		for key: String in ["epoch","map_sequence","transaction_id","tick","actor_id","action_id"]:
			if not Helpers.u32(transaction.get(key),key in ["epoch","map_sequence","transaction_id"]): return Helpers.result(false,"invalid private transaction identity")
		if data.map_sequence==PROTOCOL.U32_MAX or transaction.epoch!=data.epoch or transaction.map_sequence!=data.map_sequence+1 or transaction.tick<data.last_tick or typeof(transaction.get("dimensions"))!=TYPE_VECTOR3I or transaction.dimensions!=data.dimensions: return Helpers.result(false,"private transaction baseline mismatch")
		if typeof(transaction.get("changes"))!=TYPE_ARRAY or transaction.changes.is_empty() or transaction.changes.size()>MAX_BUFFERED_CHANGES or transaction.changes.size()>data.blocks.size(): return Helpers.result(false,"invalid private transaction count")
		_data=data; _changes=transaction.changes
		_identity={"epoch":transaction.epoch,"map_sequence":transaction.map_sequence,"tick":transaction.tick,"dimensions":transaction.dimensions}
		_state="validate"; return _progress()
	func _progress() -> Dictionary:
		var accepted: Dictionary = Helpers.result(_state in ["validate","write","ready"],_error,_state); accepted["done"]=_state=="ready"; return accepted
	func advance(max_chunks: int = 1) -> Dictionary:
		if max_chunks<1 or max_chunks>32: return Helpers.result(false,"private apply work budget must be 1..32")
		if _state not in ["validate","write"]: return _progress()
		if _data.epoch!=_identity.epoch or _data.map_sequence!=_identity.map_sequence-1 or _data.last_tick>_identity.tick or _data.dimensions!=_identity.dimensions: return _fail("private stage changed during transaction")
		var last: int = mini(_changes.size(),_index+APPLY_RECORDS*max_chunks)
		if _state=="validate":
			for index: int in range(_index,last):
				var value: Variant = _changes[index]
				if typeof(value)!=TYPE_DICTIONARY or not Helpers.change_valid(value,_data.dimensions): return _fail("invalid private transaction change")
				if _seen.has(value.cell): return _fail("duplicate private transaction cell")
				if _data.get_block(value.cell)!=value.before: return _fail("private before-color conflict; resync")
				_seen[value.cell]=true
			_index=last
			if _index==_changes.size(): _state="write"; _index=0
			return _progress()
		for index: int in range(_index,last):
			var change: Dictionary = _changes[index]
			_data.blocks[_data.index(change.cell)]=change.after
			_seen.erase(change.cell)
		_index=last
		if _index==_changes.size():
			_data.map_sequence=_identity.map_sequence; _data.last_tick=_identity.tick
			_data=null; _changes=[]; _identity={}; _state="ready"
		return _progress()
	func _fail(reason: String) -> Dictionary:
		cancel(); _state="failed"; _error=reason; return _progress()
	func cancel() -> void:
		_data=null; _changes=[]; _identity={}; _seen.clear(); _state="cancelled"
	func get_stats() -> Dictionary:
		return {"status":_state,"processed_records":_index,"retained_records":_changes.size(),"validation_cells":_seen.size()}

class DeltaSender extends RefCounted:
	var _transaction: Dictionary = {}
	var _index: int = 0
	func next_fragment() -> Dictionary:
		if _transaction.is_empty(): return Helpers.result(false,"delta sender cancelled")
		var total: int = _transaction.changes.size()
		var first: int = _index*PROTOCOL.MAX_CHANGES
		if first>=total:
			var done: Dictionary = Helpers.result(true); done["done"]=true; return done
		var changes: Array[Dictionary] = []
		for index: int in range(first,mini(first+PROTOCOL.MAX_CHANGES,total)): changes.append(Helpers.copy_change(_transaction.changes[index]))
		var payload: Dictionary = {"map_sequence":_transaction.map_sequence,"transaction_id":_transaction.transaction_id,"actor_id":_transaction.actor_id,"action_id":_transaction.action_id,"dimensions":_transaction.dimensions,"fragment_index":_index,"fragment_count":ceili(float(total)/PROTOCOL.MAX_CHANGES),"total_changes":total,"changes":changes}
		var packet: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.MAP_DELTA,payload,_transaction.epoch,_transaction.tick,_transaction.map_sequence)
		_index+=1
		var accepted: Dictionary = Helpers.result(true); accepted["done"]=false; accepted["packet"]=packet; return accepted
	func cancel() -> void: _transaction.clear()
	func get_stats() -> Dictionary:
		return {"retained_changes":_transaction.get("changes",[]).size(),"next_fragment":_index}

var _state: String = "idle"
var _error: String = ""
var _expected_epoch: int = 0
var _descriptor: Dictionary = {}
var _bytes: PackedByteArray = PackedByteArray()
var _hash_context: HashingContext
var _next_chunk: int = 0
var _stage: DATA
var _decode_job: SnapshotDecodeJob
var _final_hash_job: HashPreparationJob
var _apply_job: TransactionApplyJob
var _assembler: TransactionAssembler
var _transactions: Array[Dictionary] = []
var _buffered_bytes: int = 0
var _buffered_changes: int = 0
var _end: Dictionary = {}
var _ready: Dictionary = {}
var _last_clock: int = -1
var _started_ms: int = -1
var _config: Dictionary = {"max_buffered_bytes":MAX_BUFFERED_BYTES,"max_buffered_changes":MAX_BUFFERED_CHANGES,"max_transactions":MAX_TRANSACTIONS,"timeout_ms":240000,"incremental":true}

func configure(options: Dictionary) -> Dictionary:
	if _state!="idle": return Helpers.result(false,"join is not idle",_state)
	var ranges: Dictionary = {"max_buffered_bytes":Vector2i(1,MAX_BUFFERED_BYTES),"max_buffered_changes":Vector2i(1,MAX_BUFFERED_CHANGES),"max_transactions":Vector2i(1,MAX_TRANSACTIONS),"timeout_ms":Vector2i(100,600000)}
	for key: Variant in options:
		if key=="incremental":
			if typeof(options[key])!=TYPE_BOOL: return Helpers.result(false,"invalid incremental option",_state)
			continue
		if not ranges.has(key) or typeof(options[key])!=TYPE_INT or options[key]<ranges[key].x or options[key]>ranges[key].y: return Helpers.result(false,"invalid join configuration",_state)
	for key: Variant in options: _config[key]=options[key]
	return Helpers.result(true,"",_state)

func reset(expected_epoch: int = 0) -> Dictionary:
	if not Helpers.u32(expected_epoch): return Helpers.result(false,"invalid expected epoch",_state)
	_clear(); _state="idle"; _error=""; _expected_epoch=expected_epoch
	return Helpers.result(true,"",_state)

func cancel(reason: String = "cancelled") -> void:
	_clear(); _state="cancelled"; _error=reason.left(256)

func _clear() -> void:
	_descriptor={}; _bytes=PackedByteArray(); _hash_context=null; _next_chunk=0; _stage=null
	if _decode_job!=null: _decode_job.cancel()
	if _final_hash_job!=null: _final_hash_job.cancel()
	if _apply_job!=null: _apply_job.cancel()
	_decode_job=null; _final_hash_job=null
	_apply_job=null
	if _assembler!=null: _assembler.cancel()
	_assembler=null; _transactions.clear(); _buffered_bytes=0; _buffered_changes=0; _end={}; _ready={}; _last_clock=-1; _started_ms=-1

func _fail(reason: String) -> Dictionary:
	_clear(); _state="failed"; _error=reason
	return Helpers.result(false,reason,_state)

func _timed(now_ms: Variant) -> Dictionary:
	var clock: Dictionary = Helpers.clock(now_ms,_last_clock)
	if not clock.ok: return _fail(clock.error)
	_last_clock=clock.now
	if _started_ms>=0 and _state=="receiving" and _last_clock-_started_ms>=int(_config.timeout_ms): return _fail("map transfer timeout")
	if _state=="receiving" and _assembler!=null:
		var partial: Dictionary = _assembler.poll(_last_clock)
		if not partial.ok: return _fail(partial.error)
	return Helpers.result(_state not in ["failed","cancelled"],_error,_state)

func poll(now_ms: Variant = -1, max_chunks: int = 1) -> Dictionary:
	var timed: Dictionary = _timed(now_ms)
	if not timed.ok: return timed
	if max_chunks<1 or max_chunks>32: return _fail("join work budget must be 1..32")
	return _advance(max_chunks) if _has_work() else timed

func consume(packet: PROTOCOL.Packet, now_ms: Variant = -1) -> Dictionary:
	if _state in ["failed","cancelled","ready","consumed"]: return Helpers.result(false,"join is terminal; reset required",_state)
	var timed: Dictionary = _timed(now_ms)
	if not timed.ok: return timed
	if packet==null or packet.kind not in [PROTOCOL.Kind.MAP_BEGIN,PROTOCOL.Kind.MAP_CHUNK,PROTOCOL.Kind.MAP_DELTA,PROTOCOL.Kind.MAP_END]: return _fail("unexpected transfer packet")
	var encoded: PROTOCOL.Result = PROTOCOL.encode(packet)
	if not encoded.ok: return _fail(encoded.error)
	if packet.kind==PROTOCOL.Kind.MAP_BEGIN: return _begin(packet)
	if _state!="receiving": return _fail("map begin required")
	if packet.epoch!=_descriptor.epoch: return _fail("map epoch changed; reset required")
	match packet.kind:
		PROTOCOL.Kind.MAP_CHUNK: return _chunk(packet)
		PROTOCOL.Kind.MAP_DELTA: return _delta(packet,encoded.bytes.size())
		PROTOCOL.Kind.MAP_END: return _barrier(packet)
	return _fail("unexpected transfer packet")

func _begin(packet: PROTOCOL.Packet) -> Dictionary:
	if _state!="idle": return _fail("duplicate map begin; explicit reset required")
	var payload: Dictionary = packet.payload
	if packet.epoch==0 or (_expected_epoch!=0 and packet.epoch!=_expected_epoch) or packet.sequence!=payload.map_sequence: return _fail("baseline epoch or header sequence mismatch")
	if payload.compression!=0: return _fail("Zstandard baseline compression is unsupported")
	_descriptor={"epoch":packet.epoch,"tick":packet.tick,"snapshot_id":payload.snapshot_id,"dimensions":payload.dimensions,"size":payload.uncompressed_size,"chunk_count":payload.chunk_count,"map_sequence":payload.map_sequence,"hash":payload.hash.duplicate()}
	_hash_context=HashingContext.new()
	if _hash_context.start(HashingContext.HASH_SHA256)!=OK: return _fail("hash initialization failed")
	_assembler=TransactionAssembler.new(); _assembler.max_changes=_config.max_buffered_changes; _assembler.max_wire_bytes=_config.max_buffered_bytes; _assembler.timeout_ms=_config.timeout_ms
	_assembler.reset(packet.epoch,payload.map_sequence,payload.dimensions,packet.tick)
	_started_ms=_last_clock; _state="receiving"
	return Helpers.result(true,"",_state)

func _chunk(packet: PROTOCOL.Packet) -> Dictionary:
	var payload: Dictionary = packet.payload
	if _stage!=null or _decode_job!=null or payload.snapshot_id!=_descriptor.snapshot_id or payload.total_size!=_descriptor.size or packet.tick!=_descriptor.tick or packet.sequence!=_descriptor.map_sequence: return _fail("chunk identity mismatch or baseline already complete")
	if payload.index!=_next_chunk: return _fail("out-of-order or duplicate map chunk")
	if _bytes.size()+payload.data.size()>_descriptor.size: return _fail("baseline size exceeded")
	_bytes.append_array(payload.data); _next_chunk+=1
	if _hash_context.update(payload.data)!=OK: return _fail("hash update failed")
	if _next_chunk<_descriptor.chunk_count: return Helpers.result(true,"",_state)
	if _bytes.size()!=_descriptor.size or _hash_context.finish()!=_descriptor.hash: return _fail("baseline length or SHA256 mismatch")
	_hash_context=null; _decode_job=SnapshotDecodeJob.new()
	var started: Dictionary = _decode_job._start(_bytes,_descriptor)
	if not started.ok: return _fail(started.error)
	_bytes=PackedByteArray()
	return _request_advance()

func _delta(packet: PROTOCOL.Packet, wire_bytes: int) -> Dictionary:
	if not _end.is_empty() and (packet.payload.map_sequence>_end.map_sequence or packet.tick>_end.tick): return _fail("delta exceeds declared barrier")
	var stats: Dictionary = _assembler.get_stats()
	if _buffered_changes+stats.changes+packet.payload.changes.size()>int(_config.max_buffered_changes) or _buffered_bytes+stats.wire_bytes+wire_bytes>int(_config.max_buffered_bytes): return _fail("join delta retention budget exceeded")
	if not stats.partial and _transactions.size()>=int(_config.max_transactions): return _fail("join transaction count budget exceeded")
	var assembled: Dictionary = _assembler.push(packet,_last_clock)
	if not assembled.ok: return _fail(assembled.error)
	if assembled.get("complete",false):
		_transactions.append(assembled.transaction); _buffered_bytes+=assembled.wire_bytes; _buffered_changes+=assembled.transaction.changes.size()
	return _request_advance()

func _barrier(packet: PROTOCOL.Packet) -> Dictionary:
	var payload: Dictionary = packet.payload
	if not _end.is_empty(): return _fail("duplicate map end")
	var assembled: Dictionary = _assembler.get_stats()
	if payload.snapshot_id!=_descriptor.snapshot_id or packet.sequence!=payload.map_sequence or payload.map_sequence<_descriptor.map_sequence or payload.map_sequence<maxi(assembled.map_sequence,assembled.pending_sequence) or packet.tick<_descriptor.tick or packet.tick<maxi(assembled.tick,assembled.pending_tick): return _fail("barrier identity, sequence or tick regression")
	_end={"snapshot_id":payload.snapshot_id,"map_sequence":payload.map_sequence,"tick":packet.tick,"hash":payload.hash.duplicate()}
	return _request_advance()

func _has_work() -> bool:
	return _decode_job!=null or _final_hash_job!=null or (_stage!=null and (not _transactions.is_empty() or (not _end.is_empty() and _stage.map_sequence>=_end.map_sequence)))

func _request_advance() -> Dictionary:
	if not _config.incremental:
		while _has_work():
			var advanced: Dictionary = _advance(32)
			if not advanced.ok: return advanced
	return Helpers.result(true,"",_state)

func _advance(max_chunks: int) -> Dictionary:
	if _decode_job!=null:
		var decoded: Dictionary = _decode_job.advance(max_chunks)
		if not decoded.ok: return _fail(decoded.error)
		if decoded.done: _stage=_decode_job.take_data().data; _decode_job=null
		return Helpers.result(true,"",_state)
	if _stage==null: return Helpers.result(true,"",_state)
	if not _transactions.is_empty():
		var transaction: Dictionary = _transactions[0]
		if not _end.is_empty() and (transaction.map_sequence>_end.map_sequence or transaction.tick>_end.tick): return _fail("buffered delta exceeds barrier")
		if _apply_job==null:
			_apply_job=TransactionApplyJob.new()
			var started: Dictionary = _apply_job._start(_stage,transaction)
			if not started.ok: return _fail(started.error)
		var applied: Dictionary = _apply_job.advance(max_chunks)
		if not applied.ok: return _fail(applied.error)
		if applied.done:
			_apply_job=null; _transactions.pop_front(); _buffered_changes-=transaction.changes.size()
			_buffered_bytes-=transaction.changes.size()*15+ceili(float(transaction.changes.size())/PROTOCOL.MAX_CHANGES)*56
		return Helpers.result(true,"",_state)
	if _end.is_empty() or _stage.map_sequence<_end.map_sequence: return Helpers.result(true,"",_state)
	if _stage.map_sequence!=_end.map_sequence or _assembler.get_stats().partial or _stage.last_tick>_end.tick: return _fail("incomplete or inconsistent barrier")
	if _final_hash_job==null:
		_final_hash_job=HashPreparationJob.new()
		var started: Dictionary = _final_hash_job._start(_stage,_end.snapshot_id,"hash",false)
		if not started.ok: return _fail(started.error)
	var hashed: Dictionary = _final_hash_job.advance(max_chunks)
	if not hashed.ok: return _fail(hashed.error)
	if not hashed.done: return Helpers.result(true,"",_state)
	if _final_hash_job.take_hash().hash!=_end.hash: return _fail("barrier SHA256 mismatch")
	_final_hash_job=null
	_stage.last_tick=_end.tick
	_ready={"ok":true,"error":"","data":_stage,"epoch":_descriptor.epoch,"snapshot_id":_descriptor.snapshot_id,"map_sequence":_end.map_sequence,"tick":_end.tick,"hash":_end.hash.duplicate()}
	_stage=null; _assembler.cancel(); _assembler=null; _transactions.clear(); _bytes=PackedByteArray(); _hash_context=null; _descriptor={}; _end={}; _buffered_bytes=0; _buffered_changes=0; _started_ms=-1
	_state="ready"; return Helpers.result(true,"",_state)

func take_ready() -> Dictionary:
	if _state!="ready" or _ready.is_empty(): return Helpers.result(false,"no ready map",_state)
	var result: Dictionary = _ready; _ready={}; _state="consumed"
	return result

func get_stats() -> Dictionary:
	var partial: Dictionary = _assembler.get_stats() if _assembler!=null else {}
	var decoded: Dictionary = _decode_job.get_stats() if _decode_job!=null else {}
	return {"status":_state,"error":_error,"expected_epoch":_expected_epoch,"snapshot_id":_descriptor.get("snapshot_id",0),"baseline_bytes":_bytes.size()+decoded.get("baseline_bytes",0),"staged_map_bytes":(_stage.blocks.size()*4 if _stage!=null else 0)+decoded.get("allocated_map_bytes",0),"ready_map_bytes":_ready.data.blocks.size()*4 if not _ready.is_empty() else 0,"next_chunk":_next_chunk,"transactions":_transactions.size(),"retained_wire_bytes":_buffered_bytes+partial.get("wire_bytes",0),"retained_changes":_buffered_changes+partial.get("changes",0),"partial_transaction":partial.get("partial",false),"pending_work":_has_work(),"work_phase":"decode" if _decode_job!=null else ("hash" if _final_hash_job!=null else ("apply_"+_apply_job.get_stats().status if _apply_job!=null else ("apply" if not _transactions.is_empty() and _stage!=null else "waiting"))),"decoded_cells":decoded.get("decoded_cells",0),"apply_records":_apply_job.get_stats().processed_records if _apply_job!=null else 0,"hash_chunks":_final_hash_job.get_stats().processed_chunks if _final_hash_job!=null else 0}

static func hash_data(data: DATA) -> Dictionary: return Helpers.hash_map(data)

static func prepare_sender(data: DATA, snapshot_id: int) -> Dictionary:
	var job: HashPreparationJob = HashPreparationJob.new()
	var started: Dictionary = job._start(data,snapshot_id,"sender",true)
	if not started.ok: return started
	var accepted: Dictionary = Helpers.result(true); accepted["job"]=job; return accepted

static func make_sender(data: DATA, snapshot_id: int) -> Dictionary:
	if not Helpers.map_valid(data) or not Helpers.u32(snapshot_id,true): return Helpers.result(false,"invalid baseline sender identity")
	var sender: BaselineSender = BaselineSender.new()
	# Explicit independent packed container; physical copy cost may occur on write.
	sender._data=data.frozen_copy() as DATA; sender._snapshot_id=snapshot_id
	var hashed: Dictionary = Helpers.hash_map(sender._data)
	if not hashed.ok: sender.cancel(); return hashed
	sender._hash=hashed.hash
	var accepted: Dictionary = Helpers.result(true); accepted["sender"]=sender; return accepted

static func make_delta_sender(transaction: Dictionary) -> Dictionary:
	var validated: Dictionary = Helpers.transaction_valid(transaction)
	if not validated.ok: return validated
	var sender: DeltaSender = DeltaSender.new()
	var changes: Array[Dictionary] = []
	for change: Dictionary in transaction.changes: changes.append(Helpers.copy_change(change))
	sender._transaction={"epoch":transaction.epoch,"map_sequence":transaction.map_sequence,"transaction_id":transaction.transaction_id,"tick":transaction.tick,"actor_id":transaction.actor_id,"action_id":transaction.action_id,"dimensions":transaction.dimensions,"changes":changes}
	var accepted: Dictionary = Helpers.result(true); accepted["sender"]=sender; return accepted
