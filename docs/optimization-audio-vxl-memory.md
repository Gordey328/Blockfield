# Optimization item4: audio, VXL and memory

Date: 2026-10-11, Europe/Moscow. User approved item4 of the chat summary:
audio, loading and memory. Shot hit-volume preparation and the other stages of
[the plan](optimization-plan.md) remain separate work. This is a development
optimization checkpoint, not full OpenSpades-port acceptance.

Baseline: source `556c6dce324f1c33817cb182bb50118113195648`, whose `game/` matches
published `4c051639e286b3ea4945c77cfa6d568c36bf39be`. Engine
`4.7.2.stable.official.ed1daf0bf`, Compatibility/single-thread Web, upstream
`dcf449c845d509bbde9d79239b32d201c1389961`. Contracts are in
[ADR0013](decisions/0013-audio-vxl-memory.md).

## Implemented behavior

- Gun ambience keeps up to128 exact origins for one terrain/resource version.
  Edits/reset/map replacement/resource reload invalidate it. Full audio counters
  include gun rays, explosion ground rays, room/obstruction and player lifecycle.
  Timing remains opt-in. Existing sound layers and DSP routes are preserved.
- Local original/upload/reset VXL loading and saving yield between bounded
  column batches with HUD progress. Decode stays private until validated adoption;
  save uses a coherent frozen version. Superseding operations and reset/exit cancel
  old work and suppress stale notices/baselines/downloads. Sync network APIs remain.
- Small labs export with virtual padding, avoiding a64MiB temporary native map.
  Tint caches retain up to256 exact colors per depth mode with LRU eviction.
  Live materials survive eviction and retain their original colors.

## Native measurements

These are CPU/engine-static-memory diagnostics, not exported-game FPS, process
RSS, GPU memory or phone acceptance. Logs and JSON reports remain in `.cache/`.

Audio fixture120 calls/scenario,3 repeats with alternating cache order, identical
checksums, **142 checks/0 failures**. Report
`.cache/previews/audio-optimization/audio-item4.json`:

| Scenario | Uncached rays | Cached rays | Mean query time, uncached → cached |
| --- | ---: | ---: | --- |
| Stationary | 5640 | 47 | 2.47–3.11ms →23–26µs |
| Moving, every origin unique | 5640 | 5640 | No ray reduction |
| Edit every10 calls | 5640 | 564 | 2.52–2.82ms →260–277µs |

Stationary hits have p95=3–4µs, but the first miss still takes milliseconds;
edited-case p95 remains2.56–2.68ms. No claim of universal audio speedup.
Churn fixture192 silent logical voices/repeat: creation/release12–20µs/dry voice
and31–52µs/EFX voice. It excludes decoding, mixing, delayed frees and frame waits.
Pooling is deferred based on absolute cost, as recorded in ADR0013.

Old-model deterministic baseline retained129/257/513 materials after128/256/512
colors. Frozen copy `.cache/optimization4-baseline-556c6dce324f/`; successful log
`optimization4-model-baseline-resolved.log` records513/0. The first relative-script
invocation failed because the fixture was outside `res://`; its original log
`optimization4-model-baseline.log` is preserved. New bounds fixture passed1555/0.

Initial VXL job benchmark (before the small-map fast path), exact sync-byte parity:
decode column work482.4ms, setup17.664ms, batch p95=2.002ms, max3.340ms;
native encode work4.392s, batch p95=2.026ms, max23.984ms. Lab encoding work9.145s
and wall31.177s exposed excessive padded-column scans. This measured intermediate
implementation prompted the exact exterior-column fast path; it is not presented
as the final optimization. Log `optimization4-vxl-benchmark-before.log` is retained.

After the fast path, lab work463.068ms/wall2.390s,349 batches, p95=2.024ms,
max2.078ms and exact byte parity; native encode4.502s, p95=2.032ms/max2.380ms;
decode435.366ms, setup20.792ms, p95=2.001ms/max2.005ms. This is a comparison
with the measured intermediate implementation; the unchanged synchronous path
is separately timed in the final benchmark. Hard1024-column caps all passed.

Memory report `memory-cow-item4.json`, **77/0**, records20 compact color/freeze/
resource-generation cycles and2 actual native VXL cycles. Released compact
object/resource counts stayed1490/5; the diagnostic arrays themselves grow,
so their static bytes rose29,325,288→29,604,220 and are not a zero-growth RSS
claim. Both tint caches stay256; generation clearing returns retained materials0.
Logical64MiB snapshots initially share storage. The first live write took
13.397–14.786ms for frozen-copy fixtures and13.623–14.493ms during encoding;
static memory rose by another64MiB while both versions existed. Maximum recorded
engine static memory166,915,557bytes; final27,845,552bytes includes accumulated
diagnostic reports. This exposes a remaining indivisible first-write cost and
does not establish whole-Main/Web/GPU memory plateau.

## Verification and reproduction

Coordinator alone ran the engine. Initial parser/import passed; audio128/0,
environment70/0, new audio-cache46/0, tint bounds1555/0, VXL jobs53/0 and actual
Main VXL lifecycle12/0 passed before the padding refinement. Main load yielded267
UI process frames; reset suppressed unfinished adoption and downloads. Source
parity194/0 and post-mixer Dummy PCM134/0 +environment PCM81/0 passed.
These initial results will be supplemented with final-source checks and browser
evidence below; no unfinished validation is implied to have passed.

From repository root after import, using the pinned console engine:

```powershell
$godot = '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path game --script ../tests/world/test_vxl_jobs.gd
& $godot --headless --path game --script ../tests/world/benchmark_vxl_jobs.gd
& $godot --headless --path game --script ../tests/audio/benchmark_audio_optimization.gd -- --shots=120 --repeats=3 --output-name=audio-item4.json
& $godot --headless --path game --script ../tests/integration/benchmark_optimization_memory.gd -- --full-vxl --vxl-cycles=2 --output-name=memory-cow-item4.json
```

Browser diagnostic export: `python tools/export_optimization_probe.py --name NAME
--source FROZEN_SOURCE --import-cache IMPORT_CACHE`. It preserves production build
and uses actual Main with visible load/save/cancel/input controls and wall-clock
frame sampling, including completion-tail frames. Test scripts remain outside
the normal production entry point. Its frame timings are diagnostic, not a
controlled120-second rendering-performance baseline.

## Exported Main diagnostics

Initial sourceafbd05a game scripts, actual Godot Web Main,1280x720 visible IAB:
Title loading completed55.5547s across877 UI frames;2 input clicks were handled
while private decode ran. Batch setup49.5ms; frame p95=73.7ms/max94.9ms. Saving
was cancelled by reset after1 input click; ERR_SKIP45 and all retained temporary
bytes0, with no download. Reset itself remained expensive (max537.9ms), outside
the VXL column budget. Cache A/B32 queries in the lab: rays1152->36,
ambience CPU84.5ms->2.8ms with31 hits/1miss.

This prompted Main's foreground budget4096 columns/soft8ms for operations
begun with the menu open; live-play starts retain1024/2ms. Frozen source
`eef2225a1dc3bb9dbf2bf80975a3c32ffdf527f4` exported separately under
`.cache/optimization-probe-item4-budget-eef2225/`, preserving production files.
Title loading completed16.4946s across193 UI frames and handled2 clicks;
setup87ms, frame p95=111.4ms/max146.1ms. These single diagnostic runs show the
latency/foreground-work tradeoff and working callbacks, not comparable sustained
rendering FPS or a universal loading speedup. Initial native benchmark overlap
and uncontrolled IAB frame scheduling prevent controlled performance claims.

Machine: Windows10Pro10.0.19045, Intel Core i5-10400H2.60GHz, Intel UHD Graphics;
Codex IAB backend, default1280x720 canvas, visible tab. Browser version/DPR and
process/GPU memory were not available through the read-only browser scope.
Web MEMORY_STATIC returned0 and is treated as unavailable. Console logs and
screenshots: `.cache/previews/optimization-item4/first-web-log.json`,
`first-audio.jpg`, `budget-load.jpg`. Browser operations used actual Buttons,
not direct JavaScript simulation calls. A first tab-create call timed out after
30s but the tab existed and was reused; an attempted navigator read was outside
the supported read-only scope, then console logs supplied the diagnostic data.

The eef2225 diagnostic completed actual Title save in123.1939s/1492 UI frames,
handling2 input clicks, but final synchronous browser staging produced a1901.2ms
frame gap (p95=96ms). Download:2,106,956bytes, SHA256
`6c4cf5de1992b9be2973614aee20b0015122e1244a3df1c2ff43f689e7d6d741`.
Pinned native decode+unchanged synchronous encode confirmed this download is
byte-identical to the established encoder, not merely decodable. The raw Title
file differs because the canonical encoder normalizes unused header colors.
Evidence: `budget-save.jpg`, `budget-web-log-final.json` and
`.cache/logs/optimization4-downloaded-vxl.log`.

This final pause prompted cooperative Main browser staging: at most two16KiB
chunks per batch, soft2ms checked after each complete chunk, with cancellation
and progress notices. JS abort releases pending buffers and object URLs while
preserving pointer capture callbacks; retired dialog close events cannot cancel
a replacement. Node v24.19.0 `node --test tests/browser/test_exports.mjs` passes
3/3 tests using production JS, real Blob bytes and URL lifecycle. Final Blob
creation is timed separately and remains synchronous. Browser verification of
this follow-up used the isolated actual-Main probe with `game/` copied from
`.cache/optimization4-source-774e506bfa81/`, exported to
`.cache/optimization-probe-item4-staging-774e506/`; production build files were
preserved.

Direct staging of the original Title file was cancelled after1 input click:
20 batches staged606,208 of2,106,956bytes, `cancelled=true`, with no download
dialog. Reset still caused an864.3ms frame gap outside the staging budget.
Restarted staging completed in6.7183s (wall including completion tail6.9956s),
with69 UI frames and1 handled input click. Its68 batches had maximum4.1ms;
the soft target is2ms, not a strict limit. Final Blob construction took66.1ms;
frame p95=116.4ms/max165.3ms. The `original-title` download matched the exact
raw input bytes, SHA256
`48fe6c8e9b8287c1aea12e67742362cd7001d72c7bc027b993f7a22982beed62`.

Full actual-Main lab save completed in21.9119s (wall including completion tail
22.1779s), with234 UI frames and1 handled input click. Its67 staging batches
transferred2,112,288bytes, maximum3.9ms; final Blob construction took16.9ms.
Frame p95=112.1ms/max148.2ms. Download `blockfield-map (1).vxl` was confirmed
byte-identical to the unchanged synchronous encoder by pinned native validation,
SHA256 `46c808dee7ca7a514375284df503b1f068a2e4e64053940297c9876af6d0e766`.
Evidence: `.cache/logs/optimization4-downloaded-lab-vxl.log` and
`.cache/previews/optimization-item4/staging-web-log.json`,
`staging-download.jpg`, `staging-save.jpg`.

These diagnostic runs establish yielding, cancellation, handled input and exact
download bytes. They do not establish rendering FPS, a strict2ms batch guarantee,
or a fix for the reset/first-write copy-on-write pause. The earlier slow and failed
attempts above remain evidence of the intermediate implementations.
Final-source parser/import passed; Main lifecycle checks passed15/0. Read-only
simulation review found no blockers. Full behavioral/latency regression, final-source PCM validation
and publication remain pending.

Current exported PCM initially reported113/2 and a repeat113/1: different cases
failed only the old wall-window minimum-frame check, with no overflow and with
finite signal/pan/gain/distance checks passing. Environment PCM initially64/2:
one minimum-frame failure plus missing high-frequency obstruction. The latter
is a separate problem: both clear/blocked early energies were identical, so it
cannot be explained by unequal sample counts. Reports and complete logs are
preserved as `audio-pcm-web-first`, `audio-pcm-web-repeat`, `audio-env-web-first`
under `.cache/previews/optimization-item4/`. They are failed attempts, not Web
PCM acceptance. Sound captures now require the complete `ceil(rate*seconds)`
audio-frame window (stronger than the old60% minimum), bounded by
`seconds+max(2,2*seconds)` wall seconds; silence/disabled capture keep fixed wall
windows. Reports retain actual wall duration, raw captured frames and timeouts.
The DSP fixture freezes service updates, so its single budgeted obstruction query
could return unknown on slow Web rays and retain the clear route. It now runs the
actual production27-ray predicate with128 rays and no fixture preparation time
cap; production remains128 rays/1.5ms and budget tests stay separate. No blocked
answer is injected. Routing/ray/exhaustion diagnostics are recorded. Parser and
native corrected PCM134/0+81/0 passed.

Corrected Web proof on frozen`66e4b5b7eb89956657f97d7f623856080ea117b5`
passed AudioWorklet48kHz PCM113/0 and environmental DSP64/0. All19 sound
windows captured their exact targets with no timeout/overflow; maximum reported
capture wall/audio ratio1.0524. Environment windows also all completed without
timeouts; maximum ratio1.3412. Actual clear obstruction queries used1 ray and
blocked queries27 rays, `blocked_voices=[true]`, without fixture exhaustion.
Measured low/high frequency ratios0.9998247/0.1173766 retain the original DSP
thresholds. Reports/logs: `audio-pcm-web-final.json`, `audio-env-web-final.json`
and corresponding `*-log.json` under `.cache/previews/optimization-item4/`.
No Main/preferences/WAV writes or subjective browser listening acceptance.

Both probes were prepared from this frozen archive under
`.cache/optimization4-source-66e4b5b7eb89/.cache/`, preserving earlier exports.
`git diff --quiet 774e506 66e4b5b -- game` passed: production bytes are identical
to the actual-Main staging/cancel/download proof. This correction changes only
fixtures and documentation. Earlier wall-window failures remain preserved;
the results do not establish controlled mixer throughput versus the old release
or glitch-free subjective audio. Full frozen behavioral/latency checks and
production publication results follow.

## Frozen checkpoint and publication

`python tools/release_checkpoint.py --revision
66e4b5b7eb89956657f97d7f623856080ea117b5 --server` passed import, all85 registered
behavioral/latency invocations, runtime/launcher smoke, Web export, Linux export
and exported-server-PCK smoke. Logs/source: `.cache/release-66e4b5b7eb89/`.
The85 check logs contain no SCRIPT ERROR/Parse Error/ERROR/FAIL diagnostics.
Selected final checks: Main15/0, VXL62/0, materials1555/0, audio cache46/0,
controller511/0, source194/0, mobile2381/0+144/0, socket damage42/0 and native
shaped latency461/0. Manifest `.cache/previews/optimization-item4/frozen-validation.json`.
Headless effects skip3 GPU assertions; actual browser rendering is separate.

Normal frozen export served by `python tools/serve.py --port 8083`: rendered lab,
movement, block palette/tool switching and rifle9/50 after a shot with unlimited
ammo temporarily disabled. That option and rifle were restored. Original Title
loaded through the normal menu with progress, rendered terrain, targets and
minimap. Initial1280x720 browser later resized to619x476 with letterboxed canvas;
checks followed fresh screenshots. No controlled frame-time comparison is claimed.
Evidence: `production-shot.jpg`, `production-title.jpg`, `production-web-log.json`.
Chromium pointer lock still returned UnknownError; the visible drag fallback
worked. No captured Godot parser/script/resource errors; browser errors are not
silently omitted. Reload was requested but not separately measured/accepted.

Source pushed to main. Commands:
`python tools/package_server.py --source .cache/release-66e4b5b7eb89 --destination build/packages`,
`python tools/publish_pages.py`, and
`python tools/publish_server_release.py --package build/packages/blockfield-server-66e4b5b7eb89.zip`.
[Pages](https://gordey328.github.io/Blockfield/) build status built, bundle
`22fd63050e11fad69aa3b421a4e0b8a1c3a0caa7`; public metadata identifies clean66e4b5b.
Independent HTTP hashes match local HTML/JS/WASM/PCK. PCK16,200,448bytes SHA256
`8c54b5408d6f8d0055f9340fc4bd6685937a99af026bf2f8e9a730e13c53d5d8`;
HTML5568bytes SHA256 `96074516bd05e1f45968de943337ce2fa6568d52c15942825439dfe3dd5c8fde`.
Report `.cache/previews/optimization-item4/public-hashes.json`.
[Matching server prerelease](https://github.com/Gordey328/Blockfield/releases/tag/godot-66e4b5b7eb89)
ZIP29,344,396bytes SHA256
`76935d2fc59be4d5af6387266714001292a9c11a5adbf1c276a4e0a7799e168b`;
publication helper independently downloaded and verified it without credentials.
Network5 / authority5-no-block-regen remain; client/server fingerprints are from
the same source. Windows PCK smoke does not establish Linux/Docker execution or
public TLS/WSS. Full-port acceptance and controlled FPS/phone/memory acceptance
remain open; item4 does not remove reset, initial allocation or first-write stalls.

Final public IAB check at619x476: local entry, movement and block/rifle selection
worked, original Title load exposed progress7% and completed with terrain/targets/
minimap rendered. `public-title.jpg` and `public-web-log.json` preserve this check;
only the known Chromium pointer-lock UnknownError was captured. The public game
tab remains as a deliverable. All owned diagnostic/preview HTTP helpers stopped,
temporary tabs closed, no engine process remains. Specialist leases and root
engine/release leases are returned; concurrent mobile work stays separately owned.
