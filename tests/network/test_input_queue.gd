extends SceneTree
const QUEUE = preload("res://network/input_queue.gd")
const P = preload("res://network/protocol.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("INPUT QUEUE: "+message)
func batch(sequence: int, tick: int, count: int = 1, generation: int = 3, epoch: int = 7) -> BlockfieldProtocol.Packet:
	var records: Array = []
	for index in range(count):
		records.append({"input_sequence":sequence+index,"input_tick":tick+index,"buttons":16,"tool":255,"weapon":255,
			"move_x":0.0,"move_z":-1.0,"yaw":0.0,"pitch":0.0})
	return P.make_packet(P.Kind.INPUT_BATCH,{"records":records},epoch,tick+count-1,generation)
func _run() -> void:
	var queue := QUEUE.new()
	check(queue.reset(7,3,100),"trusted owner clock")
	check(not queue.reset(0,3,100) and queue.epoch == 7,"invalid reset atomic")
	check(not queue.accept(batch(1,100,1,2),100).ok,"old life cannot be relabeled")
	check(not queue.accept(batch(1,100,1,3,6),100).ok,"old epoch cannot enqueue")
	check(not queue.accept(batch(1,100),99).ok,"receive does not advance server clock")
	check(not queue.accept(batch(2,100),100).ok,"initial sequence gap")
	check(not queue.accept(batch(1,84),100).ok,"too-late command rejected")
	check(not queue.accept(batch(1,109),100).ok,"future command bounded")
	var malformed := batch(1,100)
	malformed.payload.records[0].move_x = 1.0
	check(not queue.accept(malformed,100).ok,"diagonal speed exploit rejected")
	var atomic := batch(1,106,4)
	check(not queue.accept(atomic,100).ok and queue.get_stats().pending == 0,"late invalid record rejects entire batch")
	check(queue.accept(batch(1,100,8),100).ok,"eight commands admitted")
	check(not queue.accept(batch(1,100),100).ok,"replay rejected")
	check(not queue.accept(batch(9,107),100).ok,"input clock replay across batches rejected")
	for tick in range(101,109):
		var result := queue.take(tick)
		check(result.ok and result.command.sequence == tick-100 and result.input_ack == tick-100,"one command per authoritative step")
		check(queue.get_stats().pending == 108-tick,"batch never runs catch-up simulation")
	check(not queue.take(108).ok and not queue.take(110).ok,"duplicate/skipped server ticks rejected")
	for tick in range(109,114):
		var result := queue.take(tick)
		check(result.ok and result.command == null and not result.clear_controls,"held state retained only within lease")
	check(queue.take(114).clear_controls,"six-tick input lease clears held controls")
	check(queue.input_ack == 8,"missing commands cannot fabricate acknowledgment")
	check(queue.accept(batch(9,122),114).ok,"bounded future command admitted")
	for tick in range(115,122):
		check(queue.take(tick).command == null,"future command waits for server time")
	check(queue.take(122).command.sequence == 9,"future command consumed exactly once when eligible")
	check(queue.reset(7,4,122),"respawn clears queue and sequence")
	check(queue.get_stats().pending == 0 and queue.input_ack == 0,"respawn no stale history")
	check(not queue.accept(batch(10,123,1,3),122).ok,"old generation after respawn")
	check(queue.accept(batch(1,123,1,4),122).ok,"new generation restarts sequence")
	check(queue.take(123).command.spawn_generation == 4,"generation remains attributed")
	queue.reset(7,3,100)
	check(queue.accept(batch(1,85,8),100).ok,"exact late window accepted")
	check(not queue.take(102).ok,"invalid step leaves queue untouched")
	check(not queue.take(101).ok and queue.needs_resync and queue.get_stats().pending == 0,"backlog expiry explicit resync, never hidden skip")
	check(not queue.accept(batch(9,102),101).ok,"resync prevents more admitted commands")
	queue.reset(8,3,5,41)
	check(queue.accept(batch(42,6,1,3,8),5).ok and queue.take(6).input_ack == 42,"trusted rebase can preserve acknowledged sequence")
	queue.reset(7,3,100)
	var owned := batch(1,101)
	check(queue.accept(owned,100).ok,"owned command fixture")
	owned.payload.records[0].buttons = 0
	check(queue.take(101).command.buttons == 16,"receive owns command copy")
	print("INPUT QUEUE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
