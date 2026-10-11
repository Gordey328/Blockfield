# ADR0015 — Bound terrain presentation work during weapon impacts

Date: 2026-10-11. Accepted implementation direction; verification recorded in
[impact evidence](../block-impact-performance.md).

## Problem

Surviving weapon hits darken one cell but currently regenerate its whole chunk
mesh and AO. Destruction rebuilds one or several complete chunks before the
frame budget can be checked. SMG cadence makes these indivisible costs visible.
Buried changes also trigger unchanged minimap texture uploads.

## Decision

Keep authority, block health, collapse, intrinsic RGB and immediate voxel queries
unchanged. Update damage/repaint colors through existing ArrayMesh attribute
regions, retaining topology, AO UV/alpha, mesh identity and collision shape.
Retain a bounded per-chunk cell-to-face index and AO metadata, rather than a copy
of all mesh buffers or live map storage.

Prepare geometric changes in bounded units on the main thread, compatible with
single-threaded Web. Keep the preceding mesh/collider until an entire current
job can be published together. Cancel affected stale jobs on geometry/resource
invalidation, unload and map replacement. Flush the same path synchronously for
`rebuild_now`; gameplay queries continue to read authoritative voxel data.

Minimap polling continues during progressive preparation. Upload only when its
image identity, dimensions or completed pixel revision changes. Same-size map
replacement must upload even if revision numbers match.

For batched impact fragments, preserve all physics substeps and source lifetime
calculations in per-frame state, then mirror the final hidden Sprite3D state
once before uploading the batch. Visible smoke/water sprites retain their
existing path. Post-update inspection and transformed-manager billboards remain
equivalent; the pools and rendering architecture of ADR0011 are retained.

## Consequences

Terrain preparation can yield between frames; GPU mesh publication and physics
shape creation remain indivisible engine calls and must be measured separately.
Rendering/collision meshes can lag data while a job is pending, as with the
previous deferred queue. These changes do not certify full-port parity or
physical-phone performance. Counters and opt-in benchmarks retain those limits.

## References

- [Godot4.7 ArrayMesh](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html)
- [RenderingServer buffer offset/stride APIs](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html)
- [Permanent block damage](0010-persistent-block-damage.md)
