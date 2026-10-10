# 0006 — Explicit endpoints and local server favorites

2026-10-10, within the approved replacement multiplayer stack.

The Godot client joins the new authoritative server through separate game and map WebSocket endpoints. The connection menu provides named local favorites, filtering and sorting. It starts with no public hosts configured. Selecting a favorite fills the connection form; connecting is a separate user action. Favorites contain public URLs, names and spectator preference only, never resume capabilities or credentials.

The original Ace of Spades master-server list cannot discover these servers because it describes the incompatible legacy protocol. No central registration service is operated for this project. Manual endpoint entry and a local favorite list replace that discovery service; this preserves repeatable server selection without claiming that legacy servers can be joined. A future public catalog can extend the same endpoint records when actual compatible hosts exist.

Browser clients served over HTTPS require WSS. Native/local HTTP testing can use WS. Pages publishes the browser client; the prepared Docker authority and Caddy proxy require a separately selected host and DNS name. This decision neither selects a provider nor creates a public multiplayer service. See server-deployment.md and ADR0005.
