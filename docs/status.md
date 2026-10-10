# Current state

Updated: 2026-10-10 (Europe/Moscow).

## Objective and authorization
Full OpenSpades v0.1.3 offline client port with a local testing lab, published Godot browser build; multiplayer is iteration2. The user authorized the specialist team, repository creation and GitHub Pages publication. Do not request repeated publication approval. Do not present a development checkpoint as a finished full port.

## Runtime, source and repository
- Godot4.7.2 `4.7.2.stable.official.ed1daf0bf`, standard GDScript, Compatibility, matching single-threaded Web templates.
- Upstream `dcf449c845d509bbde9d79239b32d201c1389961`, reference-only `.cache/openspades`.
- Repository https://github.com/Gordey328/Blockfield (`main` source, `gh-pages` generated export).
- Live development build https://gordey328.github.io/Blockfield/ — checked source `7824c31f8cae829f65d8d98d11e46d63d2adb648`, bundle `d702bd6446009a40f38091b3b6df9e10e5cb77f0`. Pages reports built/no error. Current workspace changes after that commit are **not yet published**.

## Implemented foundation
- Durable68-row source parity ledger, nine versioned skills, architectural decisions and subsystem contracts. See iterations.md, parity.md, architecture.md, skills.md.
-513 original converted outputs with hash/provenance:34 models,146 sounds,296 images plus maps/fonts/locales. Articulated soldiers, all first/third-person tools and carried intel.
- Packed chunk world, genuine512×512×64 VXL import/export, source bedrock/build/damage/recovery/collapse behavior, original weapon0.75/0.76 profiles and authored offline CTF/TC/respawn authority.
- Menu/lab, HUD/map/scoreboard/chat/hurt feedback, rebindings/preferences,17 locales, uploads, data-only ZIP resource overrides and trusted compiled skin factories.
- Latest combined checkpoint before current final slices: parser/runtime/release export pass; world30, session77, integration94, grenade17, VXL19, falling21, lighting26, topdown13, presentation504, localization76, effects3217, post79, extensions67, UI88; all zero failures.

## Current integration, not release acceptance
- Source corner-sampled player movement/climb/uncrouch and physical/render wading, with128 standalone goldens. Actual-scene source suite151/0 and integrated lab119/0 pass, including equipment gates, water friction, nonlethal head feedback, HDR and anchored browser drag-look fallback. Integration uses fixed60Hz to prevent multiple catch-up physics steps invalidating frame-count timing fixtures.
- Exact hit volumes/recoil/cadence/cube-line/depleted-tool selection, custom team metadata and native64-color palette. Later review corrected tool-use lower/raise/sprint gates, held jump, sprint velocity threshold, drag-line validation/secondary priority/support cancellation and native grenade origin. Latest selection regressions session109/0; combined recheck pending.
- Character actions30/0, corpse9046/0 plusGPU7/0; native weapon views69/0, GPU10/0; spectator view47/0, GPU11/0. Native camera equations45/0 and GPU7/0 are connected to local/follow first person. HUD227/0 and actual native-feedback GPU27/0 cover reticle, hit/alert feedback and target action previews.
- Original AO atlas, bounded spectral waves/refraction, optional palette-bounce irradiance and optional geometry reflections. Water18/0+GPU9/0, irradiance18/0+GPU6/0, reflections19/0+GPU12/0; lighting30/0, world-resource8/0. Main connects settings including independent water fog, default-off GI/reflection and layer19 exclusions.
- Audio service: original gun/ambience/explosion/impact layers, mono/stereo and inverse-distance routing, native gains/offsets;126 parameter/routing checks. Actual post-mixer PCM126/0 on WASAPI48kHz and Dummy44.1kHz includes 19 WAVs per run, spatial attenuation/pan and head-feedback gain. Browser listening remains separate acceptance; see audio.md.
- Typed console71/0 exposes48 supported variables, completion and commands. Source camera radial/hurt blur is separate; post82/0 and actual GPU15 effect checks pass. Fullscreen, session/chat JSON export and stable PNG/VXL download panel are implemented; current exported QA pending.
- Float HDR is connected to main/HUD/console with native exposure controls, original dust bloom and correction before tone mapping. Numeric37/0, standalone desktop GPU30/0, exported WebGL30/0 and actual-main GPU63/0 pass. Post86/0 and console75/0 pass after integration. The actual lab supports HDR toggling without duplicate LDR processing and preserves positional listening, MSAA, weapon and HUD. Full regression/final browser acceptance are pending.

## Browser evidence and limits
On the live7824c31 checkpoint: English/Russian preference reload, shotgun entry, large map, original Title.vxl loading and a genuine uploaded flatVXL were exercised. InvalidZIP manifest was visibly rejected; a valid original-texture resource pack was accepted. Earlier rifle ADS/headshot100 proof exists. Updated movement/render/audio/UI must be checked on the next exact export.

The embedded browser rejected pointer lock both locally and on Pages with Chromium UnknownError. A held-button drag-look fallback is now implemented and integration-tested, but awaits exported interaction. Async download waiting timed out; new stable links remain to be exercised. Audible audio/autoplay, fullscreen and sustained original-map frame/memory performance remain unverified. Full client acceptance is unfinished; see acceptance-gaps.md and subsystem docs for implementation differences.

## Active ownership and next action
- Root: main/controller/audio, all handed-off HUD/console/camera files, release tools and status/parity. Connect HDR helper contracts, run coherent full validation, commit/push, frozen Git-archive export, publish and verify browser revision.
- source_audit: multiplayer plan/validated skill and binary protocol handed off. Protocol1591/0 and parser clean;13 explicit bounded message families are documented in network-protocol.md. No sockets/auth/server/state assembly yet; N rows remain incomplete. No active ownership.
- assets: HUD227/0, feedback GPU27/0, PCM126/0 each mixer and actual-main HDR63/0 handed off. Idle; root owns those files. Original preferences restored after tests.
- voxel: HDR37/0+GPU30/0+WebGL30/0 handoff completed; no active file ownership.
Do not run full-scene parser/tests against intermediate agent edits. Ask for a coherent handoff; preserve existing preference backups. Shared files require explicit ownership. Register added suites in build.py.

## Known external limitation
GitHub Actions is blocked before job steps by account billing (run38031633237). Local pinned validation and Pages branch publication work; no payment settings were changed. See decisions/0003-pages-publication.md.

## Commands and recovery
Python: `C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
`python tools/bootstrap.py`; `python tools/build.py --export`; `python tools/release_checkpoint.py --revision HEAD`; `python tools/serve.py`; `python tools/publish_pages.py`.
`release_checkpoint.py` validates/exports a frozen Git archive and preserves the ignored separate gh-pages checkout when copying output. Reusing the same SHA directory fails intentionally; do not recursively delete unverified paths.
Logs/previews/runtime/reference archives stay ignored under `.cache/`. Credentials are handled in-memory by Git Credential Manager and github_api.py and must never appear in output or source.

Resume through AGENTS.md → this file → iterations.md → affected parity rows/contracts. Skills are reusable procedures; completion facts belong here and in the ledger, decisions in numbered ADRs. Chat is supplemental context.
