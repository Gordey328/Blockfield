# Shared match authority

> Historical pre-removal design/evidence. Multiplayer was withdrawn on2026-10-12
> under [ADR0031](decisions/0031-offline-only-game.md). Deleted networking paths
> and server instructions below do not apply to the current offline game.

`game/simulation/match_simulation.gd` (`MatchSimulation`, `RefCounted`) coordinates `SharedPlayerState`/`PlayerRules`, `VoxelData`, `GrenadeRules`, source hit volumes and `MatchObjectives`. It has no scene tree, camera, Input, audio, transport or global random dependency. The offline main/controller/session are not replaced by this file. This is implemented pure authority, not evidence of a working browser multiplayer game or a complete network snapshot schema.

Source references are the pinned OpenSpades v0.1.3 `dcf449c845d509bbde9d79239b32d201c1389961`: `Player.cpp` firearm/spade/build rules, `Weapon.cpp` profiles and `World.cpp::CubeLine`; existing Godot source goldens remain applicable. OpenSpades is a client. Admission, server scoring, spawn choice, friendly-fire enforcement, disconnect policy, queue limits and match scheduling below are explicitly authored authority policies.

## Runtime API

```gdscript
var map := VoxelData.new()
map.generate_lab(7)
var simulation := MatchSimulation.new()
var configured := simulation.configure(map, "0.75", "ctf")
var joined := simulation.add_actor("Player")
var id: int = joined.actor_id
var spawned := simulation.spawn_actor(id, 0)
var events := simulation.step_fixed({id: authenticated_command})
var map_transactions := simulation.drain_transactions()
var snapshot := simulation.snapshot_for(id)
```

| Public API | Contract |
| --- | --- |
| `configure(map_data:VoxelData,match_profile="0.75",game_mode="sandbox")->Dictionary` | Returns `{ok,error}`. Requires an initialized writable map, valid epoch, bootstrap map tick0, source profile0.75/0.76 and sandbox/ctf/tc. Validates safe map spawns before replacing state. Reconfiguring an active registry/clock requires a new epoch; failures preserve the previous match. Starts tick−1. |
| `add_actor(player_name,team=2,seed_value=1)->Dictionary` | Returns `{ok,error,actor_id}` on success. At most32 stable positive IDs, no reuse within epoch, names1..64 UTF-8 bytes with control characters rejected. Actor starts as inactive spectator generation1; a playing team argument additionally performs a trusted safe spawn. The caller authenticates/admission-limits connections and chooses seeds. |
| `get_actor(id)->SharedPlayerState` | Trusted direct authority access; null for unknown ID. This is not a client state-write API. |
| `spawn_actor(id,team,weapon=-1,feet=Vector3.INF)->Dictionary` | Returns `{ok,error,events}`. Rejects alive actors, early respawn, invalid class/team, occupied terrain and live player overlap. Omitted feet uses the authored safe team-region search; explicit feet is trusted server input, validated against the map. Increments generation, applies pending class and fills source inventory. Live class requests cannot invoke this to refill. |
| `set_team(id,team)->Dictionary` | Trusted choice0/1/2. Drops carried intel; a live actor's transition produces one authored team-change death without kill credit and retains respawn eligibility. It does not silently respawn/refill. |
| `clear_controls(id)->bool` | Neutralizes accepted move/buttons only. Preserves the cook and previous edge so the next fixed step releases a grenade after the original minimum pin time; sprint recovery and reload state remain rule-owned. The runtime applies its bounded input lease. |
| `disconnect_actor(id)->Dictionary` | Marks inactive once, neutralizes controls, drops carried intel and forcibly releases a live cook once. Retains the stable actor for reconnect grace. Forced disconnect drop is authored server policy, using the native death-drop velocity/fuse convention. |
| `reconnect_actor(id)->Dictionary` / `remove_actor(id)->Dictionary` | Restore a trusted existing binding/clock, or remove it after grace. Reconnect creates no ammo/class refill or ID change. Already-thrown grenades survive removal. The runtime owns reconnect token checks and grace duration. |
| `set_block_color(id,packed_rgb)->bool` | Trusted24-bit RGB or canonical solid color. Defaults to gray. A future wire setting needs its own ownership/schema validation. |
| `step_fixed(commands:Dictionary={})->Array[Dictionary]` | Advances exactly one60Hz tick, with no supplied delta. Only `PlayerRules.Command` values indexed by known actor IDs are consumed. Returned per-step events are immutable. The runtime selects the dictionary key from its authenticated binding, never a client-chosen ID. |
| `damage_actor(id,amount,attacker_id=0,cause="weapon",action_id="")->Array[Dictionary]` | Trusted outcome helper for fixtures/server policy. Never accepts a network claimed hit. Automatic gun/melee/grenade resolution uses the same damage path. |
| `drain_events()` / `drain_transactions()` | Immutable bounded pending history or explicit resync marker. Recorded event copies include global positive `match_sequence`; raw rule/per-step arrays remain unsequenced. See recovery below. |
| `acknowledge_map_resync()->bool` | Trusted runtime only, after invalidating all old map streams and initiating fresh immutable baselines. Clears transaction queue/count/resync flag; returns whether a resync was pending. Client requests cannot acknowledge this. |
| `snapshot_for(id)->Dictionary` | Copied internal owner/actor/projectile state, objective snapshot, map barrier, counters and block/gesture state. Unknown owner returns empty. This is not a codec. |

Public `data`, typed `actors`, `tick`, `epoch`, `profile`, `mode`, `objectives`, `grenades`, `event_sequence`, `friendly_fire`, `resync_required` and `last_error` let the trusted runtime schedule, configure and inspect authority. Public actor/objective access must never be forwarded as arbitrary RPCs.

Lifecycle operations join/spawn at the next authority tick. The runtime must step before sending a first wire snapshot so every included owner's `last_tick` agrees with the snapshot tick. Commands retain the rule module's sequence/generation checks. Authentication, scheduling/catch-up limits, input age/future windows, lease timeout, reconnect tokens and command queues remain runtime responsibilities.

## Resolution and source behavior

Each tick advances all actors in stable ID order through the same shared map before resolving attacks. A fired gun intent retains its source origin/directions; it can resolve even if its shooter dies later during that tick. Melee/build require their actor to remain active at resolution. These are explicit simultaneous-step policies. Gun queries use all actors at that current tick and current terrain; **no rewind or lag compensation exists here**. A later rewind implementation must pair historical actor poses and terrain from the same permitted time.

Firearm queries reuse `LabHitVolumes`, excluding the shooter, spectators, dead and disconnected actors. Body-part order/ties retain source behavior. `source_weapon_hit` compares horizontal distances with strict `<128`; a map/player horizontal tie retains the player. Actual map damage/occlusion is queried, not taken from input. Shot events cost source ammo through `PlayerRules`; resolved `hit_confirmed`, block impact and per-pellet tracer events carry owner/victim/part/position/friendly/source-event attribution. The view adapter may suppress first-person tracers according to source presentation behavior; authority does not select a camera.

Terrain has100HP, source weapon block damage and55 spade damage. Regeneration waits strictly more than600 ticks since the latest hit; replaced palette cells invalidate stale HP. A shotgun discharge directly destroys at most one block, while further pellets can damage another cell to0 for a later shot. Map collapse is decided by `VoxelData` and included in the same authority transaction. Native broad melee uses eye Chebyshev reach/cone and stable slot order; player selection precedes a wall hit. It deliberately does not inherit firearm occlusion. Primary destruction recovers one block capped at50; secondary dig removes the three-cell vertical column and does not grant the primary recovery stock, as the existing offline authority does.

Construction uses the authority eye/front ray, strict3-block Chebyshev endpoint reach, editable layers above1, source cooldown/stocks and overlap checks against every live actor. Primary self-overlap while airborne can queue a delayed placement; it must remain in reach, clear and supported when committed, and landing/depletion/tool/death cancels it. Revalidating delayed support and checking all actors are explicit server safeguards. Secondary press records a valid anchor; release uses the original integer-crossing `CubeLine`, including its Z-down crossing asymmetry. Anchor support is rechecked; invalid aggregate lines do not partially charge/build. Occupied line cells preserve their color but consume stock, as source `CubeLine` behavior does. Each empty cell produces an ordered attributed voxel transaction. The construction gate uses the pre-update native lower/raise/sprint state, so reaching raise1 at tick end does not allow a build one input phase early.

Damage is attributed to stable actor IDs, with a victim death increment once. Enemy kills award1 kill and1 score; friendly/self/environment/team-change deaths award no enemy kill score. `friendly_fire` defaults true to preserve offline damage availability and can be disabled by trusted server configuration. CTF capture score10 remains separate from kills. Grenades retain the thrower's generation and team at release, so a team change/respawn cannot rewrite their damage attribution. Cover damage is evaluated before explosion terrain removal. Already-released grenades are independent of the owner's connection/life.

Authored default spawn/base regions are map-scaled team fractions1/6 and5/6 at the center Z, with a bounded nearby safe-column search. TC defaults use map fractions1/4,1/2,3/4. This is not original server/map metadata. The runtime may explicitly configure `objectives` for its mode/map; source client never supplied this server policy. The inherited180-tick respawn eligibility is documented in `player-rules.md`. `MatchObjectives` preserves its configured winner state; automatic new-round/reset scheduling is external.

## Bounded history and recovery

The event ring holds2048 pending events; each fixed-step return is capped at16384 (normal source actor/projectile bounds fit within it). Global `event_sequence` is a cursor distinct from actor event ordinals. Events retain the source module envelope `type/owner_id/spawn_generation/epoch/tick/event_id`, action attribution and payload fields. Ring overflow returns `events_resync_required` rather than a plausible partial history; draining consumes this event marker. Recorded journal events now carry copied immutable `match_sequence` values; the overflow marker retains the current global cursor. Raw rule/per-step return arrays remain unsequenced. The network layer batches/privacy-routes the journal through EventsCodec; see events-codec.md.

The map drain retains at most256 transactions and32768 changes. Transactions carry epoch/map sequence/server tick/stable actor/input-action attribution, canonical colors and collapse flags. Overflow/rejection discards the incomplete drain and makes `resync_required` sticky. Every drain then returns `{ok:false,type:"map_resync_required",resync_required:true,epoch,tick,map_sequence}`. This marker is **not** a MAP_DELTA payload. The runtime must cancel old streams, create fresh immutable baselines at the current barrier and explicitly call `acknowledge_map_resync`; only then can it resume deltas. The shared voxel journal independently reports retained-history gaps. No missing changes are inferred or silently skipped.

At most256 grenades are active. Existing cooks reserve future projectile slots; capacity pressure suppresses a new pin without consuming stock, including disconnect/rejoin churn. Releasing a reserved cook, including death, retains its projectile at the exact cap. This is an authored bounded server policy. A server-only bypass that mutates actor cook state outside this coordinator can violate that reservation invariant; the module reports a capacity fault rather than claiming a successful simulation. Stable grenade IDs do not reuse a removed actor's ID. There is no implicit u32 wrap; reset/rebase before wire counters exhaust.

`snapshot_for` owns copies of actor motion/resources/RNG, grenade states, construction/block-health state, and immutable objective data. The caller can mutate copies without changing authority. **Do not broadcast these objects or every actor's private ammo/RNG**. A wire mapper must serialize explicit allowed public pose/event fields and only the recipient's private rule state. Map baseline bytes must come from a captured `VoxelData.frozen_copy()` plus the matching map/state barrier; this method does not capture a second full map or implement transfer assembly. Exact client prediction and complete objective/projectile/event snapshots need their own schema and evidence.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf`:

```powershell
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://simulation/match_simulation.gd
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_match_simulation.gd --verbose
```

Result: **208 assertions / 0 failures**, exit0; verbose output contains no script errors or ObjectDB/resource leaks, stderr empty. `.cache/logs/test-match-simulation.log` is an ignored local evidence file. Tests use real `VoxelData` and actual rule inputs, without main/settings/presentation. They cover lifecycle/admission/spawn/class/death/reconnect, owner-bound ready weapon input, enemy/friendly attribution, source hit/occlusion and through-destroyed-cover behavior, collapse metadata, source melee/CubeLine goldens, block color/line/occupied costs and all-actor overlap, native raising phase, pending air build, regeneration/replacement/shotgun destruction budget, primary recovery/three-cell dig, lease/death/removal grenade lifetime and cap reservation, CTF/drop/capture score, independent snapshot copies, bounded histories and baseline-plus-next-delta resync recovery. The separate player rules144, source motion128, grenade30, objectives27, voxel110 and adapter25 fixtures remain their own evidence. This suite does not prove two live clients, browser WSS, prediction quality or N01–N09 acceptance.
