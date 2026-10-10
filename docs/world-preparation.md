# Incremental World presentation preparation

`VoxelWorld` can adopt an already validated network map without rebuilding all
nearby geometry or scanning every image column in its installation callback.
`VoxelData` remains the immediately available authority/query model. Preparation
does not advance simulation, apply another transaction or rerun support collapse.

## Public contract

```gdscript
set_map_data(validated: VoxelData, title: String = "Network map", deferred_visuals: bool = false) -> Error
get_topdown_image() -> Image
get_topdown_image_progressive() -> Image
is_topdown_pending() -> bool
advance_visual_preparation(max_columns: int = 4096, max_usec: int = 2000) -> Dictionary
get_visual_preparation_stats() -> Dictionary
```

The default `set_map_data` remains synchronous, including initial streamed chunk
meshes/colliders and water creation. The opt-in third argument preserves the same
atomic validation, data adoption, old-node detachment, spawn calculation and
`map_loaded` notification. It queues new chunks and a water-bottom image instead
of flushing them before returning. The image allocation is full resolution, but
no per-column floor-color loop runs in that callback. Source movement, clipping
and voxel rays immediately query the new data independently of delayed Godot
colliders. Consumers using Godot physics bodies must allow their new colliders
to finish; shared network movement uses `SourcePlayerMotion` against Data.

For deferred adoption, `map_loaded` means that the new data and visual work are
installed. It does **not** promise that visual preparation has completed. No
Replica map/barrier or authority contract becomes asynchronous. The installation
callback returns its `Error` immediately. A map installer must apply every
subsequent transaction once through the World adapter; it must never apply to
the same adopted Data and then apply again through World.

`get_topdown_image_progressive` allocates and returns one shared transparent
full-resolution x/z Image on its first request, and enables frame-driven fill.
It performs no whole-map height scan. Future calls return the same Image for
that installed map. Empty columns stay transparent; completed columns have the
highest-solid original RGB and opaque alpha, including solid black.

World's normal `_process` continues its existing mesh limit of three completed
chunks or four milliseconds. It also advances requested topdown and pending
water-bottom images with a **combined** limit of 4,096 columns and a two-millisecond
target each frame. Water and topdown work alternate. Topdown dirty columns and
initial-fill columns also alternate, so repeated edits cannot starve untouched
columns. The water mesh, wave target and bottom-color texture are created after
the bottom image is complete, with the most recently selected fog, lighting,
water, waves and refraction options. Water may be temporarily absent while it
warms.

`advance_visual_preparation` permits explicit deterministic advancement without
waiting for a rendered frame. Zero or negative count/time budgets do no column
work. Its dictionary contains all preparation stats plus `processed_columns`
and `elapsed_usec`. The count cap is hard. The elapsed limit is checked between
indivisible columns; final texture upload, water/wave/reflection setup and dirty
queue compaction are indivisible and can exceed that target. It advances images;
chunk meshing still runs through `_process` or explicit `rebuild_now`.

`get_visual_preparation_stats` returns:

| Field | Meaning |
| --- | --- |
| `epoch`, `map_sequence` | Current adopted data identity |
| `topdown_requested` | Whether an Image has been requested |
| `topdown_revision` | Batch revision incremented when topdown pixels change; resets on map replacement |
| `topdown_pending_columns` | Unfilled columns plus coalesced dirty completed columns |
| `water_pending_columns` | Unfilled floor pixels plus dirty floor pixels |
| `dirty_chunks` | Pending renderer/collider queue |
| `ready` | Requested images, water and queued chunks have finished |

`is_topdown_pending` reports only requested topdown initial/dirty work. A HUD
uploads the shared image initially and whenever its revision changes, or retains
its own dirty flag while preparation is pending. It may throttle ImageTexture
uploads to 0.25 seconds while World advances every frame. Checking only the
current pending flag at upload time loses the final batch when work finishes
between two HUD polls; retain the previous pending state or compare revision.
The large map can share the small map's ImageTexture.

The existing `get_topdown_image` explicitly completes all pending topdown fill
and dirty work before returning. It preserves the synchronous API required by
offline fixtures and consumers that need immediate pixels. Calling it from a
network HUD defeats incremental preparation. It does not finish water or chunks.

## Edits and epoch cancellation

Transactions always commit atomically to Data before invalidating presentation.
A not-yet-filled column reads the newest committed cells when its cursor reaches
it. Visible edits to completed columns enqueue one coalesced rescan; buried
repaints do not enqueue it. Rescans start from the maximum affected/cached top,
preserving additions, recolors and removals that occur during initial fill.
Dirty work uses a FIFO with an index and occasional batch compaction, avoiding
an allocation of every pending dictionary key for each processed column.

Every accepted world clear, import or adoption drops old images, cursors, dirty
queues, water/waves/reflection, falling groups, meshes/collision and GI caches.
The view-chunk sentinel is reset even for identical map dimensions and center.
Retained references to an old Image stop changing after replacement. Invalid
adoption preserves the current data and all active preparation state. This is
single-thread scene work; no stale asynchronous worker can write a new epoch.

## Evidence and remaining acceptance

Run from the repository root:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/world/test_world_preparation.gd
```

On Godot 4.7.2 `ed1daf0bf`, the suite passed **53 assertions / 0 failures** with
clean stderr. It covers default synchronous compatibility, immediate pure-data
queries before colliders, exact budget progression, retained switches/fog,
edits during fill, coalescing and fairness, frame-driven caches/chunks,
synchronous completion, invalid adoption, cancellation and identical-center
synchronous/deferred resets. It decodes committed original `Title.vxl` and
compares every one of its 262,144 topdown columns and 262,144 floor-color pixels
against the packed native map, then exercises both x borders and the next-row/
last-column boundary under a two-column dirty-work cap.

The final local headless run measured native-map adoption at **468 microseconds**;
combined topdown/floor preparation took **827 batches / 1,659,970 microseconds**
total CPU work, with a **2,059-microsecond** maximum batch. Timing is reported,
not asserted as a platform guarantee. With that particular CPU and one batch
per 60 Hz frame, warming would take about 13.8 seconds; original palette columns
become available progressively during that interval. Native-map initial chunk
meshing was deliberately not flushed in this image benchmark. The existing
core World30, topdown13, water18, adapter25 and falling21 assertion suites also
passed unchanged.

These are native headless measurements. Actual exported-browser image upload,
mesh preparation, original-map adoption and live reset remain acceptance work.
No Main, preferences, GPU fixture or transport behavior was changed by this
module. Allocating image/heights buffers, detaching old streamed nodes, one
chunk rebuild, GPU uploads and optional reflection setup remain indivisible.
The preparation budget therefore reduces whole-map stalls without claiming a
hard frame-time deadline or complete browser multiplayer acceptance.
