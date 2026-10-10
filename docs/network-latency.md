# Local delayed TCP acceptance

`tools/latency_proxy.py` runs one owned native Godot process with `tests/network/test_network_latency.gd` and two raw TCP relays. The actual `BlockfieldServerRuntime` and two actual `BlockfieldClientReplica` instances use their production WebSocket transports, codecs, map barriers, prediction and authenticated input admission. The test never loads Main, preferences, renderer or audio. No production networking changes were needed.

This is local native transport acceptance with artificial delay and stopped forwarding. It is not WAN, TLS, browser, 32-client capacity or sustained 60 Hz acceptance.

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

## Recorded acceptance

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

The relay does not model packet loss/reordering, bandwidth limits, TLS proxy behavior, WAN jitter, browser scheduling or large-map memory pressure. TCP preserves order; calling a stream unreliable cannot bypass its head-of-line blocking. A 350 ms held input backlog is intentionally rejected under the current authored admission policy. Supporting longer interruptions would require an explicit server policy change, not relaxing validation in this fixture.

The runner's task-local JSON is trusted control only. Python publishes with `os.replace`; the GDScript writer removes the previous task-local destination then renames its complete temporary file because Windows rename cannot overwrite it. Readers retry a missing or invalid file. This service-file fix does not change network packet handling or project configuration.
