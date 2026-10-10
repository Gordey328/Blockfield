# Current state

Updated: 2026-10-10 (Europe/Moscow).

## Objective
Iteration 1: complete offline OpenSpades client port + local test lab + GitHub Pages build. Iteration 2: multiplayer. See iterations.md and parity.md for acceptance.

## Completed
- Inspected upstream structure and pinned OpenSpades v0.1.3 at dcf449c845d509bbde9d79239b32d201c1389961.
- Created durable documentation, 68-row parity ledger and nine project skills. Three project-owned skills pass skill-creator validation; six engine skills are pinned to GodotPrompter commit in skills.md.
- Created public repository https://github.com/Gordey328/Blockfield and configured Pages workflow hosting at https://gordey328.github.io/Blockfield/. Publication is authorized. No source push or deployment yet at this checkpoint.
- Executed Godot 4.7.2 `4.7.2.stable.official.ed1daf0bf`; matching single-threaded Web templates installed.
- Imported 511 original asset outputs including localization catalogs, with checksums/provenance; models assembled into first/third-person views and original reload/ADS/tool animations.
- Implemented VXL import/save, packed chunk world/collision, edits/support collapse, original weapon profiles and local session, offline lab/menu/HUD.
- Behavioral checks: world30/0, VXLsave19/0, session65/0, labintegration55/0, presentation504/0. Parser/import and runtime smoke pass. Browser verification remains pending. See subsystem documents for exact coverage; these results do not establish full client parity.

## In progress
- Initial web export: audio teardown leaks and material lifetime errors fixed. Export requires specifically named web_nothreads templates; bootstrap corrected and template download in progress.
- Additional movement/input/camera behaviors (source_audit); localization catalogs and presentation effects (assets); falling cluster visuals and water (voxel). These tasks are paused for a coherent initial export checkpoint.
- Browser playtest, initial source commit/push and Pages verification (coordinator).

## Decisions / assumptions
- Browser is primary. Desktop execution is a development check.
- Upstream has rifle, SMG, shotgun and spade/block/grenade tools; two team-colored soldier appearances plus spectator, not a roster of heroes.
- Upstream is a client. Offline damage, round rules and respawn need a new local authoritative simulation.
- Engine: Godot 4.7.2 standard, GDScript, Compatibility, single-threaded Web. See decisions/0001-browser-engine.md.
- Offline rules separate source constants from newly authored authority. See decisions/0002-offline-authority.md.

## Next action
Complete single-threaded template download, export, serve via tools/serve.py at localhost:8060, playtest exported browser build, push main and verify Pages. Resume the next subsystem tasks after the initial source commit. Do not mark iteration complete until the parity matrix and Pages deployment pass.

## Known blockers
No external blocker. Full original UI/effects/rendering/extensions and browser acceptance remain unfinished. Treat the first deployment as a development build.

## Local commands and ownership
Python: `C:\Users\Gordey\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
`python tools/bootstrap.py`; `python tools/build.py --export`; `python tools/serve.py`.
Logs: ignored `.cache/logs/`. Source reference: ignored `.cache/openspades`.
Root owns main/HUD/project/build/release/docs checkpoint; source_audit owns controller/session/integration tests; assets owns importer/assets/presentation; voxel owns world/world tests. Shared files require a handoff before edits.
