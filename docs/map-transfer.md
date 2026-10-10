# Ordered map transfer and transaction assembly

`game/network/map_transfer.gd` supplies pure `BlockfieldMapTransfer`, `TransactionAssembler`, `BulkWindow`, `BaselineSender`, `DeltaSender` and incremental preparation helpers using [BlockfieldProtocol](network-protocol.md) and `VoxelData`. It has no socket, scene, timer, renderer, preference or active-world reference. It prepares a joining map independently and emits it only at a verified barrier. The separate Runtime and ClientReplica integrate authentication, actor snapshots and installation; deployment/browser acceptance remain separate from this helper.

## Receiver API

| Method | Result / behavior |
|---|---|
| `configure(options)` | `{ok,error,status}`; known integer limits and boolean `incremental`, atomically checked while idle. |
| `reset(expected_epoch=0)` | Clears retained state and arms a new join. Positive epoch pins the expected match; `0` accepts a positive BEGIN epoch. Invalid epoch returns failure. |
| `consume(packet: Protocol.Packet, now_ms=-1)` | `{ok,error,status}`; accepts BEGIN/CHUNK/DELTA/END and validates with codec. Default incremental mode retains work for later polls. |
| `poll(now_ms=-1,max_chunks=1)` | Checks monotonic clock and join/partial-transaction deadlines, then performs one work phase with budget `1..32`. Caller must invoke regularly. |
| `cancel(reason="cancelled")` | Releases baseline, staging, complete/partial deltas, barrier and unclaimed ready data. Use on disconnect. Explicit reset required afterwards. |
| `take_ready()` | Once: `{ok,error,data:VoxelData,epoch,snapshot_id,map_sequence,tick,hash}`. Does not adopt into a World or spawn a player. |
| `get_chunk_ack()` | `{ok,error,packet?}`: owned copy of the latest accepted cumulative MAP_CHUNK_ACK. Tiny metadata survives ready handoff, and clears on failure/cancel/reset. Caller sends once per drained bulk batch. |
| `get_stats()` | Status/error, expected epoch/snapshot, baseline/staged/ready map bytes, next chunk, retained encoded-delta counts, `pending_work`, `work_phase`, decoded cells, apply records and final hash chunks. |

Normal states are `idle → receiving → ready → consumed`. A malformed/gapped/over-budget/timed-out join becomes terminal `failed` and releases everything. Cancellation is terminal `cancelled`. New BEGIN requires `reset()`; it cannot silently overwrite a partial transfer. Ready buffers also release on cancel/reset. `take_ready()` is a single ownership handoff, followed by another explicit reset before reuse.

`now_ms=-1` reads `Time.get_ticks_msec()`. Any injected clock is a trusted coordinator/test integer, not a network field: noninteger, negative other than sentinel `-1`, regressing or values above `0x7ffffffffffe0000` fail and clear retained state. Polling remains necessary for deadlines; no hidden timer runs.

Each poll processes at most the requested number of 16346-byte hash ranges, `4086 * max_chunks` decoded cells, or `512 * max_chunks` private transaction records, depending on the current phase. Budget is `1..32`; proposed runtime budget two means at most 1024 validation or write records, never 32 complete transactions. Only one private transaction applies at a time, and a phase transition returns before the next phase. This bounds work units, not elapsed milliseconds: native packed-buffer growth, frozen-copy detachment and container cleanup can still pause. `incremental=false` drains staging synchronously from `consume()` and exists only for explicit small fixtures/tools. Production callers use the default incremental mode, poll sockets first and schedule map work between simulation ticks; do not spin until `pending_work=false` in a production frame.

## Packet identity and ordering

The helper adds family semantics to the existing 24-byte protocol header; it does not change the codec schema:

| Family | Header epoch | Header tick | Header sequence |
|---|---|---|---|
| BEGIN | Positive match epoch | Frozen baseline `last_tick` | Baseline `map_sequence` |
| CHUNK | Same as BEGIN | Same as BEGIN | Same as BEGIN |
| CHUNK_ACK | Same as BEGIN | Same as BEGIN | Same as BEGIN |
| DELTA | Bound match epoch | Transaction tick | Transaction `map_sequence`, identical across fragments |
| END | Same match epoch | Barrier tick | Barrier `map_sequence` |

BEGIN pins snapshot ID, dimensions `(x,y,z)`, raw size, chunk count, baseline sequence/tick and SHA256. CHUNK must match the snapshot/epoch/size/tick/sequence and have the next contiguous index starting at `0`. Duplicate or out-of-order chunks require resync. Reliable per-socket ordering makes a reorder buffer unnecessary.

After accepted CHUNK bytes, `get_chunk_ack()` identifies the contiguous received prefix; it never grants credit for a rejected chunk. Final baseline hash failure clears the ACK along with other state. `BulkWindow` implements an eight-chunk send/receipt window; Runtime selects it through authenticated bulk-socket ownership. Its checks and cross-channel final ACK policy are documented in [map-backpressure.md](map-backpressure.md). The work budget two is for later decode/apply/hash, not a two-chunk incoming queue limit.

DELTA transactions must advance map sequence exactly by one and never regress tick. Each transaction's fragments begin at `0`, arrive contiguously and keep epoch, map sequence, transaction ID, tick, actor ID, action ID, dimensions, fragment count and total changes identical. Duplicate cells across fragments are rejected. The full transaction also rejects floor edits, no-op records and invalid authoritative collapse flags. After complete assembly, before colors are checked by the bounded private loading job or the live map's atomic `apply_transaction()`, depending on ownership.

END pins the target sequence, barrier tick and final-map SHA256. It may arrive before bulk chunks or the missing target deltas because reliable ordering on each of two sockets does not order the sockets against each other. One small END descriptor is retained. END must not precede the baseline or any already observed complete/partial transaction sequence/tick. No READY data appears while target deltas are missing.

Once END is known, deltas above its target sequence/tick are rejected by this loading helper. The future ClientReplica must hold post-barrier live messages separately, install the matching actor snapshot, then route complete live transactions to the adopted world. It must not keep feeding post-barrier messages into a finished join. Duplicate END fails explicitly.

## Baseline representation, hashes and compression

Only compression enum **0 (raw)** is implemented. Each cell is exactly four big-endian bytes: air `0`, solid `0x01RRGGBB`. Cell order is Godot-axis Y-fast:

```text
index = y + dimensions.y * (x + dimensions.x * z)
byte_offset = index * 4
raw_size = dimensions.x * dimensions.y * dimensions.z * 4
```

Each payload is at most 16346 bytes, so a full protocol CHUNK is 16 KiB. Boundaries can split a four-byte cell. Received bytes are appended only after exact codec/descriptor validation, at most the declared raw size. SHA256 is updated per chunk. All chunks must match BEGIN's **baseline** hash before the internal `SnapshotDecodeJob` creates a private `VoxelData`. It converts aligned byte batches with the runtime-probed native endian helpers and validates every resulting color before packed `append_array()`. Unknown native layouts use scalar BE decoding. Storage grows across polls; no up-front full-map `clear()` or scalar per-cell copy loop runs. Its color and ordering rules match `VoxelData.load_snapshot_bytes()`; it does not call that synchronous whole-map method. No stage is exposed until every cell validates and the complete declared cell count is present. The raw byte buffer then releases.

Whole buffered transactions update that private stage in sequence through an internal `TransactionApplyJob`. Validation checks metadata, all changes, duplicates and before colors in bounded batches; **every before-color check finishes before the first write**. Writes then progress in private batches. Sequence/tick advance only after all writes complete. The receiver exclusively owns this unopened stage and emits no intermediate data; failure/cancel releases the entire stage, including partially written bytes. Further complete transactions may queue within the same retention bounds while one job runs. `work_phase` reports `apply_validate` / `apply_write` and `apply_records` reports progress in that phase.

The loading job does not rerun terrain support or reconstruct historical falling visuals: authoritative removal flags are validated, but an unopened baseline needs only final cell state. No journal is retained. This is **not** a replacement for live `VoxelData.apply_transaction()` or `World.apply_map_transaction()`, whose existing atomic writes and presentation events are unchanged. Incremental SHA256 of the edited stage must match END's **barrier** hash before adoption. BEGIN and END hashes can differ after edits. Ready data records END's tick; hashing verifies content integrity, not sender authentication.

Compression enum **1 (reserved Zstandard)** returns an explicit unsupported error before baseline buffer allocation. Godot's [PackedByteArray documentation](https://docs.godotengine.org/en/4.7/classes/class_packedbytearray.html) provides fixed-size `decompress(buffer_size, mode)`, but bounded `decompress_dynamic(max_output_size, mode)` accepts only brotli/gzip/deflate. This slice does not claim validated handling of hostile/truncated Zstandard frames, consume arbitrary Variant serialization, or call an unbounded decompressor. Raw transfer is usable; compressed throughput remains a later, separately verified optimization.

The baseline currently carries only cells/dimensions/epoch/sequence/tick. Custom water/wade metadata, map title, actors, projectiles, block-health state and objectives are not encoded here; standard `VoxelData` water defaults apply until a future metadata contract exists.

## Budgets and lifecycle

| Receiver option | Default / maximum | Minimum |
|---|---:|---:|
| `max_buffered_bytes` | 8388608 encoded bytes | 1 |
| `max_buffered_changes` | 32768 records | 1 |
| `max_transactions` | 128 retained complete transactions | 1 |
| `timeout_ms` | Default 240000; maximum 600000 | 100 |
| `incremental` | `true`; boolean | — |

Baseline is separately bounded to 64 MiB, dimensions at most `512×64×512`. A maximum-size descriptor does not preallocate 64 MiB: bytes grow as valid chunks arrive. Whole transaction count includes the next partial transaction admission; partial records/encoded bytes count toward aggregate join budgets. A declared transaction exceeding the change cap is rejected before retaining its first fragment. Buffer budgets count retained messages, not all historical edits already applied to the private stage. After staging can consume a transaction, its retained records release.

Encoded bytes are an accounting limit, not a precise GDScript heap estimate. Dictionaries, duplicate-cell sets and container overhead are additionally bounded by record/transaction counts. Decoding a full raw map temporarily holds raw bytes plus the packed voxel array: up to 128 MiB of cell payload alone. The unused bytes release after successful decode. Renderer/old active map/server snapshots have separate allocations. The coordinator must cap simultaneous joins and server-wide retained snapshots; the proposed runtime starts with two concurrent joins and a two-range poll budget, but neither runtime limit is implemented by this helper.

Any active-transfer failure, timeout, cancel, disconnect cancellation or epoch reset clears partial and complete changes, byte buffer, hash context, stage, barrier and ready reference. Calls after `ready` are rejected without changing the valid pending handoff; the coordinator routes later messages or cancels it. Existing maps remain untouched during failure. Server resets require a new epoch and a fresh join; retained transactions cannot cross it.

## Live TransactionAssembler

`BlockfieldMapTransfer.TransactionAssembler` is usable independently after join:

```gdscript
var assembler = BlockfieldMapTransfer.TransactionAssembler.new()
assembler.reset(data.epoch, data.map_sequence, data.dimensions, data.last_tick)
var result = assembler.push(packet) # codec-valid MAP_DELTA only
if result.ok and result.get("complete", false):
    # Pure server/replica tests: data.apply_transaction(result.transaction)
    # Adopted rendered replica: world.apply_map_transaction(result.transaction)
    pass
```

API: `reset(epoch, sequence, dimensions, tick=0)`, `push(packet, now_ms=-1)`, `poll(now_ms=-1)`, `cancel(reason)`, `get_stats()`. Result on final fragment has `complete=true`, `transaction` and encoded `wire_bytes`. Partial results have no transaction. Public local limits `max_changes`, `max_wire_bytes`, `timeout_ms` clamp to the same hard change/byte caps and `100..120000` ms; standalone timeout defaults to 10000 ms. The joining receiver forwards its timeout, subject to this partial-transaction maximum, and polls partial deadlines even while waiting for bulk data. The assembler validates structure/identity and advances its sequence on completed output; a failed subsequent `apply_transaction()` requires resync, not continuing that stream.

Apply only once. `World.set_map_data(ready.data,title)` adopts the same writable Data object. After adoption, mutate via `world.apply_map_transaction()` so rendering/edit events fire; applying to Data first and then the World wrapper would double-apply and reject the sequence. Pure authority or loading stages can apply to Data directly. No support traversal is computed by the assembler.

## Lazy sender helpers

Production `prepare_sender(data,snapshot_id)` validates metadata, obtains an independent `frozen_copy()` packed container, then returns `{ok,error,job:HashPreparationJob}` without scanning the entire map. `job.advance(max_chunks=1)` hashes `1..32` ranges and returns `{ok,error,status,done}`. Only `done=true` permits `job.take_sender()`; the once-only result is `{ok,error,sender:BaselineSender}`. `cancel()` releases the map/context; `get_stats()` includes processed chunks, retained logical map bytes and frozen-container setup microseconds. No full serialized baseline or array of all chunks is created.

`BaselineSender.begin_packet()` returns BEGIN. `next_chunk()` returns `{ok,error,done,packet?}` and serializes one range only; the caller sends or queues that packet before requesting more. `prepare_end(barrier_data)` validates epoch/dimensions/nonregressing sequence/tick, freezes the barrier and returns a preparation job; advance it over subsequent frames and call `take_packet()` once to obtain `{ok,error,packet:MAP_END}`. The barrier snapshot captures its sequence/tick at preparation time even if the authority keeps editing. End may be prepared before all chunks have been emitted. `cancel()` releases the sender's frozen map, and `get_stats()` reports retained map bytes/next index. A cancelled sender returns null BEGIN and failed chunk calls.

`make_sender(data,snapshot_id)`, `BaselineSender.end_packet(barrier_data)` and `hash_data(data)` remain explicit synchronous tools for small fixtures/offline work. They scan all map ranges in the calling operation and must not be used in a production fixed-tick/poll loop.

Packed assignment aliases live mutation; `VoxelData.frozen_copy()` explicitly duplicates the packed container, and mutation tests prove snapshot independence. In the measured Godot 4.7.2 native build, container duplication was fast while the first live write after cloning took approximately 38 ms on a 64 MiB map. This is consistent with deferred physical copying; preparation alone is not proof that all memory/copy cost has already been paid. A retained baseline/barrier may cause a later authority write to copy the full map. Budget for separate map storage and measure mutation timing on the target platform.

`make_delta_sender(transaction)` validates the **entire** transaction, including cross-fragment duplicate/semantic records, before creating `DeltaSender`; extra native transaction outcome fields are ignored rather than serialized. It copies at most 32768 validated change records. `next_fragment()` returns one packet with at most 2048 changes, preserving source order. `cancel()` releases retained records; `get_stats()` reports count/index. A single authority edit above the retention change cap requires a new baseline/resync policy, not an oversized delta. Sender whole-transaction setup and live atomic application remain synchronous; the caller owns scheduling and snapshot/journal lifetime.

Streaming hashes use Godot's [HashingContext SHA256 API](https://docs.godotengine.org/en/4.7/classes/class_hashingcontext.html). They run on the caller's thread in bounded advances, without a background thread. The receiver's final hash borrows only its isolated private stage, so it requires no additional frozen clone.

## Native maximum-map timing probe

Optional reproducible probe, without main scene, settings, sockets or renderer:

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_map_transfer.gd -- --benchmark-map-transfer
```

Godot 4.7.2 `ed1daf0bf`, Windows native headless, `512×64×512` all-air map (64 MiB), `.cache/logs/map-transfer-benchmark.log`. Both encoder paths run in the same process; scalar bytes are compared with native bytes exactly. Full decoder advances to completion rather than sampling only early growth:

| Operation | Measured time |
|---|---:|
| Initial packed map allocation diagnostic | 35.42 ms |
| Frozen container + job setup | 0.17 ms |
| First live write while frozen map retained | 37.51 ms |
| Previous scalar 16346-byte BE range / optimized native range, means of ten | 3.155 / 1.098 ms |
| Native range + SHA256 advance, mean of ten / maximum | 1.302 / 1.673 ms |
| 64 MiB raw receive-buffer allocation diagnostic | 39.79 ms |
| First incremental decode advance / next advance | 1.099 / 1.112 ms |
| Full decode: 4107 advances, mean / maximum | 1.252 / 36.794 ms |
| Full decode wall work summed over advances | 5143.42 ms |
| Private validation: 512 records, mean / maximum of 64 units | 4.824 / 7.984 ms |
| Private writes: 512 records, mean / maximum of 64 units | 1.112 / 2.549 ms |
| Private 32768-change loading apply, total work over 128 units | 379.97 ms |
| Unchanged live atomic apply of 32768 changes, journal disabled | 548.38 ms |

Before this optimization, isolated first decode (up-front map allocation) took 41.72 ms and subsequent scalar decode 1.88 ms; the then-sampled range plus hash took 3.00 ms. The new full-map trace demonstrates that removing the up-front allocation does **not** eliminate pauses: one append/decode advance took 36.79 ms at step2956. Its exact cause (buffer growth, allocator or OS scheduling) was not instrumented. Native append is count-bounded, not a guarantee of constant frame time.

These are local samples, not percentile or browser measurements. The receive path grows its buffer as chunks arrive; the single large raw allocation above measures the diagnostic fixture, not one normal CHUNK handler. A 64 MiB baseline requires 4106 hash ranges and 4107 decode advances at budget one. Two ranges per 60 Hz poll require at least roughly 68.5 seconds for decode plus final hash, excluding download, sender preparation and transaction application. This scheduling lower bound is arithmetic, not measured throughput. Private loading validation/writes now span polls; live atomic application, deferred snapshot copy and occasional allocation growth still exceed or may exceed a 16.7 ms tick. Sustained 60 Hz maximum-map joining and live large-transaction frame safety remain unproven.

## Verification and remaining integration

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_map_transfer.gd --verbose
```

Godot 4.7.2 `ed1daf0bf`: **799 assertions, 0 failures**, `.cache/logs/map-transfer-tests.log`; standalone parser check passes. No Godot error, warning or leaked-object report. Original 720 checks remain. Additional checks cover bounded private before-color validation, cross-batch duplicates, metadata withheld during private writes, equality with live atomic outcomes, queued edits during apply and disconnect after private writes. Existing checks include an independent Python SHA256/byte golden, three raw chunks with unaligned cell boundaries, frozen sender/barrier isolation, incremental preparation/decode/hash budgets and cancellation, once-only handoffs, explicit synchronous fixture mode, two replicas converging through authoritative collapse/repaint with early/late END, a 3000-change live transaction committed only after full assembly, malformed/truncated/corrupt chunks, canonical color errors, both hash failures, all identity/ordering checks, complete/partial duplicates, before-color atomic rejection, count/byte/transaction budgets, max64MiB descriptor boundaries, production default deadline, timeout/clock/cancel/disconnect/epoch reset clearing.

Read-only regression of `tests/network/test_server_runtime.gd` after optimization: **103 assertions / 0 failures**, two actual game/bulk WebSocket clients, `.cache/logs/server-runtime-transfer-performance.log`. This demonstrates compatibility with that native coordinator test, not public WSS/browser acceptance.

The 64MiB maximum descriptor is validated without a giant allocation; the optional probe measures isolated allocation/range/whole-decode/apply costs, not a complete maximum-map socket join or browser memory. The separate Runtime/Replica now handle authenticated direction, two concurrent joins and state-barrier installation. Exported mid-round WSS/browser acceptance remains a release concern; this helper alone does not complete N04 acceptance or the multiplayer iteration.

Receive-credit slice: current pure transfer suite **958/0**, protocol **1759/0**, Runtime **103/0**; actual larger-than-window native fixture **39/0**. Logs `.cache/logs/map-window-{transfer,protocol,runtime}.log` and `map-window-backpressure-replica.log`. These extend the historical performance checks above without changing the measured encoding/decode algorithms. See [map-backpressure.md](map-backpressure.md) for exact scenarios and limits.
