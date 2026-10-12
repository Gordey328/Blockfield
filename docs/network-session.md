# Network presentation session

> Historical pre-removal design/evidence. Multiplayer was withdrawn on2026-10-12
> under [ADR0031](decisions/0031-offline-only-game.md). Deleted networking paths
> and server instructions below do not apply to the current offline game.

`game/network/network_session.gd` implements `NetworkSession extends LocalSession` as a presentation adapter over `BlockfieldClientReplica`. Existing HUD/player/character consumers can retain the typed session contract. It performs no socket polling, shared-rule step, local timer simulation or authoritative map/player mutation. Offline `LocalSession` remains a separate authority and keeps its lab behavior.

The actual inherited `scenes/network.tscn` Main scene selects this adapter before ready, polls Replica, adopts validated Data through World's deferred presentation path and routes copied state/events to Controller/HUD/models/audio. Current negotiated identities are `blockfield-godot-4.7.2-network-3` and `blockfield-source-v0.1.3-authority-3`. Production consumes MATCH_STATE14, GAME_EVENTS15 and early MATCH_PREPARING17; team/color intentions use PLAYER_REQUEST16. Preparing/loading state clears old views and gates input/entry. See [world-preparation.md](world-preparation.md) and [match-preparation.md](match-preparation.md).

```gdscript
var view := NetworkSession.new()
view.bind_replica(client_replica)
view.update(render_delta)
var intent := view.drain_intent()
# The root connection/controller builds one fixed input from this intent.
# The adapter never calls submit_input or advances a second simulation step.
view.ingest_cosmetic(cosmetic_event)
view.ingest_event(confirmed_event,
    bool(confirmed_event.get("predicted_already_played", false)))
```

## State and ownership

Only a live replica with a matching positive owner ID/epoch can populate the playable view. Before joining and after disconnect/unbind, health/inventory are zero and the team is spectator. `local_player_id()` returns the assigned positive actor ID, or0 when unbound. A bound but loading replica may already have its positive ID without playable state. Binding a different replica clears old intents, event history and counters; epoch changes discard incompatible presentation state. Generation changes discard pending old-generation intents and last-fire cues.

`update(delta)` obtains independently owned `get_owner_state()` and `get_public_state()` values and uses `sample_remote(id)` for remote pose. It does not poll either socket, drain event queues, call prediction, call any base authority updater or age simulation timers with render delta. Timers derive from source tick/deadline values, with `get_reload_progress()` delegated to `PlayerRules.reload_progress(owner,owner.last_tick)`. A500-second view update cannot complete reload, throw a grenade, respawn, capture a flag or step the server.

The owner exposes predicted private ammo/blocks/grenades, tool/display readiness, source sprint/ADS blends, position and deadlines. Health, kills/deaths/score and event outcomes remain the predictor's confirmed fields. `spawn_generation,input_ack,confirmed_tick,player_kills,tool_raise,displayed_tool,displayed_weapon,sprint_state,aim_down_state` supplement the inherited presentation scalars. `session_time` is predicted tick/60, not a second clock.

`targets` contains confirmed public actors except the local owner, with stable positive IDs, generation, name/team/connected/alive, scores, tool/weapon/displayed selections, source readiness/ADS, interpolated feet/yaw/pitch/native velocity and crouch/sprint/wade/ground pose. It adds legacy presentation aliases `position,crouching,moving,state,raise_state,death_crouch,death_velocity` and `carries_intel,visual_only,interpolation_mode,poor_connection`. The aiming boolean derives from the public visible ADS blend; it is not private raw input. Remote respawn deadlines are private and therefore represented by−1, not an invented countdown.

Public snapshots intentionally do not disclose remote HP. Targets expose **`health=-1,health_known=false`** and retain the authoritative `alive` boolean. Consumers must use alive when HP is unknown and label HP as unknown, rather than turning an unknown−1 into death or inventing100HP. Remote resources/controls/RNG are omitted. `get_target(id)` returns another independent dictionary copy.

Objective arrays are copied from confirmed typed state. CTF carriers retain their canonical actor IDs; no local actor is rewritten to0. `is_local_intel_carrier()` compares against `local_player_id()`. Main/HUD/map/scoreboard and spectator/character views use canonical positive identities and authoritative alive status when remote health is unknown. Grenades copy confirmed position/velocity/orientation/ticks and add a derived visual fuse plus `visual_only=true`. No `LabGrenade` authority is stepped by this adapter and a visual cannot supply an authoritative position.

Inherited public scalar/array fields remain compatibility **view copies**, not language-enforced immutable properties. Frontend writes can temporarily alter presentation but cannot reach replica/server objects. The next update overwrites them from trusted state, including forcing `unlimited_ammo=false` and `invulnerable=false`. Queries such as weapon info and tool eligibility use the private approved owner copy rather than those writable frontend scalars. Root disables lab edit controls in network UI; an arbitrary local view write is not a server privilege.

## Intents and denied authority

`drain_intent()` returns exactly `{tool:255,weapon:255,reload:false,team:-1,color:-1}` with any queued values, then restores those defaults. Tool0..3, class0..2 and team0..2 requests replace only their latest slot; reload is a single boolean. `request_block_color(int)` permits the canonical packed solid `0x01RRGGBB` range and queues the latest color. Invalid/uninitialized requests are ignored. Storage remains five fields even after thousands of clicks. Selection does not refill inventory, immediately change team/class/tool or start a reload. The network Controller consumes the intent once per fixed step: tool/class/reload become shared input, team/color call Replica's typed PLAYER_REQUEST16 API. Server eligibility and spectator admission restrictions remain authoritative.

Every inherited LocalSession authority entry point is explicitly overridden, including its internal update/reset/drop/event helpers. Fire, target/player/grenade damage, respawn, restock, block charges/recovery, grenade cook/release/position, target addition/removal/pose, score, profile/mode/objective configuration and lab reset are denied or no-op. `fire/use_block/begin_grenade_cook/use_grenade` return false, damage queries return0, `release_grenade` returns an empty dictionary and `add_target` returns−1. `set_team_info/get_team_info` remain local visual preferences and cannot change negotiated server profile or match mode. Rebindings and input preferences remain outside the adapter.

## Explicit presentation event hooks

`ingest_event(event,predicted_already_played=false)` expects an **EventsCodec-validated, replica-deduplicated confirmed** event. Runtime routes owner-only outcomes only to the authenticated owner; Replica rejects foreign private events. The adapter checks epoch, known type, required fields and stale actor generation before emitting compatibility signals. It does not itself consume network queues or implement delivery deduplication. Main passes Replica's suppression flag as the second argument, then routes accepted confirmed tracers, own hit blood, block hits, spatial audio and objective signals. Prediction/reconciliation never apply those confirmed outcomes a second time.

Own confirmed shots increment confirmed shot statistics, record last-fire time and emit `shot_fired` unless their predicted animation already played. Remote shots never emit the local weapon signal. Own confirmed reload completion supports the same suppression; restock, hurt/death/spawn and confirmed hit counters derive only from explicit events. Snapshot differences do not independently synthesize these signals. Hurt has no origin in the source event schema, so the bridge emits `Vector3.INF` for a nondirectional cue rather than fabricating an attacker position.

Confirmed grenade throws always emit a copied `visual_only` record with real confirmed position, preserving `predicted_already_played` for root to suppress only repeated hand animation. Predicted release has no position and never emits `grenade_thrown`; it cannot instantiate an authoritative projectile. Confirmed explosion records add the legacy `id` alias from `grenade_id`. Remote death/spawn signals retain canonical positive actor IDs. A confirmed round event emits `round_won` without setting a locally invented score/winner.

`ingest_cosmetic(event)` accepts only this owner's current epoch/generation and the prediction's explicit cosmetic kind set. Shot/reload-completion cues can emit local animation signals, but no confirmed hit/kill/log/resource mutation follows. No cosmetic grenade spawn/explosion signal exists. It is root's responsibility to call these hooks once after replica deduplication; replay must not invoke them again.

Confirmed event-log records are independent copies, capped at128. Spawn/team/death/kill credit are enriched for the existing feed using known public names/teams. A bounded128-entry confirmed-shot reference cache supplies a kill's weapon only when its `source_event_id` is present. Otherwise `weapon_known=false` and no weapon value is invented; HUD must display a generic known cause. Event hooks never apply the event's damage, stock, score, position or objective result to prediction/authority.

## Verification and remaining integration

Godot `4.7.2.stable.official.ed1daf0bf`, headless standalone without Main/preferences:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/network_session.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_network_session.gd
```

Observed result: **501 assertions / 0 failures**, exit0, no script errors. Real native server and two game+map replicas complete map/state barriers, move/reconcile input and mirror source reload/cook, positive CTF carrier and public grenade snapshots. The count includes variable socket-pump steps and may vary with timing. Tests verify all LocalSession methods have an explicit override except allowed team visual preferences, bounded intents, unknown HP, interpolation, timer no-ops, direct scalar/dictionary spoofing and denial of every authority path against actual server data/player resources and prediction. Typed EventsCodec round trips drive signal suppression, nondirectional hurt, confirmed-only hit counters, source-attributed or unknown kill weapon, visual-only throw/explosion and bounded logs. Disconnect/rebind/unbind clears incompatible state.

Controller integration is implemented: the network branch submits shared fixed input, mirrors owned motion/readiness and denies direct offline authority calls; its actual-runtime/scaffold suite passed **508/0**. The actual inherited Main network scene [test_network_scene.gd](../tests/network/test_network_scene.gd) passed **27/0** with `--fixed-fps60`, exact saved-preference restoration; log `.cache/logs/network-scene-integration.log`. It verifies trusted World/Replica map adoption, positive local/remote IDs, public unknown HP, only confirmed CTF objective models, denied lab cheats, one source-owned shot/HUD cosmetic cue, confirmed chat and disconnect/resume. Native event delivery **108/0** verifies owner/public routing and suppression independently.

Authority firearm rewind is integrated in Runtime/Match; it does not run in this view adapter. Ready/live playing owners automatically respawn at the authored 180-tick deadline through server generation/state updates, never a Session timer. Trusted greater-epoch reset clears old view/intents/event references; Main handles `epoch_reset` by clearing remote/objective/grenade views/effects and returning to its loading menu. Runtime epoch **722/0** verifies live and mid-join replacement, rotated capabilities, exact new terrain/barriers and retired channel cleanup without Main. The 27-check Main suite does not yet exercise rendered epoch reset.

Exported browser controls/render/audio, browser epoch scene reset, WSS/TLS hosting, Docker execution, connected-game frame/memory performance, sustained capacity and shaped WAN latency remain separate acceptance. These native checks do not complete iteration 2.
