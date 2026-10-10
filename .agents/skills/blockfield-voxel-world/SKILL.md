---
name: blockfield-voxel-world
description: Implement and verify Blockfield colored voxel maps, VXL loading, chunk meshes, block edits, collision and collapse in Godot. Use for changes to game/world.
---

Consult docs/architecture.md and docs/voxel.md for the current interfaces. Compare algorithms with upstream GameMap, GameMapWrapper and World in .cache/openspades/Sources/Client.

Use packed cell data and chunk meshes, not one scene node per cell. Preserve solid black (air must have a separate encoding). Convert original Z-down axes to Godot Y-up consistently for maps, rays, players and models.

Verify VXL decoding with original fixtures and malformed/truncated input; verify boundary face visibility, DDA ray hits, batched edits, collision updates and protected ground. Only affected chunks and neighbors on changed borders should rebuild. Unsupported components require original collapse behavior; do not call simple block removal full parity.

Measure representative real-map loading and destructive edits in the exported browser build. Headless checks establish data correctness, not rendering performance.
