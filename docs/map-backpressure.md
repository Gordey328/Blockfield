# Bounded map receive credit

Native Runtime can send two bulk chunks per poll while a browser pauses or
renders slowly. Successful local enqueue/flush is not proof that the receiver
read those frames. `WebSocketPeer` inbound memory/packet limits and outbound
buffered amount are different bounds ([official documentation](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html)).
The project sets a 262,144-byte engine receive buffer and 64-packet queue. A
stream without receiver credit can exceed these bounds despite zero sender
backpressure. No claim about the pinned engine's precise overflow/drop behavior
is needed for the new bounded policy. The previous generic `map chunk rejected`
diagnosis alone did not identify which receiver invariant failed.

## Wire contract and ownership

Protocol family **18 MAP_CHUNK_ACK** has twelve big-endian payload bytes:
`snapshot_id:u32, next_chunk:u32, received_bytes:u32`. Its envelope epoch,
tick and sequence match the immutable BEGIN's epoch, baseline tick and map
sequence. `next_chunk` is cumulative accepted progress, not a chunk resend
request. The codec bounds integers, checks count/byte correspondence and rejects
extra fields, zero epoch or malformed/truncated frames. No capability, player
position or actor ID is in this packet.

Runtime authenticates the bulk socket first. That bound owner selects the
window; the packet cannot select a different actor. Wrong snapshot/epoch/tick/
sequence, ahead-of-sent progress or an incorrect byte count rejects the ACK
without changing credit and disconnects the offending owner. Another owner is
unaffected. Correct repeated or older cumulative progress for the same
descriptor is an accepted no-op. Reset/disconnect releases the old window;
there is no cross-epoch credit.

`BlockfieldMapTransfer.BulkWindow` exposes:

| Method | Behavior |
|---|---|
| `reset(begin)` | Validates raw BEGIN and pins a tiny descriptor; sent/acked start at zero. Invalid reset does not change existing state. |
| `can_send()` | True while another chunk remains and `sent - acked < 8`. |
| `mark_sent(chunk)` | After transport enqueue succeeds, validates exact next chunk/descriptor and advances sent count. |
| `acknowledge(packet)` | Validates context/count/bytes; returns `{ok,error,duplicate,advanced}` on accepted progress. Failure does not change counters. |
| `get_stats()` | Armed/snapshot/count/sent/acked/outstanding/window integers, no capabilities. |
| `cancel()` | Releases descriptor and counters. |

The fixed limit is **eight unacknowledged chunks**, at most 131,072 encoded
bulk-frame bytes. It applies across local transport queue, native socket
buffering and remote receipt. This retains receive-buffer headroom; it is not a
bound on kernel memory or arbitrary malicious clients. A dishonest receiver
can falsely acknowledge its own sent data, but cannot credit unsent chunks or
another owner's snapshot. The integrity/barrier checks still determine map
acceptance.

The sender serializes one chunk lazily and retains that packet across local
enqueue backpressure. It advances window sent count only after successful
enqueue. When exhausted it waits while continuing socket polling, authority
ticks and other owners' streams. The once-only end-of-sender probe is allowed
after all chunks are queued even when the last window has not been acknowledged.

## Receiver and final cross-channel order

`MapTransfer.consume(CHUNK)` validates and appends/hashes the bytes immediately.
The later `poll(...,2)` budget is for staged decoding/application/final hashing,
not an incoming two-chunk queue. After successful chunk consumption, the caller
coalesces one `get_chunk_ack().packet` per drained bulk batch, sends it on the
authenticated bulk socket, and flushes only outgoing frames. Concrete consume
and send failures remain visible. The returned packet owns its metadata; caller
mutation cannot change retained ACK state.

ACK means bytes accepted, not canonical colors decoded or a player spawned.
MAP_END stays on the game socket and can precede remaining bulk chunks. The
receiver retains that one barrier while waiting for all chunks and ordered
deltas, checks both canonical SHA256 hashes, then emits READY. A final game
MAP_READY may reach Runtime before the final bulk ACK; it is validated normally
without waiting for ACK. The tiny window remains after `live` so a delayed final
ACK or correct duplicate can still be accepted. Decode/ready handoff retains
only the last tiny ACK descriptor; reset/cancel/failure clears it.

Active join timeout remains **240 seconds**, pending FIFO admission policy and
capability TTL are unchanged. Input future/late windows and map byte/change
budgets are unchanged. `network-4/authority-3` handshake hashes prevent older
clients joining a server requiring family18; envelope version is still1.

## Native verification

Godot 4.7.2 `ed1daf0bf`, no Main, preference, renderer or audio. All commands below
ran with engine exit0 and no error/leak reports:

| Fixture | Assertions / failures |
|---|---:|
| `tests/network/test_protocol.gd` | 1759 / 0 |
| `tests/network/test_map_transfer.gd` | 958 / 0 |
| `tests/network/test_server_runtime.gd` | 103 / 0 |
| `tests/network/test_map_backpressure.gd` | 39 / 0 |
| Latest coordinator `test_ws_transport.gd` | 612 / 0 |
| Coordinator `test_client_input_clock.gd` | 17 / 0 |

```powershell
& C:/absolute/path/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_map_backpressure.gd
```

The new fixture first runs two real game/bulk test clients against a canonical
262 KiB map, **17 chunks**. One receiver stops polling for 600 ms. The authority
and other client continue; pending bulk progress stops at exactly8. Trusted
fixture create/repaint/remove edits use Match's receipt queue during the pause;
both clients converge to map sequence3 and identical bytes. Client map changes
are never authoritative. A first diagnostic omitted the fixture's Match receipt
queue and correctly could not reach the declared sequence; that fixture mistake
was corrected rather than changing production barrier rules.

The slow test client deliberately withholds its final ACK. It crosses the game
READY/state barrier with one outstanding chunk, then sends the final ACK twice
on its real bulk socket; both are valid and it remains live. A valid ACK from
the first owner's different snapshot, sent by the second owner, disconnects
only that second owner. Pure cases additionally prove stale epoch, wrong
baseline tick/sequence/snapshot, ahead progress and mismatched byte count cannot
change credit, and that duplicates never add credit.

The fixture then starts **two actual production ClientReplicas** in a fresh
epoch on another 17-chunk map. It pauses the second receiver for 600 ms; the
first completes, the second recovers, both install exact canonical maps with
distinct living actors, and final coalesced ACKs drain to zero. All sockets and
listeners are released. The complete fixture took approximately 2.7 seconds on
the development host; authority scheduling has bounded catch-up and no input
traffic in this join test.

Logs are `.cache/logs/map-window-protocol.log`, `map-window-transfer.log`,
`map-window-runtime.log`, `map-window-backpressure-replica.log`,
`map-window-transport-final.log` and `map-window-input-clock.log`.

These are native bounded-flow and integrity tests, not proof of repaired
browser joins, TLS/WSS, background-tab survival, WAN throughput or 64 MiB joins.
Two freshly exported browser clients must still pass the original concurrent
join reproduction with concrete receiver errors and native aggregate counters.
