# Authoritative shot rewind

`MatchSimulation` has an optional historical firearm resolver, enabled by the native Runtime. `BlockfieldHitHistory` selects actor hit volumes and terrain from the same exact completed frame. This is an authored multiplayer policy built on the existing source weapon/hit rules, not a claim about the original Ace of Spades server. Upstream OpenSpades is a client.

## Coordinator contract

```gdscript
simulation.set_rewind_query_factory(history.query_at)
simulation.step_fixed(commands, admitted_shot_ticks)
```

The factory is a trusted coordinator callable `(requested_tick:int, closed_tick:int) -> Dictionary`. Its success result has exactly the HitHistory contract: `{ok,error,query:HistoricalVoxelQuery,actors:Array[Dictionary],tick,map_sequence}`. A fresh query is consumed and cancelled during each shot plan. Retain the History instance in the coordinator; a bound method alone does not keep its RefCounted target alive.

`admitted_shot_ticks` maps stable actor ID to an integer **server-admitted** tick. It is separate from commands, never a client-authoritative field. During step `T`, the factory receives latest closed tick `T-1`. Match requires an exact requested tick in `0..T-1`; HitHistory further requires that exact retained frame. Match does not clamp or choose the nearest available frame. The coordinator admits a timestamp only for the authenticated connection owner/current generation. The agreed Runtime policy clamps an otherwise admitted current/future input to the simulation's closed tick before calling step, preserves the existing 15-tick admission bound, and clears leases on generation/disconnection/expiration. That admission belongs to Runtime, not this helper.

Held commands may fire again while their admitted tick remains available. After it leaves the retained history window, a repeated shot is denied damage. Runtime must clear controls and the tick lease together; granting an input packet does not indefinitely grant a useful historical shot.

Only an explicitly empty `Callable()` disables rewind and restores the original offline `_resolve_shot` path. A configured callable whose target has been freed remains **enabled** and fails closed. Successful match configuration and replacing the factory reset its diagnostic counters.

## Plan before commit

Each canonical step proceeds as follows:

1. Existing PlayerRules validate commands, move every actor, apply source equipment/cadence/ammo rules and produce authenticated shot intents. Source fire still owns its isolated RNG and recoil.
2. Before resolving any shot/melee damage or terrain edit, Match plans **all** shots in the step. Each shot gets its own exact same-time historical actor/terrain query. There are at most 32 actors/shots and 8 source pellets per shot: 256 owned pellet plans.
3. The historical shooter must be alive, connected, finite and in the same current/shot spawn generation and match epoch. Muzzle origin is its captured unsmoothed `physics_eye + admitted_front * .01`. Aim comes from the accepted command, or retained server aim, captured before `PlayerRules.fire()` applies recoil. Existing generated `shot.directions` are preserved; no extra RNG draws or recoil occurs.
4. Existing `LabHitVolumes` test historical feet/yaw/pitch/crouch. Source hit choice retains strict horizontal distance `<128`, source part/actor tie ordering and player priority on equal map distance. The same historical terrain DDA supplies occlusion.
5. Copy only the chosen endpoint, victim ID/generation/part, or terrain cell/normal/queried color. Check the query's live identity again, then cancel it. No borrowed map/pose query is carried into damage resolution.
6. Commit the owned plans in the existing intent order. A victim must still exist, be connected/alive/playing and have the exact historical generation/epoch. A terrain cell must still have its queried historical color before hidden block health/removal can change. Source block damage and at-most-one destruction per firearm shot remain unchanged.

The public confirmed `shot` event is an owned copy with the historical origin. Its ID, sequence, rays, weapon/profile and source recoil remain unchanged; caller commands and frozen PlayerRules events are never mutated. Corresponding tracers use the same origin. Wire event families and codec schemas are unchanged.

Planning all shots before the first map destruction prevents later shotgun pellets or another shooter's ray from switching to current air behind an old obstacle. Planning before actor damage also permits two already-authorized shots to trade kills. A later pellet cannot damage a victim already killed by an earlier pellet; a new generation cannot receive old-life damage.

The block guard uses canonical color equality, not a per-cell generation. A same-color replacement cannot be distinguished by this guard alone. This is the accepted initial policy. Historical occlusion endpoints remain valid for visual tracers even when the current block has already disappeared; a rejected current block does not produce a new `block_hit` event.

## Missing history and diagnostics

Missing/future/noninteger admitted ticks, missing/out-of-window history, stale or mismatched query identity, malformed pose arrays and missing/old-life shooters deny the **entire shot's damage**. Authenticated ammo/cadence and the existing confirmed `shot` event still occur. Emit only miss tracers `origin + direction * 128`, with no hit/block/damage feedback. If an origin was established before a late planning failure, its miss tracer keeps that historical origin; otherwise it keeps the authorized current shot origin. There is no current-state fallback and no new `shot_unresolved` wire event.

`get_rewind_stats()` returns a copied bounded dictionary:

```text
enabled, planned_shots, denied_shots, denied_pellets,
applied_player_hits, blocked_generation_hits, blocked_ineligible_hits,
blocked_color_hits, last_reason, denials
```

Counters saturate at uint32 max. `denials` uses eight fixed reason strings, never client/factory error text: `step_shot_limit`, `missing_or_future_admitted_tick`, `pellet_limit`, `history_unavailable`, `invalid_history_query`, `invalid_or_stale_history`, `invalid_history_pose`, `historical_shooter_ineligible`. Statistics do not reveal tokens, usernames, arbitrary packet contents or URLs. Current victim/color rejection increments its separate counter and retains the planned tracer endpoint; it creates no successful hit event.

Only firearms rewind in this slice. Melee, grenades, building and objectives retain their existing current-time shared authority rules. This does not change input admission, sockets, client prediction, map replication, renderer or preference files.

## Verification and limits

Native Godot4.7.2 `ed1daf0bf`:

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_match_rewind.gd
```

**441 assertions / 0 failures**, `.cache/logs/match-rewind-tests.log`. Fixtures exercise actual `MatchSimulation.step_fixed` with authenticated commands and real HitHistory: old moved-target hit/current miss, historical shooter position and pre-recoil muzzle, preserved RNG/recoil, old cover/current air, all shots planned before damage, early destruction with two shooters, eight shotgun pellets, trade kills, death/disconnect/spectator/respawn generation, repaint rejection, missing/stale/cancelled/freed history, invalid factory output, held lease expiry and a full32-actor/256-pellet frame. Returned diagnostic data is isolated; queries are released. No main/preferences writes or leaked-object reports.

Existing native suites pass: Match208, HitHistory350 and PlayerRules144, all zero failures. Match parser passes. Source rules remain based on `Player.cpp:581–696` and `LabHitVolumes` (`Player.cpp:1316–1385`); server lag compensation is an authored replacement.

Runtime integration is implemented: admitted owner input ticks and retained leases select the exact closed history, with generation/disconnect/reset invalidation and ordered actor/terrain receipts after commits. Real adversarial sockets392/0 and epoch722/0 exercise it; rendered Main scene27/0 covers the client path. This does not accept browser/WAN latency or sustained60Hz capacity. [Capacity measurements](server-capacity.md) exposed repeated inverse-query construction and serialization costs; bounded shared-history and publication optimizations are being validated separately. Public WSS and full browser release acceptance remain pending.

## Prepared hit geometry

After validating every historical pose and the shooter's life/epoch, Match
prepares each eligible target's exact source hit-volume transforms once per
shot. All pellets reuse those owned transforms and the conservative world bound;
hit ordering, source narrow phase and horizontal range selection remain intact.
There is no geometry cache across shots, ticks, history leases or mutations.
The original/prepared helper differential and measured limits are recorded in
[hit-volumes.md](hit-volumes.md). Match rewind remains441/0 after integration.
