# Offline-only removal evidence

The user withdraws multiplayer after the completed first UI delivery. This task
combines UI branch53f9670 (runtime912adec) and the unchanged published Dust2 map
commit021122b, then removes networking under [ADR0031](decisions/0031-offline-only-game.md).
The original shared checkout and its concurrent zombie/Steam/optimization drafts
are preserved. Root uses the attached `offline-only/Blockfield` worktree and
`codex/offline-only` branch.

Godot:4.7.2.stable.official.ed1daf0bf. Upstream OpenSpades:
dcf449c845d509bbde9d79239b32d201c1389961. Compatibility/single-thread Web remains.
The accepted reduced engine binary stays SHA256
a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922;
it still contains generic WebSocket engine support, with no game consumers.
The future engine profile disables that module; no unverified replacement binary
is shipped. Historical module audit is retained separately.

## Ownership and implementation

Contracts agreed before edits; three specialists return all source/engine leases.
Controller owns PlayerController/LocalSession/scoreboard and two mobile fixtures;
simulation owns local rules/TDM/bot director, current-hit fixture and five pure
simulation suites moved from tests/network; tooling owns deleted transport/server/
deployment/tools/network tests, mixed fixture adaptations and template profile.
Root owns Main/HUD/Entry/GameShell, catalog, project/export/build registration,
game UI fixtures, scope/architecture/docs and serial acceptance/release.

There are no network/server routes, socket consumers, runtime network classes,
server export preset or server build/package/latency helpers. Fixed60Hz local
actor simulation, source tools/weapon profiles, CTF/TC lab equivalents, terrain
receipts/reset and five-bot TDM remain. Phone fixtures use a recording local TDM
adapter and retain command-once, life/round reset and aim-friction behavior.
Main refreshes the same Data after local receipt overflow, restoring damage tint.
N01–N09 are explicitly retired, with their old ledger preserved as history.

Dust2 is added to the finished training catalog so the combined UI retains every
bundled map. Its package SHA256 stays
d9d8e1f6f7e7d14719242def88c306f3af0dda681c765c3a41222bf91bcaab61.
Original map restrictions/provenance remain in the distributed notice.

## Validation in progress

Initial isolated parser/import passes (`offline-import.log`), with seeded unchanged
asset imports only. A normal Compatibility GPU run of
`tools/render_menu_previews.gd -- --only=dust2` passes8recorded files/0failures;
the actual640×360 Dust2 capture is visually inspected. No new AI raster assets.
Tracked diff whitespace checks pass. Specialist static dependency/Python/audit
checks pass; current profile matches56audited flag records. Historical audit bytes
are unchanged. No complete-port, physical-phone or performance claim follows.

Next gate: frozen parser/import and all registered offline behavior, exported Web
interaction (Home/setup/selected weapon, five bots, training maps, input/settings)
and publication with actual public hashes and interaction. Results and exact
runtime/source/bundle IDs will be added here after completion.
