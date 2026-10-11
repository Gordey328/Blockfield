# Fixed particle budget and simplified decorative effects

Evidence date: 2026-10-11. These measurements cover native and rendered-browser
component script CPU. They do not establish a whole-game FPS improvement, GPU
execution cost or performance on a physical phone. Compatibility readbacks and
browser integration checks are recorded below.

The accepted replacement is recorded in
[ADR0025](decisions/0025-fixed-noncolliding-effects.md). Decorative particles have
a hard limit of 50 active records, casings have a hard limit of 16 active records,
and each falling component displays at most 64 representative cubes. Particles
and casings follow analytical flight without terrain collisions. A falling group
moves for 1 second and disappears without fragments or smoke. Authoritative
collapse removal, weapon damage, grenade rules and voxel data are outside this
replacement and outside these benchmarks.

## Source and retained evidence

Engine: `4.7.2.stable.official.ed1daf0bf`. The JSON report's shorter engine string
is `4.7.2-stable (official)`; import logs retain the exact engine commit.
Reference: OpenSpades v0.1.3
`dcf449c845d509bbde9d79239b32d201c1389961`.
Baseline: Blockfield `26ea9883bdef9a7436bece87e36239857651dc8e`, archived before
production changes in `.cache/particle50-baseline/source.zip` and extracted into
`.cache/particle50-baseline`. Candidate: the isolated
`.cache/particle50-candidate-v1` project, with the new effects and falling code
copied into the same baseline project. Shared import caches and public build
folders were not used as benchmark projects.

Retained reports are `benchmark.json`, `benchmark-repeat.json` and
`simple-effects.json` in each of those two project directories. The first particle
pair and the repeat each finish with 12 assertions and 0 failures per variant.
The simple-effects report is an opt-in timing report, not a correctness gate.

SHA256 identities:

| Input | SHA256 |
| --- | --- |
| Baseline archive | `5d355a01294e62118bd689987ea63ad8a7d0dd7ca17c50fe014455ddaea035e7` |
| Baseline `openspades_effects.gd` | `c727df743b8c9c0504fb72124b8cc1d1a85a709a91018bba9a3f56ccc4ba2193` |
| Candidate `openspades_effects.gd` | `38375332563804e1227200cf8211fabf7a2419c6f646820c5369e293a8020f3e` |
| Candidate `falling_cluster.gd` | `084375a8a02ea10774da9420d2fd412cbf4ab6e9a64643116cebf1b1e39bb281` |
| First particle harness, retained in candidate tests | `23434e1a6221170dcffb62f0bbfc5de4a57e03733ad0eadb6305517e08a72154` |
| Corrected repeat particle harness | `64005c5d64f651421eedec76e135fcefe95f9f81616f35954dcdf272c6c27849` |
| Browser/current particle harness | `f26e349eceec5e7ae407fec923b94730cba18f034e03ace9573acc402f4a1905` |
| Simple-effects harness | `44f80b07ba1415d8a1698383b59963be73b223492e66a2d97701d77ffc80a9ca` |

These identify the measured component sources. A later integrated release must
record its own source commit and export identity.
The repeat harness is retained at `.cache/particle50-repeat-harness.gd`; the
current harness only renames its internal requested-event counter afterward.

## Particle workload and measurement boundaries

[The particle harness](../tests/presentation/benchmark_particle_budget.gd) creates
a compact 32 × 16 × 32 voxel world with floor and wall, a fixed camera and seeded
effects. Terrain meshing, resource loading and a warmup run occur before timing.
Casings, tracers, lights, audio and camera shake are disabled in this particle
case. Counts, statistics, recursive node counting, assertions and report writing
are outside the measured event/update interval.

The public scenario uses a fixed 1/60-second update for 480 live frames, then
720 frames without emission: 8 seconds of simulated effects plus a 12-second
expiry tail. It requests one nearby block impact every 4 frames, blood every
30 frames and an alternating land/water grenade every 120 frames. Both sources
receive 140 public event calls requesting 3,470 particles. This deliberately
compares the old default 512-particle presentation with the accepted default
50-particle presentation, including their different saturation policies.

`update` times the entire `update_effects` call, including fragment publication.
`frame_self` times emission plus that update. These are elapsed microsecond-clock
intervals around synchronous script calls, expressed below in milliseconds;
scheduling interruptions can affect them. They exclude the rest of the game and
are not frame duration or GPU timings.

| Observation, identical in both pairs | Baseline | Candidate |
| --- | ---: | ---: |
| Configured / peak active particles | 512 / 512 | 50 / 50 |
| Sum of active counts during live frames | 223,783 | 23,989 |
| Sum of active counts during tail frames | 27,990 | 5,676 |
| Live frames with active particles | 480 | 480 |
| Tail frames with active particles | 116 | 116 |
| Initial / peak / final effects nodes, including manager | 514 / 514 / 514 | 148 / 148 / 148 |
| Final active particles | 0 | 0 |

Candidate particle state allocations remain 50 and created nodes remain 147
between the initial and final snapshots. No new effect nodes or particle records
appear during this measured workload. Candidate overload counters, after
subtracting warmup values, record 3,101 recycled particles and 311 rejected
arrivals. The candidate node total includes its fixed casing model pools even
when the configured casing budget is zero; it is not a particle-only memory
comparison.

| Public live measurement | First baseline | First candidate | Repeat baseline | Repeat candidate |
| --- | ---: | ---: | ---: | ---: |
| Emission total CPU, ms | 67.202 | 214.911 | 89.917 | 106.000 |
| Update total CPU, ms | 5,075.018 | 246.826 | 6,370.287 | 101.808 |
| Emission + update total CPU, ms | 5,142.220 | 461.737 | 6,460.204 | 207.808 |
| Emission + update p50 per call, ms | 9.515 | 0.551 | 13.737 | 0.201 |
| Emission + update p95 per call, ms | 19.823 | 2.498 | 19.405 | 1.164 |
| Emission + update maximum per call, ms | 43.069 | 9.611 | 25.165 | 4.857 |
| Tail emission + update total CPU, ms | 1,011.064 | 65.586 | 458.841 | 27.392 |

Live component emission-plus-update time is 91.0% lower in the first pair and
96.8% lower in the repeat. Update time alone is 95.1% and 98.4% lower. Much of this
is the intended reduction in active particles and removal of terrain interaction.
Emission becomes more expensive: 219.8% higher in the first pair and 17.9% higher
in the repeat. The new overload policy searches the fixed pool to choose a
replacement, while the old full pool simply rejected arrivals. The update savings
outweigh that emission cost in both observed public runs.

## Equal-count comparison and repeat discrepancy

The second scenario sets both sources to 50 active particles and explicitly
requests `IGNORE` collision behavior on the historical implementation. It emits
40 fragments and 10 animated smoke particles once, with identical initial
positions, velocities, lifetime and options. There is no overload. It runs
180 live frames plus 180 tail frames; both variants peak at 50, have 150 frames
with active particles, sum to 7,500 active particle-frames and finish at zero.
Analytical trajectories replace the baseline integrator, so this is an equal
input/count comparison rather than a claim of identical intermediate poses.

| Equal 50 live measurement | First baseline | First candidate | Repeat baseline | Repeat candidate |
| --- | ---: | ---: | ---: | ---: |
| Update total CPU, ms | 109.638 | 118.961 | 71.557 | 38.683 |
| Emission + update total CPU, ms | 111.747 | 120.792 | 72.326 | 39.169 |
| Emission + update p50 per call, ms | 0.546 | 0.535 | 0.430 | 0.232 |
| Emission + update p95 per call, ms | 1.381 | 1.562 | 0.717 | 0.336 |
| Emission + update maximum per call, ms | 3.099 | 5.411 | 1.202 | 1.815 |
| Empty tail emission + update total CPU, ms | 2.349 | 13.138 | 1.337 | 0.806 |

The first equal-count pair is slower on total candidate update CPU by 8.5%, and
on emission-plus-update CPU by 8.1%. The repeat is faster by 45.9% and 45.8%,
respectively. The first candidate also has a 5.169 ms outlier in its entirely
empty tail. Both pairs retain identical active counts, but elapsed timings differ
substantially. The evidence does not establish a stable implementation-only
percentage or a cause for that variation. The large public-workload reduction is
observed in both pairs; claiming that pooling alone produced that reduction would
misrepresent this comparison.

## Casings and falling components

[The simple-effects harness](../tests/presentation/benchmark_simple_effects.gd)
emits 120 rifle/SMG casings over 480 fixed updates, with 480 further tail updates.
Audio, particles, tracers and lights are disabled. It times emission plus updates;
statistics and input construction are outside those intervals.

| Casing observation | Baseline | Candidate |
| --- | ---: | ---: |
| Configured cap / observed peak | 48 / 46 | 16 / 16 |
| Live component CPU, ms | 617.138 | 31.877 |
| Tail component CPU, ms | 35.597 | 11.059 |
| Live + tail component CPU, ms | 652.735 | 42.936 |
| Terrain queries | 21,131 | 0 |
| Contact signals | 120 | 0 |
| New nodes after prewarm | 0 | 0 |
| Final active casings | 0 | 0 |

This single pair has 94.8% lower live component CPU and 93.4% lower live-plus-tail
CPU. It combines the lower cap, shorter 2-second flight and removal of collisions
and contact behavior. It does not isolate the cost of changing casing storage.

The falling case constructs fixed 10³ and 24³ components above the ground. It
times `setup`, then `step` calls until completion. Source cell/color array
construction is excluded. Setup intentionally includes geometry preparation.
Baseline simulation includes its later debris stage; the accepted replacement
ends after its 1-second group animation. World connectivity/removal and terrain
rebuilding are not timed here.

| Falling observation | 1,000 baseline | 1,000 candidate | 13,824 baseline | 13,824 candidate |
| --- | ---: | ---: | ---: | ---: |
| Setup CPU, ms | 4.865 | 1.006 | 58.313 | 1.474 |
| Lifetime step CPU, ms | 1,270.036 | 0.181 | 1,061.420 | 0.104 |
| Renderer child nodes at completion | 3 | 1 | 3 | 1 |
| Retained fragment count in final diagnostics | 2,928 | 0 | 4,096 | 0 |
| Retained smoke count in final diagnostics | 488 | 0 | 1,024 | 0 |
| Candidate rendered cubes | — | 64 | — | 64 |
| Terrain queries | 274,922 | 0 | 423,521 | 0 |

Both candidate groups report their exact original block counts, `COMPLETE` phase
and reason `simplified`. The large lifetime CPU reduction follows from removing
thousands of simulated fragments/smoke and their terrain queries, shortening the
effect and sampling 64 cubes. These are intentionally different visible effects;
the table is not an equivalent-geometry renderer optimization claim. Baseline
fragment/smoke numbers are retained array sizes after completion, not live
particles at the end of the run.

## Harness corrections and reproducible commands

The initial particle reports used the names `emitted_events` and
`positive_emission_events`. The latter counted requests while any particles
remained, even if a saturated pool rejected a particular arrival. The corrected
repeat reports use `requested_events`, `requested_events_with_active_particles`
and `first_emission_observed`. The repeat explicitly verifies that the first
requested emission frame changes an empty manager into one with active particles;
both scenarios in both variants report true. Requested-event counts are not
accepted-particle counts. This diagnostics correction is outside the timed calls;
both retained pairs are shown above.

Earlier candidate checks exposed three separate issues: an unsupported normalized
vector expression in a GDScript constant, an untyped empty-array ternary in the
falling fixture, and asset-catalog JSON parse errors in the copied diagnostic
project. The constant became a literal unit vector, the fixture now uses a typed
empty array, and baseline asset JSON was recopied into the diagnostic. Failed
effects/falling outputs remain in `particle50-effects-first.log` and
`particle50-falling-first.log` under the candidate `.cache/logs` directory.
The later headless component fixtures pass: effects 20,928/0, fragment updates
43/0 and falling/water 43/0. GPU readback cases are explicitly skipped in these
headless logs; those results alone do not prove rendering.

The affected integration checks also pass, all with zero failures: world 30,
voxel data 171, voxel adapter 25, world resources 8, lighting 30, block impact
4,441, grenade 17, camera 45, presentation 504, lab 119 and TDM scene 62.
Audio 158 and environment 76 pass with real elapsed time, on both baseline and
candidate. An earlier coordinator helper incorrectly applied `--fixed-fps 60`
to the audio/environment fixtures and produced resource-exit diagnostics; their
corrected real-time invocations pass. Client runtime and dedicated-server smoke
checks pass. These results remain tied to the isolated candidate component
sources above, rather than a later integrated release.

The coordinator prepared the baseline with `.cache/prepare_particle50.py`, the
candidate with `.cache/check_particle50.py`, and ran the auxiliary baseline and
repeat through `.cache/run_particle50_stage.py baseline-aux` and `repeat`.
Those retained helpers show the isolated paths and exact copied inputs. The
following PowerShell commands rerun the same cases against the retained imported
projects, writing new report files so the original evidence is preserved:

```powershell
$task_root = (Get-Location).Path
$task_engine = Join-Path $task_root '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$task_first_harness = Join-Path $task_root '.cache/particle50-candidate-v1/tests/presentation/benchmark_particle_budget.gd'
$task_repeat_harness = Join-Path $task_root 'tests/presentation/benchmark_particle_budget.gd'
$task_simple_harness = Join-Path $task_root 'tests/presentation/benchmark_simple_effects.gd'
foreach ($task_variant in @('baseline', 'candidate-v1')) {
    $task_project = Join-Path $task_root ('.cache/particle50-' + $task_variant)
    & $task_engine --headless --path "$task_project/game" --script $task_first_harness -- "--label=$task_variant" "--report=$task_project/benchmark-reproduced.json"
    & $task_engine --headless --path "$task_project/game" --script $task_repeat_harness -- "--label=$task_variant" "--report=$task_project/benchmark-repeat-reproduced.json"
    & $task_engine --headless --path "$task_project/game" --script $task_simple_harness -- "--label=$task_variant" "--report=$task_project/simple-effects-reproduced.json"
}
```

Use the recorded runtime/harness hashes when checking the retained result. A
different engine, later source, host load or renderer requires new evidence;
exact elapsed timings will vary. The `.cache` projects and reports are diagnostic
artifacts, not production entry scenes or part of the Pages export.

## Native Compatibility checks and rejected bulk publication

The coordinator ran actual native Compatibility checks on
`Intel(R) UHD Graphics`, OpenGL 3.3, driver `31.0.101.2127`. Effects pass
20,931 assertions with zero failures; falling/water pass 45/0. These include the
transform/color readbacks skipped by the headless renderer. Preview generation
also completes, writing images under `.cache/particle50-candidate-v1/previews`.
Logs are `particle50-gpu-effects.log`, `particle50-gpu-falling.log` and
`particle50-gpu-preview.log` in the candidate `.cache/logs` directory. This is
native rendering evidence; it does not establish browser or physical-phone
behavior.

The existing opt-in [bulk-publication experiment](../tests/presentation/benchmark_impact_effects.gd)
was adapted to 40 collision-free data-only Title fragments, a fixed 50-slot
buffer, analytical 1/60-second updates and alternating variant order. The
experiment writes a documented 16-float transform/color buffer instead of
production per-instance setters. It samples 90 dense frames and 90 tail frames;
all integration/count/lifetime inputs are equal between its two variants.

| Publication experiment | Native headless setters | Native headless bulk | Compatibility setters | Compatibility bulk |
| --- | ---: | ---: | ---: | ---: |
| Dense total component CPU, ms | 17.136 | 20.361 | 19.642 | 21.803 |
| Tail total component CPU, ms | 6.620 | 7.129 | 8.153 | 10.020 |
| Dense + tail component CPU, ms | 23.756 | 27.490 | 27.795 | 31.823 |
| Dense publication-only CPU, ms | 6.336 | 8.661 | 7.037 | 9.360 |

Bulk total component CPU is 15.7% higher headlessly and 14.5% higher with
Compatibility rendering enabled. The bulk buffer retains another 3,200 bytes.
Correctness checks pass 187/0 headlessly and 267/0 with actual transform/color
readback. Reports are `bulk-native.json` and `bulk-gpu.json`; production retains
the measured faster per-instance setters. The Compatibility timings still cover
script calls, not a separately measured GPU execution interval or FPS.

The following commands reproduce the component checks and experiment against the
retained candidate. GPU commands omit `--headless`; audio fixtures omit
`--fixed-fps`:

```powershell
$task_candidate = Join-Path $task_root '.cache/particle50-candidate-v1'
& $task_engine --headless --path "$task_candidate/game" --script "$task_candidate/tests/audio/test_audio.gd"
& $task_engine --headless --path "$task_candidate/game" --script "$task_candidate/tests/audio/test_environment.gd"
& $task_engine --path "$task_candidate/game" --script "$task_candidate/tests/presentation/test_effects.gd"
& $task_engine --path "$task_candidate/game" --script "$task_candidate/tests/world/test_falling_clusters.gd"
& $task_engine --headless --path "$task_candidate/game" --script "$task_candidate/tests/presentation/benchmark_impact_effects.gd" -- "--report=$task_candidate/bulk-native-reproduced.json"
& $task_engine --path "$task_candidate/game" --script "$task_candidate/tests/presentation/benchmark_impact_effects.gd" -- "--report=$task_candidate/bulk-gpu-reproduced.json"
```

## Rendered browser checks

Both isolated sources use the same corrected helper, 1280 × 720 in-app browser
viewport, WebKit WebGL and hash-pinned reduced Godot 4.7.2 template
`a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`.
The Web engine reports `4.7.2-stable (custom_build)`; its template identity is
preserved in each `identity.json`. Exports are retained at
`.cache/particle50-probe-baseline-v2` and
`.cache/particle50-probe-candidate-v1-v2`.
Export commands: `python tools/export_particle_probe.py --source
.cache/particle50-baseline --name baseline-v2 --import-cache
.cache/particle50-baseline/game/.godot`, and the equivalent candidate-v1 command
with name `candidate-v1-v2`. The corrected start guard prevents overlapping runs
and clears the previous DOM result before each run. Reports were read from visible
`#particle-budget-result` into `browser-public.json` and `browser-equal50.json`
in each source directory; both workloads pass all four bounded/positive/expiry
checks for each source. CPU intervals have browser clock quantization.

| Rendered component measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Public peak particles | 512 | 50 |
| Public live update CPU, ms | 8,945.2 | 499.0 |
| Public live emission + update CPU, ms | 9,083.5 | 898.5 |
| Public live emission + update p95, ms | 26.7 | 4.8 |
| Public peak total scene draw calls | 41 | 17 |
| Public wall time including expiry tail, seconds | 44.302 | 46.269 |
| Equal 50 live emission + update CPU, ms | 285.7 | 196.9 |
| Equal 50 live update CPU, ms | 283.7 | 193.0 |
| Equal 50 peak scene draw calls | 19 | 19 |

Public component CPU falls by 90.1%. The equal-count case is 31.1% lower for
emission plus update in this single rendered pair. Native equal-count variability
still prevents a stable implementation-only percentage claim. Browser wall time
does not improve in this run; render scheduling, tool activity and host workload
are not controlled. No whole-game FPS claim follows from the CPU reduction.

The separate actual-Main probe uses the same production Effects/Falling sources
at `.cache/effects-probe-particle50-main-v1`. It runs held SMG fire into a compact
wall with terrain edits and normal audio enabled. The visible report
`#effects-probe-result`, retained as `browser-main-stress.json`, passes all seven
checks: positive particles/casings, caps, no new nodes, no new particle/casing
records, and no casing contact. Peaks are 50 particles, 16 casings and 160 total
scene draw calls; particle/casing allocations remain 50/16. Brown impact fragments
and terrain holes are visible. This is an integration test, not a paired FPS
experiment (97 frames / 12.070 simulated seconds, 16.523 wall seconds).

Removing one roof support immediately removes all 400 authoritative roof cells.
The paused quarter-second inspection renders one group of 64 colored cubes with
zero smoke/fragments and no precise physics. Advancing the remaining 0.75 seconds
leaves zero clusters/falling/fragments/smoke and the roof remains absent from map
data. Visible DOM snapshots are retained as `browser-collapse-initial.json` and
`browser-collapse-complete.json`. The diagnostic uses an independent fixed camera
for clear inspection; production automatically advances the one-second lifetime.
Native previews are retained in `.cache/particle50-candidate-v1/previews`.

Initial actual-Main startup exceeded one accessibility-call deadline and the
browser logged a generic Chromium UnknownError. Rebinding the already-created tab
worked; Godot integration checks passed. No Godot script/renderer error was observed.

## Frozen development release

Source commit `1b02c6451cf6976225c680f1ab77ddfcb9f47aa5` contains only the owned
effects/falling/fixtures/docs changes. Unrelated Mirage and research edits remain
in the shared workspace. Git archive is retained at `.cache/particle50-release`.
Its parser/import, effects 20,928/0 (three explicit dummy-renderer skips), fragment
43/0, falling 43/0, client/server runtime smokes and reduced-template Web export
pass. Project configuration is restored to exact archived bytes before export;
build metadata reports `source_dirty: false`, status `development`.
The initial frozen helper's byte comparison rejected CRLF versus Git-normalized
LF in falling source before any engine check. Comparing normalized text fixes
that helper assumption; the original archive is preserved. Production semantics
are unchanged, and frozen checks are rerun successfully.

Normal Web QA at `http://127.0.0.1:8094/release/index.html` verifies menu/SMG
selection, walking, mouse fire (30 to 14 rounds with unlimited ammo temporarily
disabled), drag-look fallback, grenade selection/throw (3 to 2), and restoring
the original unlimited-ammo setting. Diagnostic Main terrain/collapse checks
above verify map edits. The in-app browser denies pointer capture and reports
generic Chromium UnknownErrors; fallback controls work. No Godot script error is
observed. Local screenshot: `.cache/particle50-release/local-game.png`; collapse
screenshots: `.cache/particle50-candidate-v1/web-collapse{,-cleanup}.png`.

Source is pushed to `main`; a separate ignored publication checkout preserves
existing sibling Pages paths. `tools/publish_pages.py` publishes the checked
export from that checkout through its normal branch-hosting flow. Pages reports
`built` at bundle `6e4c14c21cdf4c297ac85d87cb613461757e232e`.
At 2026-10-11 18:58:47 UTC, fresh public requests confirm the exact clean source
metadata and all five matching file hashes. Full result is retained in
`.cache/particle50-release/public-verification.json`.

| Public file | SHA256 |
| --- | --- |
| `build-info.json` | `546ac2c1c96ac22c3efad23232800086a6256c6934a9231e822ecbc44abaab9d` |
| `index.html` | `431ccdd085a36a96a9a0221da9b5d5ea10ee30f1694fd5fcb7a5bac52a2e08a9` |
| `index.js` | `6cd28515e4bf854b729d9d506761cb53df661b0f133dc3b266925589244b8ed3` |
| `index.wasm` | `a5e1eb468696dcc8a21161deaaca8c382e2c722edbec151832de0c28a938eadb` |
| `index.pck` | `24ee893e1c35e9aa1b7c0ebd8782d4a68f2c79be6d1a4afc66b935ce7bd19935` |

Published development game: [Blockfield](https://gordey328.github.io/Blockfield/).
Public interactive startup also passes: retained mobile-control preference is
preserved, SMG selection and entry work, forward movement changes the scene/minimap,
and held Fire registers a visible `head · 75` hit. Screenshot:
`.cache/particle50-release/public-game.png`. Temporary probe/browser/server leases
are returned at turn end; all specialist handoffs are complete.
No full-port, physical-phone or whole-game performance acceptance is promoted.
