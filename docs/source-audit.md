# Pinned source audit and port contracts

OpenSpades `v0.1.3` at `dcf449c845d509bbde9d79239b32d201c1389961`, source audit 2026-10-10. [Original checkout](https://github.com/yvt/openspades/tree/dcf449c845d509bbde9d79239b32d201c1389961). The feature acceptance ledger is [parity.md](parity.md). Source facts and measured Godot subsystem behavior are recorded separately; neither is a blanket feature-acceptance claim.

## Findings that determine architecture

1. OpenSpades is a client. It computes presentation, movement, hit candidates and block health, but health changes, death/respawn, replenishment, CTF pickup/capture/win and TC capture/win arrive through `Sources/Client/NetClient.cpp`. There is no complete offline game server to translate. Iteration 1 needs a **local authority** behind the same gameplay contracts that the network authority will implement in iteration 2.
2. There are three firearms, four tool slots, two combat teams and a spectator team. The source has one articulated soldier model with team tint, pose and held-tool differences; it has no selectable hero/class roster. `LimboView.cpp` selects a team and one of Rifle/SMG/Shotgun. “All characters” therefore means all original team appearances and visible player states.
3. Protocol selection changes weapon timing/ammo/recoil/spread. The offline testing mode should expose 0.75 and 0.76 profiles. Otherwise a port can look complete while changing the actual weapon balance.
4. Gameplay emits `IWorldListener` events for audiovisual effects and local actions. Preserve a similarly separate event boundary in Godot: simulation should not directly own UI/audio/particles. `World::Advance` applies queued voxel actions, updates players, restores damaged blocks, updates grenades, then advances time.
5. Resource skins and GUI are AngelScript, not C++. Original `.as` cannot run as GDScript. Skin scripts are valuable behavioral specifications: ports must recreate their first/third-person animation/audio events. Models are voxel KV6 and maps are VXL; both require conversion/import support.

## Weapon constants

Source: [`Sources/Client/Weapon.cpp`](https://github.com/yvt/openspades/blob/dcf449c845d509bbde9d79239b32d201c1389961/Sources/Client/Weapon.cpp), `RifleWeapon3/SMGWeapon3/ShotgunWeapon3` = protocol 0.75; suffix `4` = 0.76. Stock excludes loaded clip. Spread is applied as a triangular random addition on each direction component; shotgun direction accumulates per pellet before normalization (`Player.cpp:568`). This is not simply a random circular cone.

| Profile | Weapon | Shot interval s | Clip / stock | Reload s | Spread | Recoil x/y/z | Pellets |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: |
| 0.75 | Rifle | 0.50 | 10 / 50 | 2.50 magazine | 0.012 | 0.025 / 0.05 / 0 | 1 |
| 0.75 | SMG | 0.11 | 30 / 120 | 2.50 magazine | 0.025 | 0.01 / 0.0125 / 0 | 1 |
| 0.75 | Shotgun | 1.00 | 6 / 48 | 0.50 per shell | 0.024 | 0.05 / 0.1 / 0 | 8 |
| 0.76 | Rifle | 0.60 | 8 / 48 | 2.50 magazine | 0.004 | 0.0001 / 0.075 / 0 | 1 |
| 0.76 | SMG | 0.10 | 30 / 150 | 2.50 magazine | 0.012 | 0.00005 / 0.0125 / 0 | 1 |
| 0.76 | Shotgun | 0.80 | 8 / 48 | 0.40 per shell | 0.036 | 0.0002 / 0.075 / 0 | 8 |

| Weapon | Torso | Head | Arms | Legs | Block 0.75 / 0.76 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rifle | 49 | 100 | 33 | 33 | 50 / 50 |
| SMG | 29 | 75 | 18 | 18 | 35 / 34 |
| Shotgun, each pellet | 27 | 37 | 16 | 16 | 34 / 34 |

These player-damage numbers are stored in the **client** but actual multiplayer damage is server-decided. In 0.76 the source comments explicitly retain 0.75 player damage. Shotgun block damage is called a guess. Use these as the pinned offline baseline and document subsequent server evidence rather than claim exact authoritative Ace of Spades server parity from this repository alone.

Firing applies damage only within 128 blocks of horizontal distance; map raycasting may scan farther. ADS halves spread. Crouching halves recoil. Gun cadence uses a next-shot clock, can fire while a slow shotgun reload is active, then interrupts that reload. Empty magazine dry-fire emits one event per held trigger sequence. Magazine reload consumption is confirmed externally for the local original client; the Godot local authority must provide completion deterministically.

## Player, tools and grenades

Sources: `Player.cpp`, `Player.h`, `PhysicsConstants.h`, `Grenade.cpp`.

- Spawn/resupply defaults: 100 HP, 3 grenades, 50 blocks; gun clip and stock use the selected profile. Player name in original preferences is limited to 15 ASCII characters; Unicode compatibility has a separate setting/packet path.
- Tool IDs: spade 0, block 1, weapon 2, grenade 3. Weapon IDs: rifle 0, SMG 1, shotgun 2. Team IDs 0/1 are active; ≥2 is spectator.
- Tool primary intervals: block 0.5 s, spade 0.2 s, grenade 0.5 s. Spade secondary dig starts after 1.0 s and repeats every 1.0 s. Spade damages blocks by 55 per primary strike; melee reports a `HitTypeMelee` event, so player melee damage is absent from the client authority.
- Build/dig eligibility uses Chebyshev distance from eye to candidate cell center `<3`, not a 6 m Euclidean sphere. Build rays scan up to 12 cells; placement requires adjacency, no player overlap, z in 0..61 and stock. Drag-line checks up to 256 cells then uses available stock; server-applied block lines are capped at 50.
- Single spade destruction returns one block up to stock cap. Secondary dig removes target and vertical neighbors (3 cells), does not use the same stock-return path. Grenade block action removes a 3×3×3 cube.
- While jumping, failed placement due to player overlap can be queued until overlap clears; cancel when grounded or stock becomes empty.
- Grenade pin pull minimum 0.15 s; total fuse 3.0 s; forced throw after 2.9 s; next throw cooldown 0.5 s. Throw velocity is forward unit vector plus player simulation velocity; death drops a cooked grenade rather than throwing it. The client does not contain the authoritative grenade damage formula.
- Grenade simulation uses `position += velocity * dt * 32`, `velocity.z += dt`; collision reflects the impacted velocity component and multiplies the entire velocity by 0.36. Bounce sound threshold is 0.1; crossing source z=63 emits water-entry event.
- Original coordinate system is x/y horizontal and **positive z downward**. Convert at a single boundary to Godot y-up; keep VXL cell coordinates explicit. Do not apply a naïve sign change inconsistently to models, hit boxes, physics and map data.
- Player horizontal half-width is 0.45 blocks. Crouch shifts position 0.9. Collision vertical samples and automatic step-up are in `BoxClipMove`; Godot's default capsule/step behavior is not exact parity.
- `BoxClipMove` samples a standing body with feet 2.25 below the eye and head 0.45 above it (2.7 total); crouched feet are 1.35 below the eye with the same upper offset (1.8 total). `SetInput` shifts the eye 0.9 only while grounded. Airborne crouch preserves the eye and raises the feet; airborne uncrouch first checks whether the feet can be lowered (`TryUncrouch`).
- Physics velocity is scaled by 32 for displacement. Jump sets source z velocity -0.36 (11.52 blocks/s upward displacement rate). Gravity adds dt, then air friction divides by `1+dt`; ground horizontal friction divides by `1+4dt`; water uses `1+6dt`. Movement acceleration multipliers: air 0.1, crouch 0.3, sneak/ADS 0.5, sprint 1.3. Diagonal input divides acceleration by √2. Looking beyond source vertical component 0.65 slows forward movement, reaching 90% slowdown when looking straight up/down.
- Auto step-up requires standing, view z<0.5 and not sprinting; raises player by one block and halves horizontal velocity. Original collision is sample-based voxel clipping, not a capsule.
- Fall slowdown threshold 0.24 and hurt threshold 0.58 in original velocity units. `FALL_DAMAGE_SCALAR=4096` is declared, but `MovePlayer` only emits `PlayerLanded(hurt)` and HP is server-supplied. Do not infer a complete damage formula from the scalar alone.
- Distinct oriented head, torso, two legs and arms hit volumes are constructed separately for standing/crouching in `Player.cpp:1316`; model geometry alone is not an acceptable replacement for hit-zone verification.

## Voxel world

Sources: `GameMap.h/cpp`, `GameMapWrapper.cpp`, `World.cpp`, `FallingBlock.cpp`.

- Fixed original dimensions 512×512×64. Solid occupancy is a 64-bit column mask; packed color uses low 24 bits RGB and high byte as health. Loaded/created solid cells initialize health to 100.
- VXL is a column-span format. Loader fills solid interior using neighboring colors, rather than merely creating surface voxels. Keep all occupied cells for edit/collision semantics; mesh only exposed faces.
- Damaged surviving blocks recover to health 100 after 10 seconds from latest damage; queue entry is refreshed by another hit. Created/destroyed actions queue before the next world simulation step.
- Direct weapon/spade interaction refuses damage to z=62/63. `World::DestroyBlock` permits a single requested cell through z=62 but multi-cell dig/grenade rejects z≥62; this reflects confirmed server actions and differs from local input checks. Preserve the distinction or record an intentional simplification.
- `ClipBox` treats outside horizontal map as solid; above the map z<0 as empty; z=63 aliases z=62; z≥64 is solid. `ClipWorld` treats outside horizontal map as empty and has different bottom behavior. This matters for player versus projectile boundary checks.
- Map reads can wrap horizontal coordinates with bit masks. Do not make Godot player traversal wrap around just because data lookups can wrap.
- `GameMapWrapper` maintains connectivity; removal may detach more than explicitly requested cells. `World` groups detached cells into connected clusters and emits `BlocksFell`. Falling cluster presentation is separate from voxel occupancy.
- Authentic VXL load, save-after-edits, cube-line determinism, chunk seam edits, block recovery and support removal need separate fixtures. A procedural small arena verifies none of the genuine-map contract by itself.

## Match rules and authority interface

Only two native modes exist (`IGameMode.h`): CTF=0 and TC=1. Server-specific custom modes are represented through one of those packet formats and server text; there is no additional native TDM/arena mode in this client.

CTF state: team scores, capture limit, whether team has enemy intel, carrier player ID, loose intel position and team base position. Client receives pickup/drop/capture; capture adds one team score and 10 displayed player kills; winner flag arrives separately in capture packet. The client does not implement authoritative pickup radius, capture validation, score reset or respawn selection.

TC state: territory position, owner team (2=neutral), capturing team (-1=none), progress baseline/rate/start time. Displayed progress is `clamp(base + rate*(world_time-start),0,1)`. Progress packet rate is signed byte ×0.05. `TC_CAPTURE_DISTANCE=16` exists in constants for UI eligibility; capture/win events are server-decided.

Recommended stable boundary for local/network authority: submit player input/tool actions; authoritative events for spawn, hurt/kill/respawn, ammo/reload/restock, block edit batch/cluster removal, grenade spawn/explosion, objective state, score and round reset. A local testing session should route through this boundary rather than bypass its mechanics with debug-only scripts.

## Presentation and extensions

- `ClientPlayer.cpp` drives articulated soldier pieces (`Arm`, `UpperArm`, `Arms`, `Head`, `Leg`, `LegCrouch`, `Torso`, `TorsoCrouch`, `Dead`) and first/third-person skins for all six weapon/tool visual families. Team tint comes from `World::Team.color`.
- `Resources/Scripts/Skin/` defines firing/reload/sprint/aim/switch animations and sounds. `Resources/Scripts/Reference/Skin/` defines the public extension interfaces; `Reference` files are declarations for documentation and are not intended to compile.
- GUI uses AngelScript: startup graphics/audio/general settings, main screen/server list/profile, pause/chat/preferences. Skin and GUI code must be translated into Godot behavior, not merely copied into assets.
- Controls default to WASD, space jump, Ctrl crouch, Shift sprint, V sneak, mouse fire/alternate, 1–4 tools, R reload, E eyedropper, M minimap scale, N full map, Tab scoreboard, L limbo, T/Y chat, H log, F spectator/dead flashlight, 0 screenshot, 9 sceneshot, 8 save map.
- Graphics baseline includes voxel world lighting/fog, models, water, dynamic lights/shadows and optional GI/HDR/post-process. Godot Compatibility/browser adaptations must be listed individually; default Godot material rendering is not a claim of full visual equality.
- Original resource packages can override files through virtual filesystem precedence. The port needs a documented replacement contract for resource/skin extensions; retaining arbitrary AngelScript execution is a separate implementation decision.
- Code headers say GPL-3.0-or-later. Original build instructions separately download a `Nonfree` asset pack. Track per-resource provenance and actual redistribution terms in the resource inventory; copying code license to all third-party assets would be incorrect.

## Unknowns requiring explicit evidence

Exact authoritative melee/grenade/fall damage, pickup/capture/resupply distances, respawn placement and full server-specific behavior are not implemented in this repository. Freeze documented offline rules and validate them against a selected server implementation or captured original match if exact compatibility is required. New backend selection is authorized, but those rules must remain named/visible in the feature ledger.

Initial `LocalSession` offline policy is explicit: melee 100 damage inside 3 blocks, 3-second player/target respawn, CTF pickup/base resupply radius 2 blocks, and grenade maximum 100 with quadratic falloff inside radius 16. TC uses original 0.05 display rate per net nearby player and 16-block radius, adding local contested/capture/win decisions that the client previously received from a server. These are authored offline rules pending authoritative reference verification; they are not claimed to be recovered server constants. The session exposes grenade spawn/explosion events and needs world-side projectile motion and occlusion.

The initial source inspection was static. Subsequent behavioral checks below compare selected formulas and contracts against running Godot code. Frame rate, browser limits and original appearance/sound timing still require separate reference and browser playtests.

## Movement, input and camera source contracts

Pinned sources: `Client_Input.cpp:49,161-198,325-370,435,513,576`, `Client_Scene.cpp:54,120,287`, `Client_Update.cpp:279,610,647`, `ClientPlayer.cpp:330` and `Player.cpp:100,978,991,1213`.

- ADS defaults to toggle (`cg_holdAimDownSight=0`); pressing alternate fire toggles only while the gun is not reloading. Hold mode directly follows the button. Source ADS animation rises by 8×dt and falls by 3×dt.
- At normalized ADS state a, zoom is `1+(3-2*a^1.5)*a^3*d`, with rifle d=1.4, SMG d=0.8, shotgun d=0.4. At full ADS these are 2.4×, 1.8× and 1.4×. Vertical field of view is transformed through its tangent, rather than multiplied by a constant.
- First-person mouse motion divides by zoom, applies normalized radial magnitude raised to `mouseExpPower/2-1/2`, applies `zoomedMouseSensScale^ADSState`, then source sensitivity and 0.003 radians/pixel. Invalid exponent resets to 1. Inversion flips vertical mouse motion. First-person following ignores mouse orientation; free/death/follow orbit uses fixed 0.003 radians/pixel and ±0.45π pitch limit.
- Wheel-up cycles spade→block→gun→grenade; wheel-down reverses this and both skip depleted tools. A negative wheel setting reverses direction, zero disables switching. Last-tool selection is available but unbound by default in the original.
- Empty held fire emits a dry-fire event once on entering that state; releasing and pressing again emits another. Footstep distance uses `moveDistance += horizontal_distance*0.3`, emitting each time it crosses 1. Wade uses its own sound bank; sprint additionally plays a run sound.
- A living active player uses first person, or third person when enabled in a one-player original match. An unjoined original client has a separate intro view. Death uses a corpse-centered orbit; spectator uses a free camera. Following can switch first/third person with jump and spectator reload returns to free camera. Dead-player follow begins after 1.3 seconds and restricts targets to the same team; spectator can follow either team.
- Third-person distance is 5 blocks. Death distance starts at 2 and approaches 5 as `5-3*exp(-elapsed)`. A voxel ray shortens the camera distance by a 0.3 near-plane margin. Free camera damps velocity by `0.3^dt`, accelerates by 10×dt (sprint ×3), checks 27 offset voxel rays, and reflects collision normal velocity with coefficient 1.2.

Port evidence on 2026-10-10: `game/gameplay/player_controller.gd` implements these input/state/camera contracts and integrates the source-derived presentation effects. `tests/integration/test_lab.gd` drives the actual scene, input, collider, authority and ray hits: 94 assertions, zero failures on Godot 4.7.2, with no runtime errors or shutdown leaks in the verbose run (`.cache/logs/controller-integration.log`). Run with `--headless --path game --script ../tests/integration/test_lab.gd --verbose`. Scenario-completion assertions prevent an aborted coroutine from silently reporting success; settings are restored after the test. This is behavioral subsystem evidence, not original-client visual or browser acceptance.

Subsequent movement integration replaces the previous Godot full-box solver, conservative standing clearance and feet-based water eligibility with `SourcePlayerMotion`; see the module handoff below for separate helper and scene evidence. Explicit remaining differences: the lab intro tracks an intro state but keeps its authored starting view; it does not recreate the original title-map camera placement. Local test targets provide a stored yaw/pitch defaulting to zero instead of live network orientation. The lab permits third-person presentation with several test targets. Server-side fall/grenade/melee damage and respawn rules remain the authored offline policy already documented above. Original-client and browser movement/camera comparison remains required.

## Acceptance audit: movement, combat, tools and reset

2026-10-10 follow-up audit covered P01–P16, W03–W07, M01–M04 and T02–T05 against the pinned source and current controller/session/main. It identified and corrected behavior that the previous basic scene tests did not exercise. Corrections live in coordinator-owned gameplay code; the independent regression suite is `tests/gameplay/test_source_parity.gd`.

| Source contract | Code / behavioral evidence |
| --- | --- |
| Jump is assigned before gravity/friction (`Player.cpp:1109–1155`). At 60 Hz the first upward velocity is `32*(.36-1/60)/(1+1/60)`, rather than 11.52. Ground/air acceleration and friction retain the source recurrence. | `BlockfieldPlayer._physics_process`; actual grounded jump plus walking/sprint/crouch/sneak/air velocity fixtures. |
| Recoil adds source up/right vectors, limits upward kick, normalizes orientation and uses a triangular wave at `world_time*.9788` (`Player.cpp:759–784`). Crouch halves both components; recoil consumes no random draw. | `BlockfieldPlayer.source_recoil`; phase 0/.25/.5/.75/1, crouch, near-vertical clamp and RNG-preservation fixtures. |
| Held fire accumulates its next deadline rather than resetting it each frame (`Weapon.cpp:86–111`). Releasing/repressing clamps stale deadline debt. An empty held shotgun trigger aborts shell reload before a shell is loaded. | `LocalSession.set_trigger_held`; all six profile/weapon combinations with fixed and irregular ticks, bounded one-tick deadline drift, idle trigger reset and empty-shotgun interruption. Shot counts allow one event at a floating-point boundary; accumulated drift must remain within one tick. |
| Firearm volumes are oriented head, torso, two separated legs and one broad arm box, with distinct crouch dimensions and head pitch pivots (`Player.cpp:1316–1385`). FireWeapon tests head→torso→legs→arms and compares horizontal distance strictly (`Player.cpp:592–628`), retaining earlier part on ties. | `LabHitVolumes`, `LabSoldier`, controller analytical target rays; original numeric centers/sizes, narrow leg gap, crouch legs, broad-arm/torso priority, pitch/yaw and vertical tie fixtures. Actual scene shot confirms voxel cover and head damage. Model head center and source eye/hit-box center are intentionally distinct. |
| Tool change clears drag/cursor/held grenade, aborts reload and weapon input (`Player.cpp:307–326`). Cancelled cooking does not throw/decrement stock. Depletion clears held triggers and selects the previous available tool (`Client_Update.cpp:468–486`). | `LocalSession.select_tool`, controller selection/depletion; magazine/shell interruption, cooked and pin-delay cancellation, depleted block/firearm/grenade and rejected depleted last-tool fixtures. |
| Placement overlap uses the eye-down box of height1.75 standing/.85 crouched, horizontal width.9 (`Player.cpp:1414–1435`); it is separate from the movement collider. Pending placement checks range again and cancels on landing or empty stock (`Player.cpp:438–464`). | Controller build validation; below-feet/above-eye/standing/crouch fixtures, airborne overlap queue, out-of-range pending rejection and permanent stock-depletion cancellation before later restock. |
| Integer cube-line crossing signs use native Z-down before conversion (`World.cpp:405–430`). Initial odd half-crossings differ by direction. Already-solid line cells retain their colors because `NetClient.cpp:1178–1186` filters them before creation; `World::ApplyBlockActions` alone is insufficient evidence for this packet path. | Controller `_cube_line`; forward/reversed golden odd-crossing prefixes. Existing actual-scene integration covers atomic line stock deduction and created cells. |
| Primary/secondary spade block reach uses `hitBlock+normal` (`Player.cpp:831,905`). Player melee selects the first living non-spectator within eye Chebyshev<3 and broad view ratio<5, using approximate ray rejection and preceding the map action (`Player.cpp:873–903`). The client does not supply melee damage authority. | Controller adjacent-cell reach and broad melee selection; off-axis target beyond3m Euclidean, exact Chebyshev boundary and player-before-map fixtures. Offline100HP damage remains authored policy. |
| Surviving damaged blocks regenerate100HP ten seconds after the latest hit (`World.cpp:96–115,191–205`); another hit refreshes the deadline and external voxel replacement invalidates stale damage. | Actual voxel occupancy checks after timed damage/recovery/replacement, without asserting a private health dictionary. |
| Full match reset restores the current imported VXL baseline and actor/resource/objective state. This is local-authority behavior replacing server map/reset events (`NetClient.cpp:1348`). | Actual scene encode/imported-baseline reset, damaged terrain restoration, CTF score/carrier/winner/resources/projectile cleanup and TC neutral/progress/contested cleanup. The test exposed untracked extra authorities surviving reset; main now clears them before rebuilding lab targets. |

Command: `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/gameplay/test_source_parity.gd --verbose`. Result: **142 assertions, 0 failures**, `.cache/logs/source-parity.log`; independently reproduced by the coordinator. No script errors, runtime errors or shutdown leaks in that run. Pure and asynchronous scenarios must reach completion to count as successful. Tests restore the prior settings bytes. This is targeted source-contract evidence, not full P/W/M/T row acceptance.

### Remaining acceptance limits

- P01–P03: `SourcePlayerMotion` now implements the native corner collision/step/uncrouch/eye/wade algorithms and is integrated into the controller. Isolated terrain evidence and repeated actual-scene jump/friction/combat/build/reset checks are described below. Dedicated scene/browser stair, uncrouch, water and camera reference acceptance remains required; the existing checks do not accept the entire movement rows.
- P06/P07/P12/P15 and T03: model/viewmodel/corpse/animation/effect implementations have their own presentation and GPU tests in assets.md. Those need complete reference/browser review; this gameplay suite does not certify original audiovisual equality. First-person eye-matrix sway/bob and camera behavior must be reviewed separately from authoritative aim rays.
- P08–P13: source constants are tested, and shotgun uses cumulative unnormalized triangular spread. A seeded shot-spread trace independent of presentation RNG, repeated actual-hit spread/ADS fixtures and multi-target/voxel boundary cases are still missing. Newly implemented source recoil/cadence/hit zones must also be exercised in the deployed build.
- W03–W07: basic single/line building, delay, stock, geometry and recovery now have source cases. Complete cube-line direction/tie corpus, occupied-line color retention, native adjacent-face reach boundaries and invalid drag starts still need focused acceptance. Native64-color palette/arrow controls and actual eyedropper synchronization are implemented/tested separately in ui.md.
- P05/P16/T02–T05: integer teams, weapon/tool switching and profile selection have scene evidence. Names/colors supplied through match state and actual stationary/moving spawn controls were added after this audit and have UI-specific checks; see ui.md. Test-lab same-weapon selection intentionally restocks through the lab selection API, whereas native `Player::SetWeaponType` returns immediately when the type is unchanged (`Player.cpp:1387`).
- M01–M04: imported-map reset is behaviorally checked. Capture/pickup/resupply radii, local objective authority, damage authority and respawn remain the explicitly authored replacement in [ADR0002](decisions/0002-offline-authority.md). Native client packets do not supply missing server validation rules. Six default lab targets are a testing roster with mixed poses, not combat AI.
- Original native reference sessions and browser acceptance remain required. Keep the feature ledger unaccepted where a full row still has an unverified requirement or a replacement without recorded acceptance.

## Native player collision module handoff

`game/gameplay/source_player_motion.gd` provides a typed `SourcePlayerMotion.State` and pure operations over real `VoxelWorld` occupancy. Sources are `Player.cpp:100–113` (`SetInput`), `978–1093` (`GetWade`, `GetOrigin`, `BoxClipMove`), `1095–1097` (ground eligibility), `1169–1188` (landing slowdown/events), `1213–1248` (`TryUncrouch`, `RepositionPlayer`), `Client_Update.cpp:408–414` (local uncrouch call) and `GameMap.cpp:162–175,195–199` (point clipping). The implementation is derived from GPL-3.0-or-later source.

The state uses **Godot world axes** throughout its public interface. `feet_position` is the physical foot anchor, `native_velocity` is the velocity before multiplication by32, and `physics_eye()` derives the unsmoothed source `position`: feet+2.25 standing or feet+1.35 crouched. `eye_position` is the separately smoothed view point. `front` supplies the original strict step eligibility condition, `-front.y<.5`; `sprint` and `crouch` supply its other gates. `grounded` is the inverse of source `airborne`. `last_climb_time` starts at-100, matching the constructor. Inputs/state are copied, so a query never mutates caller state accidentally.

Integration order:

1. Apply `set_crouch(world,state,wanted)` before movement acceleration. It performs native `TryUncrouch(false)` gating followed by `SetInput` feet/eye behavior.
2. Use the existing source acceleration, jump, gravity and friction recurrence in the controller. Physical water friction must use **state.wading from the previous contact**, rather than visual `get_wade` or the old feet threshold.
3. Save incoming downward speed `-state.native_velocity.y`; call `clip_move(world,state,dt,time)`. This operation performs only native `BoxClipMove` and `RepositionPlayer`, without acceleration, gravity, friction, footstep accumulation or fall slowdown.
4. Call `finish_landing(clipped,incoming_down_speed)` once. It halves horizontal velocity above the native strict.24 threshold and reports `landed`, `fall_hurt` and `fall_speed`. HP damage remains the documented authored offline authority.
5. Set the actor position from `feet_position`, native velocity from the result, and camera eye from `eye_position`. Use returned `grounded` for movement/tool eligibility rather than CharacterBody3D's previous contacts. `is_on_ground_or_wade` additionally tests the native vertical-speed interval `[0,.017)`.
6. Presentation/audio wading comes from `get_wade(world,state)`, which tests the smoothed eye-derived origin separately. Keep the physical flag distinct; it persists in flight and changes only at a downward collision.

Source details retained intentionally:

- X is clipped first, then native Y/Godot Z probes use updated X. A successful X climb followed by blocked Y retains Y velocity; both horizontal components are then halved.
- Horizontal and vertical collisions use destination corner samples. A blocked component retains its previous position, with no surface snapping or boundary clamp. A sufficiently large tick can cross an intervening thin wall; a swept box would produce different behavior. The helper does not add substeps silently.
- Raised step probes permit one block only while standing, not sprinting, and with native view-z<.5. A climb skips vertical displacement that tick and starts an eye offset of one block that recovers linearly over.25s.
- Native `floor(Z)` is applied **before** vertical reflection. A Godot point on an integer horizontal voxel face addresses the lower cell (`ceil(Y)-1`), unlike the existing generic `world.clip_box` floor(Y) query. Native z63 aliases z62; native z64 is solid. This distinction is covered by exact-plane/epsilon fixtures.
- Ground crouch keeps the feet fixed and lowers the physical eye. Air crouch keeps the physical eye fixed and raises the feet. `TryUncrouch` first tries lowering feet when airborne, then checks four head corners. The original local client calls it with `move=false`; even a head-clear fallback does not perform the optional.9 position shift. The standalone `move=true` branch is available and tested separately.
- Physical wade is assigned on downward contact using the **old unsmoothed eye**, native position.z>61. Rendering `GetWade` instead uses smoothed eye+(.9 standing/.45 crouched)+.3, native origin.z>62. They can disagree without being an error.
- Scalar intermediates in the clipping/sample loop are rounded through the standard Godot Vector3 binary32 representation to retain native C++ float branch behavior. This does not claim a bit-for-bit capture of an original native executable.

`tests/gameplay/test_source_motion.gd` passes **128 assertions, 0 failures** on Godot4.7.2; `.cache/logs/source-motion.log` is clean of script/runtime errors and shutdown leaks. Reproduce with `.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/gameplay/test_source_motion.gd --verbose`. Parser/import also passes (`.cache/logs/motion-import.log`). Cases cover real voxel integer-face/boundary/water alias queries, scaled free flight, large-tick crossing, axis-order sliding, floor/ceiling contact, both-axis steps and strict gates, climb eye timing, ground/air crouch, both uncrouch branches and blocked diagonal corners, physical/render wade divergence and stale-state clearing, strict fall thresholds, a200-tick step/fall walk and100 grounded crouch transitions. Every scenario must reach completion. These checks neither load the main scene nor alter user settings.

The coordinator integrated this helper into `BlockfieldPlayer._physics_process/_clip_motion`, with `is_grounded()` as the source contact flag. `tests/gameplay/test_source_parity.gd` now uses this public flag. Its friction fixture spawns above the surface and waits up to60frames for two consecutive source contacts, rather than assuming Godot's floor cache after three frames on an integer voxel face. The independent velocity expectations are unchanged. The updated actual-scene suite passes **146 assertions, 0 failures**, clean verbose `.cache/logs/source-parity-motion.log`, including the coordinator's added ray cases; it exercises jump/friction, combat, building and match reset after solver integration.

Limits at handoff: dedicated actual-scene stair/uncrouch/water/camera scenarios, original native reference play and exported-browser movement acceptance remain pending. The helper uses actual map width/depth/height for the authored lab; above64 geometry is an explicit lab extension. On a native512×64×512 map its point-boundary contract matches the original fixed dimensions. Offline fall HP remains [ADR0002](decisions/0002-offline-authority.md). No P01/P02/P03 whole-row acceptance is asserted by these targeted suites.
