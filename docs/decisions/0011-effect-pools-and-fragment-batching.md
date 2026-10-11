# 0011 — Reuse transient effects and batch fragments

Date: 2026-10-11. Status: implemented; validation in [effects performance](../effects-performance.md).

Sustained nearby SMG impacts emitted25 particles per hit, plus muzzle smoke,
lights and casings. Concurrent object caps prevented unlimited live counts, but
each emission allocated nodes/models and each default fragment submitted a draw.
An actual exported WebGL scenario reached512 particles and571 draw calls.

Keep the presentation manager's source emission/collision contracts and introduce
bounded, prewarmed reuse pools. Separate rifle/SMG idle casing pools preserve model
identity. Clear returns/reset nodes; resource-pack reload detaches old nodes and
prewarms fresh resources. Cache all original smoke frames during loading.

Use one reusable fixed-capacity MultiMesh for White.png fragments and blood.
Retain pooled hidden Sprite3D simulation state to avoid changing collision and
emitter contracts. Sync camera-facing poses/colors once after substeps. Animated
smoke/water stay pooled Sprite3D. Alpha fragments sort as one batch; this rendering
adaptation may alter blending among overlapping faded fragments.

Separate actual elapsed lifecycle time from the bounded particle/casing collision
step. Slow frames must expire effects and vibration at their defined real duration
without increasing physics catch-up work. Keep original near-distance grenade
saturation and perform the original170-unit cull before adding vibration.

This changes presentation allocation, rendering and clocks. Weapon authority,
ammo, spread, damage, terrain data and multiplayer protocol remain separate.
Pooling/batching evidence does not establish target-device FPS or whole-port acceptance.
