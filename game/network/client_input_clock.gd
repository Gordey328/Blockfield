extends RefCounted
## Wall time advances independently of dropped render/physics callbacks.
## Authority snapshots can advance this anchor, never repeatedly add replay depth.
const QUEUE = preload("res://network/input_queue.gd")
const INITIAL_TRANSIT_TICKS := 3
const MAX_TRANSIT_TICKS := QUEUE.MAX_FUTURE_TICKS-1
var latest_tick := -1
var sent_tick := -1
var _anchor_tick := -1
var _anchor_us := 0
var _waiting := false
var _transit_ticks := INITIAL_TRANSIT_TICKS

func reset() -> void:
	latest_tick = -1
	sent_tick = -1
	_anchor_tick = -1
	_anchor_us = 0
	_waiting = false
	_transit_ticks = INITIAL_TRANSIT_TICKS

func observe_rtt(rtt_ms: float) -> void:
	if not is_finite(rtt_ms) or rtt_ms < 0: return
	# A snapshot travels down, then its command travels back up. Reserve the
	# measured round trip, bounded by the unchanged authority future window.
	_transit_ticks = clampi(ceili(rtt_ms*.06),INITIAL_TRANSIT_TICKS,MAX_TRANSIT_TICKS)

func observe(tick: int, now_us: int) -> void:
	if tick <= latest_tick: return
	latest_tick = tick
	# After waiting, a genuinely newer snapshot is a fresh clock sample. A
	# paused authority must not leave a max-only wall anchor ahead forever.
	if _waiting or _anchor_tick < 0 or tick > estimate(now_us)-_transit_ticks:
		_anchor_tick = tick
		_anchor_us = now_us
	_waiting = false

func estimate(now_us: int) -> int:
	if _anchor_tick < 0: return -1
	return _anchor_tick + maxi(0,now_us-_anchor_us)*60/1000000 + _transit_ticks

func next_tick(now_us: int) -> int:
	if latest_tick < 0: return -1
	var candidate := maxi(sent_tick+1,maxi(latest_tick+1,estimate(now_us)+1))
	# A pause in authority or a stale inbound stream stops new intent. It cannot
	# expand the server window or synthesize a burst of skipped physics steps.
	_waiting = candidate > latest_tick+QUEUE.MAX_FUTURE_TICKS
	return -1 if _waiting else candidate

func request_tick(now_us: int) -> int:
	if latest_tick < 0: return -1
	var candidate := maxi(latest_tick,estimate(now_us))
	_waiting = candidate > latest_tick+QUEUE.MAX_FUTURE_TICKS
	return -1 if _waiting else candidate

func commit(tick: int) -> void:
	sent_tick = tick
