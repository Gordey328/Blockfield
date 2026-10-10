# Voxel world

The offline Godot world lives in `game/world/`. `VoxelWorld` is the authoritative voxel state for iteration 1. Iteration 2 should feed confirmed server changes through the same boundary. The data model has no node per cube.

## Coordinates and colors

Godot coordinates are `(x east, y up, z south)`, with one unit per block. Blocks occupy `[cell, cell + (1,1,1)]`. The lab is 96 × 32 × 96, with ground layers y=0..3 and walkable top y=4. `get_spawn_position()` returns the current safe map spawn. Always use it rather than a hard-coded height.

`get_block(Vector3i)` returns 0 for air or out-of-bounds. Solid values are `0x01RRGGBB`, so opaque black remains solid. Use `VoxelWorld.pack_color(Color)` and `block_color(int)` at interface boundaries. This differs from OpenSpades' internal `0xHHBBGGRR` which combines color and per-block damage.

Original VXL `(x, y, z)` maps to Godot `(x, 63-z, y)`. The original 512 × 512 × 64 map fits in a 64 MiB `PackedInt32Array`; the vertical column is contiguous. `VXLReader.decode` checks spans, upper/lower colors, hidden solid interiors, truncated inputs and z=62→63 floor duplication. VXL does not store colors inside solid spans; newly exposed interior uses a fixed earth color rather than native randomized interior colors.

## Public boundary

- `generate_lab()` resets the local test arena.
- `get_block(cell)`, `set_block(cell, color)` query or change one cell. Layer y=0 cannot be changed through gameplay.
- `remove_blocks(cells, protect_lower_layer=false)` performs a batch removal and one connectivity pass. Set `protect_lower_layer=true` for grenade/three-block spade actions, matching OpenSpades' protected two bottom layers.
- `cast_voxel(origin, direction, max_dist)` is grid DDA independent of delayed collision rebuilding. It returns `{hit, cell, normal, position}`; `cell + normal` is the placement cell when normal is nonzero.
- `explode(position, radius=1.6)` removes the native axis-aligned 3³ neighborhood and collapses unsupported structures. Radius belongs to player damage/visuals and does not change terrain damage. `explode_sphere(position, radius)` is a separate experimental lab utility.
- `load_vxl(path)` and `load_vxl_bytes(bytes, title)` return a Godot `Error`. A failed decode preserves the current world.
- `encode_vxl()` returns native VXL bytes for browser download. `save_vxl(path)` saves those bytes and returns an `Error`; invalid geometry/dimensions return `ERR_INVALID_DATA` before writing. A native map keeps its dimensions; smaller labs are padded to 512 × 64 × 512 at the original x/z origin and y-up heights, with two safe earth layers outside the lab and air above. Areas beyond native dimensions are rejected.
- `set_view_position(player_position)` must be called as the player moves on VXL maps. It streams render meshes and colliders within `render_radius` horizontal chunks; the lab remains fully loaded.
- `rebuild_now()` flushes pending mesh and collision changes, useful after a reset, import or deterministic test.
- `blocks_changed(changes)` sends entries `{cell, before, after, collapsed}`. It exposes collapse removals to sound/particles, UI diagnostics, replay and future network transport.
- `map_loaded(map_name)` announces a completed reset/import. `get_stats()` reports loaded chunks, visible faces, dirty chunks and packed data memory.
- `falling_cluster_created(cluster)` announces one cosmetic grouped mesh per unsupported connected component. `falling_cluster_finished(position, block_count, reason)` announces native collision/timeout breakup, useful for sound and camera shake; `get_effect_stats()` reports active clusters and allocated fragments/smoke.
- `set_effects_observer(position)` updates observer distance for effects; `set_view_position()` also updates it on both lab and native maps. `get_effects_observer()` provides the current position at impact.
- `water_level=1.0` is the original visible water plane (source geometric z=63), while `wade_origin_level=2.0` maps the original player's GetOrigin z>62 threshold. `set_water_enabled(bool)` toggles the plane and rebuilds dry/water floor drawing. `set_water_fog(color,distance)` aligns water fog with the environment.
- `clip_box(position)` and `clip_world(position)` map native clipping rules for falling models and particles. Horizontal out-of-map coordinates are solid for ClipBox and air for ClipWorld; both clamp the bottom cell to y=1 and treat positions below the map as solid.

## Rendering and collapse

Each 16³ chunk is one `StaticBody3D`, one `MeshInstance3D`, and one `CollisionShape3D`. `ArrayMesh` emits only exposed faces, including cross-chunk culling; vertex colors preserve the voxel style. A shared unshaded material adds directional face shading. Only changed chunks and their border neighbors are rebuilt. `_process` amortizes rebuilds over `rebuild_budget` chunks per frame. `ConcavePolygonShape3D` is used only for static world geometry.

After removal, neighboring solid components are tested for six-neighbor connectivity to the bottom two layers. Floating components are removed and marked `collapsed`. Downward search is prioritized. This preserves the native support rule; the implementation uses local depth-first searches instead of OpenSpades' maintained link forest. Floating components already present in an imported map remain until affected by a removal, as in the source.

Support traversal stops as soon as a solid bottom-layer neighbor or a component already proven supported is found; it does not traverse the remaining terrain after finding ground.

## Falling presentation (W09)

`falling_cluster.gd` preserves `FallingBlock.cpp`'s cosmetic behavior: one mesh centered at the mean voxel center, gravity 4 m/s², local rotation around mapped source axis `(1,0,1)` with incremental angle `time * 1.4 * dt`, and breakup when elapsed time exceeds one second or its center enters ClipBox geometry. Authoritative blocks remain removed; fallen models never settle as new terrain.

At breakup, only component surface cells emit particles. The normal count is six white fragments and one original animated Smoke1 sprite per surface cell. Two MultiMesh batches replace individual particle nodes. Smoke runs at source 70 fps, grows from radius 1 at 0.5 units/s, has lifetime 1–1.5 seconds and ignores collisions. Fragments have source triangular random velocity scaled by 13, radius 0.35–0.45, gravity 19.2 m/s², lifetime two seconds and a one-second fade. Near impacts (observer distance <16 m and cluster <1000 blocks) use native axis selection and 0.36 velocity damping for weak bounces; other fragment collisions delete the sprite. Impacts farther than 170 m allocate no particles.

Browser budgets are explicit: at most 24 active clusters, 4096 fragments and 1024 smoke sprites per cluster. Larger surface sets are sampled uniformly. For sets below these budgets, counts follow the native six-plus-one rule. Source original rendering also emits camera vibration proportional to `block_count / 100 / (distance + 5)` clamped to one; the world emits the breakup event so presentation can apply it. These caps preserve map rules while adapting effect load.

## Water and renderer baseline (U14)

The lab contains a 16² pool at x/z=72..87, with y=1..3 excavated above immutable y=0. Native maps use the same plane. An animated Compatibility spatial shader uses map bottom colors, two analytic normal waves, Fresnel sky tint, specular highlights and the original per-channel horizontal fog curve. Submerged y=0 floor faces are hidden visually while static box-controller collision remains available.

This is a renderer adaptation, not an exact port of OpenSpades' FFT water tanks, screen refraction, shadow visibility, radiosity or 8-neighbor AO lookup texture. Native defaults use horizontal fog/culling distance 128 m and release at 160 m; our default streaming radius four chunks implies a 64 m water fog distance. Root owns environment/fog/lighting decisions. The shader needs exported-browser visual verification; headless data/behavior checks cannot establish shader appearance.

## VXL saving

The encoder follows `GameMap::Save`: identify six-neighbor surfaces, emit upper surface colors, implicit solid interior, lower surface colors and the following air interval. Native x/z map edges are not air neighbors for save-time surface selection, matching the source. Colors are B/G/R bytes and native health 100. Every column must end in a solid immutable floor. Valid zero-upper-color spans (`top_end = top_start - 1`) occur when a lateral surface patch splits otherwise-solid interior; these are supported by both encoding and decoding.

VXL stores exposed surface colors rather than every underground voxel color. Repainted surfaces and newly exposed recolored interior cells survive saving; colors wholly buried in solid interior revert to the decoder's default earth color. This is a format limitation shared with the native encoder.

## Verification and remaining costs

Run `godot --headless --path game --script ../tests/world/test_world.gd`. Tests cover solid black, cross-chunk faces, DDA entry/normal/distance, partial and final bridge support cuts, protected explosion floor, a full-size VXL fixture, layered spans, truncation, original-map import when the pinned source is present.

Run `godot --headless --path game --script ../tests/world/test_vxl_save.gd` for decode/edit/encode/decode, multiple non-contiguous spans, zero-upper-color spans, solid black, newly exposed interior colors, malformed data and failed-import preservation, lab padding and filesystem writes. Both suites use the committed `game/assets/openspades/maps/Title.vxl`, so CI does not require `.cache/openspades`. The original map roundtrip compares all 16,777,216 cells for occupancy and every source-defined exposed surface for color.

Run `godot --headless --path game --script ../tests/world/test_falling_clusters.gd` for authoritative removal → grouped fall → COM collision → native debris → cleanup, pivot/rotation/gravity, timeout, far culling, explicit budgets, clipping and lab water metadata/settings. On 2026-10-10 this suite passed 21 assertions on Godot 4.7.2.

Pinned `Title.vxl` is 2,106,956 bytes, SHA-256 `48fe6c8e9b8287c1aea12e67742362cd7001d72c7bc027b993f7a22982beed62`. An independent occupancy reconstruction using the native decoder's initially-solid columns reports 3,778,939 solid voxels; the Godot check uses this golden count to catch air-span mistakes.

On 2026-10-10, Godot 4.7.2 `ed1daf0bf` headless passed 30 core assertions and 19 save assertions, including a real `CharacterBody3D` supported by generated chunk collision and falling after block removal, native grenade cube damage, and complete original-map geometry/surface-color save verification. `tests/world/benchmark_world.gd` measured lab generation/meshing at 642 ms (72 chunks, 25,044 visible faces, 1,179,648 data bytes), and original `Title.vxl` import plus initial streamed meshing at 2,906 ms (324 chunks, 48,627 visible faces, 67,108,864 data bytes). These are local CPU baselines, not browser timings.

After water presentation and separate hidden-floor collision were added, the same headless benchmark measured lab generation at 781 ms (24,724 rendered faces), lab native-VXL encoding at 2,869 ms (2,112,288 bytes), original-map import/meshing at 3,878 ms (39,907 rendered faces) and original native-VXL encoding at 4,622 ms (2,106,956 bytes). Surface hiding lowers rendered face count without removing water-floor collision. Workload timings are local development baselines; save operations currently block the main thread.

Full VXL import, save and initial chunk meshing are synchronous. Streaming rebuilds are deferred afterwards. Large, tall disconnected structures can cause a long connectivity pass. Hidden-face culling is implemented; greedy meshing, worker-thread generation and maintained connectivity links remain future performance work. The raw storage alone is 64 MiB for a native map; browser heap limits and realistic map/frame-time measurements must be included in release verification.

Reference semantics come from pinned OpenSpades `Sources/Client/GameMap.cpp`, `GameMapWrapper.cpp`, and `World.cpp`. Godot mesh APIs: [ArrayMesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html), [ConcavePolygonShape3D](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html).
