# Architecture and current contracts

## Boundaries
- VoxelWorld: packed colored solid cells, VXL import, chunk meshes/collision, edit batching, block-ray intersection and unsupported-block collapse.
- LocalSession: authoritative offline state for players, damage/ammo/grenades, respawn, teams and mode objectives. Presentation consumes session events. Future server runs equivalent rules.
- PlayerController: input and movement; WeaponView/CharacterView: original models and animation; HUD/LabPanel: state display and test controls.
- Transport: absent from iteration-1 execution path. Future interface delivers commands/snapshots, not direct UI callbacks.

## Voxel interface
`class_name VoxelWorld extends Node3D` in game/world/.
Methods: generate_lab(), get_spawn_position()->Vector3, get_block(Vector3i)->int, set_block(Vector3i,int), cast_voxel(origin,direction,max_dist)->Dictionary, explode(position,radius), load_vxl(path)->Error.
Air is 0; solid colors are 0x01RRGGBB. Block coordinates are Godot Y-up. VXL maps original (x,y,z) to (x,63-z,y).
Ray result: hit, cell, normal, position. blocks_changed signal array contains cell/before/after (optional collapsed).
Lab bounds 96x32x96; bedrock y=0, floor y=1..3; player spawn uses get_spawn_position().

## Skill/document roles
AGENTS.md: concise entry point and working rules.
status.md: current checkpoint and next action.
iterations.md: scope and acceptance, changed only when user changes scope.
parity.md: evidence-based source-to-port checklist.
decisions/: architecture decisions and their reasons.
skills/: reusable workflows, with links to source-of-truth docs rather than duplicated state.
