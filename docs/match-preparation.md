# Match preparation and retained-owner queue

An original-size reset can spend longer than256 command steps preparing a map.
Previously Runtime rotated its epoch immediately but withheld replacement
WELCOME until its immutable sender hash was complete. The client still believed
it was live, submitted old-epoch inputs that the server discarded, and filled
its256-entry prediction history after about4.27 seconds at60 commands/second.
Queued reset owners also inherited the active240-second deadline while waiting
behind other transfers.

## Wire and client transition

`MATCH_PREPARING17` uses the existing24-byte big-endian envelope and a9-byte
body `actor_id:u32, spawn_generation:u32=1, profile:u8(0|1)`. Header epoch is the
positive replacement epoch, tick its closed baseline tick, sequence1. It has no
resume/bulk credentials, URLs or arbitrary values. `network-3` build identity
rejects incompatible peers. The combined terrain-ray correction uses source
authority identity `authority-3`; envelope version remains1.

Runtime queues the announcement on the preserved game socket during reset,
before any preparation job or queue admission. Queue/send failure explicitly
closes the affected owner. The client keeps its stable ID, game socket and user
endpoints, but stops/drains the old bulk channel, cancels partial transfers,
replaces prediction, and clears old map/public state, remote poses, pending
events, action deduplication and input/chat/request cursors. It emits
`epoch_reset` followed by `match_preparing`, and reports `status="preparing"`.
Input, chat and player requests remain unavailable until full new readiness.
Presentation consumes this state to hide old views and show preparation.

A bound client accepts only a strictly greater announced epoch and its existing
actor ID. Trusted map epochs may skip numbers. An initially joining connection
without its first WELCOME can bind the announcement's ID; further greater
announcements keep that ID and supersede unfinished preparation. A reset may
change source profile, but the announced profile binds the subsequent WELCOME.
Duplicate/stale announcements and unannounced replacement WELCOME fail closed.
Only exact announced epoch/ID/generation/profile WELCOME returns to `joining`;
matching MAP_BEGIN then opens fresh bulk. Installed map and matching full owner
state are still mandatory before `live`. Snapshot source profile must match
accepted WELCOME as well as epoch/owner/map identity.

Capabilities are not disclosed before sender preparation completes. Registry
still rotates reset credentials and keeps existing guest/reconnect semantics.
Runtime refreshes the one-use bulk capability immediately before WELCOME; its
15-second lifetime is unchanged. The previously delivered resume credential is
retained locally until WELCOME replaces it, but cannot resume a disconnected
owner after the server already rotated the epoch. This change does not invent a
credential recovery mechanism during that interval.

## Queue, work and failure limits

At most32 admitted actors and two active joins remain supported schema bounds.
Queued reset streams contain no map clone or running preparation job. Dictionary
insertion order preserves retained-owner FIFO. New/resume HELLO admission is
unavailable while any reset owner remains queued, so newcomers cannot steal
free slots. They may retry after waiting entries have been admitted.

`MAX_QUEUE_WAIT_MS=3840000` (64 minutes) is a separate hard queue deadline.
With32 retained owners, two active slots and240 seconds per active join, the
last waiting wave is15×240 seconds; a16th wave provides scheduling slack.
`queued_at` measures waiting only; `started` resets when a slot admits that
owner. The existing240-second active deadline includes preparation, transfer,
receiver decoding/hash and MAP_READY. The first owner checkpoint remains
mandatory for client play after the server releases that active join slot. Both limits cause
explicit disconnect/cleanup when polled; neither is an infinite grace period.
`get_stats().queued` reports waiting entries separately from active `loading`.

This is an authored bounded queue policy derived from capacity/deadline bounds,
not a guarantee of successful32-player service, a64-minute soak measurement or
proof that original-size joins complete at60Hz. Existing map journal, pending
delta/event, backpressure and transfer budgets still apply; authority edits can
require an explicit new baseline rather than growing buffers indefinitely.
No new hosting, browser WSS or scheduling performance claim follows.

## Physical water boundary

VoxelData frozen copies retain their physical water metadata, while the wire map
baseline carries only canonical cells/dimensions. Client decoding reconstructs
`water_level=1.0`, `wade_origin_level=2.0`. Runtime configure and reset reject
custom or nonfinite levels before changing map/epoch/registry/stream state.
These exact native defaults must remain unchanged for the network map lifetime.
Standalone Match/offline queries were not modified; supporting custom network
levels would require an explicit versioned metadata schema, not a guessed
client value.

## Verification

Pinned native Godot4.7.2 `ed1daf0bf`, no Main, GPU or preference writes:

- Protocol1639/0: independent33-byte golden, exact metadata, all truncations,
  bad enum/type/count/header relationships and credential-field rejection.
- Registry/Replica preparation contract437/0: old loading/live state cleanup,
  same-socket owner/endpoints, prediction/effect/history cancellation, discarded
  bulk terminal frames, fresh credentials and complete new barriers.
- Real Runtime epoch722/0,274 polls, maximum2 active jobs: sparse canonical IDs,
  greater epochs61→72→83, source profile changes, concurrent destruction/deltas,
  live/loading reset, resume and retired-capability races.
- Real ClientReplica138/0 and Runtime103/0 preserve their existing behavior.
- New `test_long_reset.gd`:3344/0,606 polls. Four actual clients initially join;
  one enters current-epoch grace, three retain their IDs. Real map jobs are held
  for320 input-attempt steps, and the third owner waits with an injected timestamp
  older than240 seconds. No commands/history, stale maps or capabilities appear
  during preparation. Actual fresh and valid-resume probes cannot overtake
  waiting owners even with free active slots. On release, exact new map/profile
  and owner barriers complete, prediction restarts at sequence1 and all sockets
  cleanly close. Malicious client PREPARING cannot change authority. Terminal
  queue expiry is tested with an injected old queue timestamp.

The long suite uses controlled trusted preparation-work and clock-state
fixtures, a256KiB map and genuine TCP/WebSocket delivery. It does not claim an
actual240-second/64-minute wait or original64MiB join timing. It also exercises
stale/duplicate/wrong-owner announcements, wrong-profile/future/unannounced
WELCOME, premature/future baseline, future/profile-mismatched full state,
initial binding and reset-during-preparation. Invalid/nonfinite water configure
and resets preserve prior authority, client readiness, streams and credentials.

Logs: `.cache/logs/protocol-preparing-tests.log`,
`epoch-preparing-contract-tests.log`, `runtime-preparing-epoch-tests.log`,
`replica-preparing-tests.log`, `runtime-preparing-tests.log`,
`long-reset-tests.log`. Reproduce with:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_long_reset.gd
```

Actual Main/browser preparation feedback and exported WSS behavior require their
separate coordinator-owned checks; native tests do not establish either.
