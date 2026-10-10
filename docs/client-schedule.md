# Independent client/authority scheduling

`tests/network/test_client_schedule.gd` exercises one actual native Runtime and
two actual ClientReplicas over loopback WebSocket game/map sockets. The authority
has a monotonic 60 Hz deadline; the playing client's callback targets 24 Hz and
polls before submitting its physics-command burst. The observer uses a separate
polling path. The fixture loads no Main, preferences, renderer or audio.

The normal burst is two or three commands. A late callback catches up at most
eight commands and explicitly drops excess elapsed steps. It invokes only one
current callback, then schedules the next at `now + 1/24 s`; it does not replay
missed render callbacks immediately. The process-frame driver and OS timer add
jitter, so 24 Hz is the requested callback rate, not a measured rendering rate.

## Current clock and authority policy

`ClientInputClock` timestamps wire intent independently of prediction/replay.
It samples a strictly newer authority snapshot and advances a monotonic 60Hz
wall-time anchor through missed callbacks. Its estimate is
`anchor_tick + floor(max(0, now_us-anchor_us)*60/1_000_000) + transit_ticks`.
The transit reserve accounts for the complete measured RTT: the snapshot travels
downstream and its resulting command travels upstream. It is
`clamp(ceil(rtt_ms*0.06), 3, 7)` ticks; it starts at 3, and negative/nonfinite
RTT samples are ignored. This is a bounded scheduling reserve, not a latency
measurement or a guarantee that delayed input will arrive in time.

The next input tick is the maximum of `last_sent_tick+1`, `latest_tick+1` and
`estimate+1`. A next candidate beyond `latest_tick+8` waits for fresh authority;
waiting consumes no input sequence and adds no predicted command. A strictly
newer snapshot received after that wait resamples the anchor, even if the
authority paused; duplicate/older snapshots cannot recover it. Committed wire
ticks remain monotonic after reanchoring. Epoch/generation reset clears the
clock; same-life mode changes retain the transmitted sequence ACK barrier.
Team/color request timestamps use the same estimate/wait gate without
advancing the input sequence.

Replica polls before input and refuses to stamp input while transport incoming
events/socket packets remain, so a budgeted partial snapshot batch cannot become
the clock sample used for new intent. After successful `send`, it commits the
wire tick and calls `flush_outgoing()` before rendering. This flush does not
receive/reconcile packets halfway through prediction.

Authority identity `blockfield-source-v0.1.3-authority-4` intentionally separates
**receive admission** from **execution/rewind admission**. For the latest closed
authority tick `S`:

- INPUT_BATCH receive admission remains owner-bound, exact-schema,
  epoch/generation-bound, contiguous in sequence and strictly increasing in
  tick, with at most 32 pending records. Future ticks may not exceed `S+8`.
- `MAX_STALE_TICKS=120` permits ordered records as old as `max(0,S-120)` to enter
  that bounded queue solely so their exact sequence IDs can be acknowledged and
  retired. Records older than that still reject the stream. This changes the
  earlier receive-late-15 policy; it does not expand the shot-history window.
- On `take(S+1)`, the queue discards its bounded prefix with `input_tick < S-15`
  before selecting an executable command. Exactly `S-15` remains eligible at
  `S+1`; `S-16..S-120` is not executed or supplied to firearm rewind.
- `retired_ack` advances the actor's consumed-input cursor, removes those
  records from owner replay, clears held controls/shot-clock state and increments
  Runtime `stale_inputs`. Retired records cannot initiate movement, tool/class
  changes, firing, reload, building, damage or grenade actions. Ordinary fixed
  simulation continues, and a following fresh contiguous sequence executes
  normally. At most one executable record is selected per fixed step.

This retirement policy applies to INPUT_BATCH only. PLAYER_REQUEST retains
strict late-15/future-8 admission and its separate contiguous intention counter;
the six-tick held-input lease, queue bounds and heartbeat limits are unchanged.
It does not promise survival of arbitrary pauses or background tabs.

## Current evidence and acceptance limits

Clock fixtures passed **69/0** and actual controller integration **510/0**.
The RTT-accounted native report
`.cache/benchmarks/client-schedule-rtt-accounted.json` passed **47/0**: 130
callbacks, 339 sent inputs and 21 explicit clock-wait steps, zero dropped elapsed
steps; wire lead 1..7, peak pending 8 and wall time 6.618s. Waiting steps do not
spend a sequence or promise one command for every scheduled physics interval.
The previous fixture incorrectly required all 360 steps to submit; its retained
`client-schedule-rtt.json` reported **47 assertions / 2 failures**, 344 submitted
inputs and zero dropped steps. It is not a passing run. The corrected accounting
distinguishes sent inputs, deliberate clock waits and dropped elapsed time.

Two actual RTT-reserved Web clients completed both map barriers, each receiver
cumulatively ACKed **73/73 baseline chunks** and reached live; normal observed
wire lag was -2..2 ticks. The chunk total is not a test assertion count.
Entering/rendering the scene then caused a late-16 rejection, recorded without
credentials in `.cache/previews/browser-clock-rtt-stall-failure.log`.
That browser failure preceded the new ACK-retirement policy. It does not verify
authority-4 recovery or full browser play.

Actual-socket Runtime **223/0** verifies the new policy: a stale record with all
seven buttons set (`buttons=127`), movement, grenade-tool and shotgun-class
intent advances its ACK without changing resources/tool/class/pose, damaging another actor, editing
terrain or creating a grenade; fresh contiguous sequence 3 then executes.
These are focused native checks, not a new frozen export/publication, public
WSS/TLS, Docker/Linux execution, WAN conditions, original-map or 32-player
capacity acceptance. Exact frozen-release Web acceptance remains open.

## Partial authority-4 browser evidence

A later dirty-workspace diagnostic Web export used PCK SHA256
`4581f1740b767e459158b29a2c15b42ed12a5f413374eeaac7bea8346600241b`.
Both actual clients entered/rendered CTF with 100HP, rifle 10/50 and three
grenades. Chat sent by the first appeared on the other; block-tool palette and
blue→spectator→shotgun-class→blue respawn were exercised while connected,
returning 100HP and 6/48. Regular observed FPS was 10–11 with two running engines
on this workstation, not a performance pass.

Approximately three minutes of actual gameplay completed. Explicit disconnect
and reconnect of the first client preserved actor1, installed fresh map snapshot ID3
with 73/73 chunks acknowledged, and the UI showed Connected followed by Enter
with the same shotgun 6/48 and 100HP. Final native counters: admissions2,
resumes1, closed1 (the explicit disconnect), stale_inputs4, input_rejections0,
map_resyncs0, timeouts0 and backpressure0. Both browser logs contained only IAB
pointer-lock `WrongDocumentError`, no engine/other errors. Screenshot:
`.cache/previews/browser-network-retirement.jpg`. Those browsers/server were
stopped; the earlier RTT-stall failure remains preserved separately.

This is partial evidence for these foreground gameplay/respawn/resume paths on
the diagnostic PCK. It does not accept a frozen release, Pages publication,
public WSS/TLS, Docker/Linux execution, background tabs, sustained performance
or multiplayer completion.

## Historical fault and first repair

`ClientPrediction.reconcile` retimes retained commands to the authority snapshot
tick plus their replay index. That replay timeline
is suitable for local motion, but using its final tick to timestamp new network
commands can repeatedly add unacknowledged replay work to the wire clock.

The coordinator's actual old `c55ad92` browser trace at
`.cache/previews/browser-c55-future-rejection.log:249` records close code 1008,
`invalid input stream`: server tick 14681, commands 7094/7095 at ticks
14690/14691, lead 9/10, and only three queued authority commands. Recent accepted
leads were 4 through 8. Aggregate input rejections were one; transport
backpressure and heartbeat timeouts were zero. This is a measured violation of
the existing eight-tick future bound, rather than evidence of a full queue.
The diagnostic log contains clock integers and constant reasons, without
capabilities or packet payloads.

The first repair (c55 →0ec) used
`max(last_successfully_sent_tick + 1, last_snapshot_tick + 1)`
and advanced that clock only after a successful send.
Close, epoch change, initial synchronization and generation change reset it.
Prediction/replay remained separate. At that stage `InputQueue` enforced an
eight-tick future and fifteen-tick receive-late bound. Main also polls before the
controller's physics callback; this isolated fixture tests the equivalent
poll-before-burst ordering, not Main's scene execution.

## Reproduce

Native, from the checkout root:

```powershell
& C:/absolute/path/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_client_schedule.gd -- --schedule-report=C:/absolute/path/checkout/.cache/benchmarks/client-schedule-native.json
```

With actual raw TCP forwarding delayed 40 ms in each direction:

```powershell
python tools/latency_proxy.py --godot C:/absolute/path/Godot_v4.7.2-stable_win64_console.exe --project C:/absolute/path/checkout/game --test C:/absolute/path/checkout/tests/network/test_client_schedule.gd --report C:/absolute/path/checkout/.cache/benchmarks/client-schedule-shaped.json --deadline 45
```

The explicit fixture path works in an isolated Git-archive release checkout.
The native stream defaults to six seconds; `--seconds=` is bounded to 3–32.
Proxy mode uses twenty seconds. The fixture's whole deadline is forty seconds;
the runner's deadline includes startup/cleanup and is forty-five seconds.
Runner ownership, relay bounds and shutdown are described in
[network-latency.md](network-latency.md). Only the two fixture clients/listeners
are stopped; resume capabilities stay in memory and are never serialized.

## Historical measurements before the wall-clock/RTT policy

Windows Godot 4.7.2 `ed1daf0bf`, quiet host, final fixture using the exact
`now + 1/24 s` callback deadline. All runs use source profile 0.75 and a
32×16×32 map (65,536 canonical bytes). Production source hashes are identical
between the two JSON reports.

| Metric | Direct native | Delayed native TCP |
|---|---:|---:|
| Report in `.cache/benchmarks/` | `client-schedule-native-now.json` | `client-schedule-shaped-now.json` |
| Assertions / failures; engine exit | 47 / 0; 0 | 49 / 0; 0 |
| Requested stream duration | 6 s | 20 s |
| Actual callbacks / submitted commands | 130 / 360 | 426 / 1,200 |
| Callbacks with more than three commands | 14 | 54 |
| Dropped elapsed command steps | 0 | 0 |
| Wire input tick minus authority tick at submission | −1…5 | −3…3 |
| Hypothetical replay-derived next-tick lead, maximum | 9 | 14 |
| Pending prediction records, maximum / bound | 11 / 256 | 19 / 256 |
| Ordinary client outbound frames, maximum / bound | 5 / 32 | 5 / 32 |
| Ordinary queued plus Godot-buffered bytes, maximum / bound | 265 / 131,072 | 265 / 131,072 |
| Authority deadline lateness, maximum | 27.894 ms | 48.695 ms |
| Client callback deadline lateness, maximum | 9.006 ms | 23.965 ms |
| Confirmed rifle shots | 6 | 6 |
| Total fixture engine time | 6.714 s | 22.765 s |

The shaped runner finished in 23.578 seconds with exit 0. The hypothetical
replay-clock metric samples `owner.last_tick + 1`; it does not transmit those
ticks and is not a measured rejection of an old-clock client in this fixture.
It demonstrates why the predicted clock must not control the wire clock.
Authority lateness is elapsed time beyond the previous due step and includes a
normal fixed interval; it is not simulation computation time or RTT.

Both final runs record two admissions, three authenticated resumes, zero input
rejections and zero map resyncs. Assertions cover all command acknowledgments,
empty final replay history, motion convergence, canonical map equality,
deduplicated confirmed event IDs, and rifle shots matching inventory with no
interval shorter than thirty ticks. The two extra shaped assertions check
bounded relay setup.

Terminal cases distinguish `game closed (1008): invalid input stream`,
`input send failed: connection is not open`, and real
`input send failed: outbound backpressure`. The latter deliberately fills the
unsent 32-frame application queue and verifies the thirty-third frame fails,
clears prediction and never reaches authority. After each terminal case the
same Replica resumes with the same stable actor ID and a fresh map/state
barrier, while the observer remains connected. Unknown peer reason text is
redacted to `remote close`; timeout and overflow diagnostics have separate
static assertions. Actual heartbeat stalls are covered by the latency suite.

The delayed run accepted/closed five game and five map relay pairs; both ended
with zero connections. It recorded one raw game-socket error during deliberate
terminal/disconnect cases, so it does not claim zero TCP errors. Peak relay
buffers were 1,495 game bytes and 65,746 map bytes. Delivered game segments had
means 46.90/46.83 ms and sampled p95 47 ms in the two directions; these measure
relay read-segment delivery, not WebSocket packet latency or application RTT.

The repaired replica SHA256 is
`de3e77d06d7876825db97bdf7bb6dd838cce50d3016622ab24c6c7117b4a84bd`;
each report also pins prediction, input queue and transport hashes. Sibling
logs retain the matching assertion totals and clean engine exits.

## Historical clock sensitivity and remaining limits

The subsequent integrated change added `client_input_clock.gd`: a monotonic60Hz wall
anchor advances through missed callbacks; snapshots can move its anchor forward
without adding prediction history. An estimate beyond the newest snapshot's
unchanged8tick future window waits for fresh authority and leaves the input
sequence untouched. A genuinely newer snapshot after waiting reanchors clock
time, allowing recovery when the authority itself paused; duplicates cannot do
so and transmitted ticks remain monotonic. Epoch/life reset clears that clock.
Its earlier 44 deterministic checks covered frame gaps, delayed/duplicate
snapshots, same-frame bursts and waiting. Input also added transport
`flush_outgoing()` before render work; this
does not receive/reconcile packets halfway through prediction. The native
schedule measurements above predate these changes and are retained as history.
Later RTT/ACK-retirement evidence and pending acceptance are recorded above.

Earlier artifacts are retained separately. The first shaped attempt used an
incomplete callback model that did not account for missed physics steps and
failed after a roughly 200 ms client pause. A subsequent contended native run
recorded roughly 348 ms authority lateness, 225 ms client lateness and eleven
dropped steps, then failed. It did not establish the ordinary 24 Hz outcome;
its exact terminal cause was not recorded, and is not inferred here. Final
reports were collected after closing the previous browser/native diagnostic
session and correcting the bounded callback model. These failures remain
evidence that a real-clock suite can be sensitive to long host pauses. A suite
failure must be inspected, rather than relabeled harmless or rerun silently.

This proves the listed small-map native scenarios under the measured schedules.
It does not prove browser background-tab survival, refreshed Web build behavior,
TLS/WSS, WAN conditions, original-map joins, 32-player capacity or sustained
60 Hz performance. Exported foreground browser verification remains necessary;
long pauses can still exceed bounded admission or heartbeat limits. The current
receive-retirement and execution limits are distinct, as documented above.
