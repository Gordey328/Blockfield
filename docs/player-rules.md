# Shared player rules

`game/simulation/player_state.gd`, `weapon_profiles.gd` and `player_rules.gd` implement a scene-independent actor component for iteration 2. They do not replace the offline `LocalSession` or controller yet. Passing these tests does not establish working multiplayer, reconciliation, a dedicated server or browser networking.

The reference is OpenSpades v0.1.3 `dcf449c845d509bbde9d79239b32d201c1389961`, chiefly `Sources/Client/Weapon.cpp`, `Player.cpp`, `Client_Update.cpp` and `ClientPlayer.cpp`. The Godot code uses Y-up coordinates and native velocity magnitudes: displacement is native velocity × 32 × seconds. The source algorithms retain GPL-3.0-or-later provenance under the repository license.

## State and clock

`SharedPlayerState` is a `RefCounted` per-actor state. `player_id` is a stable actor ID, distinct from a WebSocket peer ID. `match_epoch` changes on match reset; `spawn_generation` increments on an authorized spawn. The coordinator validates identities, names and the match-wide `profile` (`0.75` or `0.76`). State includes team/name, desired/displayed tool, lower/raise and sprint/ADS state, source collision/movement state, health, magazine/reserve, block/grenade stocks, pending class, fractional deadlines, accepted controls, cook state and an isolated random stream. `score`, `kills` and `deaths` are separate; only victim deaths are incremented here. The coordinator assigns killer/objective scores.

```gdscript
var actor := SharedPlayerState.new(1, "Player", 7, "0.75", 12345)
var spawn_events := PlayerRules.spawn(actor, 0, Vector3(20.5, 4.01, 20.5), 0, 0)
var input := PlayerRules.Command.from_record(validated_input_record, actor.spawn_generation)
var events := PlayerRules.step_fixed(actor, 0, input, voxel_data)
```

`step_fixed(actor, tick, command=null, query=null, rng=null)` advances exactly 1/60 second. It accepts only `tick == actor.last_tick + 1`; duplicate/skipped/negative steps leave state unchanged. Spawn sets `last_tick = spawn_tick - 1`. A spectator joining an already-running match needs the coordinator to set `last_tick = next_tick - 1`. There is no client-provided delta or position. `Command` has sequence/generation, normalized `move`, yaw/pitch, button bits, and optional tool/class intent (`255` means no change). Its sequence/generation are positive u32; controls retain the protocol's bounds. `from_record` consumes an already decoded/validated record; it is not an alternate network decoder.

New valid input must have a greater actor input sequence and the current generation. Otherwise the last accepted controls remain held. Authentication, epoch validation, input age/future windows, bounded queues and a maximum input lease belong to the coordinator. A command packet is not permission to choose an actor, tick, spawn, restock, map edit, damage or score.

The actual motion query is `VoxelData` or an equivalent object exposing `dimensions: Vector3i`, `get_block(Vector3i)->int`, `water_level: float` and `wade_origin_level: float`. Rules call `SourcePlayerMotion` directly; there is no physics-server or renderer dependency. `query=null` is intended only for isolated resource fixtures: it does not move, collide or apply crouch. Production simulation must supply the shared map.

`copy()` owns copies of source movement and RNG state as well as all value fields. This supports replay without modifying another actor or a cosmetic random stream. A server and replay client still need a seed/state policy and a snapshot of relevant private rule state; the current wire codec alone does not provide that policy.

## Rules and events

`SourceWeaponProfiles.get_info(profile, weapon)` returns an isolated dictionary containing the source profile; indices 0/1/2 are rifle/SMG/shotgun. It preserves both source versions' ammo, cadence, reload, spread, recoil and per-part damage. `damage(profile,weapon,part,horizontal_distance)` applies the original strict 128-unit horizontal cutoff and known body-part aliases.

The desired tool uses 0 spade, 1 block, 2 weapon, 3 grenade. Selection cancels weapon/cook actions without consuming a held grenade, clears primary/secondary input and lowers the old tool before swapping/raising the new one. Actions require live/connected playing actors, zero raw sprint recovery, no active sprint and a completed tool transition. A depleted tool chooses the previous usable source tool. Initial spawn raises the weapon from zero; it does not grant an immediate shot.

Held fire keeps a fractional deadline: 0.75 SMG has a 6.6-tick period, producing ticks `0,7,14,20,27,33,40` from an already-raised fixture. New presses rebase an overdue deadline; a held trigger cannot accumulate extra shots in one fixed step. Dry-fire emits once per held trigger. Fast reload completes after 150 ticks; shotgun loads individual shells after 30 or 24 ticks for 0.75/0.76. `begin_reload` is the public method name (`Script.reload` is an engine method). Source `Weapon::FrameNext` handles firing/slow-reload interruption before shell completion, including an empty shotgun pressed exactly at the shell deadline: no phantom shell is loaded/fired. The shared rule phase is explicit and fixed; offline behavior also depends on controller trigger updates and the render-clock session update, so this fixture does not by itself identify an offline gameplay bug.

Source movement preserves acceleration/friction/gravity, crouch/ADS/sneak/sprint modifiers, vertical-look slowdown, normalized diagonal input, held-jump eligibility, previous-velocity sprint threshold, collision/step/uncrouch and landing response. Passive dead/disconnected actor damping and fall health authority follow the existing port's authored local policy. Spade secondary has priority, waits strictly more than one second and repeats on the same source timer; primary bash waits strictly more than .2 seconds. Events request melee resolution; rules do not select victims or edit the world.

Grenade pin/release has the source .15-second minimum, .5-second manual-release cooldown and strict `cook_time > 2.9` auto-release. Inventory is consumed exactly at release. Native `Update` auto-cook release calls `ThrowGrenade` directly and adds no manual-release cooldown; a held press still cannot pull a second pin until a new primary edge. A death bypasses the pin minimum, emits one drop with the remaining fuse and native velocity, and clears cooking before returning the event. The grenade coordinator must create one authoritative grenade per returned event. Switching tools cancels a cook without releasing it.

Trusted coordinator entry points:

| Method | Contract |
| --- | --- |
| `spawn(actor,tick,feet,team,weapon=-1)` | Valid team/location and spawn eligibility must be checked externally. Increments generation, applies pending class, fills source inventory, resets actions/deadlines. Explicit weapon overrides the pending selection. |
| `request_class(actor,weapon,tick)` | Stores a valid pending class. A live actor's active weapon/resources/health remain unchanged until authorized spawn. |
| `select_tool(actor,tool,tick)` | Checks live actor/tool resources and begins source lower/swap/raise. |
| `fire(actor,tick,rng=null)` / `begin_reload(actor,tick)` | Check source readiness/resources. A coordinator normally obtains fire from `step_fixed`, rather than invoking it twice. |
| `damage(actor,amount,tick,attacker_id=0,cause="weapon",action_id="")` | Trusted validated outcome only. Positive finite damage clamps to health before integer conversion and rounds upward, as offline health authority does. Emits hurt, optional forced grenade drop, and death. Victim deaths increment once; repeated damage to a dead actor is ignored. |
| `restock(actor,tick,authorized=false)` | Requires explicit true after objective/proximity validation. Fills health/reserve/block/grenades, preserves magazine as the source does. |
| `use_blocks(actor,tick,count=1)` | Call after successful coordinator reach/support/overlap/map validation. Charges stocks/cooldown; does not create blocks. |
| `recover_block(actor,tick)` | Call once after a validated recoverable source block destruction. Caps stock at 50. |
| `begin_cook` / `release_grenade(...,force_death=false)` | Normal cook readiness and release checks; forced release is reserved for the coordinator's death path. |

Returned event arrays, dictionaries and nested arrays are read-only owned copies. The common envelope is `{type,owner_id,spawn_generation,epoch,tick,action_sequence,actor_event_sequence,event_id}`. `event_id` is `epoch:actor:generation:ordinal`, suitable for merging predicted/confirmed effects. A returned shot contains weapon/profile/origin, cumulative pellet directions and recoil direction. `grenade_thrown` contains `position,native_velocity,fuse,cook_time,drop,team,cook_action_sequence,automatic`. Hurt/death contain attacker/cause/action attribution. The coordinator supplies a global event cursor, bounds queues and deduplicates authoritative actions; this module does not maintain a global damage/map history or infer attacker kills.

Death sets an authored local/server respawn eligibility of 180 ticks (`respawn_tick`). It never respawns automatically. Spawn protection, team changes, friendly fire, objective rules, ray/rewind hit resolution, block validation and grenade physics are coordinator responsibilities, not upstream-client server behavior.

`spread_from_samples` accepts six bounded float32 random samples per pellet and retains the unnormalized cumulative direction before normalizing each output. `spread_directions` uses an explicit injected RNG or the actor's stream; it never uses global randomness. `source_recoil` uses the source time-based triangular wave, vertical cap and crouch multiplier. These algorithms are deterministic under the pinned engine/runtime and shared inputs. Browser/native replay equality still requires an actual cross-runtime test.

Internal deadlines remain fractional ticks. Encode an active private deadline using `PlayerRules.deadline_tick(value)` (ceiling with a small representation tolerance); inactive reload is `0`. Do not replace internal fractional state with its integer wire representation: that loses SMG overshoot. The v1 owner snapshot needs a documented replay-state extension/reconstruction policy before exact reconciliation can be claimed. Reset/rebase counters before u32 exhaustion; there is no implicit wrap.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf`:

```powershell
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --editor --import --quit
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_player_rules.gd --verbose
```

Result: **144 assertions / 0 failures**, exit 0; no script errors, resource/ObjectDB leaks or settings writes. Fixtures cover two independent actors, copied replay state/RNG, original profiles/damage cutoff, fractional cadence, dry-fire edges, fast/shell reloads and interrupt boundary, native raising/sprint gates, depletion, class requests without live refills, authorized restock/build costs, spectator/dead/disconnected rejection, cook/death/repeated release, spade timers, sample/recoil numerical goldens, source motion modifiers, real shared-map collision, held jumping, stale input generations and duplicate/future tick rejection. `SourcePlayerMotion`'s separate 128 numerical cases remain required when that helper changes. No browser or two-client networking evidence is asserted by this suite.
