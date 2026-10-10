# Registry and client epoch replacement

A match epoch is distinct from an actor ID, a spawn generation and a socket connection. Resetting a match preserves admitted **connected** game bindings and their player/spectator roles, while requiring a fresh map/state barrier. Disconnected identities in reconnect grace are discarded at reset. This is the authored Blockfield server policy, not an assertion about the original OpenSpades server.

## Trusted registry transition

```gdscript
registry.advance_epoch(new_epoch: int, new_profile: int, now_ms: int)
# {ok, error, welcomes: Array[Protocol.Packet],
#  close_bulk: Array[int], expired_actor_ids: Array[int]}
```

The registry must already be configured. `new_epoch` is strictly greater than the current positive u32 epoch; `new_profile` is0 or1. The clock must be nonnegative, nonregressing and at most `MAX_CLOCK_MS`, which leaves room for capability/grace deadlines in the signed64-bit clock. An invalid request returns empty result arrays and leaves the previous monotonic clock untouched.

Before changing state, the registry allocates two fresh32-byte Crypto capabilities per connected owner, prepares their stored SHA256 hashes and validates every typed WELCOME with the actual protocol encoder. Fresh candidates must differ from retained credential hashes and each other. Entropy failure or any invalid candidate/packet aborts the complete operation, including previously prepared owners. The production entropy source remains `Crypto.generate_random_bytes(32)`; deterministic injected tokens exist only in tests.

One commit then advances epoch/profile/clock, removes disconnected grace records, clears all old bulk bindings, resets connected readiness/barrier and spawn generation to1, and rotates the resume/bulk hashes. Existing actor IDs, game connection IDs and admission roles remain unchanged. Returned WELCOME packets are ordered by actor ID and contain the same approved build/rules compatibility hashes, the new epoch/profile, generation1 and fresh capabilities. Stored hashes do not alias returned raw credentials. Old bulk connection IDs and discarded actor IDs are returned for Runtime's transport/simulation cleanup; the registry does not own either subsystem.

The trusted coordinator must replace its match/map/input/event/history state consistently with this transition, close returned bulk sockets, remove returned grace actors, send replacement WELCOME packets on retained game sockets and start fresh baselines. A client cannot request this operation. Runtime owns stale old-epoch input/request policy during the transition; Registry only admits a new MAP_READY after the new barrier. See the separately maintained runtime reset acceptance document for actual socket evidence.

## Replica preparation announcement and matching WELCOME

Initial WELCOME retains joining/resume semantics and produces no reset event. A trusted MATCH_PREPARING17 now announces a strictly greater epoch, the same known actor ID, generation1 and valid profile before expensive preparation. It may supersede unfinished preparation and may bind the first positive ID of an initial joining client. Repeated/stale announcements fail closed. Subsequent WELCOME must exactly match the announced epoch/ID/profile/generation; unannounced replacement or wrong compatibility/rate/token fields fail closed. See [match-preparation.md](match-preparation.md).

Before exposing the announced replacement epoch, the replica stops/drains old bulk and resets:

- Joining map buffers, decode/apply/hash work and transaction assembler.
- Installed map, private prediction/input history and confirmed snapshot.
- Remote interpolation, pending presentation events and predicted-effect suppression history.
- Chat intent/confirmed cursors, request sequence, confirmed-event cursor and snapshot tick/time.

It retains game transport/ID, callbacks, endpoint, name and admission role. Status becomes `preparing`, with `epoch_reset` and `match_preparing` events. Main clears scene views and returns to its preparation menu. Matching WELCOME activates refreshed capabilities and advances to joining; no map socket opens before the subsequent MAP_BEGIN.

The subsequent baseline uses a newly opened bulk stream and the new one-time token. Successful map installation advances only to `synchronizing`; input remains denied until a matching full owner snapshot. New map/state ticks and input/chat/request cursors may start at0/1 even when the previous match had much larger values. Server packets remain epoch-strict on the client: ordered game TCP delivers old queued game frames before replacement WELCOME. Native transport forced stop **emits and retains** terminal events, so Replica intentionally drains the complete bounded `MAX_EVENTS` queue after old bulk stop (and both transports in `close()`). This also permits immediately reusing the same Replica for connect/resume. Genuine failures on the new stream still fail closed; cleanup does not weaken packet identity or direction checks.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf`, no Main, scene preferences or Runtime load:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/session_registry.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/client_replica.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://../tests/network/test_epoch_reset_contract.gd
```

Observed contract result: **419 assertions / 0 failures**, exit0, clean stderr; original `test_session_registry.gd` remains **70/0**. Registry tests include late entropy failure after one owner was prepared, exact state/clock atomicity, stale readiness, old capability rejection after disconnect, player/spectator identity retention, discarded unexpired grace,32 actors/64 distinct fixed-size capabilities and maximum u32 epoch. Actual Protocol/SimulationCodec/MapTransfer/PlayerRules/Prediction components run over bounded independent fake transports. Tests interrupt all four permitted client statuses with pending old map/input/effect state, clear it, preserve the game binding, finish a different new baseline/profile0.76 and lower tick, and resume at input/chat/request1. Invalid/repeated welcomes and independent copied credentials are also covered. Regression fixtures mirror native retained close events, discard more than64 queued events, reuse the same Replica for close/connect/resume and deliver replacement WELCOME plus MAP_BEGIN in one poll; a genuine close on the new bulk stream remains fatal.

This establishes component contracts and byte/state behavior. Real socket queues, Runtime match replacement and exported-browser reset behavior require their own integration acceptance; this document does not mark multiplayer complete.
