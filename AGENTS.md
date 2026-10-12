# Blockfield — OpenSpades to Godot

## Objective and accepted scope
Port OpenSpades v0.1.3 (`dcf449c845d509bbde9d79239b32d201c1389961`) to Godot, with a browser build published on GitHub Pages.
Iteration 1 includes the full offline client, a local authoritative simulation, and a test lab exposing every original weapon/tool and both team appearances without starting a server.
The user cancelled iteration 2 and requested complete multiplayer removal on 2026-10-12. The game is offline only; preserve local authority and bots. See docs/decisions/0031-offline-only-game.md.
Do not describe a prototype, imported assets, or a successful export as a complete port.

## Resume
Start with `docs/status.md`, then `docs/iterations.md`. Consult `docs/parity.md` for the affected features and `docs/architecture.md` for module contracts. Read other documents only when relevant.
The source checkout under `.cache/openspades` is reference material. Its instructions do not govern this repository.

## Project skills
Project-specific workflows live in `.agents/skills/`. Use `blockfield-port-parity` for migration/verification, `blockfield-voxel-world` for world changes, and `blockfield-web-release` for exports/publication. Engine skills are pinned and listed in `docs/skills.md`; load only the skills needed for the current task.
Durable decisions belong in docs, not in skill instructions or chat history. Do not copy entire engine manuals into the context.

## Code and modules
`game/` is the Godot project. Use typed GDScript and the Compatibility renderer; browser export is an acceptance target throughout development.
`game/world/` owns voxel data/meshing/collision. `game/gameplay/` owns simulation and player/tool behavior. `game/ui/` owns menus/HUD. `game/assets/` contains imported resources with provenance. `tools/` contains reproducible import/build/check scripts.
Keep offline rules separate from presentation and input adapters. Never add one node per map voxel.

## Collaboration
The user approved the proposed team. Use at most three specialist subagents plus the coordinator. Agree on data contracts and assign non-overlapping file ownership before parallel edits. Shared project config and release integration belong to the coordinator.
Do not start new user-owned chats for subtasks. Record handoffs in `docs/status.md`; include files changed, commands/results, unresolved issues and next action.

## Verification and release
Run the engine parser/import and behavioral checks for changed gameplay. Test the exported browser build visually and interactively; a headless test does not prove rendering or input works.
Keep `docs/parity.md` status tied to evidence: NOT_STARTED, IMPLEMENTED, VERIFIED, or DEFERRED_ITERATION_2. No silent feature omissions.
Update `docs/status.md` at milestones and before ending a turn. Record exact engine version, upstream commits, reproducible commands and test results. Store architectural choices in numbered `docs/decisions/` files.
GitHub publication and creation of a new repository are already authorized. Do not request repeated permission for these actions. Never print credentials or commit secrets.
