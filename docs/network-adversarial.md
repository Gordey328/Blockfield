# Native adversarial network acceptance

> Historical pre-removal design/evidence. Multiplayer was withdrawn on2026-10-12
> under [ADR0031](decisions/0031-offline-only-game.md). Deleted networking paths
> and server instructions below do not apply to the current offline game.

`tests/network/test_network_adversarial.gd` drives the current production ServerRuntime, ClientReplica, Protocol16 families, EventsCodec, MapTransfer, HitHistory and Match through real native loopback WebSocket connections. Each scenario starts ephemeral game/bulk TCP listeners and releases every listener/peer afterward. It never instantiates Main, renderer, audio, settings or an external service.

There are two client types: the actual `BlockfieldClientReplica`, and a bounded two-socket probe that decodes the same typed packets and applies complete transactions. The probe can delay bulk polling, incremental private map validation or READY, inspect received wire events/snapshots, send explicit old admitted input ticks, and stop polling entirely. It has bounded captured effects/packets/errors and never supplies authoritative actor positions, damage or map results. Trusted fixture setup changes authority state directly when a deterministic pose or committed terrain receipt is needed; those operations are explicitly separate from client packets.

## Current result

Native Godot4.7.2 `ed1daf0bf`: **392 assertions / 0 failures**, 643 poll/step cycles. `.cache/logs/network-adversarial.log` has no warnings, errors or leaked-object reports.

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_network_adversarial.gd
```

Every wait has both a monotonic wall deadline (normally5seconds) and a poll-count guard (normally1500). Individual fixed steps are advanced by the harness; this is not a realtime60Hz/FPS benchmark. The canonical map is32×16×32, 64KiB in the canonical color stream, with fixed colors and a genuine support/collapse fixture. The process runs all scenarios serially and stops its sockets; it leaves no background server.

| Actual socket scenario | Evidence | Measured wall time |
|---|---|---|
| Two concurrent delayed map joins while authority edits | Initial live replica plus two game/bulk joiners; frozen BEGIN hashes precede support removal, four collapse cells and create/repaint transactions. Both END hashes verify sequence3. A later repaint at sequence4 waits beyond each announced barrier; matching READY installs sequence3, then ordered live delta4 precedes state4. All three replicas converge byte-for-byte. A fourth new client joins the already destroyed/repainted map exactly. | 1638ms |
| Late moving-target shot and event privacy | Actual ClientReplica movement moves the victim out of the current source ray. A first shooter input sent with the retained older tick still hits its historical pose through Runtime's admitted timestamp path. Shooter alone receives `hit_confirmed`; victim alone receives `hurt`; both receive public `shot`. Full private state is addressed to its socket owner; public actor dictionaries omit ammo/RNG/controls. Resetting history to a fresh window leaves a still-admitted old command consuming ammo with no damage. | 762ms |
| Resume, automatic respawn and hostile direction | Real close revokes game/bulk ownership; rotating-token resume repeats the map/state barrier with the same actor ID. The old capability cannot take over or allocate a duplicate actor. Actor remains dead through deadline−1 and automatically spawns exactly at the180-tick deadline. Delayed old-generation input and team requests are ignored. New-generation sequence1 works. A valid typed GAME_EVENTS packet sent back on the client channel disconnects only its sender; the other replica continues. | 3446ms |
| Malformed actual WebSocket frame | A test-only direct `WebSocketPeer.put_packet` sends an otherwise valid binary INPUT_BATCH with big-endian IEEE754NaN yaw. Server transport reports one protocol error, disconnects the bound actor before command admission, and the other complete replica continues. Unknown client damage fields are also rejected by the strict schema before encoding. | 353ms |
| Delayed READY exceeds retained map budget | Client receives END but withholds READY.129 actual committed post-barrier create/repaint transactions arrive while a healthy replica polls. Retained stream stays at/below128 transactions,32768 records and8MiB; transaction129 explicitly disconnects/releases that join. The healthy replica applies all edits and matches authority exactly. | 1895ms |
| Actual connected peer stops polling | With fixture idle600ms, application ping100ms, ping timeout300ms and close50ms, one real connected WebSocket client stops all polling. Its failed heartbeat explicitly disconnects the actor and releases input/map/event stream; a polling ClientReplica stays connected. | 611ms |

The reported timings are one local native run, including asynchronous loopback handshake/polling and harness process-frame waits. They are not server throughput, network RTT or browser timing measurements. Observed server transport maxima were **2queued frames /32768 queued+engine-buffered bytes** across all scenarios, under the configured32-frame/131072-byte limits. The queue-budget assertion measures those values each poll cycle; it does not inspect OS kernel TCP buffer memory.

## Production issue found and fixed by coordinator

The initial read-only audit found that ordinary combat deaths had no reachable runtime respawn transition: death set a positive180-tick deadline, while the only team-request spawn branch required a negative deadline. The coordinator added an explicitly authored automatic policy for ready/live, connected playing actors at/after their deadline, followed by the existing generation/input reset path. The final socket suite tests that real transition at the exact tick. It no longer uses a trusted manual spawn to claim client respawn acceptance.

No production files were edited by this acceptance slice. Its owned changes are this document and the new test only.

## Limits and remaining acceptance

- The held-READY scenario proves bounded **application join retention** and per-peer disconnect under real socket traffic. The no-read scenario proves actual peer timeout/cleanup. Loopback kernel buffering did not saturate in these cases, so there is no claim of sustained TCP send saturation, WAN head-of-line blocking or byte-budget overflow under a shaped network.
- Terrain changes are real trusted `VoxelData` committed receipts, including collapse; this suite does not test client renderer adoption/falling visuals. There are no fabricated incoming MAP_DELTA decisions by a client.
- The late shot uses a real socket and server-admitted older timestamp; the harness deliberately submits that timestamp rather than shaping WAN latency. Pure Match441/0 and History269/0 remain the more extensive same-time cover/shotgun/life goldens. This is not an anti-cheat model for dishonest-but-in-window timing claims.
- Epoch/map reset while clients are live is a future Runtime API and is not tested here. Also pending: rendered scene integration, browser WSS/TLS/reverse proxy/origin behavior, downloaded server/container execution, original64MiB map memory/timing, sustained player capacity, jitter/reordering of application scheduling and long TCP stalls under an external network shaper.
- Client effect deduplication and UI/audio behavior need their separate acceptance; received typed owner/public events here prove routing/privacy, not presentation.

These checks provide concrete native N01–N06 integration evidence. They do not mark iteration2 complete or justify changing the whole multiplayer ledger to VERIFIED.
