# Stable actor identities across match reset

> Historical pre-removal design/evidence. Multiplayer was withdrawn on2026-10-12
> under [ADR0031](decisions/0031-offline-only-game.md). Deleted networking paths
> and server instructions below do not apply to the current offline game.

`MatchSimulation.add_actor(name, team=2, seed_value=1, initial_feet=Vector3.INF, actor_id=0)` has an optional trusted identity path for the server coordinator. It is not a client request or a new wire field. Zero chooses the automatic allocator; an explicit ID must be a positive u32 never previously issued in the current epoch. Existing calls preserve their spectator/default source behavior.

The automatic allocator advances to `max(previous_next, assigned_id + 1)` after successful admission. Restoring IDs in any order preserves gaps and avoids automatic collisions. Assigning `4294967295` leaves the signed64 sentinel `4294967296`: automatic admission then fails instead of wrapping to actor0. A trusted unused lower ID can still be admitted. Removed actor IDs remain reserved until `configure` installs a new epoch. Active registry capacity remains 32; IDs do not bypass that limit. The issued-ID set grows with successful admissions over the epoch, independently of the active registry, to prevent stale identities being reassigned.

The supplied constructor receives the new match epoch/profile, exact ID/name and private server RNG seed. Default spectators remain generation1, health/inventory0 and aligned with the current match tick. A playing admission uses the existing validated source spawn, including generation increment, native equipment readiness and the selected profile's resources. A supplied initial position must be safe, finite, within the existing source spawn bounds and free of live actors/terrain. A spectator can receive a safe initial motion position without a combat spawn/refill. Failed name/ID/position/capacity validation does not reserve the ID or emit admission events.

## Coordinator reset flow

The server constructs/configures a new `MatchSimulation` and writable map with a new positive epoch. Configuration clears previous actors, grenades, counters, events, transactions, block health, objectives/winner and allocator reservations. It restores connected actor IDs through trusted `add_actor(..., actor_id=id)`, initially as spectators. Weapon/pending class preference restoration is an explicit coordinator action; previous health, ammo, kills or score are not implicitly imported. Source spawn occurs after the new baseline and state readiness barrier, using the previous playing team and new profile. Transport capabilities, generation/input/event cursor invalidation and old-epoch packet rejection belong to Runtime/Registry/ClientReplica, rather than this admission method.

## Verification

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_match_reset.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_match_simulation.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_match_rewind.gd
```

The pure suite covers sparse/unsorted identities, duplicate/removed identity denial, u32 exhaustion, active capacity, safe/invalid authored positions, automatic avoidance, new epoch cleanup, explicit class restoration and `0.75`→`0.76` source resource behavior. Complete replay snapshots are checked through the existing typed codec. Actual connected-client reset barriers and stale wire packets require the coordinator's separate runtime integration suite; passing this pure identity test does not establish those behaviors.

Godot4.7.2 verification on 2026-10-10: reset identities **108 assertions/0 failures**, existing Match **208/0**, rewind **441/0** and PlayerRules **144/0**. The changed production script also passes the engine parser. No Runtime/Registry/Client/Main code was changed in this slice.
