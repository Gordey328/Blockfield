# Actual network scene across a match reset

`tests/network/test_network_scene_epoch.gd` exercises the real inherited `game/scenes/network.tscn`, `Main`, `NetworkSession`, controller, original character/weapon meshes, HUD, mini/full maps and connection menu. A native `ServerRuntime` and a second independent `ClientReplica` exchange genuine WebSocket packets on two ephemeral loopback ports. No fake transport, replacement Main or optimistic objective/projectile simulator is used.

The scenario starts a 32×16×32 CTF map at epoch1101/profile0.75. The connection form's real Connect/Enter buttons, weapon buttons and team selector drive actual client intents. It verifies pending class selection cannot refill a living inventory, spectator selection preserves the positive canonical ID, and the authored180-tick respawn applies the queued shotgun class. A trusted server-only HP fixture distinguishes the second owner's private37HP from the first client's explicitly unknown remote HP; the actual original soldier remains alive, named and animated. Remote input packets exercise crouch, ADS, view angles and interpolated feet.

A genuine authoritative repaint receipt populates old terrain, topdown and impact-color caches. The actual local controller selects/cooks/releases a grenade. Its rendered node must copy the confirmed public position and quaternion, with no client grenade authority. The server then resets the live match to a different64×24×48 map, epoch1102/profile0.76/TC. The test checks the loading UI gates input, old objectives and projectiles disappear, HUD feedback is cleared, both map/state barriers complete, both canonical IDs survive, and the new renderer uses exact transferred cells and a rebuilt map texture. Old chunk/collision nodes, soldier, CTF meshes and grenade must be freed. Only the three TC checkpoints may remain. New-epoch class/team requests must still reach authority and produce the source0.76 SMG inventory after respawn.

The original skin is selected explicitly for this fixture. The test saves and restores the exact prior bytes and existence of `user://settings.cfg` and `user://servers.cfg`, releases its input actions, closes both replicas and stops the server. Do not run it concurrently with any suite or interactive session that writes those preference files.

Scene samples occur after the frame's node processing, using a zero-duration `SceneTreeTimer`: `process_frame` itself is emitted before `Node._process` and therefore is too early to compare the newly mirrored remote pose to its actual soldier transform. The scenario enters the game through Enter before asking for the spectator free camera; the unopened connection menu correctly remains in its introductory camera state.

Run from the repository root on a coherent production handoff:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --fixed-fps 60 --script ../tests/network/test_network_scene_epoch.gd
```

Observed Godot **4.7.2.stable.official.ed1daf0bf** result: **83 assertions / 0 failures / 642 fixed-step polls**, exit0, clean stderr and parser. Log: `.cache/logs/network-scene-epoch-integration.log`. An external180-second harness additionally restores both preference files in `finally` and kills the exact engine process tree on timeout; this run completed normally, and the suite also confirmed its own exact restoration.

The same test optionally captures the real Compatibility viewport:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 --position -16000,-16000 --fixed-fps 60 --script ../tests/network/test_network_scene_epoch.gd -- --render-scene-epoch
```

Observed Intel UHD/OpenGL3.3 result: **89 assertions / 0 failures / 648 fixed-step polls**, exit0 and clean stderr; `.cache/logs/network-scene-epoch-gpu.log`. The window was placed offscreen. Three actual1280×720 frame readbacks were saved and inspected under `.cache/previews/network-scene-epoch/`: `01-ctf-remote-pose.png` shows the named crouching remote soldier and CTF map; `02-reset-loading.png` shows disabled Enter and the loading progress; `03-tc-remote-pose.png` shows the new TC map/checkpoints, named live remote and source0.76 shotgun8/48. Captures and logs are local ignored evidence, not source assets. Dummy audio avoids playing test sounds and supplies no listening evidence.

This establishes native socket, scene-node, mesh-transform, actual viewport and UI-state behavior across the reset. It does not establish exported-browser input/audio/rendering, HTTPS/WSS, Docker deployment, WAN latency, sustained renderer performance or iteration completion. Those acceptance checks remain separate.
