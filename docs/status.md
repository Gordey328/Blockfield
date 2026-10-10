# Current state

Updated: 2026-10-10 (Europe/Moscow).

## Objective
Iteration 1: complete offline OpenSpades client port + local test lab + GitHub Pages build. Iteration 2: multiplayer. See iterations.md and parity.md for acceptance.

## Completed
- Inspected upstream structure and pinned OpenSpades v0.1.3 at dcf449c845d509bbde9d79239b32d201c1389961.
- Created durable documentation, 68-row parity ledger and nine project skills. Three project-owned skills pass skill-creator validation; six engine skills are pinned to GodotPrompter commit in skills.md.
- Created public repository https://github.com/Gordey328/Blockfield. The development build is live at https://gordey328.github.io/Blockfield/. Source is on `main`; generated files are on `gh-pages`.
- Executed Godot 4.7.2 `4.7.2.stable.official.ed1daf0bf`; matching single-threaded Web templates installed.
- Imported 513 original asset outputs (34 models, 146 sounds, 296 PNG images, catalogs/fonts/maps) with checksums/provenance. Models include first/third-person item views, articulated soldiers and carried intel. TGA orientation matches the original decoder; original Unifont supplies multilingual glyphs.
- Implemented VXL import/save, packed chunk world/collision, edits/support collapse, original weapon profiles and local session, offline lab/menu/HUD.
- Added source-based movement/input/cameras, water, grouped falling clusters, presentation effects and 17 selectable locales. Source differences and browser adaptations are recorded in subsystem documents.
- Latest validation: parser/import, runtime smoke and release export pass; world30/0, VXLsave19/0, falling/water21/0, session77/0, labintegration94/0, grenade17/0, lighting26/0, topdown13/0, presentation504/0, localization76/0, effects3217/0, post79/0, extensions67/0, UI88/0. Real Compatibility GPU previews also check UI, lights, shadows, effects and multilingual glyphs. These results do not establish full client parity.
- Latest checked public deployment: source `9f876bb2a27bad24f64899cff7bf61c52fe739c0`, bundle `09793333b69d5efa1a2a76cae704e292c30aee78`; Pages reports built/no error. Browser checks: Russian/English locale switch, lab entry, rifle ADS, headshot100 and original Title.vxl load. Mouse capture and downloads remain unverified. Expanded UI/lighting/post/resource-pack work is frozen for the next exact-revision export.
- Added HUD/map/scoreboard/chat, hurt feedback, bindings/settings, source grenade physics, map upload/reset, screenshots, flashlight, configurable graphics and validated data-only ZIP resource overrides. See ui.md, extensions.md, assets.md and voxel.md for contracts and differences.

## In progress
- Coordinator: exact-revision export/publication/browser acceptance; owns main/gameplay/UI integration and release docs/tools.
- source_audit: read-only P01–P16/W03–W07/M01–M04/T02–T05 audit; after checkpoint owns source-audit.md and new gameplay parity tests. UI handoff is complete.
- voxel: source atlas AO, spectral water/refraction and optional bounded palette-bounce GI; owns world/world tests/voxel.md after checkpoint.
- assets: source soldier/tool animations and corpse physics; owns character_view/new corpse implementation/presentation tests/assets.md after checkpoint.

## Decisions / assumptions
- Browser is primary. Desktop execution is a development check.
- Upstream has rifle, SMG, shotgun and spade/block/grenade tools; two team-colored soldier appearances plus spectator, not a roster of heroes.
- Upstream is a client. Offline damage, round rules and respawn need a new local authoritative simulation.
- Engine: Godot 4.7.2 standard, GDScript, Compatibility, single-threaded Web. See decisions/0001-browser-engine.md.
- Offline rules separate source constants from newly authored authority. See decisions/0002-offline-authority.md.

## Next action
Publish the next checked development build, then complete missing original client UI, graphics, audio and extension contracts. Update row evidence as features pass their own acceptance. Do not mark iteration complete until the parity matrix and browser deployment pass.

## Known blockers
GitHub Actions is blocked before job steps by an account billing condition (run 38031633237); local validation and Pages branch publication work. See decisions/0003-pages-publication.md. No payment settings were changed.

Full client parity and browser acceptance remain unfinished. Corpse physics, some third-person tool actions, native renderer fidelity and source audio mixing need further work. The embedded browser rejected pointer lock both locally and on Pages with a Chromium UnknownError; download waiting timed out. Complete mouse capture/audio/download acceptance still needs evidence. Treat published exports as development builds.

## Local commands and ownership
Python: `C:\Users\Gordey\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
`python tools/bootstrap.py`; `python tools/build.py --export`; `python tools/release_checkpoint.py --revision HEAD`; `python tools/serve.py`; `python tools/publish_pages.py`.
Logs: ignored `.cache/logs/`. Source reference: ignored `.cache/openspades`.
Shared files require a handoff before edits. Agents prepare read-only until the coordinator records the snapshot; release_checkpoint.py exports a Git archive so subsequent workspace edits cannot contaminate the release.
