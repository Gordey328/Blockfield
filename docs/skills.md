# Skill organization

Project skills live in `.agents/skills/` so they travel with the repository. Each entry point stays short. References hold detailed formats/contracts only when needed.

## Project-owned

- [blockfield-port-parity](../.agents/skills/blockfield-port-parity/SKILL.md): source audit, migration status and evidence.
- [blockfield-voxel-world](../.agents/skills/blockfield-voxel-world/SKILL.md): chunk/VXL invariants and world verification.
- [blockfield-web-release](../.agents/skills/blockfield-web-release/SKILL.md): reproducible Godot export and GitHub Pages checks.
- [blockfield-multiplayer](../.agents/skills/blockfield-multiplayer/SKILL.md): shared authority, WSS protocol, prediction, map joins and multiplayer verification. [Multiplayer plan](multiplayer-plan.md) holds the original design and links current production contracts; the skill passed the system creator's quick_validate.py using existing isolated PyYAML dependencies.

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

Recover in this order: [AGENTS.md](../AGENTS.md) → [current status](status.md) →
[accepted iterations](iterations.md) → affected [parity rows](parity.md) and
[acceptance gaps](acceptance-gaps.md) → relevant [architecture](architecture.md),
subsystem contract and [ADR](decisions/) → the necessary `SKILL.md`.
Open [dated history](history/2026-10-10.md) only when earlier evidence/failures
are relevant. Archived assignments and next-action statements never reopen a lease.

Keep status short: present source/export/published artifact identities, active ownership,
pending acceptance and next actions. Move detailed prior milestones into dated history
without losing facts; keep subsystem measurements with the subsystem contract.
At a handoff record files, reproducible commands, exact results, cleanup and unresolved
behavior. Update affected ledger rows only to the evidence actually obtained.
The full-suite/export/deployment/browser gates are distinct; native/probe success is
not browser or full-iteration acceptance. Facts belong in docs, procedures in skills,
and architectural choices in numbered ADRs. Chat supplies supplementary context.
