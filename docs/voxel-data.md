# Shared voxel model

`game/world/voxel_data.gd` is the iteration-2 `VoxelData` model. It extends `RefCounted` and depends only on the existing pure VXL codec and Godot math/packed containers. It has no scene, mesh, shader, physics-server or audio dependency. The offline `VoxelWorld` now composes one `.data` object and delegates its queries, bootstrap, VXL serialization, edits and support-collapse decisions to it. Rendering, chunk collision generation, water, AO, irradiance and falling presentation remain in `VoxelWorld`.

This extraction implements shared map rules and atomic transactions. It does not itself implement sockets, server command authorization, actor simulation, compression, fragment assembly, hash verification, prediction or a complete match snapshot. Those are coordinator/transport responsibilities described in [multiplayer-plan.md](multiplayer-plan.md) and [network-protocol.md](network-protocol.md).

## Storage and bootstrap

Axes are Godot `(x east, y up, z south)`. One cell occupies `[cell, cell + Vector3.ONE]`. Air is `0`; solids are exactly `0x01RRGGBB`, including solid black `0x01000000`. `PackedInt32Array blocks` uses the existing Y-fast index:

```text
index = y + dimensions.y * (x + dimensions.x * z)
```

Dimensions are bounded to x/z `1..512` and y `1..64`; a native map has 16,777,216 cells and 64 MiB of packed colors. A new object has no allocated map. Initialize it with `clear(dimensions, epoch)` or `generate_lab(epoch)`. Epoch must be a positive u32. Both reset map sequence/tick/journal; the caller owns the session's canonical epoch change. `generate_lab` creates the exact existing 96×32×96 arena, including firing lanes, bridge, trench and pool, without creating any scene node. The offline scene's reset/import increments its own epoch and rejects overflow rather than silently wrapping.

`seed_box(start, end, color)` fills a clipped, exclusive-end box for trusted bootstrap/fixtures. It creates no transaction, support search or journal record. `blocks`, dimensions and metadata are mutable members for the trusted codec/bootstrap boundary; direct changes after play starts bypass replication and must not be used for gameplay. The legacy `VoxelWorld._blocks` and dimensions properties forward to this storage for renderer/test compatibility; generation writes bulk data directly rather than repeatedly modifying a packed-array property.

`get_block`, `is_in_bounds`, `index`, `column_top`, `clip_box`, `clip_world` and `cast_voxel` are data queries. Their DDA, clipping and lower-layer semantics preserve the previous world implementation. Horizontal boundaries are solid for ClipBox and air for ClipWorld; above-map positions are air, below-map positions solid, and y=0 collision aliases y=1. Native water metadata is exposed as `water_level=1.0`, `wade_origin_level=2.0` for the shared source movement query contract. Rendering water-off does not change these physical coordinates.

## Authority transactions

`set_block(cell, color, metadata={})`, `remove_blocks(typed_cells, protect_lower_layer=false, metadata={})` and `explode(position, metadata={})` return dictionaries. Metadata permits only integer-u32 `tick`, `actor_id`, `action_id`, `transaction_id`; transaction ID must be positive when supplied, and tick cannot regress. Defaults are the current tick, system actor/action0, and the committed map sequence as transaction ID. Local colors retain the previous normalization to `0x01RRGGBB`; remote colors are strictly validated. Layer y=0 is immutable through edits. Protected batches and explosions preserve both y=0 and y=1. Explosion terrain removal is the source's centered 3³ cube.

After removals, authority performs the existing down-priority six-neighbor support search. A component survives if connected to either bottom layer; traversal stops immediately when that support is proved. Unsupported components are removed in the same transaction as the primary edits. The implementation preserves the port's local search rather than the native maintained link forest. Already floating imported terrain is only examined when affected by a removal, as before.

Successful result:

```gdscript
{
    "ok": true, "error": "", "changed": true,
    "epoch": 7, "map_sequence": 1, "transaction_id": 11,
    "tick": 40, "actor_id": 3, "action_id": 90,
    "dimensions": Vector3i(96, 32, 96),
    "changes": [
        {"cell": Vector3i(2, 2, 3), "before": 0x01cc2211, "after": 0, "flags": 0}
    ],
    "collapse_groups": [
        {"cells": typed_vector3i_array, "colors": packed_int32_array}
    ]
}
```

`flags=1` identifies an authoritative collapse removal; all primary edits use0. There is exactly one `map_sequence` increment for a nonempty transaction, regardless of its number of edits/groups. No-ops return `changed=false` without consuming sequence/tick or retaining history. Failures return `ok=false`, a short `error`, `changed=false` and empty changes/groups. Sequence exhaustion requires a session rebase/reset before another edit.

Each `changes` entry has exactly the four fields used by MAP_DELTA. The full result has runtime-only success/group fields and cannot be passed directly to the strict protocol encoder: the fragmenter selects packet payload fields and puts epoch/tick in the envelope. Sender authentication, legal tools/reach/cadence and action ownership are deliberately outside this model. A valid map transaction is not evidence of an authorized player action.

## Replica application and rendering ownership

`apply_transaction(full_transaction)` accepts a complete assembled transaction, not an individual fragment. It validates positive identity values, expected epoch, exactly the next map sequence, nonregressing tick, matching dimensions, bounded record count, every cell/type/color/flag, duplicates and **all before-color comparisons** before writing any cell. A late conflict leaves map, sequence, tick and journal intact. Gaps/duplicates/old epochs are rejected; the session requests a fresh baseline rather than guessing.

Replica application never runs support collapse. Cosmetic groups are reconstructed only from the authoritative collapsed-cell flags and pre-removal colors. This prevents a second decision based on different client terrain. The model returns removed groups; no mesh is created and no fallen block is reinserted.

`VoxelWorld.set_map_data(validated, title)->Error` adopts an already validated, writable `VoxelData` object from the receiver. It checks dimensions/count/epoch/sequence/tick/read-only/finite water metadata without scanning or copying the palette. It clears old meshes, collision nodes, topdown cache, falling groups, water targets and irradiance, computes a spawn from the center column and rebuilds through the same path as VXL import. Invalid adoption leaves the old model and presentation intact. This is a trusted model handoff; raw bytes must have passed `load_snapshot_bytes` or the VXL codec first.

The receiver/coordinator and scene then share **one object**. During loading, the receiver may apply ordered transactions to its staged model before adoption. After rendering owns that model, apply each confirmed transaction once through `world.apply_map_transaction(transaction)`, which commits Data first, invalidates presentation caches, creates cosmetic groups and emits the existing `blocks_changed` records `{cell,before,after,collapsed}` plus `map_transaction_committed(full_transaction)`. Pure servers apply directly to Data. Never apply to the shared Data and then apply the same transaction through World: the second application is correctly rejected and cannot create the missing first visual event. Data edits performed directly on an attached model likewise do not invalidate scene caches.

Existing local World edit methods still return `void` and delegate through this presentation boundary; their public arguments and event shapes are preserved. The new transaction signal emits once for accepted changed local or remote transactions. A baseline install emits `map_loaded`, not individual edit events.

## Journal and immutable baselines

The default retained history is bounded by **8 MiB of estimated MAP_DELTA wire bytes, 128 transactions and 32,768 change records**, whichever is reached first. Wire cost includes the 15-byte changes plus 56 bytes of envelope/prefix per 2048-record fragment. It is not an exact GDScript heap measurement; the record/transaction caps also bound retained Dictionary overhead. `set_journal_budget(bytes, transactions, changes)` can reduce these limits. Histories returned by `transactions_since(map_sequence)` are independent deep copies. Eviction, a transaction larger than the journal budget, or a disabled journal produce an explicit gap for older cursors. The terrain transaction still commits; a joining replica needs another baseline. Transaction memory during a very large collapse is not limited by the history cap.

`frozen_copy()` returns a read-only snapshot with frozen dimensions/epoch/map sequence/tick/water values and explicitly duplicated packed storage. Plain GDScript packed-array assignment shares mutable state; tests demonstrated that it changed an in-progress baseline, so assignment is insufficient. The explicit duplicate preserves the baseline during later authority edits. API mutation methods reject a frozen model; trusted code must also leave its public containers/metadata untouched. Budget one native packed snapshot as up to another 64 MiB; the transfer manager must bound concurrent snapshots.

`snapshot_bytes()` and `snapshot_range(byte_offset, byte_count)` emit the network schema's raw four-byte **big-endian** colors in Y-fast order. Arbitrary ranges, including the protocol's unaligned 16,346-byte chunks, are supported; invalid bounds or noncanonical colors return an empty byte array. Use ranges on the frozen copy across frames, never a changing live model. This is a raw network baseline, not native VXL or a generic Variant serialization.

`load_snapshot_bytes(bytes, dimensions, epoch, map_sequence, tick=0)->Error` checks descriptor bounds/exact byte count, decodes and validates every color into a temporary packed array, then replaces the entire map/metadata and clears history. Truncation or a malformed last color preserves the previous map. Snapshot hash verification and compression belong to transfer code. `load_vxl_bytes(bytes, epoch)` similarly installs only a successful existing VXL decode. `encode_vxl()` retains the native map exporter and its padded-small-map behavior documented in [voxel.md](voxel.md).

## Verification and measured limits

Godot `4.7.2.stable.official.ed1daf0bf`, Windows headless:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/world/test_voxel_data.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/world/test_voxel_adapter.gd
```

Pure Data: **171 assertions / 0 failures**. The original 110 checks remain, with additional packed-conversion/byte-order goldens, first/last partial cell checks, invalid palette neighbors and returned byte-buffer independence. Fixtures cover source query/bottom-layer/DDA behavior, exact BE colors/unaligned ranges, atomic late conflicts and malformed transactions, collapse flags/groups, replica non-collapse, immutable snapshot plus later journal, record/byte/count evictions, malformed snapshots and the committed genuine `Title.vxl` (3,778,939 occupied cells). The test does not preload World or create scene/physics nodes.

World adapter: **25 assertions / 0 failures**. It exercises the real mesh/collision/topdown/falling/water/GI caches, adoption/spawn/metadata, subsequent confirmed collapse, unchanged legacy events, duplicate application and invalid baseline preservation. Existing suites also pass: world30, falling/water21, VXL save19, topdown13, lighting30, water18, irradiance18 and reflection19, all with zero failures. Fixtures come from committed assets; `.cache/openspades` is not required to run them.

The optimized `snapshot_range()` copies only covering packed cells, validates their entire palette (including partial edge cells), converts to bytes and trims the requested range. Official [PackedInt32Array](https://docs.godotengine.org/en/4.7/classes/class_packedint32array.html) and [PackedByteArray](https://docs.godotengine.org/en/4.7/classes/class_packedbytearray.html) APIs provide slice/conversion/32-bit swap operations. Their encoding order is an implementation detail, so `packed_byte_order()` probes both conversion directions once: detected little endian swaps to BE, detected big endian retains BE, and unknown layouts use explicit scalar bytes. The external schema is unchanged. A 16,346-byte request retains at most 4,088 covering cells and small conversion buffers, rather than serializing the entire map.

Windows native 4.7.2 local probe on a 64 MiB map: the previous scalar range averaged **3.155 ms**, optimized range **1.098 ms**, and bytes matched exactly across ten unaligned ranges. Genuine Title load/count was **2.024 s**, with its sampled native range **1.060 ms**, in the test run. Explicit frozen-container duplication measured **0.169 ms**, while the first live write with that snapshot retained took **37.513 ms**: independence is verified, but physical copy cost was deferred. Treat snapshots as potentially another 64 MiB and budget later mutation cost; setup time alone does not prove that storage was copied eagerly.

`BlockfieldMapTransfer` now decodes private packed batches and applies loading transactions across polls; see [map-transfer.md](map-transfer.md) for timings and exclusive-stage requirements. This does not change Data's live `apply_transaction()`, which still validates and commits a full transaction atomically: the same probe measured **548.378 ms** for 32,768 changes with journal disabled. `load_snapshot_bytes()` and full serialization likewise remain synchronous tools. Mesh rebuilds and large support searches are outside this optimization. Native samples are not browser or sustained fixed-tick acceptance; buffer-growth/deferred-copy pauses and exported WSS join behavior still need runtime measurements.
