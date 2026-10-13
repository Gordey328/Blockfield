# Full arsenal / wheel evidence — A05

User2026-10-13; [ADR0037](decisions/0037-full-arsenal-wheel.md). Managed branch
codex/full-arsenal-wheel starts at integrated dev351bccd98614db7b903f621e5c6af846aa740ff7.
The dirty primary checkout and completed A04/Rush are preserved. This is an
authored option, not acceptance of the entire port or a physical phone.

Godot4.7.2.stable.official.ed1daf0bf; upstream OpenSpades
dcf449c845d509bbde9d79239b32d201c1389961. Compatibility Web uses reduced
single-thread templatea1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922,
same engine sourceed1daf0bf001b61586d9930840f2f1394092c079.

## Behavior

Home→Arsenal→Все20 grants all ten weapons, six bombs and four supports in
Lab/Survival/Rush; four slots stay favourite shortcuts. Wheel selects X01…X20
and current original-class backup, wraps both ways and respects the existing
direction/disabled preference. Selection does not deploy, refill or change the
three-class source enum. It cancels held charge/vacuum and touch confirmation.
Menus keep their GUI scrolling. Focus/pause/loading/cards/death gate gameplay
selection. Lab changes apply immediately; Survival/Rush save the next attempt,
which Replay adopts. Full rules hashes preserve legacy four-slot and source
records. Home Classic clears the flag; wheel source retains enabled full mode.

## Native working gate

Coordinator alone holds the engine lease. All specialists return source leases.
No overlapping edits or parallel Godot process is used. Command from worktree:

```powershell
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 tools/build.py --suite arsenal-panel --suite arsenal-runtime --suite arsenal-records --suite full-arsenal-input --suite arsenal-scene --suite arsenal-lab --suite source-input --suite game-shell --suite rush-scene --suite offline-tdm-scene --suite mobile-controls --suite survival-scene
```

Import/parser and runtime smoke pass;12 selected fixtures all pass, zero failures:
runtime283, records88, Panel423, actual Rush arsenal scene169, Lab50,
full-inventory actual Main/Viewport input103, source-input34, game-shell436,
Rush-scene66, TDM-scene68, mobile-controls10059, survival-scene36.
Log `.cache/logs/full-arsenal-working.log`.

The full input fixture traverses everyID+source,21-step wrap, reverse/negative/0,
touchHUD on, no application/preferences signal recursion, partial gauss and
vacuum cancellation, actual Paperclip ammo8→7 and one-off Sun1→0 across full
cycles, pause/catalog/focus/readiness/death gates and full-off original tool
wheel. Actual Rush fixture edits all four favourites then full flag, rejects
live promotion, adopts on real Replay, admits everyX, switches outside favourites,
blocks under real3-kill pending choice and writes only its distinct full bucket.
Panel fixture uses real touch header toggles and six RU/EN layouts568×320,
844×390 and390×844. Records fixture retains exact old golden hashes and saved
old/full/map/class records. Runtime fixture verifies finite admission and toggles.

Frozen gate/export, ordinary Web and public hashes/input pass as recorded below.
No world destruction, authority timing, shared pools or AI mechanism is modified;
the completed A04 measurements remain separately identified in arsenal-evidence.md.

## Retained failed freeze

Frozen c58817af588c48f4b8465a770149ceac08b68434 passed import and all selected
behavioral assertions, including full input103/0, but the strict builder rejected
its shutdown ERROR:2resources/8ObjectDB. Export did not run and this freeze is
not a release. Verbose reproduction with its exact private user directory
identifies only original SMG RaiseLocal.ogg and three Ogg playbacks, with no
authority/scene coroutine leak. The previous working user settings did not show
this cleanup diagnostic. The new input fixture must stop audio before freeing
Main and allow the existing lab's80ms audio-thread drain before quit; production
runtime is unchanged. Logs: `.cache/logs/full-arsenal-frozen-c58817a.log` and
`.cache/release-c58817af588c/.cache/logs/full-input-private-verbose.log`.

Repair is fixture-only: explicit Main.stop_audio before deletion, then the existing
80ms mixer drain and two frames before quit. Same private directory / verbose
reproduction passes103/0 with no leak/resource diagnostic. Its log is
`.cache/release-c58817af588c/.cache/logs/full-input-private-repaired.log`.

## Frozen ordinary Web gate

fd4cfef58f2c9b858d20ff9cd3276007d9b9190d is clean and passes parser/import,
runtime smoke, all13 selected fixtures and the ordinary Compatibility Web export.
Counts are the working gate's twelve plus game-launch46/0. New full-input103 has
no shutdown diagnostic. The13-selection command is:

```powershell
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 tools/release_checkpoint.py --revision fd4cfef58f2c9b858d20ff9cd3276007d9b9190d --import-cache game/.godot --suite arsenal-panel --suite arsenal-runtime --suite arsenal-records --suite full-arsenal-input --suite arsenal-scene --suite arsenal-lab --suite source-input --suite game-shell --suite game-launch --suite rush-scene --suite offline-tdm-scene --suite mobile-controls --suite survival-scene
```

Log `.cache/logs/full-arsenal-frozen-fd4cfef.log`; plain canonical30 files are in
`.cache/release-fd4cfef58f2c/build/web`. Runtime is byte-identical to c58817a;
only the new fixture cleanup and retained diagnostics change in this freeze.

Ordinary localhost8127 Web1280×720: Home All20 off→on, all checkmarks; training
starts saved SMG with full mode. Real browser wheel steps through X01–X20,
source21/21 and forward1/21/reverse21/21 wraps while the touch HUD is enabled.
Every item's name, model/action, position and finite starting resources are
visible; no wheel step applies an item. Source remains SMG30/120. Real catalogue
and pause-menu scrolling retain UI events; returning stays on source21/21.
Lab's original unlimited option is explicitly switched off, then actual Paperclip
Fire gives8→7 and a full21-item roundtrip retains7. No hidden engine hooks are used.

The ignored local DOM TouchEvent adapter reloads the same ordinary engine/PCK
and confirms the saved full flag;568×320 and390×844 touch toggles off→on work,
all buttons stay within the existing header with cards visible. Settled844×390
also fits. CSS polling settles after resize; an initial scaled frame is not used
as the final layout. Synthetic touch is not physical-phone acceptance. The local
helper HTML/JS are excluded from the canonical30/publication.

Actual portrait Rush finish/replay retains full HUD1/21 and finite starting
stocks; returning Home keeps All20 on. Manual inspection remained idle long
enough for two real23-second defeats, score115, so this does not accept a
full-duration manual victory or a live Web wheel/card milestone. The native
169-check actual Rush fixture covers full wheel/real3-kill choice/pause/Replay.
An initial Escape during loading returned Home as the ordinary cancel action;
it was not counted as a live gameplay pause. Home Classic clears the full flag
and returns; reopening shows Off, then touch On saves full mode again.

## Integration and public acceptance

Reviewed fd4cfef is fast-forwarded into dev after an ancestor check;
[attached PR6](https://github.com/Gordey328/Blockfield/pull/6) reports merged/closed
at this SHA. Final evidence/docs leave game/tools/tests byte-identical. Publication:

```powershell
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 tools/publish_pages_variant.py --folder .cache/release-fd4cfef58f2c/build/web --slug arsenal --update-existing --seed-repo .cache/pages-variant-arsenal-1791869413761317700
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 .cache/verify_arsenal_public.py --folder .cache/release-fd4cfef58f2c/build/web --url https://gordey328.github.io/Blockfield/arsenal/ --output .cache/previews/full-arsenal/public-files-fd4cfef.json
```

New publisher explicit update mode requires the same regular canonical file set,
rejects private helpers/symlinks, hashes each copy and forbids another-path diff.
Its Python syntax check passes. Bundle8f66709ea5d803571cabf91ef501dde2c91478ac
changes only arsenal/build-info.json, index.html and index.pck; root/rush/other
paths remain identical. Pages latest status built/error.message=null. All30 public
HTTP200 files/58,260,431bytes match each frozen SHA256; raw comparison JSON and
publication log `.cache/logs/full-arsenal-publication.log` are retained.

[Actual public URL](https://gordey328.github.io/Blockfield/arsenal/?v=fd4cfef):
Home new button Off→On, all checkmarks; saved SMG training starts full1/21;
wheel down1→source21→jet20, then up20→source21→1→brick2 with correct models,
stocks and original SMG30/120. Source/wheel dispatch works with visible touch HUD.
Actual public bank and All20-on in-game catalogue are observed; console errors
list is empty. Public screenshots use the game's ordinary0 PNG export. Initial
waitForEvent/download attempt timed out; documented locator.downloadMedia
retrieved the already-rendered PNG without a game-state hook. Inspected PNG is
`.cache/previews/full-arsenal/public-wheel.png` (1920×1080, wheel2/21/brick4/20).

All specialist leases are returned. Owned local HTTP8127/PID49092 is stopped
after its exact command-line check; the public game does not depend on it.
Browser viewport override is reset, public catalogue is left on/paused and its
tab is marked deliverable. Completed A04 and its limitations are retained;
zombie-rush remains paused and no new automation is created. A05 is VERIFIED.
