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

Frozen gate/export, ordinary browser interactions and public hashes are pending.
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
