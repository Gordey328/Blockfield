# Web optimization branch

Date: 2026-10-12, Europe/Moscow. Branch: `codex/web-max-optimization`.
Baseline: `d5516eb2bfd22bd5d03f32ac751dce7c01086876`.
Engine: `4.7.2.stable.official.ed1daf0bf`; OpenSpades:
`dcf449c845d509bbde9d79239b32d201c1389961`. Compatibility, single-thread Web,
accepted reduced template SHA256
`a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`.

The user requires approval before lowering graphics. The first pass retains all
quality options and rules under [ADR0027](decisions/0027-quality-preserving-web-optimization.md).
After reviewing measured sustained-combat costs, the user explicitly approves
removing corpse physics entirely; [ADR0028](decisions/0028-static-death-models.md)
records the resulting static-death presentation contract. No other graphical
quality reduction is approved.
No claim of a completed port or universal maximum performance is made.

The user specifies iPhone12 mini with Chrome as the weakest target. The working
acceptance aim is sustained30fps; desktop viewport tests do not establish A14,
iOS/WebKit, device-pixel-ratio, memory or thermal performance. A physical-phone
run remains required before claiming this target is achieved.

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

Frozen `0a129eca80ff3b2dbadae947dc43cec141311d4d` passes all102 runs
(101 Godot fixtures plus latency458/0), parser/import, client/server smokes and
normal reduced-template Web export. Logs under
`.cache/release-0a129eca80ff/.cache/logs` contain no rejected engine diagnostics.
Independent final review subsequently catches two custom-extension compatibility
edges: a Corpse subclass's `_ray` override could be bypassed, and a callback that
changes `corpse.world` could keep reading the captured old world. The final guard
requires a base Corpse script as well as base World/Data; disabled fast paths use
the live adapter. Final corpse SHA256
`303ab67651e1a01e9d125c6e6642174307006871c468e46952c7b8079161452e`
supersedes141. New independent1635/0, original9046/0, Main8/0 and actual TDM62/0
pass, including explicit normal base-cache activation and both custom cases.
The earlier paired component report remains tied to141; final browser timing
uses303. Only corpse runtime changes after the full102 gate; final affected
checks/smokes/export are repeated on a fresh archive before delivery.

Final frozen `86016890b94d18b83105256dc1714143b39e11e8` passes parser/import,
corpse-optimization1635/0, original-corpse9046/0, Main8/0, presentation245/0,
actual-TDM62/0, network-scene27/0 and offline-lifecycle19/0. Both client/server
smokes and the normal reduced-template Web export pass. All final affected logs
under `.cache/release-86016890b94d/.cache/logs` are diagnostic-free. The only runtime
change since the full102 gate is the reviewed Corpse extension compatibility fix.
The clean normal bundle reports source8601689 and `source_dirty=false`.

Expanded browser diagnostics keep authority paused until terrain is ready,
then warm for5s and measure three10s windows. TDM diagnostic kill limit10000 avoids
ending the comparison early; production limits are unchanged. Methods add Corpse
step, bot commands and Match step costs plus actual body counts. Baseline and
candidate use the identical final fixture/wrappers; their scene CPU is normalized
per rendered callback or authority step, and frame intervals remain separate.

The identical expanded quality-preserving TDM comparison has5/7/9 bodies at the
ends of corresponding windows. Baseline/candidate mean rendered rates are
25.93/26.21,15.79/16.98 and7.24/16.06fps. Main per-render CPU is
5.382/3.657,19.522/12.342 and43.427/16.117ms. The last window's corpse step
falls42.917→15.673ms per rendered callback. p95 frame intervals remain
55.122/61.657,83.333/102.157 and141.667/89.457ms. These are one sequential
desktop-browser comparison with evolving authority timelines, diagnostic overhead
and browser scheduling; it demonstrates the remaining bottleneck, not phone30fps.
Both reports contain identical graphics and `network_client_created=false`.
Baseline lab p95 is19.233/21.4/20.370ms; candidate lab is20/25/25.926ms;
no overall lab FPS improvement is established from this noisy run.

Retained rejected diagnostics: the first candidate TDM tab reverted to its default
615×476/DPR1.5 viewport. That mixed-size report is saved separately, the viewport
is reapplied and verified1280×720/DPR1 before the accepted TDM/lab run. Candidate
Title was read before completion and returned the previous lab report; it is
retained as rejected-title-capture and is not used as Title evidence. The final
static-body source receives fresh scenario-checked profiles before publication.
Four Chromium UnknownError logs during diagnostic scene creation are retained;
the fresh ordinary860 Web tab has no warning/error logs and is checked separately.

Ordinary860 Web at812×375 starts through the tap-only mobile menu with controls
forced On, fires through the screen button and selects spade/block with the
corresponding view model/HUD. Snapshot `.cache/previews/maxopt-mobile-quality-860.png`.
This is mouse interaction with the mobile layout, not a physical multitouch test.
Frozen mobile suites remain Controls10128/0, Look225/0, Aim79/0, HUD680/0 and
UI284/0. The target phone still needs physical testing. HUD safe-area placement,
touch text entry and thermal/memory limits are open; no universal device claim.

## Approved static bodies and additional CPU work

The user approves removing corpse physics rather than the proposed4-body/2s
profile, and explicitly asks to investigate other costs. Main now chooses the
original prone Player/Dead model with captured yaw/team tint, one-time bounded
floor placement and existing16 hard/6 invisible-soft retention. Bodies remain
fixed after impacts or supporting-block removal. There are no per-render solver
dispatches. Existing legacy physics remains solely available to explicit callers
and source fixtures. Static22/0 and real IntelUHD Compatibility25/0 verify the
immediate2.3×0.6×2.5m prone model, blue/green tint, zero solver/model/terrain work
across1000 step/impulse calls, resource refresh and exact subsequent pixels.
Original9046/0 and independent1635/0 remain clean. Capture:
`.cache/previews/static-corpse/prone-blue-green.png`; source corpse SHA256
`68e4fb1423814185fc841457ffe70eb3166fb0a2f5c0111d562a51656f1dddf6`.

Further inspected CPU work is independent of corpses: TDM readouts cloned a full
owner state for four weapon/ammo fields, and every state clone rebuilt reflective
property descriptors. Direct synchronous scalar readouts retain caller-owned
profile dictionaries; base actor copies use typed value assignments and retain
owned motion/RNG. Subclass reflection behavior remains explicit. World now queues
unique affected chunk keys, preserving first-seen AO/collision/color/cancellation
semantics, and avoids geometry rebuilds when water enablement is unchanged.
These changes require independent oracle fixtures, replay/wire regressions and
fresh browser evidence; no decision cadence or visible terrain is reduced.

Final private actor-copy2320/0 and guarded weapon-readout78/0 pass. PlayerRules144/0,
prediction729/0, SimulationCodec2316/0, Match226/0, fanout4065/0, AI4440/0,
TDM81/0, actual-TDM62/0, source-goldens194/0 and UI284/0 pass. The owned-copy
benchmark includes motion/RNG construction:155.293→18.569µs median per copy,
8.36×. Complete weapon readout25.869→6.337µs,4.08×, against the old getter using
the already optimized copy. Each uses five alternating paired4000-call cohorts.
All four checked file hashes match the workspace; manifests, exact commands and
reports are under `.cache/gameplay-scalar-copy-8601689/.cache/`.

Independent review finds and resolves three extension contracts: custom World/Data
bounds/mapping retain the original27 virtual queries; raw public water changes
retain mesh/waves/reflection reconciliation and invalidate actual older geometry;
session/actor/motion readout hooks retain the original owned-snapshot dispatch.
Final guarded dirty2416/0, World30/0, water18/0, impact4441/0, preparation53/0
and actual native-Main25/0 pass. Paired World invalidation2430/0 matches every
ordered queue:1600 changes66.526→20.851ms (68.7% lower),25600 changes
1070.822→345.025ms (67.8% lower). This is World invalidation CPU, separate from
Data collapse/meshing/GPU; a large synchronous edit still exceeds a frame budget.
Report `.cache/benchmarks/world-dirty-maxopt-native-guarded.json`, source manifest
`.cache/world-dirty-maxopt-check/source-manifest-guarded.json`. Earlier unguarded
benchmarks are superseded. One native-Main exit leak failed the private gate;
the verbose and ordinary repeats both25/0 with clean exits are retained. An earlier
helper's Windows cp1251 output failure after the expected malformed-UTF8 fixture
warning is retained; its UTF8-safe repetition passed.
Final review also preserves a World/Data subclass's repeated water-invalidation
notifications. Final dirty2428/0, water18/0 and actual native-Main25/0 pass cleanly;
manifest `.cache/world-dirty-maxopt-check/source-manifest-water-guarded.json`.
The invalidation benchmark remains tied to WorldSHA
`b69c2f0b8b1165ef29e52b21cce29d034d38c4e35badf1216bdfc6c922b3c11a`;
only the water setter's extension guard changes afterward, not measured dirty loops.

Remaining audited limits: unchanged idle World/rebuild CPU is already small in
the expanded lab/Title windows, while these profiles do not cover Mirage traversal
or destructive edits. BFM decode is synchronous; a bulk decoder needs malformed,
atomic and transient-memory evidence. Chunk mesh/collider publication is indivisible,
so its4ms work scheduler cannot guarantee4ms on the phone. Greedy surface merging
must preserve per-cell color/AO/damage updates; streaming cache retention needs an
explicit memory cap and epoch/invalidation proof. These are open directions, not
claimed gains or silent quality reductions.

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
