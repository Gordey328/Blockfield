extends SceneTree
## Pure maps and hostile transfer packets. No scene, sockets or preferences.
const TRANSFER = preload("res://network/map_transfer.gd")
const PROTOCOL = preload("res://network/protocol.gd")
const DATA = preload("res://world/voxel_data.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions+=1
	if not condition: failures+=1; push_error("MAP_TRANSFER: "+message)
func _run() -> void:
	if OS.get_cmdline_user_args().has("--benchmark-map-transfer"):
		_benchmark_large_map(); quit(0); return
	_test_baseline_golden()
	_test_incremental_jobs()
	_test_private_apply_jobs()
	_test_two_replicas()
	_test_baseline_failures()
	_test_transaction_failures()
	_test_budgets_and_lifecycle()
	_test_bulk_window()
	print("MAP_TRANSFER: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)

func _test_bulk_window() -> void:
	var data: DATA = _data(Vector3i(64,16,64))
	var sender: TRANSFER.BaselineSender = _sender(data)
	var begin: PROTOCOL.Packet = sender.begin_packet()
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	var receiver: TRANSFER = _join(begin)
	var window := TRANSFER.BulkWindow.new()
	check(window.reset(begin).ok and chunks.size()>16,"bulk credit fixture exceeds two full windows")
	check(not receiver.get_chunk_ack().ok,"no credit before any chunk is accepted")
	for index in range(8): check(window.mark_sent(chunks[index]).ok,"initial send fits bounded receive credit")
	check(not window.can_send() and not window.mark_sent(chunks[8]).ok and window.get_stats().outstanding_chunks==8,"ninth queued chunk waits for receiver credit")
	var before := window.get_stats()
	var ack := PROTOCOL.make_packet(PROTOCOL.Kind.MAP_CHUNK_ACK,{"snapshot_id":9,"next_chunk":8,"received_bytes":8*PROTOCOL.CHUNK_BYTES},begin.epoch,begin.tick,begin.sequence)
	for change in ["epoch","tick","sequence","snapshot","ahead","bytes"]:
		var bad := _clone(ack)
		match change:
			"epoch": bad.epoch+=1
			"tick": bad.tick+=1
			"sequence": bad.sequence+=1
			"snapshot": bad.payload.snapshot_id+=1
			"ahead": bad.payload.next_chunk=9; bad.payload.received_bytes=9*PROTOCOL.CHUNK_BYTES
			"bytes": bad.payload.received_bytes-=1
		check(not window.acknowledge(bad).ok and window.get_stats()==before,"invalid %s ACK cannot grant or remove credit" % change)
	for index in range(8): check(receiver.consume(_wire(chunks[index]),1).ok,"paused receiver later accepts its buffered window")
	var received := receiver.get_chunk_ack()
	check(received.ok and received.packet.payload.next_chunk==8 and window.acknowledge(_wire(received.packet)).advanced,"accepted cumulative ACK reopens bounded sender")
	var copied: PROTOCOL.Packet = receiver.get_chunk_ack().packet; copied.payload.next_chunk=1
	check(receiver.get_chunk_ack().packet.payload.next_chunk==8,"caller cannot mutate retained ACK metadata")
	var duplicate := window.acknowledge(ack)
	check(duplicate.ok and duplicate["duplicate"] and not duplicate.advanced,"duplicate latest cumulative ACK is a no-op")
	var older := _clone(ack); older.payload.next_chunk=1; older.payload.received_bytes=PROTOCOL.CHUNK_BYTES
	check(window.acknowledge(older)["duplicate"] and window.get_stats().acked_chunks==8,"older valid progress in the same snapshot grants no extra credit")
	check(receiver.consume(sender.end_packet(data).packet,2).ok and not receiver.take_ready().ok,"cross-channel END before remaining chunks cannot expose the map")
	for index in range(8,chunks.size()):
		if not window.can_send(): check(window.acknowledge(receiver.get_chunk_ack().packet).ok,"later full window waits for cumulative acknowledgment")
		check(window.mark_sent(chunks[index]).ok and receiver.consume(_wire(chunks[index]),3).ok,"later chunk stays within credit and strict ordered baseline")
	var final_ack: PROTOCOL.Packet = receiver.get_chunk_ack().packet
	var guard := 0
	while receiver.get_stats().pending_work and guard<100:
		check(receiver.poll(4,2).ok,"bounded decode and barrier hash preserve final pending acknowledgment")
		guard+=1
	var ready := receiver.take_ready()
	check(guard<100 and ready.ok and ready.data.blocks==data.blocks,"full windows converge at the canonical final barrier")
	check(receiver.get_chunk_ack().packet.payload==final_ack.payload,"final ACK metadata survives ready handoff for cross-socket ordering")
	check(window.acknowledge(final_ack).ok and window.get_stats().outstanding_chunks==0,"delayed final ACK is valid after ready handoff")
	window.cancel(); receiver.cancel()
	check(not window.acknowledge(final_ack).ok and not receiver.get_chunk_ack().ok,"disconnect/reset cannot retain old window or ACK metadata")
	var reset_begin := _clone(begin); reset_begin.epoch+=1
	check(window.reset(reset_begin).ok and not window.acknowledge(final_ack).ok,"previous-epoch progress cannot credit a fresh snapshot")

func _data(size: Vector3i = Vector3i(32,8,32)) -> DATA:
	var data: DATA = DATA.new()
	check(data.clear(size,7)==OK,"fixture map initialized")
	data.seed_box(Vector3i.ZERO,Vector3i(size.x,2,size.z),0x01334455)
	if size.x>10 and size.y>4 and size.z>10: data.seed_box(Vector3i(10,2,10),Vector3i(11,5,11),0x01667788)
	return data
func _wire(packet: PROTOCOL.Packet) -> PROTOCOL.Packet:
	var encoded: PROTOCOL.Result = PROTOCOL.encode(packet)
	check(encoded.ok,"helper emits a codec-valid packet")
	if not encoded.ok: return null
	var decoded: PROTOCOL.Result = PROTOCOL.decode(encoded.bytes)
	check(decoded.ok,"helper packet survives actual binary roundtrip")
	return decoded.packet
func _clone(packet: PROTOCOL.Packet) -> PROTOCOL.Packet:
	return PROTOCOL.make_packet(packet.kind,packet.payload.duplicate(true),packet.epoch,packet.tick,packet.sequence)
func _sender(data: DATA) -> TRANSFER.BaselineSender:
	var result: Dictionary = TRANSFER.make_sender(data,9)
	check(result.ok,"baseline sender validates and freezes map")
	return result.get("sender")
func _chunks(sender: TRANSFER.BaselineSender) -> Array[PROTOCOL.Packet]:
	var packets: Array[PROTOCOL.Packet] = []
	while true:
		var chunk: Dictionary = sender.next_chunk()
		check(chunk.ok,"lazy chunk generator succeeds")
		if not chunk.ok or chunk.done: break
		packets.append(_wire(chunk.packet))
	return packets
func _fragments(transaction: Dictionary) -> Array[PROTOCOL.Packet]:
	var result: Dictionary = TRANSFER.make_delta_sender(transaction)
	check(result.ok,"whole delta validates before fragmentation")
	var packets: Array[PROTOCOL.Packet] = []
	if not result.ok: return packets
	while true:
		var fragment: Dictionary = result.sender.next_fragment()
		check(fragment.ok,"lazy delta generator succeeds")
		if not fragment.ok or fragment.done: break
		packets.append(_wire(fragment.packet))
	return packets
func _large_transaction(data: DATA, count: int, sequence: int = 1, tick: int = 10) -> Dictionary:
	var changes: Array[Dictionary] = []
	for z: int in range(data.dimensions.z):
		for x: int in range(data.dimensions.x):
			for y: int in range(1,data.dimensions.y):
				if changes.size()>=count: break
				var cell: Vector3i = Vector3i(x,y,z)
				var before: int = data.get_block(cell)
				changes.append({"cell":cell,"before":before,"after":0x01112233 if before!=0x01112233 else 0x01445566,"flags":0})
	return {"epoch":data.epoch,"map_sequence":sequence,"transaction_id":sequence+100,"tick":tick,"actor_id":4,"action_id":sequence+20,"dimensions":data.dimensions,"changes":changes}
func _join(begin: PROTOCOL.Packet, options: Dictionary = {}) -> TRANSFER:
	var receiver: TRANSFER = TRANSFER.new()
	check(receiver.configure(options).ok,"join limits configured")
	check(receiver.reset(begin.epoch).ok,"receiver binds the expected epoch")
	check(_consume(receiver,_wire(begin),0).ok,"receiver accepts matching baseline descriptor")
	return receiver
func _feed_chunks(receiver: TRANSFER, chunks: Array[PROTOCOL.Packet], now: int = 1) -> void:
	for chunk: PROTOCOL.Packet in chunks: check(_consume(receiver,chunk,now).ok,"ordered chunk accepted")
func _cleared(receiver: TRANSFER) -> bool:
	var stats: Dictionary = receiver.get_stats()
	return stats.baseline_bytes==0 and stats.staged_map_bytes==0 and stats.ready_map_bytes==0 and stats.retained_changes==0 and stats.retained_wire_bytes==0 and stats.transactions==0 and not stats.partial_transaction

func _consume(receiver: TRANSFER, packet: PROTOCOL.Packet, now: int) -> Dictionary:
	var result: Dictionary = receiver.consume(packet,now)
	var guard: int = 0
	while result.ok and receiver.get_stats().pending_work and guard<5000:
		result=receiver.poll(now,32); guard+=1
	check(guard<5000,"incremental test work reaches a finite waiting/ready/error state")
	return result

func _test_incremental_jobs() -> void:
	var data: DATA = _data()
	var prep: Dictionary = TRANSFER.prepare_sender(data,9)
	check(prep.ok and prep.job.get_stats().processed_chunks==0,"production sender preparation starts without full synchronous hash")
	var first: Dictionary = prep.job.advance()
	check(first.ok and not first.done and prep.job.get_stats().processed_chunks==1,"sender hash processes one bounded range per default advance")
	check(not prep.job.take_sender().ok,"partial hash cannot emit baseline sender")
	check(not prep.job.advance(0).ok and not prep.job.advance(33).ok,"invalid hash work budget rejected")
	data.blocks[0]=0x01ffffff
	var guard: int = 0
	while not prep.job.advance().done and guard<20: guard+=1
	check(guard<20,"sender preparation finishes in bounded test advances")
	var completed: Dictionary = prep.job.take_sender()
	check(completed.ok and not prep.job.take_sender().ok and prep.job.get_stats().retained_map_bytes==0,"prepared frozen map transfers ownership once")
	var sender: TRANSFER.BaselineSender = completed.sender
	var begin: PROTOCOL.Packet = sender.begin_packet()
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	check(chunks[0].payload.data[1]==0x33,"incremental preparation freezes before live edits")
	var barrier: DATA = DATA.new(); var raw: PackedByteArray = PackedByteArray()
	for chunk: PROTOCOL.Packet in chunks: raw.append_array(chunk.payload.data)
	barrier.load_snapshot_bytes(raw,begin.payload.dimensions,7,0)
	var end_job: Dictionary = sender.prepare_end(barrier)
	check(end_job.ok and not end_job.job.take_packet().ok,"barrier hash remains a preparation job")
	barrier.blocks[0]=0x01abcdef
	guard=0
	while not end_job.job.advance().done and guard<20: guard+=1
	check(guard<20,"barrier hash advances incrementally")
	var end: Dictionary = end_job.job.take_packet()
	check(end.ok and end.packet.payload.hash==begin.payload.hash and not end_job.job.take_packet().ok,"barrier job freezes content and emits END once")
	var receiver: TRANSFER = _join(begin)
	check(receiver.consume(end.packet,1).ok,"incremental receiver stores early END without hash scan")
	for chunk: PROTOCOL.Packet in chunks: check(receiver.consume(chunk,2).ok,"raw consume queues incremental decode")
	check(receiver.get_stats().pending_work and receiver.get_stats().decoded_cells==0 and receiver.get_stats().status=="receiving","default receiver does not synchronously decode full map on last chunk")
	check(receiver.poll(3).ok and receiver.get_stats().decoded_cells>0 and receiver.get_stats().decoded_cells<8192,"one poll decodes a bounded cell range")
	check(not receiver.take_ready().ok,"partially decoded private map cannot be adopted")
	guard=0
	while receiver.get_stats().pending_work and guard<20:
		check(receiver.poll(3).ok,"decode/final hash advance without socket dependency")
		guard+=1
	check(guard<20 and receiver.take_ready().ok,"incremental decode and final SHA reach a ready barrier")
	var cancelled: Dictionary = TRANSFER.prepare_sender(data,9); cancelled.job.advance(); cancelled.job.cancel()
	check(cancelled.job.get_stats().retained_map_bytes==0 and not cancelled.job.advance().ok,"preparation cancel releases frozen map")
	var mid_decode: TRANSFER = _join(begin)
	for chunk: PROTOCOL.Packet in chunks: mid_decode.consume(chunk,1)
	mid_decode.poll(2); mid_decode.cancel("disconnect")
	check(_cleared(mid_decode),"cancel during incremental decode clears bytes and allocated map")
	var mid_hash: TRANSFER = _join(begin)
	for chunk: PROTOCOL.Packet in chunks: mid_hash.consume(chunk,1)
	mid_hash.consume(end.packet,2)
	guard=0
	while mid_hash.get_stats().work_phase!="hash" and guard<20: mid_hash.poll(3); guard+=1
	check(guard<20 and mid_hash.get_stats().hash_chunks==1,"final hash is a bounded visible work phase")
	mid_hash.cancel("disconnect"); check(_cleared(mid_hash),"cancel during barrier hash releases private staging")
	var sync: TRANSFER = _join(begin,{"incremental":false})
	_feed_chunks(sync,chunks)
	check(_consume(sync,end.packet,2).status=="ready","explicit small fixture/tool mode retains synchronous convenience")

func _test_private_apply_jobs() -> void:
	var data: DATA = _data()
	var baseline: PackedInt32Array = data.blocks.duplicate()
	var transaction: Dictionary = _large_transaction(data,3000)
	for duplicate: bool in [false,true]:
		var bad: Dictionary = transaction.duplicate(true)
		if duplicate: bad.changes[TRANSFER.APPLY_RECORDS]=bad.changes[0].duplicate()
		else: bad.changes[-1].before=0x01abcdef
		var failed: TRANSFER.TransactionApplyJob = TRANSFER.TransactionApplyJob.new()
		check(failed._start(data,bad).ok,"private transaction metadata validates without scanning all records")
		var guard: int = 0
		var result: Dictionary = failed.advance()
		while result.ok and guard<20: result=failed.advance(); guard+=1
		check(guard<20 and not result.ok and data.blocks==baseline and data.map_sequence==0 and data.last_tick==0,"cross-batch duplicate or late conflict rejects every write and metadata update")
		check(failed.get_stats().retained_records==0 and failed.get_stats().validation_cells==0,"failed private job releases retained records/duplicate set")
	var job: TRANSFER.TransactionApplyJob = TRANSFER.TransactionApplyJob.new()
	check(job._start(data,transaction).ok and not job.advance(0).ok and not job.advance(33).ok,"private work budget is bounded1..32")
	check(job.advance().ok and job.get_stats().processed_records==TRANSFER.APPLY_RECORDS and data.blocks==baseline,"one validation unit has no writes")
	var guard: int = 0
	while job.get_stats().status=="validate" and guard<20: job.advance(); guard+=1
	check(guard<20 and job.get_stats().status=="write" and data.blocks==baseline,"all before colors validate before first private write")
	check(job.advance().ok and data.blocks!=baseline and data.map_sequence==0 and data.last_tick==0,"partial private writes never advance public sequence/tick")
	guard=0
	while not job.advance().done and guard<20: guard+=1
	check(guard<20 and data.map_sequence==1 and data.last_tick==10,"whole private transaction advances metadata exactly once")
	var reference: DATA = _data()
	check(reference.apply_transaction(transaction).ok and reference.blocks==data.blocks,"bounded joining application matches unchanged live atomic application")

	var authority: DATA = _data(); var sender: TRANSFER.BaselineSender = _sender(authority)
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	var first: Dictionary = _large_transaction(authority,3000)
	var first_fragments: Array[PROTOCOL.Packet] = _fragments(first)
	check(authority.apply_transaction(first).ok,"ordered authority fixture applies first edit")
	var second: Dictionary = _large_transaction(authority,2,2,11)
	var second_fragments: Array[PROTOCOL.Packet] = _fragments(second)
	check(authority.apply_transaction(second).ok,"ordered authority fixture applies later edit")
	var receiver: TRANSFER = _join(sender.begin_packet())
	for chunk: PROTOCOL.Packet in chunks: receiver.consume(chunk,1)
	guard=0
	while receiver.get_stats().pending_work and guard<20: receiver.poll(2); guard+=1
	check(guard<20,"private baseline decode finishes before concurrent delta test")
	for fragment: PROTOCOL.Packet in first_fragments: check(receiver.consume(fragment,3).ok,"first transaction retained without synchronous application")
	check(receiver.poll(4).ok and receiver.get_stats().work_phase=="apply_validate","receiver exposes bounded validation phase")
	for fragment: PROTOCOL.Packet in second_fragments: check(receiver.consume(fragment,5).ok,"later complete delta may queue while one transaction is applying")
	check(receiver.get_stats().transactions==2 and not receiver.take_ready().ok,"queued transactions stay private before barrier")
	check(receiver.consume(sender.end_packet(authority).packet,6).ok,"barrier can arrive during private application")
	guard=0
	while receiver.get_stats().pending_work and guard<40: check(receiver.poll(7).ok,"private application/hash poll accepted"); guard+=1
	var ready: Dictionary = receiver.take_ready()
	check(guard<40 and ready.ok and ready.data.blocks==authority.blocks and ready.map_sequence==2,"queued private transactions converge before one ready handoff")

	var cancelled: TRANSFER = _join(sender.begin_packet())
	for chunk: PROTOCOL.Packet in chunks: cancelled.consume(chunk,1)
	guard=0
	while cancelled.get_stats().pending_work and guard<20: cancelled.poll(2); guard+=1
	for fragment: PROTOCOL.Packet in first_fragments: cancelled.consume(fragment,3)
	guard=0
	while cancelled.get_stats().work_phase!="apply_write" and guard<20: cancelled.poll(4); guard+=1
	check(guard<20 and cancelled.poll(5).ok and cancelled.get_stats().apply_records>0,"disconnect fixture has already written a bounded private batch")
	cancelled.cancel("disconnect")
	check(_cleared(cancelled) and reference.blocks==data.blocks and not cancelled.take_ready().ok,"cancel discards partially written stage without affecting another active replica")

func _test_baseline_golden() -> void:
	var data: DATA = DATA.new(); check(data.clear(Vector3i(2,3,2),7)==OK,"small golden map initialized")
	data.blocks[0]=0x01010203; data.blocks[2]=0x01aabbcc; data.blocks[4]=0x01000000
	var sender: TRANSFER.BaselineSender = _sender(data)
	var begin: PROTOCOL.Packet = _wire(sender.begin_packet())
	check(begin.payload.hash.hex_encode()=="791738ac6882a6671c78c0cb56e9e023859e96156140d56aae145d96b15a9f57","SHA256 matches independent Python Y-fast BE golden")
	check(begin.payload.dimensions==Vector3i(2,3,2) and begin.payload.uncompressed_size==48 and begin.payload.compression==0,"descriptor preserves x/y/z dimensions and raw exact size")
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	check(chunks.size()==1 and chunks[0].payload.data.hex_encode()=="010102030000000001aabbcc000000000100000000000000000000000000000000000000000000000000000000000000","baseline bytes are canonical Y-fast big endian")
	data.blocks[0]=0x01ffffff
	check(sender.begin_packet().payload.hash==begin.payload.hash,"live mutation cannot alter frozen baseline")
	var changed_begin: PROTOCOL.Packet = sender.begin_packet(); changed_begin.payload.hash[0]^=1
	check(sender.begin_packet().payload.hash==begin.payload.hash,"caller cannot mutate sender hash through returned packet")
	var receiver: TRANSFER = _join(begin)
	_feed_chunks(receiver,chunks)
	check(receiver.get_stats().status=="receiving" and not receiver.take_ready().ok,"complete baseline alone does not authorize installation")
	var frozen: DATA = DATA.new(); check(frozen.load_snapshot_bytes(chunks[0].payload.data,Vector3i(2,3,2),7,0)==OK,"independent expected barrier built")
	var end: Dictionary = sender.end_packet(frozen)
	check(end.ok and _consume(receiver,_wire(end.packet),2).status=="ready","matching END permits exact baseline")
	var ready: Dictionary = receiver.take_ready()
	check(ready.ok and ready.data.blocks[0]==0x01010203 and ready.tick==0 and ready.map_sequence==0,"ready data preserves frozen content and barrier")
	check(_cleared(receiver) and not receiver.take_ready().ok,"take_ready releases transfer ownership exactly once")
	sender.cancel(); check(sender.begin_packet()==null and not sender.next_chunk().ok and sender.get_stats().retained_map_bytes==0,"cancelled sender releases frozen packed allocation")

func _test_two_replicas() -> void:
	var authority: DATA = _data()
	var sender: TRANSFER.BaselineSender = _sender(authority)
	var begin: PROTOCOL.Packet = _wire(sender.begin_packet())
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	check(chunks.size()==3 and chunks[0].payload.data.size()==PROTOCOL.CHUNK_BYTES and chunks[1].payload.data.size()==PROTOCOL.CHUNK_BYTES,"lazy chunks include boundaries splitting 4-byte cells")
	var transactions: Array[Dictionary] = []
	transactions.append(authority.set_block(Vector3i(3,2,7),0x0199aabb,{"tick":100,"actor_id":4,"action_id":10,"transaction_id":21}))
	transactions.append(authority.set_block(Vector3i(10,1,10),0,{"tick":101,"actor_id":4,"action_id":11,"transaction_id":22}))
	transactions.append(authority.set_block(Vector3i(3,2,7),0x01ccbbaa,{"tick":102,"actor_id":4,"action_id":12,"transaction_id":23}))
	check(transactions[1].changes.size()==4 and transactions[1].changes[1].flags==1,"authority includes collapsed cells in its transaction")
	var end: PROTOCOL.Packet = _wire(sender.end_packet(authority).packet)
	check(end.payload.hash!=begin.payload.hash and end.payload.map_sequence==3,"END hash is edited barrier, BEGIN hash is original baseline")
	var a: TRANSFER = _join(begin); var b: TRANSFER = _join(begin)
	check(_consume(a,chunks[0],1).ok and _consume(a,end,2).ok,"END can precede remaining bulk chunks and deltas")
	_feed_chunks(b,chunks,1)
	for transaction: Dictionary in transactions:
		for fragment: PROTOCOL.Packet in _fragments(transaction):
			check(_consume(a,fragment,3).ok and _consume(b,fragment,2).ok,"both replicas accept attributed whole deltas")
	check(a.get_stats().retained_changes==6 and a.get_stats().staged_map_bytes==0,"deltas stay buffered while A's baseline is incomplete")
	for index: int in range(1,chunks.size()): check(_consume(a,chunks[index],4).ok,"remaining A chunks complete staged barrier")
	check(_consume(b,end,3).ok,"B receives END after baseline and deltas")
	var a_ready: Dictionary = a.take_ready(); var b_ready: Dictionary = b.take_ready()
	check(a_ready.ok and b_ready.ok,"both cross-socket delivery orders reach ready")
	if not a_ready.ok or not b_ready.ok: return
	check(a_ready.data.blocks==authority.blocks and b_ready.data.blocks==authority.blocks and a_ready.hash==b_ready.hash,"two replicas converge exactly with authoritative collapse and repaint")
	check(a_ready.tick==102 and a_ready.data.last_tick==102 and a_ready.map_sequence==3,"ready barrier includes final transaction tick")
	check(_cleared(a) and _cleared(b),"ready joins release chunks and retained changes")
	var large: Dictionary = _large_transaction(authority,3000,4,103)
	check(authority.apply_transaction(large).ok,"authority applies large authored system edit")
	var fragments: Array[PROTOCOL.Packet] = _fragments(large)
	check(fragments.size()==2,"3000 changes are sent as two lazy fragments")
	for replica: DATA in [a_ready.data,b_ready.data]:
		var assembler: TRANSFER.TransactionAssembler = TRANSFER.TransactionAssembler.new()
		check(assembler.reset(7,3,replica.dimensions,102).ok,"live assembler binds installed replica barrier")
		var before: PackedInt32Array = replica.blocks.duplicate()
		var first: Dictionary = assembler.push(fragments[0],0)
		check(first.ok and not first.get("complete",false) and replica.blocks==before and replica.map_sequence==3,"partial live transaction does not mutate map")
		var final: Dictionary = assembler.push(fragments[1],1)
		check(final.ok and final.complete and final.transaction.actor_id==4 and final.transaction.action_id==24,"full assembly preserves attributed identity")
		check(replica.apply_transaction(final.transaction).ok and replica.blocks==authority.blocks and replica.map_sequence==4,"atomic live application converges to authority")
		check(assembler.get_stats().changes==0 and assembler.get_stats().wire_bytes==0,"completed assembler releases partial retention")
		assembler.cancel()
	var isolated: Dictionary = TRANSFER.make_delta_sender(large)
	large.changes[0].after=0x01ffffff
	check(isolated.sender.next_fragment().packet.payload.changes[0].after!=0x01ffffff,"delta sender freezes records before exposing fragments")
	isolated.sender.cancel(); check(not isolated.sender.next_fragment().ok and isolated.sender.get_stats().retained_changes==0,"delta sender cancel releases records")

func _test_baseline_failures() -> void:
	var data: DATA = _data(); data.last_tick=10
	var sender: TRANSFER.BaselineSender = _sender(data)
	var begin: PROTOCOL.Packet = sender.begin_packet()
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	var end: PROTOCOL.Packet = sender.end_packet(data).packet
	var active: PackedInt32Array = data.blocks.duplicate()
	for kind: int in [PROTOCOL.Kind.MAP_CHUNK,PROTOCOL.Kind.MAP_END]:
		var empty: TRANSFER = TRANSFER.new()
		check(not _consume(empty,chunks[0] if kind==PROTOCOL.Kind.MAP_CHUNK else end,0).ok and _cleared(empty),"non-BEGIN packet cannot allocate or join")
	for alteration: String in ["duplicate","order","snapshot","epoch","size","tick","sequence","truncated"]:
		var receiver: TRANSFER = _join(begin)
		var bad: PROTOCOL.Packet = _clone(chunks[0])
		match alteration:
			"duplicate": check(_consume(receiver,chunks[0],1).ok,"duplicate fixture first chunk accepted")
			"order": bad=_clone(chunks[1])
			"snapshot": bad.payload.snapshot_id+=1
			"epoch": bad.epoch+=1
			"size": bad.payload.total_size+=1
			"tick": bad.tick+=1
			"sequence": bad.sequence+=1
			"truncated": bad.payload.data=bad.payload.data.slice(0,bad.payload.data.size()-1)
		check(not _consume(receiver,bad,2).ok and _cleared(receiver),"invalid chunk %s clears every retained buffer" % alteration)
		check(data.blocks==active,"chunk failure never changes authority/active map")
	var duplicate_begin: TRANSFER = _join(begin)
	check(_consume(duplicate_begin,chunks[0],1).ok,"duplicate BEGIN fixture retains chunk")
	check(not _consume(duplicate_begin,begin,2).ok and _cleared(duplicate_begin),"duplicate BEGIN cannot overwrite an in-flight transfer")
	var compressed: PROTOCOL.Packet = _clone(begin); compressed.payload.compression=1
	var unsupported: TRANSFER = TRANSFER.new()
	check(not _consume(unsupported,_wire(compressed),0).ok and unsupported.get_stats().error.contains("unsupported") and _cleared(unsupported),"reserved Zstd fails explicitly before baseline allocation")
	var wrong_hash: PROTOCOL.Packet = _clone(begin); wrong_hash.payload.hash[0]^=1
	var corrupt_hash: TRANSFER = _join(wrong_hash)
	for index: int in range(chunks.size()):
		var accepted: Dictionary = _consume(corrupt_hash,chunks[index],1)
		check(accepted.ok if index<chunks.size()-1 else not accepted.ok,"BEGIN SHA verified only after all chunks")
	check(_cleared(corrupt_hash),"baseline hash failure frees staged bytes")
	var corrupt_data: TRANSFER = _join(begin)
	for index: int in range(chunks.size()):
		var chunk: PROTOCOL.Packet = _clone(chunks[index])
		if index==0: chunk.payload.data[3]^=1
		var accepted: Dictionary = _consume(corrupt_data,chunk,1)
		check(accepted.ok if index<chunks.size()-1 else not accepted.ok,"corrupted canonical byte cannot pass original baseline hash")
	check(_cleared(corrupt_data),"corrupt raw baseline releases all buffers")
	var invalid_chunks: Array[PROTOCOL.Packet] = []
	var bytes: PackedByteArray = PackedByteArray()
	for chunk: PROTOCOL.Packet in chunks:
		var changed: PROTOCOL.Packet = _clone(chunk)
		if invalid_chunks.is_empty(): changed.payload.data[0]=2
		invalid_chunks.append(changed); bytes.append_array(changed.payload.data)
	var context: HashingContext = HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	var invalid_begin: PROTOCOL.Packet = _clone(begin); invalid_begin.payload.hash=context.finish()
	var invalid_color: TRANSFER = _join(invalid_begin)
	for index: int in range(invalid_chunks.size()):
		var accepted: Dictionary = _consume(invalid_color,invalid_chunks[index],1)
		check(accepted.ok if index<invalid_chunks.size()-1 else not accepted.ok,"canonical colors checked even when raw hash matches")
	check(_cleared(invalid_color) and data.blocks==active,"invalid canonical baseline never replaces existing map")
	for alteration: String in ["snapshot","epoch","sequence","tick","hash"]:
		var receiver: TRANSFER = _join(begin); _feed_chunks(receiver,chunks)
		var bad: PROTOCOL.Packet = _clone(end)
		match alteration:
			"snapshot": bad.payload.snapshot_id+=1
			"epoch": bad.epoch+=1
			"sequence": bad.sequence+=1
			"tick": bad.tick-=1
			"hash": bad.payload.hash[0]^=1
		check(not _consume(receiver,bad,2).ok and _cleared(receiver),"invalid END %s cannot release a ready map" % alteration)
	var waiting: TRANSFER = _join(begin)
	var future: PROTOCOL.Packet = _clone(end); future.payload.map_sequence=1; future.sequence=1
	check(_consume(waiting,future,1).ok,"early END can wait for missing ordered transaction")
	_feed_chunks(waiting,chunks,2)
	check(waiting.get_stats().status=="receiving" and not waiting.take_ready().ok,"hash match cannot bypass missing barrier delta")
	check(not _consume(waiting,future,3).ok and _cleared(waiting),"duplicate END clears pending barrier")

func _test_transaction_failures() -> void:
	var data: DATA = _data()
	var large: Dictionary = _large_transaction(data,3000)
	var fragments: Array[PROTOCOL.Packet] = _fragments(large)
	for alteration: String in ["order","duplicate","actor","action","transaction","tick","epoch","header","sequence","dimensions","cross_duplicate"]:
		var assembler: TRANSFER.TransactionAssembler = TRANSFER.TransactionAssembler.new()
		check(assembler.reset(7,0,data.dimensions).ok,"hostile assembler fixture armed")
		var bad: PROTOCOL.Packet = _clone(fragments[1])
		if alteration!="order": check(assembler.push(fragments[0],0).ok,"first fragment retained without map mutation")
		match alteration:
			"duplicate": bad=_clone(fragments[0])
			"actor": bad.payload.actor_id+=1
			"action": bad.payload.action_id+=1
			"transaction": bad.payload.transaction_id+=1
			"tick": bad.tick+=1
			"epoch": bad.epoch+=1
			"header": bad.sequence+=1
			"sequence": bad.payload.map_sequence+=1; bad.sequence+=1
			"dimensions": bad.payload.dimensions=Vector3i(33,8,32)
			"cross_duplicate": bad.payload.changes[0]=fragments[0].payload.changes[0].duplicate()
		check(not assembler.push(bad,1).ok and assembler.get_stats().changes==0 and not assembler.get_stats().armed,"invalid fragment %s is terminal and frees partial records" % alteration)
	for alteration: String in ["duplicate","floor","noop","collapse","too_many"]:
		var bad: Dictionary = large.duplicate(true)
		match alteration:
			"duplicate": bad.changes[-1]=bad.changes[0].duplicate()
			"floor": bad.changes[0].cell=Vector3i(0,0,0)
			"noop": bad.changes[0].after=bad.changes[0].before
			"collapse": bad.changes[0].flags=1
			"too_many": bad.changes.resize(TRANSFER.MAX_BUFFERED_CHANGES+1)
		check(not TRANSFER.make_delta_sender(bad).ok,"full transaction %s rejected before fragment generator allocation" % alteration)
	var conflict: Dictionary = large.duplicate(true); conflict.changes[-1].before=0x01abcdef
	var conflicting: Array[PROTOCOL.Packet] = _fragments(conflict)
	var assembler: TRANSFER.TransactionAssembler = TRANSFER.TransactionAssembler.new(); assembler.reset(7,0,data.dimensions)
	check(assembler.push(conflicting[0],0).ok,"before conflict is not falsely decided without map")
	var complete: Dictionary = assembler.push(conflicting[1],1)
	var before: PackedInt32Array = data.blocks.duplicate()
	check(complete.ok and complete.complete,"complete transaction is structurally valid before map comparison")
	check(not data.apply_transaction(complete.transaction).ok and data.blocks==before and data.map_sequence==0,"before-color conflict rejects all 3000 changes atomically")
	var sender: TRANSFER.BaselineSender = _sender(data)
	var receiver: TRANSFER = _join(sender.begin_packet())
	for fragment: PROTOCOL.Packet in conflicting: check(_consume(receiver,fragment,1).ok,"join buffers structurally valid conflict before baseline")
	var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	for index: int in range(chunks.size()):
		var result: Dictionary = _consume(receiver,chunks[index],2)
		check(result.ok if index<chunks.size()-1 else not result.ok,"join discovers conflict when baseline becomes available")
	check(_cleared(receiver) and data.blocks==before,"join conflict clears private stage and preserves active map")
	var pending: TRANSFER = _join(sender.begin_packet())
	check(_consume(pending,fragments[0],1).ok,"pending barrier fixture partial transaction")
	var end: PROTOCOL.Packet = sender.end_packet(data).packet
	end.payload.map_sequence=1; end.sequence=1; end.tick=9
	check(not _consume(pending,end,2).ok and _cleared(pending),"END tick cannot precede an already received partial transaction")
	var whole: Array[PROTOCOL.Packet] = _fragments(_large_transaction(data,1))
	for regressing_tick: bool in [false,true]:
		var complete_assembler: TRANSFER.TransactionAssembler = TRANSFER.TransactionAssembler.new(); complete_assembler.reset(7,0,data.dimensions)
		check(complete_assembler.push(whole[0],0).get("complete",false),"complete duplicate/gap fixture accepts initial transaction")
		var bad: PROTOCOL.Packet = _clone(whole[0])
		if regressing_tick: bad.sequence=2; bad.payload.map_sequence=2; bad.tick=9
		check(not complete_assembler.push(bad,1).ok and not complete_assembler.get_stats().armed,"complete duplicate or later tick regression is rejected")
	var mismatch: TRANSFER.TransactionAssembler = TRANSFER.TransactionAssembler.new(); mismatch.reset(7,0,data.dimensions)
	check(mismatch.push(fragments[0],0).ok,"total-change identity fixture starts")
	var changed_count: PROTOCOL.Packet = _clone(fragments[1]); changed_count.payload.total_changes+=1
	changed_count.payload.changes.append(_extra_change(data,3000))
	check(PROTOCOL.encode(changed_count).ok and not mismatch.push(changed_count,1).ok,"codec-valid changed total count cannot replace transaction identity")

func _extra_change(data: DATA, index: int) -> Dictionary:
	var y: int = index%(data.dimensions.y-1)+1
	var column: int = index/(data.dimensions.y-1)
	var cell: Vector3i = Vector3i(column%data.dimensions.x,y,column/data.dimensions.x)
	return {"cell":cell,"before":data.get_block(cell),"after":0x01112233,"flags":0}

func _test_budgets_and_lifecycle() -> void:
	var data: DATA = _data(); var sender: TRANSFER.BaselineSender = _sender(data)
	var begin: PROTOCOL.Packet = sender.begin_packet(); var chunks: Array[PROTOCOL.Packet] = _chunks(sender)
	var transaction: Dictionary = _large_transaction(data,3000)
	var fragments: Array[PROTOCOL.Packet] = _fragments(transaction)
	var count: TRANSFER = _join(begin,{"max_buffered_changes":2048})
	check(not _consume(count,fragments[0],1).ok and _cleared(count),"declared whole transaction count capped before retaining first fragment")
	var byte: TRANSFER = _join(begin,{"max_buffered_bytes":100})
	var small: Array[PROTOCOL.Packet] = _fragments(_large_transaction(data,3))
	check(not _consume(byte,small[0],1).ok and _cleared(byte),"encoded header plus change bytes enforce retention budget")
	for by_changes: bool in [false,true]:
		var receiver: TRANSFER = _join(begin,{"max_buffered_changes":3} if by_changes else {"max_transactions":1})
		var first: Dictionary = _large_transaction(data,2)
		var second: Dictionary = first.duplicate(true); second.map_sequence=2; second.transaction_id=102; second.tick=11
		for change: Dictionary in second.changes: change.before=change.after; change.after=0x01aabbcc
		check(_consume(receiver,_fragments(first)[0],1).ok,"first whole transaction retained within join budget")
		check(not _consume(receiver,_fragments(second)[0],2).ok and _cleared(receiver),"aggregate %s budget is not reset for each transaction" % ("change" if by_changes else "transaction"))
	for invalid: Dictionary in [{"max_buffered_bytes":TRANSFER.MAX_BUFFERED_BYTES+1},{"max_buffered_changes":32769},{"max_transactions":129},{"timeout_ms":99},{"timeout_ms":600001},{"timeout_ms":false},{"unknown":1}]:
		check(not TRANSFER.new().configure(invalid).ok,"invalid join configuration rejected")
	var timeout: TRANSFER = _join(begin,{"timeout_ms":100})
	check(_consume(timeout,chunks[0],1).ok and _consume(timeout,fragments[0],2).ok,"timeout fixture retains chunks and partial delta")
	check(not timeout.poll(100).ok and _cleared(timeout),"absolute transfer deadline clears every pending buffer")
	var partial: TRANSFER.TransactionAssembler = TRANSFER.TransactionAssembler.new(); partial.timeout_ms=100; partial.reset(7,0,data.dimensions)
	check(partial.push(fragments[0],0).ok and not partial.poll(100).ok and partial.get_stats().changes==0,"standalone partial delta has its own bounded deadline")
	for bad_clock: Variant in [-2,0,TRANSFER.MAX_CLOCK_MS+1,1.0,false]:
		var receiver: TRANSFER = _join(begin)
		check(_consume(receiver,chunks[0],1).ok,"clock fixture contains retained bytes")
		check(not receiver.poll(bad_clock).ok and _cleared(receiver),"negative, regressing, overflowing or noninteger clocks rejected")
	var reset: TRANSFER = _join(begin)
	check(_consume(reset,chunks[0],1).ok and _consume(reset,fragments[0],2).ok,"reset fixture has both baseline and partial records")
	check(reset.reset(8).ok and _cleared(reset),"epoch reset releases all previous transfer state")
	check(not _consume(reset,begin,0).ok and _cleared(reset),"old epoch BEGIN cannot join new match")
	check(reset.reset(7).ok and _consume(reset,begin,0).ok,"explicit reset can start a fresh accepted transfer")
	reset.cancel("disconnect"); check(_cleared(reset) and not _consume(reset,chunks[0],1).ok,"disconnect cancellation releases and prevents stale packets")
	check(not reset.reset(-1).ok,"invalid expected epoch is rejected")
	var future: TRANSFER = _join(begin)
	var end: PROTOCOL.Packet = sender.end_packet(data).packet
	check(_consume(future,end,1).ok,"zero-delta barrier retained before chunks")
	check(not _consume(future,_fragments(_large_transaction(data,1))[0],2).ok and _cleared(future),"delta after declared barrier must be held by future live coordinator")
	var maximum: PROTOCOL.Packet = PROTOCOL.make_packet(PROTOCOL.Kind.MAP_BEGIN,{"snapshot_id":9,"dimensions":Vector3i(512,64,512),"compression":0,"compressed_size":PROTOCOL.MAX_MAP_BYTES,"uncompressed_size":PROTOCOL.MAX_MAP_BYTES,"chunk_count":ceili(float(PROTOCOL.MAX_MAP_BYTES)/PROTOCOL.CHUNK_BYTES),"map_sequence":0,"hash":PackedByteArray()},7,0,0)
	maximum.payload.hash=PackedByteArray(); maximum.payload.hash.resize(32)
	var largest: TRANSFER = TRANSFER.new()
	check(_consume(largest,_wire(maximum),0).ok and largest.get_stats().baseline_bytes==0,"64MiB descriptor accepted without preallocating a complete raw buffer")
	check(largest.poll(239999).ok and not largest.poll(240000).ok and _cleared(largest),"production default deadline permits a bounded240second large-map join")
	largest.reset(); check(largest.configure({"timeout_ms":600000}).ok,"coordinator may raise deadline within finite maximum")
	check(_consume(largest,maximum,0).ok,"maximum-size descriptor can restart after explicit reset")
	largest.cancel(); check(_cleared(largest),"maximum-size pending transfer cancels without retained memory")
	maximum.payload.compressed_size+=1
	var oversized: TRANSFER = TRANSFER.new()
	check(not _consume(oversized,maximum,0).ok and _cleared(oversized),"size above64MiB rejected before any baseline allocation")

func _benchmark_large_map() -> void:
	var metrics: Dictionary = {"engine":Engine.get_version_info().string,"dimensions":"512x64x512","raw_bytes":PROTOCOL.MAX_MAP_BYTES,"timing_unit":"microseconds","sample_ranges":10}
	var started: int = Time.get_ticks_usec()
	var data: DATA = DATA.new(); data.clear(Vector3i(512,64,512),7)
	metrics["packed_map_allocate_us"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	var preparation: Dictionary = TRANSFER.prepare_sender(data,9)
	metrics["frozen_clone_job_setup_us"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec(); data.blocks[0]=0x01010203
	metrics["first_live_write_after_clone_us"]=Time.get_ticks_usec()-started
	metrics["frozen_copy_independent"]=preparation.job._data.blocks[0]==0
	data.blocks[0]=0
	var total_us: int = 0; var maximum_us: int = 0
	for sample: int in range(10):
		started=Time.get_ticks_usec(); preparation.job.advance()
		var elapsed: int = Time.get_ticks_usec()-started
		total_us+=elapsed; maximum_us=maxi(maximum_us,elapsed)
	metrics["hash_range_mean_us"]=total_us/10; metrics["hash_range_max_us"]=maximum_us
	preparation.job.cancel()
	var scalar_us: int = 0; var native_us: int = 0; var exact: bool = true
	for sample: int in range(10):
		var offset: int = sample*PROTOCOL.CHUNK_BYTES
		started=Time.get_ticks_usec(); var scalar: PackedByteArray = _scalar_snapshot_range(data,offset,PROTOCOL.CHUNK_BYTES)
		scalar_us+=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec(); var native: PackedByteArray = data.snapshot_range(offset,PROTOCOL.CHUNK_BYTES)
		native_us+=Time.get_ticks_usec()-started; exact=exact and scalar==native
	metrics["scalar_snapshot_range_mean_us"]=scalar_us/10; metrics["native_snapshot_range_mean_us"]=native_us/10; metrics["native_snapshot_exact"]=exact
	var bytes: PackedByteArray = PackedByteArray(); started=Time.get_ticks_usec(); bytes.resize(PROTOCOL.MAX_MAP_BYTES)
	metrics["raw_buffer_allocate_us"]=Time.get_ticks_usec()-started
	var decoder: TRANSFER.SnapshotDecodeJob = TRANSFER.SnapshotDecodeJob.new()
	decoder._start(bytes,{"dimensions":data.dimensions,"epoch":7,"map_sequence":0,"tick":0})
	started=Time.get_ticks_usec(); decoder.advance()
	metrics["first_decode_us"]=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec(); decoder.advance()
	metrics["next_decode_range_us"]=Time.get_ticks_usec()-started
	var decode_total_us: int = metrics.first_decode_us+metrics.next_decode_range_us
	var decode_max_us: int = maxi(metrics.first_decode_us,metrics.next_decode_range_us)
	var decode_steps: int = 2; var decode_max_step: int = 1
	while decoder.get_stats().status=="decoding" and decode_steps<6000:
		started=Time.get_ticks_usec(); decoder.advance(); var elapsed: int = Time.get_ticks_usec()-started
		decode_steps+=1; decode_total_us+=elapsed
		if elapsed>decode_max_us: decode_max_us=elapsed; decode_max_step=decode_steps
	metrics["full_decode_steps"]=decode_steps; metrics["full_decode_mean_us"]=decode_total_us/decode_steps
	metrics["full_decode_max_us"]=decode_max_us; metrics["full_decode_max_step"]=decode_max_step; metrics["full_decode_total_us"]=decode_total_us
	var complete: Dictionary = decoder.take_data()
	metrics["full_decode_exact"]=complete.get("ok",false) and complete.data.blocks==data.blocks
	var private_data: DATA = complete.get("data")
	decoder.cancel(); bytes=PackedByteArray()
	var changes: Array[Dictionary] = []
	for index: int in range(32768): changes.append(_extra_change(data,index))
	var transaction: Dictionary = {"epoch":7,"map_sequence":1,"transaction_id":1,"tick":1,"actor_id":0,"action_id":0,"dimensions":data.dimensions,"changes":changes}
	data.set_journal_budget(0,0,0)
	started=Time.get_ticks_usec(); var applied: Dictionary = data.apply_transaction(transaction)
	metrics["atomic_apply_32768_us"]=Time.get_ticks_usec()-started; metrics["atomic_apply_ok"]=applied.ok
	var apply_job: TRANSFER.TransactionApplyJob = TRANSFER.TransactionApplyJob.new()
	apply_job._start(private_data,transaction)
	var validate_total: int = 0; var validate_max: int = 0; var validate_steps: int = 0
	var write_total: int = 0; var write_max: int = 0; var write_steps: int = 0
	while apply_job.get_stats().status in ["validate","write"] and validate_steps+write_steps<200:
		var phase: String = apply_job.get_stats().status
		started=Time.get_ticks_usec(); apply_job.advance(); var elapsed: int = Time.get_ticks_usec()-started
		if phase=="validate": validate_total+=elapsed; validate_max=maxi(validate_max,elapsed); validate_steps+=1
		else: write_total+=elapsed; write_max=maxi(write_max,elapsed); write_steps+=1
	metrics["private_validate_unit_mean_us"]=validate_total/maxi(validate_steps,1); metrics["private_validate_unit_max_us"]=validate_max
	metrics["private_write_unit_mean_us"]=write_total/maxi(write_steps,1); metrics["private_write_unit_max_us"]=write_max
	metrics["private_apply_total_us"]=validate_total+write_total; metrics["private_apply_units"]=validate_steps+write_steps
	metrics["private_apply_exact"]=apply_job.get_stats().status=="ready" and private_data.blocks==data.blocks and private_data.map_sequence==data.map_sequence
	print("MAP_TRANSFER_BENCHMARK: "+JSON.stringify(metrics))

func _scalar_snapshot_range(data: DATA, byte_offset: int, byte_count: int) -> PackedByteArray:
	# Pre-optimization BE algorithm retained only as an independent timing/golden.
	var output: PackedByteArray = PackedByteArray(); output.resize(byte_count)
	var source: int = byte_offset; var written: int = 0
	while written<byte_count:
		var packed: int = data.blocks[source/4]
		if not DATA.valid_color(packed): return PackedByteArray()
		var remainder: int = source%4; var count: int = mini(4-remainder,byte_count-written)
		for byte: int in range(count): output[written+byte]=(packed>>((3-remainder-byte)*8))&255
		written+=count; source+=count
	return output
