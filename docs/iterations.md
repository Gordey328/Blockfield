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

## Accepted gameplay addition — 2026-10-11

The user requested offline team combat 3×3: one human and five bots. Add a separate
playable match with shared movement, shooting, damage and respawn rules, cover and
flanking behavior. Initial acceptance uses one authored compact arena; see
[ADR0020](decisions/0020-offline-team-bots.md). This addition does not replace the
full-port or multiplayer acceptance gates.

## Accepted presentation replacement — 2026-10-11

The user requested researching current shooter combat UI and modernizing the
boxy interface. Health/ammunition/resources, score and touch controls use the
authored modern treatment in [ADR0022](decisions/0022-modern-combat-ui.md).
Gameplay rules, input ownership and original feedback semantics retain their
existing acceptance requirements. This change does not accept the full port.

## Accepted mobile input addition — 2026-10-11

The user requests a thumb-oriented mobile combat layout and slight aim stickiness
on enemies. [ADR0023](decisions/0023-mobile-thumb-layout-and-aim-friction.md)
defines the asymmetric controls and optional touch-only gain reduction. This
explicit input adaptation retains authoritative weapon rules and desktop input.

## Accepted decorative effects replacement — 2026-10-11

The user replaces particle/casing collisions with collision-free presentation and
limits the whole decorative particle pool to50 simultaneously active particles.
Fresh important combat feedback has priority under saturation. Casings have simple
finite flight/fade; falling components use a bounded sampled group without impact
debris. Smaller visible counts and changed trajectories are accepted. Authoritative
unsupported-component removal, grenade rules, bullets, damage and map transactions
retain their contracts. See [ADR0025](decisions/0025-fixed-noncolliding-effects.md).
This replacement does not accept unrelated parity or the complete port.
