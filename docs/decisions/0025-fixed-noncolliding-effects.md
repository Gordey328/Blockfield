# 0025 — Fixed noncolliding effects and simplified falling structures

Date: 2026-10-11. Status: accepted; implemented and checked in native/Compatibility
and exported-browser fixtures. Development publication is recorded in
[performance evidence](../simple-effects-performance.md).

The user replaces decorative particle collision/count behavior with a hard limit
of50 simultaneously active particles and requests maximum practical performance.
The user then explicitly includes collision-free casings and substantially simpler
falling structures. Earlier Title Web profiles measured particle integration plus
fragment publication at about45% of instrumented shoot script CPU; this is an
earlier workload, not a GPU or current TDM bottleneck measurement.

Preallocate50 typed particle records and fixed active/free index storage. Emission
reuses records; expiry removes an active index without shifting the remaining
array. White fragments and blood write directly into the existing MultiMesh,
without hidden Sprite3D mirrors. Animated smoke/textured water keep prewarmed
sprites. Configuration can reduce capacity to0..50 but cannot raise the hard cap.
Particles make no terrain queries, including grenade visual bias, and use
analytical motion/damping/growth once per rendered frame. Actual elapsed time
drives age, animation and fade, including hitches.

Under saturation, rank importance and distance: slow smoke0, rapid smoke1,
fragments/splashes2, explicit muzzle/glow3; multiply importance by4 and add
distance band3 below16 units,2 below32,1 below64, otherwise0. An arrival replaces
the lowest-ranked active particle, choosing the oldest on ties, only when its
rank is at least as high. This keeps fresh important close feedback visible.

Casings use16 preallocated typed state slots and bounded rifle/SMG model pools.
Retain model/ejection direction and spin, use analytical2s flight/fade once per
frame, and remove terrain collision, ground-contact events and contact sounds.
The maximum can be lowered to0..16. Other weapon/explosion audio remains.

Falling presentation samples at most64 colored cubes per detached component,
using one grouped MultiMesh and a shared unit cube mesh. Move/rotate the group
analytically for1s, then signal completion and remove it. There are no terrain
collision queries, shatter fragments or smoke in this separate world renderer.
Authoritative unsupported-component detection, ordered removals, damage, bullets,
grenade simulation, map data and multiplayer contracts retain their behavior.

This explicitly changes emission saturation, decorative terrain interaction,
trajectories, casing lifetime/audio and falling presentation from OpenSpades.
It supersedes those specific contracts in ADR0011/0015/0016; unrelated world,
camera/audio and authority contracts remain. No original parity row is accepted
by this optimization alone. Benchmarks must separate reduced visible workload
from implementation-only comparisons and name the measured CPU/GPU/frame metric.
