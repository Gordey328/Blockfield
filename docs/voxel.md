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
- `set_draw_distance(meters)->float` rounds upward to 16 m chunk steps and clamps to 16..160 m. `get_draw_distance()` returns the actual value. It updates native-map streaming, mesh visibility ranges and water fog; default is 64 m. Increasing distance can synchronously queue many chunks; normal frame processing then amortizes them.
- `set_lighting_enabled(bool)` and `set_ambient_occlusion_enabled(bool)` update one shared shader without rebuilding meshes/collision. Both default to true. Lighting-off uses emissive palette colors, retaining optional AO.
- `get_topdown_image()->Image` returns a full-resolution x/z image with highest-solid RGB and opaque alpha, matching `GLFlatMapRenderer::GenerateBitmap`. It caches one Image and rescans only edited top columns. Buried edits do not require rescanning. Reset/import replaces the Image; consumers can use a shared nearest-filtered ImageTexture and throttle updates after `blocks_changed`. Empty lab columns are transparent.
- `rebuild_now()` flushes pending mesh and collision changes, useful after a reset, import or deterministic test.
- `blocks_changed(changes)` sends entries `{cell, before, after, collapsed}`. It exposes collapse removals to sound/particles, UI diagnostics, replay and future network transport.
- `map_loaded(map_name)` announces a completed reset/import. `get_stats()` reports loaded chunks, visible faces, dirty chunks and packed data memory.
- `falling_cluster_created(cluster)` announces one cosmetic grouped mesh per unsupported connected component. `falling_cluster_finished(position, block_count, reason)` announces native collision/timeout breakup, useful for sound and camera shake; `get_effect_stats()` reports active clusters and allocated fragments/smoke.
- `set_effects_observer(position)` updates observer distance for effects; `set_view_position()` also updates it on both lab and native maps. `get_effects_observer()` provides the current position at impact.
- `water_level=1.0` is the original visible water plane (source geometric z=63), while `wade_origin_level=2.0` maps the original player's GetOrigin z>62 threshold. `set_water_enabled(bool)` toggles the plane and rebuilds dry/water floor drawing. `set_water_fog(color,distance)` aligns water fog with the environment.
- `clip_box(position)` and `clip_world(position)` map native clipping rules for falling models and particles. Horizontal out-of-map coordinates are solid for ClipBox and air for ClipWorld; both clamp the bottom cell to y=1 and treat positions below the map as solid.

## Rendering and collapse

Each 16³ chunk is one `StaticBody3D`, one `MeshInstance3D`, and one `CollisionShape3D`. `ArrayMesh` emits only exposed faces, including cross-chunk culling, with four indexed vertices per face. An 18³ packed halo caches raw blocks and renderer occupancy for culling/AO. Vertex RGB preserves the VXL palette; vertex alpha stores ambient occlusion. The shared lit Compatibility shader receives directional/omni/spot lights and Godot shadows.

AO-dependent chunk invalidation includes diagonal neighbors: a corner edit dirties eight chunks, an edge four, a single border two, and an interior one. Collider invalidation uses only geometry changes and directly touched face-neighbor chunks. Repainting and AO-only neighbor updates retain existing collision objects. Collider faces greedily merge exact coplanar cells into rectangles; render faces remain separate for per-corner AO. A uniform 16×2×16 slab retains 640 rendered voxel faces but has six collision rectangles. Openings and steps retain their exact physical shape.

`_process` stops after three completed chunks or four milliseconds of rebuild work, whichever happens first. One chunk is indivisible and can exceed this time budget; synchronous reset/import/tests flush with `rebuild_now()`. `ConcavePolygonShape3D` is used only for static world geometry.

After removal, neighboring solid components are tested for six-neighbor connectivity to the bottom two layers. Floating components are removed and marked `collapsed`. Downward search is prioritized. This preserves the native support rule; the implementation uses local depth-first searches instead of OpenSpades' maintained link forest. Floating components already present in an imported map remain until affected by a removal, as in the source.

Support traversal stops as soon as a solid bottom-layer neighbor or a component already proven supported is found; it does not traverse the remaining terrain after finding ground.

## Falling presentation (W09)

`falling_cluster.gd` preserves `FallingBlock.cpp`'s cosmetic behavior: one mesh centered at the mean voxel center, gravity 4 m/s², local rotation around mapped source axis `(1,0,1)` with incremental angle `time * 1.4 * dt`, and breakup when elapsed time exceeds one second or its center enters ClipBox geometry. Authoritative blocks remain removed; fallen models never settle as new terrain.

At breakup, only component surface cells emit particles. The normal count is six white fragments and one original animated Smoke1 sprite per surface cell. Two MultiMesh batches replace individual particle nodes. Smoke runs at source 70 fps, grows from radius 1 at 0.5 units/s, has lifetime 1–1.5 seconds and ignores collisions. Fragments have source triangular random velocity scaled by 13, radius 0.35–0.45, gravity 19.2 m/s², lifetime two seconds and a one-second fade. Near impacts (observer distance <16 m and cluster <1000 blocks) use native axis selection and 0.36 velocity damping for weak bounces; other fragment collisions delete the sprite. Impacts farther than 170 m allocate no particles.

Browser budgets are explicit: at most 24 active clusters, 4096 fragments and 1024 smoke sprites per cluster. Larger surface sets are sampled uniformly. For sets below these budgets, counts follow the native six-plus-one rule. Source original rendering also emits camera vibration proportional to `block_count / 100 / (distance + 5)` clamped to one; the world emits the breakup event so presentation can apply it. These caps preserve map rules while adapting effect load.

## Water and renderer baseline (U14)

The lab contains a 16² pool at x/z=72..87, with y=1..3 excavated above immutable y=0. Native maps use the same plane. An animated Compatibility spatial shader uses map bottom colors, two analytic normal waves, Fresnel sky tint, specular highlights and the original per-channel horizontal fog curve. Submerged y=0 floor faces are hidden visually while static box-controller collision remains available.

Water is a renderer adaptation rather than an exact port of OpenSpades' FFT water tanks, screen refraction, shadow visibility or radiosity. Its analytic shader remains unshaded; terrain lights do not illuminate water. Native defaults use horizontal fog/culling distance 128 m and release at 160 m; our default streaming radius four chunks implies a 64 m water fog distance. Root owns environment/fog/lighting decisions. The water shader still needs exported-browser visual verification; headless data/behavior checks cannot establish appearance.

## Terrain lighting and AO (U14)

`voxel_ao.gd` follows `GLMapChunk::calcAOID`: for each exposed face, evaluate the eight axial/diagonal neighbors around its exterior air cell, using the native mapped tangent orientation. The resulting 8-bit ID selects a 16² tile in the original 256² `Gfx/AmbientOcclusion.png`. Four red-channel corner values are cached and emitted into mesh alpha. Native horizontal map edges wrap for AO, below-map samples are solid, above-map samples air, and water bottom sampling uses layer y=1. Physical collision remains bounded.

The native empty tile is 1.0; negative-u occlusion has corner 184/255; dense tile255 has corner112/255. Godot interpolates these values across each pair of triangles. This preserves native corner values, but approximates the atlas's full rounded detail inside each face. It is not the native continuous atlas fragment lookup.

`terrain.gdshader` uses Lambert diffuse lighting, full roughness, no direct specular, and ambient-only AO (`AO_LIGHT_AFFECT=0`). Unlike the previous baked face multipliers, palette RGB is unchanged on all orientations. Dynamic point lights and flashlight spots remain effective inside AO-darkened corners. Native OpenSpades uses fixed sun coefficients plus ambient/radiosity volumes; Godot normal-based lighting, shadow maps and environment fog are explicit renderer adaptations. Native GL radiosity, ambient-shadow volumes, SSAO and exact per-channel terrain fog are not implemented.

Actual Compatibility GPU checks on Intel UHD/OpenGL3.3 verify omni light, spot light, ambient-only AO, caster→receiver shadow and a rendered palette pixel. The backend's additive shadow path changes gamma/brightness relative to its shadows-off path and showed self-shadow bands, also with stock StandardMaterial3D. Comparing whole-scene means across those two paths is therefore misleading; the shadow test holds the shadow path active and toggles only mesh casting, including a known floor point under the pillar shadow. Browser appearance/performance remains an acceptance requirement; these checks do not claim native GL visual parity.

## VXL saving

The encoder follows `GameMap::Save`: identify six-neighbor surfaces, emit upper surface colors, implicit solid interior, lower surface colors and the following air interval. Native x/z map edges are not air neighbors for save-time surface selection, matching the source. Colors are B/G/R bytes and native health 100. Every column must end in a solid immutable floor. Valid zero-upper-color spans (`top_end = top_start - 1`) occur when a lateral surface patch splits otherwise-solid interior; these are supported by both encoding and decoding.

VXL stores exposed surface colors rather than every underground voxel color. Repainted surfaces and newly exposed recolored interior cells survive saving; colors wholly buried in solid interior revert to the decoder's default earth color. This is a format limitation shared with the native encoder.

## Verification and remaining costs

Run `godot --headless --path game --script ../tests/world/test_world.gd`. Tests cover solid black, cross-chunk faces, DDA entry/normal/distance, partial and final bridge support cuts, protected explosion floor, a full-size VXL fixture, layered spans, truncation, original-map import when the pinned source is present.

Run `godot --headless --path game --script ../tests/world/test_vxl_save.gd` for decode/edit/encode/decode, multiple non-contiguous spans, zero-upper-color spans, solid black, newly exposed interior colors, malformed data and failed-import preservation, lab padding and filesystem writes. Both suites use the committed `game/assets/openspades/maps/Title.vxl`, so CI does not require `.cache/openspades`. The original map roundtrip compares all 16,777,216 cells for occupancy and every source-defined exposed surface for color.

Run `godot --headless --path game --script ../tests/world/test_falling_clusters.gd` for authoritative removal → grouped fall → COM collision → native debris → cleanup, pivot/rotation/gravity, timeout, far culling, explicit budgets, clipping and lab water metadata/settings. On 2026-10-10 this suite passed 21 assertions on Godot 4.7.2.

Run `godot --headless --path game --script ../tests/world/test_lighting.gd` for native atlas golden corners, real mesh AO orientation, palette preservation, indexed quads, diagonal chunk invalidation, settings without reallocation, unchanged collider retention, merged collision rays/openings, draw distance/fog and native halo boundaries. It passed 26 assertions. Run `test_topdown.gd` for image/cache/reset/edit semantics and every original Title column's highest source color; it passed 13 assertions.

Run `godot --path game --rendering-method gl_compatibility --script ../tests/world/render_lighting.gd -- --output=<absolute evidence directory>` with graphics enabled. This requires a real GPU and deliberately rejects headless rendering. It passed seven assertions; screenshots and metrics are saved under the output directory. On Intel UHD: mean brightness dark0.01145, omni0.05472, spot0.04041; direct-light AO toggle difference0; ambient AO darkened7,827 pixels; caster shadow darkened18,794 pixels. The fullbright sampled pixel was exactly (128,96,64)/255. These are local renderer checks, not browser timings.

Pinned `Title.vxl` is 2,106,956 bytes, SHA-256 `48fe6c8e9b8287c1aea12e67742362cd7001d72c7bc027b993f7a22982beed62`. An independent occupancy reconstruction using the native decoder's initially-solid columns reports 3,778,939 solid voxels; the Godot check uses this golden count to catch air-span mistakes.

On 2026-10-10, Godot 4.7.2 `ed1daf0bf` headless passed 30 core assertions and 19 save assertions, including a real `CharacterBody3D` supported by generated chunk collision and falling after block removal, native grenade cube damage, and complete original-map geometry/surface-color save verification. `tests/world/benchmark_world.gd` measured lab generation/meshing at 642 ms (72 chunks, 25,044 visible faces, 1,179,648 data bytes), and original `Title.vxl` import plus initial streamed meshing at 2,906 ms (324 chunks, 48,627 visible faces, 67,108,864 data bytes). These are local CPU baselines, not browser timings.

After water presentation and separate hidden-floor collision were added, the same headless benchmark measured lab generation at 781 ms (24,724 rendered faces), lab native-VXL encoding at 2,869 ms (2,112,288 bytes), original-map import/meshing at 3,878 ms (39,907 rendered faces) and original native-VXL encoding at 4,622 ms (2,106,956 bytes). Surface hiding lowers rendered face count without removing water-floor collision. Workload timings are local development baselines; save operations currently block the main thread.

After packed halos, indexed AO quads, separate collider invalidation and merged collision, one baseline measured lab365 ms and Title1,855 ms with the same rendered face counts/data sizes. Dense single-chunk repaint averaged7.32 ms (maximum11.46 ms); an eight-chunk corner update took31.12 ms when synchronously flushed. A subsequent run measured a destructive lab edit, including support checking and rebuild, at8.57 ms; corner rebuild42.32 ms. Native top-down image creation took632 ms;100 cached reads took38 µs. Expanding streamed distance64→128 m took3,358 ms and raised324→1,156 chunks /39,907→163,931 faces. These local timings vary with concurrent development work and support keeping64 m as the initial browser default pending exported-browser measurements.

Full VXL import, save, first top-down image and initial chunk meshing are synchronous. Streaming rebuilds are deferred afterwards. Large, tall disconnected structures can cause a long connectivity pass. Hidden-face culling and greedy collider faces are implemented; greedy render meshing, worker-thread generation and maintained connectivity links remain future performance work. The raw storage alone is 64 MiB for a native map; browser heap limits and realistic map/frame-time measurements must be included in release verification.

Reference semantics come from pinned OpenSpades `Sources/Client/GameMap.cpp`, `GameMapWrapper.cpp`, `World.cpp`, `FallingBlock.cpp`, `Sources/Draw/GLMapChunk.cpp:87..209`, `GLMapRenderer.cpp:95..130`, `GLFlatMapRenderer.cpp:54..73` and `Resources/Shaders/BasicBlock.fs` / `Shadow/MapRadiosity.fs`. Godot APIs: [ArrayMesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html), [ConcavePolygonShape3D](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html), [spatial shader AO/light behavior](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).
