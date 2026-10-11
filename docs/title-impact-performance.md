# Warmed Title impact / CPU optimization — 2026-10-11

The user asks to continue optimizing the remaining Title terrain-hit freezes and
aggregate CPU. Baseline source `0d69907d05922316185333594e7a5ead29820c9b` has the
published b3e game bytes. Godot `4.7.2.stable.official.ed1daf0bf`, source
`dcf449c845d509bbde9d79239b32d201c1389961`, Compatibility/single-threaded Web.
Previous evidence and preserved failure chain: [impact optimization](block-impact-performance.md).

## Contracts and ownership

Root owns integration/Main/UI audit, docs/config/release and serial engine runs.
`impact_world` owns Chunk/World, batching execution across unchanged bounded
columns/planes to avoid repeated buffer ownership transfers; deadline/unit caps
still apply at each original boundary, complete current mesh/shape publish together.
`impact_rules` owns Effects and a regression fixture, removing identity arithmetic,
redundant white-fragment fade work and dynamic calls for exact concrete Data.
All source counts, lifetimes, collision, fade/billboards and visible sprites remain.
`impact_tests` owns new native/warmed actual-Main diagnostics and the isolated
export helper. The previous browser probe and frozen artifacts stay intact.
Existing Steam AoS research files and status insertion remain separately owned.

Measured audio follow-up ownership is non-overlapping: World specialist owns
only the new PCM converter/asset tree/manifest; Rules specialist owns Extensions
and the new PCM fixture. Root owns wet-change coverage and suite registration.
Diagnostics owns identical trusted-input overlays, isolated source copies and
serial imports/exports. All specialist engine leases are returned before the
actual browser measurements; only one game tab is running during those phases.

## Measurement plan

Archive `.cache/title-impact-baseline-source.zip` is extracted under
`.cache/title-impact-baseline/source`. Native fixed60Hz actual-Main throughput
measures idle/shoot/tail inclusive/exclusive CPU through identical diagnostic-only
wrappers; synchronous terrain flush ensures equal completed geometry work.
The production-budget cadence benchmark remains separate for latency/cancellation.
The Web probe waits for completed voxel/visual/minimap preparation, warms effects
and shaders, then shoots editable original Title terrain. Positive shot/removal
counts, pending queues, tail work, module CPU and frame distributions are required.
Instrumentation is bounded and shared by both sources. No reduction is claimed
until paired evidence exists; exported visual/input and frozen checks follow.

## Bounded world batching checkpoint

The unchanged fixed-cadence fixture in `.cache/title-impact-fixed-benchmark.gd`
runs against archived0d69907 and candidate game bytes, serially with no game browser.
Reports: `.cache/benchmarks/title-batch-{baseline,candidate}-native.json`.
Destructive presentation includes all completed work, rather than only shot latency:

| Map | Published baseline median / mean | Candidate median / mean | Candidate peak slice |
| --- | --- | --- | --- |
| Grounded lab wall | 11.112 / 13.950ms | 9.086 / 10.844ms | 4.236ms |
| Original Title excerpt | 10.005 / 12.069ms | 7.720 / 9.342ms | 4.479ms |

Candidate aggregate medians are also below the older monolithic662a288 paired
baseline10.875/8.579ms, by16.4%/10.0%; means fall13.9%/10.7%. This is a
headless CPU fixture, excluding real callbacks, GPU and physical-device FPS.
Optional stage timing is enabled only in this breakdown fixture. It accounts for
37/30 full jobs and35/29 collision jobs; candidate has0 cancellations, baseline
lab has1. Halo/mesh/collision/publication retain their original unit counts and
each original deadline boundary. Default production stage timing remains off.

World import, world30, damage31, lighting30, impact4441 and preparation53 pass.
The initial damage command named a nonexistent test; its log was subsequently
overwritten by the successful corrected invocation, so the tool history is the
retained evidence of that command error. A diagnostic-only packed-array/int merge
error was repaired; `.cache/logs/title-batch-candidate-harness-failed.log` is
preserved. No production parser or behavioral failure occurred in this checkpoint.
World specialist returned the engine lease and stable files. Effects has the next
serial lease; the full warmed Main/browser comparison remains pending.

## Effects checkpoint

Stable Effects parser/import, fragment34/0 (five additional non-identity/fade/
concrete/overridden-world cases) and existing effects32588/0 pass; the existing
three headless GPU skips remain explicit. An opt-in400-fragment Title fixture
compares per-instance setters with a fixed512-instance,16-float-per-instance bulk
buffer. Both use exact deterministic1/60 integration and identical lifetimes.
Correctness checks:187/0 headless and987/0 actual Compatibility, including800
transform/color readbacks. Reports/logs: `.cache/benchmarks/title-effects-*` and
`.cache/logs/title-effects-*`. No FPS claim follows from these CPU windows.

Actual Compatibility setter dense median3638→3170µs, aggregate342649→291364µs
(-15.0%); tail110109→100084µs (-9.1%). Candidate bulk dense303491µs versus
setters291364µs (+4.2%), tail+4.4%; production retains per-instance setters.
The experiment is outside normal gates; no speculative API change was adopted.

The first benchmark invocation assigned an untyped ternary array to a typed
array, aborted its coroutine and then timed out180s before sampling. That failed
log is preserved as `title-effects-baseline-pressure.log`; explicit typed append
order fixes only the fixture. The corrected repeated runs pass. Effects returned
the exclusive engine lease; diagnostics now own it for Main profiles and exports.

## Actual-Main fixture corrections and audio audit

The first d baseline reaches a warmed original Title cliff at(386,13,387), outward
normal(0,0,-1), eight inward solid cells and three outward air cells:73shots,
24removed cells,0collapse, drained terrain/effect queues. Earlier c preparation
failed because radius128/step4/top-2 excluded that real cliff; its failed log
`warm-title-baseline-c-1.log` remains. The finder validates the priority original
coordinate and has a full-map/step1/y>=2 fallback; it does not edit terrain.

The valid d baseline report is retained, but its engine invocation failed cleanup:
root cannot restore PROCESS_MODE_INHERIT. The engine nevertheless exited normally
and printed PASS; the validation wrapper correctly rejected the ERROR diagnostic.
No timeout/tree termination occurred for d. The native fixture now saves/restores
the actual previous root process mode. This failed invocation is not a passing
check or final paired performance result. The corrected e baseline engine passed,
but Python summary output failed to encode a Unicode arrow in CP1251 after the
engine completed; its report/log are retained. Subsequent runs use UTF8 output.

The baseline native manual fixture exposes substantial Audio._play and
Audio._process CPU, but its compressed virtual time keeps128logical voices /
384players alive because the mixer uses wall time. Native total CPU therefore
cannot be compared as equal audio work without voice/update counts. Real Web
cadence and module-specific CPU remain required.

Read-only pinned engine audit identifies a safe narrower audio improvement:
AudioStreamPlayerInternal::set_pitch_scale walks active playbacks even if its
stored value is unchanged. Wet copies can skip exact-equal pitch and global
transform writes. Naive bus equality checks would add a bus-name scan, so they
are excluded. Ogg playback creates a fresh decoder; PCM/pool rewrites are deferred
until lookup/start timing and real-cadence evidence justify them.

## Clean actual-Main native pair f

`warm-title-{baseline,candidate}-f-1.json` / corresponding logs: clean import,
native engine exit and Web export. Both produce73shots/24removals/0collapse,
identical removal/shot trajectory without wall timestamps, peak509particles,
26mesh/26collider builds,25color updates/1200bytes,0build cancellations and
143tail frames. Default graphics and effects counters match. Audio update counts
also match48872shoot+18304tail, with128logical/384players retained at tail end;
this pair compares equal native instrumented work, still excluding real mixer
cadence, GPU and disposal. Drained means World rebuild/visual queues and effects;
audio lifetime is reported separately.

| Shoot CPU metric | Published baseline | Candidate f |
| --- | --- | --- |
| Sum instrumented exclusive CPU | 3803.4ms | 3546.3ms |
| Manual CPU-frame p95 | 23.332ms | 21.083ms |
| World synchronous completed work | 247934µs | 187783µs |
| Particle integration | 853433µs | 599627µs |
| Audio process | 791850µs | 728915µs |
| HUD inclusive | 161622µs | 95927µs |
| HUD exclusive | 111509µs | 95927µs |
| Hidden World.get_stats calls | 480 | 0 |

Effects update inclusive1655.002→1507.758ms includes nested audio callbacks;
module self sum1460.355→1349.630ms (-7.6%). Fragment batch433167→581196µs
increases34.2% in this one pair despite unchanged setters, so the standalone
particle/Compatibility fixture and complete callback are both reported.
Audio start exclusive657731→699280µs increases6.3%; f addresses redundant
wet setters, not decoder startup. Baseline _play inclusive700251µs/exclusive24499;
_start_voice675752/657731µs and942_new_player calls18021µs locate the larger cost
after node construction. Resource lookup is a smaller part of this fixture.

Native engine totals96.0/99.5s include unmeasured deferred physics/tree disposal:
first await39/43.5s, total cleanup79/83.5s; audio.stop18/5ms. There is no timeout
or suppressed production diagnostic. These timings do not establish real frame
latency or complete scene-disposal performance. The old eight-second browser
probe SHA remains217adbcea68bfb754994ce58b022ce3d16d4ea929e0ff5296fcf9bdd15229478.

## Native-format PCM follow-up

The measured decoder cost motivates the source-native approach rather than a
reduction in sound layers. Upstream `Sources/Audio/ALDevice.cpp:59–75,96–143`
predecodes original Opus to PCM16, using floor(float*32768). Source
`Sources/Core/OpusAudioStream.cpp` reads48kHz libopus floats. The new
`tools/predecode_impact_sounds.py` reads the original pinned r33/source resources,
explicitly selects libopus, validates OpusHead/EOS frames/channels, converts with
native quantization and emits uncompressed PCM16 WAV plus a separate manifest.
It never decodes the existing Vorbis transcode. Native PCM is the upstream output
format; bit identity to the different, lossy Vorbis derivative is not claimed.

Generation/verification:49/0,7,442,462 PCM bytes /7,444,618 WAV bytes, largest618,976
PCM bytes, no nonfinite or overflowing samples, all48kHz and exact original frame
counts/channels. Second conversion preserves99 file hashes (WAV/import/manifest).
Log: `.cache/logs/title-impact-pcm-generation.log`. Existing FFmpeg7.1 from the
prior asset importer is used, binary hash/version included in the manifest.
Reproduce with the bundled Python (or Python3.10+) and existing converter:

```powershell
python tools/predecode_impact_sounds.py --ffmpeg .cache/asset-python/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe
python tools/predecode_impact_sounds.py --verify
```

Godot4.7.2 defaults WAV import to QOA, so these49 imports explicitly set
compress/mode=0 and disable mono/8bit/rate changes, trimming, normalization and
loops. The new `tests/audio/test_impact_pcm.gd` must verify exact imported
`AudioStreamWAV.data` hashes, rate/channel/frame identity, aliases, active ZIP
precedence and bounded missing/malformed fallback. Extensions retains at most
8MiB immutable whitelisted PCM; overrides remain first and the146-entry catalog
remains available. [ADR0016](decisions/0016-impact-cpu-batching.md) owns the choice.

The first f Web baseline result is retained separately as
`warm-title-baseline-web-f-suspended.json`:1527 settling callbacks,
73shots/24removals, shoot p9583.4ms and4.0465s exclusive CPU. Audio retains
128logical/384players after the real-cadence tail, suggesting the browser audio
context was never gesture-activated when the outside-canvas profile button was
clicked. This is not accepted as audible/real audio-cadence comparison. Console
records two host Chromium UnknownError diagnostics. The next paired fixture must
use an ordinary trusted canvas input before preparation and report actual audio
release workload; source/CPU checks and browser audibility remain separate.

Pinned Web bootstrap binds mousedown to the canvas; DisplayServerWeb's mouse
callback resumes audio. The outside diagnostic button bypassed that callback.
New G diagnostic buttons remain disabled until a trusted canvas mousedown is
observed, with a visible instruction to click the game then release the cursor.
No AudioContext override or hidden game scripting is used by browser automation.
The same overlay/recorder is exported for both production sources.

Current native parser/import passes on unchanged-source retry after a cold49-WAV
import returned1 without SCRIPT/Parse/ERROR diagnostics. The failed
`warm-g-current-import.log` is preserved separately from the successful retry.
PCM523/0 and environment76/0 pass, including all49 imported sample hashes, ZIP
override stacking/removal, malformed/missing/frame-mismatch fallback and the six
actual wet pitch/global-transform change checks. These are exact sample/routing
checks, separate from audible browser acceptance.

## Gesture-activated G browser comparison

Serial G baseline/candidate exports pass parser/import/export with byte-identical
diagnostics. Profile e59df28e1ee9246995afd09d5c41afd74f3a9c672cde299b3549d89b5dc2b25b;
native919a5cb79117453c69ba2f0877dfaadc60ca33b3039e1bd879038860988f0509;
recorderc6a473da2b6414f36308435a5f16f0895d339eddefe2f7a6d36a1f52a26866da.
Only six common production modules differ (World/Chunk/Effects/Audio/Extensions/HUD),
plus candidate PCM assets. Build folders are
`.cache/block-impact-probe-warm-{baseline,candidate}-g/build/web`, served locally
at8907/8905. One foreground IAB tab alternates sources; no concurrent engine,
converter or other game tab runs during measured phases. A trusted canvas click,
Escape and the visible Profile warmed Title button start each independent load.
Every report records activation count1, exact default graphics, settled visual
and minimap preparation, positive removals and drained World/effects queues.

First pair `warm-title-{baseline,candidate}-web-g-a.json`:73shots/24removals each.
Unlike the suspended f sample, both release actual audio and end tail with zero
logical voices:609+339 versus804+144 players released in shoot/tail. Shoot+tail
instrumented exclusive CPU3523.3→3348.8ms (-5.0%); shoot3156.4→2918.8ms (-7.5%).
Audio start inclusive811.1→122.4ms (-84.9%). There are more candidate rendered
callbacks115→237, so per-frame CPU reductions are not aggregate CPU reductions.
Audio mixing/renderer/engine costs outside GDScript wrappers remain unmeasured.
Shoot callback p50/p95/p99/max75.6/103.1/105.2/118.8→33.0/46.6/48.2/50.9ms.
Idle p9527.7→22.7ms; tail p9549.7→24.8ms. These are actual browser frame intervals
on this host/viewport, not physical-device or universal60FPS acceptance. Repeats
and the frozen normal build remain pending at this checkpoint.

All three independent G pairs are valid and remove the same24 original cliff
cells in the same map-sequence order. Baseline shots73/73/72, candidate73/73/73;
the third baseline has one fewer shot under real cadence. Mean shoot CPU falls
8.7% raw or9.1% per shot; shoot+tail falls6.1% raw or6.5% per shot. Idle mean
exclusive CPU/realsecond105.28→83.89ms (-20.3%). These are summed instrumented
GDScript times, not OS CPU utilization or all renderer/AudioServer work.

| Repeat | Baseline shoot p95 / max | Candidate shoot p95 / max | Baseline / candidate shoot+tail CPU |
| --- | --- | --- | --- |
| a | 103.1 / 118.8ms | 46.6 / 50.9ms | 3523.3 / 3348.8ms |
| b | 114.1 / 121.7ms | 46.7 / 63.9ms | 3591.0 / 3339.3ms |
| c | 119.8 / 126.2ms | 45.9 / 52.1ms | 3594.4 / 3369.7ms |

Median of the three p95 values114.1→46.6ms (-59.2%). Candidate tail p95
24.8/25.8/27.0ms versus49.7/62.7/62.9ms; candidate final voices0/0/0,
baseline0/1/1. Candidate queues finish during shooting; baseline finishes in
tail. Candidate26 completed mesh/collider jobs and0 cancellations each; baseline
3/7/9 cancellations during shooting. Equal completed-work native evidence stays
separate from this faster real-cadence queue. Mean Web audio-start inclusive
849.2→121.37ms (-85.7%), world self324.17→290.07ms, particles1139.87→929.53ms.
The higher callback count raises fragment-publication/HUD totals129.67→375.8ms /
53.93→70.13ms, even though per-frame writes and hidden-stats behavior improve;
these increases are included in the aggregate CPU sum. Mixer update counts also
differ8262/7836/7519 versus12431/12157/12281 and are not treated as equal workload.

Reports/logs: `.cache/benchmarks/warm-title-{baseline,candidate}-web-g-{a,b,c}.json`,
`.cache/logs/warm-title-{baseline,candidate}-web-g-{a,b,c}-console.json`;
derived `.cache/benchmarks/title-impact-web-summary.json`. Same6px diagnostic
overlay/default viewport and graphics throughout; canvas922x714 physical,
614x476 CSS, DPR1.5. Host pointer-lock UnknownError is retained; no script/parser
or failed WebGL resource diagnostic was suppressed. Rare63.9ms frames still occur
on this host. This accepts the measured improvement, not zero stalls everywhere,
complete port acceptance or sustained physical iPhone performance.

Console artifacts accumulate the single tab's prior navigations; URLs/timestamps
identify each load. The seeded baseline G diagnostic reports a startup-only
invalid scene-script UID and resolves it through the correct `res://__probe/impact.gd`
text path. Its visible trusted-input gate and identical script hash confirm the
new G script runs; no warning occurs in measured phases. This diagnostic-cache
warning is retained and is separate from parser/resource failure. The frozen
normal Main export must be checked independently without diagnostic scene/cache.

Static cross-review of frozen427c64b9 found no actionable concern: Rules reviewed
World/Chunk deadlines, unit caps, buffer ownership, cancellation and complete
publication plus HUD visibility; World reviewed Extensions alias/ZIP/cache/fallback
and Effects collision/fade semantics. Reviewers made no edits or engine runs.

## Frozen-check fixture repair

The first frozen427c64b9 all-suite run stopped at fragment34/1, not a passing
release. All earlier gates passed; the failed log is retained under
`.cache/release-427c64b9e26b/.cache/logs/test-impact-fragment-updates.log` and
`.cache/logs/title-frozen-release.log`. The opaque fixture assumed zero scale
writes after a random spin. Godot's basis decomposition/global-position mirror
can round that scale slightly, legitimately causing one exact corrective write;
trajectory, gravity, age, radius and color checks all passed. Root's actual
`opaque-scale-diagnostic.log` reproduces it at deterministic1.234rad with one
scale write and zero color writes, while zero spin performs no scale write.

Only the fixture is repaired: zero-spin/exact-scale setup for the zero-write
contract; separate1.234rad50/100ms cases require retained3/6substeps, one position
mirror, at most one scale mirror, no color mirror and correct final source state.
All prior collision/fade/external-transform/custom-world assertions remain.
Ten serial invocations pass44/0 each, logs `test-impact-fragment-deterministic-1`
through`-10`. Production game bytes and all paired Web evidence are unchanged.
The final frozen revision repeats the full89 gates and normal Web export.
