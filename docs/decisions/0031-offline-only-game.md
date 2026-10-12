# ADR0031 — Offline-only game

Status: accepted,2026-10-12.

The user requests removal of all multiplayer code after the first game UI delivery:
multiplayer is no longer needed. This overrides iteration2 and ADR0005/0006's
active networking scope. The UI implementation completed before deletion began.

Remove dedicated server/transport/protocol, replica, prediction/reconciliation,
remote interpolation, lag-compensation history/rewind, reconnect, discovery,
server configuration/export/deployment and related tests/tools/menu routes.
There is no disabled alternate network scene or hidden server command route.

Keep the offline lab and one-human/five-bot3×3. Local PlayerRules/GrenadeRules/
MatchObjectives/MatchSimulation remain at60Hz; shooting uses current actor/terrain
state. Keep source weapon profiles0.75/0.76 as gameplay tuning, local actor IDs,
life generations, round epochs, terrain transactions and reset bytes. These
contracts prevent duplicate local actions or stale life effects and are useful
without networking. Presentation samples the committed local actor state.

Bounded local terrain receipt overflow requires a local World refresh from the
same authoritative Data, restoring persistent damaged-cell tint; no remote ACK
or duplicated map mutation is needed. Event queues remain bounded and consumed.

Preserve the finished Home/map/loadout launch and original phone/desktop input,
Mirage and newly combined Dust2. No map is promoted to bot-navigation acceptance.
Historical network documents, upstream reference source and old build identities
remain explicitly historical. N01–N09 are withdrawn from the active parity gate,
not marked verified or silently deferred. Full offline-port acceptance stays open.

The reduced engine profile disables WebSocket for future template builds. The
previously accepted generic engine binary remains hash-pinned until rebuilt;
there are no game WebSocket consumers. General engine TLS/crypto remains enabled.

Verification requires parser/import, local simulation/tool/reset/bot/mobile
behavior and actual browser launch/input/map/settings checks. Export alone does
not verify the change. [Release evidence](../offline-only-release.md) records the
checked source, commands, results, public artifact identity and remaining limits.
