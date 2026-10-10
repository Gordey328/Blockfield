# Local delayed TCP acceptance

`tools/latency_proxy.py` runs one owned native Godot process with `tests/network/test_network_latency.gd` and two raw TCP relays. The actual `BlockfieldServerRuntime` and two actual `BlockfieldClientReplica` instances use their production WebSocket transports, codecs, map barriers, prediction and authenticated input admission. The test never loads Main, preferences, renderer or audio.

The current fixture targets the newly authored `authority-4` stale-input retirement policy. Its updated 350 ms recovery scenario passes **460 assertions / 0 failures**, Godot exit0 and clean diagnostics, in the native run recorded below. The measured `authority-3` results are historical: they expected a late-input disconnect and two resumes, and do not verify the new policy.

This is local native transport acceptance with artificial delay and stopped forwarding. It is not WAN, TLS, browser, 32-client capacity or sustained 60 Hz acceptance.

The frozen00d241c7da06 run reported499/0 but its engine log included a control-file
JSON parse error, so the release gate rejected it before export. The Python writer
already uses atomic replacement; a Windows path can disappear/change between an
existence check and opening it. Both GDScript control readers now use one read
handle, a non-logging JSON parser and their existing bounded retry/wait. Malformed
control data cannot acknowledge a request or extend its deadline. A focused
post-repair run passes501/0 with clean diagnostics; the failed archive is retained.

## Reproduce

Pass absolute existing paths. The test defaults to the script beside the runner's repository, so the command also works in a Git-archive release checkout without looking up the original workspace.

```powershell
python tools/latency_proxy.py --godot C:/absolute/path/Godot_v4.7.2-stable_win64_console.exe --project C:/absolute/path/checkout/game --report C:/absolute/path/checkout/.cache/benchmarks/network-latency.json
```

`--test` accepts an explicit fixture path. `--deadline` accepts 5–45 seconds; the default whole-run deadline is 45 seconds. The runner returns 0 only when Godot exits 0 and its JSON result reports no failed assertions. The report and sibling `.log` hold bounded metrics and test diagnostics. A unique `.cache/network-latency-*` directory holds task-local control/status/result files for diagnosis.

Windows starts Godot suspended, assigns it to a `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` Job Object, then resumes its owned thread. Cleanup closes that job and waits for the exact owned process. Other platforms use the owned process group. Every relay listener and accepted socket is closed in `finally`; there is no background service or blanket process-name kill. No resume capability or packet content is written to control, report or log files.

## Shaping and bounds

Both relay listeners and their upstream connections use `127.0.0.1` with ephemeral ports. The relay preserves TCP byte ordering and applies a 40 ms forwarding deadline in each direction, including the HTTP WebSocket upgrade. It does not parse or rewrite game packets. Game and map sockets use separate relays, retaining production channel separation.

| Bound | Actual fixture value |
|---|---:|
| Accepted simultaneous connections per relay | 8 |
| Retained pending bytes per direction per connection | 262,144 |
| Pending segments per direction | 4,096 |
| Maximum read segment | 16,384 bytes |
| Accept work per poll | 8 sockets |
| Idle relay pair lifetime | 15 seconds |
| Trusted stall command duration | 1–3,000 ms |
| Trusted control requests per run | 16 |
| Retained delivery timing samples per direction | 4,096 |
| Whole runner deadline | 45 seconds |

When a retained byte/segment limit is reached, the relay stops reading that direction and lets TCP apply backpressure. A partially sent first segment retains its original allocation until fully forwarded; this can add up to one 16 KiB allocation beyond its counted remaining bytes. Kernel socket buffers are separate: the runner requests 16 KiB send/receive buffers, but does not claim a bound on kernel memory. Delivery statistics measure complete relay read segments, not application RTT or WebSocket packet latency.

The authority uses a 24×16×24 map (36,864 canonical bytes), source profile `0.75`, sandbox rules and real-clock 60 Hz scheduled steps with at most four catch-up steps per process frame. Map edits and deterministic combat poses are trusted fixture setup; clients still send genuine bounded input/chat packets and never supply authoritative damage, positions or edits. Compatibility comes from the production `BlockfieldCompatibility` hashes, including the source-ray rule revision `authority-3` used in the recorded run.

## Current stale-input recovery contract

The executable input/rewind age remains at most 15 closed authority ticks, future input remains at most 8 ticks, and the pending queue remains at most 32 commands. Authenticated, fully validated, contiguous and strictly increasing input records aged 16..120 ticks may be retired with an ACK without execution. Older-than-120 input, schema/owner/epoch/generation violations, gaps/replay, future overflow and capacity violations remain terminal failures. This is authored server behavior, not original OpenSpades server behavior.

The 350 ms case retains the existing actual game connection and spawn generation:

1. Drain existing transmitted input and save authority resources, horizontal position and confirmed combat-event counts.
2. Send one real `PRIMARY|RELOAD` plus rightward movement command. Assert it predicts an armed shot locally; immediately ask the owned relay to stall the first game connection. The relay's ordinary 40 ms delivery deadline gives its runner a chance to apply this control before forwarding the command. An early delivery or a probe which does not become stale fails this scenario; the test cannot count that as recovery evidence.
3. Continue neutral input and edit terrain during the 350 ms pause. Require `stale_inputs` to increase, prediction to receive an ACK covering the probe, and both maps to converge. The same socket/actor/generation must remain live, with zero input rejections, timeouts or resumes.
4. Require unchanged authority ammo/reserve/blocks/grenades/health, reload/cook/tool/weapon state, last-shot tick, victim health and horizontal position. Confirmed shot/reload/hit/hurt counts must not increase. Retained prediction commands must all follow the retired probe; after draining neutral input, the predicted owner must again match authority resources and pose.
5. Independently exercise the 1,500 ms idle stall with shortened heartbeat timing. This must still time out and require the only resume of the run, preserving stable ID/profile and exact terrain. Final cleanup stops every owned socket/process.

Temporary `awaiting fresh authority clock/stream` results are normal throttling, not failed transport. The initial combat command remains armed until it is successfully sent, so clock throttling cannot silently omit its mandatory shot check. Event identities still undergo the existing deduplication checks. These checks do not permit late actions to execute, enlarge hit history, or turn replay into authority.

Result JSON now records `backlog_recovery_ms`, `stale_probe_sequence`, `retired_probe_ack`, the retirement policy, `expected_input_rejections=0` and actual server totals. It no longer reports the old expected backlog failure duration. Assertion count includes one check per real authority step and is therefore scheduling-dependent; required scenario outcomes are explicit checks. No new timing/count claim should be copied from the historical run.

## Authority-4 native acceptance

Godot4.7.2 `ed1daf0bf`, Windows native loopback, `.cache/benchmarks/network-latency-retirement.json` and sibling `.log`: **460/0**, engine/runner exit0, empty error list and **7.344s** total runner time. Its owned Godot process and all relay/server sockets were cleaned; the subsequent process inventory found no Godot processes. This is the tested working-tree checkpoint, not a frozen release/browser acceptance.

| Scenario | Actual observation |
|---|---|
| Initial shot/private routing, chat and edits | Both source0.75 replicas pass the existing real join/hash, one confirmed shot, owner-only hit/victim-only hurt, no public inventory, event deduplication and exact ordered terrain checks. |
| 75ms stall | Relay release78ms; same live peers and exact maps after601ms of observation. |
| 350ms stale-input recovery | Relay release359ms; ACK/map recovery observed444ms after relay control acknowledgement. Server retired2 inputs; probe sequence37 was covered by ACK38. Same actual game socket/ID/generation remained live; authority and reconciled prediction kept exact stock/reload/cook state and pose, and no stale shot/reload/hit/hurt was confirmed. No reconnect, heartbeat timeout or input rejection occurred in this phase. |
| Separate1,500ms heartbeat stall | Relay release1,500ms; terminal timeout observed575ms after control acknowledgement. Heartbeat may already have an outstanding ping when this pause begins, so this observation is not a newly started650ms timer. Healthy peer remained live; the only resume retained actor ID/profile and exact edited terrain. |
| Final bounds/cleanup | Peak pending prediction10/256, transport queued frames2/32 and queued plus Godot-buffered bytes32,768/131,072. Three game and three map connections were accepted and closed across initial joins and the one heartbeat resume; both relays ended with zero connections. |

Runtime totals:2 admissions,1 resume,1 closed owner,0 input rejections,2 stale inputs,0 map resyncs and1 chat. This small fixture's `step_once` mean0.854ms/p951.934ms/max5.559ms excludes separate polling/publication costs and proves neither original-map performance nor sustained60Hz capacity. Relay peak retained game bytes21,282/map bytes36,990. One raw game socket `OSError` occurred during the deliberate timeout/disconnect; no claim of zero raw TCP errors is made.

The first attempt, preserved as `.cache/benchmarks/network-latency-retirement-initial-failed.{json,log}`, failed262/2 before the350ms scenario: Windows rejected removal of `request.json` during concurrent Python reading, so the second stall request was never delivered. This was a harness control-file failure with `stale_inputs=0` and `input_rejections=0`, not a production retirement failure. Removing delete/rename publication then passed459/0 in7.375s (`network-latency-retirement-write-repair.{json,log}`). The final460/0 run includes the additional bounded opening retry described below. Counts can also vary with retained-pending checks and scheduling; all mandatory phases remain explicit.

## Historical authority-3 acceptance

Godot 4.7.2 `ed1daf0bf`, Windows native loopback: `.cache/benchmarks/network-latency-final.json` reports **502 assertions / 0 failures**, Godot exit 0, 8.094 seconds total runner time. A bookkeeping check after the result was serialized printed 503 in the original stdout; the fixture now omits that post-serialization success check so JSON and stdout counts agree in future runs. The recorded 502 assertions already include gameplay and socket cleanup.

| Scenario | Actual observation |
|---|---|
| Delayed initial join and source shot | Both real replicas install matching baseline/state barriers. A genuine rifle input produces one deduplicated local confirmed shot. `hit_confirmed` reaches only the shooter and `hurt` only the victim. Remote actor state contains no health/ammo/reserve. |
| Ordered edits and chat | Repaint/create/remove transactions and typed chat traverse the shaped channels; both replicas match authority map sequence and packed cell bytes exactly. |
| 75 ms stopped game forwarding | Relay release observed at 78 ms. Clients remain live and converge after edits made during the pause. The fixture observes recovery for another 600 ms; this is not a measured 600 ms stall. |
| 350 ms stopped game forwarding with ongoing input | Release observed at 359 ms; the client fails at 391 ms with exactly one authoritative late-input rejection and zero heartbeat timeouts. This exceeds the existing 15-tick admission window. The same Replica resumes with the same stable actor ID, a fresh map/state barrier and cleared stale prediction. |
| 1,500 ms stopped game forwarding after input drain | Release observed at 1,500 ms. The first client fails at 658 ms with exactly one real application-heartbeat timeout. The second remains live. After the old socket closes, the same Replica resumes again with the same ID, profile and exact edited map. |
| Final cleanup | Four game and four map connections were accepted across initial joins and two resumes. Both relays have zero remaining connections; Runtime client/server transports are stopped and the owned Godot process exits. |

Only the first test client's heartbeat is shortened before its transport starts: ping interval 100 ms, ping timeout 650 ms, idle timeout 1,200 ms and close timeout 100 ms. The idle timeout case therefore does not demonstrate production-default timing. The test restores the default transport values on the discarded client transport before its final reconnect. These settings never touch project preferences.

Observed maxima were **31 pending prediction records** (limit 256), **2 transport queued frames / 32,768 queued plus Godot-buffered bytes** (limits 32 / 131,072), **21,951 retained game-relay bytes** and **36,990 map-relay bytes**. Unstalled map delivery segments measured 46–47 ms each way on this host's timer/poll scheduling. Game direction aggregates include both deliberate stalls; client-to-server sampled p95 was 266 ms and must not be presented as the ordinary 40 ms configured delay.

Authority step measurements were mean 0.800 ms, p95 1.890 ms and maximum 4.807 ms for this small two-client fixture. They exclude publication/polling work outside `step_once` and do not establish capacity or original-map join performance. The runtime totals were 2 admissions, 2 resumes, 1 expected input rejection, 2 closed owners, 0 map resyncs and 1 chat. The game relay observed one raw socket `OSError` while exercising deliberate disconnects; the test does not claim zero raw TCP errors. Received game bytes exceed forwarded bytes because pending bytes are discarded when a failed connection is released.

## Explicit remaining limits

Frozen9d186266fb8b rerun passed501/0 in8.094s with438 real steps versus439
in the502-check handoff. The fixture adds an assertion per real simulation step;
the fixed remainder63 and required stages/admissions/two resumes/late rejection
are identical. Assertion count is scheduling-dependent, not an omitted gate.

The relay does not model packet loss/reordering, bandwidth limits, TLS proxy behavior, WAN jitter, browser scheduling or large-map memory pressure. TCP preserves order; calling a stream unreliable cannot bypass its head-of-line blocking. The historical 350 ms backlog was intentionally rejected by authority-3. Authority-4 instead requires ACK-only retirement within its explicit 120-tick bound; its current acceptance status is recorded above. A longer/background interruption can still legitimately require reconnect, and no timeout or queue limit is disabled by the fixture.

The runner's task-local JSON is trusted control only. Python publishes with `os.replace`. The GDScript writer truncates and writes one complete small JSON document, flushes and closes it; it does not delete a path which Python may hold open. A sharing failure during opening is retried in1ms increments for at most20ms, then explicitly fails the fixture. This synchronous wait is confined to test control, below the configured40ms relay delay, and is not production game behavior. Both readers retry missing/empty/invalid JSON; Python accepts a request only at the next expected sequence and validates its action/channel/bounds. The runner reads final result JSON only after the owned engine exits, catches malformed JSON, and requires a valid result plus exit0/zero failures to report success. No partial result can pass. These control-file changes do not alter packet handling or preferences.
