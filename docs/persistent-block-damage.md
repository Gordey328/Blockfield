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
Web. Final frozen source `4c051639e286b3ea4945c77cfa6d568c36bf39be` preserves the
committed effects repair16f1e70 and all mobile/grenade/scoreboard changes.

All81 registered behavioral/latency checks are covered on this same frozen source.
Parser/import, Controller194/0, MatchSimulation226/0, MapTransfer1186/0,
Runtime223/0, HitHistory352/0, rewind441/0, mesh damage31/0, real
Runtime/codec/sockets/Main damage42/0, Main/HUD119/0, mobile controls2381/0,
touch-look144/0 and shaped native TCP458/0 passed. The socket fixture waits beyond
660 authority ticks, checks retained25HP and original RGB, reconnects the same
owner into a damage-flagged baseline, applies a later hit during loading, destroys
using retained HP and verifies same-color recreation/recolor/stale-event guards.

Validation is a recorded same-revision chain, not an uninterrupted first pass:

- f0ddb456dbc7 stopped at MapTransfer1171/1: newly added source-event fixtures lacked
  mandatory actor ordinal. a14b26f corrected only fixtures/docs and passed1186/0.
- a14 suffix exposed Runtime223/1: removing the authority `data.last_tick` clock
  invalidated HitHistory.4c05163 restores that existing contract; subsequent
  Runtime/history/rewind/socket tests all pass.
- First4c cold import exited nonzero without an explicit error line; its log is
  preserved as `import-initial-failed.log`. Repeated import passed.
- First4c controller run failed1351/3 at grenade preparation/release while browser
  testing was concurrent. Unchanged isolated repeat passed511/0. Preserve
  `test-network-controller.log` and `test-network-controller-repeat.log`; do not
  infer that the transient pacing issue was fixed in production.
- The completed prefix was retained on the same immutable4c source, followed by
  every remaining registered test, latency, runtime/launcher and exports. Exact
  command/log hashes are in `.cache/release-4c051639e286/.cache/validation-manifest.json`.

Reproducible standard entry point in a clean checkout:

```text
python tools/release_checkpoint.py --revision 4c051639e286b3ea4945c77cfa6d568c36bf39be --server
python tools/browser_fidelity_probe.py --release .cache/release-4c051639e286
```

The actual exported Main test scene passed11 checks /0 failures: a real rifle shot
keeps canonical RGB while darkening; after12.142s it stays damaged; the second shot
uses retained damage to destroy it; after another12.009s it stays air; explicit
same-color replacement starts healthy. Four grenade-edge/cooldown checks and both
scoreboard preference modes also passed. Fixture SHA256:
`b74c84b163b96b4abdc8c81f23c208d9750b0eddb80ec04f7c269e164812b016`.
Evidence: `.cache/previews/persistent-browser/{healthy,damaged,destroyed,block-complete,scoreboard-on,scoreboard-off}.png`
and timestamped `web-log.json`. The after12s persistence is confirmed by the timed
Web check; the damaged screenshot captures the initial damaged state, not a later
frame. One Chromium `UnknownError` occurred at initial probe startup; interaction
and all11 checks completed. No full browser-input acceptance is inferred from it.

Parser/import, native runtime/launcher, Web export, Linux server export and
exported-PCK Title launcher smoke passed. The PCK smoke uses the Windows host
engine and does not execute the Linux binary.

Normal local export: menu/start, mobile panel, keyboard weapon/grenade selection,
drag-look and original Title.vxl loading/rendering were exercised. Public Pages:
menu/start, real3D lab, keyboard grenade selection and drag-look were exercised.
Both preserve existing preferences; physical touch/phone feel remain unverified.
The public browser also logged the initial Chromium UnknownError; subsequent
interaction worked, and no Godot script error was observed. Full pointer-capture
acceptance remains open. Screenshots: `production-local.png`, `production-title.png`
and `production-public.png`; public browser log: `public-errors.json` in the same
preview directory. The test-only fidelity scene is excluded from production.

[Pages development build](https://gordey328.github.io/Blockfield/) serves clean
source4c051639e286, bundle `db3932405f3f07217f83b6ca844286af71eed02e`.
Public metadata matches that source; independent public downloads equal local
HTML5568bytes SHA256 `ab716cba3f68e75c1c99a2ed48aca9945fccef500a37d29017a826e9ebcb7e5e`
and PCK16,180,848bytes SHA256 `10be980d25073beab27914f28c6a709d4fea4fa4f571165d9dc96fa46437f518`.
Report: `.cache/previews/public-persistent-4c051639e286.json`.

[Matching server development package](https://github.com/Gordey328/Blockfield/releases/tag/godot-4c051639e286)
was independently publicly downloaded and hash-verified:29,335,660bytes, SHA256
`eb6997de1cd726068fa31acd2ec4a2209138aab4a5b34e86b36805bbdf43241f`.
Commands: `python tools/package_server.py --source .cache/release-4c051639e286`,
`python tools/publish_server_release.py --package build/packages/blockfield-server-4c051639e286.zip`,
`python tools/publish_pages.py`. Initial Pages metadata still showed dcee15f;
verification was repeated after deployment and passed. Deployment/preparation
scope remains unchanged; no server host/domain was selected or created.

Physical-phone feel, public WSS hosting, Docker/Linux execution and whole-port
acceptance remain open. This change does not complete either port iteration.
All specialist handoffs and coordinator release work are complete.
