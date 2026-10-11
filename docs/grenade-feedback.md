# Grenade distance feedback

2026-10-11. Engine Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility;
upstream `dcf449c845d509bbde9d79239b32d201c1389961`.

The user requested quieter, weaker distant explosions. Two read-only specialists
audited camera and audio; neither edited files or ran the engine. Root owns
`game/presentation/grenade_feedback.gd`, Effects/Audio, their fixtures, this evidence,
ADR0019 and integration. Mobile Fire/look, optimization advisory and Steam AoS
research remain separately owned. Root runs serial engine validation; diagnostics
use isolated frozen copies and never replace another chat's import cache.

Native shake/audio saturation, selected range and collapse confounder are explained
in [ADR0019](decisions/0019-grenade-feedback-range.md). At32 units, deterministic
maximum grenade roll falls from17.65degrees to.967degrees, before elapsed decay.
Audio additionally attenuates every land/water layer and both room branches.

## Native validation

Frozen `d8e5ddb09d0ff63917d3312a758a2f9f4c584430` includes all-item Fire/look
commits4833050/6d61ea9. Its isolated archive is `.cache/grenade-release-d8e5ddb09d0f`.
Bundled Python is
`C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`;
engine `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.

Reproduction: archive that revision with `git archive`, extract into a fresh
directory, seed `.godot` from the workspace, then run `--headless --path <copy>/game
--editor --import --quit`. Run each fixture below with `--script <copy>/<path>`;
lab/mobile fixtures additionally use `--fixed-fps 60`. The local orchestration is
`.cache/freeze_grenade.py`; exact engine outputs are in the frozen `.cache/logs/`.

| Fixture | Frozen result |
| --- | --- |
| tests/presentation/test_effects.gd | 32601/0, three explicit headless GPU readback skips |
| tests/audio/test_audio.gd | 158/0 |
| tests/audio/render_grenade_feedback.gd | 43/0, real post-limiter Dummy44.1kHz PCM |
| tests/audio/test_environment.gd | 76/0 |
| tests/presentation/test_camera_effects.gd | 45/0 |
| tests/presentation/test_impact_fragment_updates.gd | 44/0 |
| tests/integration/test_lab.gd | 119/0 |
| tests/gameplay/test_grenade.gd | 17/0 |
| tests/ui/test_mobile_controls.gd | 3099/0 |
| tests/integration/test_mobile_look.gd | 226/0 |

Every blast capture has132300 stereo mixer frames, finite values, nonzero energy
and no ring overflow. Frozen raw RMS32/5 and80/5 ratios are.159585/.026353 land,
.163969/.026039 water. The initial workspace run was.142521/.023535 land and
.058969/.009367 water. Mixer scheduling affects the3s window, so these are retained
as separate captures; both pass the independent40%/10% amplitude bounds. Review
WAV scale is identical.95, while reported RMS/energy is unnormalized. Reports:
`<frozen>/.cache/previews/grenade-feedback/dummy/report.json` and the workspace
`.cache/previews/grenade-feedback/dummy/report.json`. Dummy PCM is mathematical
output proof, not physical-device listening acceptance.

Runtime120-frame smoke and normal Web export pass on the same frozen source.
These are ten affected behavioral/mixer fixtures, not a rerun of all89 previous
network/world/latency invocations. No server rules/export changed.

## Actual exported browser

`python tools/export_grenade_probe.py --source .cache/grenade-release-d8e5ddb09d0f
--name d8e5ddb --import-cache .cache/grenade-release-d8e5ddb09d0f/game/.godot`
passes its own parser/import and Web export. Serve the frozen normal export on
18084 and `.cache/grenade-probe-d8e5ddb/build/web` on18085 with
`python -m http.server <port> --bind 127.0.0.1 --directory <folder>`.

Normal exported game renders grenade selection/lab entry, a300ms primary throw
and its permanent front ledge crater. Actual-Main probe clicks5/32/80 produce
five sound layers and58 particles each. Gesture-activated Web Stream captures
144000 finite stereo frames at48kHz per blast, with zero overflow. Raw amplitude
32/5 is.142805,80/5 .023605. Camera accumulators at32 are.006664/.033321 and
at80 .000518/.002589, compared with close.170414/.4. Real smoke/fragments were
visible in the close case; normal camera input and source size remain present.
Browser report: `.cache/grenade-web-feedback.json`; tool screenshots show the
normal lab/crater, close particles and final80-unit report.

Initial DOM-only probe click ran with suspended browser audio, correctly yielding
zero frames/pass=false. Click the game canvas once to activate audio before the
DOM distance controls; the repeat and both farther cases pass. This is a gesture
requirement, not accepted silent playback. Both normal/probe console logs contain
only the existing host pointer-lock Chromium UnknownError, with no engine/script
warning or error. Cold normal startup also caused two CDP focus timeouts while
WASM compiled; re-binding the same loaded tab succeeded without another mechanism.
Physical listening/device feel and broader U11/U12 acceptance remain open.

## Publication

Source d8e5ddb09d0ff63917d3312a758a2f9f4c584430 is pushed to main. Normal
development build: https://gordey328.github.io/Blockfield/. Pages bundle
`2f786bedd3e1c33c41010f382b05b7b37e476ff0` reports built/no error.
Independent downloads of metadata, HTML/JS/WASM/PCK and both audio worklets match
the frozen export byte-for-byte. PCK23751916bytes, SHA256
`2b9f1d81c4190fce199a805f58eb89ad91cb2b6daaaeba252dd37b45168ea71c`;
HTML7092bytes, SHA256
`99f3debfa2f144aa1e234492f8a9f25eeb86c76b86a4831908d56fd4d141a5a4`.
Full hash/Pages report: `.cache/grenade-public-verification.json`.

Public normal menu/lab/grenade rendering, Fire-drag camera turning while holding
the grenade, and300ms Fire are exercised with no captured warnings/errors.
The direct public play check is not an instrumented distance measurement; those
results belong to the exact-source local Web probe above. Existing Title/mobile/
startup changes are included. Compatible server is unchanged; ten targeted
fixtures do not claim full89-suite/Linux/server/device acceptance.

The release uses an isolated `.cache/grenade-pages-d8e5ddb/build/web` checkout;
`publish_pages.ROOT` points to its parent, preserving the normal helper. Clone
without noninteractive credential settings stalled; its exact process tree was
stopped and the diagnostic preserved. Copying the existing published `.git`, then
fetching with GIT_TERMINAL_PROMPT0/GCM_INTERACTIVEnever succeeds without printing
credentials. Frozen files are recopied and hashes checked before publication.
The shared normal `build/web` checkout subsequently fast-forwards to this exact
bundle. Source/Python scripts and scoped Git diff checks pass. Both owned HTTP
helpers are stopped at cleanup; no specialists or engine/release leases remain.
