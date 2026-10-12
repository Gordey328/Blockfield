# Architecture and current contracts

## Boundaries
- Rush is a canonical variant of OfflineSurvivalSession, with kill-based run choices
  and actor-scoped firearm/zombie-armor modifiers. Pending choice and unfinished
  launch preparation independently gate fixed simulation and HUD input. RushRecords
  stores local versioned best scores per weapon; UI never grants damage or resources.
  See [ADR0035](decisions/0035-market-oriented-rush.md).
- OfflineSurvivalSession reuses OfflineTDMSession's local command/presentation bridge,
  with its own bounded roster, timed overlapping waves, supply and finite outcomes.
  ZombieDirector proposes commands and bite/breach intents; MatchSimulation and the
  survival authority validate and commit them. Each life locks a random obstacle
  choice; navigation validates bounded detour/breach paths and projects elevated
  targets to a lower approach. Reachable forward blocks can be breached when the
  owner stands above normal step height. Main pools twelve unarmed
  ZombieViews and presents committed terrain once; SurvivalPanel/HUD only display.
  GameMapCatalog admits canonical damage/wave settings and trusted Crossroads,
  Minecraft Chunk and MIRA HQ survival identities. Trusted per-life grenadier
  loadouts and isolated explosion profiles stay in MatchSimulation; the director
  only proposes60tick throws. Human grenade rules remain independent. See
  [ADR0032](decisions/0032-timed-zombie-survival.md), its latest selection/startup
  amendment [ADR0033](decisions/0033-zombie-pursuit-and-startup.md), and [evidence](zombie-survival.md).
- Entry creates GameShell without a world/simulation; all launch routes are local. GameMapCatalog whitelists mode/map/weapon, preserves a separate
  saved selection and supplies baked previews. Entry hands a one-shot launch to
  Main through SceneTree metadata. Main keeps input gated through map adoption and
  session-owned weapon selection, then opens gameplay. Loading/recovery/Home are
  presentation; local authority stays with the adapters. See
  [ADR0030](decisions/0030-game-shell-and-offline-launch.md).
  Match Main disables the discarded lab bootstrap before child readiness and
  seeds streaming/camera at the authority spawn. Entry gives the pending shell two
  presentation turns before loading; standalone lab bootstrap stays enabled.
  Normal match launch awaits existing bounded chunk and progressive minimap/water
  preparation with a30second error/retry deadline before clock/input admission.
  Survival Entry warms a packed scene/resource list without instantiating a world;
  Main stages effects/equipment/setup and lazily creates enabled HDR. See
  [ADR0034](decisions/0034-survival-grenadiers-and-levels.md).
- Web startup uses `game/web/loading.html`, derived from the pinned engine shell. The existing `Engine.onProgress` byte callback supplies decimal MB for the engine/game pack; exported file sizes supply the complete denominator before downloads start. Its original startup/error/overlay lifecycle stays intact; see [ADR0017](decisions/0017-web-download-progress.md).
- VoxelData: shared packed cells, source queries, VXL, edit/collapse rules, atomic ordered transactions and bounded journal. VoxelWorld adopts Data and owns chunk meshes/collision, water/GI/reflections, top-down textures and visual falling clusters. Never apply an adopted transaction to Data then World twice.
- LocalSession owns the offline lab and source-shaped local rules. SharedPlayerState, PlayerRules, GrenadeRules, MatchObjectives and MatchSimulation own fixed60Hz local multi-actor combat. OfflineTDMSession supplies one human and five bots; transport, prediction, rewind and connection lifecycle are removed under [ADR0031](decisions/0031-offline-only-game.md).
- PlayerController routes lab controls to LocalSession and samples one local command per fixed TDM step. It adopts local actor life/pose through `_adopt_match_owner` and presents committed effects through `apply_match_cosmetic`; render look cannot duplicate input at physics boundaries. WeaponView/CharacterView retain original models/animation; HUD displays the local adapter.
- CombatReadout reads the existing session adapter and owns modern health/ammo/resource/score drawing. CombatTheme supplies authored line icons and the pinned Inter font with the existing multilingual fallback. Display values and local island rectangles are exposed for scene/layout checks; no input, rules or transport authority lives here. MobileControls shares the authored icon/font treatment and preserves pointer claims across its asymmetric thumb layout. See [ADR0022](decisions/0022-modern-combat-ui.md) and [ADR0023](decisions/0023-mobile-thumb-layout-and-aim-friction.md).
- TouchAimAssist computes a stateless touch gain from public target poses, original firearm hit volumes and source terrain visibility. Player applies it only to living first-person firearm touch intent before the existing local command path. It never generates angles, shots, damage or authoritative state. Main persists the optional default-on setting; desktop look is independent.
- OfflineTDMSession is the third explicit adapter: a fixed60Hz MatchSimulation with one human command and five TdmBotDirector commands. Main adopts shared actor state and presents committed terrain/events once. TDM goals, score/time limits and physical supply points belong to the adapter; tactical perception and bounded voxel navigation belong to `game/ai/`. The separate Crossroads scene leaves the lab independent. See [ADR0020](decisions/0020-offline-team-bots.md).
- MobileControls owns immutable touch/mouse pointer claims, per-ID absolute-position history, floating/fixed stick and optional primary-fire/look gestures. Its NexQuake layout uses full-height40% movement /60% look columns with button priority and optional mirroring. It emits local logical-coordinate look deltas, cancellation, movement and action edges. HUD owns touch preferences, lifecycle gates and `InputEventAction` bridging; PlayerController queues width-normalized displacement and consumes it once at a render/physics boundary, before lab motion or local match-command sampling. The baseline is400degrees/full-width at1x, independently of mouse gain; analog stick joins keyboard intent. No new simulation/authority path is introduced. See [mobile controls](mobile-controls.md), [ADR0008](decisions/0008-mobile-fps-input.md) and [ADR0014](decisions/0014-nexquake-mobile-camera.md).
- OpenSpadesAudio: per-view sound layers, environmental ray sampling and mono/stereo distance/pan routing. Main supplies the listener; presentation consumes authoritative events. Extensions checks active ZIP overrides before its bounded native PCM whitelist, with the full legacy catalog as fallback. See audio.md and [ADR0016](decisions/0016-impact-cpu-batching.md).
- Local VXL jobs retain private decode data or one frozen encode version. World guards one operation by token/Data/epoch; Main guards notices, baseline and download by request ID. Validated adoption is atomic. Exact ambience and model-tint caches have fixed retention bounds; live mesh materials survive eviction. See [ADR0013](decisions/0013-audio-vxl-memory.md).
- BlockfieldMap validates compact BFM1 packages into independent VoxelData before Main adopts them. Main retains the original reset bytes/metadata; World retains validated feet spawn for streaming and respawn. Native saves select a supported spawn if edits destroy its original support. Dry-map metadata combines with the user's water preference. Explicit bundled maps under assets/maps export with the game and precede same-name local shortcuts; raw Blender/BSP inputs and ignored local maps stay outside the public build. See [ADR0024](decisions/0024-local-map-conversion.md) and [ADR0026](decisions/0026-bundled-map-publication.md).
- Terrain impact presentation updates only affected cell color attributes, retaining mesh/collider identity and AO. World advances one bounded chunk job at a time and publishes complete geometry/shape together; invalidation cancels stale jobs. Several original columns/planes share local output ownership within a callback, retaining each unit deadline/count boundary; optional stage profiling is off by default. `rebuild_now` synchronously flushes the same path. Minimap uploads follow Image identity/dimensions/pixel revision. See [ADR0015](decisions/0015-budgeted-block-impact-rendering.md) and [ADR0016](decisions/0016-impact-cpu-batching.md).
- SourcePlayerMotion: native corner collision, step/climb and crouch eye geometry against Data or World's narrow query contract. PlayerRules owns shared acceleration/fall authority; existing offline controller remains a compatibility path. SourceCameraEffects: isolated presentation noise, angular basis/FOV and radial blur; authoritative aim rays remain on the player head. GrenadeFeedback shares the user-selected shorter distance envelope between grenade/collapse shake and explosion dry/wet audio; source world scale/rules stay unchanged. See [ADR0019](decisions/0019-grenade-feedback-range.md).
- OpenSpadesEffects owns50 preallocated typed decorative particle records and16 casing records with fixed active/free indices. Particles/casings have analytical collision-free motion once per rendered frame; white fragments write directly into MultiMesh without hidden Sprite3D mirrors, animated smoke/water and original casing models use bounded prewarmed nodes. Importance/distance-ranked recycling keeps fresh particle feedback visible under saturation. Clear/reload retain bounded resources; tracer/light pools and camera/weapon audio remain. FallingVoxelCluster renders at most64 representative cubes in one grouped MultiMesh for1s, without terrain checks or impact debris; authoritative collapse stays in VoxelData. See [ADR0025](decisions/0025-fixed-noncolliding-effects.md), [ADR0011](decisions/0011-effect-pools-and-fragment-batching.md) and [effects evidence](effects-performance.md).
- LabConsole: typed allowlist of local commands and saved preferences; LabChat owns input/history/completion, with no runtime script evaluation. See console.md.
- MatchSimulation keeps immutable bounded terrain receipts and presentation events. After receipt overflow, Main presents retained receipts once, then rebuilds VoxelWorld from the same adopted Data and restores damaged-cell tint. No second Data application or remote acknowledgement occurs; events remain bounded and consumed locally.


On `dev` and `codex/web-max-optimization`, Main uses OpenSpadesCorpse's explicit
`setup_static` path with the existing Player/Dead model and a captured death pose.
Floor projection happens once; resource refresh preserves the pose, and Main does
not dispatch per-frame corpse physics. Existing body retention, camera center and
clear contracts remain. The legacy source solver is retained for differential
fixtures. This user-approved presentation adaptation is [ADR0028](decisions/0028-static-death-models.md).

## Voxel interface
`class_name VoxelWorld extends Node3D` in game/world/.
Methods: generate_lab(), get_spawn_position()->Vector3, get_block(Vector3i)->int, set_block(Vector3i,int), cast_voxel(origin,direction,max_dist)->Dictionary, explode(position,radius), load_vxl(path)->Error.
Air is 0; solid colors are 0x01RRGGBB. Block coordinates are Godot Y-up. VXL maps original (x,y,z) to (x,63-z,y).
Damage presentation uses World's `set_block_damaged`/`is_block_damaged`/`clear_block_damage`
mask and `get_render_color` mesh adapter. The controller or shared authority owns
persistent health; no timer restores it. VoxelData colors, collision and journals stay intrinsic.
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
