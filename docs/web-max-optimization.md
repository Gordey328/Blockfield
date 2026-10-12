# Web optimization branch

Date: 2026-10-12, Europe/Moscow. Branch: `codex/web-max-optimization`.
Baseline: `d5516eb2bfd22bd5d03f32ac751dce7c01086876`.
Engine: `4.7.2.stable.official.ed1daf0bf`; OpenSpades:
`dcf449c845d509bbde9d79239b32d201c1389961`. Compatibility, single-thread Web,
accepted reduced template SHA256
`a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`.

The user requires approval before lowering graphics. This branch retains all
quality options and rules; its optimization contract is [ADR0027](decisions/0027-quality-preserving-web-optimization.md).
No claim of a completed port or universal maximum performance is made.

## Audit and implementation

The root and three specialists inspected existing measurements and current
world/data, character/weapon/effects, UI, controller, shared rules/AI and network
adapters. Previous particle and impact gains are already in the baseline and are
not counted again. Offline `Main.network_mode=false` never constructs/polls the
Replica or its transports. TDM runs local MatchSimulation and five bots; removing
multiplayer would not remove that work. Network Main also had one redundant
adapter update immediately after its render poll, eliminated without changing
poll/command cadence.

Implemented changes: one final body-pose application, exact outline cache,
per-instance palette/selection cache with unchanged drawing retained, and linear
minimap icon work; one-shot live pellet pose cache; sparse linear collapse traversal
and exact empty-halo fast path; disabled flare query/publication guard. AI reads
clip size directly, and the per-tick reload/fire gates read the immutable slow-reload
flag. Public weapon dictionaries remain owned mutable copies; cadence is unchanged.

## Component results

Private native checks: collapse7961/0, empty chunks3021/0, VoxelData171/0,
impact4441/0, world30/0, preparation53/0. Two paired benchmarks require exact
ordered transaction/map equality in all six workloads. Second run means:

| Native CPU workload | Reference | Candidate | Reduction across both runs |
| --- | ---: | ---: | ---: |
| Supported collapse search | 444 µs | 216 µs | 48–51% |
| Roof removal,6400 cells | 107.370 ms | 37.515 ms | 64.8–65.1% |
| Slab removal,25600 cells | 376.280 ms | 139.584 ms | 62.3–62.9% |
| Empty chunk rebuild | 2.218 ms | 1.828 ms | 17.6–22.6% |

Occupied chunk variation changes sign between runs; no occupied gain/regression
is established. Large synchronous removals still exceed a frame budget. These are
native component timings, not Web frame measurements. Reports:
`.cache/benchmarks/world-maxopt-native{,-repeat}.json`.

Presentation fixture245/0 compares96 final visible actor poses and nested/immediate
setter behavior, corpse activation/global movement, resource refresh, palette draws
and actual minimap icon eligibility/coordinates. Character30/0, hottrack6343/0,
minimap37/0 pass. Four paired3000-frame actor samples use identical dynamic inputs:
immediate186.138–188.730ms, batched63.955–64.640ms (65.30–65.75% lower CPU).
10000 identical outline displays cost362.968ms with rebuilds versus19.730ms cached
(94.56% lower); geometry uploads10001 versus1. Final visible poses match.
Report: `.cache/benchmarks/maxopt-presentation.json`.

Retained early failures: initial private world import completed then Windows engine
exit3221225477; retry clean. First world benchmark used an untyped test array,
corrected and repeated with diagnostic-free results. Initial presentation245/50
compared hidden corpse transforms that legacy intermediate setters briefly update;
the final visible activation/movement contract is tested instead. UI284/0 initially
had11 Main runtime errors because a dynamic call received an untyped empty flare
array. Root supplies an explicitly typed `Array[Dictionary]`; clean repetition and
the new option-transition fixture remain required. Assertion totals alone do not
accept logs with engine errors.

Gameplay private import, live-shot457/0, Main8/0, clean UI284/0, PlayerRules144/0,
source goldens194/0, TDM AI4440/0 and OfflineTDM81/0 pass. Thus the typed flare
fix passes both the option-transition and actual UI fixtures. The first live-shot
test's wrong spy default type and the Main spy's missing inherited default are
retained as rejected fixture attempts. Five alternating paired eight-pellet query
benchmarks include cache creation and preparation:

| Native query workload | Uncached mean | Cached mean | Speedup |
| --- | ---: | ---: | ---: |
| Lab,5 targets | 0.952 ms | 0.445 ms | 2.14× |
| Shared,5 targets | 1.028 ms | 0.508 ms | 2.02× |
| Lab,32 targets | 5.481 ms | 2.299 ms | 2.38× |
| Shared,32 targets | 5.985 ms | 2.790 ms | 2.15× |

20000 clip/slow-reload field reads cost81.427 versus32.210ms (2.53×), identical
checksum. These are actor-query/scalar component costs, not complete shot/frame
time. Reports and checked source manifest live in
`.cache/gameplay-maxopt-check-20261012/.cache/benchmarks/live-shot-acceleration.json`
and that private project's `.cache/source-manifest.json`.

## Initial browser bottleneck

The original diagnostic baseline's three samples per scene run sequentially with
no native tests/benchmarks running. Actual1280×720 canvas, DPR1, visible IAB.
Lab:551/561/567 frames per10s, p95 intervals24.074/19.444/20ms.
Title:563/564/588 frames, p95 intervals22.222/24.982/18.056ms.
TDM:230/114/75 frames, p95 intervals69.9/140.933/144.224ms; Main inclusive
per-render CPU8.736/33.156/63.943ms while body pose CPU remains about0.35ms and
graphics update about0.18ms. Initial safe client savings alone would leave the
actual sustained-combat bottleneck unresolved. TDM creates no network client.
Root expands the pass to exact corpse physics query/damping optimization, retaining
all bodies, collisions, substeps and trajectories. Fresh identical baseline/candidate
diagnostics add corpse/AI/shared authority timing; do not mix wrapper versions.
Original reports: `.cache/benchmarks/maxopt-web-baseline-{lab,tdm,title}.json`.
Diagnostic scene-recreation logs include three Chromium `UnknownError` messages,
with no Godot script errors; normal final Web is checked separately.

The exact corpse pass is frozen at SHA256
`141f67ac034cda645ab6010709b180280120fc5779295ec9f8cb7fa8f22bccd5`.
It caches at most256 occupancy cells inside one synchronous step (base World AND
base Data only), captures dimensions/water and damping once, and reuses two typed
internal line-ray records. Public ray dictionaries remain independently owned;
custom World/Data predicates and reentrant queries retain live behavior.
The committed oracle exactly matches the archived original after removing its
global class name; original SHA256
`f265dab2369eb362ae570d3c0c6d7067715168c144615f6b760e0c7e2614bc9e`.
Independent differential1590/0, measured cohorts1599/0, original corpse9046/0,
actual TDM62/0 and lifecycle19/0 pass with diagnostic-free logs. Every measured
position/velocity/force/edge state and all six model matrices exactly match.
Sixteen-body native CPU falls49.37–50.35% for four-substep60Hz frames,
52.71–53.22% for24-substep100ms frames and53.37–53.78% for60-substep250ms frames.
Normal cohort costs about11.8→5.9ms/frame. Report:
`.cache/benchmarks/maxopt-corpse.json`; first-pass evidence is retained separately.
No bodies, collisions, source substeps, lifetimes or graphics options are removed.

First frozen full check at `c3c503552aa5b21bcde6feb8557c07aa8a70d753` passes
import and the first14 fixtures, then UI284/1 fails its remapped movement assertion.
The old UI fixture waits12 rendered frames for physical motion without a fixed
simulation/render ratio. Faster rendered callbacks do not guarantee the expected
physics duration. The same archived UI fixture at `--fixed-fps60` passes284/0
without production changes; build.py now gives this actual-input fixture the same
fixed60 mode as other input/scene fixtures. Failed and clean logs remain under
`.cache/release-c3c503552aa5/.cache/logs/test-ui{,-fixed60}.log`. A fresh frozen
full gate is still required. Two test-oracle trailing EOF blank lines were removed
after the first implementation commit; staged whitespace checks then pass.

## Reproduction and evidence

Use bundled Python
`C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
Baseline archived with `git archive --format=zip` and Python `zipfile` at
`.cache/maxopt-baseline-d5516eb`. Diagnostic command:
`python tools/export_max_optimization_probe.py --source .cache/maxopt-baseline-d5516eb --name baseline-c --import-cache game/.godot`.
Import/export pass; helper serves its `build/web` with
`python tools/serve.py --port 8093 --directory .cache/maxopt-probe-baseline-c/build/web`.
Initial diagnostic copies baseline-a/b retain the corrected wrong LabSoldier path
and unsupported multiline wrapper attempts; these were helper preparation errors,
not production parser failures. Current probe wraps identical synchronous methods
in baseline/candidate using the existing nested CPU recorder. Scenes: actual lab,
3×3 and Title; five-second warmup after terrain settlement, three ten-second
samples at identical1280×720. Diagnostic cost and browser scheduling are included;
this is shorter than proposed sustained-device acceptance, with no thermal claim.

Native suites, paired CPU reports, frozen build identity and browser results will
be recorded here before delivery. Full parity row statuses remain unchanged.
