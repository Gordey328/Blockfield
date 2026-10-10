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
	var too_old := QUEUE.new()
	too_old.reset(7,3,300)
	check(not too_old.accept(batch(1,179),300).ok,"121-tick receive age exceeds bounded stale retirement window")
	check(not queue.accept(batch(1,109),100).ok,"future command bounded")
	var malformed := batch(1,100)
	malformed.payload.records[0].move_x = 1.0
	check(not queue.accept(malformed,100).ok,"diagonal speed exploit rejected")
	var atomic := batch(1,106,4)
	check(not queue.accept(atomic,100).ok and queue.get_stats().pending == 0,"ninth-tick future record rejects entire batch atomically")
	check(queue.accept(batch(1,100,8),100).ok,"eight commands admitted")
	check(not queue.accept(batch(1,100),100).ok,"replay rejected")
	check(not queue.accept(batch(9,107),100).ok,"input clock replay across batches rejected")
	for tick in range(101,109):
		var result := queue.take(tick)
		check(result.ok and result.command.sequence == tick-100 and result.input_ack == tick-100,"one command per authoritative step")
		check(queue.get_stats().pending == 108-tick,"batch never runs catch-up simulation")
		check(result.discarded == 0 and result.retired_ack == 0,"fresh command never reports a fabricated stale-retirement ACK")
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
	for tick in range(101,109):
		var boundary := queue.take(tick)
		check(boundary.ok and boundary.command != null and boundary.input_ack == tick-100 and boundary.input_tick == tick-16,"exact late boundary executes once against15tick closed history")
		check(boundary.discarded == 0 and not boundary.clear_controls,"closed S-15 boundary remains executable rather than stale retirement")
	check(not queue.needs_resync and queue.get_stats().pending == 0,"accepted lower boundary cannot falsely expire during next step")
	check(queue.accept(batch(9,109),108).ok and queue.take(109).input_ack == 9,"same-life input continues after lower boundary")
	queue.reset(7,3,100)
	for part in range(3):
		check(queue.accept(batch(1+part*8,85+part*8,8),100).ok,"mixed late/current/future batches fit original admitted window")
	for tick in range(101,125):
		var mixed := queue.take(tick)
		check(mixed.ok and mixed.command != null and mixed.input_ack == tick-100 and mixed.input_tick >= tick-1-QUEUE.MAX_LATE_TICKS,"monotonic mixed batch never ages outside15tick closed history")
		check(mixed.discarded == 0,"exactly admissible mixed queue does not skip any valid historical command")
	check(queue.get_stats().pending == 0 and not queue.needs_resync,"mixed admitted queue drains without stale execution or resync")
	queue.reset(8,3,5,41)
	check(queue.accept(batch(42,6,1,3,8),5).ok and queue.take(6).input_ack == 42,"trusted rebase can preserve acknowledged sequence")
	queue.reset(7,3,100)
	var owned := batch(1,101)
	check(queue.accept(owned,100).ok,"owned command fixture")
	owned.payload.records[0].buttons = 0
	check(queue.take(101).command.buttons == 16,"receive owns command copy")
	stale_boundaries()
	stale_and_fresh()
	stale_capacity_and_atomicity()
	print("INPUT QUEUE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func stale_boundaries() -> void:
	check(QUEUE.MAX_LATE_TICKS == 15 and QUEUE.MAX_STALE_TICKS == 120 and QUEUE.MAX_PENDING == 32,"execution history and bounded receive-age/capacity policies remain distinct")
	var queue := QUEUE.new()
	queue.reset(7,3,100)
	check(queue.accept(batch(1,84),100).ok,"S-16 command can be admitted for ACK retirement")
	var retired := queue.take(101)
	check(retired.ok and retired.command == null and retired.input_tick == -1,"S-16 command is never returned for authority execution")
	check(typeof(retired.discarded) == TYPE_INT and retired.discarded == 1 and retired.input_ack == 1 and retired.retired_ack == 1,"S-16 retirement reports bounded scalar count and actual input ACK")
	check(retired.clear_controls and not queue.needs_resync and queue.get_stats().pending == 0,"valid stale input releases held controls without disconnect/resync")
	check(not queue.accept(batch(1,84),101).ok,"retired input sequence cannot be replayed")
	check(queue.accept(batch(2,102),101).ok,"same owner/life resumes after an acknowledged stale command")
	var next := queue.take(102)
	check(next.ok and next.command.sequence == 2 and next.input_ack == 2 and next.retired_ack == 0 and next.discarded == 0,"fresh input follows stale ACK exactly once without another retirement")
	queue.reset(7,3,300)
	var lower := batch(1,180,8)
	for index in range(8):
		lower.payload.records[index].buttons = P.INPUT_BUTTON_MASK
		lower.payload.records[index].tool = index % 4
		lower.payload.records[index].weapon = index % 3
	check(queue.accept(lower,300).ok,"exact 120-tick oldest receive boundary remains valid")
	var all_actions := queue.take(301)
	check(all_actions.ok and all_actions.command == null and all_actions.input_tick == -1,"stale jump/crouch/sprint/sneak/fire/secondary/reload and tool/class actions cannot execute")
	check(all_actions.discarded == 8 and all_actions.retired_ack == 8 and all_actions.input_ack == 8 and all_actions.clear_controls,"all stale action intents retire in one bounded pass with controls released")
	check(queue.get_stats().pending == 0 and not queue.needs_resync,"all-action stale batch does not require owner resynchronization")
	queue.reset(7,3,300)
	var before := queue.get_stats()
	check(not queue.accept(batch(1,179),300).ok and queue.get_stats() == before,"age121 rejection leaves clock, ACK, sequence tail and queue intact")
	check(queue.accept(batch(1,180),300).ok,"rejected age121 packet does not consume the next valid sequence")

func stale_and_fresh() -> void:
	var queue := QUEUE.new()
	queue.reset(7,3,200)
	var packet := batch(1,182,8)
	for index in range(8):
		var record: Dictionary = packet.payload.records[index]
		if index < 3:
			record.buttons = P.INPUT_BUTTON_MASK
			record.tool = 3
			record.weapon = 2
		else:
			record.buttons = 0
			record.tool = 255
			record.weapon = 255
	check(queue.accept(packet,200).ok,"ordered stale prefix and valid S-15 suffix are admitted together")
	check(not queue.take(202).ok and queue.get_stats().pending == 8 and queue.input_ack == 0,"invalid authority step cannot retire any queued prefix")
	var mixed := queue.take(201)
	check(mixed.ok and mixed.discarded == 3 and mixed.retired_ack == 3 and mixed.input_ack == 4,"retired ACK is visible before the one fresh command final ACK")
	check(mixed.command != null and mixed.command.sequence == 4 and mixed.input_tick == 185,"one valid S-15 command can follow multiple retired records in the same step")
	check(mixed.command.buttons == 0 and mixed.command.tool == 255 and mixed.command.weapon == 255,"discarded stale action bits and selections cannot leak into fresh command")
	check(mixed.clear_controls and queue.get_stats().pending == 4 and not queue.needs_resync,"stale-prefix clearing remains explicit even when a fresh command follows")
	for tick in range(202,206):
		var fresh := queue.take(tick)
		check(fresh.ok and fresh.command != null and fresh.command.sequence == tick-197 and fresh.input_tick == tick-16,"remaining exact-boundary suffix advances one authority command per tick")
		check(fresh.discarded == 0 and fresh.retired_ack == 0 and fresh.input_ack == tick-197 and not fresh.clear_controls,"no second retirement or ACK jump occurs while suffix drains")
	check(queue.get_stats().pending == 0 and queue.input_ack == 8 and not queue.needs_resync,"mixed batch drains in order without stale execution or disconnect")
	queue.reset(7,3,400,40)
	check(queue.accept(batch(41,381,8),400).ok,"trusted rebase ACK can precede an ordered stale prefix")
	var rebased := queue.take(401)
	check(rebased.discarded == 4 and rebased.retired_ack == 44 and rebased.command.sequence == 45 and rebased.input_ack == 45,"retirement respects preserved acknowledged sequence instead of rebasing to zero")

func stale_capacity_and_atomicity() -> void:
	var queue := QUEUE.new()
	queue.reset(7,3,300)
	for part in range(4):
		check(queue.accept(batch(1+part*8,180+part*8,8),300).ok,"bounded32 stale actions can queue across ordered eight-record packets")
	var full := queue.get_stats()
	check(full.pending == 32 and full.tail_sequence == 32 and full.input_ack == 0,"queued stale history has a hard32 bound and no receive-time ACK")
	check(not queue.accept(batch(33,212),300).ok and queue.get_stats() == full,"33rd stale record is rejected atomically rather than permitting an unbounded discard loop")
	var all := queue.take(301)
	check(all.ok and all.command == null and all.discarded == 32 and all.retired_ack == 32 and all.input_ack == 32 and all.clear_controls,"one bounded take retires full32 queue without executing actions")
	check(queue.get_stats().pending == 0 and not queue.needs_resync,"capacity retirement releases slots without invalidating owner")
	check(queue.accept(batch(33,302),301).ok and queue.take(302).input_ack == 33,"capacity rejection leaves next sequence available after prefix retirement")
	queue.reset(7,3,300)
	check(queue.accept(batch(1,180,8),300).ok,"existing stale prefix retained for atomic failure fixtures")
	var before := queue.get_stats()
	check(not queue.accept(batch(9,306,4),300).ok and queue.get_stats() == before,"three valid future records cannot partially append before an invalid future9 record")
	check(not queue.accept(batch(9,188,1,2),300).ok and queue.get_stats() == before,"stale admission does not loosen authenticated spawn generation")
	check(not queue.accept(batch(9,188,1,3,6),300).ok and queue.get_stats() == before,"stale admission does not loosen match epoch")
	var malformed := batch(9,188)
	malformed.payload.records[0].buttons = P.INPUT_BUTTON_MASK + 1
	check(not queue.accept(malformed,300).ok and queue.get_stats() == before,"stale command still requires exact bounded action schema")
	check(not queue.accept(batch(1,180),300).ok and queue.get_stats() == before,"stale retransmission cannot duplicate pending sequence")
	check(not queue.accept(batch(9,188),299).ok and queue.get_stats() == before,"stale receive cannot forge or regress authority clock")
	var retired := queue.take(301)
	check(retired.ok and retired.discarded == 8 and retired.command == null and retired.input_ack == 8,"invalid packets leave only the original stale prefix to retire")
	check(queue.accept(batch(9,302),301).ok and queue.take(302).command.sequence == 9,"atomic validation failures never consume sequence or fresh execution capacity")
