# Network player controller

`game/gameplay/player_controller.gd` preserves its offline branch and takes an early network branch when its session is `NetworkSession`. The coordinator supplies `lab.network_client`, polls `ClientReplica`, installs authoritative map transactions and refreshes the presentation session. The controller does not poll sockets, advance the match, decide hits or edit terrain.

## Fixed input and owned pose

The project physics callback runs at 60 Hz. Each live callback submits one `ClientReplica.submit_input` command with normalized movement, Godot yaw/pitch, seven source button bits and a drained tool/class/reload intent. Team and canonical packed block colors use the replica's typed requests. A temporary terrain/rebase rejection retains unsent selection/reload intents; a failed transport does not continue local play.

Menus submit neutral movement/buttons, including primary release during grenade cooking. The shared source minimum of nine ticks before release still applies. Gravity and source motion continue through prediction while controls are unavailable. An inactive actor normally submits no movement command. A pending class request can submit one neutral command; inactive presentation continues to read the confirmed owner instead of the resulting inactive prediction. The free/follow camera only changes local presentation.

Active physics feet, native velocity, eye/climb state, stance, water, walking phase, ADS/sprint blends, displayed equipment and source tool deadlines are copied from `SharedPlayerState`. No second `SourcePlayerMotion` or variable-delta action clock runs in this branch. Source native velocity becomes Godot velocity through multiplication by 32. The predictor's bounded eye translation correction smooths presentation while collision/query feet stay exact. Angular reconciliation is applied as a difference from the preceding simulation reference: unchanged snapshots preserve accumulated mouse input, and the submitted command becomes the next reference before adopting recoil. Cosmetic effects never add source recoil to aim a second time.

Native `WeaponView.set_simulation_state` receives raw desired/displayed equipment and tool/ADS/sprint blends before its pose update. Custom first-person skins may omit this optional hook and use their existing cosmetic integration. Gameplay readiness always uses `PlayerRules.can_use_tool`, independently of skin timing. A skin cannot authorize a premature shot, block edit or grenade.

## Presentation hooks and authority boundary

The existing `NetworkSession` signals drive own fire/reload animations. `apply_network_cosmetic(event)` accepts only the current owner, epoch and spawn generation. It adds predicted muzzle/casing/kick, spade action and grenade release animation; it does not raycast, damage, create projectiles, play network audio or change aim. The coordinator routes confirmed tracers, impacts, audio and hurt/objective effects after replica deduplication. An own predicted fire signal animates once; a matching confirmed shot stays suppressed. Remote grenade events do not animate the local hand, and a confirmed own release already played by prediction does not animate again.

The network input handler returns before offline grenade/block-line handlers. Direct calls to `_shoot`, `_spade`, `_damage_block`, `_place`, block-line/single-build handlers, grenade cook/throw, `_clip_motion` and `respawn_at` explicitly deny network authority. Build preview and source ray helpers remain read-only queries. Console or UI calls cannot teleport the network body, refill inventory or write client/server terrain through these entry points.

## Verification

Run with Godot 4.7.2:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://gameplay/player_controller.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_network_controller.gd
```

The standalone suite builds a player/camera/collision scaffold and a recording skin, uses a real authoritative runtime and two real WebSocket clients with baseline/state barriers, and avoids Main/preferences. It checks authority bypasses against server and client maps/resources, source-owned physics, mouse preservation, recoil once, shared readiness, input normalization/buttons, reload/cook deadlines, menu neutralization, typed palette/team requests, inactive class input, cosmetic identity and disconnect. Native skin behavior has its separate presentation suite. Main scene, exported browser pointer lock/drag input and visible network effects need coordinator integration/browser checks; this headless suite does not establish those outcomes.

On 2026-10-10 the full runtime/scaffold suite passed **508 assertions, 0 failures** (the count includes the variable number of authority polling steps). The controller parser passed, source motion remained **128/0** and pure prediction **592/0**. The all-button jump/reload scenario exposed a signed `motion.fall_speed` wire-bound defect; the coordinator corrected the codec to `-128..128`, and the codec regression remained **2316/0** with a negative jump fixture. This is an actual source state transport correction, not a movement approximation.
