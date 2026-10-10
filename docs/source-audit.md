# Pinned source audit and port contracts

OpenSpades `v0.1.3` at `dcf449c845d509bbde9d79239b32d201c1389961`, source audit 2026-10-10. [Original checkout](https://github.com/yvt/openspades/tree/dcf449c845d509bbde9d79239b32d201c1389961). The feature acceptance ledger is [parity.md](parity.md). This document records facts from source, not implemented port behavior.

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

The audit is static. It has not measured frame rate, browser limits, original appearance/sound timings or Godot parity. Those require a runnable original reference and recorded playtests.

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

Explicit remaining differences: the player uses Godot's full box collision solver with conservative standing clearance instead of the original sparse voxel samples. The collider dimensions and eye offsets use the source dimensions above, and the aerial feet shift is preserved. Water friction uses the original factor, but activation compares Godot feet to `world.water_level+0.5`; this accounts for retained solid-bottom collision and is an adaptation of the original eye-origin/source-z tests. The lab intro tracks an intro state but keeps its authored starting view; it does not recreate the original title-map camera placement. Local test targets provide a stored yaw/pitch defaulting to zero instead of live network orientation. The lab permits third-person presentation with several test targets. Server-side fall/grenade/melee damage and respawn rules remain the authored offline policy already documented above.
