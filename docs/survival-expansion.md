# Survival expansion — 2026-10-12

User requests faster Start survival, independent player/block damage, a grenadier
and small real downloaded Teardown maps based on known games. The attached
zombie-survival worktree starts from460714f7aed30ea0936a9e0567e946314cf6fa41; the
shared dirty primary checkout is preserved. [ADR0034](decisions/0034-survival-grenadiers-and-levels.md)
defines contracts. Godot4.7.2.stable.official.ed1daf0bf/Compatibility and OpenSpades
dcf449c845d509bbde9d79239b32d201c1389961 remain pinned. No networking or complete
port acceptance. All three specialist source/serial engine leases are returned.

## Implementation and source maps

Home warms only a packed resource and bounded model resources, without creating a
hidden simulation. Main stages survival setup, slices228smoke frames, binds the
selected first-person equipment before live input and creates HDR targets only
when enabled. Selected weapon enters the initial registry once. Preparation waits
for existing bounded terrain/minimap/water jobs. Exit drains pending scene loading;
native loader behavior does not imply a Web worker in the single-threaded export.

Setup exposes zombie_damage and zombie_block_damage1..100/default20/40. Both are
validated, saved and shown in pause/results. Bite/grenade peak use player damage;
strike/exposed grenade cells use persistent block damage independently.

Every fourth admitted life is a visible orange/olive grenadier, with the same
six-part/eight-node pooled rig.3throws per life,60tick warning,480tick cooldown,
6..24range and at most4hostile projectiles. Trusted authority revalidates visibility,
range/life/cooldown/stock, then spawns ordinary bouncing2.5second-fuse ordnance.
Configured blasts use falloff within8 and up to96exposed cells within3, with one
canonical removal/collapse transaction; protected ground and human grenade rules
remain. Cleanup waits ordnance; a late lethal explosion defeats the player.

New trusted survival levels: Minecraft Chunk92×30×48 and MIRA HQ66×20×88. Both
are actual downloaded XML/VOX adaptations, not generated lookalikes. The house/
farm/tree and cafeteria/balcony/rooms retain source geometry; explicit crops,
removed roofs/subsurface spaces and added foundation provide one safe floor.
Eight supported connected distant sectors each; new selectors/level state/retry
retain each map. Original imported Dust2/Mirage navigation is still unaccepted.
[Map sources, attribution, hashes and conversion](survival-maps.md) records the
authors/public download pages and absence of an identified separate reuse license.
Raw archives/scripts stay ignored/unexecuted; assets are not relabeled MIT.

## Mutable checks

All results below are separate from the frozen release gate. Logs are in
ignored `.cache/logs/` of this managed worktree.

| Check | Pass | Evidence |
| --- | --- | --- |
| Authority parser/import | yes | grenadier-authority-import-1.log |
| Settings / session / real zombie ordnance | 37/0;156/0;66/0 | grenadier-authority-{settings-1,session-1,projectiles-1}.log |
| Shared simulation / original human grenades / TDM | 244/0;30/0;81/0 | grenadier-authority-{match-1,human-grenades-1,tdm-1}.log |
| AI / pooled view / parser | 661/0;94/0;pass | zombie-grenadier-{ai-first,view-first,import}.log |
| Actual launch / survival scene / startup | 46/0;36/0;16/0 | survival-expansion-final-launch.log |
| Real level timelines/full horde / desktop options | 34/0;11/0 | survival-expansion-full-horde.log; survival-expansion-lazy-hdr-options.log |
| Lazy HDR enable/disable and launch | 7/0 | survival-expansion-lazy-hdr-options.log |
| Effects / post effects / HDR | 20928/0;86/0;47/0 | survival-expansion-root-gate.log |
| Raw-source conversion/reproduction | 10/0 | survival-map-data.log |

The three MultiMesh GPU assertions are skipped by the headless dummy renderer in
the effects fixture; ordinary local desktop Web rendering is checked below. Python10/0
includes byte-identical reconversion of both pinned archives, outside the live
accepted output. New level real timelines admit four lives, move and hurt the
owner, and perform actual throws. The fixture lowers configured damage to1 to
observe the fourth life rather than dying before its windup; this does not change
production default20. Full-horde timelines reach12live and stay within4hostile
projectiles on all three maps, with no route/spawn interruption.

Native full-session CPU samples (not rendered FPS): Crossroads mean3.128ms/max53.550,
Minecraft mean4.517/max130.519, MIRA mean4.963/max95.391 over1500ticks. Long planner/
initial-cache peaks remain; this is not sustained browser or phone performance.
The planner allows one bounded pair per tick and may retry exhausted searches;
Minecraft's earlier four-life run records7exhausted searches without an interrupted
attempt. No arbitrary stacked-map support is inferred.

## Launch measurement and corrections

Same native warm-menu click fixture, previous frozen37297ed2fc4b versus this source:
before2361.510ms click→ready/max process gap1315.656ms/41frames; after samples
632.604–710.817ms, max117.544–148.309ms,63–66frames. Most warm work now occurs while
choosing settings; this is not whole app/download latency or a browser/phone timing.
Frozen final source equipment preparation measures711.913ms/max159.342ms/74frames.
Logs: survival-launch-latency-before.log, survival-launch-latency-after.log,
test-survival-launch-latency.log, survival-latency-clean.log.

Retained failures: the first MIRA timeline killed the owner before a grenadier
throw; controlled damage1 completes the observed lifecycle. A fast smoke exit
initially shut down shaders during loading; Entry now drains its one request and
uses process-step model warming. Native fixed-FPS frames initially left stopped
audio mixer references at immediate test exit; scene/latency fixtures wait80ms
outside the measured interval before exiting. Final gates no longer have shader/
resource errors. Native warm latency still warns about11zero-reference RefCounted
ObjectDB records at exit; verbose survival-launch-leak-detail.log records them,
without active resources. This warning is retained, not labelled a clean warning
list or proven growing live-game memory. Failed gate logs are preserved in
survival-expansion-{root-gate,levels-options,integration-final,warm-gate}.log and
survival-levels-initial.log.

```powershell
$python_runtime = 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $python_runtime -X utf8 tools/test_survival_maps.py
& $python_runtime -X utf8 tools/build.py --suite zombie-grenades --suite survival-session --suite zombie-ai --suite zombie-view --suite survival-levels --suite survival-options-desktop --suite survival-launch-latency --suite survival-scene --suite startup-work --suite game-launch --suite effects --suite post-effects --suite hdr-exposure
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path .cache/release-37297ed2fc4b/game --fixed-fps 60 --script 'C:/Users/Gordey/.codex/worktrees/zombie-survival/Blockfield/tests/integration/test_survival_launch_latency.gd' -- --baseline
```

## Frozen checks and local desktop acceptance

Clean runtime **1630770bf574280d852abd52204998043a324611**, frozen into
`.cache/release-1630770bf574`, passes parser/import,25 selected native fixtures,
runtime smoke and ordinary Web export. Log: survival-expansion-frozen.log.
Counts: world30, lab session166, lab integration119, voxel adapter25, world
preparation53, TDM81, TDM scene68, game launch46, survival settings37/session156,
AI661/view94, survival scene36, startup16, launch latency7, real levels/full horde34,
desktop options11, zombie grenades66, player rules141, shared match244, original
human grenades30, effects20928, post effects86, HDR47, BFM93; all0failures.
Effects retain3headless-dummy GPU skips. The original full85fixture acceptance is
historical; this is not a repeat of every fixture or any mobile UI fixture.

Additional native Compatibility GPU capture of the frozen view passes95/0 on
Intel UHD/OpenGL3.3; orange torso/backpack, overhand grenade warning, walker and
corpse visibly render. Evidence: survival-expansion-grenadier-gpu.log and
`.cache/previews/survival-expansion/grenadier/walker-walk-grenadier-windup-corpse.png`.
This controlled capture proves the rig, not a live Web projectile observation.

Normal local desktop export at `http://127.0.0.1:8100/?v=1630770bf574` shows all
three map cards before the wave controls. Minecraft selects player5/block65;
individual key entry confirms65, setup persists after return Home, and the result
shows5/65. Both imported levels show an early equipment preparation overlay and
then real converted geometry/minimap. Keyboard movement, drag-look fallback,
rifle firing/ammunition loss and reload work. Minecraft admits6lives and deals
real lethal damage at00:39. MIRA with damage1/1 receives real pursuit/hurt, reaches
12live and defeats the stationary/limited-moving owner; pause freezes the clock,
retry resets preparation and return Home works. There is no live Web projectile
visual claim; trusted projectile behavior is verified by the66/0fixture, real
level timelines and AI windup checks. Console records4Chromium UnknownErrors
with unavailable pointer capture/functional drag fallback, no GDScript errors.
Screenshots: `.cache/previews/survival-expansion/setup-damage.jpg`, `mira-game.jpg`
(live view), `minecraft-game.jpg` (despite its filename, the defeat/results panel).
Console: survival-expansion-local-console.json. Own HTTP helper/tab stopped/closed.
User excludes deployed-browser and mobile-UI repeats; ui-2 remains PAUSED.

```powershell
& $python_runtime -X utf8 tools/release_checkpoint.py --revision 1630770bf574280d852abd52204998043a324611 --import-cache game/.godot --suite world --suite session --suite integration --suite voxel-adapter --suite world-preparation --suite offline-tdm --suite offline-tdm-scene --suite game-launch --suite survival-settings --suite survival-session --suite zombie-ai --suite zombie-view --suite survival-scene --suite startup-work --suite survival-launch-latency --suite survival-levels --suite survival-options-desktop --suite zombie-grenades --suite player-rules --suite match-simulation --suite shared-grenade --suite effects --suite post-effects --suite hdr-exposure --suite blockfield-map
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path .cache/release-1630770bf574/game --rendering-method gl_compatibility --rendering-driver opengl3 --script ../tests/presentation/test_zombie_view.gd -- --gpu --output=C:/Users/Gordey/.codex/worktrees/zombie-survival/Blockfield/.cache/previews/survival-expansion/grenadier
& $python_runtime -X utf8 tools/serve.py --directory build/web --port 8100
```

## Publication

The reduced template SHA256 remains
`a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`.
Frozen source is pushed to codex/zombie-survival and fast-forwarded into dev.
Pages bundle652342c9c16e95b53c34c57290465b9b8c9949a0 reports built/no API error.
All30public file SHA256 values match the frozen clean runtime, including both
new BFM packages and source notices. Reports:
`.cache/survival-expansion-pages-prepared.json`,
`.cache/public-survival-expansion-hashes.json`; publish log:
survival-expansion-pages-publish.log. The private helper
copies only30root files, checks every copied SHA and preserves optimized/game-ui/
reduced sibling inventories;4new BFM/provenance files are now public. It does not
run public-browser gameplay.

```powershell
& $python_runtime -X utf8 .cache/survival-expansion-release-check.py prepare
git push origin HEAD:codex/zombie-survival HEAD:dev
& $python_runtime -X utf8 tools/publish_pages.py --directory .cache/zombie-pages
& $python_runtime -X utf8 .cache/survival-expansion-release-check.py public
```

URL: https://gordey328.github.io/Blockfield/?v=1630770bf574 . Evidence-only docs
follow the frozen runtime; production game/tests/tools are unchanged afterwards.
