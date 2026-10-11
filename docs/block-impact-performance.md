# Weapon/block impact optimization — 2026-10-11

The user reports terrain-hit stalls, particularly with SMG. Baseline source
`662a288`, upstream `dcf449c845d509bbde9d79239b32d201c1389961`, pinned Godot
`4.7.2.stable.official.ed1daf0bf`, Compatibility and single-threaded Web.
Baseline source is preserved in `.cache/block-impact-baseline/source.zip`.

Implementation follows [ADR0015](decisions/0015-budgeted-block-impact-rendering.md).
Authority/collapse/network rules remain unchanged. Existing Steam AoS research
files and its status insertion belong to their original task and are preserved.

## Ownership and handoff

- `impact_world`: `game/world/voxel_chunk.gd`, `game/world/voxel_world.gd`.
- `impact_rules`: `game/ui/lab_map.gd`, new minimap upload regression fixture.
- `impact_tests`: new world impact correctness/benchmark and actual-Main Web probe.
- Coordinator: existing fixture integration, tool registration/export helper,
  architecture/parity/status/decision/evidence, serial engine and release checks.

## Verification in progress

Native benchmark uses damage-only and geometric edits, real Title terrain and
repeatable cadence. The browser diagnostic uses actual Main and real weapon
events; normal browser build is also required. Measurements, failures, commands
and frozen/published identities will be appended after completion. No new parity
rows are promoted merely by this optimization.

Initial affected checks: import, existing damage31/0, lighting30/0, preparation53/0,
new minimap37/0 and impact4441/0. The latter includes all256 RGB values, healthy,
damaged and recovered, comparing exact raw RGBA8/AO/UV against a full rebuild.
Existing world/lighting fixtures now assert retained topology and one-chunk color
invalidation; the old world two-neighbor repaint expectation failed before repair.

Baseline native `.cache/benchmarks/block-impact-baseline-native-v2.json` records
first-hit synchronous presentation median8.65ms (lab),6.25ms (densest streamed
Title chunk14/0/15); no-op already-dark hits ~1µs. First native fixture used an
untyped removal array; failed log retained then typed-array repair passed.

Actual-Main browser baseline uses probe SHA256
`217adbcea68bfb754994ce58b022ce3d16d4ea929e0ff5296fcf9bdd15229478` with
fixed initial seed, held source SMG input, compensated camera recoil, original
effects/audio and unlimited local ammo. It preserves source weapon cadence and
damage; fixture maintains input focus/position solely for measurement. Canvas
922x714 physical /614x476 CSS, WebKit WebGL in Codex IAB, DPR1.5. Wall runs8s:
72–73 shots,14–18 removed blocks, p95 frames51.7/64.3/73.8ms; maxima239.3/78.8/87.2ms.
Title8s:73 shots,1 removed block, p9560.3ms,max72.1ms,414 batched fragments at finish.
Its aim near shallow protected terrain does not model repeated deep excavation.
These short desktop diagnostic repeats are not sustained physical-device FPS
acceptance. Frame-dependent effects random draws produce different removal counts
despite an equal initial seed; comparisons must include workload and these limits.

Artifacts: `.cache/benchmarks/block-impact-baseline-web-{wall-1,wall-2,wall-3,title-1}.json`,
`.cache/block-impact-baseline/{wall,title}.jpg`. Baseline-b produced zero shots due
to DOM input focus, so its result is excluded and retained in
`.cache/block-impact-baseline/invalid-browser-b.json`. Baseline-c uses repaired
held-input/focus fixture; its script matches the current SHA exactly. The local
HTTP directory alias initially named baseline-b was replaced by c for serving;
the original b source/probe and invalid result remain available for reproduction.
