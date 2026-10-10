# Architecture and current contracts

## Boundaries
- VoxelData: shared packed cells, source queries, VXL, edit/collapse rules, atomic ordered transactions and bounded journal. VoxelWorld adopts Data and owns chunk meshes/collision, water/GI/reflections, top-down textures and visual falling clusters. Never apply an adopted transaction to Data then World twice.
- LocalSession owns the serverless offline lab and its source-shaped local rules. SharedPlayerState, PlayerRules, GrenadeRules, MatchObjectives and MatchSimulation provide pure fixed60Hz multi-actor authority for the dedicated server. NetworkSession subclasses only the presentation interface, mirrors owned confirmed/predicted state and never runs inherited offline authority. The two adapters remain explicit compatibility paths, with source goldens covering their behavior.
- PlayerController routes offline controls to LocalSession and network controls to authenticated typed intents plus ClientPrediction. Network Main adopts only committed Replica map/state barriers; rendering cannot run offline damage, objectives, projectiles or lab cheats. WeaponView/CharacterView own original models/animation; HUD/LabPanel displays the adapter and controls the local lab.
- MobileControls owns immutable touch/mouse pointer claims, per-ID absolute-position history, floating/fixed stick and optional primary-fire/look gestures. It emits local logical-coordinate look deltas, movement and action edges. HUD owns touch preferences, lifecycle gates and `InputEventAction` bridging; PlayerController normalizes touch look by overlay width independently of mouse gain and combines the analog stick with keyboard intent before either offline motion or authenticated network commands. No new simulation/authority path is introduced. See [mobile controls](mobile-controls.md) and [ADR0008](decisions/0008-mobile-fps-input.md).
- OpenSpadesAudio: per-view sound layers, environmental ray sampling and mono/stereo distance/pan routing. Main supplies the listener; presentation consumes authoritative events. See audio.md.
- SourcePlayerMotion: native corner collision, step/climb and crouch eye geometry against Data or World's narrow query contract. PlayerRules owns shared acceleration/fall authority; existing offline controller remains a compatibility path. SourceCameraEffects: isolated presentation noise, angular basis/FOV and radial blur; authoritative aim rays remain on the player head.
- LabConsole: typed allowlist of local commands and saved preferences; LabChat owns input/history/completion, with no runtime script evaluation. See console.md.
- BlockfieldProtocol/WSTransport use explicit bounded bytes and poll-driven socket lifecycle. SessionRegistry binds guest capabilities to stable actors; InputQueue enforces generation/epoch, bounded intent and one command per step. MapTransfer stages baseline/deltas privately before adoption. ServerRuntime wires these to MatchSimulation; ClientPrediction provides pure replay/interpolation and ClientReplica owns confirmed public state plus private owner state. MATCH_STATE14 and GAME_EVENTS15 use validated shared public serialization with owner-only private fields; PLAYER_REQUEST16 carries bounded class/team/color/reload intents. Full native wire/Replica/rendered integration is implemented; browser/deployment acceptance remains unfinished. See decisions/0005-authoritative-multiplayer.md and server-runtime.md.
- HitHistory retains exact closed actor/terrain frames. Runtime admits input timestamps; Match plans all historical firearm pellets before damage and checks current life/color on commit. One bounded immutable terrain index may be shared by independently revocable queries. Prepared source hit-volume transforms live only within a shot. Round reset rotates capabilities and completes fresh map/state barriers while preserving canonical IDs. See hit-history.md, match-rewind.md and runtime-epoch.md.

## Voxel interface
`class_name VoxelWorld extends Node3D` in game/world/.
Methods: generate_lab(), get_spawn_position()->Vector3, get_block(Vector3i)->int, set_block(Vector3i,int), cast_voxel(origin,direction,max_dist)->Dictionary, explode(position,radius), load_vxl(path)->Error.
Air is 0; solid colors are 0x01RRGGBB. Block coordinates are Godot Y-up. VXL maps original (x,y,z) to (x,63-z,y).
Transient damage uses World's `set_block_damaged`/`is_block_damaged`/`clear_block_damage`
mask and `get_render_color` mesh adapter. The controller or confirmed network-event
adapter owns expiry; VoxelData colors, collision and journals stay intrinsic.
Edits/reset clear marks. See [ADR0009](decisions/0009-block-damage-presentation.md).
Ray result: hit, cell, normal, position. blocks_changed signal array contains cell/before/after (optional collapsed).
Lab bounds 96x32x96; bedrock y=0, floor y=1..3; player spawn uses get_spawn_position().

## Skill/document roles
AGENTS.md: concise entry point and working rules.
status.md: current checkpoint and next action.
iterations.md: scope and acceptance, changed only when user changes scope.
parity.md: evidence-based source-to-port checklist.
decisions/: architecture decisions and their reasons.
skills/: reusable workflows, with links to source-of-truth docs rather than duplicated state.
