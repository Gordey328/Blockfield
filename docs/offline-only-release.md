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

## Initial verification

Initial isolated parser/import passes (`offline-import.log`), with seeded unchanged
asset imports only. A normal Compatibility GPU run of
`tools/render_menu_previews.gd -- --only=dust2` passes8recorded files/0failures;
the actual640×360 Dust2 capture is visually inspected. No new AI raster assets.
Tracked diff whitespace checks pass. Specialist static dependency/Python/audit
checks pass; current profile matches56audited flag records. Historical audit bytes
are unchanged. No complete-port, physical-phone or performance claim follows.

Next gate: frozen parser/import and all registered offline behavior, exported Web
interaction (Home/setup/selected weapon, five bots, training maps, input/settings)
and publication with actual public hashes and interaction. Final results and runtime/source/bundle IDs are recorded below.

## Frozen gate and local browser checks

Frozen source6605204017b56abd49780c21786714a84c00a431 passes parser/import,
all78 registered Godot fixtures, ordinary runtime smoke and Web export. All
registered paths exist, with no skipped missing suites and zero rejected engine
diagnostics. Three existing effects GPU checks explicitly skip in the headless
dummy renderer; their rendering contract is not inferred from this gate.
Private fixture settings are removed from the restored exported project; archived
production project.godot bytes match source exactly.

```powershell
& C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe -X utf8 tools/release_checkpoint.py --revision 6605204017b56abd49780c21786714a84c00a431 --import-cache game/.godot
```

Key changed coverage: shell434/0, real launch46/0 (including Dust2), TDM scene68/0
(including actual omitted-tail replacement/old-hit overflow), TDM81/0, AI4440/0,
mobile controls10059/0, mobile look223/0, aim assist79/0, source input34/0,
UI282/0, combat680/0, retained grenade30/0, player rules141/0, objectives27/0,
match234/0, reset106/0, actor presentation34/0. The local source ray/weapon/model/
terrain/audio equivalence fixtures remain part of the complete78-run gate.

Ordinary local exported Web at1280×720 shows Home without Multiplayer, selected
shotgun Crossroads with all five bots, moving actors/score/death/respawn, forward
movement and actual shotgun6to5. Pause/Home return work. Training lists lab, Title,
Mirage and Dust2. At375×812, settled Dust2/setup/equipment fills the portrait shell
and retains shotgun; gameplay retains the pre-existing16:9 aspect after leaving
shell. Dust2 loads from the catalog, walks and shows firearm terrain damage
(with the lab unlimited-ammo toggle on). Its legacy menu has five tabs and no
network tab. Mouse capture reports the existing Chromium UnknownError and uses
the unchanged drag-look fallback; no GDScript/Parse errors occurred. This is not
a physical-phone/performance or full-port acceptance. Captures are retained under
.cache/previews/offline-only-browser, with scene import/bake/gate logs in .cache.

Source6605204 is pushed on codex/offline-only and fast-forwarded into origin/dev
from dee5603; remote SHA verification confirms both. No shared dirty checkout was
switched or reset. A private Pages checkout based on8804b56 receives the exact
frozen26-file export (all copied hashes match); only root build-info.json,
index.html and index.pck change. Sibling builds and map/engine artifacts stay
byte-identical. Publication d0c06b5becd38f9ec58e56f9ada5075a989f9aca is queued,
with the latest API report building/no error; actual public checks follow.

```powershell
& C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe -X utf8 tools/publish_pages.py --directory .cache/offline-pages
```

Pre-existing CI limit: pages.yml does not supply the ignored hash-pinned reduced
Web template on a clean runner. This release uses the already accepted local
artifact, with parser/behavior/export gates; no CI success is inferred.

## Public acceptance and cleanup

Pages bundle d0c06b5becd38f9ec58e56f9ada5075a989f9aca is built with no API error.
All26 public export files, including metadata/HTML/JS/WASM/PCK/maps/licenses,
independently match SHA256; .cache/public-offline-hashes.json retains the report.
This confirms clean source6605204 and both original compiled map hashes.

Actual public Home has no Multiplayer. Crossroads launches with saved shotgun
and five bots; ordinary movement, real score/death/respawn, touch Fire6to5 and
pause/Home return are checked. Public Mirage launches from the catalog and walks.
Reloaded setup preserves shotgun/Crossroads. Pre-existing public Mobile controls
On remains unchanged; the filtered public warning/error log is empty. Local
Chromium capture errors remain only on the earlier localhost tab history, with
the established fallback preserved. No new public runtime errors are observed.

Normal1280×720/375×812 checks are desktop browser checks; they do not establish
phone hardware comfort/FPS or full OpenSpades parity. Existing gameplay16:9 aspect,
original models/assets, local authority and accepted visual adaptations remain.
No networking path is deferred or hidden: active scope is offline only.

Heartbeat ui is disabled (PAUSED), tool update/saved configuration verified.
All specialists/engine leases are closed. Temporary HTTP8074/helper and clean
private Pages checkout are removed; browser viewport override is reset, public
deliverable retained. Screenshots remain in .cache/previews/offline-only-browser.
Later evidence commits change documentation only; production game/tests/tools
remain exactly the checked6605204 tree. Updated dev is the base for further work.

Requested removal/integration/publication and verification are complete.
Public URL:https://gordey328.github.io/Blockfield/?v=6605204 .
