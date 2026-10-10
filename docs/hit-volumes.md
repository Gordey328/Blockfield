# Prepared source player hit volumes

`LabHitVolumes` keeps the five hit volumes from pinned OpenSpades v0.1.3 `Sources/Client/Player.cpp:1316–1385`: head, torso, left leg, right leg, broad arms. Native Z-down coordinates map to Godot Y-up. Pitch rotates the head around the original offset pivot; the other volumes retain the original crouching and standing transforms.

## Query contract

```gdscript
var pose: LabHitVolumes.PreparedPose = LabHitVolumes.prepare_pose(feet, yaw, crouching, pitch)
var result: Dictionary = LabHitVolumes.cast_prepared(origin, direction, pose, max_distance)
```

`prepare_pose(feet: Vector3, yaw: float, crouch: bool, pitch: float = 0.0)` computes five world inverse transforms, local AABBs, ordered part names, and the union of their transformed world AABBs. The returned `PreparedPose` owns read-only typed arrays. Its public inspection getters return value copies: `get_inverse_transforms()`, `get_boxes()`, `get_parts()`, `get_world_bounds()`, and `get_volume_count()`. This is an immutable API contract for trusted simulation code; GDScript underscore members are not a security boundary for arbitrary scripts.

`cast_prepared(origin: Vector3, direction: Vector3, pose: PreparedPose, max_distance: float = 500.0)` returns the unchanged dictionary `{hit: bool, part: String, distance: float, position: Vector3}`. `cast_ray(origin, direction, feet, yaw, crouch, pitch = 0.0, max_distance = 500.0)` remains the compatibility entry point. It preserves the original short circuit for direction length squared below `1e-6`, before constructing any pose, then delegates to a prepared query. Callers with several pellets should prepare each validated actor pose once and reuse it for that shot. A prepared pose must represent those exact feet/yaw/crouch/pitch values. There is no global pose cache or implicit reuse between actors, frames, historical ticks, or spawn generations.

The narrow phase preserves the original matrix multiplication and inversion order, the local parallel-axis epsilon `1e-6`, inclusive box boundaries, and strict horizontal-distance comparison. Equal horizontal distances retain the original head/torso/left-leg/right-leg/arms order, including vertical rays whose distances all tie horizontally. A miss retains `origin + direction * max_distance` with the original, potentially unnormalized direction. The helper does not add the caller's firearm horizontal-range cutoff or change it to a Euclidean-distance cutoff.

## Conservative broad rejection

Only a finite normalized ray, finite origin, finite nonnegative maximum distance, and finite prepared bounds use broad rejection. Other inputs continue through the original narrow phase. The world-axis slab calculation treats only exactly zero components as parallel: applying the source local-axis epsilon to a rotated world ray would change boundary hits.

The stored union is unpadded. The query grows it by `2 * 1e-6 * max_distance + 8e-6 * scale`, where `scale` is the largest of 1, maximum distance, and absolute origin/bounds coordinates. The first term covers the drift of up to three local components ignored by the source parallel-axis test; the second allows float32 transform/inverse/point roundoff. This intentionally permits extra candidates near boundaries and at large coordinates. It never replaces the original five volume tests for surviving candidates. A distant near-parallel arm hit can lie outside the tight geometric union and must survive this guard.

## Differential verification and measurement

[test_hit_volume_acceleration.gd](../tests/gameplay/test_hit_volume_acceleration.gd) contains a frozen independent copy of the pre-optimization helper from commit `c4f808990b84d068242dde47b8fe4f2951e322fe`; it does not use the production volume or narrow-phase functions to calculate expected results. Source-derived fixed poses, part/gap rays, head pivots, and vertical tie goldens also check the geometry independently.

The corpus compares exact hit/miss, part, distance, and point values across standing/crouching poses, yaw wraps, head pitch, box corners/interiors, exact maximum-distance boundaries, small nonzero components, float32 large coordinates, seeded random rays, and legacy invalid-input fallbacks. Inspection-copy mutation and interleaved different actor poses test safe reuse. Non-finite directions intentionally trigger Godot's normalization warning in both implementations; only those expected diagnostics are suppressed temporarily, while assertions and exit status remain active.

Run the pure tests from the repository root:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/gameplay/test_hit_volume_acceleration.gd
```

Add `-- --benchmark` for a five-sample CPU measurement. Each sample contains 96 salvos of 32 actor poses and eight pellet rays, with pose preparation included for every salvo, alternating measurement order, and exact hit/distance checksum comparisons. The output is local `.cache/benchmarks/hit-volume-acceleration.json`. Timings are reported rather than enforced as a machine-dependent test threshold. The benchmark measures this query helper; server frame time, history queries, collision with map data, fanout, transport, and browser performance require separate measurements. It makes no 32-player/60-Hz acceptance claim.

Measured on Godot 4.7.2 official Windows headless, Intel Core i5-10400H, without concurrent engine workloads: **65,925 differential rays**, **69,284 assertions / 0 failures** including benchmark checks, clean engine log. The sample has 96.875% misses. Median time per 32-pose/eight-pellet salvo decreased from **3.294 ms** for the frozen original to **1.406 ms** with preparation included, **2.342×** faster. Five complete 96-salvo samples were 308.947–317.819 ms original and 133.343–136.644 ms prepared. This is a measured CPU helper improvement, not multiplayer capacity verification. Production helper SHA-256 at this measurement: `b73a05a5f5b9e4138eaebcc7333e27e4455eaad23ef3a352ba98c1a1ab1c0828`.
