# Accepted iterations

## Iteration 1 — offline full port and test lab
Deliver a Godot project and browser build on GitHub Pages. Preserve the original client's gameplay presentation and features; implement local equivalents for behavior that previously required server messages. No server process, account or multiplayer connection is required to enter the lab.

Test lab acceptance:
- Switch rifle, SMG, shotgun, spade, block and grenade; exercise magazine/reload, recoil, spread, aiming and grenade timing.
- Switch both team appearances, inspect player models, third/first-person views, animations, spectator and dead states.
- Spawn targets/test soldiers; inspect damage, head/body/limb hits, death and respawn, unlimited resource options and reset state.
- Build/destroy blocks, lines, grenade craters and unsupported structures; test original maps and sample terrain.
- Exercise CTF/TC state, HUD/minimap/scoreboard/chat equivalents, controls, sound and settings in a local session.
- List verified features and explicit remaining deviations from v0.1.3. Prototype completion is not iteration completion.

Release gate: parser/import pass; gameplay and voxel checks pass; all iteration-1 parity rows VERIFIED or an explicit user-accepted replacement is recorded; release web export; browser interaction checks; published Pages URL checked.

## Iteration 2 — full multiplayer
Dedicated authoritative simulation, compatible browser transport, movement prediction/reconciliation/interpolation, validated shooting/block operations, map snapshot + ordered changes, joining mid-round, respawn/team/spectator, chat/scoreboard/CTF/TC, disconnect/reconnect and latency tests. Hosting the game simulation requires a server host separate from static GitHub Pages.

Old AoS server protocol compatibility is not required by the approved replacement-networking scope. If later requested, track it as additional work rather than silently replacing the chosen stack.

## Accepted gameplay replacement — 2026-10-11

The user explicitly removed automatic block regeneration. Surviving blocks retain
damage and darkening until an actual replacement or explicit map/round reset;
destroyed blocks remain air. Waiting, respawn and reconnect do not heal them.
This overrides OpenSpades' ten-second recovery in both iterations; see
[ADR0010](decisions/0010-persistent-block-damage.md).
