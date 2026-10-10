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

## Fault and repair under test

`ClientPrediction.reconcile` retimes retained commands to the authority snapshot
tick plus their replay index (`client_prediction.gd:175`). That replay timeline
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

The repaired `ClientReplica.submit_input` uses
`max(last_successfully_sent_tick + 1, last_snapshot_tick + 1)`
(`client_replica.gd:355`) and advances that clock only after a successful send.
Close, epoch change, initial synchronization and generation change reset it.
Prediction/replay remains separate. `InputQueue` retains its eight-tick future
and fifteen-tick late bounds (`input_queue.gd:7`). Main also polls before the
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

## Final measurements

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

## Clock sensitivity and remaining limits

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
long pauses can exceed unchanged admission or heartbeat limits.
