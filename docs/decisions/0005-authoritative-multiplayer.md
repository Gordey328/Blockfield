# 0005 — Shared fixed-step authority and browser WebSocket protocol

Accepted 2026-10-10 within the user's approved replacement-networking scope.

The browser and native dedicated server use the pinned Godot4.7.2 GDScript runtime, a 60Hz shared MatchSimulation and an explicit bounded binary protocol. Native WebSocketPeer listeners run behind TLS termination; the browser uses WSS. Separate `/play` and `/map` sockets keep bulk bytes off the gameplay socket's queue. Both still use ordered TCP and share network congestion; this decision does not assert UDP-like latency.

Stable actor IDs, match epochs and spawn generations are independent of socket connection IDs. Clients submit movement/buttons/tool/class intentions. The server owns hit tests, resources, damage, objective outcomes and map edits. Source motion/hit/weapon equations remain shared; friendly fire, same-tick shot ordering, scores, respawn and objective behavior are explicitly authored policies documented in match-simulation.md. Initial shots query current-tick actors and terrain; rewind/lag compensation is unfinished.

Guest sessions have rotating32-byte resume capabilities, SHA256 digests retained by the registry, a30-second disconnected identity grace and one-time15-second bulk capabilities. The server renews the bulk capability after baseline preparation before delivering WELCOME. These are resumable guest ownership, not account authentication. Tokens are exchanged inside WSS, never included in logs/client build configuration. Crypto uses Godot's secure random bytes and constant-time digest comparison. [Godot Crypto API](https://docs.godotengine.org/en/4.7/classes/class_crypto.html)

A client cannot submit gameplay before verifying the map's baseline, ordered deltas and END barrier and returning matching MAP_READY. At most two joins prepare maps concurrently. Hash/decode work is explicitly budgeted between fixed steps. Any gap, overflow, inconsistent before color or stale identity requires a fresh baseline. Count-bounded work does not guarantee a millisecond bound; measured large copy/transaction pauses remain acceptance gaps.

Legacy Ace of Spades ENet0.75/0.76 servers cannot connect to this new protocol. The game retains those weapon balance profiles; that is distinct from network compatibility. Old-server interoperability is additional future scope, not a claimed feature of this port.

GitHub Pages hosts the exported client only. Public multiplayer requires a native host and valid TLS domain. Repository creation and Pages publication are authorized; provider/account/payment changes require deployment inputs. The server packaging/configuration can be prepared independently.

Current evidence: protocol1591, actual transport602, shared motion128, PlayerRules144, Data110/adoption25, grenade30/objectives27, MatchSimulation204, prediction592, guest registry70 and input queue58 checks; server runtime103 checks exercise two native clients, map barriers, owned shooting/chat, lease, reconnect and malicious sequence rejection. Full state/event wire schemas, rendered client integration, browser WSS, map-reset/latency/capacity tests and public deployment remain incomplete. This ADR documents the accepted design and actual partial implementation, not completion of iteration2.
