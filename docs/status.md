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
- Latest `python tools/build.py --export`: parser/import, runtime smoke and release export pass; world30/0, VXLsave19/0, falling/water21/0, session65/0, labintegration94/0, presentation504/0, localization76/0, effects3217/0. Real Compatibility GPU previews also check effects and multilingual glyphs. These results do not establish full client parity.
- First public deployment: source `5d367dfafab5524c1f4c572218fb6a0605ec9c42`, bundle commit `128f0059f686f14602ee669de1ba44cb75279b45`. HTTPS menu and entering the local lab with the original shotgun were verified in the in-app browser. Later work below is being exported for the next deployment.

## In progress
- Coordinator: commit this coherent source checkpoint, export from that exact revision, publish and test the updated browser bundle. Integrate forthcoming UI events/settings and graphics options.
- source_audit: preparing full HUD/map/scoreboard/chat/control-binding work; owns `game/ui/`, `tests/ui/`, `docs/ui.md` after checkpoint.
- voxel: preparing source-based ambient occlusion and lit voxel material, draw-distance/toggle APIs; owns world files/tests/docs after checkpoint.
- assets: effects/localization/model work complete and frozen for checkpoint; next ownership will be assigned explicitly.

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

Full original UI/rendering/audio/extensions and browser acceptance remain unfinished. The embedded browser rejected pointer lock at localhost with a Chromium UnknownError, so complete mouse capture/audio acceptance still needs evidence; menu and keyboard checks alone do not satisfy B03. Treat published exports as development builds.

## Local commands and ownership
Python: `C:\Users\Gordey\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
`python tools/bootstrap.py`; `python tools/build.py --export`; `python tools/serve.py`; `python tools/publish_pages.py`.
Logs: ignored `.cache/logs/`. Source reference: ignored `.cache/openspades`.
Root owns main/gameplay/project/build/release/checkpoint docs. source_audit owns UI/UI tests/UI doc; voxel owns world/world tests/voxel doc. assets' importer/assets/presentation changes are frozen pending next assignment. Shared files require a handoff before edits. Agents prepare read-only until the coordinator records the snapshot.
