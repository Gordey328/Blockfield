extends SceneTree

const DATA = preload("res://world/voxel_data.gd")
const TITLE := "res://assets/openspades/maps/Title.vxl"
const RED := 0x01cc2211
const BLUE := 0x011133dd
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func fresh(size: Vector3i = Vector3i(8,8,8), match_epoch: int = 7) -> RefCounted:
	var value: RefCounted = DATA.new()
	check(value.clear(size,match_epoch) == OK,"pure map clear")
	return value

func unchanged(value: RefCounted, transaction: Dictionary, label: String) -> void:
	var bytes: PackedByteArray = value.snapshot_bytes()
	var sequence: int = value.map_sequence
	var stats: Dictionary = value.get_journal_stats()
	var result: Dictionary = value.apply_transaction(transaction)
	check(not result.ok and value.snapshot_bytes() == bytes and value.map_sequence == sequence and value.get_journal_stats() == stats,label)

func bridge() -> RefCounted:
	var value: RefCounted = fresh()
	value.seed_box(Vector3i(0,0,0),Vector3i(8,2,8),RED)
	value.seed_box(Vector3i(2,2,3),Vector3i(3,5,4),RED)
	value.seed_box(Vector3i(2,4,3),Vector3i(6,5,4),BLUE)
	return value

func query_checks() -> void:
	var child_count: int = root.get_child_count()
	var value: RefCounted = fresh()
	check(value is RefCounted and not value.is_class("Node") and root.get_child_count() == child_count,"map creates no scene or physics nodes")
	check(value.water_level == 1.0 and value.wade_origin_level == 2.0,"pure native water/wade metadata")
	value.seed_box(Vector3i(3,1,3),Vector3i(4,4,4),0x000000)
	check(value.get_block(Vector3i(3,2,3)) == 0,"zero is air")
	value.seed_box(Vector3i(3,1,3),Vector3i(4,4,4),0x01000000)
	check(value.get_block(Vector3i(3,2,3)) == 0x01000000,"solid black distinct from air")
	check(value.index(Vector3i(1,2,3)) == 2+8*(1+8*3),"Y-fast storage index")
	check(value.get_block(Vector3i(-1,2,3)) == 0 and value.get_block(Vector3i(8,2,3)) == 0,"bounded voxel queries")
	check(value.clip_box(Vector3(-1,4,3)) and not value.clip_world(Vector3(-1,4,3)),"source horizontal box/world boundary distinction")
	check(value.clip_box(Vector3(3,-1,3)) and value.clip_world(Vector3(3,-1,3)),"source lower map boundary")
	check(not value.clip_box(Vector3(3,8,3)) and not value.clip_world(Vector3(3,8,3)),"source above-map boundary")
	check(value.clip_box(Vector3(3,0,3)) and value.clip_world(Vector3(3,0,3)),"lowest layer aliases second bottom layer")
	check(value.column_top(3+8*3,7) == Vector2i(0x01000000,3),"top column query without Image")
	check(value.column_top(-1,7) == Vector2i(0,-1),"invalid column is empty")
	var hit: Dictionary = value.cast_voxel(Vector3(0.5,2.5,3.5),Vector3.RIGHT,10)
	check(hit.hit and hit.cell == Vector3i(3,2,3) and hit.normal == Vector3i.LEFT and hit.position == Vector3(3,2.5,3.5),"DDA exact entry face")
	hit = value.cast_voxel(Vector3(-2,2.5,3.5),Vector3.RIGHT,10)
	check(hit.hit and hit.cell == Vector3i(3,2,3),"DDA starts outside map")
	check(not value.cast_voxel(Vector3.ZERO,Vector3.ZERO,10).hit and not value.cast_voxel(Vector3.ZERO,Vector3.RIGHT,-1).hit,"degenerate DDA")
	check(not value.cast_voxel(Vector3(INF,0,0),Vector3.RIGHT,10).hit,"nonfinite ray rejected")
	check(not value.set_block(Vector3i(3,0,3),RED).ok and value.map_sequence == 0,"immutable lower layer")
	check(value.set_block(Vector3i(3,1,3),0).ok,"spade may remove second lower layer")
	var invalid: RefCounted = DATA.new()
	check(invalid.clear(Vector3i(513,64,512),7) == ERR_INVALID_PARAMETER and invalid.blocks.is_empty(),"dimensions validated before allocation")
	check(invalid.clear(Vector3i(8,8,8),0) == ERR_INVALID_PARAMETER and invalid.blocks.is_empty(),"positive epoch required")
	check(not invalid.set_block(Vector3i(2,2,2),RED).ok,"uninitialized map rejects actions")

func transaction_checks() -> void:
	var authority: RefCounted = bridge()
	var replica: RefCounted = fresh()
	check(replica.load_snapshot_bytes(authority.snapshot_bytes(),authority.dimensions,7,0) == OK,"replica baseline installed")
	var cuts: Array[Vector3i] = [Vector3i(2,2,3)]
	var transaction: Dictionary = authority.remove_blocks(cuts,false,{"tick":40,"actor_id":3,"action_id":90,"transaction_id":11})
	check(transaction.ok and transaction.changed and transaction.map_sequence == 1 and transaction.epoch == 7 and transaction.tick == 40,"one edit/collapse commits one map sequence")
	check(transaction.actor_id == 3 and transaction.action_id == 90 and transaction.transaction_id == 11,"action identity retained")
	check(transaction.changes.size() == 6 and transaction.collapse_groups.size() == 1,"support cut returns direct edit plus entire unsupported group")
	check(transaction.changes[0].flags == 0 and transaction.collapse_groups[0].cells.size() == 5 and transaction.collapse_groups[0].colors.has(BLUE),"collapse retains original colors separate from terrain")
	var collapsed: int = 0
	for change: Dictionary in transaction.changes:
		if change.flags == 1:
			collapsed += 1
		check(authority.get_block(change.cell) == change.after,"terrain authority reflects transaction")
	check(collapsed == 5,"wire collapse flags match group")
	var result: Dictionary = replica.apply_transaction(transaction)
	check(result.ok and replica.blocks == authority.blocks and result.collapse_groups.size() == 1 and result.collapse_groups[0].cells.size() == 5,"replica applies authority changes and cosmetic group")
	unchanged(replica,transaction,"duplicate transaction rejected atomically")
	var noop: Dictionary = authority.set_block(Vector3i(1,1,1),RED,{"tick":41,"actor_id":3})
	check(noop.ok and not noop.changed and authority.map_sequence == 1 and authority.last_tick == 40,"no-op consumes no map sequence or tick")
	check(not authority.set_block(Vector3i(1,2,1),RED,{"tick":39}).ok and authority.map_sequence == 1,"regressed authoritative tick rejected")
	check(not authority.set_block(Vector3i(1,2,1),RED,{"tick":40.0}).ok,"float metadata rejected")
	check(not authority.set_block(Vector3i(1,2,1),RED,{1:3}).ok,"non-text metadata key rejected without error")
	check(not authority.set_block(Vector3i(1,2,1),RED,{"unknown":3}).ok,"unknown metadata rejected")
	check(not authority.set_block(Vector3i(1,2,1),RED,{"transaction_id":0}).ok,"wire transaction identity must be positive")
	var gap: Dictionary = transaction.duplicate(true)
	gap.map_sequence = 3
	unchanged(replica,gap,"sequence gap requires resync")
	gap.map_sequence = 2
	gap.epoch = 8
	unchanged(replica,gap,"wrong epoch rejected")
	gap.epoch = 7
	gap.dimensions = Vector3i(8,7,8)
	unchanged(replica,gap,"dimension mismatch rejected")
	var valid: Dictionary = authority.set_block(Vector3i(1,2,1),BLUE,{"tick":41,"actor_id":3,"action_id":91})
	var corrupt: Dictionary = valid.duplicate(true)
	corrupt.changes.append({"cell":Vector3i(4,2,4),"before":BLUE,"after":RED,"flags":0})
	unchanged(replica,corrupt,"late before-color conflict does not commit first record")
	corrupt = valid.duplicate(true)
	corrupt.changes.append(corrupt.changes[0].duplicate())
	unchanged(replica,corrupt,"duplicate cells rejected before any mutation")
	for after: int in [-1,0x00012345,0x02000000,0x100000000]:
		corrupt = valid.duplicate(true)
		corrupt.changes[0].after = after
		unchanged(replica,corrupt,"noncanonical network color %d" % after)
	corrupt = valid.duplicate(true)
	corrupt.changes[0].flags = 2
	unchanged(replica,corrupt,"unknown flags rejected")
	corrupt = valid.duplicate(true)
	corrupt.changes[0].flags = 1
	unchanged(replica,corrupt,"placement cannot be collapse")
	corrupt = valid.duplicate(true)
	corrupt.changes[0].cell = Vector3i(1,0,1)
	unchanged(replica,corrupt,"remote floor mutation rejected")
	corrupt = valid.duplicate(true)
	corrupt.tick = 39
	unchanged(replica,corrupt,"remote tick regression rejected")
	corrupt = valid.duplicate(true)
	corrupt.changes[0].before = 0.0
	unchanged(replica,corrupt,"typed before color required")
	check(replica.apply_transaction(valid).ok and replica.blocks == authority.blocks,"valid action succeeds after rejected malformed actions")
	# Deliberately unsupported native editor voxel: replica must not decide a
	# second collapse merely because it receives a neighboring removal.
	var no_support: RefCounted = fresh()
	no_support.seed_box(Vector3i(3,4,3),Vector3i(5,5,4),RED)
	var primary_only: Dictionary = {"epoch":7,"map_sequence":1,"transaction_id":1,"tick":0,"actor_id":0,"action_id":0,"dimensions":no_support.dimensions,"changes":[{"cell":Vector3i(3,4,3),"before":RED,"after":0,"flags":0}]}
	check(no_support.apply_transaction(primary_only).ok and no_support.get_block(Vector3i(4,4,3)) == RED,"replica never reruns support decisions")
	var blast: RefCounted = fresh(Vector3i(10,10,10))
	blast.seed_box(Vector3i.ZERO,Vector3i(10,8,10),RED)
	var exploded: Dictionary = blast.explode(Vector3(4.5,4.5,4.5))
	check(exploded.changes.size() == 27 and exploded.collapse_groups.is_empty(),"source grenade removes exactly 3x3x3")
	exploded = blast.explode(Vector3(4.5,1.5,4.5))
	check(blast.get_block(Vector3i(4,0,4)) == RED and blast.get_block(Vector3i(4,1,4)) == RED,"grenade protects two lowest layers")
	check(not blast.explode(Vector3(NAN,0,0)).ok,"nonfinite explosion rejected")

func snapshot_checks() -> void:
	var value: RefCounted = fresh(Vector3i(2,2,2))
	value.blocks[0] = 0x01000000
	value.blocks[1] = 0x01010203
	value.blocks[2] = 0x01ffffff
	var bytes: PackedByteArray = value.snapshot_bytes()
	check(bytes.slice(0,16) == PackedByteArray([1,0,0,0,1,1,2,3,1,255,255,255,0,0,0,0]),"snapshot BE golden includes black and Y-fast columns")
	check(bytes.size() == 32,"snapshot exact schema byte count")
	for offset: int in range(5):
		check(value.snapshot_range(offset,9) == bytes.slice(offset,offset+9),"unaligned snapshot byte range %d" % offset)
	check(value.snapshot_range(-1,4).is_empty() and value.snapshot_range(31,2).is_empty(),"snapshot ranges bounded")
	var frozen: RefCounted = value.frozen_copy()
	var baseline: PackedByteArray = frozen.snapshot_bytes()
	var first: PackedByteArray = frozen.snapshot_range(0,7)
	check(value.set_block(Vector3i(0,1,1),RED,{"tick":1}).ok,"live action while snapshot in progress")
	first.append_array(frozen.snapshot_range(7,25))
	check(first == baseline and value.snapshot_bytes() != baseline,"explicit packed snapshot duplicate remains immutable across live edit")
	check(frozen.map_sequence == 0 and frozen.last_tick == 0 and frozen.epoch == 7,"snapshot freezes sequence/tick/epoch")
	check(not frozen.set_block(Vector3i(1,1,1),BLUE).ok and frozen.clear(Vector3i(1,1,1),8) == ERR_UNAUTHORIZED,"frozen mutation methods reject")
	frozen.seed_box(Vector3i.ZERO,frozen.dimensions,BLUE)
	check(frozen.snapshot_bytes() == baseline,"frozen bootstrap rejects writes")
	var replica: RefCounted = fresh(Vector3i(1,1,1))
	check(replica.load_snapshot_bytes(first,frozen.dimensions,7,0) == OK,"assembled frozen baseline installed")
	var history: Dictionary = value.transactions_since(frozen.map_sequence)
	check(history.ok and history.transactions.size() == 1 and replica.apply_transaction(history.transactions[0]).ok and replica.blocks == value.blocks,"baseline plus journal catches up to identical map")
	var prior: PackedByteArray = replica.snapshot_bytes()
	var prior_epoch: int = replica.epoch
	var prior_seq: int = replica.map_sequence
	var corrupted: PackedByteArray = prior.duplicate()
	corrupted[corrupted.size()-4] = 2
	check(replica.load_snapshot_bytes(corrupted,replica.dimensions,8,9) == ERR_INVALID_DATA and replica.snapshot_bytes() == prior and replica.epoch == prior_epoch and replica.map_sequence == prior_seq,"late invalid snapshot color leaves entire previous map intact")
	check(replica.load_snapshot_bytes(prior.slice(0,prior.size()-1),replica.dimensions,8,9) == ERR_INVALID_DATA and replica.snapshot_bytes() == prior,"truncated snapshot rejected atomically")
	check(replica.load_snapshot_bytes(prior,replica.dimensions,0,9) == ERR_INVALID_DATA,"zero snapshot epoch rejected")
	check(replica.load_snapshot_bytes(prior,Vector3i(513,64,512),8,9) == ERR_INVALID_DATA,"oversized descriptor rejected before allocation")
	check(replica.load_snapshot_bytes(prior,replica.dimensions,8,0,20) == OK and replica.epoch == 8 and replica.map_sequence == 0 and replica.last_tick == 20 and replica.get_journal_stats().transactions == 0,"new epoch baseline resets journal and installs barrier tick")
	value.blocks[0] = 0x02000000
	check(value.snapshot_bytes().is_empty(),"export refuses noncanonical legacy storage")

func journal_checks() -> void:
	var value: RefCounted = fresh()
	value.set_journal_budget(142,2,10)
	var one: Dictionary = value.set_block(Vector3i(1,2,1),RED,{"tick":1})
	value.set_block(Vector3i(2,2,1),RED,{"tick":2})
	var stats: Dictionary = value.get_journal_stats()
	check(stats.transactions == 2 and stats.wire_bytes == 142 and stats.changes == 2,"journal exact 15-byte records plus fragment/envelope budget")
	one.changes[0].after = BLUE
	var history: Dictionary = value.transactions_since(0)
	check(history.transactions[0].changes[0].after == RED,"returned action cannot mutate retained journal")
	history.transactions[0].changes[0].after = BLUE
	check(value.transactions_since(0).transactions[0].changes[0].after == RED,"returned history cannot mutate retained journal")
	value.set_block(Vector3i(3,2,1),RED,{"tick":3})
	check(not value.transactions_since(0).ok and value.transactions_since(1).transactions.size() == 2,"evicted join baseline reports gap and exact retained suffix")
	check(value.transactions_since(3).ok and value.transactions_since(3).transactions.is_empty(),"caught-up journal suffix is empty")
	check(not value.transactions_since(4).ok and not value.transactions_since(-1).ok,"invalid history cursor rejected")
	value.set_journal_budget(100000,20,1)
	check(value.get_journal_stats().changes == 1 and value.get_journal_stats().transactions == 1,"journal also bounded by total record count")
	value.set_journal_budget(0)
	check(value.get_journal_stats().transactions == 0 and not value.transactions_since(2).ok,"zero journal requires fresh baseline")
	var collapse: RefCounted = bridge()
	collapse.set_journal_budget(100000,20,2)
	var cuts: Array[Vector3i] = [Vector3i(2,2,3)]
	check(collapse.remove_blocks(cuts).changed and collapse.map_sequence == 1 and collapse.get_journal_stats().transactions == 0 and not collapse.transactions_since(0).ok,"oversized transaction commits terrain but invalidates retained history")
	value.map_sequence = DATA.MAX_UINT32
	check(not value.set_block(Vector3i(5,2,5),BLUE).ok,"sequence must rebase before u32 overflow")

func fixture_checks() -> void:
	var lab: RefCounted = DATA.new()
	check(lab.generate_lab(12) == OK and lab.epoch == 12 and lab.map_sequence == 0 and lab.get_journal_stats().transactions == 0,"server can bootstrap exact offline lab without renderer")
	check(lab.get_block(Vector3i(48,3,70)) == 0x01668d57 and lab.get_block(Vector3i(48,4,70)) == 0,"lab spawn floor and clear firing lane")
	check(lab.get_block(Vector3i(75,0,75)) == 0x0179694c and lab.get_block(Vector3i(75,1,75)) == 0 and lab.get_block(Vector3i(75,3,75)) == 0,"lab native water pool")
	check(lab.get_block(Vector3i(20,11,57)) == 0x018cb8cd,"lab destructible bridge layout")
	var value: RefCounted = DATA.new()
	var started: int = Time.get_ticks_usec()
	var error: Error = value.load_vxl_bytes(FileAccess.get_file_as_bytes(TITLE),15)
	check(error == OK and value.dimensions == Vector3i(512,64,512) and value.epoch == 15,"genuine committed native Title VXL decoded by pure data")
	var occupied: int = 0
	for color: int in value.blocks:
		if color != 0:
			occupied += 1
	check(occupied == 3778939,"native Title occupancy fixture")
	var frozen: RefCounted = value.frozen_copy()
	var range_started: int = Time.get_ticks_usec()
	var chunk: PackedByteArray = frozen.snapshot_range(16346,16346)
	check(chunk.size() == 16346,"native baseline emits canonical unaligned 16,346-byte chunk")
	print("VOXEL DATA PERF: Title load/count %0.1fms, snapshot chunk %0.3fms" % [float(range_started-started)/1000.0,float(Time.get_ticks_usec()-range_started)/1000.0])
	var old_blocks: PackedInt32Array = value.blocks
	check(value.load_vxl_bytes(PackedByteArray([0,0,0]),16) != OK and value.blocks == old_blocks and value.epoch == 15,"malformed VXL leaves current data and epoch intact")
	var bytes: PackedByteArray = lab.encode_vxl()
	var roundtrip: RefCounted = DATA.new()
	check(not bytes.is_empty() and roundtrip.load_vxl_bytes(bytes,20) == OK,"lab export remains native padded VXL")
	check(roundtrip.get_block(Vector3i(20,11,57)) == lab.get_block(Vector3i(20,11,57)) and roundtrip.get_block(Vector3i(75,1,75)) == 0,"VXL shared export preserves bridge and pool")

func run() -> void:
	query_checks()
	transaction_checks()
	snapshot_checks()
	packed_snapshot_checks()
	journal_checks()
	fixture_checks()
	print("VOXEL DATA TESTS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)

func packed_snapshot_checks() -> void:
	var value: RefCounted = fresh(Vector3i(32,8,32))
	for cell: int in range(value.blocks.size()):
		value.blocks[cell]=0 if cell%5==0 else 0x01000000|((cell*0x10203)&0xffffff)
	var expected: PackedByteArray = PackedByteArray()
	expected.resize(value.blocks.size()*4)
	for byte: int in range(expected.size()): expected[byte]=(value.blocks[byte/4]>>((3-byte%4)*8))&255
	check(DATA.packed_byte_order() in [0,1,2],"packed runtime byte-order probe has a bounded result")
	for offset: int in [0,1,2,3,16345,16346,16347,expected.size()-4,expected.size()-1]:
		for count: int in [1,2,3,4,16346]:
			var length: int = mini(count,expected.size()-offset)
			check(value.snapshot_range(offset,length)==expected.slice(offset,offset+length),"native snapshot matches independent scalar bytes at offset%d length%d" % [offset,length])
	check(value.snapshot_range(expected.size(),0).is_empty() and value.snapshot_range(0,-1).is_empty(),"empty-end and negative native range semantics preserved")
	var first: PackedByteArray = value.snapshot_range(0,4); first[0]=255
	check(value.snapshot_range(0,4)==expected.slice(0,4),"returned byte buffer cannot alter packed map")
	for invalid: int in [-1,0x00ffffff,0x02000000,0x7fffffff]:
		var prior: int = value.blocks[4090]
		value.blocks[4090]=invalid
		check(value.snapshot_range(4090*4+1,1).is_empty(),"partial byte cannot hide invalid covering cell%d" % invalid)
		check(value.snapshot_range(4090*4-1,2).is_empty(),"native range validates malformed trailing partial cell")
		check(value.snapshot_range(4090*4+4,4)==expected.slice(4090*4+4,4090*4+8),"excluded malformed neighbor does not poison valid range")
		value.blocks[4090]=prior
