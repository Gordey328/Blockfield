# Architecture and current contracts

## Boundaries
- VoxelData: shared packed cells, source queries, VXL, edit/collapse rules, atomic ordered transactions and bounded journal. VoxelWorld adopts Data and owns chunk meshes/collision, water/GI/reflections, top-down textures and visual falling clusters. Never apply an adopted transaction to Data then World twice.
- LocalSession: existing authoritative offline adapter for lab/presentation. SharedPlayerState, PlayerRules, GrenadeRules, MatchObjectives and MatchSimulation now provide pure fixed60Hz multi-actor authority; LocalSession/controller delegation is unfinished. No claim that extracting rules alone migrates the offline adapter.
- PlayerController: input and movement; WeaponView/CharacterView: original models and animation; HUD/LabPanel: state display and test controls.
- OpenSpadesAudio: per-view sound layers, environmental ray sampling and mono/stereo distance/pan routing. Main supplies the listener; presentation consumes authoritative events. See audio.md.
- SourcePlayerMotion: native corner collision, step/climb and crouch eye geometry against Data or World's narrow query contract. PlayerRules owns shared acceleration/fall authority; existing offline controller remains a compatibility path. SourceCameraEffects: isolated presentation noise, angular basis/FOV and radial blur; authoritative aim rays remain on the player head.
- LabConsole: typed allowlist of local commands and saved preferences; LabChat owns input/history/completion, with no runtime script evaluation. See console.md.
- BlockfieldProtocol/WSTransport: explicit bounded bytes and poll-driven socket lifecycle. SessionRegistry binds guest capabilities to stable actors; InputQueue enforces generation/epoch, bounded intent and one command per step. MapTransfer stages baseline/deltas privately before adoption. ServerRuntime wires these to MatchSimulation; ClientPrediction provides pure replay/interpolation. Full wire/replica/rendered multiplayer integration is ongoing, separately from the offline path. See decisions/0005-authoritative-multiplayer.md and server-runtime.md.

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
