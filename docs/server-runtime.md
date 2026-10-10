# Native runtime, connection ownership and input admission

`BlockfieldServerRuntime` owns two poll-driven transports, `BlockfieldSessionRegistry`, one `BlockfieldInputQueue` per bound actor and the shared `MatchSimulation`. No renderer, settings, Input singleton, HUD, sound or visual grenade node is instantiated. `configure(simulation,build_hash,rules_hash)` is trusted; `start(game_port=0,map_port=0,bind_address="127.0.0.1")` returns actual native ports; `poll()` handles sockets/joins between steps; `step_once()` advances exactly one authority tick; `stop()` releases both listeners.

`game/entry.gd` selects the dedicated scene only for the `dedicated_server` feature or explicit user argument `--server`. Ordinary headless offline tests retain the original lab. The dedicated Node calls `poll` in process and one `step_once` per engine60Hz physics callback. Large workload/catch-up behavior is not yet a sustained-performance acceptance result.

## Ownership and join sequence

HELLO must have zero epoch/tick/sequence and compatible32-byte build/rules hashes. Roles are playing guest0, spectator1, paired bulk2. Only the trusted Match allocator creates actor IDs; a bulk socket never creates an actor. All game and bulk connection bindings are separate even when their numeric IDs coincide. The registry exposes only public connection/generation/readiness views.

Resume requires a disconnected actor within30seconds, the same role and a matching32-byte capability digest. Active ownership cannot be taken over. Successful resume rotates both tokens and repeats the map barrier. Disconnect immediately neutralizes controls, drops cooked grenade/intel through Match rules and revokes the bulk socket; the identity/scores remain during grace. Expiry asks Match to remove the actor while retaining already-thrown projectiles.

Baseline preparation uses an immutable packed snapshot and incremental SHA ranges; WELCOME is delayed until preparation completes. A fresh one-time bulk token with15seconds lifetime is issued then, followed by BEGIN on the game socket. The client opens `/map` only after consuming BEGIN, eliminating an early-chunk race. Chunks use the bulk socket; ordered transactions and END use the game socket. END freezes a later map barrier, while transactions beyond that sequence remain queued until matching READY. A live client then receives post-barrier deltas before the latest state snapshot. Initial guest spawn follows map readiness.

At most two loading joins are retained. Each peer retains at most128 transactions,32768 changes and8MiB of estimated encoded deltas. A240second absolute join deadline includes preparation and validation. Slow peers, gaps and over-budget edits close their current stream explicitly; reconnect requests a fresh baseline. Transport heartbeat/backpressure remains separately bounded. Old map streams are invalidated before the trusted `acknowledge_map_resync()` clears Match's sticky overflow marker.

## Command family semantics

INPUT_BATCH header epoch is the match epoch, sequence is the actor's **spawn generation**, and tick equals the final record's input tick. Each batch has1..8 contiguous records, each generation starts with sequence1 (or the trusted acknowledged sequence+1 after reconnect). Across batches sequence must remain contiguous and input ticks strictly advance. Admission accepts ticks no more than15 behind or8 ahead of current server time; this is a queue window, not a rewind permission.

The queue owns decoded Command copies, with at most32 pending. Each server step consumes at most one eligible command. Future commands wait; clients cannot request dt or multiple simulation steps. An expired backlog requires resync rather than hidden skips. Six ticks without a consumed command clear held controls; clearing retains cooking and previous button edges until the next rules step, so release follows the normal authority path. Epoch/generation transitions clear old commands and acknowledgment state.

CHAT intents have sender_id0 and contiguous per-session message IDs. Runtime assigns the actual sender and global ID, enforces four messages per five seconds and routes team chat only to the same team. Chat generation/epoch must match. Only ready clients receive chat; backpressure closes the affected stream. Team/class requests and the complete event feed still need their wire adapters.

## Current snapshot boundary and verification

The default emits complete MATCH_STATE14 through SimulationCodec: full private owner replay state, public actors/grenades and typed objectives. `set_snapshot_factory(Callable)` remains a trusted test/extension hook. Legacy SNAPSHOT remains supported by Protocol for its existing fixtures; it is not the production default. The runtime currently drains authoritative events without a feed adapter; events are not yet replicated. Do not use this checkpoint to claim full multiplayer.

Unsent state is replaceable at20Hz; bytes already queued into ordered TCP are not withdrawable. Deltas retain order and are never silently replaced. Fixed-step publication and transport polling are distinct operations.

Commands: `python tools/build.py`; standalone `--headless --path game --script ../tests/network/test_server_runtime.gd`. Latest runtime fixture: **103 assertions,0 failures** in .cache/logs/server-runtime.log. Two actual native game+bulk clients install exact maps, receive owner snapshots, submit a source gun shot, exercise lease/chat/disconnect/rotating-token resume and reject a malicious sequence gap without stopping the other client. Registry70/input58 standalone checks cover forged/expired capabilities, active takeovers, exact grace, epochs, atomic batch validation, stale generations, future waits and owned copies. Browser WSS, mid-round edits, adversarial latency, full client adapter and container deployment remain separate acceptance.
