# 0005 — Shared fixed-step authority and browser WebSocket protocol

Accepted 2026-10-10 within the user's approved replacement-networking scope.

The browser and native dedicated server use the pinned Godot 4.7.2 GDScript runtime, a 60 Hz shared MatchSimulation and an explicit bounded binary protocol. Public browser deployment requires native WebSocketPeer listeners behind TLS termination and browser WSS. Native localhost tests use WS; public WSS/TLS is not yet verified. Separate `/play` and `/map` sockets keep bulk bytes off the gameplay socket's queue. Both use ordered TCP and share network congestion. Delivery order across these two sockets must be enforced by application barriers.

Stable actor IDs, match epochs and spawn generations are independent of socket connection IDs. Clients submit movement/buttons/tool/class intentions and typed team/color requests. The server owns hit tests, resources, damage, objective outcomes and map edits. Source motion/hit/weapon equations remain shared; friendly fire, same-tick shot ordering, scores, respawn and objective behavior are explicitly authored policies documented in [match-simulation.md](../match-simulation.md). Runtime automatically respawns ready, connected playing actors at their 180-tick death deadline; loading, disconnected and spectator actors cannot use that path.

Runtime records completed actor poses and committed terrain changes in one bounded HitHistory window. Firearm rewind uses an exact server-admitted tick, clamping an admitted current/future input to the latest closed tick. Actor hit volumes and terrain occlusion come from the same historical query; all shots in a step are planned before damage/map edits. Current life eligibility and queried block colors are checked again before commit. Missing/out-of-window history denies damage while source ammo/cadence and confirmed discharge still occur; there is no current-cover fallback. Melee, grenades, building and objectives retain current-time authority. This is an authored server policy, with limits in [match-rewind.md](../match-rewind.md) and [hit-history.md](../hit-history.md).

The current compatibility identities are `blockfield-godot-4.7.2-network-4` and `blockfield-source-v0.1.3-authority-4`; HELLO/WELCOME carry their SHA256 hashes. Envelope version remains1. The authority-4 amendment below changes stale INPUT_BATCH admission/retirement, so earlier authority hashes cannot silently use this policy. Production uses complete MATCH_STATE14, confirmed GAME_EVENTS15, PLAYER_REQUEST16, early MATCH_PREPARING17 and cumulative MAP_CHUNK_ACK18 alongside input/chat/map families. Owner snapshots preserve replay readiness, cadence, controls and resources without server RNG. Remote actors expose public pose/readiness/score without HP, inventory or raw controls. Owner-only outcomes route only to their authenticated owner and are checked again by Replica. Public confirmed rays are outcomes, never client-authoritative shots.

Guest sessions have rotating 32-byte resume capabilities, SHA256 digests retained by the registry, a 30-second disconnected identity grace and one-time 15-second bulk capabilities. The server renews the bulk capability after baseline preparation before delivering WELCOME. These are resumable guest ownership, not account authentication. Tokens are exchanged inside WSS, never included in logs/client build configuration. Crypto uses Godot's secure random bytes and constant-time digest comparison. [Godot Crypto API](https://docs.godotengine.org/en/4.7/classes/class_crypto.html)

A client cannot submit gameplay before verifying the map's baseline, ordered deltas and END barrier, returning matching MAP_READY and receiving the matching full owner state. At most two joins prepare maps concurrently. Hash/decode work is budgeted between fixed steps. Gaps, overflow and inconsistent before colors fail the stream; already in-flight older-epoch or older-generation input/request frames are ignored rather than applied to the replacement life. Count-bounded work does not guarantee a millisecond bound; measured large copy/transaction pauses remain acceptance gaps.

Bulk sender progress is now bounded by authenticated cumulative receive credit:
at most8 full16KiB frames are sent without accepted acknowledgment. A socket's
owner and frozen baseline identity select its window; duplicate older credit
cannot advance it. MAP_READY still requires canonical bytes and the END barrier,
and may precede a last ACK across sockets. Local outbound buffering alone never
proves that a paused browser has received its baseline. New handshake identity
rejects older clients that cannot replenish this window.

Wire input time is independent of retimed local replay and missed render
callbacks. A monotonic 60Hz wall-time anchor observes authority snapshots and
adds a full-RTT reserve `clamp(ceil(rtt_ms*0.06),3,7)` ticks, initially 3. The
snapshot travels downstream before its command travels upstream; this reserve
is bounded by the unchanged future ceiling, not inferred from replay depth.
If the next candidate exceeds the newest snapshot tick plus 8, input waits
without spending a sequence. A strictly newer snapshot after waiting resamples
the anchor even after an authority pause; duplicates cannot reanchor it and
submitted ticks remain monotonic. Replica waits until pending incoming packets
are drained, then dispatches successfully queued input before render work.
Same-life mode reset retains the transmitted ACK floor rather than reusing an
unacknowledged sequence. See [client-schedule.md](../client-schedule.md).

Authority-4 policy amendment, 2026-10-10: preserve the **15-closed-tick execution
and firearm-rewind window**, but receive strictly validated ordered stale input
for **ACK retirement only**, up to `MAX_STALE_TICKS=120`. At latest closed tick
`S`, receive admission is `max(0,S-120)..S+8`. On `take(S+1)`, the bounded queue
first discards records older than `S-15`; exactly `S-15` is still executable.
Discarded commands never enter MatchSimulation or HitHistory. Their
`retired_ack` promotes the actor's consumed sequence, clears held controls and
shot-clock state, and increments `stale_inputs`. This acknowledges lost-time
intent without replaying movement, tools/class, resources, damage, terrain or
grenade actions. A following fresh contiguous command executes normally.
Strict schema, authenticated owner, epoch/generation, sequence/tick order,
32-record capacity, future-8 and six-tick control lease remain enforced; older
than 120 ticks still rejects. PLAYER_REQUEST retains strict late-15/future-8
admission, without stale retirement. This intentionally changes the previous
receive-late-15 policy, not the simulation timestep or shot-history window.
Background-tab survival and arbitrary stalls are not promised.

Trusted `reset_match(new_writable_map,profile="",mode="")` replaces epoch/simulation, preserving connected sparse actor IDs, names, roles and team/class preferences while clearing old authority/history/stream state. Disconnected grace identities invalidate and credentials rotate. Early capability-free MATCH_PREPARING17 clears client map/prediction/interpolation/effects and pauses input before hashing or queued admission; the later WELCOME must match that identity. Every owner repeats the map/state barrier before play. Old senders/bindings revoke immediately; idle old bulk sockets remain until client closure, owner disconnect or bounded expiry. Queued reset owners have a separate capacity-derived64-minute cap and FIFO priority; active transfers keep240seconds from admission. One-use old in-flight bulk digests grant only idle retired sockets within their original15seconds, without map access. Network maps support native physical water1/wade2 and reject other/nonfinite levels atomically. See [runtime-epoch.md](../runtime-epoch.md) and [match-preparation.md](../match-preparation.md).

Legacy Ace of Spades ENet0.75/0.76 servers cannot connect to this new protocol. The game retains those weapon balance profiles; that is distinct from network compatibility. Old-server interoperability is additional future scope, not a claimed feature of this port.

GitHub Pages hosts the exported client only. Public multiplayer requires a native host and valid TLS domain. Repository creation and Pages publication are authorized; provider/account/payment changes require deployment inputs. The server packaging/configuration can be prepared independently.

Earlier native contract evidence includes SimulationCodec2316/0, EventsCodec280/0, PlayerRules144/0, source motion128/0, prediction592/0, Match208/0, firearm rewind441/0 and HitHistory269/0. Runtime103/0 and Replica138/0 used real game/map sockets; NetworkSession501/0 and controller508/0 verified the presentation/authority boundary. The inherited Main scene passed27/0 for map adoption, identity, remote/objective views, an owned shot, chat, cheat denial and disconnect/resume with exact preference restoration. Runtime epoch722/0 covered live/joining reset, baseline/deltas, credentials, stale commands and retired sockets.

The current clock passed69/0 and controller510/0. RTT-accounted native scheduler
47/0 recorded130 callbacks,339 sent inputs plus21 deliberate waits, zero dropped
steps, wire lead1..7, peak pending8 and6.618s wall time. Runtime223/0 with actual
sockets verifies stale input with all seven buttons set (`buttons=127`), movement,
grenade-tool/shotgun-class intent advances its ACK without resource/tool/class,
motion/hit/terrain/grenade effects; fresh sequence3 then executes. Before this
retirement amendment, both RTT-reserved Web receivers ACKed73/73 baseline chunks
(not73 test assertions), with ordinary wire lag-2..2 before scene-entry late-16 rejection:
`.cache/previews/browser-clock-rtt-stall-failure.log`. That run does not accept
authority-4 browser recovery.

A later authority-4 dirty diagnostic Web PCK
`4581f1740b767e459158b29a2c15b42ed12a5f413374eeaac7bea8346600241b`
provided partial foreground proof: both clients rendered/played CTF, cross-client
chat and block palette worked, blue→spectator→shotgun→blue respawn returned
100HP/6/48. Explicit disconnect/reconnect preserved actor1 and fresh map snapshot ID3;
73/73 chunks were ACKed and UI Connected→Enter restored shotgun6/48/100HP.
Approximately three minutes of gameplay ended with admissions2/resumes1,
expected closed1, stale_inputs4 and zero input rejection/map resync/timeout/
backpressure. Observed10–11FPS with two engines is not capacity acceptance.
Browser logs had only IAB pointer-lock WrongDocumentError, no engine/other errors;
both clients/server stopped. `.cache/previews/browser-network-retirement.jpg`
records the scene. Details remain in client-schedule.md; this accepts no frozen
release/Pages publication, public WSS/TLS, Docker/Linux execution, WAN/capacity,
background-tab survival or completion of iteration2.
