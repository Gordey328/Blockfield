# Persistent block damage — accepted replacement

The user's2026-10-11 instruction removes automatic block regeneration. OpenSpades
v0.1.3 `dcf449c845d509bbde9d79239b32d201c1389961` restores partial HP after ten
seconds; Blockfield deliberately replaces that behavior under
[ADR0010](decisions/0010-persistent-block-damage.md).

Surviving damage and half-RGB mesh color persist through idle time, respawn and
network reconnect. A later strike uses the existing HP. Destroyed cells remain
air. Same-RGB writes do nothing; genuine delete/place or recolor clears that cell's
damage. Explicit map/round resets and VXL reload start fresh state. Canonical RGB,
occupancy, colliders, minimap and VXL remain independent of damage tint.

## Implementation and handoff

- Gameplay specialist: `game/gameplay/player_controller.gd` and source fixture;
  removed expiry call/method/timestamp, retained real edit/reset cleanup.
- Simulation specialist: `game/simulation/match_simulation.gd` and match fixture;
  removed expiry sweep, supplied copied valid-cell damage mask and optional lean
  snapshot. Runtime does not copy private HP into20Hz wire state.
- Transfer specialist: MapTransfer, Replica, Runtime and transfer fixture;
  froze damage bits with canonical map at simulation tick, authenticated flagged
  BEGIN bytes, stripped flags during bounded decode and authenticated canonical
  END terrain. Existing loading event budget carries later partial hits before
  initial state; replacement fences filter stale hits. Tint-only catch-up avoids
  replaying historical effects/audio.
- Coordinator: Main adapter, compatibility, socket/browser fixture, docs and
  frozen release. Removed client expiry sweep, retained edit fences, installed
  baseline damage before live state. Mobile/grenade/scoreboard repairs retained.

Compatibility is network5 / authority5-no-block-regen; envelope version1 remains.
Previous recovering packages are incompatible and rejected during handshake.

## Verification and release

Pinned Godot4.7.2 `4.7.2.stable.official.ed1daf0bf`, Compatibility, single-threaded
Web. Frozen candidate `f0ddb456dbc73b70ccb63952c7895213392663b9` is under validation:

```text
python tools/release_checkpoint.py --revision f0ddb456dbc73b70ccb63952c7895213392663b9 --server
```

The initial isolated MatchSimulation check passed226 assertions /0 failures.
Full parser/registered behavioral checks, real authority/codec/socket/Main
damage+resume fixture, exported browser interaction, matching server export and
public artifact verification are pending; this record makes no release claim yet.

Unrelated effects/pooling work in another chat is excluded from this frozen
candidate. Physical-phone feel, public WSS hosting, Docker/Linux execution and
whole-port acceptance remain separate open checks. This change does not complete
either port iteration.
