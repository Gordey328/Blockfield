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

## Accepted scope change — 2026-10-12

The user cancels iteration2 and requests removal of all multiplayer code after
the first game UI delivery. The accepted game is offline only: the lab, local
CTF/TC equivalents and one-human/five-bot TDM remain. Transport, dedicated server,
prediction, lag compensation, remote state/terrain replication, reconnect,
discovery and hosting are no longer requirements. This is explicit scope removal,
not deferred implementation or verified multiplayer. See
[ADR0031](decisions/0031-offline-only-game.md).

## Accepted gameplay replacement — 2026-10-11

The user explicitly removed automatic block regeneration. Surviving blocks retain
damage and darkening until an actual replacement or explicit map/round reset;
destroyed blocks remain air. Waiting and respawn do not heal them.
This overrides OpenSpades' ten-second recovery in the offline game; see
[ADR0010](decisions/0010-persistent-block-damage.md).

## Accepted gameplay addition — 2026-10-11

The user requested offline team combat 3×3: one human and five bots. Add a separate
playable match with shared movement, shooting, damage and respawn rules, cover and
flanking behavior. Initial acceptance uses one authored compact arena; see
[ADR0020](decisions/0020-offline-team-bots.md). This addition does not replace the
full offline-port acceptance gate.

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

## Accepted gameplay addition — 2026-10-12

The user requests offline zombie waves after completed multiplayer removal.
Survive a configurable duration then clear remaining enemies; waves may overlap
on a strict active-time schedule. Settings cover duration, quota and growth with
elapsed time. The latest same-day request replaces the easier-path policy with
a stable random detour/breach choice and requires reachable forward destruction
when the player stands too high, removal of retreat oscillation and less launch
stutter. Repeat deployed-browser and mobile-UI tests are explicitly declined for
this follow-up. See [ADR0033](decisions/0033-zombie-pursuit-and-startup.md).
This addition uses separate survival round rules and does not
accept the full port. See [ADR0032](decisions/0032-timed-zombie-survival.md) and
[the design and confirmed answers](zombie-waves-plan.md).
