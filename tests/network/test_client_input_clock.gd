extends SceneTree
const CLOCK = preload("res://network/client_input_clock.gd")
var assertions := 0
var failures := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error("INPUT CLOCK: "+message)
func _initialize() -> void:
	var clock := CLOCK.new()
	check(clock.next_tick(1000000) == -1,"no command without confirmed authority")
	clock.observe(600,1000000)
	clock.sent_tick = 600
	for index in range(3):
		var tick := clock.next_tick(1000000)
		check(tick == 604+index,"same frame keeps distinct monotonic inputs with transit reserve")
		clock.commit(tick)
	# A 200ms dropped frame must skip wall ticks rather than continue tick604.
	clock.observe(612,1200000)
	check(clock.next_tick(1200000) == 616,"dropped callbacks do not leave command time behind")
	clock.commit(616)
	# A delayed snapshot cannot repeatedly restart or advance elapsed clock.
	clock.observe(615,1300000)
	check(clock.estimate(1300000) == 621,"slow snapshot delivery preserves elapsed authority estimate")
	check(clock.next_tick(1300000) == 622,"wire time ignores retimed pending replay")
	clock.commit(622)
	check(clock.next_tick(1500000) == -1,"stale authority stream stops input within original future window")
	check(clock.sent_tick == 622,"waiting leaves wire cursor untouched")
	clock.observe(630,1500000)
	check(clock.next_tick(1500000) == 634,"fresh authority resumes contiguous sequence with current tick")
	clock.reset()
	clock.observe(3,2500000)
	check(clock.next_tick(2500000) == 7,"new epoch or generation discards old clock")
	clock.commit(7)
	clock.observe(3,2550000)
	check(clock.latest_tick == 3 and clock.next_tick(2550000) == 10,"duplicate snapshot cannot reanchor clock")
	clock.observe(9,2600000)
	check(clock.next_tick(2600000) == 13,"newest snapshot advances ceiling without adding pending count")
	clock.reset()
	clock.observe(600,1000000)
	clock.commit(601)
	check(clock.next_tick(2000000) == -1,"authority pause cannot authorize local wall ticks")
	clock.observe(600,2050000)
	check(clock.next_tick(2050000) == -1,"duplicate state cannot masquerade as recovered authority")
	clock.observe(603,2100000)
	check(clock.next_tick(2100000) == 607,"new authority sample recovers after clock wait without permanent drift")
	clock.commit(607)
	check(clock.next_tick(2100000) == 608,"clock recovery retains strictly monotonic transmitted ticks")
	clock.reset()
	clock.observe(600,1000000)
	clock.commit(608)
	check(clock.next_tick(1000000) == -1,"full future window cannot submit a ninth frame command")
	clock.observe(601,1000000)
	check(clock.next_tick(1000000) == 609,"recovery cannot rewind last transmitted tick")
	clock.commit(609)
	check(clock.next_tick(1000000) == -1,"same-time recovery cannot exceed refreshed authority ceiling")
	clock.observe(602,1000000)
	check(clock.next_tick(1000000) == 610,"next snapshot releases only newly admitted tick")
	var input_before := clock.sent_tick
	check(clock.request_tick(1000000) == 605 and clock.sent_tick == input_before,"request clock neither uses replay nor consumes input cursor")
	check(clock.request_tick(2000000) == -1,"team and color requests wait through stale authority too")
	clock.observe(605,2000000)
	check(clock.request_tick(2000000) == 608 and clock.sent_tick == input_before,"request recovery retains independent input sequence")
	clock.reset()
	clock.observe(600,1000000)
	clock.commit(601)
	clock.next_tick(2000000)
	for frame in range(1,21):
		var authority_tick := 600+frame*3
		var now_us := 2000000+frame*50000
		clock.observe(authority_tick,now_us)
		var wire_tick := clock.next_tick(now_us)
		check(wire_tick == authority_tick+4,"continued20Hz snapshots do not recreate pre-pause wall drift")
		clock.commit(wire_tick)
	clock.reset()
	clock.observe(600,1000000)
	clock.observe_rtt(200.0)
	check(clock.next_tick(1000000) == 608,"measured round trip reserves bounded transit at latest snapshot")
	clock.commit(608)
	check(clock.next_tick(1000000) == -1,"RTT cannot authorize a ninth future tick")
	clock.observe_rtt(INF)
	clock.observe_rtt(NAN)
	clock.observe_rtt(-1.0)
	clock.observe(603,1050000)
	check(clock.next_tick(1050000) == 611,"invalid timing samples leave bounded measured reserve intact")
	clock.observe_rtt(0.0)
	check(clock.next_tick(1050000) == 609,"low RTT reduces reserve without rewinding sent cursor")
	clock.commit(609)
	clock.reset()
	clock.observe(3,2000000)
	check(clock.next_tick(2000000) == 7,"new life resets learned transit reserve")
	# A genuine received snapshot is six ticks old after100ms downward transit.
	# Returning another100ms later must not use that old received tick directly.
	clock.observe_rtt(200.0)
	var previous := 0
	for frame in range(20):
		var captured := 3+frame*3
		var received_us := 2000000+frame*50000
		clock.observe(captured,received_us)
		var wire := clock.next_tick(received_us)
		var arrival_tick := captured+12
		check(wire > previous and wire <= captured+8 and arrival_tick-wire <= 15,"delayed20Hz round trip retains admitted monotonic wire clock")
		clock.commit(wire)
		previous = wire
	print("INPUT CLOCK: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
