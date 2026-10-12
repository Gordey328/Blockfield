# Pure client prediction and remote poses

> Historical pre-removal design/evidence. Multiplayer was withdrawn on2026-10-12
> under [ADR0031](decisions/0031-offline-only-game.md). Deleted networking paths
> and server instructions below do not apply to the current offline game.

`game/network/client_prediction.gd` implements `ClientPrediction`, a `RefCounted` using [shared player rules](player-rules.md) and [VoxelData](voxel-data.md). It has no socket, Input singleton, scene, renderer, physics-server or audio dependency. Runtime/wire decoding, fixed-clock scheduling, authoritative match simulation and presentation adapters are separate. These unit checks do not establish a connected multiplayer game or cross-runtime/browser replay acceptance.

## Owner state and commands

```gdscript
var prediction := ClientPrediction.new()
prediction.reset(trusted_complete_owner, server_tick, confirmed_map_sequence)
var result := prediction.predict(copied_input_command, confirmed_voxel_data)
var next_view := prediction.get_state()
# A newer complete snapshot acknowledges owner.consumed_input_sequence.
prediction.reconcile(trusted_complete_owner, server_tick,
    confirmed_map_sequence, confirmed_voxel_data)
var rendered := prediction.sample_local_presentation(render_delta)
```

Owner input is a trusted `SharedPlayerState` reconstructed by the runtime from a validated **complete replay-state snapshot**. Its `last_tick` must equal the header's `server_tick`. The source spawn's pre-step `last_tick=spawn_tick-1` is not an after-tick snapshot; advance the spawn tick before publishing that snapshot. Owner identity/epoch/generation, profile/tool, finite pose and replay deadlines are checked before adoption. The snapshot must retain fractional shot/reload deadlines, held/previous input, trigger/reload/cook/tool readiness, source motion/climb/wade state and private resources. Reconstructing only pose, magazine and rounded deadlines cannot reproduce source cadence; the earlier minimal protocol owner schema is insufficient for this API.

The module copies scalar/value fields and owns a copy of motion. It explicitly excludes the server's `shot_rng` rather than copying then using its seed/state. A new isolated fixed cosmetic RNG supplies the existing shared rule function's internal spread calculation; **no predicted pellet directions escape**. Recoil/resource/animation state remains deterministic because source recoil does not depend on pellet RNG. `get_state()` and `get_confirmed_state()` return independent copies with only that private cosmetic stream, not transport pointers or the server stream.

`predict(PlayerRules.Command, VoxelData)` accepts only the next contiguous positive input sequence for the current generation. It owns the command before stepping shared rules exactly once at `last_tick+1`, with fixed1/60s and `authoritative_damage=false`. No caller delta, victim, hit, stock refill or world edit is accepted. `get_pending_commands()` returns owned command copies for a runtime to batch/encode; modifying them cannot alter replay history.

History retains at most **256 unacknowledged commands**, each with its prediction tick and terrain sequence. Reaching the cap stops further prediction and sets `needs_rebase`; it does not silently discard commands, invent elapsed ticks or grow memory. Tick/u32 exhaustion also requests rebase. Input timing/lead limits and the suspended-tab policy belong to the connection runtime. An explicit `reset` is reserved for a trusted join/rebase/reset transition; it clears incompatible history and correction. A reset within the same actor/epoch/spawn generation retains the last submitted input sequence and waits for its acknowledgement before accepting another command. Only a new epoch/generation or a newly initialized prediction stream can establish a fresh sequence baseline. The transport must coordinate any input timeline rebase with the server rather than reusing old queued sequences unilaterally.

## Reconciliation and terrain policy

`reconcile(owner,server_tick,map_sequence,query)` restores complete authoritative state, removes commands through `owner.consumed_input_sequence`, and replays the retained contiguous suffix at server ticks `server_tick+1..N`. This deliberately rebases surviving command ticks to the authoritative clock if delivery/scheduling differed; source time-dependent recoil and deadlines then use those canonical replay ticks. The `input_ack` in status remains the server's acknowledgement, while the predicted copy's `consumed_input_sequence` includes the replayed suffix.

Prediction and reconciliation require the query's exact epoch/map sequence. Missing current terrain returns `map_sync=true` without changing physics/history. A retained command that was originally predicted against a different terrain sequence returns `needs_rebase=true`, reason `historical terrain unavailable`; it is not replayed against an invented old map or silently rewritten using the new terrain. This first module has no historical terrain query. The coordinator must install a trusted fresh owner/map barrier and explicitly rebase, or a later historical-query implementation must supply and test the correct terrain. Frequent destructive edits can therefore interrupt prediction until that runtime policy is implemented; this is a documented gap rather than working historical replay.

Old snapshots/generations/epochs are ignored before terrain synchronization checks, so a stale packet cannot poison a new match or resurrect a confirmed death. A new epoch/generation clears incompatible history and establishes the new authoritative sequence baseline. Invalid snapshots, acknowledgements beyond submitted inputs and unavailable terrain preserve the current model; status exposes `reason`, `needs_rebase`, `map_sync`, pending count, server/predicted tick, acknowledgement, last submitted sequence, `reset_ack_floor` and terrain sequence.

### Same-life mode/reset acknowledgement barrier

A team, active class/profile, connected state or alive/dead change within the same
actor/epoch/generation changes how pending commands may be simulated. Old-mode
commands are therefore discarded instead of replayed into the new mode. The new
copied authoritative pose/resources become visible immediately, and old render
correction is cleared. This visual reset **does not reset the wire input sequence**:
the server may already have accepted a command absent from the snapshot's ACK.

For example, the server queue has accepted sequence20, then a same-generation
spectator snapshot acknowledges19. Prediction keeps `last_submitted=20`, clears
old history, sets `reset_ack_floor=20` and `needs_rebase=true`, and rejects further
`predict` calls without events or cursor changes. Both `reset` and `reconcile`
return `ok=false` with reason `same-life reset awaiting transmitted input
acknowledgement`; this is an adopted confirmed view with a waiting barrier, not an
invalid snapshot. Integration must retain the connection and show the confirmed
inactive pose while `needs_rebase` remains true.

Newer ACK19 snapshots refresh that confirmed pose, including further mode changes,
without clearing the barrier merely because replay history is empty. At ACK20,
`reconcile` returns `ok=true`, clears `reset_ack_floor` to-1, and the next command
is21. ACK beyond the submitted floor fails validation; an explicit same-life reset
cannot bypass the floor. New epoch/generation clears the old floor. Missing terrain
retains the floor and uses the existing `map_sync` policy; restoring matching terrain
alone cannot authorize an unacknowledged sequence reset.

The connection runtime's existing `needs_rebase` admission gate blocks input, and
its trusted retry-reset at `ACK == last_submitted` remains compatible. No transport,
ACK field, authority queue or prediction replay clock is changed by this barrier.

Physics feet, source motion, resources and aim use the corrected replay result immediately. Rendering retains the pre-reconcile position/yaw/pitch offset and decays it exponentially with an authored **80ms time constant** through `sample_local_presentation(delta)`. The result contains rendered `feet`, `eye`, `yaw`, `pitch`; it cannot move collision state. Corrections larger than3m snap presentation rather than keeping a long offset. These smoothing choices are multiplayer presentation policy, not native OpenSpades camera equations. Those equations remain a later presentation layer.

## Authority and effects

Shared rules can predict ammo/reload/cook/grenade stock/tool readiness and recoil. Prediction passes `authoritative_damage=false`, so even a hard landing cannot temporarily kill the actor, release a death grenade or consume its inventory. Health, kills, deaths, score, death/respawn deadlines and the actor event counter always remain the latest confirmed values. Real victims, damage, projectile creation, map changes, block charges/recovery and objective outcomes remain server-confirmed. Block placement is still a preview/confirmed-operation boundary; `PlayerRules.use_blocks` is not invoked by a predicted command.

Live prediction returns read-only **cosmetic records**, separate from shared authority events:

```gdscript
{
    "kind": "shot", "predicted": true,
    "owner_id": 5, "spawn_generation": 1, "epoch": 7,
    "input_sequence": 20, "tick": 20,
    "effect_key": "7:5:1:20:shot:20",
    "weapon": 1, "profile": "0.75", "recoil_direction": Vector3(...)
}
```

Allowed kinds are shot/dry-fire, reload/shell/tool/class animation, grenade pin/release, spade animation, jump/land/footstep. Grenade release carries no spawn position, velocity, fuse or damage. Shot carries no origin, pellet directions, victim, damage or hit indicator. Records deliberately use `kind`, not the authority event's `type/event_id`; they cannot be passed directly to a MatchSimulation event resolver. The landing record may expose a `fall_warning` for a local pose cue, never damage authority.

Every reconciliation result has `events=[]`: internal shared-rule replay events are discarded, so no callback, sound, shot, grenade, collapse, chat or HUD feed is emitted again. Cosmetic keys remain stable for their original live prediction. Confirm/reject merging is a runtime responsibility using actor/generation/input/action correlation; a tick-containing cosmetic key is **not** proof that a delayed server event will have the same tick or authoritative event ID. The module does not implement authoritative event delivery/deduplication.

## Remote interpolation

`ClientPrediction.RemotePoseBuffer` is a separate pure object per remote actor. `push(public_pose,epoch,tick)` owns only validated public value fields: ID/generation/team/flags/tool/weapon/name, feet, native velocity, yaw and pitch. Owner health/resources/RNG and unknown extensions are discarded. Wrong actor, malformed/nonfinite data, old epoch/generation and duplicate/reordered ticks are rejected without modifying the buffer. New epoch/generation clears old samples, preventing interpolation from an old corpse into a new spawn.

The buffer keeps at most **32 poses**. `sample(estimated_server_tick_float)` initially renders100ms behind the caller's estimated server clock. Feet/native velocity interpolate linearly; yaw/pitch use the shortest angular difference, including the ±π yaw crossing. Discrete crouch/alive/tool/team flags use the older sample until the newer sample's timestamp. Clock estimation is not implemented here. `set_delay_seconds` permits a bounded0..250ms delay for a future jitter policy; it does not measure jitter itself.

Beyond the newest sample, native velocity scales to world displacement by `velocity*32*seconds` for at most **100ms**. Further sampling freezes at that extrapolated endpoint, sets `poor_connection=true`, and never snaps back to the last snapshot position. There is no extrapolated collision, aim/hit history, authoritative motion or acceleration. Server hit validation uses simulation states, never these visual poses. Disconnect can call `clear()`.

## Verification

Godot `4.7.2.stable.official.ed1daf0bf`, standalone headless, without main/preferences:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/client_prediction.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_client_prediction.gd
```

Current result: **729 assertions / 0 failures**, exit0, clean diagnostics in
`.cache/logs/test-client-prediction-mode.log`; production parser also passes.
A real shared voxel query drives a180-tick authoritative/predicted
movement/sprint/jump/crouch/weapon/reload trace. Delayed snapshots replay twelve
unacknowledged commands with corrected position/ammo; tests check fractional
timers, confirmed health/score/counters, separate render correction, command/state
ownership, stripped server RNG, no external replay effects, hard-fall/no forced
death grenade, map/history failures,256-command limits, respawn/death/team/epoch
changes, stale packets and u32 exhaustion. Remote cases check shortest yaw crossing,
discrete state timing, native velocity scaling,100ms freeze endpoint,
malformed/stale/wrong actors, generation resets and32-pose bounds.

New mode fixtures cover spectator/team/death/weapon/profile/disconnect with
submitted20 and ACK19, repeated ACK19, a second mode change while waiting, exact
ACK20 recovery and next21; they compare resumed shared rules and confirmed/private
resources. Explicit reset, missing/restored terrain, impossibleACK, new life and
new epoch cases exercise floor lifetime. An independent actual `BlockfieldInputQueue`
fixture accepts future20, publishes spectator ACK19 before its consumption, consumes
20 once, and then accepts pending-class21 without duplicate sequence or stock refill.
The new regression fixtures failed61 checks against the previous implementation;
the previous suite had592/0. Older tests that explicitly reused sequence1 after an
unacknowledged same-life terrain reset now require ACK1 and resume at2. No presentation
or physics nodes, Main, preferences, sockets or GPU are created by this pure suite.

Wire full-owner reconstruction, server input scheduling/rebase, authoritative event correlation, historical terrain, real network latency/TCP stalls, cross-runtime native/Web determinism, two-client browser input and rendered smoothing remain integration/acceptance work. N02 remains incomplete until those actual runtime paths are connected and exercised.
