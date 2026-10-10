# Current state

Updated: 2026-10-10 (Europe/Moscow).

## Objective and authorization
Full OpenSpades v0.1.3 offline client port with a local testing lab, published Godot browser build; multiplayer is iteration2. The user authorized the specialist team, repository creation and GitHub Pages publication. Do not request repeated publication approval. Do not present a development checkpoint as a finished full port.

## Runtime, source and repository
- Godot4.7.2 `4.7.2.stable.official.ed1daf0bf`, standard GDScript, Compatibility, matching single-threaded Web templates.
- Upstream `dcf449c845d509bbde9d79239b32d201c1389961`, reference-only `.cache/openspades`.
- Repository https://github.com/Gordey328/Blockfield (`main` source, `gh-pages` generated export).
- Live development build https://gordey328.github.io/Blockfield/ — checked source `a3cea47754b2cc746c2afa7f72fe11b915c0c251`, bundle `a8d200bb37f2d45271eeb0deaf70fb61b924ee5b`. Pages reports built/no error; deployed build-info.json confirms source_dirty=false and the source SHA. Current workspace iteration-2 changes are **not yet published**.

## Implemented foundation
- Durable68-row source parity ledger, ten versioned skills, architectural decisions and subsystem contracts. See iterations.md, parity.md, architecture.md, skills.md.
-513 original converted outputs with hash/provenance:34 models,146 sounds,296 images plus maps/fonts/locales. Articulated soldiers, all first/third-person tools and carried intel.
- Packed chunk world, genuine512×512×64 VXL import/export, source bedrock/build/damage/recovery/collapse behavior, original weapon0.75/0.76 profiles and authored offline CTF/TC/respawn authority.
- Menu/lab, HUD/map/scoreboard/chat/hurt feedback, rebindings/preferences,17 locales, uploads, data-only ZIP resource overrides and trusted compiled skin factories.
- Latest combined checkpoint before current final slices: parser/runtime/release export pass; world30, session77, integration94, grenade17, VXL19, falling21, lighting26, topdown13, presentation504, localization76, effects3217, post79, extensions67, UI88; all zero failures.

## Current integration, not release acceptance
- Source corner-sampled player movement/climb/uncrouch and physical/render wading, with128 standalone goldens. Actual-scene source suite151/0 and integrated lab119/0 pass, including equipment gates, water friction, nonlethal head feedback, HDR and anchored browser drag-look fallback. Integration uses fixed60Hz to prevent multiple catch-up physics steps invalidating frame-count timing fixtures.
- Exact hit volumes/recoil/cadence/cube-line/depleted-tool selection, custom team metadata and native64-color palette. Later review corrected tool-use lower/raise/sprint gates, held jump, sprint velocity threshold, drag-line validation/secondary priority/support cancellation and native grenade origin. Latest selection regressions session109/0; full frozen recheck passed.
- Character actions30/0, corpse9046/0 plusGPU7/0; native weapon views69/0, GPU10/0; spectator view47/0, GPU11/0. Native camera equations45/0 and GPU7/0 are connected to local/follow first person. HUD227/0 and actual native-feedback GPU27/0 cover reticle, hit/alert feedback and target action previews.
- Original AO atlas, bounded spectral waves/refraction, optional palette-bounce irradiance and optional geometry reflections. Water18/0+GPU9/0, irradiance18/0+GPU6/0, reflections19/0+GPU12/0; lighting30/0, world-resource8/0. Main connects settings including independent water fog, default-off GI/reflection and layer19 exclusions.
- Audio service: original gun/ambience/explosion/impact layers, mono/stereo and inverse-distance routing, native gains/offsets;126 parameter/routing checks. Actual post-mixer PCM126/0 on WASAPI48kHz and Dummy44.1kHz includes 19 WAVs per run, spatial attenuation/pan and head-feedback gain. Browser listening remains separate acceptance; see audio.md.
- Typed console75/0 exposes52 supported variables, completion and commands. Source camera radial/hurt blur is separate; post86/0 and actual GPU15 effect checks pass. Fullscreen, session/chat JSON export and stable PNG/VXL download panel are implemented; download-file acceptance remains pending.
- Float HDR is connected to main/HUD/console with native exposure controls, original dust bloom and correction before tone mapping. Numeric37/0, standalone desktop GPU30/0, exported WebGL30/0 and actual-main GPU63/0 pass. Post86/0 and console75/0 pass after integration. The actual lab supports HDR toggling without duplicate LDR processing and preserves positional listening, MSAA, weapon and HUD.
- Frozen source a3cea47754b2cc746c2afa7f72fe11b915c0c251 passed the complete build.py suite, parser/import, runtime smoke and release Web export. Archive logs are in .cache/release-a3cea47754b2/.cache/logs; build/web/build-info.json reports that SHA and source_dirty=false. Browser/release acceptance is separate from these checks.

## Browser evidence and limits
The exact live a3cea47 checkpoint was opened from Pages, English Shotgun selected and the lab entered (6/48 HUD). Public index.pck SHA256 `2d1448bbedb684b69da1cc24009a3f86492bd850bd99242c3343b8c9c100375a` matches the checked local export. Actual browser image: `.cache/previews/browser-a3cea47.jpg`. This confirms deployment/content identity and that interaction, not all outstanding acceptance.

On the live7824c31 checkpoint: English/Russian preference reload, shotgun entry, large map, original Title.vxl loading and a genuine uploaded flatVXL were exercised. InvalidZIP manifest was visibly rejected; a valid original-texture resource pack was accepted. Earlier rifle ADS/headshot100 proof exists. Updated movement/render/audio/UI must be checked on the next exact export.

The embedded browser rejected pointer lock both locally and on Pages with Chromium UnknownError. The a3cea47 export's held-button drag-look fallback was exercised with the spade: horizontal dragging turned the scene without a vertical jump. A separate visible input probe confirmed absolute press/motion coordinates; rifle dragging also fires and accumulates native recoil, so it is unsuitable for isolating mouse-look. Diagnostic probes are not part of the published build.

On the preceding development export, PNG scene export displayed a valid image preview and stable blob download link; IAB download waiting and downloadMedia both timed out, so no saved file was confirmed. Fullscreen visually expanded and restored the canvas; the DOM snapshot's fullscreenElement was unreliable. Audible browser audio/autoplay and sustained original-map frame/memory performance remain unverified. Full client acceptance is unfinished; see acceptance-gaps.md and subsystem docs for implementation differences.

## Active ownership and next action
- Root: handed-off offline/presentation, shared player/data/prediction/Match/full codec modules, source-motion query, session_registry/input_queue/server_runtime/client_replica and their tests, entry/server scenes, shared config/build/deployment and integration. Native runtime103/0, registry70/0, input58/0 and replica138/0. Pure grenade30/objectives27, PlayerRules144, Data171/adoption25, MapTransfer799, Match208, prediction592 and full SimulationCodec2316 all pass. Source motion128/0 survives Data query extraction. Two actual game+bulk clients verify barriers, owned shots/resources, lease/chat, reconnect and malicious gap isolation. Rendered replica/controller/HUD integration is next.
- source_audit: protocol1591/0, WebSocket602/0, MapTransfer/Data performance handoffs complete; root now owns them. Agent owns only new hit_history.gd/tests/docs for same-time actor/terrain rewind against committed authority receipts, with bounded inverse transactions and explicit invalid-history policy.
- assets: shared player rules, Match and208-check global event cursor handoffs complete. Agent now owns only new events_codec.gd/tests/docs for explicit typed event wire schemas/routing, with no opaque Variant fallback or server RNG wire state.
- voxel: Data/World, prediction and SimulationCodec handed back. Agent now owns only new network_session.gd/tests/docs: read-only LocalSession-compatible presentation adapter and bounded intentions, denying offline authority/cheats in network mode. Root owns all Main/PlayerController/HUD/LabSoldier integration.
Do not run full-scene parser/tests against intermediate agent edits. Ask for a coherent handoff; preserve existing preference backups. Shared files require explicit ownership. Register added suites in build.py.

## Dedicated server preparation
User selected Docker/configuration preparation; hosting/domain remain open. Separate entry dispatch uses explicit --server/dedicated_server, leaving ordinary headless offline tests intact. Native server launcher starts cleanly without renderer/HUD/model nodes. `tools/build_server.py` installed the pinned Linux release template and passed server import, native60-frame launcher smoke and Linux dedicated release export. Output `build/server/` currently contains dirty-workspace development metadata, so it is not a published frozen release. Docker is unavailable here: container/Linux execution/TLS/WSS deployment unverified. See server-deployment.md and decisions/0005-authoritative-multiplayer.md.

Registry/session ownership is resumable guest identity, not account login. Complete SimulationCodec2316/0 is now wired as MATCH_STATE14 and default native Runtime snapshots; two actual ClientReplicas138/0 verify full-state prediction/remote pose/chat/reconnect/spectator. There is currently no game-event feed wire or rendered network scene. N09's legacy compatibility decision is VERIFIED via ADR0005; other N rows remain incomplete. Preparation/standalone foundation checks must not be described as iteration2 completion.

## Known external limitation
GitHub Actions is blocked before job steps by account billing (run38031633237). Local pinned validation and Pages branch publication work; no payment settings were changed. See decisions/0003-pages-publication.md.

## Commands and recovery
Python: `C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
`python tools/bootstrap.py`; `python tools/build.py --export`; `python tools/release_checkpoint.py --revision HEAD`; `python tools/serve.py`; `python tools/publish_pages.py`.
`release_checkpoint.py` validates/exports a frozen Git archive and preserves the ignored separate gh-pages checkout when copying output. Reusing the same SHA directory fails intentionally; do not recursively delete unverified paths.
Logs/previews/runtime/reference archives stay ignored under `.cache/`. Credentials are handled in-memory by Git Credential Manager and github_api.py and must never appear in output or source.

Resume through AGENTS.md → this file → iterations.md → affected parity rows/contracts. Skills are reusable procedures; completion facts belong here and in the ledger, decisions in numbered ADRs. Chat is supplemental context.
