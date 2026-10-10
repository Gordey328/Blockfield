# Skill organization

Project skills live in `.agents/skills/` so they travel with the repository. Each entry point stays short. References hold detailed formats/contracts only when needed.

## Project-owned
- blockfield-port-parity: source audit, migration status and evidence.
- blockfield-voxel-world: chunk/VXL invariants and world verification.
- blockfield-web-release: reproducible Godot export and GitHub Pages checks.
- blockfield-multiplayer: shared authority, WSS protocol, prediction, map joins and multiplayer verification. Read docs/multiplayer-plan.md for the proposed design; the skill passed the system creator's quick_validate.py using existing isolated PyYAML dependencies.

## Engine knowledge
Candidate source: https://github.com/jame581/GodotPrompter at commit 1e7d79d3cbbd6fd8016cd9cc77c6a79f342ea218 (queried 2026-10-10).
Install selected skills with the standard skill installer into `.agents/skills/`; do not install its entire plugin, hooks or duplicate agent configuration. Record installed directories and source hashes below. Confirm examples against the pinned executable; third-party instructions may contain incorrect version-specific advice.

Priority: gdscript-patterns, godot-project-setup, 3d-essentials, godot-optimization, godot-testing, export-pipeline. Add player-controller/input-handling/physics-system, assets-pipeline, shader-basics, audio-system and UI skills as their tasks begin. Network skills are for iteration 2.

Installed 2026-10-10 using the standard skill-installer into this repository:
`gdscript-patterns`, `godot-project-setup`, `3d-essentials`, `godot-optimization`,
`godot-testing`, `export-pipeline`, all from the pinned commit above. The three
original project-owned skills are authored here and versioned with the game. The multiplayer workflow adds a fourth project-owned skill (ten total).

Read only the relevant SKILL.md and its requested references. Skills explain
repeatable workflows; they are not a place to store current completion claims.
Third-party advice is subordinate to this project's contract and actual engine
behavior (for example Godot's `--quit-after` counts frames, not milliseconds).

## Context recovery
At each milestone update status and affected parity rows. At a handoff record commands/results and unresolved behavior; cite source files. A future agent starts with AGENTS + status + scope, then opens only relevant documents/skills. Chat history is supplemental, not the sole record of requirements.
