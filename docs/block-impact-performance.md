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

## Verification record

Native benchmark uses damage-only and geometric edits, real Title terrain and
repeatable cadence. The browser diagnostic uses actual Main and real weapon
events; normal browser build is also checked. Measurements, failures, commands
and frozen/published identities follow below. No new parity
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

Paired native runs with no rendered browser active use the same benchmark on
archived baseline then current source. `.cache/benchmarks/block-impact-paired-native-{baseline,patched}.json`
and matching logs record first-hit sync median9.256→0.026ms lab and7.098→0.032ms
Title; each phase72 targeted color updates and0 mesh/collision builds. Headless
`dummy_surface` explicitly excludes the real GPU attribute path. Largest
destructive frame slice11.867→4.820ms lab,10.032→4.637ms Title, but aggregate
per-shot presentation CPU10.875→19.074ms and8.579→16.731ms respectively. Staging
currently spreads work while increasing total CPU; exported comparison and
throughput review are required before accepting this tradeoff. Destruction
authority median221→232µs lab/182→190µs Title stays effectively unchanged.

First patched actual-Main Web (`cd8ac5e`, patched-a) retained the same72/73/73
shots and14/18/15 removals as corresponding wall baseline repeats. p9549.5/64.6/85.2ms,
max235.1/72.3/131.1ms did not establish a consistent overall frame improvement.
GPU path explicitly reports `attribute_region`;11/15/14 stale-build cancellations
show why geometry throughput needs a second pass. Retain all patched-a JSON.
Second pass moves mutable build buffers into sole-owned typed locals inside
bounded units and computes palette only on visible cells. It also reduces
hidden batched-fragment transform/color writes to final per-frame state while
retaining exact substep collision and post-update Sprite3D inspection.

Final scheduler/hot-loop native run is
`.cache/benchmarks/block-impact-scheduler-native.json` with matching
`.cache/logs/block-impact-scheduler-*`: destructive peak slices11.867→4.636ms
lab and10.032→4.049ms Title. Aggregate medians10.875→12.390ms lab and
8.579→9.879ms Title retain14–15% overhead; means retain16–19%. The initial
75–95% increase is removed, but this is still a latency/throughput tradeoff.
Publication maxima671/960µs; lab2 stale cancellations, Title0. Import,
RGB4441/0 and preparation53/0 pass on final scheduler. Batched-fragment fixture
29/0 proves3/6 physics substeps issue one final hidden position write per frame;
existing effects32588/0 pass with three explicit headless GPU skips.
Specialist leases are returned; frozen release and final Web comparison follow.

## Final Web comparison

Final exported patched-b is frozen game source `b3e29b38c573`; its Main probe
SHA256 remains exactly the baseline-c SHA above. Same browser/canvas, no native
engine running during8s scenarios. Wall repeats73/73/71 shots with14/18/15
removed cells match baseline removed-cell workloads; the third repeat fires two
fewer shots. p95 frames48.1/55.3/62.1ms versus51.7/64.3/73.8ms (7/14/16% lower),
medians32.9/29.8/34.1ms versus27.6/30.7/32.5ms do not improve consistently.
Maxima183.4/60.7/333ms show that rare stalls remain. Final dirty queues drain
to0; geometry builds28/30/21 and stale cancellations0/4/8; real GPU
`attribute_region` uploads480/384/384bytes, minimap2 uploads per run.
The final cumulative fragment counters give449880 substeps/150262 position
writes after the three runs; hidden substep setter work is reduced, with all
source integration steps retained.

Title repeat73 shots/1 removal,169 frames, p50=43.1ms,
p9583.7ms/max169.8ms versus baseline60.3/72.1ms does **not** establish an overall
Title frame improvement. It includes progressive visual preparation (29 minimap
uploads); its workload is shallow protected ground with391 batched fragments
at finish and136 draw calls. World edits alone issue2 geometry/collider builds,
one96byte color update and0 stale cancellations. Retained color index~1.45MiB
across324 active chunks. Final Web results are directional lab evidence only;
general sustained/device FPS and remaining Title/render/effect costs are open.

Artifacts: `.cache/benchmarks/block-impact-patched-b-web-{wall-1,wall-2,wall-3,title-1}.json`,
`.cache/block-impact-probe-patched-b/{identity.json,wall.jpg,title.jpg}`. Probe
console reported four Chromium pointer-lock UnknownErrors and one
WrongDocumentError; this host limitation is retained, not counted as clean logs.
All four scenarios report real positive shots/removals and `valid_impacts=true`.

Initial frozen release cold import stopped during font import with nonzero exit
and no script/error diagnostic. The log is retained as
`.cache/release-b3e29b38c573/.cache/logs/import-initial-cold-failure.log`.
Retry preserves the frozen source and seeds the previously checked import cache
before rerunning import and the complete registered build/export pipeline;
`.cache/resume_impact_release.py` records the exact retry operation.

## Frozen release checks

Frozen `b3e29b38c5733612a19ebc5529dd5c1d02cacea5` passes all88 registered
native behavioral/latency invocations, parser/import, runtime smoke,
server-launcher smoke and normal Web export on Godot
`4.7.2.stable.official.ed1daf0bf`. World30/0, damage31/0, lighting30/0,
preparation53/0, impact4441/0, minimap37/0, fragment29/0, effects32588/0
(three explicit Dummy GPU skips), mobile controls3090/0, actual mobile-look209/0,
network block-damage42/0 and shaped latency459/0. All logs and frozen game
bytes are in `.cache/release-b3e29b38c573`; export metadata reports clean source.
This client presentation change does not require a new dedicated-server binary.

Normal local exported Main was exercised through its Russian arsenal menu:
SMG selection, entering the lab, drag fallback look, block/weapon hotkeys,
1.5s held genuine SMG primary input, visibly darkened/destroyed pillar cells,
and menu re-entry. Screenshot `.cache/browser/block-impact-local-smg.jpg`;
captured logs `.cache/browser/block-impact-local-logs.json` retain the host
pointer-lock failure. Normal Title loaded through the menu to completion, rendered
terrain/minimap/characters and accepted1.2s held SMG input with visible hit debris.
Capture `.cache/browser/block-impact-local-title.jpg` and final console logs
`block-impact-local-final-logs.json` (two pointer-lock host errors).

Public Pages bundle `4827fa214b92b0180a834cad87a6e5922a8db1a6` is built/no error,
serving the exact frozen b3e source. Independent metadata plus all six public
HTML/JS/WASM/PCK/audio-worklet SHA256 values match local export;
`.cache/browser/block-impact-public-hashes.json` records sizes/digests. PCK
16214544bytes, SHA256
`d7204e76ccec9ed7d370741ca9003361ec9e96dfdccb93d76e422ed11fca99b3`.
Normal public Russian arsenal/SMG/entry, active touch-layout look drag and1.5s
held Fire button rendered damage/destruction. Capture
`.cache/browser/block-impact-public-smg.jpg`; public captured warning/error logs
are empty (`block-impact-public-logs.json`). Existing touch preference is retained.
This is desktop browser interaction with touch UI, not a physical-phone test.

## Reproduction and handoff

Use bundled Python, with the pinned executable under `.tools/godot/`:

```powershell
git archive --format=zip --output=.cache/block-impact-baseline/source.zip 662a288
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/export_block_impact_probe.py --source .cache/block-impact-baseline/source --name baseline-c
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/export_block_impact_probe.py --name patched-b --import-cache game/.godot
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/release_checkpoint.py --revision b3e29b38c5733612a19ebc5529dd5c1d02cacea5
# Recorded cold-import retry, same frozen source:
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .cache/resume_impact_release.py
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/serve.py --port 8897
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/publish_pages.py
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .cache/verify_impact_public.py
```

Diagnostic helper refuses to overwrite a previous run: use fresh names on rerun.
Extract archived baseline before export. Native benchmark is opt-in:
Godot `--headless --path <source>/game --script <repo>/tests/world/benchmark_block_impact.gd -- --output=<absolute-json>`.
Only the test suites, not this benchmark, are registered in normal builds. Serve
each diagnostic export, use its visible wall/Title buttons, save the visible JSON
result and do not run another engine/rendered tab during frame measurements.

Changed modules: world Chunk/World, minimap, effects; new world/minimap/fragment
regressions and CPU/Main browser diagnostics, build registration/export helper,
fixture contract updates and docs. Source commits cd8ac5e and b3e29b3 are pushed.
All specialist/file/engine leases returned. Current release is checked/published;
unresolved sustained device/Title FPS, aggregate destruction overhead and
indivisible GPU/physics publication remain explicit. Next performance work should
profile a warmed Title scene and real device, including effect/render/authority
costs, rather than infer global FPS from headless chunk timing.
