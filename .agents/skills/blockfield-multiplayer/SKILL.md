---
name: blockfield-multiplayer
description: Implement and verify Blockfield authoritative multiplayer, browser WSS transport, shared simulation, prediction and map synchronization. Use for iteration-2 networking and multiplayer acceptance.
---

Read `docs/status.md`, `docs/iterations.md`, affected N01–N09 rows in `docs/parity.md`, and `docs/multiplayer-plan.md`. The plan is a proposed design, not implementation evidence or hosting authorization. Accepted protocol/transport/rules decisions belong in `docs/decisions/`; actual byte schemas and measured limits belong in network documentation.

Keep the offline lab available without a server. Share rules between local authority, headless server and client prediction; separate voxel data/query rules from renderer, HUD, audio and model nodes. Preserve source motion/hit-volume/weapon goldens when extracting controller code. Upstream OpenSpades is a client: label newly authored server policies rather than inventing original server behavior.

Bind commands to their authenticated connection owner. Stable actor IDs, spawn generations and match epochs are distinct from transport peer IDs; remove local-player0 assumptions. Clients send bounded input/actions, never authoritative hits, resources, positions, kills or objective outcomes. Server validates tools, reach, cadence, ammo, reload/cook and world changes.

Use fixed-step simulation and bounded command/history queues. Reconciliation replays pure rules without repeated sounds, damage, projectiles or feed events. Deduplicate predicted/confirmed effects by action/event ID. Query source hit volumes and voxel occlusion at the same permitted rewind time; missing history needs an explicit policy.

A joining client applies an immutable baseline plus ordered map transactions before the matching state barrier and spawn. Reset changes the epoch; death/respawn changes actor generation. Bound transfer/decompression/journal buffers and resync gaps instead of guessing edits. Server owns collapse decisions; client falling clusters are visual.

Pages hosts the client; an authoritative process needs a separate native host. Browser WSS requires valid hostname/TLS and polling; custom handshake headers/control pings are unavailable in Web exports. WebSocket uses ordered TCP: unreliable RPC labels cannot remove head-of-line blocking. Verify current official Godot docs when touching transport/export APIs. Keep secrets out of client exports and logs.

Agree file ownership before team edits. Run pure rules/protocol tests independently; run actual-scene suites only on a coherent handoff, preserving preference restoration. Exercise two real clients, mid-round map joins, reconnect/reset, malicious/late/duplicate actions and real latency/TCP stalls before marking N rows VERIFIED. Headless passes do not prove exported browser behavior. Deployment/provider/account setup is a separate action within the user's authorized scope, not implied by creating this skill.
