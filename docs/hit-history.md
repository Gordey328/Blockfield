# Same-time hit history

`game/network/hit_history.gd` is a pure bounded `BlockfieldHitHistory` service. It keeps public actor poses and inverse committed terrain changes at the same canonical server tick. It contains no socket, input admission, damage/kill decision, renderer, timer or complete-map snapshot. `ServerRuntime` now records closed frames and committed receipts, admits owned input ticks, and supplies this service to `MatchSimulation`'s shot planner. That integration exists; public WSS/browser multiplayer acceptance remains separate.

## API and clock

| Method | Contract |
|---|---|
| `configure(window_ticks=15,max_changes=32768,max_bytes=8388608)` | `{ok,error}`; window `0..15`, records `1..32768`, encoded bytes `1..8MiB`. Configure before reset or after cancellation/invalid history. |
| `reset(epoch,data:VoxelData)` | Pins the exact writable authority object, positive epoch, dimensions, water metadata, map sequence and `data.last_tick`. Does not invent an initial actor frame. |
| `record_frame(tick,data,actors:Array[SharedPlayerState],transactions:Array[Dictionary])` | `{ok,error}`; first tick equals the pinned baseline tick, thereafter exactly previous tick +1; `data.last_tick` equals the recorded tick. |
| `query_at(request_tick,current_tick)` | `{ok,error,query:HistoricalVoxelQuery,actors:Array[Dictionary],tick,map_sequence}` on success. `current_tick` must equal the latest recorded tick; requested tick must have an exact retained frame. No future/clamped/nearest-frame fallback. |
| `cancel(reason)` | Releases retained history and revokes outstanding query leases. |
| `get_stats()` | Status/error, epoch/latest/oldest tick, map sequence, frames, transactions, records, encoded bytes/window; `cache_entries`, `cache_records`, `cache_cells`, `cache_indexed`, cumulative `cache_builds`/`cache_hits` since reset. |

The caller records once per completed canonical 60 Hz frame, after all actor updates and committed map receipts. Reset before tick0 on a fresh map whose `last_tick=0`, then record tick0 explicitly; a mid-match reset records the pinned current tick first. The helper does not advance the simulation or infer a missing tick. A map/frame/receipt/generation gap or capacity overflow invalidates and clears history. Recover explicitly with a trusted reset and fresh current frame.

At most **16 frames** are retained, inclusive of latest and 15 ticks earlier. Window zero keeps only current poses. A frame contains at most 32 actors. Transactions at/before the oldest frame are removed because that frame already reflects them; only changes needed to rewind newer map sequences remain. Byte accounting uses 15 bytes per change plus 56 bytes per 2048-record MAP_DELTA fragment; it is a wire estimate, not a GDScript heap measurement. Per-frame incoming records/bytes also obey configured caps before full retention. Dictionaries and sets add bounded overhead. No 64 MiB packed baseline is allocated per frame or query.

## Trusted receipts and map validation

`record_frame` accepts **only receipts already committed by the authority**. Never feed client-proposed map transactions to this service. The caller's map is current post-commit state; history never applies or rolls back it.

Receipts require positive epoch/map sequence/transaction ID, bounded actor/action/tick identities, exact matching dimensions, contiguous map sequence, nonempty records and transaction tick equal to the recorded frame. Every change validates cell/type, canonical air/solid color, immutable y0, no-op rejection, collapse flags and duplicate cells within one transaction. Different ordered transactions may edit the same cell. The final receipt sequence must equal the live map sequence; missing receipts invalidate history.

Reverse walking checks each latest after color against current terrain and joins successive before/after colors for repeated cells. Cells with known prior retained edits must also match their previous recorded after color. A first-ever cell's before color cannot be independently reconstructed from a post-commit map without old storage; it is trusted as a committed `VoxelData` receipt. Canonical before values, chain consistency and actual final after values are still checked. This boundary is deliberate and does not authenticate arbitrary transaction claims.

Inverse timelines restore authoritative primary and collapse removals together. No support search, replica collapse decision, historical falling mesh or journal mutation runs. Public map mutations during play must go through sequenced transactions: raw writes/`seed_box()` that preserve identity bypass this guard and are unsupported trusted-caller misuse. Sequence identity distinguishes repaint/remove/recreate receipts even when the color returns to its old value. Match's later historical-color/current-color guard cannot distinguish a newly recreated block of identical color; block incarnation IDs are not part of this schema.

## Public actor poses and lives

Each copied pose contains:

```text
id, spawn_generation, epoch, team, alive, connected, pose_valid,
feet, physics_eye, front, yaw, pitch, crouch
```

Poses are ordered by stable actor ID. No transport ID, private ammo, cooldown, input queue or RNG object is exposed. Feet/eye/front are value copies; returned pose dictionaries cannot modify retained history. Physics eye uses source standing2.25/crouch1.35 offsets; front comes from captured yaw/pitch. Actor epochs/IDs/generations are bounded; duplicates, retained generation regression, invalid health/angles and future actor ticks invalidate the frame. Generations are observed values, never generated by this module.

Inactive source spectators may contain nonfinite feet. Those become finite zero coordinates with `pose_valid=false` and `alive=false`; they must never be hit. Live nonfinite feet are rejected. Dead/disconnected poses remain captured for life transitions, but the damage coordinator must filter their eligibility.

The authoritative damage caller must validate the admitted command tick and current shooter life, then use the historical shooter's `physics_eye` with admitted aim, and test historical target volumes against the **same query's** terrain. Before applying damage, check current target eligibility and `spawn_generation == historical.spawn_generation`; an old hit must not damage a respawned life. This service neither selects a rewind tick from a client timestamp nor authorizes damage. Missing history requires an explicit Match policy; mixing old actors with current cover is unsupported.

## HistoricalVoxelQuery lifetime

The query derives from `VoxelData` with an empty packed array, a private live authority reference, an independently cancellable lease and a shared immutable closed-frame query context. The inherited DDA and ClipWorld dispatch to the overridden `get_block()`; native behavioral tests verify this dispatch. Supported narrow surface is `dimensions`, `water_level`, `wade_origin_level`, `get_block`, `clip_world`, `cast_voxel`, `is_valid` and `cancel`. General Data mutation/serialization is not its contract; inherited mutations are blocked with `read_only=true`.

`is_valid()` pins the current authority epoch/map sequence/last_tick/dimensions/count/water values, the shared context's revocation state and the lease's exact requested tick/map sequence. It becomes false when the authority advances, metadata changes, the lease is cancelled, or history records/resets/cancels/invalidates. Cancelling one lease leaves other leases and the context usable. Use the query immediately inside the owning fixed-step critical section and check it again **before applying damage**. Do not retain it for later network polls. A query's past tick/map sequence is separate from this current live-storage guard.

Stale `cast_voxel()` returns `{hit:false,valid:false,error:"stale historical query",...}`. Callers must check `valid`, not interpret that as clear terrain. Stale `get_block()` returns solid black and `clip_world()` returns true to fail closed, recording `last_error`. The shared cell dictionary, each integer timeline and authority identity dictionary are frozen with `make_read_only()`. Returned actor arrays remain independent deep copies. Direct access/assignment to private helper fields is outside the supported surface; this is not a sandbox for untrusted server scripts or client objects.

## One bounded closed-frame cache

The first request for an older map sequence builds a chronological cell index from the retained committed receipts. Each cell's frozen integer array contains `[sequence,before,sequence,before,...]`. `get_block()` uses binary search to select the first change strictly newer than the requested frame's map sequence, then returns that change's before color. A cell with no newer change uses the live authority color. Repeated cells across transactions and collapsed cells use the same rule; no float32 or signed32 sequence conversion occurs.

All requested ticks in the same latest closed authority context share this one index. The index stores at most the retained change count, capped at 32768 records and the configured 8 MiB wire estimate; it does not allocate one change-sized overlay per actor or per historical frame. A current-map query does not build unused historical terrain. If a later request needs old terrain, the service installs a fully frozen index into the same context; existing current-map leases retain identical results. Construction is synchronous and occurs only on the trusted single-thread fixed-step path.

Successful frame recording, reset, cancellation or invalid history revokes the old context and releases its change-sized dictionary even if callers retain old query objects. A query request that observes an unrecorded authority advance also revokes/releases the cached context. Unsupported raw cell writes which keep epoch/sequence/tick unchanged remain undetectable, as before. The service retains one context, at most 16 pose frames and one bounded receipt journal. GDScript heap overhead is unmeasured; the 8 MiB value is encoded receipt accounting, not a heap cap.

`cache_builds` counts full index construction, `cache_hits` counts reuse of the current context, and both saturate at uint32 and reset on `reset()`. Revoking a context sets its records/cells to zero. Requests without older terrain may have `cache_entries=1` and `cache_indexed=false` with zero index records.

## Verification

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_hit_history.gd --verbose
```

Godot4.7.2 `ed1daf0bf`, native standalone: **350 assertions / 0 failures**, `.cache/logs/hit-history-optimized-tests.log`; standalone parser passes. No Godot errors, warnings or leaked-object reports; no main scene or preference writes. Fixtures retain the original 269 behavior checks and add recursively frozen timelines, same-context reuse across different requested ticks, independent actor copies/cancellation, release of retained contexts after record/reset/cancel/overflow, stale metadata guards, lazy current-map queries and exact uint32 sequence comparisons near wrap. Source `LabHitVolumes` (`Player.cpp:1316–1385`) standing/crouched head distance10.7 and crouched legs, old cover, moved actors, generations, collapse/repaint chains and inherited DDA/ClipWorld still pass.

The existing unchanged `test_match_rewind.gd` also passes **441/0**, `.cache/logs/match-rewind-cache-tests.log`: actual Match preplanning of all shots before damage/terrain mutation, same-time cover/actors, life/color guards and missing-history denial. Runtime calls `step_fixed(commands,_shot_ticks)` and records history after the closed step. These are native integration facts, not public WSS/browser timing or full N03 acceptance.

## Native performance probe

Opt-in focused mode avoids sockets/Main/preferences and leaves the earlier loaded-workstation capacity baseline intact:

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/benchmark_server_capacity.gd -- --history-only --output-name=history-query-cache.json
```

On Windows/i5-10400H (4 cores/8 logical), pinned official editor binary, a closer paired pre-cache run measured 32 repeated queries over 32768 changes at **546.092 ms mean** (three groups), and one actual 32-shot step at **752.053 ms**. Three final cached runs each pass **194/0**; their nine warm 32-query groups average **3.061 ms**, with group means 2.999..3.178 ms. The first cold index/query is **44.834..49.813 ms**. Three actual 32-shot steps explicitly evict the index first and include its cold rebuild: **259.006, 261.457, 325.522 ms** (mean281.995). Every run plans32 shots, denies0, and retains one context/32768 records. Historical actor copies, source pellet rays and Match rules remain active.

The warm group improvement is about178× in this fixture; the observed actual shot step is about2.7× faster against the single nearer baseline sample. First index construction is slower than one old uncached query (~18 ms), and frame-to-frame CPU load was not isolated. This is not a statistical capacity certification. The original 156-second multi-slice benchmark ran under heavier workstation load and is not used for this speedup ratio. Evidence/hashes: `.cache/benchmarks/history-query-baseline.json`, `history-query-cache-final-1.json` through `-3.json`; corresponding logs under `.cache/logs/`. Final history SHA256 `479f6c7fe4e6e819b8e23374ee665924548932eae22fedb2f0e90c238fcec1a7`; Match/RULES/Data and original hit-volume code are unchanged between the paired runs.

This fixes repeated index construction, not sustained60 Hz. Full 32768-cell transaction application (~247..254 ms), history record/validation (~183..217 ms), one cold index build and the remaining source actor/pellet work remain synchronous. Live transaction frame safety, Linux release performance, real paced socket capacity, WAN/TCP conditions and browser/WSS remain separate measurements.
