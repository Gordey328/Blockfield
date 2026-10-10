extends SceneTree
const HISTORY = preload("res://network/hit_history.gd")
const DATA = preload("res://world/voxel_data.gd")
const PLAYER = preload("res://simulation/player_state.gd")
const HITS = preload("res://gameplay/lab_hit_volumes.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions+=1
	if not condition: failures+=1; push_error("HIT_HISTORY: "+message)
func _run() -> void:
	_test_source_cover_and_lives()
	_test_transactions_and_collapse()
	_test_record_failures()
	_test_capacity_and_lifecycle()
	_test_overflow_and_reverse_chain()
	_test_shared_query_context()
	_test_cached_identity_invalidation()
	print("HIT_HISTORY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)

func _map() -> DATA:
	var data: DATA = DATA.new(); check(data.clear(Vector3i(32,8,32),7)==OK,"authority fixture initialized")
	data.seed_box(Vector3i.ZERO,Vector3i(32,2,32),0x01334455)
	return data
func _actor(id: int = 9, feet: Vector3 = Vector3(12,2,5)) -> PLAYER:
	var actor: PLAYER = PLAYER.new(id,"Actor",7)
	actor.spawn_generation=1; actor.team=1; actor.health=100; actor.motion.feet_position=feet
	return actor
func _actors(actor: PLAYER) -> Array[SharedPlayerState]: return [actor]
func _frame(history: HISTORY, tick: int, data: DATA, actors: Array[SharedPlayerState], transactions: Array[Dictionary] = []) -> Dictionary:
	data.last_tick=tick
	for actor: SharedPlayerState in actors: actor.last_tick=tick
	return history.record_frame(tick,data,actors,transactions)
func _history(data: DATA, window_ticks: int = 15, changes: int = 32768, bytes: int = 8*1024*1024) -> HISTORY:
	var history: HISTORY = HISTORY.new()
	check(history.configure(window_ticks,changes,bytes).ok and history.reset(7,data).ok,"history bounded and pinned to authority")
	return history
func _pose(poses: Array, id: int) -> Dictionary:
	for pose: Dictionary in poses:
		if pose.id==id: return pose
	return {}
func _visible(result: Dictionary, origin: Vector3, direction: Vector3, id: int = 9) -> Dictionary:
	if not result.get("ok",false): return {"hit":false,"blocked":false}
	var pose: Dictionary = _pose(result.actors,id)
	if pose.is_empty() or not pose.alive or not pose.connected or not pose.pose_valid or not result.query.is_valid(): return {"hit":false,"blocked":false}
	var actor_hit: Dictionary = HITS.cast_ray(origin,direction,pose.feet,pose.yaw,pose.crouch,pose.pitch,100.0)
	var cover: Dictionary = result.query.cast_voxel(origin,direction,100.0)
	var blocked: bool = cover.hit and actor_hit.hit and origin.distance_to(cover.position)<=actor_hit.distance
	return {"hit":actor_hit.hit and not blocked,"blocked":blocked,"part":actor_hit.part,"distance":actor_hit.distance}

func _test_source_cover_and_lives() -> void:
	var data: DATA = _map(); data.seed_box(Vector3i(6,2,5),Vector3i(7,5,6),0x01aa6633)
	var target: PLAYER = _actor(); var actors: Array[SharedPlayerState] = _actors(target)
	var history: HISTORY = _history(data)
	check(_frame(history,0,data,actors).ok,"coherent initial actor+cover frame")
	var first_query: Dictionary = history.query_at(0,0)
	var origin: Vector3 = Vector3(1,4.35,5)
	var raw_hit: Dictionary = HITS.cast_ray(origin,Vector3.RIGHT,target.feet(),0,false,0,100)
	check(raw_hit.hit and raw_hit.part=="head" and is_equal_approx(raw_hit.distance,10.7),"source standing head ray golden distance10.7")
	check(first_query.ok and first_query.query.blocks.is_empty(),"historical query owns no packed64MiB baseline")
	check(_visible(first_query,origin,Vector3.RIGHT).blocked,"same-frame cover blocks original head volume")
	var removed: Dictionary = data.remove_blocks([Vector3i(6,4,5)],false,{"tick":1,"actor_id":4,"action_id":1})
	check(removed.ok and _frame(history,1,data,actors,[removed]).ok,"committed cover removal recorded")
	check(not first_query.query.is_valid(),"borrowed terrain query expires after authority advances")
	check(_visible(history.query_at(0,1),origin,Vector3.RIGHT).blocked,"rewound actor and rewound old cover agree")
	check(_visible(history.query_at(1,1),origin,Vector3.RIGHT).hit,"same ray hits after cover destruction")
	target.motion.feet_position=Vector3(12,2,9); target.motion.crouch=true
	check(_frame(history,2,data,actors).ok,"moving/crouching target frame recorded")
	check(_visible(history.query_at(1,2),origin,Vector3.RIGHT).hit and not _visible(history.query_at(2,2),origin,Vector3.RIGHT).hit,"historical target hit differs from current moved target")
	var crouch: Dictionary = _visible(history.query_at(2,2),Vector3(1,3.45,9),Vector3.RIGHT)
	check(crouch.hit and crouch.part=="head" and is_equal_approx(crouch.distance,10.7),"source crouched head ray golden survives public pose copy")
	var crouch_leg: Dictionary = _visible(history.query_at(2,2),Vector3(1,2.25,9),Vector3.RIGHT)
	check(crouch_leg.hit and crouch_leg.part=="legs","source crouched leg volume uses historical feet")
	target.health=0
	check(_frame(history,3,data,actors).ok,"death frame captured")
	target.spawn_generation=2; target.health=100; target.motion.crouch=false; target.motion.feet_position=Vector3(18,2,5)
	check(_frame(history,4,data,actors).ok,"new authoritative life captured")
	var old: Dictionary = history.query_at(1,4); var dead: Dictionary = history.query_at(3,4); var current: Dictionary = history.query_at(4,4)
	check(_pose(old.actors,9).spawn_generation==1 and _pose(dead.actors,9).spawn_generation==1 and not _pose(dead.actors,9).alive and _pose(current.actors,9).spawn_generation==2,"history copies exact death/respawn generations without rewriting old life")
	check(_visible(old,origin,Vector3.RIGHT).hit and not _visible(dead,origin,Vector3.RIGHT).hit,"dead historical pose is never a target")
	check(_pose(old.actors,9).spawn_generation!=target.spawn_generation,"caller can reject old-life hit against current generation")
	check(_pose(current.actors,9).physics_eye==target.motion.physics_eye() and _pose(current.actors,9).front==target.front(),"public source physics eye/front derived from captured pose")

func _test_transactions_and_collapse() -> void:
	var data: DATA = _map()
	data.seed_box(Vector3i(2,2,2),Vector3i(3,5,3),0x01000000)
	var history: HISTORY = _history(data); var actor: PLAYER = _actor(); var actors: Array[SharedPlayerState] = _actors(actor)
	check(_frame(history,0,data,actors).ok,"collapse fixture baseline")
	var cell: Vector3i = Vector3i(2,3,2)
	var repaint1: Dictionary = data.set_block(cell,0x01112233,{"tick":1,"actor_id":9,"action_id":1})
	var repaint2: Dictionary = data.set_block(cell,0x01445566,{"tick":1,"actor_id":9,"action_id":2})
	check(repaint1.ok and repaint2.ok and _frame(history,1,data,actors,[repaint1,repaint2]).ok,"same cell allowed in separate ordered transactions")
	var old: Dictionary = history.query_at(0,1); var current: Dictionary = history.query_at(1,1)
	check(old.ok and old.query.get_block(cell)==0x01000000 and current.query.get_block(cell)==0x01445566,"reverse chain restores before first repaint while latest keeps second")
	var removed: Dictionary = data.remove_blocks([Vector3i(2,2,2)],false,{"tick":2,"actor_id":9,"action_id":3})
	var collapsed: int = 0
	for change: Dictionary in removed.changes: if change.flags==1: collapsed+=1
	check(removed.ok and collapsed==2 and _frame(history,2,data,actors,[removed]).ok,"committed authority collapse flags recorded without replica support search")
	var rewound: Dictionary = history.query_at(1,2)
	check(rewound.query.get_block(Vector3i(2,2,2))==0x01000000 and rewound.query.get_block(cell)==0x01445566 and rewound.query.get_block(Vector3i(2,4,2))==0x01000000,"inverse overlay restores primary and collapsed cells together")
	check(rewound.query.clip_world(Vector3(2.1,3.1,2.1)) and not history.query_at(2,2).query.clip_world(Vector3(2.1,3.1,2.1)),"inherited ClipWorld dispatch uses historical get_block")
	var ray: Dictionary = rewound.query.cast_voxel(Vector3(0.5,3.5,2.5),Vector3.RIGHT,10)
	check(ray.hit and ray.cell==cell and ray.valid,"inherited DDA dispatch hits restored old cover")
	var source_ray: Dictionary = rewound.query.cast_source_ray(Vector3(0.5,3.5,2.5),Vector3.RIGHT,10)
	check(source_ray.hit and source_ray.cell==cell and source_ray.valid and source_ray.normal==Vector3i.LEFT,"source step-count ray also reads historical cover through its lease")
	check(rewound.query.get_block(Vector3i.ZERO)==data.get_block(Vector3i.ZERO) and rewound.query.get_block(Vector3i(-1,2,0))==0,"untouched cells/bounds preserve Data queries")
	var saved_blocks: PackedInt32Array = data.blocks.duplicate()
	check(not rewound.query.set_block(cell,0x01ffffff).ok and rewound.query.clear(Vector3i.ONE,9)==ERR_UNAUTHORIZED and data.blocks==saved_blocks,"query mutation methods cannot write authority")
	rewound.actors[0].feet=Vector3(99,99,99); rewound.actors[0].spawn_generation=100
	check(rewound.query._context.cells.is_read_only() and rewound.query._context.cells[cell].is_read_only(),"shared inverse timelines are recursively immutable")
	var again: Dictionary = history.query_at(1,2)
	check(_pose(again.actors,9).feet==actor.feet() and _pose(again.actors,9).spawn_generation==1 and again.query.get_block(cell)==0x01445566 and data.blocks==saved_blocks,"returned poses and shared read-only overlay preserve history and authority")
	removed.changes[0].before=0x01ffffff
	check(history.query_at(1,2).query.get_block(Vector3i(2,2,2))==0x01000000,"history owns copied receipt colors")
	data.last_tick=3
	check(not again.query.is_valid() and not again.query.cast_voxel(Vector3.ZERO,Vector3.RIGHT).valid and again.query.clip_world(Vector3(999,999,999)) and again.query.get_block(Vector3i(99,99,99))==0x01000000,"stale query reports invalid and fails closed")
	check(not again.query.cast_source_ray(Vector3.ZERO,Vector3.RIGHT).valid and not again.query.cast_source_ray_legacy(Vector3.ZERO,Vector3.RIGHT).valid,"both source ray APIs fail closed after historical lease revocation")
	check(not history.query_at(1,2).ok,"query refuses authority tick not yet recorded")

func _test_record_failures() -> void:
	for alteration: String in ["missing","sequence","tick","epoch","dimensions","after","before","duplicate","floor","color","collapse","identity"]:
		var data: DATA = _map(); var history: HISTORY = _history(data); var actors: Array[SharedPlayerState] = _actors(_actor())
		check(_frame(history,0,data,actors).ok,"malformed receipt fixture begins")
		var cell: Vector3i = Vector3i(4,2,4)
		var first: Dictionary = data.set_block(cell,0x01112233,{"tick":1,"actor_id":9,"action_id":1})
		check(first.ok and _frame(history,1,data,actors,[first]).ok,"known before-color fixture recorded")
		var second: Dictionary = data.set_block(cell,0x01445566,{"tick":2,"actor_id":9,"action_id":2})
		var receipts: Array[Dictionary] = [second.duplicate(true)]
		var bad: Dictionary = receipts[0]
		match alteration:
			"missing": receipts=[]
			"sequence": bad.map_sequence+=1
			"tick": bad.tick=1
			"epoch": bad.epoch=8
			"dimensions": bad.dimensions=Vector3i(33,8,32)
			"after": bad.changes[0].after=0x01aabbcc
			"before": bad.changes[0].before=0x01ffffff
			"duplicate": bad.changes.append(bad.changes[0].duplicate())
			"floor": bad.changes[0].cell=Vector3i(4,0,4)
			"color": bad.changes[0].before=-1
			"collapse": bad.changes[0].flags=1
			"identity": bad.actor_id=-1
		var authority: PackedInt32Array = data.blocks.duplicate()
		check(not _frame(history,2,data,actors,receipts).ok and history.get_stats().status=="invalid" and history.get_stats().frames==0 and history.get_stats().changes==0,"invalid committed %s clears history" % alteration)
		check(data.blocks==authority and not history.query_at(0,2).ok,"invalid history never rolls authority back or fabricates query")
	for invalid_pose: String in ["duplicate_id","epoch","generation","yaw","pitch","feet","health","future_actor_tick"]:
		var data: DATA = _map(); var history: HISTORY = _history(data); var actor: PLAYER = _actor(); var actors: Array[SharedPlayerState] = _actors(actor)
		check(_frame(history,0,data,actors).ok,"pose validation initial frame")
		actor.last_tick=1
		match invalid_pose:
			"duplicate_id": actors.append(actor.copy())
			"epoch": actor.match_epoch=8
			"generation": actor.spawn_generation=0
			"yaw": actor.yaw=NAN
			"pitch": actor.pitch=2.0
			"feet": actor.motion.feet_position=Vector3.INF
			"health": actor.health=101
			"future_actor_tick": actor.last_tick=2
		data.last_tick=1
		check(not history.record_frame(1,data,actors,[]).ok and not history.query_at(0,1).ok,"invalid public pose%s is not retained" % invalid_pose)
	var data: DATA = _map(); var actor: PLAYER = _actor(); var history: HISTORY = _history(data)
	check(_frame(history,0,data,_actors(actor)).ok,"generation regression baseline")
	actor.spawn_generation=2
	check(_frame(history,1,data,_actors(actor)).ok,"new observed generation accepted")
	actor.spawn_generation=1
	check(not _frame(history,2,data,_actors(actor)).ok,"generation regression cannot rewrite an old life")

func _test_capacity_and_lifecycle() -> void:
	var data: DATA = _map(); var actor: PLAYER = _actor(); var actors: Array[SharedPlayerState] = _actors(actor)
	var history: HISTORY = _history(data,3)
	check(_frame(history,0,data,actors).ok,"small window initial frame")
	for tick: int in range(1,25):
		var transaction: Dictionary = data.set_block(Vector3i(5,2,5),tick,{"tick":tick,"actor_id":9,"action_id":tick})
		check(transaction.ok and _frame(history,tick,data,actors,[transaction]).ok,"rolling history retains contiguous ticks")
		check(history.get_stats().frames<=4 and history.get_stats().changes<=3,"poses and inverse records evict together")
	check(history.query_at(21,24).ok and history.query_at(21,24).query.get_block(Vector3i(5,2,5))==0x01000015,"oldest retained map and pose remain queryable")
	check(not history.query_at(20,24).ok and not history.query_at(25,24).ok and not history.query_at(24,23).ok and not history.query_at(-1,24).ok,"expired/future/fabricatedcurrent/negative ticks rejected")
	var owned: Dictionary = history.query_at(21,24)
	history.cancel("shutdown")
	check(history.get_stats().frames==0 and history.get_stats().changes==0 and not owned.query.is_valid(),"cancel releases retained history and revokes borrowed query leases")
	check(history.reset(7,data).ok and not history.query_at(24,24).ok and _frame(history,24,data,actors).ok,"reset starts at pinned map tick without inventing earlier poses")
	check(not _frame(history,26,data,actors).ok and history.get_stats().status=="invalid","missing canonical tick invalidates history")
	for by_bytes: bool in [false,true]:
		var bounded_data: DATA = _map(); var bounded: HISTORY = _history(bounded_data,15,32768 if by_bytes else 2,141 if by_bytes else 8*1024*1024)
		check(_frame(bounded,0,bounded_data,actors).ok,"retention limit fixture")
		for tick: int in range(1,3):
			var transaction: Dictionary = bounded_data.set_block(Vector3i(tick,2,1),0x01010203,{"tick":tick})
			check(_frame(bounded,tick,bounded_data,actors,[transaction]).ok if not by_bytes or tick==1 else not _frame(bounded,tick,bounded_data,actors,[transaction]).ok,"exact retained byte/count budget applied")
		if not by_bytes:
			var overflow: Dictionary = bounded_data.set_block(Vector3i(3,2,1),0x01010203,{"tick":3})
			check(not _frame(bounded,3,bounded_data,actors,[overflow]).ok,"third retained change exceeds configured capacity")
		check(bounded.get_stats().status=="invalid" and bounded.get_stats().wire_bytes==0 and bounded.get_stats().frames==0,"overflow explicitly invalidates and clears history")
	var no_rewind: DATA = _map(); var current_only: HISTORY = _history(no_rewind,0)
	check(_frame(current_only,0,no_rewind,actors).ok and _frame(current_only,1,no_rewind,actors).ok and current_only.get_stats().frames==1 and not current_only.query_at(0,1).ok,"zero window permits current pose only")
	var maximum: DATA = _map(); var full_window: HISTORY = _history(maximum)
	for tick: int in range(20): check(_frame(full_window,tick,maximum,actors).ok,"full authoritative window contiguous")
	check(full_window.get_stats().frames==16 and full_window.query_at(4,19).ok and not full_window.query_at(3,19).ok,"maximum15tick rewind retains exactly16 frames")
	var inactive: PLAYER = _actor(3); inactive.team=2; inactive.health=0; inactive.motion.feet_position=Vector3(NAN,INF,-INF)
	check(_frame(full_window,20,maximum,_actors(inactive)).ok,"inactive nonfinite source spectator is normalized")
	var normalized: Dictionary = _pose(full_window.query_at(20,20).actors,3)
	check(not normalized.pose_valid and not normalized.alive and normalized.feet==Vector3.ZERO,"inactive normalized pose can never be hit")
	maximum.epoch=8; maximum.last_tick=21
	check(not full_window.record_frame(21,maximum,_actors(inactive),[]).ok and full_window.get_stats().frames==0,"epoch mutation clears old map and life history")
	for invalid: Vector3i in [Vector3i(-1,32768,8388608),Vector3i(16,32768,8388608),Vector3i(15,32769,8388608),Vector3i(15,32768,8388609),Vector3i(15,0,8388608),Vector3i(15,32768,0)]:
		check(not HISTORY.new().configure(invalid.x,invalid.y,invalid.z).ok,"invalid configured bounds rejected")
	var wrong_map: DATA = _map(); wrong_map.epoch=8
	check(not HISTORY.new().reset(7,wrong_map).ok and not HISTORY.new().reset(0,wrong_map).ok,"reset rejects mismatched/zero epoch")
	var custom: DATA = _map(); custom.water_level=1.123456789; custom.wade_origin_level=2.987654321
	var custom_history: HISTORY = _history(custom)
	check(_frame(custom_history,0,custom,actors).ok and custom_history.query_at(0,0).query.is_valid() and custom_history.query_at(0,0).query.water_level==custom.water_level,"query preserves finite water metadata without float32 truncation")

func _test_overflow_and_reverse_chain() -> void:
	var actors: Array[SharedPlayerState] = _actors(_actor())
	var exhausted: DATA = _map(); exhausted.map_sequence=HISTORY.U32_MAX
	var map_history: HISTORY = _history(exhausted)
	check(_frame(map_history,0,exhausted,actors).ok,"exhausted map sequence may describe current baseline")
	exhausted.map_sequence=0
	check(not _frame(map_history,1,exhausted,actors).ok and not map_history.query_at(0,1).ok,"map sequence wrap explicitly invalidates history")
	var clock_map: DATA = _map(); clock_map.last_tick=HISTORY.U32_MAX
	var tick_history: HISTORY = _history(clock_map)
	check(_frame(tick_history,HISTORY.U32_MAX,clock_map,actors).ok,"maximum canonical tick accepted once")
	check(not _frame(tick_history,HISTORY.U32_MAX+1,clock_map,actors).ok,"tick overflow requires reset instead of invented history")
	var data: DATA = _map(); var chain: HISTORY = _history(data)
	check(_frame(chain,0,data,actors).ok,"same-frame reverse-chain fixture")
	var first: Dictionary = data.set_block(Vector3i(3,2,3),0x01112233,{"tick":1})
	var second: Dictionary = data.set_block(Vector3i(3,2,3),0x01445566,{"tick":1})
	second.changes[0].before=0x01ffffff
	check(not _frame(chain,1,data,actors,[first,second]).ok,"different transactions may repeat cell only with consistent reverse colors")
	var bounded_data: DATA = _map(); var bounded: HISTORY = _history(bounded_data,15,1)
	check(_frame(bounded,0,bounded_data,actors).ok,"incoming count-cap baseline")
	var first_edit: Dictionary = bounded_data.set_block(Vector3i(1,2,1),0x01112233,{"tick":1})
	var second_edit: Dictionary = bounded_data.set_block(Vector3i(2,2,1),0x01112233,{"tick":1})
	check(not _frame(bounded,1,bounded_data,actors,[first_edit,second_edit]).ok and bounded.get_stats().changes==0,"whole incoming frame is bounded before retaining its full records")

func _test_shared_query_context() -> void:
	var data: DATA = _map(); var history: HISTORY = _history(data)
	var actor: PLAYER = _actor(); var actors: Array[SharedPlayerState] = _actors(actor)
	var cell: Vector3i = Vector3i(3,2,3)
	data.seed_box(cell,cell+Vector3i.ONE,0x01010203)
	check(_frame(history,0,data,actors).ok,"shared cache starts without invented poses")
	var first: Dictionary = data.set_block(cell,0x01445566,{"tick":1})
	var second: Dictionary = data.set_block(cell,0x01778899,{"tick":1})
	check(_frame(history,1,data,actors,[first,second]).ok,"shared timeline retains two ordered changes within one frame")
	var third: Dictionary = data.set_block(cell,0x01010203,{"tick":2})
	check(_frame(history,2,data,actors,[third]).ok,"shared timeline records return to identical old color")
	check(history.get_stats().cache_entries==0,"index is lazy before first query")
	var current_first: Dictionary = history.query_at(2,2)
	check(current_first.query.get_block(cell)==data.get_block(cell) and history.get_stats().cache_builds==0 and history.get_stats().cache_records==0,"current-map query does not build unused retained inverse terrain")
	var old: Dictionary = history.query_at(0,2)
	var middle: Dictionary = history.query_at(1,2)
	var latest: Dictionary = history.query_at(2,2)
	var shared: HISTORY.QueryContext = old.query._context
	check(is_same(shared,middle.query._context) and is_same(shared,latest.query._context),"different request ticks share one closed-tick index")
	check(old.query.get_block(cell)==0x01010203 and middle.query.get_block(cell)==0x01778899 and latest.query.get_block(cell)==data.get_block(cell),"binary timeline lookup selects exact frame sequence rather than matching color")
	check(shared.cells.is_read_only() and shared.cells[cell].is_read_only() and shared.cells[cell].size()==6,"shared index and repeated-cell sequence/before timeline frozen")
	check(history.get_stats().cache_builds==1 and history.get_stats().cache_hits==3 and history.get_stats().cache_cells==1 and history.get_stats().cache_records==3 and history.get_stats().cache_entries==1,"one cache counts every retained receipt only once")
	check(is_same(shared,current_first.query._context) and current_first.query.is_valid() and current_first.query.get_block(cell)==data.get_block(cell),"lazy immutable index installation leaves current-map lease semantics unchanged")
	old.actors[0].feet=Vector3.ONE*99
	check(_pose(middle.actors,9).feet==actor.feet(),"independent returned actor arrays do not alias")
	old.query.cancel()
	check(not old.query.is_valid() and middle.query.is_valid() and latest.query.is_valid() and shared.active and shared.records==3,"cancelling one lease cannot revoke independent leases or shared cache")
	var repeated: Dictionary = history.query_at(1,2)
	check(is_same(shared,repeated.query._context) and repeated.query.get_block(cell)==0x01778899 and history.get_stats().cache_builds==1,"query cancellation preserves subsequent same-context cache reuse")
	repeated.query.map_sequence=0
	check(not repeated.query.is_valid() and not repeated.query.cast_voxel(Vector3.ZERO,Vector3.RIGHT).valid and middle.query.is_valid(),"changing a lease frame identity cannot fabricate a different rewind frame")
	check(not history.query_at(3,2).ok and not history.query_at(1,1).ok and history.get_stats().cache_builds==1,"cache does not supply missing or fabricated current ticks")
	check(_frame(history,3,data,actors).ok,"next closed frame advances without terrain writes")
	check(not middle.query.is_valid() and not latest.query.is_valid() and not shared.active and shared.cells.is_empty() and shared.records==0,"record advancement revokes old contexts and releases change-sized storage even with retained leases")
	var next: Dictionary = history.query_at(1,3)
	check(not is_same(shared,next.query._context) and next.query.get_block(cell)==0x01778899 and history.get_stats().cache_builds==2,"new closed tick builds independent immutable context")
	var next_context: HISTORY.QueryContext = next.query._context
	check(history.reset(7,data).ok and not next.query.is_valid() and not next_context.active and next_context.cells.is_empty(),"reset on same authority identity revokes independent leases and cache")
	check(_frame(history,3,data,actors).ok,"fresh reset records current baseline only")
	var baseline: Dictionary = history.query_at(3,3)
	var empty_context: HISTORY.QueryContext = baseline.query._context
	history.cancel("test shutdown")
	check(not baseline.query.is_valid() and not empty_context.active and history.get_stats().cache_entries==0,"cancel clears shared context and all outstanding leases")

func _test_cached_identity_invalidation() -> void:
	for alteration: String in ["epoch","sequence","tick","dimensions","cells","water","wade"]:
		var data: DATA = _map(); var history: HISTORY = _history(data)
		var actors: Array[SharedPlayerState] = _actors(_actor())
		check(_frame(history,0,data,actors).ok,"cached identity fixture")
		var receipt: Dictionary = data.set_block(Vector3i(3,2,3),0x01112233,{"tick":1})
		check(_frame(history,1,data,actors,[receipt]).ok,"cached identity has actual inverse terrain")
		var borrowed: Dictionary = history.query_at(0,1)
		var shared: HISTORY.QueryContext = borrowed.query._context
		match alteration:
			"epoch": data.epoch+=1
			"sequence": data.map_sequence+=1
			"tick": data.last_tick+=1
			"dimensions": data.dimensions.x+=1
			"cells": data.blocks.resize(data.blocks.size()-1)
			"water": data.water_level+=.1
			"wade": data.wade_origin_level+=.1
		check(not borrowed.query.is_valid() and borrowed.query.get_block(Vector3i.ZERO)==0x01000000,"authority %s mutation invalidates every borrowed cache lease"%alteration)
		check(not history.query_at(0,1).ok and not shared.active and shared.cells.is_empty() and history.get_stats().cache_entries==0,"stale %s lookup never reuses or retains invalid context"%alteration)
	var data: DATA = _map(); var history: HISTORY = _history(data)
	var actors: Array[SharedPlayerState] = _actors(_actor())
	check(_frame(history,0,data,actors).ok,"unrecorded receipt fixture baseline")
	var before: Dictionary = history.query_at(0,0)
	var context: HISTORY.QueryContext = before.query._context
	var edit: Dictionary = data.set_block(Vector3i(4,2,4),0x01aabbcc,{"tick":1})
	check(edit.ok and not before.query.is_valid() and not history.query_at(0,0).ok and not context.active,"committed but unrecorded live edit invalidates old cache without guessing receipts")
	check(_frame(history,1,data,actors,[edit]).ok and history.query_at(0,1).query.get_block(Vector3i(4,2,4))==0,"valid committed receipt restores exact rewind after cache revocation")
	var valid: Dictionary = history.query_at(0,1)
	var valid_context: HISTORY.QueryContext = valid.query._context
	var next_edit: Dictionary = data.set_block(Vector3i(5,2,5),0x01020304,{"tick":2})
	next_edit.changes[0].after=0x01112233
	check(not _frame(history,2,data,actors,[next_edit]).ok and not valid.query.is_valid() and not valid_context.active and valid_context.cells.is_empty(),"invalid receipt clears shared cache rather than reusing previously valid history")
	# Full uint32 sequences must not be narrowed to signed Vector2i/float keys.
	var high_map: DATA = _map(); high_map.map_sequence=HISTORY.U32_MAX-2
	var high: HISTORY = _history(high_map)
	check(_frame(high,0,high_map,actors).ok,"high sequence baseline")
	var high_edit: Dictionary = high_map.set_block(Vector3i(6,2,6),0x01ffffff,{"tick":1})
	check(_frame(high,1,high_map,actors,[high_edit]).ok and high.query_at(0,1).query.get_block(Vector3i(6,2,6))==0 and high.query_at(1,1).query.get_block(Vector3i(6,2,6))==0x01ffffff,"shared timeline preserves full uint32 comparison near wrap")
	var bounded_map: DATA = _map(); var bounded: HISTORY = _history(bounded_map,15,1)
	check(_frame(bounded,0,bounded_map,actors).ok,"cached capacity baseline")
	var accepted_edit: Dictionary = bounded_map.set_block(Vector3i(7,2,7),0x01020304,{"tick":1})
	check(_frame(bounded,1,bounded_map,actors,[accepted_edit]).ok,"cache fits exact configured record budget")
	var accepted: Dictionary = bounded.query_at(0,1)
	var bounded_context: HISTORY.QueryContext = accepted.query._context
	var overflow: Dictionary = bounded_map.set_block(Vector3i(8,2,8),0x01020304,{"tick":2})
	check(not _frame(bounded,2,bounded_map,actors,[overflow]).ok and not accepted.query.is_valid() and not bounded_context.active and bounded_context.cells.is_empty() and bounded.get_stats().cache_entries==0,"retained record overflow revokes and releases populated cache")
